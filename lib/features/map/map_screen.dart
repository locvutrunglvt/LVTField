import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/form_engine_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/gps_service.dart';
import '../../core/services/crs_service.dart';
import '../../core/services/import_service.dart';
import '../../core/services/export_service.dart';
import '../../core/services/mbtiles_tile_provider.dart';
import '../tools/gps_compass_screen.dart';
import '../../data/models/project_model.dart';
import '../../data/models/layer_model.dart';
import '../../data/models/feature_model.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/layer_repository.dart';
import '../../data/repositories/feature_repository.dart';
import '../../data/models/form_field_model.dart';
import '../../data/database/app_database.dart';
import 'widgets/add_layer_dialog.dart';
import 'widgets/feature_info_sheet.dart';
import 'widgets/dynamic_form_dialog.dart';
import 'widgets/layer_style_dialog.dart';
import 'widgets/navigation_overlay.dart';
import 'widgets/vertex_edit_toolbar.dart';
import '../sync/sync_screen.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ---------------------------------------------------------------------------
// Enums & constants
// ---------------------------------------------------------------------------

/// Current drawing mode for the map
enum DrawingMode { idle, point, line, polygon }

/// Available base map tile layers
enum TileSource { osm, satellite }

/// Default center: Hanoi, Vietnam
const _kDefaultCenter = LatLng(16.1700, 108.1322); // Đỉnh Đèo Hải Vân, Đà Nẵng

// ---------------------------------------------------------------------------
// MapScreen — the core screen of LVTField
// ---------------------------------------------------------------------------

/// Main map screen for viewing and collecting geographic data.
/// Supports GPS tracking, layer rendering, and feature digitizing.
///
/// Author: Lộc Vũ Trung
class MapScreen extends StatefulWidget {
  final String projectId;

  const MapScreen({super.key, required this.projectId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // Controllers & services
  final MapController _mapController = MapController();
  final _gpsService = GpsService();
  final _projectRepo = ProjectRepository();
  final _layerRepo = LayerRepository();
  final _featureRepo = FeatureRepository();

  // Data state
  ProjectModel? _project;
  List<LayerModel> _layers = [];
  Map<String, List<FeatureModel>> _featuresByLayer = {};
  final Map<String, MBTilesTileProvider> _mbtilesProviders = {};

  // GPS state
  GpsPosition? _currentPosition;
  StreamSubscription<GpsPosition>? _gpsSub;
  bool _autoCenter = true;
  bool _gpsPermissionDenied = false;
  bool _gpsEnabled = true; // GPS toggle state: on/off
  String _gpsStatusText = 'Đang khởi tạo GPS...';

  // Map state
  TileSource _tileSource = TileSource.satellite;
  double _mapRotation = 0; // Map rotation in degrees for compass
  bool _mapReady = false; // Whether map controller camera is ready

  // Drawing state
  DrawingMode _drawingMode = DrawingMode.idle;
  String? _activeLayerId;
  List<LatLng> _vertices = [];

  // Layer panel
  bool _showLayerPanel = false;

  // Left toolbar
  bool _showLeftToolbar = false;

  // Feature selection
  FeatureModel? _selectedFeature;
  LayerModel? _selectedFeatureLayer;

  // Navigation mode
  bool _navigationMode = false;
  LatLng? _navigationTarget;
  String? _navigationTargetName;

  // Vertex edit mode
  bool _vertexEditMode = false;
  FeatureModel? _editingFeature;
  LayerModel? _editingFeatureLayer;
  List<LatLng> _editVertices = [];
  List<List<LatLng>> _vertexHistory = []; // undo stack
  int? _draggingVertexIndex;
  bool _translateMode = false;     // true = drag moves entire polygon
  LatLng? _translateStartPoint;    // start position for translate drag

  // Feature layer cache (avoid rebuilding expensive layer widgets on every setState)
  List<Widget>? _featureLayerCache;

  // GPS position update throttle — avoid excessive rebuilds
  DateTime _lastGpsSetState = DateTime.now();
  static const _gpsThrottleMs = 500; // minimum ms between GPS-triggered setState

  // CRS display mode
  CrsDisplayMode _crsDisplayMode = CrsDisplayMode.wgs84;

  // Track recording (inline on map)
  bool _trackRecording = false;
  bool _trackPaused = false;
  List<LatLng> _trackPoints = [];
  double _trackDistance = 0;
  DateTime? _trackStartTime;
  Position? _trackLastPos;
  StreamSubscription<Position>? _trackGpsSub;
  Timer? _trackRefreshTimer;
  GeometryType _trackGeomType = GeometryType.line;
  // Track settings
  Color _trackColor = const Color(0xFFFF5722);
  double _trackWidth = 3.0;
  int _trackProfileIdx = 2; // default: Xe máy
  int _trackDistFilter = 10; // meters
  String _trackProfileName = 'Xe máy';
  int _trackTimeInterval = 0; // seconds, 0 = disabled (distance-only)
  Timer? _trackIntervalTimer; // time-based GPS collection

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _initGps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsSub?.cancel();
    _trackGpsSub?.cancel();
    _trackRefreshTimer?.cancel();
    _trackIntervalTimer?.cancel();
    _gpsService.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Re-start GPS when app returns from background (user may have enabled location)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_gpsService.isTracking) {
      _initGps();
    }
  }

  // -------------------------------------------------------------------------
  // Data loading
  // -------------------------------------------------------------------------

  /// Load project, layers, and all features from the database
  Future<void> _loadData() async {
    final project = await _projectRepo.getById(widget.projectId);
    final layers = await _layerRepo.getByProject(widget.projectId);

    final featuresByLayer = <String, List<FeatureModel>>{};
    for (final layer in layers) {
      featuresByLayer[layer.id] = await _featureRepo.getByLayer(layer.id);
    }

    if (!mounted) return;
    setState(() {
      _project = project;
      _layers = layers;
      _featuresByLayer = featuresByLayer;
      _featureLayerCache = null; // invalidate cache
    });
  }

  /// Reload features only (after saving a new feature)
  Future<void> _reloadFeatures() async {
    final featuresByLayer = <String, List<FeatureModel>>{};
    for (final layer in _layers) {
      featuresByLayer[layer.id] = await _featureRepo.getByLayer(layer.id);
    }
    if (!mounted) return;
    setState(() {
      _featuresByLayer = featuresByLayer;
      _featureLayerCache = null; // invalidate cache
    });
  }

  // -------------------------------------------------------------------------
  // GPS — robust initialization with retry
  // -------------------------------------------------------------------------

