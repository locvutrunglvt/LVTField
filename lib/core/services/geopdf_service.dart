// GeoPDF Service - Parse GeoPDF metadata and convert for overlay display
// Supports: QGIS GeoPDF export with /GPTS geographic coordinates
// Author: Lộc Vũ Trung

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfx/pdfx.dart';

/// Parsed GeoPDF bounds
class GeoPdfInfo {
  final double north;
  final double south;
  final double east;
  final double west;
  final int pageWidth;
  final int pageHeight;

  const GeoPdfInfo({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.pageWidth,
    required this.pageHeight,
  });

  @override
  String toString() => 'GeoPdfInfo(${west.toStringAsFixed(6)},${south.toStringAsFixed(6)} → '
      '${east.toStringAsFixed(6)},${north.toStringAsFixed(6)} ${pageWidth}x$pageHeight)';
}

/// Result of GeoPDF processing
class GeoPdfResult {
  final bool success;
  final String? pngPath;
  final GeoPdfInfo? geoInfo;
  final String? errorMessage;

  const GeoPdfResult({
    required this.success,
    this.pngPath,
    this.geoInfo,
    this.errorMessage,
  });
}

class GeoPdfService {

  /// Process a GeoPDF file: parse bounds + render to PNG overlay
  Future<GeoPdfResult> processGeoPdf(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const GeoPdfResult(success: false, errorMessage: 'File không tồn tại');
    }

    final fileSize = await file.length();
    debugPrint('GeoPdfService: Processing ${p.basename(filePath)} (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

    // Limit file size (50MB)
    if (fileSize > 50 * 1024 * 1024) {
      return const GeoPdfResult(
        success: false,
        errorMessage: 'File PDF quá lớn (>50MB).',
      );
    }

    try {
      // 1. Parse geographic metadata from PDF
      final bytes = await file.readAsBytes();
      final geoInfo = _parseGeoPdfMetadata(bytes);

      if (geoInfo == null) {
        return const GeoPdfResult(
          success: false,
          errorMessage: 'Không tìm thấy thông tin tọa độ trong PDF.\n'
              'File cần là GeoPDF (xuất từ QGIS Layout với tùy chọn Geo-referencing).',
        );
      }

      debugPrint('GeoPdfService: Parsed bounds: $geoInfo');

      // 2. Render PDF page to PNG
      final pngPath = await _renderPdfToPng(filePath);
      if (pngPath == null) {
        return const GeoPdfResult(
          success: false,
          errorMessage: 'Không thể render PDF thành ảnh.',
        );
      }

      return GeoPdfResult(
        success: true,
        pngPath: pngPath,
        geoInfo: geoInfo,
      );
    } catch (e) {
      debugPrint('GeoPdfService: Error: $e');
      return GeoPdfResult(
        success: false,
        errorMessage: 'Lỗi xử lý GeoPDF: $e',
      );
    }
  }

  /// Parse GeoPDF metadata from PDF binary
  /// Looks for /GPTS array containing geographic coordinates
  /// Format: /GPTS [lat1 lon1 lat2 lon2 lat3 lon3 lat4 lon4]
  /// The 4 points represent the corners of the map in order:
  /// bottom-left, bottom-right, top-right, top-left
  GeoPdfInfo? _parseGeoPdfMetadata(Uint8List bytes) {
    // Convert to string for text search (PDF structure is ASCII-based)
    // Use latin1 to avoid encoding issues with binary data
    final content = String.fromCharCodes(bytes);

    // Search for /GPTS array - this contains the geographic coordinates
    // QGIS/GDAL GeoPDF format: /GPTS [lat1 lon1 lat2 lon2 lat3 lon3 lat4 lon4]
    final gptsPattern = RegExp(
      r'/GPTS\s*\[([^\]]+)\]',
      multiLine: true,
    );

    final match = gptsPattern.firstMatch(content);
    if (match == null) {
      debugPrint('GeoPdfService: No /GPTS found in PDF');

      // Try alternative: /Measure dictionary with /GPTS
      final altPattern = RegExp(
        r'GPTS\s*\[([^\]]+)\]',
        multiLine: true,
      );
      final altMatch = altPattern.firstMatch(content);
      if (altMatch == null) {
        debugPrint('GeoPdfService: No GPTS metadata found at all');
        return null;
      }
      return _parseGptsValues(altMatch.group(1)!);
    }

    return _parseGptsValues(match.group(1)!);
  }

