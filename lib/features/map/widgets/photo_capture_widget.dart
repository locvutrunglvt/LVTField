import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/media_service.dart';
import '../../../core/services/gps_service.dart';
import '../../../data/models/media_model.dart';
import '../../../data/repositories/media_repository.dart';
import 'photo_viewer.dart';

/// Widget for capturing and managing photos attached to a feature
/// Shown as a bottom sheet with camera/gallery options and photo grid
/// Author: Lộc Vũ Trung
class PhotoCaptureWidget extends StatefulWidget {
  final String featureId;
  final String projectId;

  const PhotoCaptureWidget({
    super.key,
    required this.featureId,
    required this.projectId,
  });

  /// Show the photo capture widget as a modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String featureId,
    required String projectId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSizes.radiusLg),
            ),
          ),
          child: PhotoCaptureWidget(
            featureId: featureId,
            projectId: projectId,
          ),
        ),
      ),
    );
  }

  @override
  State<PhotoCaptureWidget> createState() => _PhotoCaptureWidgetState();
}

class _PhotoCaptureWidgetState extends State<PhotoCaptureWidget> {
  final MediaService _mediaService = MediaService();
  final MediaRepository _mediaRepository = MediaRepository();
  final GpsService _gpsService = GpsService();

  List<MediaModel> _photos = [];
  bool _isLoading = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  /// Load all existing photos for this feature
  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    try {
      _photos = await _mediaRepository.getByFeatureId(widget.featureId);
    } catch (e) {
      debugPrint('PhotoCaptureWidget _loadPhotos error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Take a photo from camera and save it
  Future<void> _takePhoto() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final filePath = await _mediaService.takePhoto(
        projectId: widget.projectId,
        featureId: widget.featureId,
      );

      if (filePath != null) {
        await _saveMediaRecord(filePath);
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Pick a photo from gallery and save it
  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final filePath = await _mediaService.pickFromGallery(
        projectId: widget.projectId,
        featureId: widget.featureId,
      );

      if (filePath != null) {
        await _saveMediaRecord(filePath);
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Create a media record with GPS coordinates and persist it
  Future<void> _saveMediaRecord(String filePath) async {
    // Get current GPS position for geo-tagging
    final gpsPos = await _gpsService.getCurrentPosition();

    final media = MediaModel(
      featureId: widget.featureId,
      filePath: filePath,
      mediaType: MediaType.photo,
      latitude: gpsPos?.latLng.latitude,
      longitude: gpsPos?.latLng.longitude,
    );

    await _mediaRepository.insert(media);
    await _loadPhotos();
  }

  /// Delete a photo with confirmation dialog
  Future<void> _deletePhoto(MediaModel media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa ảnh'),
        content: const Text('Bạn có chắc muốn xóa ảnh này không?'),
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
      await _mediaService.deleteMediaFile(media.filePath);
      await _mediaRepository.delete(media.id);
      await _loadPhotos();
    }
  }

  /// Open the full-screen photo viewer
  void _viewPhoto(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: _photos,
          initialIndex: index,
          onDelete: (media) async {
            await _mediaService.deleteMediaFile(media.filePath);
            await _mediaRepository.delete(media.id);
            await _loadPhotos();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: AppSizes.sm),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          ),
        ),

        // Header with photo count badge
        Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            children: [
              const Icon(Icons.photo_library, color: AppColors.primary),
              const SizedBox(width: AppSizes.sm),
              const Text(
                'Ảnh đính kèm',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              // Photo count badge
              if (_photos.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                  child: Text(
                    '${_photos.length}',
                    style: const TextStyle(
                      color: AppColors.textOnPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              // Close button
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
          child: Row(
            children: [
              // Camera button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Chụp ảnh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    minimumSize: const Size(0, AppSizes.buttonHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              // Gallery button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isCapturing ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(0, AppSizes.buttonHeight),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSizes.md),
        const Divider(height: 1),

        // Photo grid
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _photos.isEmpty
                  ? _buildEmptyState()
                  : _buildPhotoGrid(),
        ),
      ],
    );
  }

  /// Empty state when no photos are attached
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: AppSizes.iconXl * 1.5,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSizes.md),
          const Text(
            'Chưa có ảnh nào',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          const Text(
            'Chụp ảnh hoặc chọn từ thư viện',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Grid view of photo thumbnails
  Widget _buildPhotoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSizes.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSizes.xs,
        mainAxisSpacing: AppSizes.xs,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return _buildPhotoTile(photo, index);
      },
    );
  }

  /// Individual photo tile with tap and long-press gestures
  Widget _buildPhotoTile(MediaModel photo, int index) {
    final file = File(photo.filePath);

    return GestureDetector(
      onTap: () => _viewPhoto(index),
      onLongPress: () => _deletePhoto(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo thumbnail
            file.existsSync()
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.background,
                      child: const Icon(
                        Icons.broken_image,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : Container(
                    color: AppColors.background,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: AppColors.textSecondary,
                    ),
                  ),

            // GPS indicator
            if (photo.latitude != null && photo.longitude != null)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
