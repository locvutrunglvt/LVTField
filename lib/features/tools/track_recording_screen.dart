import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/layer_model.dart';
import '../../data/models/feature_model.dart';
import '../../data/repositories/layer_repository.dart';
import '../../data/repositories/feature_repository.dart';

/// Track Recording screen — records GPS track as Line or Polygon
/// Inspired by Locus Map Track Recording
///
/// Author: Loc Vu Trung
class TrackRecordingScreen extends StatefulWidget {
  final String projectId;

  const TrackRecordingScreen({super.key, required this.projectId});

  @override
  State<TrackRecordingScreen> createState() => _TrackRecordingScreenState();
}

/// Recording profile configuration
class _RecordingProfile {
  final String name;
  final IconData icon;
  final int intervalSeconds;
  final double minDistanceMeters;

  const _RecordingProfile({
    required this.name,
    required this.icon,
    required this.intervalSeconds,
    required this.minDistanceMeters,
  });
}

enum _RecordingState { idle, recording, paused }

class _TrackRecordingScreenState extends State<TrackRecordingScreen> {
  // Profiles
  static const _profiles = [
    _RecordingProfile(name: 'Đi bộ', icon: Icons.directions_walk, intervalSeconds: 3, minDistanceMeters: 5),
    _RecordingProfile(name: 'Xe máy', icon: Icons.two_wheeler, intervalSeconds: 2, minDistanceMeters: 8),
    _RecordingProfile(name: 'Ô tô', icon: Icons.directions_car, intervalSeconds: 1, minDistanceMeters: 10),
    _RecordingProfile(name: 'Chính xác', icon: Icons.precision_manufacturing, intervalSeconds: 1, minDistanceMeters: 1),
  ];

  int _selectedProfile = 0;
  GeometryType _geometryType = GeometryType.line;
  _RecordingState _recordingState = _RecordingState.idle;

  // Recording data
  final List<LatLng> _trackPoints = [];
  StreamSubscription<Position>? _gpsSub;
  Timer? _timer;
  DateTime? _startTime;
  double _totalDistance = 0;
  Position? _lastPosition;

  // Repos
  final _layerRepo = LayerRepository();
  final _featureRepo = FeatureRepository();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  _RecordingProfile get _profile => _profiles[_selectedProfile];

  // ─── Recording Logic ─────────────────────────────────────────────────

