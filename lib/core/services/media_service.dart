import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service for camera capture and media file management
/// Handles photo storage in organized project directories
/// Author: Lộc Vũ Trung
class MediaService {
  final ImagePicker _picker = ImagePicker();

  /// Take a photo using the device camera
  /// Returns the saved file path, or null if cancelled
  Future<String?> takePhoto({
    required String projectId,
    required String featureId,
  }) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (photo == null) return null;

      return _saveToMediaDirectory(
        sourcePath: photo.path,
        projectId: projectId,
        featureId: featureId,
      );
    } catch (e) {
      debugPrint('MediaService takePhoto error: $e');
      return null;
    }
  }

  /// Pick a photo from the device gallery
  /// Returns the saved file path, or null if cancelled
  Future<String?> pickFromGallery({
    required String projectId,
    required String featureId,
  }) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (photo == null) return null;

      return _saveToMediaDirectory(
        sourcePath: photo.path,
        projectId: projectId,
        featureId: featureId,
      );
    } catch (e) {
      debugPrint('MediaService pickFromGallery error: $e');
      return null;
    }
  }

  /// Get the media storage directory for a project
  /// Creates the directory if it doesn't exist
  /// Path: Documents/LVTField/media/{projectId}/
  Future<String> getMediaDirectory(String projectId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(
      p.join(appDir.path, 'LVTField', 'media', projectId),
    );

    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    return mediaDir.path;
  }

  /// Delete a media file from disk
  /// Returns true if successfully deleted
  Future<bool> deleteMediaFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('MediaService deleted: $path');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('MediaService deleteMediaFile error: $e');
      return false;
    }
  }

  /// Get or generate a thumbnail path for a photo
  /// Returns the thumbnail file path (stored in a thumbs/ subdirectory)
  /// If thumbnail doesn't exist yet, returns the original path as fallback
  Future<String> getPhotoThumbnail(String path, {int size = 200}) async {
    try {
      final dir = p.dirname(path);
      final filename = p.basenameWithoutExtension(path);
      final ext = p.extension(path);

      final thumbDir = Directory(p.join(dir, 'thumbs'));
      if (!await thumbDir.exists()) {
        await thumbDir.create(recursive: true);
      }

      final thumbPath = p.join(
        thumbDir.path,
        '${filename}_thumb_$size$ext',
      );

      // If thumbnail already exists, return it
      if (await File(thumbPath).exists()) {
        return thumbPath;
      }

      // For now, return original path as fallback
      // Full thumbnail generation requires image manipulation package
      return path;
    } catch (e) {
      debugPrint('MediaService getPhotoThumbnail error: $e');
      return path;
    }
  }

  /// Copy source file to the organized media directory
  /// with naming convention: {projectId}_{featureId}_{timestamp}.jpg
  Future<String> _saveToMediaDirectory({
    required String sourcePath,
    required String projectId,
    required String featureId,
  }) async {
    final mediaDir = await getMediaDirectory(projectId);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${projectId}_${featureId}_$timestamp.jpg';
    final destPath = p.join(mediaDir, fileName);

    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);

    debugPrint('MediaService saved photo: $destPath');
    return destPath;
  }
}
