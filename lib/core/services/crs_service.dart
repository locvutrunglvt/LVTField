// CRS (Coordinate Reference System) service for LVTField
// Supports WGS 84 (EPSG:4326), VN-2000 per province, UTM zones
// Author: Lộc Vũ Trung

import 'dart:math';

/// Display CRS mode for coordinate overlay
enum CrsDisplayMode { wgs84, vn2000, utm, selectedCrs }

/// CRS definition with EPSG code and display info
class CrsDefinition {
  final String code;            // e.g. "EPSG:4326"
  final String name;            // e.g. "WGS 84"
  final String description;     // e.g. "Hệ tọa độ toàn cầu GPS"
  final String? province;       // VN-2000 province name (null for global CRS)
  final double? centralMeridian;// Central meridian in degrees
  final int? epsgCode;          // EPSG numeric code
  final double scaleFactor;     // k0 (0.9996 for UTM, 0.9999 for TM-3)
  final bool isVn2000Datum;     // True if VN-2000 datum (needs Helmert shift)
  final bool isGeographic;      // True for lat/lon CRS (4326, 4756)

  const CrsDefinition({
    required this.code,
    required this.name,
    required this.description,
    this.province,
    this.centralMeridian,
    this.epsgCode,
    this.scaleFactor = 0.9999,
    this.isVn2000Datum = false,
    this.isGeographic = false,
  });

  @override
  String toString() => '$name ($code)';
}

/// CRS Service — manages coordinate reference systems and projections
class CrsService {
  // Singleton
  static final CrsService _instance = CrsService._();
  factory CrsService() => _instance;
  CrsService._();

  /// Current project CRS (default WGS 84)
  CrsDefinition _currentCrs = wgs84;

  CrsDefinition get currentCrs => _currentCrs;

  void setCrs(CrsDefinition crs) {
    _currentCrs = crs;
  }

  /// Selected CRS for coordinate display (user picks from list)
  CrsDefinition _selectedCrs = wgs84;

  CrsDefinition get selectedCrs => _selectedCrs;

  void setSelectedCrs(CrsDefinition crs) {
    _selectedCrs = crs;
  }

  /// Reset to WGS 84
  void reset() {
    _currentCrs = wgs84;
    _selectedCrs = wgs84;
  }

  // =========================================================================
  // Global CRS definitions
  // =========================================================================

  static const wgs84 = CrsDefinition(
    code: 'EPSG:4326',
    name: 'WGS 84',
    description: 'Hệ tọa độ toàn cầu (GPS mặc định)',
    epsgCode: 4326,
    isGeographic: true,
  );

  static const vn2000 = CrsDefinition(
    code: 'EPSG:4756',
    name: 'VN-2000',
    description: 'Hệ tọa độ quốc gia Việt Nam (địa lý)',
    epsgCode: 4756,
    isVn2000Datum: true,
    isGeographic: true,
  );

  // =========================================================================
  // Predefined CRS list — matches QGIS "Predefined Coordinate Reference Systems"
  // =========================================================================