  void _startRecording() {
    setState(() {
      _recordingState = _RecordingState.recording;
      _trackPoints.clear();
      _totalDistance = 0;
      _startTime = DateTime.now();
      _lastPosition = null;
    });

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _profile.minDistanceMeters.toInt(),
      ),
    ).listen(_onGpsUpdate);
  }

  void _onGpsUpdate(Position pos) {
    if (_recordingState != _RecordingState.recording) return;

    final point = LatLng(pos.latitude, pos.longitude);

    // Calculate distance from last point
    if (_lastPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastPosition!.latitude, _lastPosition!.longitude,
        pos.latitude, pos.longitude,
      );
      // Skip if not moved enough
      if (dist < _profile.minDistanceMeters) return;
      _totalDistance += dist;
    }

    setState(() {
      _trackPoints.add(point);
      _lastPosition = pos;
    });
  }

  void _pauseRecording() {
    setState(() => _recordingState = _RecordingState.paused);
    _gpsSub?.pause();
  }

  void _resumeRecording() {
    setState(() => _recordingState = _RecordingState.recording);
    _gpsSub?.resume();
  }

  Future<void> _stopRecording() async {
    _gpsSub?.cancel();
    _gpsSub = null;

    if (_trackPoints.length < 2) {
      setState(() => _recordingState = _RecordingState.idle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Cần ít nhất 2 điểm để lưu')),
        );
      }
      return;
    }

    // Ask for layer name
    final name = await _askLayerName();
    if (name == null || name.isEmpty) {
      setState(() => _recordingState = _RecordingState.idle);
      return;
    }

    // Create layer + feature
    final layer = LayerModel(
      projectId: widget.projectId,
      name: name,
      geometryType: _geometryType,
      styleConfig: _geometryType == GeometryType.polygon
          ? {'fillColor': 0x332196F3, 'strokeColor': 0xFF2196F3, 'strokeWidth': 2.0, 'sourceFormat': 'tracking'}
          : {'color': 0xFFFF5722, 'width': 3.0, 'sourceFormat': 'tracking'},
    );
    await _layerRepo.insert(layer);

    final coords = List<LatLng>.from(_trackPoints);
    if (_geometryType == GeometryType.polygon && coords.length >= 3) {
      // Close polygon
      if (coords.first != coords.last) {
        coords.add(coords.first);
      }
    }

    final feature = FeatureModel(
      layerId: layer.id,
      coordinates: coords,
      attributes: {
        'name': name,
        'profile': _profile.name,
        'points': _trackPoints.length,
        'distance_m': _totalDistance.toStringAsFixed(1),
        'duration': _formatDuration(),
        'recorded_at': DateTime.now().toIso8601String(),
      },
    );
    await _featureRepo.insert(feature);

    setState(() {
      _recordingState = _RecordingState.idle;
      _trackPoints.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Đã lưu "$name" — ${_trackPoints.length} điểm')),
      );
      Navigator.pop(context, true); // Return true to refresh map
    }
  }

  Future<String?> _askLayerName() async {
    final controller = TextEditingController(
      text: 'Track_${DateTime.now().day}.${DateTime.now().month}',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lưu vết GPS'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Tên lớp',
            hintText: 'Ví dụ: Khảo sát khu A',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Lưu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDuration() {
    if (_startTime == null) return '00:00';
    final dur = DateTime.now().difference(_startTime!);
    final h = dur.inHours;
    final m = dur.inMinutes % 60;
    final s = dur.inSeconds % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─── Build UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        title: const Text('Ghi vết GPS', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Recording Profile ──
            _sectionHeader('CHẾ ĐỘ GHI', Icons.tune),
            const SizedBox(height: 12),
            _buildProfileSelector(),

            const SizedBox(height: 28),

            // ── Parameters ──
            _sectionHeader('THAM SỐ', Icons.settings),
            const SizedBox(height: 12),
            _buildParameters(),

            const SizedBox(height: 28),

            // ── Geometry Type ──
            _sectionHeader('LOẠI HÌNH HỌC', Icons.shape_line),
            const SizedBox(height: 12),
            _buildGeometryToggle(),

            const SizedBox(height: 32),

            // ── Recording Stats (if recording) ──
            if (_recordingState != _RecordingState.idle) ...[
              _sectionHeader('ĐANG GHI', Icons.fiber_manual_record, color: Colors.redAccent),
              const SizedBox(height: 12),
              _buildRecordingStats(),
              const SizedBox(height: 24),
            ],

            // ── Play / Pause / Stop button ──
            Center(child: _buildActionButton()),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? const Color(0xFF0066CC)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color ?? const Color(0xFF0066CC),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(_profiles.length, (i) {
          final p = _profiles[i];
          final selected = i == _selectedProfile;
          return InkWell(
            onTap: _recordingState == _RecordingState.idle
                ? () => setState(() => _selectedProfile = i)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF0066CC).withValues(alpha: 0.15) : null,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(color: const Color(0xFF0066CC).withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(p.icon, color: selected ? Colors.white : Colors.white38, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white60,
                            fontSize: 15,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        Text(
                          '${p.intervalSeconds}s / ${p.minDistanceMeters.toInt()}m',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle, color: Color(0xFF0066CC), size: 20),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildParameters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timer, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
              const Expanded(child: Text('Thời gian ghi', style: TextStyle(color: Colors.white60, fontSize: 13))),
              Text(
                'Mỗi ${_profile.intervalSeconds}s',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.straighten, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
              const Expanded(child: Text('Khoảng cách tối thiểu', style: TextStyle(color: Colors.white60, fontSize: 13))),
              Text(
                '${_profile.minDistanceMeters.toInt()} m',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeometryToggle() {
    return Row(
      children: [
        _geomButton(GeometryType.line, Icons.timeline, 'Đường'),
        const SizedBox(width: 12),
        _geomButton(GeometryType.polygon, Icons.pentagon, 'Vùng'),
      ],
    );
  }

  Widget _geomButton(GeometryType type, IconData icon, String label) {
    final selected = _geometryType == type;
    return Expanded(
      child: GestureDetector(
        onTap: _recordingState == _RecordingState.idle
            ? () => setState(() => _geometryType = type)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0066CC).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0066CC)
                  : Colors.white.withValues(alpha: 0.1),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.white38, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Điểm', '${_trackPoints.length}', Icons.place),
              _statItem('Khoảng cách', '${(_totalDistance / 1000).toStringAsFixed(2)} km', Icons.straighten),
              _statItem('Thời gian', _formatDuration(), Icons.timer),
            ],
          ),
          if (_recordingState == _RecordingState.paused)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pause_circle, size: 14, color: Colors.yellowAccent.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    'Tạm dừng',
                    style: TextStyle(
                      color: Colors.yellowAccent.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
      ],
    );
  }

  Widget _buildActionButton() {
    switch (_recordingState) {
      case _RecordingState.idle:
        return GestureDetector(
          onTap: _startRecording,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.play_arrow, size: 50, color: Colors.white),
          ),
        );

      case _RecordingState.recording:
      case _RecordingState.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pause/Resume
            GestureDetector(
              onTap: _recordingState == _RecordingState.recording
                  ? _pauseRecording
                  : _resumeRecording,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orangeAccent.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.orangeAccent, width: 2),
                ),
                child: Icon(
                  _recordingState == _RecordingState.recording
                      ? Icons.pause
                      : Icons.play_arrow,
                  size: 30,
                  color: Colors.orangeAccent,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Stop
            GestureDetector(
              onTap: _stopRecording,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFEF5350), Color(0xFFC62828)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.stop, size: 40, color: Colors.white),
              ),
            ),
          ],
        );
    }
  }
}
