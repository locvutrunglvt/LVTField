// Live Position Tracking Service
// Author: Lộc Vũ Trung

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:latlong2/latlong.dart';
import 'gps_service.dart';

/// Live position of a team member
class TeamMemberPosition {
  final String id; // live_positions record id
  final String userId;
  final String teamId;
  final LatLng position;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final String? deviceName;
  final DateTime updatedAt;
  String? userName; // filled from expand
  
  TeamMemberPosition({
    required this.id,
    required this.userId,
    required this.teamId,
    required this.position,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    this.deviceName,
    required this.updatedAt,
    this.userName,
  });
  
  factory TeamMemberPosition.fromRecord(RecordModel r) => TeamMemberPosition(
    id: r.id,
    userId: r.getStringValue('user'),
    teamId: r.getStringValue('team'),
    position: LatLng(
      r.getDoubleValue('latitude'),
      r.getDoubleValue('longitude'),
    ),
    accuracy: r.getDoubleValue('accuracy'),
    altitude: r.getDoubleValue('altitude'),
    speed: r.getDoubleValue('speed'),
    heading: r.getDoubleValue('heading'),
    deviceName: r.getStringValue('device_name'),
    updatedAt: DateTime.tryParse(r.getStringValue('updated')) ?? DateTime.now(),
  );
  
  /// Check if position is stale (>60s old)
  bool get isStale => DateTime.now().difference(updatedAt).inSeconds > 60;
}

class LiveTrackingService {
  static const _serverUrl = 'https://lvtfield.lvtcenter.it.com';
  static const _updateIntervalSeconds = 5;
  
  final PocketBase _pb;
  final GpsService _gpsService;
  
  Timer? _publishTimer;
  StreamSubscription? _realtimeSub;
  String? _activeTeamId;
  String? _myPositionRecordId; // existing record to update
  bool _isSharing = false;
  
  // Team positions stream
  final _positionsController = StreamController<List<TeamMemberPosition>>.broadcast();
  Stream<List<TeamMemberPosition>> get positionsStream => _positionsController.stream;
  
  final Map<String, TeamMemberPosition> _teamPositions = {};
  
  bool get isSharing => _isSharing;
  String? get activeTeamId => _activeTeamId;
  
  LiveTrackingService({PocketBase? pb, GpsService? gpsService})
      : _pb = pb ?? PocketBase(_serverUrl),
        _gpsService = gpsService ?? GpsService();
  
  /// Use existing authenticated PocketBase instance
  void usePocketBase(PocketBase pb) {
    // Copy auth state
  }
  
  String? get _currentUserId => _pb.authStore.record?.id;
  
  /// Start sharing position for a team
  Future<void> startSharing(String teamId) async {
    if (!_pb.authStore.isValid || _currentUserId == null) {
      debugPrint('LiveTracking: Not authenticated');
      return;
    }
    
    _activeTeamId = teamId;
    _isSharing = true;
    
    // Check if I already have a position record
    try {
      final existing = await _pb.collection('live_positions').getList(
        filter: 'user = "$_currentUserId" && team = "$teamId"',
        perPage: 1,
      );
      if (existing.items.isNotEmpty) {
        _myPositionRecordId = existing.items.first.id;
      }
    } catch (_) {}
    
    // Start periodic position publishing
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(
      const Duration(seconds: _updateIntervalSeconds),
      (_) => _publishPosition(),
    );
    
    // Publish immediately
    await _publishPosition();
    
    // Subscribe to team positions
    await _subscribeToTeam(teamId);
    
    // Load initial positions
    await _loadTeamPositions(teamId);
    
    debugPrint('LiveTracking: Started sharing for team $teamId');
  }
  
  /// Stop sharing position
  Future<void> stopSharing() async {
    _publishTimer?.cancel();
    _publishTimer = null;
    _isSharing = false;
    
    // Unsubscribe from realtime
    try {
      await _pb.collection('live_positions').unsubscribe('*');
    } catch (_) {}
    _realtimeSub?.cancel();
    _realtimeSub = null;
    
    // Delete my position record
    if (_myPositionRecordId != null) {
      try {
        await _pb.collection('live_positions').delete(_myPositionRecordId!);
      } catch (_) {}
    }
    _myPositionRecordId = null;
    _activeTeamId = null;
    _teamPositions.clear();
    _positionsController.add([]);
    
    debugPrint('LiveTracking: Stopped sharing');
  }
  
  /// Publish current GPS position
  Future<void> _publishPosition() async {
    if (!_isSharing || _activeTeamId == null || _currentUserId == null) return;
    
    final pos = _gpsService.lastPosition;
    if (pos == null) return;
    
    final data = {
      'user': _currentUserId,
      'team': _activeTeamId,
      'latitude': pos.latLng.latitude,
      'longitude': pos.latLng.longitude,
      'accuracy': pos.accuracy,
      'altitude': pos.altitude ?? 0,
      'speed': pos.speed ?? 0,
      'heading': pos.heading ?? 0,
      'device_name': 'LVTField',
    };
    
    try {
      if (_myPositionRecordId != null) {
        // Update existing record
        await _pb.collection('live_positions').update(_myPositionRecordId!, body: data);
      } else {
        // Create new record
        final record = await _pb.collection('live_positions').create(body: data);
        _myPositionRecordId = record.id;
      }
    } catch (e) {
      debugPrint('LiveTracking: Publish error: $e');
      // If update failed (deleted), reset and create
      _myPositionRecordId = null;
    }
  }
  
  /// Subscribe to real-time updates for team positions
  Future<void> _subscribeToTeam(String teamId) async {
    try {
      await _pb.collection('live_positions').subscribe('*', (e) {
        if (e.record == null) return;
        final record = e.record!;
        
        // Only process positions for our team
        if (record.getStringValue('team') != teamId) return;
        
        // Skip our own position
        if (record.getStringValue('user') == _currentUserId) return;
        
        switch (e.action) {
          case 'create':
          case 'update':
            final pos = TeamMemberPosition.fromRecord(record);
            _teamPositions[pos.userId] = pos;
            break;
          case 'delete':
            final userId = record.getStringValue('user');
            _teamPositions.remove(userId);
            break;
        }
        
        _emitPositions();
      });
      debugPrint('LiveTracking: Subscribed to team $teamId');
    } catch (e) {
      debugPrint('LiveTracking: Subscribe error: $e');
    }
  }
  
  /// Load current team positions
  Future<void> _loadTeamPositions(String teamId) async {
    try {
      final result = await _pb.collection('live_positions').getList(
        filter: 'team = "$teamId"',
        perPage: 100,
      );
      _teamPositions.clear();
      for (final r in result.items) {
        if (r.getStringValue('user') == _currentUserId) continue; // skip self
        final pos = TeamMemberPosition.fromRecord(r);
        _teamPositions[pos.userId] = pos;
      }
      _emitPositions();
    } catch (e) {
      debugPrint('LiveTracking: Load positions error: $e');
    }
  }
  
  void _emitPositions() {
    // Remove stale positions (>120s)
    _teamPositions.removeWhere((_, p) => 
      DateTime.now().difference(p.updatedAt).inSeconds > 120);
    _positionsController.add(_teamPositions.values.toList());
  }
  
  Future<void> dispose() async {
    await stopSharing();
    await _positionsController.close();
  }
}
