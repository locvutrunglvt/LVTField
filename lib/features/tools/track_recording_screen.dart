import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/layer_model.dart';
import '../../data/models/feature_model.dart';
import '../../data/repositories/layer_repository.dart';
import '../../data/repositories/feature_repository.dart';

/// Track Recording screen — professional GPS track recording
/// with customizable settings, background support, and style options.
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
  final String description;

  const _RecordingProfile({
    required this.name,
    required this.icon,
    required this.intervalSeconds,
    required this.minDistanceMeters,
    required this.description,
  });
}

enum _RecordingState { idle, recording, paused }

class _TrackRecordingScreenState extends State<TrackRecordingScreen>
    with TickerProviderStateMixin {
  // ─── Profiles ───
  static const _profiles = [
    _RecordingProfile(
      name: 'Đi bộ', icon: Icons.directions_walk,
      intervalSeconds: 3, minDistanceMeters: 5,
      description: 'Chậm, chính xác cao',
    ),
    _RecordingProfile(
      name: 'Xe đạp', icon: Icons.pedal_bike,
      intervalSeconds: 2, minDistanceMeters: 8,
      description: 'Tốc độ trung bình',
    ),
    _RecordingProfile(
      name: 'Xe máy', icon: Icons.two_wheeler,
      intervalSeconds: 2, minDistanceMeters: 10,
      description: 'Di chuyển nhanh',
    ),
    _RecordingProfile(
      name: 'Ô tô', icon: Icons.directions_car,
      intervalSeconds: 1, minDistanceMeters: 15,
      description: 'Tốc độ cao',
    ),
    _RecordingProfile(
      name: 'Thuyền', icon: Icons.sailing,
      intervalSeconds: 5, minDistanceMeters: 20,
      description: 'Trên sông/biển',
    ),
    _RecordingProfile(
      name: 'Chính xác', icon: Icons.precision_manufacturing,
      intervalSeconds: 1, minDistanceMeters: 1,
      description: 'Đo đạc, khảo sát',
    ),
  ];

  // ─── State ───
  int _selectedProfile = 2; // Xe máy default
  GeometryType _geometryType = GeometryType.line;
  _RecordingState _recordingState = _RecordingState.idle;

  // Custom settings (override profile defaults)
  late double _customInterval;
  late double _customDistance;
  bool _useCustomSettings = false;

  // Track style
  Color _trackColor = const Color(0xFFFF5722); // Orange
  double _trackWidth = 3.0;

  // Preset track colors
  static const _trackColors = [
    Color(0xFFFF5722), // Orange
    Color(0xFFE91E63), // Pink
    Color(0xFF2196F3), // Blue
    Color(0xFF4CAF50), // Green
    Color(0xFF9C27B0), // Purple
    Color(0xFFFF9800), // Amber
    Color(0xFF00BCD4), // Cyan
    Color(0xFFF44336), // Red
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF795548), // Brown
  ];

  // Recording data
  final List<LatLng> _trackPoints = [];
  StreamSubscription<Position>? _gpsSub;
  Timer? _statsTimer;
  DateTime? _startTime;
  double _totalDistance = 0;
  Position? _lastPosition;
  double _currentSpeed = 0;

  // Animation
  late AnimationController _pulseController;

  // Repos
  final _layerRepo = LayerRepository();
  final _featureRepo = FeatureRepository();

  @override
  void initState() {
    super.initState();
    _customInterval = _profile.intervalSeconds.toDouble();
    _customDistance = _profile.minDistanceMeters;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _statsTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  _RecordingProfile get _profile => _profiles[_selectedProfile];
  int get _effectiveInterval => _useCustomSettings
      ? _customInterval.round()
      : _profile.intervalSeconds;
  double get _effectiveDistance => _useCustomSettings
      ? _customDistance
      : _profile.minDistanceMeters;

  // ─── Foreground Task ──────────────────────────────────────────────────

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'lvtfield_gps_track',
        channelName: 'Ghi vết GPS',
        channelDescription: 'Duy trì GPS khi tắt màn hình',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        eventAction: ForegroundTaskEventAction.repeat(
          _effectiveInterval * 1000,
        ),
      ),
    );
  }

  Future<void> _startForegroundService() async {
    await _initForegroundTask();
    // Request notification permission on Android 13+
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    await FlutterForegroundTask.startService(
      notificationTitle: '🔴 LVTField — Đang ghi vết GPS',
      notificationText: 'Chạm để mở app',
    );
  }

  Future<void> _updateForegroundNotification() async {
    if (_recordingState == _RecordingState.recording) {
      final pts = _trackPoints.length;
      final dist = (_totalDistance / 1000).toStringAsFixed(2);
      await FlutterForegroundTask.updateService(
        notificationTitle: '🔴 Đang ghi vết — $pts điểm',
        notificationText: '$dist km | ${_formatDuration()} | ${_profile.name}',
      );
    }
  }

  Future<void> _stopForegroundService() async {
    await FlutterForegroundTask.stopService();
  }

  // ─── Recording Logic ─────────────────────────────────────────────────

  Future<void> _startRecording() async {
    // Start foreground service first
    await _startForegroundService();

    setState(() {
      _recordingState = _RecordingState.recording;
      _trackPoints.clear();
      _totalDistance = 0;
      _startTime = DateTime.now();
      _lastPosition = null;
      _currentSpeed = 0;
    });

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _effectiveDistance.toInt(),
        intervalDuration: Duration(seconds: _effectiveInterval),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'LVTField GPS',
          notificationText: 'Đang thu thập tọa độ...',
          enableWakeLock: true,
        ),
      ),
    ).listen(_onGpsUpdate);

    // Stats refresh timer
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _updateForegroundNotification();
    });
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
      if (dist < _effectiveDistance) return;
      _totalDistance += dist;
    }

    setState(() {
      _trackPoints.add(point);
      _lastPosition = pos;
      _currentSpeed = pos.speed * 3.6; // m/s → km/h
    });
  }

  void _pauseRecording() {
    setState(() => _recordingState = _RecordingState.paused);
    _gpsSub?.pause();
    FlutterForegroundTask.updateService(
      notificationTitle: '⏸️ Tạm dừng ghi vết',
      notificationText: '${_trackPoints.length} điểm | ${(_totalDistance / 1000).toStringAsFixed(2)} km',
    );
  }

  void _resumeRecording() {
    setState(() => _recordingState = _RecordingState.recording);
    _gpsSub?.resume();
  }

  Future<void> _stopRecording() async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _statsTimer?.cancel();
    _statsTimer = null;

    await _stopForegroundService();

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

    // Build style config with user-chosen color/width
    final Map<String, dynamic> styleConfig;
    if (_geometryType == GeometryType.polygon) {
      styleConfig = {
        'fillColor': _trackColor.value,
        'fillOpacity': 0.2,
        'strokeColor': _trackColor.value,
        'strokeWidth': _trackWidth,
        'sourceFormat': 'tracking',
      };
    } else {
      styleConfig = {
        'color': _trackColor.value,
        'strokeColor': _trackColor.value,
        'width': _trackWidth,
        'strokeWidth': _trackWidth,
        'sourceFormat': 'tracking',
      };
    }

    // Create layer + feature
    final layer = LayerModel(
      projectId: widget.projectId,
      name: name,
      geometryType: _geometryType,
      styleConfig: styleConfig,
    );
    await _layerRepo.insert(layer);

    final coords = List<LatLng>.from(_trackPoints);
    if (_geometryType == GeometryType.polygon && coords.length >= 3) {
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

    final savedPoints = _trackPoints.length;
    final savedCoords = List<LatLng>.from(coords);
    final savedDistance = _totalDistance;
    final savedDuration = _formatDuration();
    setState(() {
      _recordingState = _RecordingState.idle;
      _trackPoints.clear();
    });

    if (mounted) {
      // Ask if user wants to export GPX
      final shouldExport = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ Đã lưu thành công'),
          content: Text('"$name" — $savedPoints điểm\n'
              'Khoảng cách: ${(savedDistance / 1000).toStringAsFixed(2)} km\n'
              'Thời gian: $savedDuration\n\n'
              'Bạn có muốn xuất file GPX để chia sẻ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Đóng'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.file_download, size: 18),
              label: const Text('Xuất GPX', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0066CC),
              ),
            ),
          ],
        ),
      );

      if (shouldExport == true && mounted) {
        await _exportGpx(name, savedCoords, savedDistance, savedDuration);
      }

      if (mounted) Navigator.pop(context, true);
    }
  }

  /// Export track to GPX file and share
  Future<void> _exportGpx(
    String trackName,
    List<LatLng> coords,
    double distanceM,
    String duration,
  ) async {
    try {
      final now = DateTime.now();
      final isoNow = now.toUtc().toIso8601String();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);

      final sb = StringBuffer();
      sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      sb.writeln('<gpx version="1.1" creator="LVTField"');
      sb.writeln('  xmlns="http://www.topografix.com/GPX/1/1"');
      sb.writeln('  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
      sb.writeln('  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');
      sb.writeln('  <metadata>');
      sb.writeln('    <name>${_escapeXml(trackName)}</name>');
      sb.writeln('    <desc>Ghi bởi LVTField | ${_profile.name} | ${(distanceM / 1000).toStringAsFixed(2)} km | $duration</desc>');
      sb.writeln('    <author><name>Lộc Vũ Trung</name></author>');
      sb.writeln('    <time>$isoNow</time>');
      sb.writeln('  </metadata>');
      sb.writeln('  <trk>');
      sb.writeln('    <name>${_escapeXml(trackName)}</name>');
      sb.writeln('    <type>${_profile.name}</type>');
      sb.writeln('    <trkseg>');

      for (final pt in coords) {
        sb.writeln('      <trkpt lat="${pt.latitude.toStringAsFixed(8)}" lon="${pt.longitude.toStringAsFixed(8)}">');
        sb.writeln('        <time>$isoNow</time>');
        sb.writeln('      </trkpt>');
      }

      sb.writeln('    </trkseg>');
      sb.writeln('  </trk>');
      sb.writeln('</gpx>');

      // Write to temp file
      final dir = await getApplicationDocumentsDirectory();
      final gpxFile = File('${dir.path}/${trackName.replaceAll(RegExp(r'[^\w]'), '_')}_$dateStr.gpx');
      await gpxFile.writeAsString(sb.toString(), flush: true);

      // Share
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(gpxFile.path)],
            subject: 'Vết GPS: $trackName',
            text: 'Xuất từ LVTField — ${coords.length} điểm, '
                '${(distanceM / 1000).toStringAsFixed(2)} km',
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📁 Đã xuất GPX: ${gpxFile.path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi xuất GPX: $e')),
        );
      }
    }
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

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
    final isRecording = _recordingState != _RecordingState.idle;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            if (isRecording)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Container(
                  width: 10, height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _recordingState == _RecordingState.paused
                        ? Colors.yellow.withValues(alpha: 0.5 + _pulseController.value * 0.5)
                        : Colors.red.withValues(alpha: 0.5 + _pulseController.value * 0.5),
                  ),
                ),
              ),
            const Text('Ghi vết GPS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        actions: [
          if (isRecording)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _formatDuration(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Recording Stats (if recording) ──
            if (isRecording) ...[
              _buildRecordingStats(),
              const SizedBox(height: 16),
            ],

            // ── Action Button ──
            Center(child: _buildActionButton()),

            if (!isRecording) ...[
              const SizedBox(height: 24),

              // ── Profile Selector ──
              _sectionHeader('PHƯƠNG TIỆN', Icons.commute),
              const SizedBox(height: 10),
              _buildProfileGrid(),
              const SizedBox(height: 20),

              // ── Custom Settings ──
              _sectionHeader('THAM SỐ GHI', Icons.tune),
              const SizedBox(height: 10),
              _buildSettingsPanel(),
              const SizedBox(height: 20),

              // ── Track Style ──
              _sectionHeader('KIỂU VỆT', Icons.brush),
              const SizedBox(height: 10),
              _buildTrackStylePanel(),
              const SizedBox(height: 20),

              // ── Geometry Type ──
              _sectionHeader('LOẠI HÌNH HỌC', Icons.shape_line),
              const SizedBox(height: 10),
              _buildGeometryToggle(),

              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, {Color? color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (color ?? const Color(0xFF0066CC)).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color ?? const Color(0xFF0066CC)),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color ?? const Color(0xFF0066CC),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  // ─── Profile Grid ────────────────────────────────────────────────────

  Widget _buildProfileGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_profiles.length, (i) {
        final p = _profiles[i];
        final selected = i == _selectedProfile;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedProfile = i;
              if (!_useCustomSettings) {
                _customInterval = p.intervalSeconds.toDouble();
                _customDistance = p.minDistanceMeters;
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: (MediaQuery.of(context).size.width - 56) / 3,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0066CC).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0066CC)
                    : Colors.white.withValues(alpha: 0.08),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(p.icon, color: selected ? Colors.white : Colors.white38, size: 24),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.intervalSeconds}s / ${p.minDistanceMeters.toInt()}m',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ─── Settings Panel ──────────────────────────────────────────────────

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          // Custom override toggle
          Row(
            children: [
              const Icon(Icons.edit, size: 14, color: Colors.white38),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Tùy chỉnh tham số',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              Switch(
                value: _useCustomSettings,
                onChanged: (v) => setState(() => _useCustomSettings = v),
                activeColor: const Color(0xFF0066CC),
              ),
            ],
          ),

          if (_useCustomSettings) ...[
            const Divider(color: Colors.white10, height: 20),

            // Time interval slider
            _sliderRow(
              icon: Icons.timer,
              label: 'Thời gian',
              value: '${_customInterval.round()}s',
              slider: Slider(
                value: _customInterval,
                min: 1, max: 30, divisions: 29,
                activeColor: const Color(0xFF0066CC),
                inactiveColor: Colors.white12,
                label: '${_customInterval.round()}s',
                onChanged: (v) => setState(() => _customInterval = v),
              ),
            ),

            const SizedBox(height: 4),

            // Distance slider
            _sliderRow(
              icon: Icons.straighten,
              label: 'Khoảng cách',
              value: '${_customDistance.round()}m',
              slider: Slider(
                value: _customDistance,
                min: 1, max: 50, divisions: 49,
                activeColor: const Color(0xFF0066CC),
                inactiveColor: Colors.white12,
                label: '${_customDistance.round()}m',
                onChanged: (v) => setState(() => _customDistance = v),
              ),
            ),
          ] else ...[
            const Divider(color: Colors.white10, height: 20),
            Row(
              children: [
                const Icon(Icons.timer, size: 14, color: Colors.white38),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Thời gian ghi',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                Text('Mỗi ${_profile.intervalSeconds}s',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.straighten, size: 14, color: Colors.white38),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Khoảng cách tối thiểu',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                Text('${_profile.minDistanceMeters.toInt()} m',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sliderRow({
    required IconData icon,
    required String label,
    required String value,
    required Widget slider,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white38),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0066CC).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        SizedBox(height: 24, child: slider),
      ],
    );
  }

  // ─── Track Style Panel ───────────────────────────────────────────────

  Widget _buildTrackStylePanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Color picker
          const Text('Màu sắc vệt',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trackColors.map((color) {
              final selected = color.value == _trackColor.value;
              return GestureDetector(
                onTap: () => setState(() => _trackColor = color),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                        : null,
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 16,
                          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Stroke width slider
          _sliderRow(
            icon: Icons.line_weight,
            label: 'Nét lực',
            value: '${_trackWidth.toStringAsFixed(1)} px',
            slider: Slider(
              value: _trackWidth,
              min: 1, max: 8, divisions: 14,
              activeColor: _trackColor,
              inactiveColor: Colors.white12,
              label: _trackWidth.toStringAsFixed(1),
              onChanged: (v) => setState(() => _trackWidth = v),
            ),
          ),

          const SizedBox(height: 12),

          // Preview
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Text('Xem trước',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(height: 8),
                  CustomPaint(
                    size: const Size(200, 40),
                    painter: _TrackPreviewPainter(
                      color: _trackColor,
                      width: _trackWidth,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Geometry Toggle ─────────────────────────────────────────────────

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
        onTap: () => setState(() => _geometryType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0066CC).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0066CC)
                  : Colors.white.withValues(alpha: 0.08),
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

  // ─── Recording Stats ─────────────────────────────────────────────────

  Widget _buildRecordingStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _trackColor.withValues(alpha: 0.08),
            _trackColor.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _trackColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Điểm', '${_trackPoints.length}', Icons.place),
              _statItem('Khoảng cách',
                  '${(_totalDistance / 1000).toStringAsFixed(2)} km', Icons.straighten),
              _statItem('Tốc độ',
                  '${_currentSpeed.toStringAsFixed(1)} km/h', Icons.speed),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _recordingState == _RecordingState.paused
                    ? Icons.pause_circle
                    : Icons.fiber_manual_record,
                size: 14,
                color: _recordingState == _RecordingState.paused
                    ? Colors.yellowAccent
                    : Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Text(
                _recordingState == _RecordingState.paused
                    ? 'Tạm dừng — ${_profile.name}'
                    : 'Đang ghi — ${_profile.name}',
                style: TextStyle(
                  color: _recordingState == _RecordingState.paused
                      ? Colors.yellowAccent.withValues(alpha: 0.8)
                      : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // Background info
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.screen_lock_portrait, size: 12, color: Colors.greenAccent),
                SizedBox(width: 4),
                Text(
                  'Hoạt động khi tắt màn hình',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w600),
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
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
      ],
    );
  }

  // ─── Action Button ───────────────────────────────────────────────────

  Widget _buildActionButton() {
    switch (_recordingState) {
      case _RecordingState.idle:
        return GestureDetector(
          onTap: _startRecording,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow, size: 36, color: Colors.white),
                Text('BẮT ĐẦU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
              ],
            ),
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
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orangeAccent.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.orangeAccent, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _recordingState == _RecordingState.recording
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 24,
                      color: Colors.orangeAccent,
                    ),
                    Text(
                      _recordingState == _RecordingState.recording ? 'Dừng' : 'Tiếp',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Stop & Save
            GestureDetector(
              onTap: _stopRecording,
              child: Container(
                width: 72,
                height: 72,
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
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.stop, size: 30, color: Colors.white),
                    Text('LƯU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}

// ─── Track Preview Painter ──────────────────────────────────────────────

class _TrackPreviewPainter extends CustomPainter {
  final Color color;
  final double width;

  _TrackPreviewPainter({required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(10, size.height * 0.7);
    path.cubicTo(
      size.width * 0.25, size.height * 0.1,
      size.width * 0.45, size.height * 0.9,
      size.width * 0.65, size.height * 0.3,
    );
    path.cubicTo(
      size.width * 0.8, size.height * 0.0,
      size.width * 0.9, size.height * 0.5,
      size.width - 10, size.height * 0.6,
    );

    canvas.drawPath(path, paint);

    // Draw dots at key points
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(10, size.height * 0.7), 3, dotPaint);
    canvas.drawCircle(Offset(size.width - 10, size.height * 0.6), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _TrackPreviewPainter old) =>
      old.color != color || old.width != width;
}
