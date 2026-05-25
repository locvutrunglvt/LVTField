import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../data/database/app_database.dart';
import 'package:uuid/uuid.dart';

/// LVT Sync Service - PocketBase cloud synchronization
/// 
/// CHIẾN LƯỢC AN TOÀN DỮ LIỆU:
/// 1. KHÔNG BAO GIỜ XÓA - chỉ đánh dấu soft-delete (is_deleted = 1)
/// 2. MERGE, KHÔNG GHI ĐÈ - remote + local cùng tồn tại
/// 3. VERSION TRACKING - so sánh version trước khi update
/// 4. CONFLICT KEEP BOTH - nếu xung đột, giữ cả 2 phiên bản
/// 5. PULL ADDITIVE ONLY - chỉ thêm, không xóa dữ liệu local
///
/// Author: Lộc Vũ Trung
class SyncService {
  static const String _pbUrl = 'https://lvtfield.lvtcenter.it.com';
  late final PocketBase _pb;

  // Sync state
  bool _isSyncing = false;
  String? _lastError;
  DateTime? _lastSyncTime;
  int _conflicts = 0;

  // User info
  String? get currentUserEmail =>
      _pb.authStore.record?.getStringValue('email');
  String? get currentUserName =>
      _pb.authStore.record?.getStringValue('name');
  String? get currentUserAvatar =>
      _pb.authStore.record?.getStringValue('avatar');
  bool get isAuthenticated => _pb.authStore.isValid;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get conflicts => _conflicts;

  SyncService() {
    _pb = PocketBase(_pbUrl);
  }

  /// Login with email and password (works on all platforms)
  Future<bool> loginWithEmail(String email, String password) async {
    try {
      await _pb.collection('users').authWithPassword(email, password);
      debugPrint('Sync: Email login successful - $currentUserEmail');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync: Email login failed - $e');
      return false;
    }
  }

  /// Login with Google OAuth2 (may not work on all mobile devices)
  Future<bool> loginWithGoogle() async {
    try {
      await _pb.collection('users').authWithOAuth2('google', (url) async {
        // PocketBase SDK opens browser automatically
      });
      debugPrint('Sync: Google login successful - $currentUserEmail');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Sync: Google login failed - $e');
      return false;
    }
  }

  /// Logout and clear auth store
  void logout() {
    _pb.authStore.clear();
    _lastSyncTime = null;
    _lastError = null;
    debugPrint('Sync: Logged out');
  }

