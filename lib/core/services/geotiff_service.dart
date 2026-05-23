// GeoTIFF Service - Parse GeoTIFF metadata and convert for overlay display
// Supports: GeoTIFF tags, .tfw world files, VN-2000 CRS detection
// Author: Lộc Vũ Trung

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Parsed GeoTIFF bounds and metadata
class GeoTiffInfo {
  final double north;
  final double south;
  final double east;
  final double west;
  final int width;
  final int height;
  final String? crsName;

  const GeoTiffInfo({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.width,
    required this.height,
    this.crsName,
  });

  @override
  String toString() => 'GeoTiffInfo(${west.toStringAsFixed(6)},${south.toStringAsFixed(6)} → '
      '${east.toStringAsFixed(6)},${north.toStringAsFixed(6)} ${width}x$height crs=$crsName)';
}

/// Result of GeoTIFF import
class GeoTiffResult {
  final bool success;
  final String? pngPath;      // Path to converted PNG file
  final GeoTiffInfo? geoInfo;  // Geographic bounds
  final String? errorMessage;

  const GeoTiffResult({
    required this.success,
    this.pngPath,
    this.geoInfo,
    this.errorMessage,
  });
}

class GeoTiffService {

  /// Process a GeoTIFF file: parse bounds + convert to PNG overlay
  Future<GeoTiffResult> processGeoTiff(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const GeoTiffResult(success: false, errorMessage: 'File không tồn tại');
    }

    final fileSize = await file.length();
    debugPrint('GeoTiffService: Processing ${p.basename(filePath)} (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

    // Warn if file is very large
    if (fileSize > 100 * 1024 * 1024) {
      return const GeoTiffResult(
        success: false,
        errorMessage: 'File TIFF quá lớn (>100MB). Hãy convert sang MBTiles trong QGIS.',
      );
    }

    try {
      final bytes = await file.readAsBytes();

      // 1. Parse GeoTIFF tags for bounds
      GeoTiffInfo? geoInfo = _parseGeoTiffTags(bytes);

      // 2. Fallback: try .tfw world file
      if (geoInfo == null) {
        geoInfo = await _parseWorldFile(filePath, bytes);
      }

      if (geoInfo == null) {
        return const GeoTiffResult(
          success: false,
          errorMessage: 'Không tìm thấy thông tin tọa độ.\n'
              'File cần có tag GeoTIFF hoặc file .tfw đi kèm.',
        );
      }

      debugPrint('GeoTiffService: Parsed bounds: $geoInfo');

      // 3. Decode TIFF → PNG
      final pngPath = await _convertTiffToPng(bytes, filePath);
      if (pngPath == null) {
        return const GeoTiffResult(
          success: false,
          errorMessage: 'Không thể giải mã file TIFF. File có thể bị hỏng.',
        );
      }

      return GeoTiffResult(
        success: true,
        pngPath: pngPath,
        geoInfo: geoInfo,
      );
    } catch (e) {
      debugPrint('GeoTiffService: Error: $e');
      return GeoTiffResult(
        success: false,
        errorMessage: 'Lỗi xử lý GeoTIFF: $e',
      );
    }
  }