  /// Initialize GPS with proper permission handling and retry logic
  Future<void> _initGps() async {
    setState(() {
      _gpsStatusText = 'Đang kiểm tra GPS...';
      _gpsPermissionDenied = false;
    });

    // Step 1: Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _gpsStatusText = 'GPS tắt! Hãy bật định vị';
        _gpsPermissionDenied = true;
      });
      _showGpsDialog(
        'GPS đang tắt',
        'Vui lòng bật dịch vụ định vị GPS trên thiết bị để sử dụng ứng dụng.',
        openSettings: true,
      );
      return;
    }

    // Step 2: Check and request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      setState(() {
        _gpsStatusText = 'Chưa cấp quyền GPS';
        _gpsPermissionDenied = true;
      });
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _gpsStatusText = 'Quyền GPS bị từ chối';
        _gpsPermissionDenied = true;
      });
      _showGpsDialog(
        'Quyền GPS bị từ chối',
        'Ứng dụng cần quyền truy cập vị trí. Vui lòng vào Cài đặt > Ứng dụng > LVTField > Quyền > Vị trí để cấp lại.',
        openAppSettings: true,
      );
      return;
    }

    // Step 3: Start tracking
    setState(() => _gpsStatusText = 'Đang tìm GPS...');
    await _startGpsTracking();
  }

  /// Start continuous GPS tracking
  Future<void> _startGpsTracking() async {
    final ok = await _gpsService.startTracking(
      distanceFilter: 2,  // Only update when moved ≥2m (reduces setState flood)
      intervalMs: 500,
    );
    if (!ok) {
      if (!mounted) return;
      setState(() => _gpsStatusText = 'Lỗi khởi động GPS');
      return;
    }

    _gpsSub?.cancel();
    _gpsSub = _gpsService.positionStream.listen(
      (pos) {
        if (!mounted) return;
        // Throttle: skip if less than 500ms since last setState
        final now = DateTime.now();
        if (now.difference(_lastGpsSetState).inMilliseconds < _gpsThrottleMs) {
          // Still update internal position for auto-center without rebuild
          _currentPosition = pos;
          if (_autoCenter) {
            try {
              _mapController.move(pos.latLng, _mapController.camera.zoom);
            } catch (_) {}
          }
          return;
        }
        _lastGpsSetState = now;
        setState(() {
          _currentPosition = pos;
          _gpsStatusText = pos.accuracyText;
        });

        // Auto-center the map on the first fix, or when auto-center is on
        if (_autoCenter) {
          try {
            _mapController.move(pos.latLng, _mapController.camera.zoom);
          } catch (_) {
            // MapController may not be ready yet
          }
        }
      },
      onError: (error) {
        debugPrint('GPS stream error: $error');
        if (!mounted) return;
        setState(() => _gpsStatusText = 'Lỗi GPS');
      },
    );
  }

  /// Show GPS permission/settings dialog
  void _showGpsDialog(String title, String message,
      {bool openSettings = false, bool openAppSettings = false}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.gps_off, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          if (openSettings)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openLocationSettings();
              },
              child: const Text('Mở cài đặt GPS'),
            ),
          if (openAppSettings)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openAppSettings();
              },
              child: const Text('Mở cài đặt ứng dụng'),
            ),
        ],
      ),
    );
  }

  /// Toggle GPS on/off
  void _toggleGps() {
    if (_gpsEnabled) {
      // Disable GPS - stop tracking
      _gpsSub?.cancel();
      _gpsSub = null;
      _gpsService.stopTracking();
      setState(() {
        _gpsEnabled = false;
        _currentPosition = null;
        _gpsStatusText = 'GPS đã tắt';
        _autoCenter = false;
      });
      _showSnackBar('GPS đã tắt');
    } else {
      // Re-enable GPS
      setState(() {
        _gpsEnabled = true;
        _gpsStatusText = 'Đang bật GPS...';
      });
      _initGps();
      _showSnackBar('GPS đã bật');
    }
  }

  /// Move map to current GPS location
  void _centerOnGps() {
    if (!_gpsEnabled) {
      _showSnackBar('GPS đang tắt. Bấm vào badge GPS để bật.');
      return;
    }
    final pos = _currentPosition;
    if (pos == null) {
      // If no GPS, try to re-init
      if (_gpsPermissionDenied) {
        _initGps();
      } else {
        _showSnackBar('Đang chờ tín hiệu GPS...');
      }
      return;
    }
    _mapController.move(pos.latLng, _mapController.camera.zoom.clamp(15, 20));
    setState(() => _autoCenter = true);
  }

  // -------------------------------------------------------------------------
  // Drawing logic
  // -------------------------------------------------------------------------

  /// Start digitizing a specific geometry type
  /// If no layers exist, prompt user to create one first
  Future<void> _startDrawing(DrawingMode mode) async {
    final targetType = _geometryTypeFor(mode);

    // 1) If we have an active layer and it matches geometry type — use it
    if (_activeLayerId != null) {
      final activeLayer = _layers.where((l) => l.id == _activeLayerId).firstOrNull;
      if (activeLayer != null && activeLayer.geometryType == targetType && !activeLayer.isReadOnly) {
        setState(() {
          _drawingMode = mode;
          _vertices = [];
          _autoCenter = false;
        });
        return;
      }
    }

    // 2) Find any editable layer of the correct geometry type
    final editableLayers = _layers.where((l) => l.geometryType == targetType && !l.isReadOnly).toList();

    if (editableLayers.isNotEmpty) {
      // If multiple, pick last used or first
      final layerId = editableLayers.first.id;
      setState(() {
        _drawingMode = mode;
        _activeLayerId = layerId;
        _vertices = [];
        _autoCenter = false;
      });
      return;
    }

    // 3) No layer exists — create one via dialog
    final result = await AddLayerDialog.show(context, widget.projectId);
    if (result == null) return;

    final newLayer = result['layer'] as LayerModel;
    final fieldDefs = result['fields'] as List<Map<String, dynamic>>? ?? [];

    final correctedLayer = LayerModel(
      id: newLayer.id,
      projectId: widget.projectId,
      name: newLayer.name,
      geometryType: targetType,
    );

    await _layerRepo.insert(correctedLayer);

    if (fieldDefs.isNotEmpty) {
      final formEngine = FormEngineService();
      final uuid = const Uuid();
      final fields = fieldDefs.map((def) => FormFieldModel(
        id: uuid.v4(),
        layerId: correctedLayer.id,
        fieldName: def['fieldName'] as String,
        label: def['label'] as String,
        fieldType: FormFieldType.values.firstWhere(
          (t) => t.name == (def['fieldType'] as String? ?? 'text'),
          orElse: () => FormFieldType.text,
        ),
        autoSource: def['autoSource'] as String?,
        hint: def['hint'] as String?,
        sortOrder: def['sortOrder'] as int? ?? 0,
      )).toList();
      await formEngine.saveFields(fields);
    }

    await _loadData();

    if (!mounted) return;
    setState(() {
      _drawingMode = mode;
      _activeLayerId = correctedLayer.id;
      _vertices = [];
      _autoCenter = false;
    });
  }

  /// Map drawing mode to GeometryType
  GeometryType _geometryTypeFor(DrawingMode mode) {
    switch (mode) {
      case DrawingMode.point:
        return GeometryType.point;
      case DrawingMode.line:
        return GeometryType.line;
      case DrawingMode.polygon:
        return GeometryType.polygon;
      case DrawingMode.idle:
        return GeometryType.point;
    }
  }

  /// Handle tap on the map
  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // Ignore map taps during vertex editing (handled by vertex markers)
    if (_vertexEditMode) return;

    // If in drawing mode, add vertex (with snap-to-vertex)
    if (_drawingMode != DrawingMode.idle) {
      // Add vertex at tap point (NO snap — snap disabled for speed)
      setState(() {
        _vertices.add(point);
      });

      if (_drawingMode == DrawingMode.point && _vertices.length == 1) {
        _saveFeature();
      }
      return;
    }

    // Dismiss all popups when tapping the map
    if (_showLeftToolbar || _showLayerPanel) {
      setState(() {
        _showLeftToolbar = false;
        _showLayerPanel = false;
      });
      return;
    }

    // If in idle mode, try to select a feature
    _trySelectFeature(point);
  }

  /// Find the nearest vertex within snap distance (15 screen pixels)
  LatLng? _findSnapPoint(LatLng tapPoint) {
    const snapRadiusDeg = 0.0002; // ~22m at equator, good for zoom 15+
    LatLng? nearest;
    double nearestDist = double.infinity;

    for (final entry in _featuresByLayer.entries) {
      for (final feature in entry.value) {
        for (final coord in feature.coordinates) {
          final dist = _quickDistance(tapPoint, coord);
          if (dist < snapRadiusDeg && dist < nearestDist) {
            nearestDist = dist;
            nearest = coord;
          }
        }
      }
    }
    return nearest;
  }

  double _quickDistance(LatLng a, LatLng b) {
    final dx = a.longitude - b.longitude;
    final dy = a.latitude - b.latitude;
    return (dx * dx + dy * dy);
  }

  /// Try to select a feature near the tap point
  void _trySelectFeature(LatLng tapPoint) {
    const searchRadius = 0.0005; // ~55m
    FeatureModel? bestFeature;
    LayerModel? bestLayer;
    double bestDist = double.infinity;

    for (final layer in _layers) {
      if (!layer.isVisible) continue;
      final features = _featuresByLayer[layer.id] ?? [];
      for (final feature in features) {
        // For points: check distance to centroid
        // For lines/polygons: check distance to each vertex
        double dist;
        if (layer.geometryType == GeometryType.point) {
          dist = _quickDistance(tapPoint, feature.centroid);
        } else {
          dist = feature.coordinates
              .map((c) => _quickDistance(tapPoint, c))
              .reduce((a, b) => a < b ? a : b);
        }
        if (dist < searchRadius && dist < bestDist) {
          bestDist = dist;
          bestFeature = feature;
          bestLayer = layer;
        }
      }
    }

    if (bestFeature != null && bestLayer != null) {
      _showFeatureInfoSheet(bestFeature, bestLayer);
    }
  }

  /// Show the feature info bottom sheet
  void _showFeatureInfoSheet(FeatureModel feature, LayerModel layer) {
    setState(() {
      _selectedFeature = feature;
      _selectedFeatureLayer = layer;
    });

    FeatureInfoSheet.show(
      context,
      feature: feature,
      layer: layer,
      onEditAttributes: () => _editFeatureAttributes(feature, layer),
      onEditGeometry: () {
        Navigator.of(context).pop(); // close bottom sheet
        _enterVertexEditMode(feature, layer);
      },
      onNavigate: () => _startNavigation(feature),
      onDelete: () => _deleteFeature(feature),
    ).then((_) {
      if (mounted) {
        setState(() {
          _selectedFeature = null;
          _selectedFeatureLayer = null;
        });
      }
    });
  }

  /// Edit feature attributes via simple inline dialog
  void _editFeatureAttributes(FeatureModel feature, LayerModel layer) async {
    // Close bottom sheet first, then wait for it to fully close
    Navigator.of(context).pop();
    await Future.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;

    // Prepare attribute controllers
    final attrs = Map<String, dynamic>.from(feature.attributes);
    final controllers = <String, TextEditingController>{};
    for (final entry in attrs.entries) {
      controllers[entry.key] = TextEditingController(
        text: entry.value?.toString() ?? '',
      );
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit_note, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sửa thuộc tính — ${layer.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: controllers.length,
              itemBuilder: (context, index) {
                final key = controllers.keys.elementAt(index);
                final ctrl = controllers[key]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      labelText: key,
                      labelStyle: const TextStyle(fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () {
                final result = <String, dynamic>{};
                for (final entry in controllers.entries) {
                  final val = entry.value.text.trim();
                  if (val.isNotEmpty) {
                    // Try to preserve numeric types
                    final numVal = num.tryParse(val);
                    result[entry.key] = numVal ?? val;
                  }
                }
                Navigator.pop(ctx, result);
              },
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );

    // Dispose controllers
    for (final ctrl in controllers.values) {
      ctrl.dispose();
    }

    if (result != null && mounted) {
      final updated = feature.copyWith(attributes: result);
      await _featureRepo.update(updated);
      await _reloadFeatures();
      _showSnackBar('✅ Đã cập nhật thuộc tính');
    }
  }

  /// Delete a feature
  void _deleteFeature(FeatureModel feature) async {
    await _featureRepo.delete(feature.id);
    await _reloadFeatures();
    _showSnackBar('Đã xóa đối tượng');
  }

  /// Start navigation to a feature's centroid
  void _startNavigation(FeatureModel feature) {
    Navigator.of(context).pop(); // Close bottom sheet
    setState(() {
      _navigationMode = true;
      _navigationTarget = feature.centroid;
      _navigationTargetName = feature.attributes['name']?.toString() ?? 'Feature ${feature.id.substring(0, 6)}';
      _autoCenter = true;
    });
  }

  /// Stop navigation mode
  void _stopNavigation() {
    setState(() {
      _navigationMode = false;
      _navigationTarget = null;
      _navigationTargetName = null;
    });
  }

  // -------------------------------------------------------------------------
  // Vertex Editing — Chỉnh sửa đồ hình
  // -------------------------------------------------------------------------

  /// Enter vertex edit mode for a feature
  void _enterVertexEditMode(FeatureModel feature, LayerModel layer) {
    // Read-only layers (KML/KMZ/MBTiles) cannot be edited
    if (layer.isReadOnly) {
      _showSnackBar('🔒 Layer ${layer.sourceFormat?.toUpperCase()} chỉ xem — không thể chỉnh sửa');
      return;
    }
    // Point features can't be vertex-edited
    if (layer.geometryType == GeometryType.point) {
      _showSnackBar('Đối tượng dạng điểm không cần chỉnh sửa đồ hình');
      return;
    }

    setState(() {
      _vertexEditMode = true;
      _editingFeature = feature;
      _editingFeatureLayer = layer;
      _editVertices = List<LatLng>.from(feature.coordinates);
      _vertexHistory = [];
      _draggingVertexIndex = null;
      // Hide other UI
      _showLeftToolbar = false;
      _showLayerPanel = false;
    });

    // Zoom to feature bounds with padding for context
    _zoomToVertices(feature.coordinates);

    _showSnackBar('🔧 Chế độ chỉnh sửa đồ hình — Kéo đỉnh để di chuyển');
  }

  /// Exit vertex edit mode, optionally saving changes
  Future<void> _exitVertexEditMode({bool save = false}) async {
    if (save && _editingFeature != null) {
      // Validate minimum vertices
      final layer = _editingFeatureLayer;
      if (layer != null) {
        final minVertices = layer.geometryType == GeometryType.polygon ? 3 : 2;
        if (_editVertices.length < minVertices) {
          _showSnackBar('⚠️ Cần ít nhất $minVertices đỉnh cho ${layer.geometryType == GeometryType.polygon ? 'vùng' : 'đường'}');
          return;
        }
      }

      // Save updated coordinates
      final updated = _editingFeature!.copyWith(
        coordinates: List<LatLng>.from(_editVertices),
        isModified: true,
      );
      await _featureRepo.update(updated);
      await _reloadFeatures();
      _showSnackBar('✅ Đã lưu thay đổi đồ hình (${_editVertices.length} đỉnh)');
    } else {
      _showSnackBar('Đã hủy chỉnh sửa đồ hình');
    }

    setState(() {
      _vertexEditMode = false;
      _editingFeature = null;
      _editingFeatureLayer = null;
      _editVertices = [];
      _vertexHistory = [];
      _draggingVertexIndex = null;
    });
  }

  /// Undo the last vertex edit operation
  void _undoVertexEdit() {
    if (_vertexHistory.isEmpty) return;
    setState(() {
      _editVertices = _vertexHistory.removeLast();
    });
  }

  /// Save current state to undo history before making changes
  void _pushVertexHistory() {
    _vertexHistory.add(List<LatLng>.from(_editVertices));
    // Limit undo depth
    if (_vertexHistory.length > 30) {
      _vertexHistory.removeAt(0);
    }
  }

  /// Add a new vertex at the midpoint between index and index+1
  void _addVertexAtMidpoint(int index) {
    if (index < 0 || index >= _editVertices.length) return;
    final nextIndex = (index + 1) % _editVertices.length;

    final mid = LatLng(
      (_editVertices[index].latitude + _editVertices[nextIndex].latitude) / 2,
      (_editVertices[index].longitude + _editVertices[nextIndex].longitude) / 2,
    );

    _pushVertexHistory();
    setState(() {
      _editVertices.insert(index + 1, mid);
    });
    _showSnackBar('➕ Thêm đỉnh mới (${_editVertices.length} đỉnh)');
  }

  /// Delete a vertex by index (with minimum check)
  void _deleteVertexAt(int index) {
    if (index < 0 || index >= _editVertices.length) return;

    final layer = _editingFeatureLayer;
    final minVertices = (layer?.geometryType == GeometryType.polygon) ? 3 : 2;

    if (_editVertices.length <= minVertices) {
      _showSnackBar('⚠️ Không thể xóa — cần ít nhất $minVertices đỉnh');
      return;
    }

    _pushVertexHistory();
    setState(() {
      _editVertices.removeAt(index);
    });
    _showSnackBar('🗑️ Đã xóa đỉnh (còn ${_editVertices.length} đỉnh)');
  }

  /// Zoom map to fit a list of vertices with padding
  void _zoomToVertices(List<LatLng> vertices) {
    if (vertices.isEmpty) return;

    // Compute bounding box
    double minLat = vertices[0].latitude;
    double maxLat = vertices[0].latitude;
    double minLng = vertices[0].longitude;
    double maxLng = vertices[0].longitude;

    for (final v in vertices) {
      if (v.latitude < minLat) minLat = v.latitude;
      if (v.latitude > maxLat) maxLat = v.latitude;
      if (v.longitude < minLng) minLng = v.longitude;
      if (v.longitude > maxLng) maxLng = v.longitude;
    }

    // Add 30% padding for context (see neighbors)
    final latPad = (maxLat - minLat) * 0.3;
    final lngPad = (maxLng - minLng) * 0.3;

    // Zoom with padding for context (see neighbors)
    try {
      final bounds = LatLngBounds(
        LatLng(minLat - latPad, minLng - lngPad),
        LatLng(maxLat + latPad, maxLng + lngPad),
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
      );
    } catch (e) {
      // Fallback: move to centroid
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController.move(LatLng(centerLat, centerLng), 16);
    }
  }

  /// Quick GPS point: create a point at current GPS position immediately
  /// No drawing mode needed — saves directly to active layer
  Future<void> _quickGpsPoint() async {
    final pos = _currentPosition;
    if (pos == null) {
      _showSnackBar('Chưa có tín hiệu GPS. Vui lòng đợi...');
      return;
    }
    if (_activeLayerId == null) {
      _showSnackBar('Chưa chọn lớp');
      return;
    }

    // Temporarily set vertices for auto-calc
    _vertices = [pos.latLng];
    _drawingMode = DrawingMode.point;
    await _saveFeature();
  }

  /// Add a vertex at the current GPS position
  void _addGpsVertex() {
    final pos = _currentPosition;
    if (pos == null) {
      _showSnackBar('Chưa có tín hiệu GPS. Vui lòng đợi...');
      return;
    }

    // Warn if accuracy is poor
    if (pos.accuracy > 20) {
      _showSnackBar('⚠️ Độ chính xác: ${pos.accuracyText} — hãy đợi GPS ổn định hơn');
    }

    setState(() => _vertices.add(pos.latLng));

    // Auto-save for point mode
    if (_drawingMode == DrawingMode.point && _vertices.length == 1) {
      _saveFeature();
    }
  }

  /// Undo the last vertex
  void _undoVertex() {
    if (_vertices.isEmpty) return;
    setState(() => _vertices.removeLast());
  }

  /// Cancel the current drawing session
  void _cancelDrawing() {
    setState(() {
      _drawingMode = DrawingMode.idle;
      _activeLayerId = null;
      _vertices = [];
    });
  }

  /// Save the drawn feature to the database
  Future<void> _saveFeature() async {
    if (_activeLayerId == null || _vertices.isEmpty) return;

    // Validate minimum vertices
    if (_drawingMode == DrawingMode.line && _vertices.length < 2) {
      _showSnackBar('Đường phải có ít nhất 2 điểm');
      return;
    }
    if (_drawingMode == DrawingMode.polygon && _vertices.length < 3) {
      _showSnackBar('Vùng phải có ít nhất 3 điểm');
      return;
    }

    // Show form dialog to collect attributes
    Map<String, dynamic> attributes = {};
    final activeLayer = _layers.where((l) => l.id == _activeLayerId).firstOrNull;

    if (activeLayer != null) {
      try {
        final appDb = await AppDatabase.database;
        final formRows = await appDb.query(
          'form_fields',
          where: 'layer_id = ?',
          whereArgs: [activeLayer.id],
          orderBy: 'sort_order ASC',
        );

        if (formRows.isNotEmpty && mounted) {
          final formFields = formRows.map((r) => FormFieldModel.fromMap(r)).toList();

          // Auto-calculate values
          final initialValues = <String, dynamic>{};
          for (final field in formFields) {
            final src = field.autoSource;
            if (src == null) continue;
            switch (src) {
              case 'auto_increment':
                // Count existing features + 1
                final count = await appDb.rawQuery(
                  'SELECT COUNT(*) as cnt FROM features WHERE layer_id = ?',
                  [activeLayer.id],
                );
                initialValues[field.fieldName] = ((count.first['cnt'] as int? ?? 0) + 1).toString();
                break;
              case 'area_ha':
                if (_vertices.length >= 3) {
                  initialValues[field.fieldName] = _calculateAreaHa(_vertices).toStringAsFixed(4);
                }
                break;
              case 'length_m':
                if (_vertices.length >= 2) {
                  initialValues[field.fieldName] = _calculateLengthM(_vertices).toStringAsFixed(2);
                }
                break;
              case 'lat_7':
                if (_vertices.isNotEmpty) {
                  initialValues[field.fieldName] = _vertices.first.latitude.toStringAsFixed(7);
                }
                break;
              case 'long_7':
                if (_vertices.isNotEmpty) {
                  initialValues[field.fieldName] = _vertices.first.longitude.toStringAsFixed(7);
                }
                break;
            }
          }

          final result = await DynamicFormDialog.show(
            context,
            title: 'Nhập thông tin — ${activeLayer.name}',
            formFields: formFields,
            initialValues: initialValues,
            allowAddCustom: true,
          );
          if (result == null) {
            // User cancelled — don't save
            return;
          }
          attributes = result;
        }
      } catch (e) {
        debugPrint('MapScreen: Error loading form fields: $e');
      }
    }

    final feature = FeatureModel(
      layerId: _activeLayerId!,
      coordinates: List.from(_vertices),
      gpsAccuracy: _currentPosition?.accuracy,
      attributes: attributes,
    );

    try {
      await _featureRepo.insert(feature);
      await _reloadFeatures();

      if (!mounted) return;
      _showSnackBar('✅ Đã lưu đối tượng (${_vertices.length} đỉnh)');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('${AppStrings.errorOccurred}: $e');
    }

    // Reset drawing state — keep active layer for fast re-draw
    setState(() {
      _drawingMode = DrawingMode.idle;
      // Keep _activeLayerId so user can immediately draw more
      _vertices = [];
    });
  }

  /// Calculate polygon area in hectares using Shoelace formula on WGS84
  double _calculateAreaHa(List<LatLng> vertices) {
    if (vertices.length < 3) return 0;
    // Spherical excess method for small polygons
    double area = 0;
    final n = vertices.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final lat1 = vertices[i].latitude * math.pi / 180;
      final lat2 = vertices[j].latitude * math.pi / 180;
      final dLng = (vertices[j].longitude - vertices[i].longitude) * math.pi / 180;
      area += dLng * (2 + math.sin(lat1) + math.sin(lat2));
    }
    area = (area * 6378137 * 6378137 / 2).abs();
    return area / 10000; // m² to ha
  }

  /// Calculate line length in meters using Haversine
  double _calculateLengthM(List<LatLng> vertices) {
    double total = 0;
    for (int i = 0; i < vertices.length - 1; i++) {
      total += _haversineDistance(vertices[i], vertices[i + 1]);
    }
    return total;
  }

  /// Haversine distance between two points in meters
  double _haversineDistance(LatLng a, LatLng b) {
    const R = 6378137.0; // Earth radius in meters
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            sinLng * sinLng;
    return 2 * R * math.asin(math.sqrt(h));
  }

  /// Show a snack bar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // -------------------------------------------------------------------------
  // Layer management
  // -------------------------------------------------------------------------

  /// Toggle visibility of a layer
  Future<void> _toggleLayerVisibility(LayerModel layer) async {
    final updated = layer.copyWith(isVisible: !layer.isVisible);
    await _layerRepo.toggleVisibility(layer.id, !layer.isVisible);
    if (!mounted) return;
    setState(() {
      final idx = _layers.indexWhere((l) => l.id == layer.id);
      if (idx >= 0) _layers[idx] = updated;
      _featureLayerCache = null; // invalidate cache
    });
  }

  /// Add a new layer to the project
  Future<void> _addLayer() async {
    final result = await AddLayerDialog.show(context, widget.projectId);
    if (result == null) return;

    final newLayer = result['layer'] as LayerModel;
    final fieldDefs = result['fields'] as List<Map<String, dynamic>>? ?? [];

    await _layerRepo.insert(newLayer);

    // Create form fields
    if (fieldDefs.isNotEmpty) {
      final formEngine = FormEngineService();
      final uuid = const Uuid();
      final fields = fieldDefs.map((def) => FormFieldModel(
        id: uuid.v4(),
        layerId: newLayer.id,
        fieldName: def['fieldName'] as String,
        label: def['label'] as String,
        fieldType: FormFieldType.values.firstWhere(
          (t) => t.name == (def['fieldType'] as String? ?? 'text'),
          orElse: () => FormFieldType.text,
        ),
        autoSource: def['autoSource'] as String?,
        hint: def['hint'] as String?,
        sortOrder: def['sortOrder'] as int? ?? 0,
      )).toList();
      await formEngine.saveFields(fields);
    }

    await _loadData();

    if (!mounted) return;
    _showSnackBar('✅ Đã tạo lớp "${newLayer.name}"');
  }

  /// Delete a layer
  Future<void> _deleteLayer(LayerModel layer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lớp dữ liệu'),
        content: Text('Xóa lớp "${layer.name}" và tất cả đối tượng trong đó?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _layerRepo.delete(layer.id);
      await _loadData();
      if (!mounted) return;
      _showSnackBar('Đã xóa lớp "${layer.name}"');
    }
  }
  // -------------------------------------------------------------------------
  // Import GIS Data into project
  // -------------------------------------------------------------------------

  Future<void> _showImportDataDialog() async {
    final projectId = widget.projectId;

    // Pick file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Chọn file GIS để nhập',
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    final ext = filePath.toLowerCase();
    final supportedExts = ['.gpkg', '.shp', '.kml', '.kmz', '.geojson', '.json', '.mbtiles', '.tif', '.tiff', '.lvtfield', '.zip'];
    final isSupported = supportedExts.any((e) => ext.endsWith(e));

    if (!isSupported) {
      _showSnackBar('❌ Định dạng không hỗ trợ. Hãy chọn: GPKG, SHP(ZIP), KML, KMZ, GeoJSON');
      return;
    }

    // Show progress dialog
    if (!mounted) return;
    final progressNotifier = ValueNotifier<_ImportProgress>(
      _ImportProgress(0, 0, 'Đang chuẩn bị...'),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ValueListenableBuilder<_ImportProgress>(
              valueListenable: progressNotifier,
              builder: (_, progress, __) {
                final percent = progress.total > 0
                    ? (progress.current / progress.total).clamp(0.0, 1.0)
                    : 0.0;
                final percentText = progress.total > 0
                    ? '${(percent * 100).toInt()}%'
                    : '...';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress.total > 0 ? percent : null,
                            strokeWidth: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              percent >= 1.0 ? Colors.green : Theme.of(context).primaryColor,
                            ),
                          ),
                          Text(
                            percentText,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      progress.message,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    if (progress.total > 0) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            percent >= 1.0 ? Colors.green : Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${progress.current} / ${progress.total}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    // Import with progress callback
    final importService = ImportService();
    final importResult = await importService.importFile(
      filePath,
      projectId,
      onProgress: (current, total, message) {
        progressNotifier.value = _ImportProgress(current, total, message);
      },
    );

    // Close loading
    if (mounted) Navigator.pop(context);
    progressNotifier.dispose();

    if (importResult.success) {
      _showSnackBar(
        '✅ Nhập thành công: ${importResult.featureCount} đối tượng'
        '${importResult.layerCount > 0 ? ", ${importResult.layerCount} lớp" : ""}',
      );
      // Reload layers and features
      await _loadData();

      // Auto-zoom to overlay bounds (for TIFF/raster imports)
      if (importResult.overlayBounds != null && importResult.overlayBounds!.length == 4) {
        final b = importResult.overlayBounds!;
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(b[0], b[1]), // south, west
            LatLng(b[2], b[3]), // north, east
          ),
          padding: const EdgeInsets.all(40),
        ));
      }
    } else {
      _showSnackBar('❌ ${importResult.errorMessage ?? "Lỗi không xác định"}');
    }
  }

  // -------------------------------------------------------------------------
  // CRS Picker — Hệ tọa độ
  // -------------------------------------------------------------------------

  void _showCrsPicker() {
    final crsService = CrsService();
    final grouped = CrsService.groupedCrs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.public, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Hệ tọa độ (CRS)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      crsService.currentCrs.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // CRS list grouped by region
            Expanded(
              child: ListView(
                controller: scrollController,
                children: grouped.entries.map((entry) {
                  return ExpansionTile(
                    title: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    initiallyExpanded: entry.key == 'Toàn cầu',
                    children: entry.value.map((crs) {
                      final isSelected = crsService.currentCrs.code == crs.code;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(
                          crs.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
                        subtitle: Text(crs.description, style: const TextStyle(fontSize: 12)),
                        dense: true,
                        onTap: () {
                          crsService.setCrs(crs);
                          Navigator.pop(ctx);
                          _showSnackBar('✅ Đã chọn: ${crs.name}');
                        },
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Export Data dialog
  // -------------------------------------------------------------------------

  void _showExportDialog() {
    if (_layers.isEmpty) {
      _showSnackBar('Chưa có lớp nào để xuất');
      return;
    }

    final formats = [
      {'icon': Icons.code, 'name': 'GeoJSON', 'desc': 'Tất cả lớp (.geojson)', 'key': 'geojson_all'},
      {'icon': Icons.map, 'name': 'KML', 'desc': 'Google Earth (.kml)', 'key': 'kml'},
      {'icon': Icons.route, 'name': 'GPX', 'desc': 'GPS Track (.gpx)', 'key': 'gpx'},
      {'icon': Icons.table_chart, 'name': 'CSV', 'desc': 'Excel (.csv)', 'key': 'csv'},
      {'icon': Icons.archive, 'name': 'KMZ', 'desc': 'KML nén (.kmz)', 'key': 'kmz'},
      {'icon': Icons.inventory_2, 'name': 'LVTField', 'desc': 'Gói dự án (.lvtfield)', 'key': 'lvtfield'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.file_upload, color: AppColors.success),
                SizedBox(width: 8),
                Text('Xuất dữ liệu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Dự án: ${_project?.name ?? ""}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 12),
            ...formats.map((f) => ListTile(
              leading: Icon(f['icon'] as IconData, color: AppColors.primary),
              title: Text(f['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(f['desc'] as String, style: const TextStyle(fontSize: 12)),
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () {
                Navigator.pop(ctx);
                _executeExport(f['key'] as String);
              },
            )),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Future<void> _executeExport(String formatKey) async {
    final projectId = widget.projectId;
    // Get username from shared prefs or default
    const username = 'user'; // TODO: get from auth

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Đang xuất dữ liệu...'),
              ],
            ),
          ),
        ),
      ),
    );

    final exportService = ExportService();
    ExportResult result;

    try {
      switch (formatKey) {
        case 'geojson_all':
          result = await exportService.exportAllLayersGeoJson(
            projectId: projectId, username: username,
          );
          break;
        case 'kml':
          if (_layers.isEmpty) {
            result = const ExportResult(success: false, errorMessage: 'Không có lớp');
          } else {
            result = await exportService.exportKML(
              projectId: projectId, layerId: _layers.first.id, username: username,
            );
          }
          break;
        case 'gpx':
          if (_layers.isEmpty) {
            result = const ExportResult(success: false, errorMessage: 'Không có lớp');
          } else {
            result = await exportService.exportGPX(
              projectId: projectId, layerId: _layers.first.id, username: username,
            );
          }
          break;
        case 'csv':
          if (_layers.isEmpty) {
            result = const ExportResult(success: false, errorMessage: 'Không có lớp');
          } else {
            result = await exportService.exportCSV(
              projectId: projectId, layerId: _layers.first.id, username: username,
            );
          }
          break;
        case 'kmz':
          if (_layers.isEmpty) {
            result = const ExportResult(success: false, errorMessage: 'Không có lớp');
          } else {
            result = await exportService.exportKMZ(
              projectId: projectId, layerId: _layers.first.id, username: username,
            );
          }
          break;
        case 'lvtfield':
          result = await exportService.exportProjectPackage(
            projectId: projectId, username: username,
          );
          break;
        default:
          result = const ExportResult(success: false, errorMessage: 'Định dạng chưa hỗ trợ');
      }
    } catch (e) {
      result = ExportResult(success: false, errorMessage: 'Lỗi: $e');
    }

    // Close loading
    if (mounted) Navigator.pop(context);

    if (result.success) {
      _showSnackBar('✅ Đã xuất: ${result.filePath?.split('/').last ?? 'file'}');
    } else {
      _showSnackBar('❌ ${result.errorMessage ?? "Lỗi không xác định"}');
    }
  }

  // -------------------------------------------------------------------------
  // Build — main tree
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ---- Map ----
          _buildMap(),

          // ---- Navigation overlay ----
          if (_navigationMode && _currentPosition != null && _navigationTarget != null)
            NavigationOverlay(
              currentPosition: _currentPosition!.latLng,
              targetPosition: _navigationTarget!,
              targetName: _navigationTargetName,
              onStop: _stopNavigation,
            ),

          // ---- Top bar (hide during navigation & vertex edit) ----
          if (!_navigationMode && !_vertexEditMode) _buildTopBar(),

          // ---- Scale bar (bottom-left, above coordinates) ----
          if (!_vertexEditMode && _mapReady) _buildScaleBar(),

          // ---- Speed indicator (bottom-left, above scale bar) ----
          if (!_vertexEditMode && _currentPosition?.speed != null) _buildSpeedIndicator(),

          // ---- Compass (top-right) ----
          if (!_vertexEditMode && _mapReady) _buildCompass(),

          // ---- GPS accuracy badge (right side) ----
          if (!_vertexEditMode) _buildGpsBadge(),


          // ---- Left-side quick toolbar ----
          if (!_vertexEditMode) _buildLeftToolbar(),

          // ---- Right-side map controls ----
          if (_mapReady) _buildMapControls(),

          // ---- Center crosshair (always visible) ----
          if (!_vertexEditMode) _buildCrosshair(),

          // ---- Bottom action bar (only for idle mode with active layer) ----
          if (!_vertexEditMode && _drawingMode == DrawingMode.idle && _activeLayerId != null) _buildBottomBar(),

          // ---- Floating digitizing toolbar (compact, above coordinate bar) ----
          if (!_vertexEditMode && _drawingMode != DrawingMode.idle) _buildFloatingDigitizeBar(),

          // ---- Vertex edit toolbar ----
          if (_vertexEditMode) _buildVertexEditToolbarWidget(),

          // ---- Coordinate display (bottom-left, always visible) ----
          if (!_vertexEditMode && _mapReady) _buildCoordinateDisplay(),

          // ---- Track recording indicator ----
          if (_trackRecording || _trackPaused) _buildTrackRecordingOverlay(),

          // ---- GPS Track FAB (bottom-right, always visible when not recording) ----
          if (!_trackRecording && !_trackPaused && !_vertexEditMode && _mapReady)
            _buildGpsTrackFab(),

          // ---- Layer panel (slide-up) ----
          if (_showLayerPanel && !_vertexEditMode) _buildLayerPanel(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Map widget
  // -------------------------------------------------------------------------

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _kDefaultCenter,
        initialZoom: AppSizes.defaultZoom,
        minZoom: AppSizes.minZoom,
        maxZoom: AppSizes.maxZoom,
        // Disable map drag during vertex edit so markers receive pan gestures
        interactionOptions: InteractionOptions(
          flags: _vertexEditMode
              ? InteractiveFlag.pinchZoom | InteractiveFlag.pinchMove | InteractiveFlag.doubleTapZoom
              : InteractiveFlag.all,
        ),
        onTap: _onMapTap,
        onMapReady: () {
          setState(() => _mapReady = true);
        },
        onPositionChanged: (pos, hasGesture) {
          if (!_mapReady) return;
          // Track rotation for compass
          try {
            final rot = _mapController.camera.rotation;
            if (rot != _mapRotation) {
              setState(() => _mapRotation = rot);
            }
          } catch (_) {}
          // Disable auto-center when user pans manually
          if (hasGesture && _autoCenter) {
            setState(() => _autoCenter = false);
          }
        },
      ),
      children: [
        // Base tile layer
        _buildTileLayer(),

        // Rendered features from database
        ..._buildFeatureLayers(),

        // Vertex edit overlay (above feature layers)
        ..._buildVertexEditLayers(),

        // Active drawing overlay
        if (_vertices.isNotEmpty && !_vertexEditMode) _buildDrawingOverlay(),

        // Live GPS track while recording
        if ((_trackRecording || _trackPaused) && _trackPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _trackPoints,
                color: _trackColor,
                strokeWidth: _trackWidth,
              ),
            ],
          ),

        // GPS position marker
        if (_currentPosition != null) _buildGpsMarker(),

        // Navigation line (bird's eye)
        if (_navigationMode && _currentPosition != null && _navigationTarget != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_currentPosition!.latLng, _navigationTarget!],
                color: const Color(0xFFFF5722),
                strokeWidth: 3,
                pattern: StrokePattern.dashed(segments: [10, 6]),
              ),
            ],
          ),
      ],
    );
  }

  /// Build tile layer based on selected source
  Widget _buildTileLayer() {
    switch (_tileSource) {
      case TileSource.osm:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.lvtfield.app',
          maxZoom: 19,
          keepBuffer: 8,
          panBuffer: 3,
          tileSize: 256,
        );
      case TileSource.satellite:
        return TileLayer(
          urlTemplate:
              'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.lvtfield.app',
          maxZoom: 20,
          keepBuffer: 8,
          panBuffer: 3,
          tileSize: 256,
        );
    }
  }

  // -------------------------------------------------------------------------
  // Feature layer rendering
  // -------------------------------------------------------------------------

  /// Build map layers for all visible features
  List<Widget> _buildFeatureLayers() {
    // NOTE: No caching — labels are viewport-dependent (only visible features rendered)

    final widgets = <Widget>[];

    for (final layer in _layers) {
      if (!layer.isVisible) continue;

      // GeoTIFF overlay layers — render as image overlay
      if (layer.sourceFormat == 'tiff') {
        final overlayPath = layer.styleConfig['overlayPath'] as String?;
        final boundsMap = layer.styleConfig['overlayBounds'] as Map<String, dynamic>?;
        if (overlayPath != null && boundsMap != null) {
          final file = File(overlayPath);
          if (file.existsSync()) {
            // Read brightness/contrast/saturation from styleConfig
            final brightness = (layer.styleConfig['brightness'] as num?)?.toDouble() ?? 0;
            final contrast = (layer.styleConfig['contrast'] as num?)?.toDouble() ?? 0;
            final saturation = (layer.styleConfig['saturation'] as num?)?.toDouble() ?? 0;

            Widget overlayWidget = OverlayImageLayer(
              overlayImages: [
                OverlayImage(
                  bounds: LatLngBounds(
                    LatLng(
                      (boundsMap['south'] as num).toDouble(),
                      (boundsMap['west'] as num).toDouble(),
                    ),
                    LatLng(
                      (boundsMap['north'] as num).toDouble(),
                      (boundsMap['east'] as num).toDouble(),
                    ),
                  ),
                  imageProvider: FileImage(file),
                  opacity: layer.opacity,
                ),
              ],
            );

            // Apply brightness/contrast/saturation via combined ColorFilter matrix
            if (brightness != 0 || contrast != 0 || saturation != 0) {
              final con = 1.0 + contrast / 100.0;
              final bri = brightness * 2.55;
              final ct = (1.0 - con) * 128.0;
              final sat = 1.0 + saturation / 100.0;
              // Luminance coefficients (BT.709)
              const lr = 0.2126, lg = 0.7152, lb = 0.0722;
              final sr = lr * (1 - sat);
              final sg = lg * (1 - sat);
              final sb = lb * (1 - sat);
              // Combined: Contrast * Saturation matrix
              overlayWidget = ColorFiltered(
                colorFilter: ColorFilter.matrix(<double>[
                  con * (sr + sat), con * sg,         con * sb,         0, bri + ct,
                  con * sr,         con * (sg + sat), con * sb,         0, bri + ct,
                  con * sr,         con * sg,         con * (sb + sat), 0, bri + ct,
                  0,                0,                0,                1, 0,
                ]),
                child: overlayWidget,
              );
            }

            widgets.add(overlayWidget);
          }
        }
        continue; // Skip vector rendering for overlay layers
      }

      // MBTiles overlay layers — render as TileLayer from SQLite
      if (layer.sourceFormat == 'mbtiles') {
        final dbPath = layer.styleConfig['dbPath'] as String?;
        if (dbPath != null) {
          // Get or create tile provider for this layer
          var provider = _mbtilesProviders[layer.id];
          if (provider == null) {
            provider = MBTilesTileProvider(dbPath: dbPath);
            _mbtilesProviders[layer.id] = provider;
            // Initialize async — will render on next build
            provider.init().then((_) {
              if (mounted) setState(() {});
            });
          }

          final minZoom = (layer.styleConfig['minZoom'] as num?)?.toDouble() ?? 0;
          final maxZoom = (layer.styleConfig['maxZoom'] as num?)?.toDouble() ?? 22;
          final maxNativeZoom = (layer.styleConfig['maxZoom'] as num?)?.toInt() ?? 22;

          widgets.add(
            Opacity(
              opacity: layer.opacity,
              child: TileLayer(
                tileProvider: provider,
                minZoom: minZoom,
                maxZoom: maxZoom,
                maxNativeZoom: maxNativeZoom,
                tileSize: 256,
                errorTileCallback: (tile, error, stackTrace) {
                  // Silently ignore tile errors
                },
              ),
            ),
          );
        }
        continue;
      }

      final features = _featuresByLayer[layer.id] ?? [];
       if (features.isEmpty) continue;

      // Get visible bounds for label viewport culling (performance)
      final currentZoom = _mapController.camera.zoom;
      final visibleBounds = _mapController.camera.visibleBounds;

      switch (layer.geometryType) {
        case GeometryType.polygon:
          widgets.add(PolygonLayer(
            polygons: features
                .where((f) => f.coordinates.length >= 3)
                .map((f) => Polygon(
                      points: f.coordinates,
                      color: layer.fillColor.withValues(alpha: (layer.styleConfig['fillOpacity'] as num?)?.toDouble() ?? layer.opacity),
                      borderColor: layer.strokeColor,
                      borderStrokeWidth: layer.strokeWidth,
                    ))
                .toList(),
          ));
          // Add labels for polygons (only at zoom >= labelMinZoom, viewport only)
          if (layer.labelsEnabled && currentZoom >= layer.labelMinZoom) {
            widgets.add(MarkerLayer(
              markers: features
                  .where((f) => f.coordinates.length >= 3 && visibleBounds.contains(f.centroid))
                  .map((f) => _buildLabelMarker(f, layer))
                  .toList(),
            ));
          }
          break;

        case GeometryType.line:
          widgets.add(PolylineLayer(
            polylines: features
                .where((f) => f.coordinates.length >= 2)
                .map((f) => Polyline(
                      points: f.coordinates,
                      color: layer.strokeColor,
                      strokeWidth: layer.strokeWidth,
                    ))
                .toList(),
          ));
          // Add labels for lines (only at zoom >= labelMinZoom, viewport only)
          if (layer.labelsEnabled && currentZoom >= layer.labelMinZoom) {
            widgets.add(MarkerLayer(
              markers: features
                  .where((f) => f.coordinates.length >= 2 && visibleBounds.contains(f.centroid))
                  .map((f) => _buildLabelMarker(f, layer))
                  .toList(),
            ));
          }
          break;

        case GeometryType.point:
          widgets.add(CircleLayer(
            circles: features
                .where((f) => f.coordinates.isNotEmpty)
                .map((f) => CircleMarker(
                      point: f.coordinates.first,
                      radius: layer.pointSize / 2,
                      color: layer.pointColor,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2,
                    ))
                .toList(),
          ));
          // Add labels for points (only at zoom >= labelMinZoom, viewport only)
          if (layer.labelsEnabled && currentZoom >= layer.labelMinZoom) {
            widgets.add(MarkerLayer(
              markers: features
                  .where((f) => f.coordinates.isNotEmpty && visibleBounds.contains(f.centroid))
                  .map((f) => _buildLabelMarker(f, layer))
                  .toList(),
            ));
          }
          break;
      }
    }

    _featureLayerCache = widgets;
    return widgets;
  }

  // -------------------------------------------------------------------------
  // Label rendering
  // -------------------------------------------------------------------------

  /// Build a text label marker at feature centroid
  Marker _buildLabelMarker(FeatureModel feature, LayerModel layer) {
    // Build label text from configured fields
    final parts = <String>[];
    final field1 = layer.labelField;
    if (field1 != null && field1.isNotEmpty) {
      final val = feature.attributes[field1]?.toString() ?? '';
      if (val.isNotEmpty) parts.add(val);
    }
    final field2 = layer.labelField2;
    if (field2 != null && field2.isNotEmpty) {
      final val = feature.attributes[field2]?.toString() ?? '';
      if (val.isNotEmpty) {
        final suffix = layer.labelSuffix2 ?? '';
        parts.add('$val$suffix');
      }
    }
    final labelText = parts.join('\n');

    return Marker(
      point: feature.centroid,
      width: 120,
      height: 50,
      child: IgnorePointer(
        child: Center(
          child: Text(
            labelText,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: layer.labelFontSize,
              fontWeight: FontWeight.w700,
              color: layer.labelColor,
              shadows: const [
                Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54),
                Shadow(offset: Offset(-0.5, -0.5), blurRadius: 2, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Drawing overlay (in-progress vertices / edges)
  // -------------------------------------------------------------------------

  Widget _buildDrawingOverlay() {
    final children = <Widget>[];

    // Draw edges between vertices (for line and polygon modes)
    if (_vertices.length >= 2 &&
        (_drawingMode == DrawingMode.line ||
            _drawingMode == DrawingMode.polygon)) {
      children.add(PolylineLayer(
        polylines: [
          Polyline(
            points: _vertices,
            color: AppColors.vertexColor,
            strokeWidth: 3.0,
          ),
        ],
      ));
    }

    // Dashed closing line from last vertex to first (polygon only)
    if (_drawingMode == DrawingMode.polygon && _vertices.length >= 3) {
      children.add(PolylineLayer(
        polylines: [
          Polyline(
            points: [_vertices.last, _vertices.first],
            color: AppColors.vertexColor.withValues(alpha: 0.5),
            strokeWidth: 2.0,
            pattern: StrokePattern.dashed(segments: const [8, 6]),
          ),
        ],
      ));
    }

    // Vertex markers
    children.add(CircleLayer(
      circles: _vertices
          .map((v) => CircleMarker(
                point: v,
                radius: 6,
                color: AppColors.vertexColor,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ))
          .toList(),
    ));

    return Stack(children: children);
  }

  // -------------------------------------------------------------------------
  // GPS marker on the map
  // -------------------------------------------------------------------------

  Widget _buildGpsMarker() {
    final pos = _currentPosition!;
    return CircleLayer(
      circles: [
        // Accuracy circle
        CircleMarker(
          point: pos.latLng,
          radius: pos.accuracy,
          useRadiusInMeter: true,
          color: AppColors.gpsCircleFill,
          borderColor: AppColors.gpsCircleStroke,
          borderStrokeWidth: 1,
        ),
        // Blue dot
        CircleMarker(
          point: pos.latLng,
          radius: 7,
          color: AppColors.gpsCircleStroke,
          borderColor: Colors.white,
          borderStrokeWidth: 2.5,
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Top bar with back button & project name
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + AppSizes.xs,
          left: AppSizes.sm,
          right: AppSizes.sm,
          bottom: AppSizes.xs,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.5),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Back button
            _TopIconButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            // Project name (compact)
            Expanded(
              child: Text(
                _project?.name ?? '',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Basemap toggle
            _TopIconButton(
              icon: _tileSource == TileSource.osm
                  ? Icons.satellite_alt
                  : Icons.map_outlined,
              onTap: () => setState(() {
                _tileSource = _tileSource == TileSource.osm
                    ? TileSource.satellite
                    : TileSource.osm;
              }),
              color: const Color(0xFFFFD600),
            ),
            const SizedBox(width: 4),
            // Search / Zoom to layer
            _TopIconButton(
              icon: Icons.search,
              onTap: () {
                if (_layers.isEmpty) {
                  _showSnackBar('Chưa có lớp nào.');
                  return;
                }
                if (_layers.length == 1) {
                  _zoomToLayer(_layers.first);
                  return;
                }
                // Show layer picker for zoom
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Zoom tới lớp',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        ..._layers.map((l) => ListTile(
                          dense: true,
                          leading: Icon(
                            l.geometryType == GeometryType.point
                                ? Icons.location_on
                                : l.geometryType == GeometryType.line
                                    ? Icons.timeline
                                    : Icons.pentagon,
                            color: l.displayColor,
                            size: 22,
                          ),
                          title: Text(l.name, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${(_featuresByLayer[l.id] ?? []).length} đối tượng',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _zoomToLayer(l);
                          },
                        )),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            // Layers
            _TopIconButton(
              icon: Icons.layers,
              onTap: () => setState(() => _showLayerPanel = true),
              color: const Color(0xFF64FFDA),
            ),
            const SizedBox(width: 4),
            // Cloud sync
            _TopIconButton(
              icon: Icons.cloud_sync,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              ),
              color: const Color(0xFF81D4FA),
            ),
            const SizedBox(width: 4),
            // Settings
            _TopIconButton(
              icon: Icons.settings,
              onTap: () => context.push('/settings'),
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // GPS accuracy badge
  // -------------------------------------------------------------------------

  Widget _buildGpsBadge() {
    final pos = _currentPosition;
    final Color bgColor;
    final IconData gpsIcon;

    if (!_gpsEnabled) {
      bgColor = Colors.grey.shade600;
      gpsIcon = Icons.gps_off;
    } else if (_gpsPermissionDenied) {
      bgColor = AppColors.error;
      gpsIcon = Icons.gps_off;
    } else if (pos == null) {
      bgColor = AppColors.gpsPoor;
      gpsIcon = Icons.gps_not_fixed;
    } else {
      gpsIcon = Icons.gps_fixed;
      switch (pos.quality) {
        case GpsQuality.good:
          bgColor = AppColors.gpsGood;
          break;
        case GpsQuality.moderate:
          bgColor = AppColors.gpsModerate;
          break;
        case GpsQuality.poor:
        case GpsQuality.noSignal:
          bgColor = AppColors.gpsPoor;
          break;
      }
    }

    // Estimate satellite count from accuracy
    final satEstimate = pos == null
        ? '0'
        : pos.accuracy < 3
            ? '12+'
            : pos.accuracy < 5
                ? '8-12'
                : pos.accuracy < 10
                    ? '5-8'
                    : '3-5';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 110,
      right: AppSizes.md,
      child: GestureDetector(
        onTap: _toggleGps,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bgColor.withValues(alpha: 0.6), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Satellite icon + count
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.satellite_alt, color: bgColor, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    satEstimate,
                    style: TextStyle(
                      color: bgColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Accuracy
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(gpsIcon, color: Colors.white, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    _gpsStatusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// GPS Track recording button (below satellite panel)
  Widget _buildTrackRecordBtn() {
    final isActive = _trackRecording || _trackPaused;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 155,
      right: AppSizes.md,
      child: GestureDetector(
        onTap: () {
          if (isActive) {
            // Already recording — do nothing, panel is visible at bottom
            return;
          }
          _showTrackStartDialog();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.red.withValues(alpha: 0.75)
                : Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? Colors.red : Colors.white24,
              width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? Icons.fiber_manual_record : Icons.route,
                color: isActive ? Colors.white : Colors.white70,
                size: 13),
              const SizedBox(width: 4),
              Text(
                isActive ? 'Ghi...' : 'Ghi vết',
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Left-side quick toolbar (collapsible)
  // -------------------------------------------------------------------------

  /// Get the first active layer, or first layer if none active
  LayerModel? get _toolbarTargetLayer {
    if (_layers.isEmpty) return null;
    if (_activeLayerId != null) {
      return _layers.cast<LayerModel?>().firstWhere(
        (l) => l!.id == _activeLayerId,
        orElse: () => _layers.first,
      );
    }
    return _layers.first;
  }

  Widget _buildLeftToolbar() {
    final topPadding = MediaQuery.of(context).padding.top + 90;

    return Positioned(
      top: topPadding,
      left: AppSizes.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle button
          _ToolbarToggleButton(
            isExpanded: _showLeftToolbar,
            onTap: () => setState(() => _showLeftToolbar = !_showLeftToolbar),
          ),

          // Expanded toolbar items
          if (_showLeftToolbar)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolbarItem(
                    icon: Icons.add_location_alt,
                    color: Colors.green.shade700,
                    label: 'Thêm',
                    onTap: () {
                      final layer = _toolbarTargetLayer;
                      if (layer == null) {
                        _showSnackBar('Chưa có lớp nào. Hãy nhập dữ liệu trước.');
                        return;
                      }
                      setState(() => _showLeftToolbar = false);
                      _startAddFeature(layer);
                    },
                  ),
                  _ToolbarItem(
                    icon: Icons.edit_location_alt,
                    color: Colors.orange.shade700,
                    label: 'Chỉnh sửa',
                    onTap: () {
                      final layer = _toolbarTargetLayer;
                      if (layer == null) {
                        _showSnackBar('Chưa có lớp nào.');
                        return;
                      }
                      setState(() => _showLeftToolbar = false);
                      _startEditLayer(layer);
                    },
                  ),

                  _ToolbarItem(
                    icon: Icons.palette,
                    color: Colors.purple.shade600,
                    label: 'Kiểu hiển thị',
                    onTap: () {
                      final layer = _toolbarTargetLayer;
                      if (layer == null) {
                        _showSnackBar('Chưa có lớp nào.');
                        return;
                      }
                      setState(() => _showLeftToolbar = false);
                      _editLayerStyle(layer);
                    },
                  ),

                  const Divider(height: 1, indent: 8, endIndent: 8),
                  _ToolbarItem(
                    icon: Icons.satellite_alt,
                    color: Colors.teal.shade600,
                    label: 'GPS & La bàn',
                    onTap: () {
                      setState(() => _showLeftToolbar = false);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GpsCompassScreen(gpsService: _gpsService),
                        ),
                      );
                    },
                  ),

                ],
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Compass widget (rotates with map)
  // -------------------------------------------------------------------------

  Widget _buildCompass() {
    final topPadding = MediaQuery.of(context).padding.top + 56;
    return Positioned(
      top: topPadding,
      right: AppSizes.md,
      child: GestureDetector(
        onTap: () {
          // Reset map rotation to north
          _mapController.rotate(0);
          setState(() => _mapRotation = 0);
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Transform.rotate(
            angle: -_mapRotation * (math.pi / 180),
            child: CustomPaint(
              size: const Size(48, 48),
              painter: _CompassPainter(),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Inline Track Recording on Map
  // -------------------------------------------------------------------------

  // Track profiles
  static const _trackProfiles = [
    {'name': 'Đi bộ', 'icon': 'directions_walk', 'dist': 5},
    {'name': 'Xe đạp', 'icon': 'pedal_bike', 'dist': 8},
    {'name': 'Xe máy', 'icon': 'two_wheeler', 'dist': 10},
    {'name': 'Ô tô', 'icon': 'directions_car', 'dist': 15},
    {'name': 'Thuyền', 'icon': 'sailing', 'dist': 20},
    {'name': 'Chính xác', 'icon': 'precision_manufacturing', 'dist': 1},
  ];

  static const _trackProfileIcons = [
    Icons.directions_walk, Icons.pedal_bike, Icons.two_wheeler,
    Icons.directions_car, Icons.sailing, Icons.precision_manufacturing,
  ];

  static const _trackColors = [
    Color(0xFFFF5722), Color(0xFFE91E63), Color(0xFF2196F3),
    Color(0xFF4CAF50), Color(0xFF9C27B0), Color(0xFFFF9800),
    Color(0xFF00BCD4), Color(0xFFF44336), Color(0xFFFFEB3B),
    Color(0xFF795548),
  ];

  void _showTrackStartDialog() {
    final activeLayer = _activeLayerId != null
        ? _layers.where((l) => l.id == _activeLayerId).firstOrNull
        : null;

    // Local state for dialog
    var selectedGeom = _trackGeomType;
    var profileIdx = _trackProfileIdx;
    var distFilter = _trackDistFilter;
    var trackColor = _trackColor;
    var trackWidth = _trackWidth;
    var timeInterval = _trackTimeInterval;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final profile = _trackProfiles[profileIdx];
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: 14, right: 14, top: 10,
                bottom: MediaQuery.of(ctx).padding.bottom + 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(child: Container(
                    width: 32, height: 3.5,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                  )),

                  // Title
                  Row(children: [
                    Icon(Icons.route, color: Colors.white60, size: 16),
                    const SizedBox(width: 6),
                    const Text('Thiết lập ghi vết',
                        style: TextStyle(color: Colors.white, fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),

                  // ── 1. Phương tiện (compact 2 rows x 3) ──
                  _sheetLabel('Phương tiện'),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5, runSpacing: 5,
                    children: List.generate(_trackProfiles.length, (i) {
                      final p = _trackProfiles[i];
                      final sel = i == profileIdx;
                      return GestureDetector(
                        onTap: () => ss(() {
                          profileIdx = i;
                          distFilter = p['dist'] as int;
                        }),
                        child: Container(
                          width: (MediaQuery.of(ctx).size.width - 56) / 3,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: sel
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                              color: sel ? Colors.white54 : Colors.white12,
                              width: sel ? 1.5 : 1),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_trackProfileIcons[i],
                                  color: sel ? Colors.white : Colors.white38,
                                  size: 16),
                              const SizedBox(height: 2),
                              Text(p['name'] as String,
                                  style: TextStyle(fontSize: 10,
                                      color: sel ? Colors.white : Colors.white38,
                                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),

                  // ── 2. Khoảng cách + Thời gian (2 rows compact) ──
                  Row(children: [
                    // Distance
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetLabel('Khoảng cách'),
                        SizedBox(height: 24, child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.white70,
                            thumbColor: Colors.white,
                            inactiveTrackColor: Colors.white12,
                            overlayColor: Colors.white.withValues(alpha: 0.1),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            trackHeight: 2,
                          ),
                          child: Slider(
                            value: distFilter.toDouble(),
                            min: 1, max: 50, divisions: 49,
                            onChanged: (v) => ss(() => distFilter = v.round()),
                          ),
                        )),
                        Center(child: Text('${distFilter}m',
                            style: const TextStyle(color: Colors.white70, fontSize: 11))),
                      ],
                    )),
                    const SizedBox(width: 12),
                    // Time interval
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetLabel('Thời gian'),
                        SizedBox(height: 24, child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.white70,
                            thumbColor: Colors.white,
                            inactiveTrackColor: Colors.white12,
                            overlayColor: Colors.white.withValues(alpha: 0.1),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            trackHeight: 2,
                          ),
                          child: Slider(
                            value: timeInterval.toDouble(),
                            min: 0, max: 60, divisions: 12,
                            onChanged: (v) => ss(() => timeInterval = v.round()),
                          ),
                        )),
                        Center(child: Text(
                            timeInterval == 0 ? 'Tắt' : '${timeInterval}s',
                            style: const TextStyle(color: Colors.white70, fontSize: 11))),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 8),

                  // ── 3. Màu + Độ rộng (1 row) ──
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Colors
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetLabel('Màu vệt'),
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: _trackColors.map((c) {
                          final sel = c.value == trackColor.value;
                          return GestureDetector(
                            onTap: () => ss(() => trackColor = c),
                            child: Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: sel ? Border.all(color: Colors.white, width: 2) : null,
                              ),
                            ),
                          );
                        }).toList()),
                      ],
                    )),
                    // Width
                    SizedBox(width: 100, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetLabel('Độ rộng'),
                        SizedBox(height: 24, child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: trackColor.withValues(alpha: 0.7),
                            thumbColor: trackColor,
                            inactiveTrackColor: Colors.white12,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            trackHeight: 2,
                          ),
                          child: Slider(
                            value: trackWidth,
                            min: 1, max: 8, divisions: 7,
                            onChanged: (v) => ss(() => trackWidth = v),
                          ),
                        )),
                        Center(child: Text('${trackWidth.toStringAsFixed(0)}px',
                            style: const TextStyle(color: Colors.white70, fontSize: 11))),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 8),

                  // ── 4. Loại hình học (compact inline) ──
                  Row(children: [
                    _sheetLabel('Hình học:  '),
                    _compactGeomChip(ss, selectedGeom, GeometryType.line,
                        Icons.show_chart, 'Đường', (g) => selectedGeom = g),
                    const SizedBox(width: 6),
                    _compactGeomChip(ss, selectedGeom, GeometryType.polygon,
                        Icons.pentagon, 'Vùng', (g) => selectedGeom = g),
                    const Spacer(),
                    // Active layer badge
                    if (activeLayer != null) ...[
                      Icon(Icons.layers, color: Colors.green, size: 14),
                      const SizedBox(width: 4),
                      Flexible(child: Text(activeLayer.name,
                          style: const TextStyle(color: Colors.green, fontSize: 10),
                          overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                  const SizedBox(height: 12),

                  // ── Start button ──
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _trackProfileIdx = profileIdx;
                        _trackDistFilter = distFilter;
                        _trackColor = trackColor;
                        _trackWidth = trackWidth;
                        _trackTimeInterval = timeInterval;
                        _trackProfileName = profile['name'] as String;
                        _startTrackRecording(selectedGeom);
                      },
                      icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                      label: Text(
                        'Bắt đầu · ${profile['name']}',
                        style: const TextStyle(color: Colors.white, fontSize: 13,
                            fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(title,
          style: const TextStyle(color: Colors.white54, fontSize: 12,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _compactGeomChip(
    void Function(void Function()) ss,
    GeometryType current,
    GeometryType type,
    IconData icon,
    String label,
    void Function(GeometryType) onSet,
  ) {
    final sel = current == type;
    return GestureDetector(
      onTap: () => ss(() => onSet(type)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: sel ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: sel ? Colors.white54 : Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: sel ? Colors.white : Colors.white38, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            fontSize: 11,
            color: sel ? Colors.white : Colors.white38,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget _sheetGeomOption(
    BuildContext ctx,
    void Function(void Function()) setSheetState,
    GeometryType current,
    GeometryType type,
    IconData icon,
    String label,
    void Function(GeometryType) onSet,
  ) {
    final selected = current == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setSheetState(() => onSet(type)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: selected ? Colors.white54 : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.white38, size: 24),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Colors.white38,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackGeomOption(
    BuildContext ctx,
    void Function(void Function()) setDlgState,
    GeometryType current,
    GeometryType type,
    IconData icon,
    String label,
    void Function(GeometryType) onSet,
  ) {
    final selected = current == type;
    return GestureDetector(
      onTap: () => setDlgState(() => onSet(type)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
          border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.primary : Colors.grey, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? AppColors.primary : Colors.grey,
            )),
          ],
        ),
      ),
    );
  }

  void _startTrackRecording(GeometryType geomType) {
    setState(() {
      _trackRecording = true;
      _trackPaused = false;
      _trackPoints = [];
      _trackDistance = 0;
      _trackStartTime = DateTime.now();
      _trackLastPos = null;
      _trackGeomType = geomType;
    });

    _trackGpsSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _trackDistFilter,
      ),
    ).listen(_onTrackGpsUpdate);

    // Start foreground service for background GPS
    _startTrackForegroundService();

    // Timer to refresh UI every second (duration counter)
    _trackRefreshTimer?.cancel();
    _trackRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) { if (mounted && _trackRecording) setState(() {}); },
    );

    _showSnackBar('🔴 Đang ghi vết GPS · $_trackProfileName');

    // Time-interval based recording (if enabled)
    if (_trackTimeInterval > 0) {
      _trackIntervalTimer?.cancel();
      _trackIntervalTimer = Timer.periodic(
        Duration(seconds: _trackTimeInterval),
        (_) async {
          if (!_trackRecording || _trackPaused) return;
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high),
            );
            _onTrackGpsUpdate(pos);
          } catch (_) {}
        },
      );
    }
  }

  Future<void> _startTrackForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'lvtfield_track',
        channelName: 'Ghi vết GPS',
        channelDescription: 'Ghi vết GPS đang hoạt động',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    await FlutterForegroundTask.startService(
      notificationTitle: '🔴 Đang ghi vết GPS · $_trackProfileName',
      notificationText: 'LVTField đang ghi vết...',
    );
  }

  Future<void> _stopTrackForegroundService() async {
    await FlutterForegroundTask.stopService();
  }

  void _onTrackGpsUpdate(Position pos) {
    if (!_trackRecording || _trackPaused) return;

    final point = LatLng(pos.latitude, pos.longitude);

    if (_trackLastPos != null) {
      final dist = Geolocator.distanceBetween(
        _trackLastPos!.latitude, _trackLastPos!.longitude,
        pos.latitude, pos.longitude,
      );
      if (dist < _trackDistFilter) return; // minimum distance filter
      _trackDistance += dist;
    }

    setState(() {
      _trackPoints.add(point);
      _trackLastPos = pos;
    });
  }

  void _pauseTrackRecording() {
    setState(() => _trackPaused = true);
    _trackGpsSub?.pause();
    FlutterForegroundTask.updateService(
      notificationTitle: '⏸️ Tạm dừng ghi vết',
      notificationText: '${_trackPoints.length} điểm | ${(_trackDistance / 1000).toStringAsFixed(2)} km',
    );
  }

  void _resumeTrackRecording() {
    setState(() => _trackPaused = false);
    _trackGpsSub?.resume();
    FlutterForegroundTask.updateService(
      notificationTitle: '🔴 Đang ghi vết GPS',
      notificationText: '${_trackPoints.length} điểm...',
    );
  }

  Future<void> _saveTrackRecording() async {
    _trackGpsSub?.cancel();
    _trackGpsSub = null;
    _trackRefreshTimer?.cancel();
    _trackRefreshTimer = null;
    _trackIntervalTimer?.cancel();
    _trackIntervalTimer = null;
    await _stopTrackForegroundService();

    if (_trackPoints.length < 2) {
      setState(() {
        _trackRecording = false;
        _trackPaused = false;
      });
      _showSnackBar('⚠️ Cần ít nhất 2 điểm để lưu');
      return;
    }

    // Get active layer info
    final activeLayer = _activeLayerId != null
        ? _layers.where((l) => l.id == _activeLayerId).firstOrNull
        : null;

    // Ask save mode
    final controller = TextEditingController(
      text: 'Track_${DateTime.now().day}.${DateTime.now().month}',
    );
    bool saveToActive = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Lưu vết GPS'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activeLayer != null) ...[
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        dense: true,
                        title: const Text('Tạo layer mới', style: TextStyle(fontSize: 14)),
                        value: false,
                        groupValue: saveToActive,
                        onChanged: (v) => setDlgState(() => saveToActive = v!),
                        activeColor: AppColors.primary,
                      ),
                      RadioListTile<bool>(
                        dense: true,
                        title: Text('Thêm vào "${activeLayer.name}"',
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                        subtitle: const Text('Layer đang kích hoạt',
                            style: TextStyle(fontSize: 11)),
                        value: true,
                        groupValue: saveToActive,
                        onChanged: (v) => setDlgState(() => saveToActive = v!),
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!saveToActive)
                TextField(
                  controller: controller,
                  autofocus: activeLayer == null,
                  decoration: InputDecoration(
                    labelText: 'Tên layer',
                    hintText: 'Ví dụ: Khảo sát khu A',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              if (saveToActive)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_location_alt, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Vết GPS → đối tượng mới trong "${activeLayer!.name}"',
                            style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(saveToActive ? Icons.add : Icons.save, size: 16, color: Colors.white),
              label: Text(
                saveToActive ? 'Thêm vào layer' : 'Tạo layer mới',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: saveToActive ? Colors.green : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      // Resume if cancelled
      _trackGpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
      ).listen(_onTrackGpsUpdate);
      return;
    }

    final coords = List<LatLng>.from(_trackPoints);
    if (_trackGeomType == GeometryType.polygon && coords.length >= 3) {
      if (coords.first != coords.last) coords.add(coords.first);
    }

    final dur = _trackStartTime != null
        ? DateTime.now().difference(_trackStartTime!)
        : Duration.zero;
    final durStr = dur.inHours > 0
        ? '${dur.inHours}h${(dur.inMinutes % 60).toString().padLeft(2, '0')}m'
        : '${(dur.inMinutes % 60).toString().padLeft(2, '0')}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';

    String targetLayerId;
    String displayName;

    if (saveToActive && activeLayer != null) {
      // Save as feature in active layer
      targetLayerId = activeLayer.id;
      displayName = activeLayer.name;
    } else {
      // Create new layer
      final name = controller.text.trim();
      if (name.isEmpty) return;
      displayName = name;
      final layer = LayerModel(
        projectId: widget.projectId,
        name: name,
        geometryType: _trackGeomType,
        styleConfig: _trackGeomType == GeometryType.polygon
            ? {'fillColor': 0x332196F3, 'strokeColor': 0xFF2196F3, 'strokeWidth': 2.0, 'sourceFormat': 'tracking'}
            : {'color': 0xFFFF5722, 'width': 3.0, 'sourceFormat': 'tracking'},
      );
      await _layerRepo.insert(layer);
      targetLayerId = layer.id;
    }

    final feature = FeatureModel(
      layerId: targetLayerId,
      coordinates: coords,
      attributes: {
        'name': displayName,
        'points': _trackPoints.length,
        'distance_m': _trackDistance.toStringAsFixed(1),
        'duration': durStr,
        'recorded_at': DateTime.now().toIso8601String(),
      },
    );
    await _featureRepo.insert(feature);

    setState(() {
      _trackRecording = false;
      _trackPaused = false;
      _trackPoints = [];
    });

    await _loadData();
    final modeLabel = saveToActive ? 'vào "${displayName}"' : '"$displayName"';
    _showSnackBar('✅ Đã lưu $modeLabel — ${coords.length} điểm');
  }

  void _discardTrackRecording() {
    _trackGpsSub?.cancel();
    _trackGpsSub = null;
    _trackRefreshTimer?.cancel();
    _trackRefreshTimer = null;
    _trackIntervalTimer?.cancel();
    _trackIntervalTimer = null;
    setState(() {
      _trackRecording = false;
      _trackPaused = false;
      _trackPoints = [];
      _trackDistance = 0;
    });
    _stopTrackForegroundService();
    _showSnackBar('Đã hủy ghi vết GPS');
  }

  /// Floating GPS Track button — bottom-right, near basemap controls
  Widget _buildGpsTrackFab() {
    return Positioned(
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 78,
      child: GestureDetector(
        onTap: _showTrackStartDialog,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5722), Color(0xFFE64A19)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5722).withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.route, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildTrackRecordingOverlay() {
    final dur = _trackStartTime != null
        ? DateTime.now().difference(_trackStartTime!)
        : Duration.zero;
    final h = dur.inHours;
    final m = dur.inMinutes % 60;
    final s = dur.inSeconds % 60;
    final durStr = h > 0
        ? '${h}h${m.toString().padLeft(2, '0')}m'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final distStr = _trackDistance >= 1000
        ? '${(_trackDistance / 1000).toStringAsFixed(2)} km'
        : '${_trackDistance.toStringAsFixed(0)} m';
    final isPaused = _trackPaused;

    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 10,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (isPaused
                  ? const Color(0xFFFF9800)
                  : const Color(0xFFD32F2F))
              .withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Status + Duration ──
            Row(
              children: [
                // Pulse dot
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPaused ? Colors.yellow : Colors.white,
                    boxShadow: isPaused
                        ? null
                        : [BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isPaused ? 'TẠM DỪNG' : 'ĐANG GHI VẾT GPS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                // Duration badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    durStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Stats row ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _trackStat(Icons.location_on, '${_trackPoints.length}', 'Điểm'),
                _trackStat(Icons.straighten, distStr, 'Khoảng cách'),
                _trackStat(
                  _trackProfileIcons[_trackProfileIdx],
                  _trackProfileName,
                  'Phương tiện',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Control buttons ──
            Row(
              children: [
                // Pause / Resume
                Expanded(
                  child: _trackCtrlBtn(
                    icon: isPaused ? Icons.play_arrow : Icons.pause,
                    label: isPaused ? 'Tiếp tục' : 'Tạm dừng',
                    color: Colors.white.withValues(alpha: 0.25),
                    onTap: isPaused ? _resumeTrackRecording : _pauseTrackRecording,
                  ),
                ),
                const SizedBox(width: 8),
                // Save
                Expanded(
                  child: _trackCtrlBtn(
                    icon: Icons.save,
                    label: 'Lưu lại',
                    color: Colors.green.withValues(alpha: 0.7),
                    onTap: _saveTrackRecording,
                  ),
                ),
                const SizedBox(width: 8),
                // Discard
                SizedBox(
                  width: 48,
                  child: _trackCtrlBtn(
                    icon: Icons.close,
                    label: '',
                    color: Colors.black.withValues(alpha: 0.3),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Hủy ghi vết?'),
                          content: Text(
                              'Bạn sẽ mất ${_trackPoints.length} điểm đã ghi.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Không')),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _discardTrackRecording();
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                              child: const Text('Hủy ghi',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }

  Widget _trackCtrlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Scale bar (auto-calculates from zoom)
  // -------------------------------------------------------------------------

  Widget _buildScaleBar() {
    final zoom = _mapController.camera.zoom;
    final lat = _mapController.camera.center.latitude;

    // Calculate meters per pixel at current zoom and latitude
    final metersPerPixel = 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);

    // Choose a nice round distance for ~80px bar width
    const targetPx = 80.0;
    final targetMeters = metersPerPixel * targetPx;

    // Find nearest "nice" distance
    final niceDistances = [5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
    int bestDist = niceDistances.first;
    for (final d in niceDistances) {
      if (d <= targetMeters * 1.5) bestDist = d;
    }

    final barWidth = bestDist / metersPerPixel;
    final label = bestDist >= 1000 ? '${bestDist ~/ 1000} km' : '$bestDist m';

    // Position: very bottom-left, at screen edge
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 2,
      left: AppSizes.sm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: barWidth.clamp(30.0, 120.0),
              height: 3,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Speed indicator (GPS speed in km/h)
  // -------------------------------------------------------------------------

  Widget _buildSpeedIndicator() {
    final speedMs = _currentPosition?.speed ?? 0;
    final speedKmh = speedMs * 3.6;
    final topPadding = MediaQuery.of(context).padding.top + 48;

    return Positioned(
      top: topPadding,
      left: 3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              speedKmh.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 2),
            const Text(
              'km/h',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Right-side map controls (zoom, center)
  // -------------------------------------------------------------------------


  Widget _buildMapControls() {
    final zoom = _mapController.camera.zoom;
    return Positioned(
      right: AppSizes.md,
      bottom: _drawingMode != DrawingMode.idle ? 180 : 130,
      child: Column(
        children: [
          _MapButton(
            icon: Icons.add,
            onPressed: () {
              final z = (zoom + 1).clamp(AppSizes.minZoom, AppSizes.maxZoom);
              _mapController.move(_mapController.camera.center, z);
            },
          ),
          // Zoom level indicator
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Z${zoom.toStringAsFixed(1)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
          _MapButton(
            icon: Icons.remove,
            onPressed: () {
              final z = (zoom - 1).clamp(AppSizes.minZoom, AppSizes.maxZoom);
              _mapController.move(_mapController.camera.center, z);
            },
          ),
          const SizedBox(height: AppSizes.sm),
          _MapButton(
            icon: _autoCenter ? Icons.my_location : Icons.location_searching,
            onPressed: _centerOnGps,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // -------------------------------------------------------------------------
  // Vertex Edit — Map overlay (vertex markers + midpoint markers)
  // -------------------------------------------------------------------------

  /// Build vertex edit layers as a list of FlutterMap layer widgets
  List<Widget> _buildVertexEditLayers() {
    if (!_vertexEditMode || _editVertices.isEmpty) return [];

    final isPolygon = _editingFeatureLayer?.geometryType == GeometryType.polygon;
    final List<Widget> layers = [];

    // Shape preview (amber highlight)
    if (isPolygon) {
      layers.add(PolygonLayer(
        polygons: [
          Polygon(
            points: _editVertices,
            color: const Color(0x33FFAB00),
            borderColor: const Color(0xFFFFAB00),
            borderStrokeWidth: 2.5,
            isFilled: true,
          ),
        ],
      ));
    } else {
      layers.add(PolylineLayer(
        polylines: [
          Polyline(
            points: _editVertices,
            color: const Color(0xFFFFAB00),
            strokeWidth: 3,
          ),
        ],
      ));
    }

    // Midpoint markers (tap to add vertex) — hide during drag for performance
    if (_draggingVertexIndex == null) {
    final midpoints = <Marker>[];
    final vertexCount = _editVertices.length;
    final edgeCount = isPolygon ? vertexCount : vertexCount - 1;

    for (int i = 0; i < edgeCount; i++) {
      final nextI = (i + 1) % vertexCount;
      final midLat = (_editVertices[i].latitude + _editVertices[nextI].latitude) / 2;
      final midLng = (_editVertices[i].longitude + _editVertices[nextI].longitude) / 2;

      midpoints.add(Marker(
        point: LatLng(midLat, midLng),
        width: 24,
        height: 24,
        child: GestureDetector(
          onTap: () => _addVertexAtMidpoint(i),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade500, width: 1.5),
            ),
            child: const Icon(Icons.add, size: 14, color: Colors.grey),
          ),
        ),
      ));
    }

    if (midpoints.isNotEmpty) {
      layers.add(MarkerLayer(markers: midpoints));
    }
    } // end if not dragging

    // Vertex markers (draggable, numbered)
    final vertexMarkers = <Marker>[];
    for (int i = 0; i < _editVertices.length; i++) {
      vertexMarkers.add(Marker(
        point: _editVertices[i],
        width: 22,
        height: 22,
        child: GestureDetector(
          onPanStart: (_) {
            _pushVertexHistory();
            _draggingVertexIndex = i;
          },
          onPanUpdate: (details) {
            if (_draggingVertexIndex != i) return;
            final camera = _mapController.camera;
            final screenPt = camera.latLngToScreenPoint(_editVertices[i]);
            final newScreenPt = math.Point<double>(
              screenPt.x.toDouble() + details.delta.dx,
              screenPt.y.toDouble() + details.delta.dy,
            );
            final newLatLng = camera.pointToLatLng(newScreenPt);
            setState(() {
              _editVertices[i] = newLatLng;
            });
          },
          onPanEnd: (_) {
            _draggingVertexIndex = null;
          },
          onLongPress: () => _deleteVertexAt(i),
          child: Container(
            decoration: BoxDecoration(
              color: _draggingVertexIndex == i
                  ? const Color(0xFFFFAB00)
                  : AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    layers.add(MarkerLayer(markers: vertexMarkers));

    return layers;
  }

  /// Build the vertex edit toolbar (Positioned at bottom of screen)
  Widget _buildVertexEditToolbarWidget() {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomPadding,
      child: VertexEditToolbar(
        vertexCount: _editVertices.length,
        canUndo: _vertexHistory.isNotEmpty,
        onCancel: () => _exitVertexEditMode(save: false),
        onUndo: _undoVertexEdit,
        onSave: () => _exitVertexEditMode(save: true),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Center crosshair (visible during digitizing)
  // -------------------------------------------------------------------------

  Widget _buildCrosshair() {
    return const Center(
      child: IgnorePointer(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CustomPaint(painter: _CrosshairPainter()),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bottom action bar — switches between idle and digitizing mode
  // -------------------------------------------------------------------------

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 10,
          bottom: MediaQuery.of(context).padding.bottom + 8,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: _drawingMode == DrawingMode.idle
            ? _buildIdleActions()
            : _buildDigitizingActions(),
      ),
    );
  }

  /// Idle mode: shows active layer quick-draw or type selector
  Widget _buildIdleActions() {
    // Get the active editable layer
    final activeLayer = _activeLayerId != null
        ? _layers.where((l) => l.id == _activeLayerId).firstOrNull
        : null;

    // If we have an active editable layer → show quick-draw for that type
    if (activeLayer != null && !activeLayer.isReadOnly) {
      final geoType = activeLayer.geometryType;
      final drawMode = geoType == GeometryType.point
          ? DrawingMode.point
          : geoType == GeometryType.line
              ? DrawingMode.line
              : DrawingMode.polygon;
      final geoIcon = geoType == GeometryType.point
          ? Icons.location_on
          : geoType == GeometryType.line
              ? Icons.timeline
              : Icons.pentagon_outlined;
      final geoColor = geoType == GeometryType.point
          ? AppColors.pointColor
          : geoType == GeometryType.line
              ? AppColors.lineColor
              : AppColors.polygonStroke;
      final geoLabel = geoType == GeometryType.point
          ? 'Tạo điểm'
          : geoType == GeometryType.line
              ? 'Tạo đường'
              : 'Tạo vùng';

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active layer indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: geoColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(geoIcon, size: 14, color: geoColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    activeLayer.name,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: geoColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _activeLayerId = null),
                  child: Icon(Icons.close, size: 14, color: geoColor.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Quick-draw button (main action)
              _ActionButton(
                icon: geoIcon,
                label: geoLabel,
                color: geoColor,
                onPressed: () => _startDrawing(drawMode),
              ),
              // GPS quick-point (only for point layers)
              if (geoType == GeometryType.point)
                _ActionButton(
                  icon: Icons.gps_fixed,
                  label: 'GPS',
                  color: AppColors.gpsCircleStroke,
                  onPressed: _quickGpsPoint,
                ),
              // Layer panel
              _ActionButton(
                icon: Icons.layers_outlined,
                label: 'Lớp',
                color: AppColors.info,
                onPressed: () => setState(() => _showLayerPanel = true),
              ),
            ],
          ),
        ],
      );
    }

    // No active layer → "Thêm" = add a new layer
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionButton(
          icon: Icons.add_circle_outline,
          label: 'Thêm lớp',
          color: AppColors.primary,
          onPressed: () async {
            final result = await AddLayerDialog.show(context, widget.projectId);
            if (result == null) return;
            final newLayer = result['layer'] as LayerModel;
            final fieldDefs = result['fields'] as List<Map<String, dynamic>>? ?? [];
            await _layerRepo.insert(newLayer);
            if (fieldDefs.isNotEmpty) {
              final formEngine = FormEngineService();
              final uuid = const Uuid();
              final fields = fieldDefs.map((def) => FormFieldModel(
                id: uuid.v4(),
                layerId: newLayer.id,
                fieldName: def['fieldName'] as String,
                label: def['label'] as String,
                fieldType: FormFieldType.values.firstWhere(
                  (t) => t.name == (def['fieldType'] as String? ?? 'text'),
                  orElse: () => FormFieldType.text,
                ),
                autoSource: def['autoSource'] as String?,
                hint: def['hint'] as String?,
                sortOrder: def['sortOrder'] as int? ?? 0,
              )).toList();
              await formEngine.saveFields(fields);
            }
            await _loadData();
            if (!mounted) return;
            setState(() => _activeLayerId = newLayer.id);
            _showSnackBar('✅ Đã tạo lớp "${newLayer.name}" — chạm bản đồ để thêm đối tượng');
          },
        ),
        _ActionButton(
          icon: Icons.layers_outlined,
          label: 'Lớp',
          color: AppColors.info,
          onPressed: () => setState(() => _showLayerPanel = true),
        ),
      ],
    );
  }

  /// Compact floating digitize toolbar — positioned above coordinate display
  Widget _buildFloatingDigitizeBar() {
    final modeName = _drawingMode == DrawingMode.point
        ? 'Đ'
        : _drawingMode == DrawingMode.line
            ? 'L'
            : 'V';
    final vtxCount = _vertices.length;
    final canSave = _canSave();

    return Positioned(
      left: 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status badge (mode + count)
              Container(
                width: 32,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$modeName$vtxCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Undo
              _MiniDigitBtn(
                icon: Icons.undo,
                color: Colors.orange,
                onTap: _vertices.isEmpty ? null : _undoVertex,
              ),
              const SizedBox(height: 4),
              // Cancel
              _MiniDigitBtn(
                icon: Icons.close,
                color: Colors.redAccent,
                onTap: _cancelDrawing,
              ),
              const SizedBox(height: 4),
              // Save
              _MiniDigitBtn(
                icon: Icons.check,
                color: canSave ? Colors.green : Colors.grey,
                onTap: canSave ? _saveFeature : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Digitizing mode actions — no longer used directly in bottom bar
  Widget _buildDigitizingActions() {
    // Redirected to floating bar
    return const SizedBox.shrink();
  }

  /// Check whether the current vertices meet minimum requirements to save
  bool _canSave() {
    switch (_drawingMode) {
      case DrawingMode.point:
        return _vertices.length == 1;
      case DrawingMode.line:
        return _vertices.length >= 2;
      case DrawingMode.polygon:
        return _vertices.length >= 3;
      case DrawingMode.idle:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // Coordinate display (bottom-left, tappable to toggle CRS)
  // -------------------------------------------------------------------------

  Widget _buildCoordinateDisplay() {
    // Map center coordinates
    final center = _mapController.camera.center;
    final centerCoord = CrsService.formatCoordinate(
      center.latitude, center.longitude, _crsDisplayMode,
    );

    // GPS device coordinates
    final hasGps = _currentPosition != null;
    final gpsCoord = hasGps
        ? CrsService.formatCoordinate(
            _currentPosition!.latLng.latitude,
            _currentPosition!.latLng.longitude,
            _crsDisplayMode,
          )
        : 'Đang tìm GPS...';

    final modeLabel = CrsService.displayModeLabel(_crsDisplayMode);

    // Auto-contrast: dark bg for satellite, light bg for OSM
    final isSatellite = _tileSource == TileSource.satellite;
    final bgColor = isSatellite
        ? Colors.black.withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.9);
    final textColor = isSatellite ? Colors.white : Colors.black87;
    final secondaryColor = isSatellite ? Colors.white60 : Colors.black54;
    final badgeBg = isSatellite
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);

    return Positioned(
      left: 8,
      bottom: MediaQuery.of(context).padding.bottom + 35,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _crsDisplayMode = CrsService.nextDisplayMode(_crsDisplayMode);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSatellite ? Colors.white12 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // CRS mode badge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      modeLabel,
                      style: TextStyle(
                        color: secondaryColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '▸ Chạm đổi CRS',
                    style: TextStyle(color: secondaryColor, fontSize: 7),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              // Row 1: Map center
              Row(
                children: [
                  Icon(Icons.center_focus_strong, size: 11, color: const Color(0xFFFF0000).withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  Text(
                    'Tâm: ',
                    style: TextStyle(color: secondaryColor, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Text(
                      centerCoord,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Row 2: GPS device position
              Row(
                children: [
                  Icon(
                    Icons.gps_fixed,
                    size: 11,
                    color: hasGps ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'GPS: ',
                    style: TextStyle(color: secondaryColor, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Text(
                      gpsCoord,
                      style: TextStyle(
                        color: hasGps ? textColor : secondaryColor,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Layer panel (DraggableScrollableSheet)
  // -------------------------------------------------------------------------

  Widget _buildLayerPanel() {
    return GestureDetector(
      // Tap on the scrim to close the panel
      onTap: () => setState(() => _showLayerPanel = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.2,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
            return GestureDetector(
              // Prevent taps on the panel from closing it
              onTap: () {},
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.md,
                        vertical: AppSizes.sm,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.layers, color: AppColors.primary),
                          const SizedBox(width: AppSizes.sm),
                          const Expanded(
                            child: Text(
                              'Lớp dữ liệu',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          // Add layer button
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: AppColors.primary),
                            tooltip: 'Thêm lớp mới',
                            onPressed: () {
                              setState(() => _showLayerPanel = false);
                              _addLayer();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _showLayerPanel = false),
                          ),
                        ],
                      ),
                    ),
                    // ── Action buttons: Nhập / Xuất ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: _LayerPanelAction(
                              icon: Icons.file_download,
                              label: 'Nhập lớp',
                              color: AppColors.primary,
                              onTap: () {
                                setState(() => _showLayerPanel = false);
                                _showImportDataDialog();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _LayerPanelAction(
                              icon: Icons.file_upload,
                              label: 'Xuất',
                              color: AppColors.success,
                              onTap: () {
                                setState(() => _showLayerPanel = false);
                                _showExportDialog();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Divider(height: 1),
                    // Layer list
                    Expanded(
                      child: _layers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.layers_clear,
                                      size: 48,
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.5)),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Chưa có lớp dữ liệu',
                                    style: TextStyle(
                                        color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      setState(
                                          () => _showLayerPanel = false);
                                      _addLayer();
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Thêm lớp mới'),
                                  ),
                                ],
                              ),
                            )
                          : ReorderableListView.builder(
                              scrollController: scrollController,
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSizes.sm),
                              itemCount: _layers.length,
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (newIndex > oldIndex) newIndex--;
                                  final layer = _layers.removeAt(oldIndex);
                                  _layers.insert(newIndex, layer);
                                });
                              },
                              proxyDecorator: (child, index, animation) {
                                return Material(
                                  elevation: 4,
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  child: child,
                                );
                              },
                              itemBuilder: (context, index) {
                                final layer = _layers[index];
                                final count =
                                    _featuresByLayer[layer.id]?.length ??
                                        0;
                                return _buildLayerTile(layer, count,
                                    key: ValueKey(layer.id));
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Single layer tile inside the layer panel
  Widget _buildLayerTile(LayerModel layer, int featureCount, {Key? key}) {
    final IconData typeIcon;
    switch (layer.geometryType) {
      case GeometryType.point:
        typeIcon = Icons.location_on;
        break;
      case GeometryType.line:
        typeIcon = Icons.timeline;
        break;
      case GeometryType.polygon:
        typeIcon = Icons.pentagon_outlined;
        break;
    }

    final isActive = _activeLayerId == layer.id;

    return ListTile(
      key: key,
      leading: CircleAvatar(
        backgroundColor: layer.displayColor.withValues(alpha: 0.15),
        child: Icon(typeIcon, color: layer.displayColor, size: 20),
      ),
      title: Text(
        layer.name,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: layer.isVisible
              ? (isActive ? AppColors.primary : AppColors.textPrimary)
              : AppColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$featureCount đối tượng${isActive ? " • Đang hoạt động" : ""}${layer.isReadOnly ? " • 🔒${layer.sourceFormat?.toUpperCase()}" : ""}',
        style: TextStyle(
          fontSize: 12,
          color: isActive ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch.adaptive(
            value: layer.isVisible,
            activeColor: AppColors.primary,
            onChanged: (_) => _toggleLayerVisibility(layer),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) => _handleLayerMenuAction(value, layer),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'zoom',
                child: Row(
                  children: [
                    Icon(Icons.zoom_in_map, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Zoom tới lớp'),
                  ],
                ),
              ),
              if (!layer.isReadOnly) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'add',
                  child: Row(
                    children: [
                      Icon(Icons.add_location_alt, color: Colors.green[700], size: 20),
                      const SizedBox(width: 8),
                      const Text('Thêm đối tượng'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_location_alt, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      const Text('Chỉnh sửa đối tượng'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'tracking',
                  child: Row(
                    children: [
                      Icon(Icons.my_location, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      const Text('GPS Tracking'),
                    ],
                  ),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'style',
                child: Row(
                  children: [
                    Icon(Icons.palette, color: Colors.purple[600], size: 20),
                    const SizedBox(width: 8),
                    const Text('Kiểu hiển thị'),
                  ],
                ),
              ),
              if (layer.sourceFormat == 'tiff')
                PopupMenuItem(
                  value: 'image_adjust',
                  child: Row(
                    children: [
                      Icon(Icons.brightness_6, color: Colors.amber[700], size: 20),
                      const SizedBox(width: 8),
                      const Text('Sáng / Tương phản'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Đổi tên lớp'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Text('Xóa lớp', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Handle layer context menu actions
  void _handleLayerMenuAction(String action, LayerModel layer) {
    switch (action) {
      case 'zoom':
        _zoomToLayer(layer);
        break;
      case 'add':
        _startAddFeature(layer);
        break;
      case 'edit':
        _startEditLayer(layer);
        break;
      case 'tracking':
        _startLayerGpsTracking(layer);
        break;
      case 'style':
        _editLayerStyle(layer);
        break;
      case 'image_adjust':
        _showImageAdjustDialog(layer);
        break;
      case 'rename':
        _renameLayer(layer);
        break;
      case 'delete':
        _deleteLayer(layer);
        break;
    }
  }

  /// Zoom to layer extent (bounding box of all features)
  void _zoomToLayer(LayerModel layer) {
    final features = _featuresByLayer[layer.id] ?? [];
    if (features.isEmpty) {
      _showSnackBar('Lớp "${layer.name}" chưa có đối tượng');
      return;
    }

    // Calculate bounding box
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final f in features) {
      for (final coord in f.coordinates) {
        if (coord.latitude < minLat) minLat = coord.latitude;
        if (coord.latitude > maxLat) maxLat = coord.latitude;
        if (coord.longitude < minLng) minLng = coord.longitude;
        if (coord.longitude > maxLng) maxLng = coord.longitude;
      }
    }

    // Close layer panel
    setState(() => _showLayerPanel = false);

    // Fit map to bounds with padding
    try {
      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
      _showSnackBar('📍 Zoom tới lớp "${layer.name}" (${features.length} đối tượng)');
    } catch (e) {
      // If fitCamera fails, move to center of bounds
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController.move(LatLng(centerLat, centerLng), 14);
      _showSnackBar('📍 Di chuyển tới lớp "${layer.name}"');
    }
  }

  /// Start adding features to a specific layer
  void _startAddFeature(LayerModel layer) {
    if (layer.isReadOnly) {
      _showSnackBar('🔒 Layer ${layer.sourceFormat?.toUpperCase()} chỉ xem — không thể thêm đối tượng');
      return;
    }
    setState(() {
      _showLayerPanel = false;
      _activeLayerId = layer.id;
    });

    // Activate drawing mode based on layer geometry type
    DrawingMode mode;
    switch (layer.geometryType) {
      case GeometryType.point:
        mode = DrawingMode.point;
        break;
      case GeometryType.line:
        mode = DrawingMode.line;
        break;
      case GeometryType.polygon:
        mode = DrawingMode.polygon;
        break;
    }

    setState(() {
      _drawingMode = mode;
      _vertices = [];
    });

    _showSnackBar('✏️ Chế độ thêm đối tượng vào "${layer.name}" — Chạm bản đồ để vẽ');
  }

  /// Start editing features in a layer
  void _startEditLayer(LayerModel layer) {
    final features = _featuresByLayer[layer.id] ?? [];
    if (features.isEmpty) {
      _showSnackBar('Lớp "${layer.name}" chưa có đối tượng để sửa');
      return;
    }

    setState(() {
      _showLayerPanel = false;
      _activeLayerId = layer.id;
    });

    // Show feature list for editing
    _showFeatureListForEdit(layer, features);
  }

  /// Show list of features in a layer for editing
  void _showFeatureListForEdit(LayerModel layer, List<FeatureModel> features) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.edit_location_alt, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chỉnh sửa "${layer.name}"',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${features.length} đối tượng',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Feature list
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: features.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                itemBuilder: (ctx, i) {
                  final f = features[i];
                  // Use labelField if configured, then common name fields, then first attribute
                  String? name;
                  final lf = layer.labelField;
                  if (lf != null && lf.isNotEmpty) {
                    name = f.attributes[lf]?.toString();
                  }
                  name ??= f.attributes['name']?.toString()
                      ?? f.attributes['Name']?.toString()
                      ?? f.attributes['ten']?.toString();
                  // Fallback: first non-empty attribute value
                  if (name == null || name.isEmpty) {
                    for (final v in f.attributes.values) {
                      if (v != null && v.toString().isNotEmpty) {
                        name = v.toString();
                        break;
                      }
                    }
                  }
                  name ??= 'Đối tượng #${i + 1}';
                  final coordStr = f.coordinates.isNotEmpty
                      ? '${f.coordinates.first.latitude.toStringAsFixed(5)}, ${f.coordinates.first.longitude.toStringAsFixed(5)}'
                      : 'N/A';
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      name.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      coordStr,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Zoom to feature
                        IconButton(
                          icon: const Icon(Icons.my_location, size: 18),
                          tooltip: 'Zoom tới',
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (f.coordinates.isNotEmpty) {
                              _mapController.move(f.coordinates.first, 17);
                            }
                          },
                        ),
                        // Edit attributes
                        IconButton(
                          icon: Icon(Icons.edit_note, size: 18, color: Colors.orange[700]),
                          tooltip: 'Sửa thuộc tính',
                          onPressed: () {
                            Navigator.pop(ctx);
                            _editLayerFeatureAttributes(f, layer);
                          },
                        ),
                        // Delete feature
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                          tooltip: 'Xóa',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: ctx,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('Xóa đối tượng'),
                                content: Text('Xóa "$name"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                    child: const Text('Xóa'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await _featureRepo.delete(f.id);
                              await _loadData();
                              if (mounted) {
                                Navigator.pop(ctx);
                                _showSnackBar('Đã xóa "$name"');
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Edit feature attributes from layer edit panel
  Future<void> _editLayerFeatureAttributes(FeatureModel feature, LayerModel layer) async {
    final attrs = Map<String, dynamic>.from(feature.attributes);
    final controllers = <String, TextEditingController>{};
    for (final entry in attrs.entries) {
      controllers[entry.key] = TextEditingController(text: entry.value?.toString() ?? '');
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sửa thuộc tính', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controllers.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: e.value,
                  decoration: InputDecoration(
                    labelText: e.key,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              )).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final updated = <String, dynamic>{};
              for (final e in controllers.entries) {
                if (e.value.text.isNotEmpty) {
                  updated[e.key] = e.value.text;
                }
              }
              Navigator.pop(ctx, updated);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null) {
      final updated = feature.copyWith(attributes: result);
      await _featureRepo.update(updated);
      await _loadData();
      if (mounted) _showSnackBar('✅ Đã cập nhật thuộc tính');
    }
  }

  /// Start GPS tracking on a specific layer
  void _startLayerGpsTracking(LayerModel layer) {
    if (_currentPosition == null) {
      _showSnackBar('⚠️ Chưa có tín hiệu GPS. Đợi định vị...');
      return;
    }

    setState(() {
      _showLayerPanel = false;
      _activeLayerId = layer.id;
      _autoCenter = true;
    });

    // Activate appropriate drawing mode for tracking
    DrawingMode mode;
    switch (layer.geometryType) {
      case GeometryType.point:
        // For point layers, add current GPS position as point
        _addGpsPoint(layer);
        return;
      case GeometryType.line:
        mode = DrawingMode.line;
        break;
      case GeometryType.polygon:
        mode = DrawingMode.polygon;
        break;
    }

    // Start with current GPS position
    setState(() {
      _drawingMode = mode;
      _vertices = [_currentPosition!.latLng];
    });

    _showSnackBar('📡 GPS Tracking trên "${layer.name}" — Di chuyển để ghi lại vị trí');
  }

  /// Add current GPS position as a point feature
  Future<void> _addGpsPoint(LayerModel layer) async {
    if (_currentPosition == null) return;

    final feature = FeatureModel(
      layerId: layer.id,
      coordinates: [_currentPosition!.latLng],
      attributes: {
        'name': 'GPS Point ${DateTime.now().toString().substring(11, 19)}',
        'lat': _currentPosition!.latLng.latitude.toStringAsFixed(6),
        'lng': _currentPosition!.latLng.longitude.toStringAsFixed(6),
        'accuracy': '${_currentPosition!.accuracy.toStringAsFixed(1)}m',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    await _featureRepo.insert(feature);
    await _loadData();
    if (mounted) {
      _showSnackBar('📍 Đã thêm điểm GPS vào "${layer.name}"');
    }
  }

  /// Show brightness/contrast/saturation/gamma adjustment dialog for TIFF layers
  void _showImageAdjustDialog(LayerModel layer) {
    double brightness = (layer.styleConfig['brightness'] as num?)?.toDouble() ?? 0;
    double contrast = (layer.styleConfig['contrast'] as num?)?.toDouble() ?? 0;
    double saturation = (layer.styleConfig['saturation'] as num?)?.toDouble() ?? 0;
    double gamma = (layer.styleConfig['gamma'] as num?)?.toDouble() ?? 1.0;
    bool gammaProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Row(
                  children: [
                    Icon(Icons.tune, color: Colors.amber[700], size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Chỉnh ảnh — ${layer.name}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Brightness slider
                _buildSliderRow(
                  icon: Icons.wb_sunny,
                  label: 'Độ sáng',
                  value: brightness,
                  min: -50, max: 50,
                  color: Colors.amber[700]!,
                  displayValue: brightness.round().toString(),
                  onChanged: (v) {
                    setModalState(() => brightness = v);
                    setState(() => layer.styleConfig['brightness'] = v);
                  },
                ),

                // Saturation slider
                _buildSliderRow(
                  icon: Icons.color_lens,
                  label: 'Bão hòa',
                  value: saturation,
                  min: -50, max: 50,
                  color: Colors.pink[600]!,
                  displayValue: saturation.round().toString(),
                  onChanged: (v) {
                    setModalState(() => saturation = v);
                    setState(() => layer.styleConfig['saturation'] = v);
                  },
                ),

                // Contrast slider
                _buildSliderRow(
                  icon: Icons.contrast,
                  label: 'Tương phản',
                  value: contrast,
                  min: -50, max: 50,
                  color: Colors.deepPurple,
                  displayValue: contrast.round().toString(),
                  onChanged: (v) {
                    setModalState(() => contrast = v);
                    setState(() => layer.styleConfig['contrast'] = v);
                  },
                ),

                // Gamma slider
                Row(
                  children: [
                    Icon(Icons.tonality, size: 20, color: Colors.teal[700]),
                    const SizedBox(width: 8),
                    const SizedBox(width: 65, child: Text('Gamma', style: TextStyle(fontSize: 13))),
                    Expanded(
                      child: Slider(
                        value: gamma,
                        min: 0.3, max: 3.0,
                        divisions: 54,
                        activeColor: Colors.teal[700],
                        label: gamma.toStringAsFixed(2),
                        onChanged: (v) {
                          setModalState(() => gamma = v);
                        },
                        onChangeEnd: (v) {
                          setModalState(() => gammaProcessing = true);
                          _applyGammaToOverlay(layer, v).then((_) {
                            setModalState(() => gammaProcessing = false);
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: gammaProcessing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(gamma.toStringAsFixed(2),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                // Reset button
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Đặt lại mặc định'),
                  onPressed: () {
                    setModalState(() {
                      brightness = 0; contrast = 0; saturation = 0; gamma = 1.0;
                      gammaProcessing = true;
                    });
                    setState(() {
                      layer.styleConfig['brightness'] = 0.0;
                      layer.styleConfig['contrast'] = 0.0;
                      layer.styleConfig['saturation'] = 0.0;
                    });
                    _applyGammaToOverlay(layer, 1.0).then((_) {
                      setModalState(() => gammaProcessing = false);
                    });
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Helper: build a slider row for image adjustment
  Widget _buildSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        SizedBox(width: 65, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value, min: min, max: max,
            divisions: (max - min).round(),
            activeColor: color,
            label: displayValue,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(displayValue,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );
  }

  /// Apply gamma correction to the overlay PNG (non-linear, can't do with ColorFilter)
  Future<void> _applyGammaToOverlay(LayerModel layer, double gamma) async {
    final overlayPath = layer.styleConfig['overlayPath'] as String?;
    if (overlayPath == null) return;

    // Ensure we have a base copy (original PNG before any gamma)
    final basePath = '${overlayPath}.base';
    final baseFile = File(basePath);
    final overlayFile = File(overlayPath);
    if (!baseFile.existsSync()) {
      // First time: save original as base
      await overlayFile.copy(basePath);
    }

    try {
      // Load base PNG
      final baseBytes = await baseFile.readAsBytes();
      final image = img.decodePng(baseBytes);
      if (image == null) return;

      // Apply gamma LUT
      final lut = List<int>.generate(256, (i) {
        return (255.0 * math.pow(i / 255.0, gamma)).clamp(0, 255).round();
      });

      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final px = image.getPixel(x, y);
          final r = lut[px.r.toInt()];
          final g = lut[px.g.toInt()];
          final b = lut[px.b.toInt()];
          image.setPixelRgba(x, y, r, g, b, px.a.toInt());
        }
      }

      // Save modified PNG
      final pngBytes = img.encodePng(image);
      await overlayFile.writeAsBytes(pngBytes);

      // Evict image cache to force reload
      FileImage(overlayFile).evict();

      // Store gamma value
      layer.styleConfig['gamma'] = gamma;
      setState(() {});
    } catch (e) {
      debugPrint('Gamma apply error: $e');
    }
  }

  /// Edit layer style (colors, labels)
  Future<void> _editLayerStyle(LayerModel layer) async {
    setState(() => _showLayerPanel = false);

    // Collect available field names from features
    final features = _featuresByLayer[layer.id] ?? [];
    final fieldNames = <String>{};
    for (final f in features) {
      fieldNames.addAll(f.attributes.keys);
    }

    if (!mounted) return;

    final newStyle = await LayerStyleDialog.show(
      context,
      layer: layer,
      availableFields: fieldNames.toList()..sort(),
    );

    if (newStyle != null) {
      final updated = layer.copyWith(styleConfig: newStyle);
      await _layerRepo.update(updated);
      await _loadData();
      _showSnackBar('✅ Đã cập nhật kiểu hiển thị');
    }
  }

  /// Rename a layer
  Future<void> _renameLayer(LayerModel layer) async {
    final controller = TextEditingController(text: layer.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên lớp'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên lớp',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != layer.name) {
      final updated = layer.copyWith(name: newName);
      await _layerRepo.update(updated);
      await _loadData();
      if (mounted) _showSnackBar('✅ Đã đổi tên thành "$newName"');
    }
  }
}

// ===========================================================================
// Private helper widgets
// ===========================================================================

/// Crosshair painter for digitizing mode
class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const gap = 5.0;
    const arm = 16.0;

    // Bright red crosshair with white outline for visibility
    final outlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final mainPaint = Paint()
      ..color = const Color(0xFFFF0000) // Bright red
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw outline then main color
    for (final paint in [outlinePaint, mainPaint]) {
      canvas.drawLine(Offset(cx - arm, cy), Offset(cx - gap, cy), paint);
      canvas.drawLine(Offset(cx + gap, cy), Offset(cx + arm, cy), paint);
      canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy - gap), paint);
      canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + arm), paint);
    }

    // Center dot - bright red
    canvas.drawCircle(
      Offset(cx, cy),
      2.5,
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      2.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Circular map control button (zoom, location, tile toggle)

// ---------------------------------------------------------------------------
// Top Icon Button (compact, semi-transparent for top bar)
// ---------------------------------------------------------------------------

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _TopIconButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12, width: 0.5),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compass Painter (N/S needle with cardinal marks)
// ---------------------------------------------------------------------------

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // North needle (red triangle pointing up)
    final northPaint = Paint()..color = const Color(0xFFFF3D00);
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - radius + 2)
      ..lineTo(center.dx - 5, center.dy)
      ..lineTo(center.dx + 5, center.dy)
      ..close();
    canvas.drawPath(northPath, northPaint);

    // South needle (white triangle pointing down)
    final southPaint = Paint()..color = Colors.white70;
    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + radius - 2)
      ..lineTo(center.dx - 5, center.dy)
      ..lineTo(center.dx + 5, center.dy)
      ..close();
    canvas.drawPath(southPath, southPaint);

    // "N" letter at top
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Color(0xFFFF3D00),
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, 1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Circular map button (zoom +/-, GPS center)
// ---------------------------------------------------------------------------

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MapButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      shape: const CircleBorder(),
      color: Colors.white,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}

/// Action button used in the bottom action bar
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    final effectiveColor = isDisabled ? color.withValues(alpha: 0.35) : color;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: isDisabled ? 0.05 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: effectiveColor, size: 22),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attribute Edit Dialog
// ---------------------------------------------------------------------------

/// Dialog for editing feature attributes (key-value pairs)
class _AttributeEditDialog extends StatefulWidget {
  final Map<String, dynamic> initialAttributes;

  const _AttributeEditDialog({required this.initialAttributes});

  @override
  State<_AttributeEditDialog> createState() => _AttributeEditDialogState();
}

class _AttributeEditDialogState extends State<_AttributeEditDialog> {
  late List<MapEntry<String, TextEditingController>> _controllers;
  final _newKeyController = TextEditingController();
  final _newValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controllers = widget.initialAttributes.entries.map((e) {
      return MapEntry(e.key, TextEditingController(text: '${e.value}'));
    }).toList();
  }

  @override
  void dispose() {
    for (final entry in _controllers) {
      entry.value.dispose();
    }
    _newKeyController.dispose();
    _newValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_note, color: AppColors.primary, size: 24),
          const SizedBox(width: 8),
          const Text('Sửa thuộc tính'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Existing attributes
              ..._controllers.asMap().entries.map((entry) {
                final i = entry.key;
                final kv = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          kv.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: kv.value,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 18, color: AppColors.error),
                        onPressed: () {
                          setState(() => _controllers.removeAt(i));
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              }),

              const Divider(height: 24),

              // Add new attribute
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _newKeyController,
                      decoration: InputDecoration(
                        hintText: 'Tên trường',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _newValueController,
                      decoration: InputDecoration(
                        hintText: 'Giá trị',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppColors.primary, size: 22),
                    onPressed: () {
                      final key = _newKeyController.text.trim();
                      final value = _newValueController.text.trim();
                      if (key.isNotEmpty) {
                        setState(() {
                          _controllers.add(MapEntry(
                            key,
                            TextEditingController(text: value),
                          ));
                          _newKeyController.clear();
                          _newValueController.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: () {
            final result = <String, dynamic>{};
            for (final entry in _controllers) {
              final value = entry.value.text;
              // Try to preserve numeric types
              final numVal = num.tryParse(value);
              result[entry.key] = numVal ?? value;
            }
            Navigator.pop(context, result);
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

/// Helper class for import progress tracking
class _ImportProgress {
  final int current;
  final int total;
  final String message;
  const _ImportProgress(this.current, this.total, this.message);
}

// =========================================================================
// Left toolbar widgets
// =========================================================================

/// Toggle button for expanding/collapsing the left toolbar
class _ToolbarToggleButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _ToolbarToggleButton({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isExpanded
              ? AppColors.primary
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isExpanded ? Icons.close : Icons.menu,
          color: isExpanded ? Colors.white : AppColors.primary,
          size: 22,
        ),
      ),
    );
  }
}

/// Individual toolbar item with icon and label
class _ToolbarItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ToolbarItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact action button for the layer panel (Nhập / Hệ tọa độ / Xuất)
class _LayerPanelAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LayerPanelAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact floating button for digitizing toolbar
/// Mini circular button for vertical digitizing toolbar
class _MiniDigitBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MiniDigitBtn({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final effectiveColor = disabled ? Colors.grey.shade600 : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveColor.withValues(alpha: disabled ? 0.3 : 0.85),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