  /// Check network connectivity
  Future<bool> _hasNetwork() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// FULL SYNC: Push local → remote, then Pull remote → local
  /// 
  /// Nguyên tắc:
  /// - PUSH: Đẩy data local chưa sync lên server (create/update)
  /// - PULL: Tải data mới từ server về (chỉ THÊM, không xóa local)
  /// - CONFLICT: Giữ CẢ HAI phiên bản, đánh dấu để user xử lý
  /// - KHÔNG BAO GIỜ: delete record ở bất kỳ đâu
  /// ═══════════════════════════════════════════════════════════════════
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Đang đồng bộ...');
    }
    if (!isAuthenticated) {
      return SyncResult(success: false, message: 'Chưa đăng nhập');
    }
    if (!await _hasNetwork()) {
      return SyncResult(
          success: false, message: 'Không có kết nối mạng');
    }

    _isSyncing = true;
    _lastError = null;
    _conflicts = 0;
    int pushed = 0, pulled = 0, skipped = 0;
    final errors = <String>[];

    try {
      final db = await AppDatabase.database;
      final userId = _pb.authStore.record?.id ?? '';

      // ═══════════════════════════════════
      // PHASE 1: PUSH Local → Remote
      // ═══════════════════════════════════

      // 1a. Push projects
      final localProjects = await db.query('projects');
      for (final p in localProjects) {
        try {
          final remoteId = p['remote_id'] as String?;
          final data = {
            'name': p['name'],
            'description': p['description'] ?? '',
            'crs_epsg': int.tryParse(
                    p['crs']?.toString().replaceAll('EPSG:', '') ??
                        '4326') ??
                4326,
            'owner': userId,
            'device_id': p['id'],
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            // Update existing — server already has this project
            try {
              await _pb.collection('projects').update(remoteId, body: data);
              pushed++;
            } catch (e) {
              // If 404 (deleted on server), RE-CREATE instead of losing data
              if (e.toString().contains('404')) {
                debugPrint('Sync: Project deleted on server, re-creating: ${p['name']}');
                final record = await _pb.collection('projects').create(body: data);
                await db.update('projects',
                  {'remote_id': record.id, 'is_synced': 1},
                  where: 'id = ?', whereArgs: [p['id']]);
                pushed++;
              } else {
                rethrow;
              }
            }
          } else {
            // New project — create on server
            final record = await _pb.collection('projects').create(body: data);
            await db.update('projects',
              {'remote_id': record.id, 'is_synced': 1},
              where: 'id = ?', whereArgs: [p['id']]);
            pushed++;
          }
        } catch (e) {
          errors.add('Project ${p['name']}: $e');
          debugPrint('Sync push project error: $e');
        }
      }

      // 1b. Push layers
      final localLayers = await db.query('layers');
      for (final l in localLayers) {
        try {
          final projectRows = await db.query('projects',
            where: 'id = ?', whereArgs: [l['project_id']]);
          final remoteProjectId = projectRows.isNotEmpty
              ? (projectRows.first['remote_id'] as String? ?? '') : '';

          if (remoteProjectId.isEmpty) {
            skipped++;
            continue; // Skip layers whose project hasn't synced yet
          }

          final remoteId = l['remote_id'] as String?;
          final data = {
            'project_id': remoteProjectId,
            'name': l['name'],
            'geometry_type': l['geometry_type'],
            'style_config': l['style_json'] ?? '{}',
            'source_format': '',
            'field_schema': '{}',
            'sort_order': l['z_order'] ?? 0,
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            try {
              await _pb.collection('layers').update(remoteId, body: data);
              pushed++;
            } catch (e) {
              if (e.toString().contains('404')) {
                debugPrint('Sync: Layer deleted on server, re-creating: ${l['name']}');
                final record = await _pb.collection('layers').create(body: data);
                await db.update('layers', {'remote_id': record.id},
                  where: 'id = ?', whereArgs: [l['id']]);
                pushed++;
              } else {
                rethrow;
              }
            }
          } else {
            final record = await _pb.collection('layers').create(body: data);
            await db.update('layers', {'remote_id': record.id},
              where: 'id = ?', whereArgs: [l['id']]);
            pushed++;
          }
        } catch (e) {
          errors.add('Layer ${l['name']}: $e');
          debugPrint('Sync push layer error: $e');
        }
      }

      // 1c. Push features (only modified/unsynced ones)
      final modifiedFeatures = await db.query('features',
        where: 'is_modified = 1 OR is_synced = 0');
      for (final f in modifiedFeatures) {
        try {
          final layerRows = await db.query('layers',
            where: 'id = ?', whereArgs: [f['layer_id']]);
          final remoteLayerId = layerRows.isNotEmpty
              ? (layerRows.first['remote_id'] as String? ?? '') : '';

          if (remoteLayerId.isEmpty) {
            skipped++;
            continue;
          }

          final localVersion = f['version'] as int? ?? 1;
          final remoteId = f['remote_id'] as String?;
          final data = {
            'layer_id': remoteLayerId,
            'coordinates_json': f['coordinates_json'],
            'attributes': f['attributes_json'] ?? '{}',
            'device_id': f['id'],
            'version': localVersion + 1,
            'owner': userId,
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            // ─── CONFLICT CHECK ───
            try {
              final remoteRecord = await _pb.collection('features').getOne(remoteId);
              final remoteVersion = remoteRecord.getIntValue('version', 0);

              if (remoteVersion > localVersion) {
                // Remote is NEWER → KEEP BOTH (don't overwrite remote)
                // Create a new record on server with local data as backup
                debugPrint('Sync: CONFLICT detected for feature ${f['id']} '
                    '(local v$localVersion < remote v$remoteVersion). Keeping both.');
                
                final conflictData = {
                  ...data,
                  'device_id': '${f['id']}_conflict_${DateTime.now().millisecondsSinceEpoch}',
                };
                await _pb.collection('features').create(body: conflictData);
                _conflicts++;
                pushed++;
              } else {
                // Local is same or newer → safe to update
                await _pb.collection('features').update(remoteId, body: data);
                pushed++;
              }
            } catch (e) {
              if (e.toString().contains('404')) {
                // Deleted on server → re-create (never lose local data)
                debugPrint('Sync: Feature deleted on server, re-creating');
                final record = await _pb.collection('features').create(body: data);
                await db.update('features', {
                  'remote_id': record.id,
                  'is_synced': 1,
                  'is_modified': 0,
                  'version': localVersion + 1,
                }, where: 'id = ?', whereArgs: [f['id']]);
                pushed++;
              } else {
                rethrow;
              }
            }
          } else {
            // New feature — create on server
            final record = await _pb.collection('features').create(body: data);
            await db.update('features', {
              'remote_id': record.id,
              'is_synced': 1,
              'is_modified': 0,
              'version': localVersion + 1,
            }, where: 'id = ?', whereArgs: [f['id']]);
            pushed++;
          }
        } catch (e) {
          errors.add('Feature: $e');
          debugPrint('Sync push feature error: $e');
        }
      }

      // ═══════════════════════════════════
      // PHASE 2: PULL Remote → Local
      // CHỈ THÊM MỚI — KHÔNG XÓA LOCAL
      // ═══════════════════════════════════

      // 2a. Pull remote projects
      try {
        final remoteProjects = await _pb.collection('projects').getFullList(
          filter: 'owner = "$userId"',
        );
        for (final rp in remoteProjects) {
          final existing = await db.query('projects',
            where: 'remote_id = ?', whereArgs: [rp.id]);
          
          if (existing.isEmpty) {
            // Check if same device_id exists locally (avoid duplicates)
            final deviceId = rp.getStringValue('device_id');
            final byDevice = deviceId.isNotEmpty
                ? await db.query('projects', where: 'id = ?', whereArgs: [deviceId])
                : <Map<String, dynamic>>[];

            if (byDevice.isNotEmpty) {
              // Already exists locally — just link remote_id
              await db.update('projects',
                {'remote_id': rp.id, 'is_synced': 1},
                where: 'id = ?', whereArgs: [deviceId]);
              debugPrint('Sync: Linked local project to remote: ${rp.getStringValue('name')}');
            } else {
              // Truly new from server — create locally
              final localId = const Uuid().v4();
              await db.insert('projects', {
                'id': localId,
                'name': rp.getStringValue('name'),
                'description': rp.getStringValue('description'),
                'crs': 'EPSG:${rp.getIntValue('crs_epsg', 4326)}',
                'remote_id': rp.id,
                'is_synced': 1,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              });
              pulled++;
              debugPrint('Sync: Pulled new project: ${rp.getStringValue('name')}');
            }
          }
          // NOTE: If project exists locally, we DO NOT overwrite local changes.
          // Local data is the "source of truth" for field-collected data.
        }
      } catch (e) {
        errors.add('Pull projects: $e');
        debugPrint('Sync pull projects error: $e');
      }

      // 2b. Pull remote layers
      try {
        // Get all remote project IDs that are linked locally
        final linkedProjects = await db.query('projects',
          columns: ['remote_id'], where: 'remote_id IS NOT NULL AND remote_id != ""');
        final remoteProjectIds = linkedProjects
            .map((p) => p['remote_id'] as String)
            .toList();

        for (final rpId in remoteProjectIds) {
          final remoteLayers = await _pb.collection('layers').getFullList(
            filter: 'project_id = "$rpId"',
          );

          for (final rl in remoteLayers) {
            final existing = await db.query('layers',
              where: 'remote_id = ?', whereArgs: [rl.id]);

            if (existing.isEmpty) {
              // Find local project_id from remote project_id
              final projectRows = await db.query('projects',
                where: 'remote_id = ?', whereArgs: [rpId]);
              if (projectRows.isEmpty) continue;

              final localProjectId = projectRows.first['id'] as String;
              final localLayerId = const Uuid().v4();

              await db.insert('layers', {
                'id': localLayerId,
                'project_id': localProjectId,
                'name': rl.getStringValue('name'),
                'geometry_type': rl.getStringValue('geometry_type'),
                'style_json': rl.getStringValue('style_config'),
                'z_order': rl.getIntValue('sort_order', 0),
                'is_visible': 1,
                'opacity': 1.0,
                'remote_id': rl.id,
                'created_at': DateTime.now().toIso8601String(),
              });
              pulled++;
              debugPrint('Sync: Pulled new layer: ${rl.getStringValue('name')}');
            }
          }
        }
      } catch (e) {
        errors.add('Pull layers: $e');
        debugPrint('Sync pull layers error: $e');
      }

      // 2c. Pull remote features (ADDITIVE ONLY)
      try {
        final linkedLayers = await db.query('layers',
          columns: ['id', 'remote_id'],
          where: 'remote_id IS NOT NULL AND remote_id != ""');

        for (final ll in linkedLayers) {
          final remoteLayerId = ll['remote_id'] as String;
          final localLayerId = ll['id'] as String;

          final remoteFeatures = await _pb.collection('features').getFullList(
            filter: 'layer_id = "$remoteLayerId"',
          );

          for (final rf in remoteFeatures) {
            // Check if we already have this feature
            final existingByRemote = await db.query('features',
              where: 'remote_id = ?', whereArgs: [rf.id]);

            // Also check by device_id to avoid duplicates
            final deviceId = rf.getStringValue('device_id');
            final existingByDevice = deviceId.isNotEmpty
                ? await db.query('features', where: 'id = ?', whereArgs: [deviceId])
                : <Map<String, dynamic>>[];

            if (existingByRemote.isEmpty && existingByDevice.isEmpty) {
              // Truly new from server (from QGIS or another device)
              final localFeatureId = const Uuid().v4();
              await db.insert('features', {
                'id': localFeatureId,
                'layer_id': localLayerId,
                'coordinates_json': rf.getStringValue('coordinates_json'),
                'attributes_json': rf.getStringValue('attributes'),
                'collected_at': DateTime.now().toIso8601String(),
                'collected_by': 'sync',
                'gps_accuracy': 0,
                'is_modified': 0,
                'is_synced': 1,
                'remote_id': rf.id,
                'version': rf.getIntValue('version', 1),
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              });
              pulled++;
              debugPrint('Sync: Pulled new feature from server');
            } else if (existingByDevice.isNotEmpty && existingByRemote.isEmpty) {
              // Feature exists locally but not linked — just link it
              await db.update('features',
                {'remote_id': rf.id, 'is_synced': 1},
                where: 'id = ?', whereArgs: [deviceId]);
            }
            // NOTE: If feature exists both locally and remotely,
            // we DO NOT overwrite local data. Local is source of truth.
          }
        }
      } catch (e) {
        errors.add('Pull features: $e');
        debugPrint('Sync pull features error: $e');
      }

      _lastSyncTime = DateTime.now();
      _isSyncing = false;

      // Build result message
      final parts = <String>[];
      if (pushed > 0) parts.add('Đẩy lên: $pushed');
      if (pulled > 0) parts.add('Tải về: $pulled');
      if (skipped > 0) parts.add('Bỏ qua: $skipped');
      if (_conflicts > 0) parts.add('⚠️ Xung đột: $_conflicts');
      if (errors.isNotEmpty) parts.add('Lỗi: ${errors.length}');

      final message = parts.isEmpty
          ? 'Dữ liệu đã đồng bộ đầy đủ ✓'
          : 'Đồng bộ xong! ${parts.join(' · ')}';

      return SyncResult(
        success: errors.isEmpty,
        message: message,
        pushed: pushed,
        pulled: pulled,
        conflicts: _conflicts,
        errors: errors,
      );
    } catch (e) {
      _isSyncing = false;
      _lastError = e.toString();
      return SyncResult(success: false, message: 'Lỗi đồng bộ: $e');
    }
  }
}

/// Sync result model
class SyncResult {
  final bool success;
  final String message;
  final int pushed;
  final int pulled;
  final int conflicts;
  final List<String> errors;

  SyncResult({
    required this.success,
    required this.message,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.errors = const [],
  });
}
