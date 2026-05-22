import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/media_model.dart';

/// Full-screen photo viewer with pinch-to-zoom and swipe navigation
/// Displays photo metadata: caption, GPS coordinates, timestamp
/// Author: Lộc Vũ Trung
class PhotoViewer extends StatefulWidget {
  final List<MediaModel> photos;
  final int initialIndex;
  final Future<void> Function(MediaModel media)? onDelete;

  const PhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.onDelete,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late List<MediaModel> _photos;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _photos = List.from(widget.photos);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Toggle overlay visibility on tap
  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
  }

  /// Share the current photo via system share sheet
  Future<void> _sharePhoto() async {
    final photo = _photos[_currentIndex];
    final file = File(photo.filePath);

    if (await file.exists()) {
      await Share.shareXFiles([XFile(photo.filePath)]);
    }
  }

  /// Delete current photo with confirmation
  Future<void> _deleteCurrentPhoto() async {
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
      final photo = _photos[_currentIndex];
      await widget.onDelete?.call(photo);

      setState(() {
        _photos.removeAt(_currentIndex);
        if (_photos.isEmpty) {
          Navigator.pop(context);
          return;
        }
        if (_currentIndex >= _photos.length) {
          _currentIndex = _photos.length - 1;
        }
      });
    }
  }

  /// Format GPS coordinates for display
  String _formatCoordinates(double lat, double lng) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lngDir = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(6)}° $latDir, '
        '${lng.abs().toStringAsFixed(6)}° $lngDir';
  }

  /// Format timestamp for display
  String _formatTimestamp(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable photo pages
          GestureDetector(
            onTap: _toggleOverlay,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _photos.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final photo = _photos[index];
                final file = File(photo.filePath);

                return Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: file.existsSync()
                        ? Image.file(
                            file,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image,
                              color: Colors.white54,
                              size: 64,
                            ),
                          )
                        : const Icon(
                            Icons.image_not_supported,
                            color: Colors.white54,
                            size: 64,
                          ),
                  ),
                );
              },
            ),
          ),

          // Top overlay - app bar
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        // Back button
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        // Page indicator
                        Expanded(
                          child: Text(
                            '${_currentIndex + 1} / ${_photos.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Share button
                        IconButton(
                          onPressed: _sharePhoto,
                          icon: const Icon(Icons.share, color: Colors.white),
                        ),
                        // Delete button
                        if (widget.onDelete != null)
                          IconButton(
                            onPressed: _deleteCurrentPhoto,
                            icon: const Icon(Icons.delete, color: AppColors.error),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Bottom overlay - metadata
          if (_showOverlay)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildMetadataOverlay(),
            ),
        ],
      ),
    );
  }

  /// Build the bottom metadata overlay showing caption, GPS, and timestamp
  Widget _buildMetadataOverlay() {
    final photo = _photos[_currentIndex];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Caption
              if (photo.caption != null && photo.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    photo.caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              // GPS coordinates
              if (photo.latitude != null && photo.longitude != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppColors.gpsGood,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatCoordinates(photo.latitude!, photo.longitude!),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              // Timestamp
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatTimestamp(photo.capturedAt),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
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
}
