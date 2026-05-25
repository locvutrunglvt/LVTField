import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../data/database/app_database.dart';
import 'package:uuid/uuid.dart';

/// LVT Sync Service - PocketBase cloud synchronization
/// Author: Lộc Vũ Trung
class SyncService {
  static const String _pbUrl = 'https://lvtfield.lvtcenter.it.com';
  late final PocketBase _pb;

  // Sync state
  bool _isSyncing = false;
  String? _lastError;
  DateTime? _lastSyncTime;

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

  SyncService() {
    _pb = PocketBase(_pbUrl);
  }

  /// Login with Google OAuth2
  /// PocketBase SDK handles browser redirect internally
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

  /// Full sync: push local changes then pull remote changes
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
    int pushed = 0, pulled = 0;

    try {
      final db = await AppDatabase.database;
      final userId = _pb.authStore.record?.id ?? '';

      // === PUSH: Local → Remote ===

      // Push projects
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
            await _pb.collection('projects').update(remoteId, body: data);
          } else {
            final record =
                await _pb.collection('projects').create(body: data);
            await db.update(
              'projects',
              {'remote_id': record.id, 'is_synced': 1},
              where: 'id = ?',
              whereArgs: [p['id']],
            );
          }
          pushed++;
        } catch (e) {
          debugPrint('Sync push project error: $e');
        }
      }

      // Push layers
      final localLayers = await db.query('layers');
      for (final l in localLayers) {
        try {
          // Find remote project_id
          final projectRows = await db.query(
            'projects',
            where: 'id = ?',
            whereArgs: [l['project_id']],
          );
          final remoteProjectId = projectRows.isNotEmpty
              ? (projectRows.first['remote_id'] as String? ?? '')
              : '';

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
            await _pb.collection('layers').update(remoteId, body: data);
          } else {
            final record =
                await _pb.collection('layers').create(body: data);
            await db.update(
              'layers',
              {'remote_id': record.id},
              where: 'id = ?',
              whereArgs: [l['id']],
            );
          }
          pushed++;
        } catch (e) {
          debugPrint('Sync push layer error: $e');
        }
      }

      // Push features (only modified ones)
      final modifiedFeatures = await db.query(
        'features',
        where: 'is_modified = 1 OR is_synced = 0',
      );
      for (final f in modifiedFeatures) {
        try {
          final layerRows = await db.query(
            'layers',
            where: 'id = ?',
            whereArgs: [f['layer_id']],
          );
          final remoteLayerId = layerRows.isNotEmpty
              ? (layerRows.first['remote_id'] as String? ?? '')
              : '';

          final remoteId = f['remote_id'] as String?;
          final data = {
            'layer_id': remoteLayerId,
            'coordinates_json': f['coordinates_json'],
            'attributes': f['attributes_json'] ?? '{}',
            'device_id': f['id'],
            'version': (f['version'] as int? ?? 0) + 1,
            'owner': userId,
          };

          if (remoteId != null && remoteId.isNotEmpty) {
            await _pb
                .collection('features')
                .update(remoteId, body: data);
          } else {
            final record =
                await _pb.collection('features').create(body: data);
            await db.update(
              'features',
              {
                'remote_id': record.id,
                'is_synced': 1,
                'is_modified': 0,
                'version': (f['version'] as int? ?? 0) + 1,
              },
              where: 'id = ?',
              whereArgs: [f['id']],
            );
          }
          pushed++;
        } catch (e) {
          debugPrint('Sync push feature error: $e');
        }
      }

      // === PULL: Remote → Local ===
      // Pull remote projects owned by this user
      try {
        final remoteProjects = await _pb.collection('projects').getFullList(
              filter: 'owner = "$userId"',
            );
        for (final rp in remoteProjects) {
          final existing = await db.query(
            'projects',
            where: 'remote_id = ?',
            whereArgs: [rp.id],
          );
          if (existing.isEmpty) {
            // New remote project - create locally
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
          }
        }
      } catch (e) {
        debugPrint('Sync pull projects error: $e');
      }

      _lastSyncTime = DateTime.now();
      _isSyncing = false;

      return SyncResult(
        success: true,
        message: 'Đồng bộ thành công! Đẩy lên: $pushed, Tải về: $pulled',
        pushed: pushed,
        pulled: pulled,
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

  SyncResult({
    required this.success,
    required this.message,
    this.pushed = 0,
    this.pulled = 0,
  });
}
