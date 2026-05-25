import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// LVTField SQLite database manager
/// Author: Lộc Vũ Trung
class AppDatabase {
  static Database? _database;
  static const String _dbName = 'lvtfield.db';
  static const int _dbVersion = 3;

  /// Get singleton database instance
  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create all tables
  static Future<void> _onCreate(Database db, int version) async {
    // Users table (authentication)
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        full_name TEXT NOT NULL,
        email TEXT,
        organization TEXT,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_login_at TEXT NOT NULL
      )
    ''');

    // Projects table
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        crs TEXT DEFAULT 'EPSG:4326',
        source_file TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        remote_id TEXT
      )
    ''');

    // Layers table
    await db.execute('''
      CREATE TABLE layers (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        name TEXT NOT NULL,
        geometry_type TEXT NOT NULL,
        style_json TEXT,
        z_order INTEGER DEFAULT 0,
        is_visible INTEGER DEFAULT 1,
        opacity REAL DEFAULT 1.0,
        created_at TEXT NOT NULL,
        remote_id TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');

    // Features table
    await db.execute('''
      CREATE TABLE features (
        id TEXT PRIMARY KEY,
        layer_id TEXT NOT NULL,
        coordinates_json TEXT NOT NULL,
        attributes_json TEXT DEFAULT '{}',
        collected_at TEXT NOT NULL,
        collected_by TEXT,
        gps_accuracy REAL,
        is_modified INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        remote_id TEXT,
        version INTEGER DEFAULT 1,
        FOREIGN KEY (layer_id) REFERENCES layers (id) ON DELETE CASCADE
      )
    ''');

    // Media table
    await db.execute('''
      CREATE TABLE media (
        id TEXT PRIMARY KEY,
        feature_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        media_type TEXT DEFAULT 'photo',
        caption TEXT,
        latitude REAL,
        longitude REAL,
        captured_at TEXT NOT NULL,
        FOREIGN KEY (feature_id) REFERENCES features (id) ON DELETE CASCADE
      )
    ''');

    // Form templates table
    await db.execute('''
      CREATE TABLE form_fields (
        id TEXT PRIMARY KEY,
        layer_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        label TEXT NOT NULL,
        field_type TEXT DEFAULT 'text',
        default_value TEXT,
        options_json TEXT,
        is_required INTEGER DEFAULT 0,
        validation_rule TEXT,
        hint TEXT,
        auto_source TEXT,
        sort_order INTEGER DEFAULT 0,
        FOREIGN KEY (layer_id) REFERENCES layers (id) ON DELETE CASCADE
      )
    ''');

    // GPS tracks table
    await db.execute('''
      CREATE TABLE gps_tracks (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        name TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        accuracy REAL,
        speed REAL,
        recorded_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for performance
    await db.execute('CREATE INDEX idx_users_username ON users (username)');
    await db.execute('CREATE INDEX idx_layers_project ON layers (project_id)');
    await db.execute('CREATE INDEX idx_features_layer ON features (layer_id)');
    await db.execute('CREATE INDEX idx_media_feature ON media (feature_id)');
    await db.execute('CREATE INDEX idx_form_fields_layer ON form_fields (layer_id)');
    await db.execute('CREATE INDEX idx_gps_tracks_project ON gps_tracks (project_id)');
  }

  /// Handle database upgrades
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add users table for authentication
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id TEXT PRIMARY KEY,
          username TEXT NOT NULL UNIQUE,
          full_name TEXT NOT NULL,
          email TEXT,
          organization TEXT,
          password_hash TEXT NOT NULL,
          created_at TEXT NOT NULL,
          last_login_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_users_username ON users (username)',
      );
    }

    if (oldVersion < 3) {
      // Add sync columns for LVT Sync
      await db.execute('ALTER TABLE projects ADD COLUMN remote_id TEXT');
      await db.execute('ALTER TABLE layers ADD COLUMN remote_id TEXT');
      await db.execute('ALTER TABLE features ADD COLUMN remote_id TEXT');
      await db.execute('ALTER TABLE features ADD COLUMN version INTEGER DEFAULT 1');
    }
  }

  /// Close the database
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