  /// Parse GeoTIFF tags from TIFF binary data
  GeoTiffInfo? _parseGeoTiffTags(Uint8List bytes) {
    if (bytes.length < 8) return null;

    // Check byte order
    final byteOrder = String.fromCharCodes(bytes.sublist(0, 2));
    final bool isLittleEndian;
    if (byteOrder == 'II') {
      isLittleEndian = true;
    } else if (byteOrder == 'MM') {
      isLittleEndian = false;
    } else {
      debugPrint('GeoTiffService: Not a TIFF file');
      return null;
    }

    final bd = ByteData.sublistView(bytes);
    final endian = isLittleEndian ? Endian.little : Endian.big;

    // Check magic number
    final magic = bd.getUint16(2, endian);
    if (magic != 42 && magic != 43) {
      debugPrint('GeoTiffService: Not a valid TIFF (magic=$magic)');
      return null;
    }

    // Get first IFD offset
    int ifdOffset;
    if (magic == 43) {
      // BigTIFF
      ifdOffset = bd.getUint64(8, endian);
    } else {
      ifdOffset = bd.getUint32(4, endian);
    }

    // Parse IFD entries
    int? imageWidth;
    int? imageHeight;
    List<double>? modelPixelScale; // Tag 33550
    List<double>? modelTiepoint;   // Tag 33922

    while (ifdOffset > 0 && ifdOffset < bytes.length - 2) {
      final numEntries = bd.getUint16(ifdOffset, endian);
      int entryOffset = ifdOffset + 2;

      for (int i = 0; i < numEntries && entryOffset + 12 <= bytes.length; i++) {
        final tag = bd.getUint16(entryOffset, endian);
        final type = bd.getUint16(entryOffset + 2, endian);
        final count = bd.getUint32(entryOffset + 4, endian);
        final valueOffset = bd.getUint32(entryOffset + 8, endian);

        switch (tag) {
          case 256: // ImageWidth
            imageWidth = (type == 3) ? bd.getUint16(entryOffset + 8, endian) : valueOffset;
            break;
          case 257: // ImageLength (height)
            imageHeight = (type == 3) ? bd.getUint16(entryOffset + 8, endian) : valueOffset;
            break;
          case 33550: // ModelPixelScaleTag
            if (count >= 2 && type == 12 && valueOffset + count * 8 <= bytes.length) {
              modelPixelScale = _readDoubles(bd, valueOffset, count, endian);
            }
            break;
          case 33922: // ModelTiepointTag
            if (count >= 6 && type == 12 && valueOffset + count * 8 <= bytes.length) {
              modelTiepoint = _readDoubles(bd, valueOffset, count, endian);
            }
            break;
        }

        entryOffset += 12;
      }

      // Next IFD
      if (entryOffset + 4 <= bytes.length) {
        ifdOffset = bd.getUint32(entryOffset, endian);
      } else {
        break;
      }
    }

    if (imageWidth == null || imageHeight == null) {
      debugPrint('GeoTiffService: Missing image dimensions');
      return null;
    }

    debugPrint('GeoTiffService: Image size: ${imageWidth}x$imageHeight');
    debugPrint('GeoTiffService: PixelScale: $modelPixelScale');
    debugPrint('GeoTiffService: Tiepoint: $modelTiepoint');

    if (modelPixelScale != null && modelTiepoint != null &&
        modelPixelScale.length >= 2 && modelTiepoint.length >= 6) {
      // Standard GeoTIFF with tiepoint + pixel scale
      final tieI = modelTiepoint[0]; // pixel X
      final tieJ = modelTiepoint[1]; // pixel Y
      final originX = modelTiepoint[3]; // geographic X (lon or easting)
      final originY = modelTiepoint[4]; // geographic Y (lat or northing)
      final scaleX = modelPixelScale[0];
      final scaleY = modelPixelScale[1];

      double west = originX - tieI * scaleX;
      double north = originY + tieJ * scaleY;
      double east = west + imageWidth * scaleX;
      double south = north - imageHeight * scaleY;

      // Detect if coordinates are in projected CRS (meters)
      // WGS84 lon range: -180 to 180, lat range: -90 to 90
      // VN-2000/UTM coordinates are typically > 100000
      String? crsName;
      if (west.abs() > 360 || north.abs() > 360) {
        // Likely projected coordinates (VN-2000, UTM, etc.)
        debugPrint('GeoTiffService: Detected projected CRS (values > 360)');
        crsName = 'projected';
        // Try to convert from VN-2000 or UTM to WGS84
        final converted = _tryConvertToWgs84(west, south, east, north);
        if (converted != null) {
          west = converted[0];
          south = converted[1];
          east = converted[2];
          north = converted[3];
          crsName = 'vn2000_converted';
        } else {
          debugPrint('GeoTiffService: Cannot convert projected coords to WGS84');
          return null;
        }
      } else {
        crsName = 'wgs84';
      }

      // Validate bounds
      if (south >= north || west >= east) {
        debugPrint('GeoTiffService: Invalid bounds: $south>=$north or $west>=$east');
        return null;
      }

      return GeoTiffInfo(
        north: north,
        south: south,
        east: east,
        west: west,
        width: imageWidth,
        height: imageHeight,
        crsName: crsName,
      );
    }

    debugPrint('GeoTiffService: No ModelPixelScale or ModelTiepoint found');
    return null;
  }