  /// All selectable CRS options (ordered like QGIS list)
  static const List<CrsDefinition> allSelectableCrs = [
    // --- Toàn cầu ---
    wgs84,
    CrsDefinition(code: 'EPSG:32648', name: 'WGS 84 / UTM zone 48N', description: 'KTT 105°E', epsgCode: 32648, centralMeridian: 105.0, scaleFactor: 0.9996),
    CrsDefinition(code: 'EPSG:32649', name: 'WGS 84 / UTM zone 49N', description: 'KTT 111°E', epsgCode: 32649, centralMeridian: 111.0, scaleFactor: 0.9996),

    // --- VN-2000 / UTM (6° zones, k0=0.9996) ---
    CrsDefinition(code: 'EPSG:3405', name: 'VN-2000 / UTM zone 48N', description: 'KTT 105°E', epsgCode: 3405, centralMeridian: 105.0, scaleFactor: 0.9996, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:3406', name: 'VN-2000 / UTM zone 49N', description: 'KTT 111°E', epsgCode: 3406, centralMeridian: 111.0, scaleFactor: 0.9996, isVn2000Datum: true),

    // --- VN-2000 / TM-3 (3° zones, k0=0.9999) ---
    CrsDefinition(code: 'EPSG:9205', name: 'VN-2000 / TM-3 103-00', description: 'KTT 103°00\'', epsgCode: 9205, centralMeridian: 103.0, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9206', name: 'VN-2000 / TM-3 104-00', description: 'KTT 104°00\'', epsgCode: 9206, centralMeridian: 104.0, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9207', name: 'VN-2000 / TM-3 104-30', description: 'KTT 104°30\'', epsgCode: 9207, centralMeridian: 104.5, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9208', name: 'VN-2000 / TM-3 104-45', description: 'KTT 104°45\'', epsgCode: 9208, centralMeridian: 104.75, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9209', name: 'VN-2000 / TM-3 105-30', description: 'KTT 105°30\'', epsgCode: 9209, centralMeridian: 105.5, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9210', name: 'VN-2000 / TM-3 105-45', description: 'KTT 105°45\'', epsgCode: 9210, centralMeridian: 105.75, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9211', name: 'VN-2000 / TM-3 106-00', description: 'KTT 106°00\'', epsgCode: 9211, centralMeridian: 106.0, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9212', name: 'VN-2000 / TM-3 106-15', description: 'KTT 106°15\'', epsgCode: 9212, centralMeridian: 106.25, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9213', name: 'VN-2000 / TM-3 106-30', description: 'KTT 106°30\'', epsgCode: 9213, centralMeridian: 106.5, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9214', name: 'VN-2000 / TM-3 107-00', description: 'KTT 107°00\'', epsgCode: 9214, centralMeridian: 107.0, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9215', name: 'VN-2000 / TM-3 107-15', description: 'KTT 107°15\'', epsgCode: 9215, centralMeridian: 107.25, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9216', name: 'VN-2000 / TM-3 107-30', description: 'KTT 107°30\'', epsgCode: 9216, centralMeridian: 107.5, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:5899', name: 'VN-2000 / TM-3 107-45', description: 'KTT 107°45\'', epsgCode: 5899, centralMeridian: 107.75, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9217', name: 'VN-2000 / TM-3 108-15', description: 'KTT 108°15\'', epsgCode: 9217, centralMeridian: 108.25, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:9218', name: 'VN-2000 / TM-3 108-30', description: 'KTT 108°30\'', epsgCode: 9218, centralMeridian: 108.5, isVn2000Datum: true),

    // --- VN-2000 / TM-3 named zones ---
    CrsDefinition(code: 'EPSG:5899', name: 'VN-2000 / TM-3 Da Nang zone', description: 'KTT 107°45\' (Đà Nẵng)', epsgCode: 5899, centralMeridian: 107.75, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:5896', name: 'VN-2000 / TM-3 zone 481', description: 'KTT 102°E', epsgCode: 5896, centralMeridian: 102.0, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:5897', name: 'VN-2000 / TM-3 zone 482', description: 'KTT 105°E', epsgCode: 5897, centralMeridian: 105.0, isVn2000Datum: true),
    CrsDefinition(code: 'EPSG:5898', name: 'VN-2000 / TM-3 zone 491', description: 'KTT 108°E', epsgCode: 5898, centralMeridian: 108.0, isVn2000Datum: true),
  ];

  /// Convert WGS84 lat/lon to a specific selected CRS
  /// Returns formatted string
  static String wgs84ToSelectedCrs(double lat, double lon, CrsDefinition crs) {
    if (crs.isGeographic) {
      if (crs.isVn2000Datum) {
        // WGS84 → VN-2000 geographic
        final vn = _helmertWgs84ToVn2000(lat, lon);
        if (vn != null) {
          return '${vn[0].toStringAsFixed(7)}°, ${vn[1].toStringAsFixed(7)}°';
        }
        return 'N/A';
      }
      // WGS84 geographic
      return '${lat.toStringAsFixed(7)}°, ${lon.toStringAsFixed(7)}°';
    }

    // Projected CRS
    final cm = crs.centralMeridian ?? 105.0;
    final k0 = crs.scaleFactor;

    if (crs.isVn2000Datum) {
      // WGS84 → VN-2000 datum → project
      final vn = _helmertWgs84ToVn2000(lat, lon);
      if (vn != null) {
        final proj = wgs84ToTm(vn[0], vn[1], cm, k0: k0);
        if (proj != null) {
          return 'E: ${proj[0].toStringAsFixed(3)}  N: ${proj[1].toStringAsFixed(3)}';
        }
      }
      return 'N/A';
    } else {
      // WGS84 → project directly (UTM WGS84)
      final proj = wgs84ToTm(lat, lon, cm, k0: k0);
      if (proj != null) {
        return 'E: ${proj[0].toStringAsFixed(3)}  N: ${proj[1].toStringAsFixed(3)}';
      }
      return 'N/A';
    }
  }

  // =========================================================================
  // Projection Constants (WGS84 ellipsoid)
  // =========================================================================

  static const double _a = 6378137.0;           // semi-major axis
  static const double _f = 1.0 / 298.257223563; // flattening
  static const double _e2 = 2 * _f - _f * _f;   // first eccentricity squared
  static const double _ep2 = _e2 / (1 - _e2);   // second eccentricity squared

  // VN-2000 to WGS84 — 7-parameter Helmert (Coordinate Frame Rotation)
  // Source: EPSG transformation code 6960 (Department of Survey and Mapping)
  // Accuracy: ~1.0 m
  // TOWGS84[-191.90441429, -39.30318279, -111.45032835,
  //         -0.00928836, 0.01975479, -0.00427372, 0.252906278]
  static const double _dx = -191.90441429;  // Translation X (metres)
  static const double _dy = -39.30318279;   // Translation Y (metres)
  static const double _dz = -111.45032835;  // Translation Z (metres)
  static const double _rx = -0.00928836;    // Rotation X (arc-seconds)
  static const double _ry = 0.01975479;     // Rotation Y (arc-seconds)
  static const double _rz = -0.00427372;    // Rotation Z (arc-seconds)
  static const double _ds = 0.252906278;    // Scale difference (ppm)

  // =========================================================================
  // Forward Projection: WGS84 (lat/lon) → Transverse Mercator (E, N)
  // =========================================================================

  /// Convert WGS84 lat/lon to VN-2000 projected coordinates (meters)
  /// [latDeg], [lonDeg] in degrees; [centralMeridianDeg] in degrees
  /// Returns (Easting, Northing)
  static List<double>? wgs84ToTm(double latDeg, double lonDeg, double centralMeridianDeg, {
    double k0 = 0.9999,
    double falseEasting = 500000.0,
    double falseNorthing = 0.0,
  }) {
    try {
      final lat = latDeg * pi / 180.0;
      final lon = lonDeg * pi / 180.0;
      final lon0 = centralMeridianDeg * pi / 180.0;

      final sinLat = sin(lat);
      final cosLat = cos(lat);
      final tanLat = tan(lat);

      final N = _a / sqrt(1 - _e2 * sinLat * sinLat);
      final T = tanLat * tanLat;
      final C = _ep2 * cosLat * cosLat;
      final A = (lon - lon0) * cosLat;

      final M = _a * (
        (1 - _e2 / 4 - 3 * _e2 * _e2 / 64 - 5 * _e2 * _e2 * _e2 / 256) * lat
        - (3 * _e2 / 8 + 3 * _e2 * _e2 / 32 + 45 * _e2 * _e2 * _e2 / 1024) * sin(2 * lat)
        + (15 * _e2 * _e2 / 256 + 45 * _e2 * _e2 * _e2 / 1024) * sin(4 * lat)
        - (35 * _e2 * _e2 * _e2 / 3072) * sin(6 * lat)
      );

      final easting = falseEasting + k0 * N * (
        A
        + (1 - T + C) * A * A * A / 6
        + (5 - 18 * T + T * T + 72 * C - 58 * _ep2) * A * A * A * A * A / 120
      );

      final northing = falseNorthing + k0 * (
        M + N * tanLat * (
          A * A / 2
          + (5 - T + 9 * C + 4 * C * C) * A * A * A * A / 24
          + (61 - 58 * T + T * T + 600 * C - 330 * _ep2) * A * A * A * A * A * A / 720
        )
      );

      return [easting, northing];
    } catch (e) {
      return null;
    }
  }

  /// Convert WGS84 lat/lon to UTM
  /// Returns (Easting, Northing, Zone, Hemisphere)
  static Map<String, dynamic>? wgs84ToUtm(double latDeg, double lonDeg) {
    try {
      final zone = ((lonDeg + 180) / 6).floor() + 1;
      final centralMeridian = (zone - 1) * 6.0 - 180.0 + 3.0;
      final isNorth = latDeg >= 0;

      final result = wgs84ToTm(
        latDeg, lonDeg, centralMeridian,
        k0: 0.9996,
        falseEasting: 500000.0,
        falseNorthing: isNorth ? 0.0 : 10000000.0,
      );

      if (result == null) return null;

      return {
        'easting': result[0],
        'northing': result[1],
        'zone': zone,
        'hemisphere': isNorth ? 'N' : 'S',
      };
    } catch (e) {
      return null;
    }
  }

  // =========================================================================
  // Inverse Projection: TM (E, N) → WGS84 (lat/lon)
  // =========================================================================

  /// Convert Transverse Mercator coordinates to WGS84
  /// Returns (latitude, longitude) in degrees
  static List<double>? tmToWgs84(double easting, double northing, double centralMeridianDeg, {
    double k0 = 0.9999,
    double falseEasting = 500000.0,
    bool isVn2000 = false,
  }) {
    try {
      final x = easting - falseEasting;
      final y = northing;

      // Footpoint latitude
      final M = y / k0;
      final mu = M / (_a * (1 - _e2 / 4 - 3 * _e2 * _e2 / 64 - 5 * _e2 * _e2 * _e2 / 256));

      final e1 = (1 - sqrt(1 - _e2)) / (1 + sqrt(1 - _e2));

      final phi1 = mu
          + (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * sin(2 * mu)
          + (21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * sin(4 * mu)
          + (151 * e1 * e1 * e1 / 96) * sin(6 * mu);

      final sinPhi1 = sin(phi1);
      final cosPhi1 = cos(phi1);
      final tanPhi1 = tan(phi1);

      final N1 = _a / sqrt(1 - _e2 * sinPhi1 * sinPhi1);
      final T1 = tanPhi1 * tanPhi1;
      final C1 = _ep2 * cosPhi1 * cosPhi1;
      final R1 = _a * (1 - _e2) / pow(1 - _e2 * sinPhi1 * sinPhi1, 1.5);
      final D = x / (N1 * k0);

      final lat = phi1 - (N1 * tanPhi1 / R1) * (
          D * D / 2
          - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * _ep2) * D * D * D * D / 24
          + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * _ep2 - 3 * C1 * C1) * D * D * D * D * D * D / 720
      );

      final lon = (D
          - (1 + 2 * T1 + C1) * D * D * D / 6
          + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * _ep2 + 24 * T1 * T1) * D * D * D * D * D / 120
      ) / cosPhi1;

      var latDeg = lat * 180.0 / pi;
      var lonDeg = centralMeridianDeg + lon * 180.0 / pi;

      if (latDeg >= -90 && latDeg <= 90 && lonDeg >= -180 && lonDeg <= 180) {
        // Apply VN-2000 → WGS84 Helmert transform if needed
        if (isVn2000) {
          final shifted = _helmertVn2000ToWgs84(latDeg, lonDeg);
          if (shifted != null) return shifted;
        }
        return [latDeg, lonDeg];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Convert UTM coordinates to WGS84
  static List<double>? utmToWgs84(double easting, double northing, int zone, bool isNorth) {
    final centralMeridian = (zone - 1) * 6.0 - 180.0 + 3.0;
    final adjustedNorthing = isNorth ? northing : northing - 10000000.0;
    return tmToWgs84(easting, adjustedNorthing, centralMeridian,
      k0: 0.9996,
      falseEasting: 500000.0,
    );
  }

  // =========================================================================
  // 7-Parameter Helmert (Coordinate Frame Rotation) — EPSG:6960
  // VN-2000 geographic (lat/lon) ↔ WGS84 geographic (lat/lon)
  // =========================================================================

  /// Apply 7-param Helmert: VN-2000 → WGS84
  /// Input/output in degrees
  static List<double>? _helmertVn2000ToWgs84(double latDeg, double lonDeg) {
    try {
      final lat = latDeg * pi / 180.0;
      final lon = lonDeg * pi / 180.0;

      // Geographic to geocentric (cartesian XYZ)
      final sinLat = sin(lat);
      final cosLat = cos(lat);
      final sinLon = sin(lon);
      final cosLon = cos(lon);
      final N = _a / sqrt(1 - _e2 * sinLat * sinLat);

      final X = N * cosLat * cosLon;
      final Y = N * cosLat * sinLon;
      final Z = N * (1 - _e2) * sinLat;

      // Convert rotation from arc-seconds to radians
      final rxRad = _rx * pi / (180.0 * 3600.0);
      final ryRad = _ry * pi / (180.0 * 3600.0);
      final rzRad = _rz * pi / (180.0 * 3600.0);
      final s = _ds * 1e-6; // ppm to ratio

      // Coordinate Frame Rotation: X_wgs84 = T + (1+s)*R * X_vn2000
      final X2 = _dx + (1 + s) * (X - rzRad * Y + ryRad * Z);
      final Y2 = _dy + (1 + s) * (rzRad * X + Y - rxRad * Z);
      final Z2 = _dz + (1 + s) * (-ryRad * X + rxRad * Y + Z);

      // Geocentric back to geographic (iterative)
      final p = sqrt(X2 * X2 + Y2 * Y2);
      final lon2 = atan2(Y2, X2);
      var lat2 = atan2(Z2, p * (1 - _e2));

      for (int i = 0; i < 10; i++) {
        final sinLat2 = sin(lat2);
        final N2 = _a / sqrt(1 - _e2 * sinLat2 * sinLat2);
        lat2 = atan2(Z2 + _e2 * N2 * sinLat2, p);
      }

      return [lat2 * 180.0 / pi, lon2 * 180.0 / pi];
    } catch (e) {
      return null;
    }
  }

  /// Apply 7-param Helmert: WGS84 → VN-2000 (inverse transform)
  static List<double>? _helmertWgs84ToVn2000(double latDeg, double lonDeg) {
    try {
      final lat = latDeg * pi / 180.0;
      final lon = lonDeg * pi / 180.0;

      final sinLat = sin(lat);
      final cosLat = cos(lat);
      final sinLon = sin(lon);
      final cosLon = cos(lon);
      final N = _a / sqrt(1 - _e2 * sinLat * sinLat);

      final X = N * cosLat * cosLon;
      final Y = N * cosLat * sinLon;
      final Z = N * (1 - _e2) * sinLat;

      // Inverse Coordinate Frame Rotation
      final rxRad = _rx * pi / (180.0 * 3600.0);
      final ryRad = _ry * pi / (180.0 * 3600.0);
      final rzRad = _rz * pi / (180.0 * 3600.0);
      final s = _ds * 1e-6;

      // Inverse: X_vn2000 = (1/(1+s)) * R^T * (X_wgs84 - T)
      final Xt = X - _dx;
      final Yt = Y - _dy;
      final Zt = Z - _dz;
      final invS = 1.0 / (1 + s);

      final X2 = invS * (Xt + rzRad * Yt - ryRad * Zt);
      final Y2 = invS * (-rzRad * Xt + Yt + rxRad * Zt);
      final Z2 = invS * (ryRad * Xt - rxRad * Yt + Zt);

      final p = sqrt(X2 * X2 + Y2 * Y2);
      final lon2 = atan2(Y2, X2);
      var lat2 = atan2(Z2, p * (1 - _e2));

      for (int i = 0; i < 10; i++) {
        final sinLat2 = sin(lat2);
        final N2 = _a / sqrt(1 - _e2 * sinLat2 * sinLat2);
        lat2 = atan2(Z2 + _e2 * N2 * sinLat2, p);
      }

      return [lat2 * 180.0 / pi, lon2 * 180.0 / pi];
    } catch (e) {
      return null;
    }
  }

  // =========================================================================
  // Unified multi-CRS conversion: WGS84 → all 5 systems
  // =========================================================================

  /// Convert WGS84 lat/lon to all 5 CRS systems simultaneously
  /// Returns a map: { 'EPSG:xxxx': { 'label': ..., 'value': ... } }
  static Map<String, Map<String, String>> wgs84ToAllSystems(double lat, double lon) {
    final result = <String, Map<String, String>>{};

    // 1. EPSG:4326 — WGS 84 (geographic, degrees)
    result['4326'] = {
      'label': 'WGS 84',
      'value': '${lat.toStringAsFixed(7)}°, ${lon.toStringAsFixed(7)}°',
      'desc': 'Hệ tọa độ toàn cầu GPS',
    };

    // 2. EPSG:32648 — WGS 84 / UTM zone 48N (CM = 105°E)
    final utm48 = wgs84ToTm(lat, lon, 105.0, k0: 0.9996);
    if (utm48 != null) {
      result['32648'] = {
        'label': 'WGS 84 / UTM 48N',
        'value': 'E: ${utm48[0].toStringAsFixed(3)}  N: ${utm48[1].toStringAsFixed(3)}',
        'desc': 'KTT 105°E, k₀ = 0.9996',
      };
    }

    // 3. EPSG:32649 — WGS 84 / UTM zone 49N (CM = 111°E)
    final utm49 = wgs84ToTm(lat, lon, 111.0, k0: 0.9996);
    if (utm49 != null) {
      result['32649'] = {
        'label': 'WGS 84 / UTM 49N',
        'value': 'E: ${utm49[0].toStringAsFixed(3)}  N: ${utm49[1].toStringAsFixed(3)}',
        'desc': 'KTT 111°E, k₀ = 0.9996',
      };
    }

    // 4. EPSG:3405 — VN-2000 / UTM zone 48N (CM = 105°E, datum shift)
    // First apply WGS84 → VN-2000 datum shift, then project
    final vn48geo = _helmertWgs84ToVn2000(lat, lon);
    if (vn48geo != null) {
      final vn48 = wgs84ToTm(vn48geo[0], vn48geo[1], 105.0, k0: 0.9996);
      if (vn48 != null) {
        result['3405'] = {
          'label': 'VN-2000 / UTM 48N',
          'value': 'E: ${vn48[0].toStringAsFixed(3)}  N: ${vn48[1].toStringAsFixed(3)}',
          'desc': 'Datum VN-2000, KTT 105°E',
        };
      }
    }

    // 5. EPSG:3406 — VN-2000 / UTM zone 49N (CM = 111°E, datum shift)
    final vn49geo = _helmertWgs84ToVn2000(lat, lon);
    if (vn49geo != null) {
      final vn49 = wgs84ToTm(vn49geo[0], vn49geo[1], 111.0, k0: 0.9996);
      if (vn49 != null) {
        result['3406'] = {
          'label': 'VN-2000 / UTM 49N',
          'value': 'E: ${vn49[0].toStringAsFixed(3)}  N: ${vn49[1].toStringAsFixed(3)}',
          'desc': 'Datum VN-2000, KTT 111°E',
        };
      }
    }

    return result;
  }

  // =========================================================================
  // SRS Detection from WKT definition
  // =========================================================================

  /// Extract central_meridian and scale_factor from WKT projection definition
  /// Handles multiple WKT formats (OGC WKT1, WKT2, ESRI WKT)
  static Map<String, double> parseWktProjectionParams(String wkt) {
    final params = <String, double>{};

    // Pattern: PARAMETER["name",value] or PARAMETER["name", value]
    final paramRegex = RegExp(
      r'PARAMETER\s*\[\s*"([^"]+)"\s*,\s*([-\d.eE+]+)\s*\]',
      caseSensitive: false,
    );

    for (final match in paramRegex.allMatches(wkt)) {
      final name = match.group(1)!.toLowerCase().replaceAll(' ', '_');
      final value = double.tryParse(match.group(2)!);
      if (value != null) {
        params[name] = value;
      }
    }

    return params;
  }

  /// Detect CRS and get central meridian from WKT definition
  static double? extractCentralMeridian(String wkt) {
    final params = parseWktProjectionParams(wkt);

    // Try various parameter names used in different WKT formats
    return params['central_meridian']
        ?? params['longitude_of_center']
        ?? params['longitude_of_origin']
        ?? params['longitude_of_natural_origin'];
  }

  /// Detect scale factor from WKT definition
  static double? extractScaleFactor(String wkt) {
    final params = parseWktProjectionParams(wkt);
    return params['scale_factor']
        ?? params['scale_factor_at_natural_origin'];
  }

  /// Detect false easting from WKT definition
  static double? extractFalseEasting(String wkt) {
    final params = parseWktProjectionParams(wkt);
    return params['false_easting'];
  }

  /// Detect if WKT defines a projected CRS
  static bool isProjectedCrs(String wkt) {
    final upper = wkt.toUpperCase();
    return upper.contains('PROJCS') || upper.contains('PROJECTEDCRS')
        || upper.contains('TRANSVERSE_MERCATOR') || upper.contains('UTM');
  }

  /// Detect if this is a UTM zone CRS
  static bool isUtmCrs(String wkt) {
    final upper = wkt.toUpperCase();
    return upper.contains('UTM') && upper.contains('ZONE');
  }

  /// Extract UTM zone number from WKT
  static int? extractUtmZone(String wkt) {
    final zoneMatch = RegExp(r'(?:UTM|utm).*?(?:zone|ZONE)\s*(\d+)', caseSensitive: false).firstMatch(wkt);
    if (zoneMatch != null) {
      return int.tryParse(zoneMatch.group(1)!);
    }
    // Also try EPSG codes for UTM zones
    final epsgMatch = RegExp(r'(?:EPSG|epsg).*?326(\d{2})', caseSensitive: false).firstMatch(wkt);
    if (epsgMatch != null) {
      return int.tryParse(epsgMatch.group(1)!);
    }
    return null;
  }

  /// Detect CRS from EPSG/SRS ID and extract projection parameters
  static Map<String, dynamic> detectProjectionFromSrsId(int srsId) {
    // UTM zone N (EPSG:326xx)
    if (srsId >= 32601 && srsId <= 32660) {
      final zone = srsId - 32600;
      final cm = (zone - 1) * 6.0 - 180.0 + 3.0;
      return {
        'type': 'utm',
        'zone': zone,
        'hemisphere': 'N',
        'centralMeridian': cm,
        'scaleFactor': 0.9996,
        'falseEasting': 500000.0,
      };
    }
    // UTM zone S (EPSG:327xx)
    if (srsId >= 32701 && srsId <= 32760) {
      final zone = srsId - 32700;
      final cm = (zone - 1) * 6.0 - 180.0 + 3.0;
      return {
        'type': 'utm',
        'zone': zone,
        'hemisphere': 'S',
        'centralMeridian': cm,
        'scaleFactor': 0.9996,
        'falseEasting': 500000.0,
      };
    }
    // VN-2000 UTM zone 48N / 49N
    if (srsId == 3405) {
      return {
        'type': 'vn2000_utm',
        'zone': 48,
        'centralMeridian': 105.0,
        'scaleFactor': 0.9996,
        'falseEasting': 500000.0,
      };
    }
    if (srsId == 3406) {
      return {
        'type': 'vn2000_utm',
        'zone': 49,
        'centralMeridian': 111.0,
        'scaleFactor': 0.9996,
        'falseEasting': 500000.0,
      };
    }
    // WGS84
    if (srsId == 4326) {
      return {'type': 'geographic', 'name': 'WGS 84'};
    }
    // VN-2000 geographic
    if (srsId == 4756) {
      return {'type': 'geographic', 'name': 'VN-2000'};
    }

    return {'type': 'unknown', 'srsId': srsId};
  }

  /// Format a WGS84 coordinate according to display mode
  static String formatCoordinate(double lat, double lon, CrsDisplayMode mode, {double? centralMeridian}) {
    switch (mode) {
      case CrsDisplayMode.wgs84:
        return '${lat.toStringAsFixed(6)}°, ${lon.toStringAsFixed(6)}°';

      case CrsDisplayMode.vn2000:
        final cm = centralMeridian ?? _guessVn2000Meridian(lon);
        final result = wgs84ToTm(lat, lon, cm);
        if (result == null) return 'N/A';
        return 'E: ${result[0].toStringAsFixed(2)}\nN: ${result[1].toStringAsFixed(2)}';

      case CrsDisplayMode.utm:
        final result = wgs84ToUtm(lat, lon);
        if (result == null) return 'N/A';
        return '${result['zone']}${result['hemisphere']}  E: ${result['easting'].toStringAsFixed(1)}\nN: ${result['northing'].toStringAsFixed(1)}';

      case CrsDisplayMode.selectedCrs:
        final sel = CrsService()._selectedCrs;
        return wgs84ToSelectedCrs(lat, lon, sel);
    }
  }

  /// Get display mode label
  static String displayModeLabel(CrsDisplayMode mode) {
    switch (mode) {
      case CrsDisplayMode.wgs84:
        return 'WGS 84';
      case CrsDisplayMode.vn2000:
        return 'VN-2000';
      case CrsDisplayMode.utm:
        return 'UTM';
      case CrsDisplayMode.selectedCrs:
        final sel = CrsService()._selectedCrs;
        return sel.name;
    }
  }

  /// Cycle to next display mode
  static CrsDisplayMode nextDisplayMode(CrsDisplayMode current) {
    switch (current) {
      case CrsDisplayMode.wgs84:
        return CrsDisplayMode.vn2000;
      case CrsDisplayMode.vn2000:
        return CrsDisplayMode.utm;
      case CrsDisplayMode.utm:
        return CrsDisplayMode.selectedCrs;
      case CrsDisplayMode.selectedCrs:
        return CrsDisplayMode.wgs84;
    }
  }

  /// Guess the VN-2000 central meridian based on longitude
  static double _guessVn2000Meridian(double lon) {
    // Vietnam longitude range: ~102° - 110°
    // Find nearest VN-2000 province meridian
    double bestCm = 105.75;
    double bestDist = 999;
    for (final p in vn2000Provinces) {
      if (p.centralMeridian != null) {
        final dist = (p.centralMeridian! - lon).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestCm = p.centralMeridian!;
        }
      }
    }
    return bestCm;
  }

  // =========================================================================
  // VN-2000 per province — 63 tỉnh/thành
  // =========================================================================

  /// All available CRS options
  static List<CrsDefinition> get allCrs => [
    wgs84,
    vn2000,
    ...vn2000Provinces,
  ];

  /// VN-2000 by province with central meridian
  static const List<CrsDefinition> vn2000Provinces = [
    // --- Bắc Bộ ---
    CrsDefinition(code: 'VN2000:HN', name: 'VN-2000 Hà Nội', description: 'KTT 105°00\'', province: 'Hà Nội', centralMeridian: 105.0),
    CrsDefinition(code: 'VN2000:HP', name: 'VN-2000 Hải Phòng', description: 'KTT 105°45\'', province: 'Hải Phòng', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:HG', name: 'VN-2000 Hà Giang', description: 'KTT 105°30\'', province: 'Hà Giang', centralMeridian: 105.5),
    CrsDefinition(code: 'VN2000:CB', name: 'VN-2000 Cao Bằng', description: 'KTT 106°15\'', province: 'Cao Bằng', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:BK', name: 'VN-2000 Bắc Kạn', description: 'KTT 106°00\'', province: 'Bắc Kạn', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:TQ', name: 'VN-2000 Tuyên Quang', description: 'KTT 105°30\'', province: 'Tuyên Quang', centralMeridian: 105.5),
    CrsDefinition(code: 'VN2000:LC', name: 'VN-2000 Lào Cai', description: 'KTT 104°45\'', province: 'Lào Cai', centralMeridian: 104.75),
    CrsDefinition(code: 'VN2000:DB', name: 'VN-2000 Điện Biên', description: 'KTT 103°00\'', province: 'Điện Biên', centralMeridian: 103.0),
    CrsDefinition(code: 'VN2000:LS', name: 'VN-2000 Lai Châu', description: 'KTT 103°30\'', province: 'Lai Châu', centralMeridian: 103.5),
    CrsDefinition(code: 'VN2000:SL', name: 'VN-2000 Sơn La', description: 'KTT 104°00\'', province: 'Sơn La', centralMeridian: 104.0),
    CrsDefinition(code: 'VN2000:YB', name: 'VN-2000 Yên Bái', description: 'KTT 104°45\'', province: 'Yên Bái', centralMeridian: 104.75),
    CrsDefinition(code: 'VN2000:HB', name: 'VN-2000 Hoà Bình', description: 'KTT 105°30\'', province: 'Hoà Bình', centralMeridian: 105.5),
    CrsDefinition(code: 'VN2000:TN', name: 'VN-2000 Thái Nguyên', description: 'KTT 106°00\'', province: 'Thái Nguyên', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:LS2', name: 'VN-2000 Lạng Sơn', description: 'KTT 107°00\'', province: 'Lạng Sơn', centralMeridian: 107.0),
    CrsDefinition(code: 'VN2000:QN2', name: 'VN-2000 Quảng Ninh', description: 'KTT 107°00\'', province: 'Quảng Ninh', centralMeridian: 107.0),
    CrsDefinition(code: 'VN2000:BG', name: 'VN-2000 Bắc Giang', description: 'KTT 106°15\'', province: 'Bắc Giang', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:PT', name: 'VN-2000 Phú Thọ', description: 'KTT 105°15\'', province: 'Phú Thọ', centralMeridian: 105.25),
    CrsDefinition(code: 'VN2000:VP', name: 'VN-2000 Vĩnh Phúc', description: 'KTT 105°30\'', province: 'Vĩnh Phúc', centralMeridian: 105.5),
    CrsDefinition(code: 'VN2000:BN', name: 'VN-2000 Bắc Ninh', description: 'KTT 106°00\'', province: 'Bắc Ninh', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:HD', name: 'VN-2000 Hải Dương', description: 'KTT 106°15\'', province: 'Hải Dương', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:HY', name: 'VN-2000 Hưng Yên', description: 'KTT 106°00\'', province: 'Hưng Yên', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:TB', name: 'VN-2000 Thái Bình', description: 'KTT 106°10\'', province: 'Thái Bình', centralMeridian: 106.17),
    CrsDefinition(code: 'VN2000:HNam', name: 'VN-2000 Hà Nam', description: 'KTT 105°45\'', province: 'Hà Nam', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:NĐ', name: 'VN-2000 Nam Định', description: 'KTT 106°00\'', province: 'Nam Định', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:NB', name: 'VN-2000 Ninh Bình', description: 'KTT 105°45\'', province: 'Ninh Bình', centralMeridian: 105.75),

    // --- Bắc Trung Bộ ---
    CrsDefinition(code: 'VN2000:TH', name: 'VN-2000 Thanh Hoá', description: 'KTT 105°30\'', province: 'Thanh Hoá', centralMeridian: 105.5),
    CrsDefinition(code: 'VN2000:NA', name: 'VN-2000 Nghệ An', description: 'KTT 105°00\'', province: 'Nghệ An', centralMeridian: 105.0),
    CrsDefinition(code: 'VN2000:HT', name: 'VN-2000 Hà Tĩnh', description: 'KTT 105°45\'', province: 'Hà Tĩnh', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:QB', name: 'VN-2000 Quảng Bình', description: 'KTT 106°15\'', province: 'Quảng Bình', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:QT', name: 'VN-2000 Quảng Trị', description: 'KTT 107°00\'', province: 'Quảng Trị', centralMeridian: 107.0),
    CrsDefinition(code: 'VN2000:TTH', name: 'VN-2000 Thừa Thiên Huế', description: 'KTT 107°30\'', province: 'Thừa Thiên Huế', centralMeridian: 107.5),

    // --- Nam Trung Bộ ---
    CrsDefinition(code: 'VN2000:ĐN', name: 'VN-2000 Đà Nẵng', description: 'KTT 108°00\'', province: 'Đà Nẵng', centralMeridian: 108.0),
    CrsDefinition(code: 'VN2000:QNam', name: 'VN-2000 Quảng Nam', description: 'KTT 107°45\'', province: 'Quảng Nam', centralMeridian: 107.75),
    CrsDefinition(code: 'VN2000:QNg', name: 'VN-2000 Quảng Ngãi', description: 'KTT 108°30\'', province: 'Quảng Ngãi', centralMeridian: 108.5),
    CrsDefinition(code: 'VN2000:BD2', name: 'VN-2000 Bình Định', description: 'KTT 108°45\'', province: 'Bình Định', centralMeridian: 108.75),
    CrsDefinition(code: 'VN2000:PY', name: 'VN-2000 Phú Yên', description: 'KTT 109°00\'', province: 'Phú Yên', centralMeridian: 109.0),
    CrsDefinition(code: 'VN2000:KH', name: 'VN-2000 Khánh Hoà', description: 'KTT 109°00\'', province: 'Khánh Hoà', centralMeridian: 109.0),
    CrsDefinition(code: 'VN2000:NT', name: 'VN-2000 Ninh Thuận', description: 'KTT 108°30\'', province: 'Ninh Thuận', centralMeridian: 108.5),
    CrsDefinition(code: 'VN2000:BT', name: 'VN-2000 Bình Thuận', description: 'KTT 108°15\'', province: 'Bình Thuận', centralMeridian: 108.25),

    // --- Tây Nguyên ---
    CrsDefinition(code: 'VN2000:KT', name: 'VN-2000 Kon Tum', description: 'KTT 108°00\'', province: 'Kon Tum', centralMeridian: 108.0),
    CrsDefinition(code: 'VN2000:GL', name: 'VN-2000 Gia Lai', description: 'KTT 108°30\'', province: 'Gia Lai', centralMeridian: 108.5),
    CrsDefinition(code: 'VN2000:ĐL', name: 'VN-2000 Đắk Lắk', description: 'KTT 108°30\'', province: 'Đắk Lắk', centralMeridian: 108.5),
    CrsDefinition(code: 'VN2000:ĐN2', name: 'VN-2000 Đắk Nông', description: 'KTT 107°45\'', province: 'Đắk Nông', centralMeridian: 107.75),
    CrsDefinition(code: 'VN2000:LĐ', name: 'VN-2000 Lâm Đồng', description: 'KTT 108°15\'', province: 'Lâm Đồng', centralMeridian: 108.25),

    // --- Đông Nam Bộ ---
    CrsDefinition(code: 'VN2000:BP', name: 'VN-2000 Bình Phước', description: 'KTT 106°45\'', province: 'Bình Phước', centralMeridian: 106.75),
    CrsDefinition(code: 'VN2000:TN2', name: 'VN-2000 Tây Ninh', description: 'KTT 106°15\'', province: 'Tây Ninh', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:BD', name: 'VN-2000 Bình Dương', description: 'KTT 106°45\'', province: 'Bình Dương', centralMeridian: 106.75),
    CrsDefinition(code: 'VN2000:ĐNai', name: 'VN-2000 Đồng Nai', description: 'KTT 107°15\'', province: 'Đồng Nai', centralMeridian: 107.25),
    CrsDefinition(code: 'VN2000:BR', name: 'VN-2000 Bà Rịa-Vũng Tàu', description: 'KTT 107°45\'', province: 'Bà Rịa-Vũng Tàu', centralMeridian: 107.75),
    CrsDefinition(code: 'VN2000:HCM', name: 'VN-2000 TP Hồ Chí Minh', description: 'KTT 106°30\'', province: 'TP Hồ Chí Minh', centralMeridian: 106.5),

    // --- Tây Nam Bộ (Đồng bằng sông Cửu Long) ---
    CrsDefinition(code: 'VN2000:LA', name: 'VN-2000 Long An', description: 'KTT 106°15\'', province: 'Long An', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:TG', name: 'VN-2000 Tiền Giang', description: 'KTT 106°15\'', province: 'Tiền Giang', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:BT2', name: 'VN-2000 Bến Tre', description: 'KTT 106°30\'', province: 'Bến Tre', centralMeridian: 106.5),
    CrsDefinition(code: 'VN2000:TV', name: 'VN-2000 Trà Vinh', description: 'KTT 106°15\'', province: 'Trà Vinh', centralMeridian: 106.25),
    CrsDefinition(code: 'VN2000:VL', name: 'VN-2000 Vĩnh Long', description: 'KTT 106°00\'', province: 'Vĩnh Long', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:ĐT', name: 'VN-2000 Đồng Tháp', description: 'KTT 105°45\'', province: 'Đồng Tháp', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:AG', name: 'VN-2000 An Giang', description: 'KTT 105°00\'', province: 'An Giang', centralMeridian: 105.0),
    CrsDefinition(code: 'VN2000:KG', name: 'VN-2000 Kiên Giang', description: 'KTT 104°45\'', province: 'Kiên Giang', centralMeridian: 104.75),
    CrsDefinition(code: 'VN2000:CT', name: 'VN-2000 Cần Thơ', description: 'KTT 105°45\'', province: 'Cần Thơ', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:HG2', name: 'VN-2000 Hậu Giang', description: 'KTT 105°45\'', province: 'Hậu Giang', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:ST', name: 'VN-2000 Sóc Trăng', description: 'KTT 106°00\'', province: 'Sóc Trăng', centralMeridian: 106.0),
    CrsDefinition(code: 'VN2000:BL', name: 'VN-2000 Bạc Liêu', description: 'KTT 105°45\'', province: 'Bạc Liêu', centralMeridian: 105.75),
    CrsDefinition(code: 'VN2000:CM', name: 'VN-2000 Cà Mau', description: 'KTT 105°00\'', province: 'Cà Mau', centralMeridian: 105.0),
  ];

  // =========================================================================
  // Auto-detect CRS from file metadata
  // =========================================================================

  /// Try to detect CRS from GPKG srs_id or .prj file content
  static CrsDefinition detectFromSrsId(int srsId) {
    // Common EPSG codes
    switch (srsId) {
      case 4326: return wgs84;
      case 4756: return vn2000;
      case 3405: // VN-2000 UTM zone 48N
      case 3406: // VN-2000 UTM zone 49N
        return vn2000;
      default:
        // Check VN-2000 provincial codes (9201-9263 range)
        if (srsId >= 9201 && srsId <= 9263) {
          final idx = srsId - 9201;
          if (idx < vn2000Provinces.length) {
            return vn2000Provinces[idx];
          }
        }
        return wgs84; // fallback
    }
  }

  /// Detect CRS from .prj file content (WKT format)
  static CrsDefinition detectFromPrj(String prjContent) {
    final upper = prjContent.toUpperCase();
    if (upper.contains('VN-2000') || upper.contains('VN_2000')) {
      // Try to extract province from name
      for (final crs in vn2000Provinces) {
        if (crs.province != null && upper.contains(crs.province!.toUpperCase())) {
          return crs;
        }
      }
      return vn2000;
    }
    if (upper.contains('WGS') && upper.contains('84')) return wgs84;
    if (upper.contains('UTM')) return wgs84; // UTM zones treated as WGS84 for display
    return wgs84; // default
  }

  /// Get CRS options grouped by region for UI picker
  static Map<String, List<CrsDefinition>> get groupedCrs => {
    'Toàn cầu': [wgs84, vn2000],
    'Bắc Bộ': vn2000Provinces.where((c) => [
      'Hà Nội', 'Hải Phòng', 'Hà Giang', 'Cao Bằng', 'Bắc Kạn',
      'Tuyên Quang', 'Lào Cai', 'Điện Biên', 'Lai Châu', 'Sơn La',
      'Yên Bái', 'Hoà Bình', 'Thái Nguyên', 'Lạng Sơn', 'Quảng Ninh',
      'Bắc Giang', 'Phú Thọ', 'Vĩnh Phúc', 'Bắc Ninh', 'Hải Dương',
      'Hưng Yên', 'Thái Bình', 'Hà Nam', 'Nam Định', 'Ninh Bình',
    ].contains(c.province)).toList(),
    'Bắc Trung Bộ': vn2000Provinces.where((c) => [
      'Thanh Hoá', 'Nghệ An', 'Hà Tĩnh', 'Quảng Bình', 'Quảng Trị',
      'Thừa Thiên Huế',
    ].contains(c.province)).toList(),
    'Nam Trung Bộ': vn2000Provinces.where((c) => [
      'Đà Nẵng', 'Quảng Nam', 'Quảng Ngãi', 'Bình Định', 'Phú Yên',
      'Khánh Hoà', 'Ninh Thuận', 'Bình Thuận',
    ].contains(c.province)).toList(),
    'Tây Nguyên': vn2000Provinces.where((c) => [
      'Kon Tum', 'Gia Lai', 'Đắk Lắk', 'Đắk Nông', 'Lâm Đồng',
    ].contains(c.province)).toList(),
    'Đông Nam Bộ': vn2000Provinces.where((c) => [
      'Bình Phước', 'Tây Ninh', 'Bình Dương', 'Đồng Nai',
      'Bà Rịa-Vũng Tàu', 'TP Hồ Chí Minh',
    ].contains(c.province)).toList(),
    'Tây Nam Bộ': vn2000Provinces.where((c) => [
      'Long An', 'Tiền Giang', 'Bến Tre', 'Trà Vinh', 'Vĩnh Long',
      'Đồng Tháp', 'An Giang', 'Kiên Giang', 'Cần Thơ', 'Hậu Giang',
      'Sóc Trăng', 'Bạc Liêu', 'Cà Mau',
    ].contains(c.province)).toList(),
  };
}