  /// Parse GPTS values string into GeoPdfInfo
  /// Values are: lat1 lon1 lat2 lon2 lat3 lon3 lat4 lon4
  /// (4 corners: bottom-left, bottom-right, top-right, top-left)
  GeoPdfInfo? _parseGptsValues(String gptsStr) {
    debugPrint('GeoPdfService: Raw GPTS: $gptsStr');

    final values = gptsStr
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map((s) => double.tryParse(s))
        .toList();

    if (values.length < 8 || values.any((v) => v == null)) {
      debugPrint('GeoPdfService: Invalid GPTS values (need 8 numbers, got ${values.length})');
      return null;
    }

    // GPTS contains 4 corner points as lat/lon pairs
    // Order: BL, BR, TR, TL (Bottom-Left, Bottom-Right, Top-Right, Top-Left)
    final lats = [values[0]!, values[2]!, values[4]!, values[6]!];
    final lons = [values[1]!, values[3]!, values[5]!, values[7]!];

    final south = lats.reduce((a, b) => a < b ? a : b);
    final north = lats.reduce((a, b) => a > b ? a : b);
    final west = lons.reduce((a, b) => a < b ? a : b);
    final east = lons.reduce((a, b) => a > b ? a : b);

    debugPrint('GeoPdfService: Parsed bounds: S=$south W=$west N=$north E=$east');

    // Validate bounds
    if (south >= north || west >= east) {
      debugPrint('GeoPdfService: Invalid bounds');
      return null;
    }
    if (south.abs() > 90 || north.abs() > 90 || west.abs() > 180 || east.abs() > 180) {
      debugPrint('GeoPdfService: Bounds out of range');
      return null;
    }

    return GeoPdfInfo(
      north: north,
      south: south,
      east: east,
      west: west,
      pageWidth: 0,  // Will be updated after render
      pageHeight: 0,
    );
  }

  /// Render first page of PDF to PNG image
  Future<String?> _renderPdfToPng(String pdfPath) async {
    try {
      debugPrint('GeoPdfService: Rendering PDF to PNG...');

      final document = await PdfDocument.openFile(pdfPath);
      final page = await document.getPage(1);

      // Render at high DPI for quality (max 3000px on longest side)
      final double scale;
      if (page.width > page.height) {
        scale = 3000.0 / page.width;
      } else {
        scale = 3000.0 / page.height;
      }
      // Clamp scale to avoid excessive memory
      final renderScale = scale.clamp(1.0, 4.0);

      final pageImage = await page.render(
        width: (page.width * renderScale).round().toDouble(),
        height: (page.height * renderScale).round().toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );

      await page.close();
      await document.close();

      if (pageImage == null || pageImage.bytes.isEmpty) {
        debugPrint('GeoPdfService: Failed to render PDF page');
        return null;
      }

      // Save PNG to overlays directory
      final appDir = await getApplicationDocumentsDirectory();
      final overlayDir = Directory(p.join(appDir.path, 'LVTField', 'overlays'));
      if (!await overlayDir.exists()) {
        await overlayDir.create(recursive: true);
      }

      final pngName = '${const Uuid().v4()}.png';
      final pngPath = p.join(overlayDir.path, pngName);
      await File(pngPath).writeAsBytes(pageImage.bytes);

      final fileSizeMB = (pageImage.bytes.length / 1024 / 1024).toStringAsFixed(1);
      debugPrint('GeoPdfService: Saved PNG ${pageImage.width}x${pageImage.height} ($fileSizeMB MB) to $pngPath');

      return pngPath;
    } catch (e) {
      debugPrint('GeoPdfService: PDF render error: $e');
      return null;
    }
  }
}
