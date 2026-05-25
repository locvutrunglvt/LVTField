import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite/sqflite.dart';

/// Custom TileProvider that reads tiles from an MBTiles SQLite database
class MBTilesTileProvider extends TileProvider {
  final String dbPath;
  Database? _db;
  bool _initialized = false;

  // MBTiles metadata
  int minZoom = 0;
  int maxZoom = 22;
  String format = 'png';

  MBTilesTileProvider({required this.dbPath});

  /// Initialize the database connection and read metadata
  Future<void> init() async {
    if (_initialized) return;
    try {
      _db = await openDatabase(dbPath, readOnly: true);
      _initialized = true;

      // Read metadata
      final rows = await _db!.rawQuery('SELECT name, value FROM metadata');
      for (final row in rows) {
        final name = row['name'] as String;
        final value = row['value'] as String;
        switch (name) {
          case 'minzoom':
            minZoom = int.tryParse(value) ?? 0;
            break;
          case 'maxzoom':
            maxZoom = int.tryParse(value) ?? 22;
            break;
          case 'format':
            format = value;
            break;
        }
      }
      debugPrint('MBTilesTileProvider: init OK, z=$minZoom-$maxZoom, fmt=$format');
    } catch (e) {
      debugPrint('MBTilesTileProvider: init error - $e');
    }
  }

  /// Get tile image from MBTiles database
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MBTilesImageProvider(
      db: _db,
      x: coordinates.x,
      y: coordinates.y,
      z: coordinates.z,
    );
  }

  /// Close database when disposing
  Future<void> dispose() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _initialized = false;
    }
  }
}

/// Custom ImageProvider that loads tile data from MBTiles SQLite
class MBTilesImageProvider extends ImageProvider<MBTilesImageProvider> {
  final Database? db;
  final int x, y, z;

  const MBTilesImageProvider({
    required this.db,
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  Future<MBTilesImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MBTilesImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      MBTilesImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadTile(ImageDecoderCallback decode) async {
    if (db == null || !db!.isOpen) {
      return _transparentTile(decode);
    }

    // MBTiles uses TMS y-coordinate (flipped from XYZ)
    final tmsY = (1 << z) - 1 - y;

    try {
      final rows = await db!.rawQuery(
        'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, tmsY],
      );

      if (rows.isEmpty || rows.first['tile_data'] == null) {
        return _transparentTile(decode);
      }

      final data = rows.first['tile_data'] as Uint8List;
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      return decode(buffer);
    } catch (e) {
      debugPrint('MBTiles tile error z=$z x=$x y=$y: $e');
      return _transparentTile(decode);
    }
  }

  /// Return a 1x1 transparent PNG for missing tiles
  Future<ui.Codec> _transparentTile(ImageDecoderCallback decode) async {
    // Minimal 1x1 transparent PNG
    final bytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT
      0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
      0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, // IEND
      0x60, 0x82,
    ]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MBTilesImageProvider &&
        other.x == x &&
        other.y == y &&
        other.z == z &&
        other.db == db;
  }

  @override
  int get hashCode => Object.hash(x, y, z, db);
}