  /// Try to convert projected coordinates to WGS84
  /// Handles common VN cases: VN-2000, UTM zone 48N
  List<double>? _tryConvertToWgs84(double west, double south, double east, double north) {
    // Detect UTM zone 48N (most of Vietnam)
    // UTM zone 48: central meridian = 105°E
    // Easting range: ~100000-900000, Northing range: ~0-10000000
    if (west > 100000 && west < 900000 && south > 0 && south < 10000000) {
      debugPrint('GeoTiffService: Trying UTM Zone 48N conversion');
      final sw = _utmToWgs84(west, south, 48, true);
      final ne = _utmToWgs84(east, north, 48, true);
      if (sw != null && ne != null) {
        return [sw[0], sw[1], ne[0], ne[1]]; // [west, south, east, north] in lon,lat
      }
    }

    // Detect VN-2000 TM3 (common for provincial data)
    // VN-2000 uses various central meridians (102, 103, 104, ..., 111)
    // Easting typically around 500000 (false easting), Northing > 1000000
    if (west > 100000 && south > 1000000) {
      debugPrint('GeoTiffService: Trying VN-2000 TM3 conversion (CM=105)');
      // Assume central meridian 105 (most common)
      final sw = _tm3ToWgs84(west, south, 105.0, 500000.0, 0.9999);
      final ne = _tm3ToWgs84(east, north, 105.0, 500000.0, 0.9999);
      if (sw != null && ne != null) {
        return [sw[0], sw[1], ne[0], ne[1]];
      }
    }

    return null;
  }

