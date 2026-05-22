import 'package:uuid/uuid.dart';

/// Types of media attachments
enum MediaType { photo, video, audio }

/// Represents a media file attached to a feature
class MediaModel {
  final String id;
  final String featureId;
  final String filePath;
  final MediaType mediaType;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final DateTime capturedAt;

  MediaModel({
    String? id,
    required this.featureId,
    required this.filePath,
    this.mediaType = MediaType.photo,
    this.caption,
    this.latitude,
    this.longitude,
    DateTime? capturedAt,
  })
      : id = id ?? const Uuid().v4(),
        capturedAt = capturedAt ?? DateTime.now();

  factory MediaModel.fromMap(Map<String, dynamic> map) {
    return MediaModel(
      id: map['id'] as String,
      featureId: map['feature_id'] as String,
      filePath: map['file_path'] as String,
      mediaType: MediaType.values.firstWhere(
        (e) => e.name == (map['media_type'] as String),
      ),
      caption: map['caption'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      capturedAt: DateTime.parse(map['captured_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'feature_id': featureId,
      'file_path': filePath,
      'media_type': mediaType.name,
      'caption': caption,
      'latitude': latitude,
      'longitude': longitude,
      'captured_at': capturedAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'MediaModel(id: $id, type: ${mediaType.name})';
}
