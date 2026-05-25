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
    final bool isBigTiff = magic == 43;
    if (magic != 42 && magic != 43) {
      debugPrint('GeoTiffService: Not a valid TIFF (magic=$magic)');
      return null;
    }

    // Get first IFD offset
    int ifdOffset;
    int entrySize; // 12 for classic TIFF, 20 for BigTIFF
    if (isBigTiff) {
      // BigTIFF: bytes 8-15 = first IFD offset (8 bytes)
      if (bytes.length < 16) return null;
      ifdOffset = bd.getUint64(8, endian);
      entrySize = 20;
      debugPrint('GeoTiffService: BigTIFF detected, IFD at $ifdOffset');
    } else {
      ifdOffset = bd.getUint32(4, endian);
      entrySize = 12;
    }

    // Parse IFD entries
    int? imageWidth;
    int? imageHeight;
    List<double>? modelPixelScale; // Tag 33550
    List<double>? modelTiepoint;   // Tag 33922
    List<int>? geoKeyDirectory;    // Tag 34735
    int? epsgCode;

    while (ifdOffset > 0 && ifdOffset < bytes.length - 2) {
      int numEntries;
      int entryStart;

      if (isBigTiff) {
        if (ifdOffset + 8 > bytes.length) break;
        numEntries = bd.getUint64(ifdOffset, endian);
        entryStart = ifdOffset + 8;
      } else {
        numEntries = bd.getUint16(ifdOffset, endian);
        entryStart = ifdOffset + 2;
      }

      for (int i = 0; i < numEntries && entryStart + entrySize <= bytes.length; i++) {
        final tag = bd.getUint16(entryStart, endian);
        final type = bd.getUint16(entryStart + 2, endian);

        int count;
        int valueOrOffset;
        if (isBigTiff) {
          count = bd.getUint64(entryStart + 4, endian);
          valueOrOffset = bd.getUint64(entryStart + 12, endian);
        } else {
          count = bd.getUint32(entryStart + 4, endian);
          valueOrOffset = bd.getUint32(entryStart + 8, endian);
        }

        switch (tag) {
          case 256: // ImageWidth
            if (isBigTiff) {
              imageWidth = (type == 3) ? bd.getUint16(entryStart + 12, endian) : valueOrOffset;
            } else {
              imageWidth = (type == 3) ? bd.getUint16(entryStart + 8, endian) : valueOrOffset;
            }
            break;
          case 257: // ImageLength (height)
            if (isBigTiff) {
              imageHeight = (type == 3) ? bd.getUint16(entryStart + 12, endian) : valueOrOffset;
            } else {
              imageHeight = (type == 3) ? bd.getUint16(entryStart + 8, endian) : valueOrOffset;
            }
            break;
          case 33550: // ModelPixelScaleTag
            if (count >= 2 && type == 12 && valueOrOffset + count * 8 <= bytes.length) {
              modelPixelScale = _readDoubles(bd, valueOrOffset, count, endian);
            }
            break;
          case 33922: // ModelTiepointTag
            if (count >= 6 && type == 12 && valueOrOffset + count * 8 <= bytes.length) {
              modelTiepoint = _readDoubles(bd, valueOrOffset, count, endian);
            }
            break;
          case 34735: // GeoKeyDirectoryTag
            if (type == 3 && valueOrOffset + count * 2 <= bytes.length) {
              geoKeyDirectory = <int>[];
              for (int k = 0; k < count && valueOrOffset + k * 2 + 2 <= bytes.length; k++) {
                geoKeyDirectory.add(bd.getUint16(valueOrOffset + k * 2, endian));
              }
            }
            break;
        }

        entryStart += entrySize;
      }

      // Next IFD
      if (isBigTiff) {
        if (entryStart + 8 <= bytes.length) {
          ifdOffset = bd.getUint64(entryStart, endian);
        } else {
          break;
        }
      } else {
        if (entryStart + 4 <= bytes.length) {
          ifdOffset = bd.getUint32(entryStart, endian);
        } else {
          break;
        }
      }
    }

    // Parse EPSG from GeoKeyDirectory
    if (geoKeyDirectory != null && geoKeyDirectory.length >= 4) {
      // Format: [KeyDirVersion, KeyRevision, MinorRev, NumKeys, key1ID, key1Loc, key1Count, key1Val, ...]
      final numKeys = geoKeyDirectory[3];
      for (int k = 0; k < numKeys && (4 + k * 4 + 3) < geoKeyDirectory.length; k++) {
        final keyId = geoKeyDirectory[4 + k * 4];
        final keyLoc = geoKeyDirectory[4 + k * 4 + 1];
        final keyVal = geoKeyDirectory[4 + k * 4 + 3];
        // ProjectedCSTypeGeoKey = 3072, GeographicTypeGeoKey = 2048
        if (keyId == 3072 && keyLoc == 0) {
          epsgCode = keyVal;
          debugPrint('GeoTiffService: Found ProjectedCSType EPSG:$epsgCode');
        } else if (keyId == 2048 && keyLoc == 0 && epsgCode == null) {
          epsgCode = keyVal;
          debugPrint('GeoTiffService: Found GeographicCSType EPSG:$epsgCode');
        }
      }
    }

    if (imageWidth == null || imageHeight == null) {
      debugPrint('GeoTiffService: Missing image dimensions');
      return null;
    }

    debugPrint('GeoTiffService: Image size: ${imageWidth}x$imageHeight');
    debugPrint('GeoTiffService: PixelScale: $modelPixelScale');
    debugPrint('GeoTiffService: Tiepoint: $modelTiepoint');
    debugPrint('GeoTiffService: EPSG: $epsgCode');

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
      String? crsName;
      if (west.abs() > 360 || north.abs() > 360) {
        // Likely projected coordinates
        debugPrint('GeoTiffService: Detected projected CRS (values > 360)');
        crsName = 'projected';

        // Determine UTM zone from EPSG code
        int? utmZone;
        bool isNorth = true;
        if (epsgCode != null) {
          // EPSG 326xx = UTM zone xx North, 327xx = UTM zone xx South
          if (epsgCode >= 32601 && epsgCode <= 32660) {
            utmZone = epsgCode - 32600;
            isNorth = true;
            crsName = 'EPSG:$epsgCode (UTM ${utmZone}N)';
          } else if (epsgCode >= 32701 && epsgCode <= 32760) {
            utmZone = epsgCode - 32700;
            isNorth = false;
            crsName = 'EPSG:$epsgCode (UTM ${utmZone}S)';
          }
        }

        bool converted = false;

        // Try EPSG-based UTM conversion first
        if (utmZone != null) {
          debugPrint('GeoTiffService: Converting UTM zone $utmZone ${isNorth ? "N" : "S"}');
          final sw = _utmToWgs84(west, south, utmZone, isNorth);
          final ne = _utmToWgs84(east, north, utmZone, isNorth);
          if (sw != null && ne != null) {
            west = sw[0]; south = sw[1]; east = ne[0]; north = ne[1];
            converted = true;
          }
        }

        // Fallback to auto-detect
        if (!converted) {
          final result = _tryConvertToWgs84(west, south, east, north);
          if (result != null) {
            west = result[0]; south = result[1]; east = result[2]; north = result[3];
            crsName = 'auto_converted';
            converted = true;
          }
        }

        if (!converted) {
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

      // Detect BigTIFF vs standard TIFF
      final byteOrder = String.fromCharCodes(bytes.sublist(0, 2));
      final isLE = byteOrder == 'II';
      final endian = isLE ? Endian.little : Endian.big;
      final magic = ByteData.sublistView(bytes).getUint16(2, endian);

      img.Image? decoded;
      if (magic == 43) {
        debugPrint('GeoTiffService: BigTIFF → custom decoder');
        decoded = _decodeBigTiff(bytes);
      } else {
        decoded = img.decodeTiff(bytes);
      }

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
      final pngBytes = img.encodePng(output, level: 6);

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

  // =========================================================================
  // BigTIFF Decoder
  // =========================================================================

  /// Decode BigTIFF (20-byte IFD entries) → img.Image
  img.Image? _decodeBigTiff(Uint8List bytes) {
    try {
      final isLE = String.fromCharCodes(bytes.sublist(0, 2)) == 'II';
      final bd = ByteData.sublistView(bytes);
      final endian = isLE ? Endian.little : Endian.big;

      final ifdOffset = bd.getUint64(8, endian);
      if (ifdOffset + 8 > bytes.length) return null;
      final numEntries = bd.getUint64(ifdOffset, endian);

      int imgW = 0, imgH = 0, tileW = 0, tileH = 0;
      int compression = 1, spp = 1, bps = 8;
      int predictor = 1;
      List<int> tileOffsets = [], tileByteCounts = [];

      int pos = ifdOffset + 8;
      for (int i = 0; i < numEntries && pos + 20 <= bytes.length; i++) {
        final tag = bd.getUint16(pos, endian);
        final type = bd.getUint16(pos + 2, endian);
        final count = bd.getUint64(pos + 4, endian);

        // Read inline SHORT or LONG value from BigTIFF entry
        int inlineVal() {
          if (type == 3) return bd.getUint16(pos + 12, endian); // SHORT
          if (type == 4) return bd.getUint32(pos + 12, endian); // LONG
          return bd.getUint64(pos + 12, endian); // LONG8
        }

        switch (tag) {
          case 256: imgW = inlineVal(); break;
          case 257: imgH = inlineVal(); break;
          case 258: bps = inlineVal(); break; // First BitsPerSample
          case 259: compression = inlineVal(); break;
          case 277: spp = inlineVal(); break;
          case 317: predictor = inlineVal(); break;
          case 322: tileW = inlineVal(); break;
          case 323: tileH = inlineVal(); break;
          case 324: // TileOffsets
            final off = bd.getUint64(pos + 12, endian);
            for (int t = 0; t < count && off + t * (type == 16 ? 8 : 4) < bytes.length; t++) {
              tileOffsets.add(type == 16
                  ? bd.getUint64(off + t * 8, endian)
                  : bd.getUint32(off + t * 4, endian));
            }
            break;
          case 325: // TileByteCounts
            final off = bd.getUint64(pos + 12, endian);
            for (int t = 0; t < count && off + t * (type == 16 ? 8 : 4) < bytes.length; t++) {
              tileByteCounts.add(type == 16
                  ? bd.getUint64(off + t * 8, endian)
                  : bd.getUint32(off + t * 4, endian));
            }
            break;
        }
        pos += 20;
      }

      debugPrint('BigTIFF: ${imgW}x$imgH tile=${tileW}x$tileH comp=$compression '
          'bps=$bps spp=$spp pred=$predictor tiles=${tileOffsets.length}');

      if (imgW == 0 || imgH == 0 || tileW == 0 || tileH == 0) return null;
      if (tileOffsets.length != tileByteCounts.length) return null;
      if (compression != 5 && compression != 8 && compression != 1) {
        debugPrint('BigTIFF: Unsupported compression: $compression');
        return null;
      }

      final bytesPS = bps ~/ 8; // bytes per sample
      final tileCols = (imgW + tileW - 1) ~/ tileW;

      // ── Pass 1: find max value for auto-stretch (sample first 4 tiles) ──
      int globalMax = 0;
      if (bps > 8) {
        for (int ti = 0; ti < math.min(tileOffsets.length, 4); ti++) {
          final raw = _decompressTile(bytes, tileOffsets[ti], tileByteCounts[ti], compression);
          if (raw == null) continue;
          if (predictor == 2) _undoHDiff(raw, tileW, tileH, spp, bytesPS, isLE);
          final rbd = ByteData.sublistView(raw);
          final pxEnd = isLE ? Endian.little : Endian.big;
          for (int p = 0; p < raw.length - 1; p += bytesPS * spp) {
            for (int s = 0; s < math.min(spp, 3); s++) {
              final off = p + s * bytesPS;
              if (off + 2 <= raw.length) {
                final v = rbd.getUint16(off, pxEnd);
                if (v > globalMax) globalMax = v;
              }
            }
          }
        }
        if (globalMax == 0) globalMax = (1 << bps) - 1;
      } else {
        globalMax = 255;
      }

      // Use 98th percentile approximation: clip at 90% of max
      final stretchMax = (globalMax * 0.9).clamp(1, 65535);
      debugPrint('BigTIFF: auto-stretch max=$globalMax stretchMax=$stretchMax');

      // ── Pass 2: decode tiles → image ──
      final output = img.Image(width: imgW, height: imgH);
      final pxEnd = isLE ? Endian.little : Endian.big;

      for (int ti = 0; ti < tileOffsets.length; ti++) {
        final tileCol = ti % tileCols;
        final tileRow = ti ~/ tileCols;
        final startX = tileCol * tileW;
        final startY = tileRow * tileH;

        final raw = _decompressTile(bytes, tileOffsets[ti], tileByteCounts[ti], compression);
        if (raw == null) continue;
        if (predictor == 2) _undoHDiff(raw, tileW, tileH, spp, bytesPS, isLE);

        final rbd = ByteData.sublistView(raw);

        for (int ty = 0; ty < tileH; ty++) {
          final y = startY + ty;
          if (y >= imgH) break;
          for (int tx = 0; tx < tileW; tx++) {
            final x = startX + tx;
            if (x >= imgW) break;

            final pOff = (ty * tileW + tx) * spp * bytesPS;
            if (pOff + spp * bytesPS > raw.length) break;

            int r, g, b;
            if (bytesPS == 2) {
              if (spp >= 3) {
                r = (rbd.getUint16(pOff, pxEnd) * 255 / stretchMax).clamp(0, 255).round();
                g = (rbd.getUint16(pOff + 2, pxEnd) * 255 / stretchMax).clamp(0, 255).round();
                b = (rbd.getUint16(pOff + 4, pxEnd) * 255 / stretchMax).clamp(0, 255).round();
              } else {
                final v = (rbd.getUint16(pOff, pxEnd) * 255 / stretchMax).clamp(0, 255).round();
                r = g = b = v;
              }
            } else {
              if (spp >= 3) {
                r = raw[pOff]; g = raw[pOff + 1]; b = raw[pOff + 2];
              } else {
                r = g = b = raw[pOff];
              }
            }
            output.setPixelRgba(x, y, r, g, b, 255);
          }
        }
      }

      debugPrint('BigTIFF: Decoded successfully ${imgW}x$imgH');
      return output;
    } catch (e) {
      debugPrint('BigTIFF decode error: $e');
      return null;
    }
  }

  /// Decompress a single tile
  Uint8List? _decompressTile(Uint8List bytes, int offset, int length, int compression) {
    if (offset + length > bytes.length) return null;
    final data = bytes.sublist(offset, offset + length);
    switch (compression) {
      case 1: return data; // No compression
      case 5: return _tiffLzwDecompress(data); // LZW
      case 8: // DEFLATE
        try {
          return Uint8List.fromList(zlib.decode(data));
        } catch (_) {
          try {
            // Try raw deflate without zlib header
            final codec = ZLibCodec(raw: true);
            return Uint8List.fromList(codec.decode(data));
          } catch (_) {
            return null;
          }
        }
      default:
        return null;
    }
  }

  /// Undo horizontal differencing predictor (tag 317 = 2)
  void _undoHDiff(Uint8List raw, int w, int h, int spp, int bps, bool isLE) {
    final endian = isLE ? Endian.little : Endian.big;
    final bd = ByteData.sublistView(raw);
    final rowBytes = w * spp * bps;

    for (int y = 0; y < h; y++) {
      final rowStart = y * rowBytes;
      if (rowStart + rowBytes > raw.length) break;
      for (int x = 1; x < w; x++) {
        for (int s = 0; s < spp; s++) {
          final curr = rowStart + (x * spp + s) * bps;
          final prev = rowStart + ((x - 1) * spp + s) * bps;
          if (curr + bps > raw.length) break;
          if (bps == 2) {
            bd.setUint16(curr, (bd.getUint16(curr, endian) + bd.getUint16(prev, endian)) & 0xFFFF, endian);
          } else {
            raw[curr] = (raw[curr] + raw[prev]) & 0xFF;
          }
        }
      }
    }
  }

  /// TIFF LZW decompression (MSB-first bit packing)
  Uint8List _tiffLzwDecompress(Uint8List input) {
    const clearCode = 256;
    const eoiCode = 257;

    int bitPos = 0;
    int codeSize = 9;

    int readCode() {
      int code = 0;
      for (int i = 0; i < codeSize; i++) {
        final byteIdx = (bitPos + i) ~/ 8;
        final bitIdx = 7 - ((bitPos + i) % 8); // MSB-first
        if (byteIdx < input.length) {
          code = (code << 1) | ((input[byteIdx] >> bitIdx) & 1);
        }
      }
      bitPos += codeSize;
      return code;
    }

    final output = <int>[];
    final table = <List<int>>[];

    void initTable() {
      table.clear();
      for (int i = 0; i < 258; i++) {
        table.add(i < 256 ? [i] : const []);
      }
      codeSize = 9;
    }

    initTable();

    var code = readCode();
    if (code != clearCode) return Uint8List(0);

    code = readCode();
    if (code == eoiCode) return Uint8List(0);

    output.addAll(table[code]);
    var prevEntry = List<int>.from(table[code]);

    while (bitPos < input.length * 8) {
      code = readCode();
      if (code == eoiCode) break;

      if (code == clearCode) {
        initTable();
        code = readCode();
        if (code == eoiCode) break;
        if (code >= table.length) break;
        output.addAll(table[code]);
        prevEntry = List<int>.from(table[code]);
        continue;
      }

      List<int> entry;
      if (code < table.length) {
        entry = table[code];
      } else if (code == table.length) {
        entry = List<int>.from(prevEntry)..add(prevEntry[0]);
      } else {
        break; // Invalid code
      }

      output.addAll(entry);
      table.add(List<int>.from(prevEntry)..add(entry[0]));
      prevEntry = List<int>.from(entry);

      // Increase code size when table reaches next power of 2
      if (table.length >= (1 << codeSize) && codeSize < 12) {
        codeSize++;
      }
    }

    return Uint8List.fromList(output);
  }
}