  /// Convert UTM to WGS84 (lon, lat)
  List<double>? _utmToWgs84(double easting, double northing, int zone, bool isNorth) {
    const double a = 6378137.0; // WGS84 semi-major axis
    const double f = 1 / 298.257223563;
    const double e2 = 2 * f - f * f;
    final double e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2));
    const double k0 = 0.9996;

    final x = easting - 500000.0;
    final y = isNorth ? northing : northing - 10000000.0;

    final m = y / k0;
    final mu = m / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64));

    final phi1 = mu + (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * math.sin(2 * mu)
        + (21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * math.sin(4 * mu)
        + (151 * e1 * e1 * e1 / 96) * math.sin(6 * mu);

    final n1 = a / math.sqrt(1 - e2 * math.sin(phi1) * math.sin(phi1));
    final t1 = math.tan(phi1) * math.tan(phi1);
    final c1 = e2 / (1 - e2) * math.cos(phi1) * math.cos(phi1);
    final r1 = a * (1 - e2) / math.pow(1 - e2 * math.sin(phi1) * math.sin(phi1), 1.5);
    final d = x / (n1 * k0);

    final lat = phi1 - (n1 * math.tan(phi1) / r1) * (
        d * d / 2
            - (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * e2 / (1 - e2)) * d * d * d * d / 24
            + (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1) * d * d * d * d * d * d / 720
    );

    final lon = (d - (1 + 2 * t1 + c1) * d * d * d / 6
        + (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * e2 / (1 - e2) + 24 * t1 * t1) * d * d * d * d * d / 120
    ) / math.cos(phi1);

    final lonDeg = lon * 180 / math.pi + (zone * 6 - 183);
    final latDeg = lat * 180 / math.pi;

    if (latDeg.isNaN || lonDeg.isNaN || latDeg.abs() > 90 || lonDeg.abs() > 180) {
      return null;
    }

    return [lonDeg, latDeg];
  }

  /// Convert TM3 (VN-2000) to WGS84
  List<double>? _tm3ToWgs84(double easting, double northing, double centralMeridian, double falseEasting, double scaleFactor) {
    const double a = 6378137.0;
    const double f = 1 / 298.257223563;
    const double e2 = 2 * f - f * f;
    final double e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2));

    final x = (easting - falseEasting) / scaleFactor;
    final y = northing / scaleFactor;

    final m = y;
    final mu = m / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64));

    final phi1 = mu + (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * math.sin(2 * mu)
        + (21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * math.sin(4 * mu)
        + (151 * e1 * e1 * e1 / 96) * math.sin(6 * mu);

    final n1 = a / math.sqrt(1 - e2 * math.sin(phi1) * math.sin(phi1));
    final t1 = math.tan(phi1) * math.tan(phi1);
    final c1 = e2 / (1 - e2) * math.cos(phi1) * math.cos(phi1);
    final r1 = a * (1 - e2) / math.pow(1 - e2 * math.sin(phi1) * math.sin(phi1), 1.5);
    final d = x / n1;

    final lat = phi1 - (n1 * math.tan(phi1) / r1) * (
        d * d / 2
            - (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * e2 / (1 - e2)) * d * d * d * d / 24
    );

    final lon = (d - (1 + 2 * t1 + c1) * d * d * d / 6) / math.cos(phi1);

    final lonDeg = lon * 180 / math.pi + centralMeridian;
    final latDeg = lat * 180 / math.pi;

    if (latDeg.isNaN || lonDeg.isNaN || latDeg.abs() > 90 || lonDeg.abs() > 180) {
      return null;
    }

    return [lonDeg, latDeg];
  }

  /// Read doubles from ByteData
  List<double> _readDoubles(ByteData bd, int offset, int count, Endian endian) {
    final result = <double>[];
    for (int i = 0; i < count && offset + i * 8 + 8 <= bd.lengthInBytes; i++) {
      result.add(bd.getFloat64(offset + i * 8, endian));
    }
    return result;
  }

  /// Parse .tfw world file for bounds
  Future<GeoTiffInfo?> _parseWorldFile(String tiffPath, Uint8List tiffBytes) async {
    // Try common world file extensions
    final baseName = tiffPath.replaceAll(RegExp(r'\.(tif|tiff)$', caseSensitive: false), '');
    final worldExts = ['.tfw', '.wld', '.tifw'];

    for (final ext in worldExts) {
      final worldPath = '$baseName$ext';
      final worldFile = File(worldPath);
      if (await worldFile.exists()) {
        debugPrint('GeoTiffService: Found world file: $worldPath');
        final content = await worldFile.readAsString();
        return _parseWorldFileContent(content, tiffBytes);
      }
    }

    // Also try .TFW (uppercase)
    for (final ext in ['.TFW', '.WLD']) {
      final worldPath = '$baseName$ext';
      final worldFile = File(worldPath);
      if (await worldFile.exists()) {
        final content = await worldFile.readAsString();
        return _parseWorldFileContent(content, tiffBytes);
      }
    }

    return null;
  }

  /// Parse world file content (6 lines)
  GeoTiffInfo? _parseWorldFileContent(String content, Uint8List tiffBytes) {
    final lines = content.trim().split(RegExp(r'[\r\n]+'));
    if (lines.length < 6) return null;

    final scaleX = double.tryParse(lines[0].trim());
    final rotY = double.tryParse(lines[1].trim());
    final rotX = double.tryParse(lines[2].trim());
    final scaleY = double.tryParse(lines[3].trim()); // negative
    final originX = double.tryParse(lines[4].trim()); // X of upper-left center
    final originY = double.tryParse(lines[5].trim()); // Y of upper-left center

    if (scaleX == null || scaleY == null || originX == null || originY == null) {
      return null;
    }

    // Get image dimensions from TIFF header
    final dims = _getImageDimensions(tiffBytes);
    if (dims == null) return null;

    final width = dims[0];
    final height = dims[1];

    // Calculate bounds (ignore rotation for now)
    var west = originX - scaleX / 2; // pixel center to edge
    var north = originY - scaleY / 2;
    var east = west + width * scaleX;
    var south = north + height * scaleY; // scaleY is negative

    // Swap if needed
    if (south > north) {
      final tmp = south;
      south = north;
      north = tmp;
    }

    // Check if projected coordinates
    if (west.abs() > 360 || north.abs() > 360) {
      final converted = _tryConvertToWgs84(west, south, east, north);
      if (converted != null) {
        west = converted[0];
        south = converted[1];
        east = converted[2];
        north = converted[3];
      } else {
        return null;
      }
    }

    return GeoTiffInfo(
      north: north,
      south: south,
      east: east,
      west: west,
      width: width,
      height: height,
      crsName: 'tfw',
    );
  }

  /// Get image dimensions from TIFF header
  List<int>? _getImageDimensions(Uint8List bytes) {
    if (bytes.length < 8) return null;

    final byteOrder = String.fromCharCodes(bytes.sublist(0, 2));
    final isLittleEndian = byteOrder == 'II';
    final bd = ByteData.sublistView(bytes);
    final endian = isLittleEndian ? Endian.little : Endian.big;

    final ifdOffset = bd.getUint32(4, endian);
    if (ifdOffset >= bytes.length - 2) return null;

    final numEntries = bd.getUint16(ifdOffset, endian);
    int? width, height;

    for (int i = 0; i < numEntries && ifdOffset + 2 + i * 12 + 12 <= bytes.length; i++) {
      final entryOffset = ifdOffset + 2 + i * 12;
      final tag = bd.getUint16(entryOffset, endian);
      final type = bd.getUint16(entryOffset + 2, endian);

      switch (tag) {
        case 256:
          width = (type == 3) ? bd.getUint16(entryOffset + 8, endian) : bd.getUint32(entryOffset + 8, endian);
          break;
        case 257:
          height = (type == 3) ? bd.getUint16(entryOffset + 8, endian) : bd.getUint32(entryOffset + 8, endian);
          break;
      }
    }

    if (width != null && height != null) return [width, height];
    return null;
  }

  /// Convert TIFF to PNG for overlay display
  /// Returns path to saved PNG file
  Future<String?> _convertTiffToPng(Uint8List bytes, String originalPath) async {
    try {
      debugPrint('GeoTiffService: Decoding TIFF...');
      final decoded = img.decodeTiff(bytes);
      if (decoded == null) {
        debugPrint('GeoTiffService: Failed to decode TIFF');
        return null;
      }

      debugPrint('GeoTiffService: Decoded ${decoded.width}x${decoded.height}');

      // Resize if too large for mobile (max 4096px on either side)
      var output = decoded;
      const maxSize = 4096;
      if (decoded.width > maxSize || decoded.height > maxSize) {
        final scale = maxSize / math.max(decoded.width, decoded.height);
        final newW = (decoded.width * scale).round();
        final newH = (decoded.height * scale).round();
        debugPrint('GeoTiffService: Resizing to ${newW}x$newH');
        output = img.copyResize(decoded, width: newW, height: newH,
            interpolation: img.Interpolation.linear);
      }

      // Encode as PNG
      debugPrint('GeoTiffService: Encoding PNG...');
      final pngBytes = img.encodePng(output, level: 6); // level 6 = good compression/speed balance

      // Save to app overlay directory
      final appDir = await getApplicationDocumentsDirectory();
      final overlayDir = Directory(p.join(appDir.path, 'LVTField', 'overlays'));
      if (!await overlayDir.exists()) {
        await overlayDir.create(recursive: true);
      }

      final pngName = '${const Uuid().v4()}.png';
      final pngPath = p.join(overlayDir.path, pngName);
      await File(pngPath).writeAsBytes(pngBytes);

      debugPrint('GeoTiffService: Saved PNG to $pngPath (${(pngBytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
      return pngPath;
    } catch (e) {
      debugPrint('GeoTiffService: PNG conversion error: $e');
      return null;
    }
  }
}
