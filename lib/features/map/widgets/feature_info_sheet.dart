import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/feature_model.dart';
import '../../../data/models/layer_model.dart';

/// Bottom sheet showing feature details when a feature is tapped on the map.
/// Supports HTML description from KML data rendered as a styled table popup.
///
/// Author: Loc Vu Trung
class FeatureInfoSheet extends StatefulWidget {
  final FeatureModel feature;
  final LayerModel layer;
  final VoidCallback? onEditAttributes;
  final VoidCallback? onEditGeometry;
  final VoidCallback? onNavigate;
  final VoidCallback? onDelete;
  final VoidCallback? onViewPhotos;
  final VoidCallback? onSplit;
  final VoidCallback? onMerge;

  const FeatureInfoSheet({
    super.key,
    required this.feature,
    required this.layer,
    this.onEditAttributes,
    this.onEditGeometry,
    this.onNavigate,
    this.onDelete,
    this.onViewPhotos,
    this.onSplit,
    this.onMerge,
  });

  /// Show as a modal bottom sheet - tap outside to dismiss
  static Future<T?> show<T>(
    BuildContext context, {
    required FeatureModel feature,
    required LayerModel layer,
    VoidCallback? onEditAttributes,
    VoidCallback? onEditGeometry,
    VoidCallback? onNavigate,
    VoidCallback? onDelete,
    VoidCallback? onViewPhotos,
    VoidCallback? onSplit,
    VoidCallback? onMerge,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true, // tap outside to close
      enableDrag: true,
      builder: (ctx) => FeatureInfoSheet(
        feature: feature,
        layer: layer,
        onEditAttributes: onEditAttributes,
        onEditGeometry: onEditGeometry,
        onNavigate: onNavigate,
        onDelete: onDelete,
        onViewPhotos: onViewPhotos,
        onSplit: onSplit,
        onMerge: onMerge,
      ),
    );
  }

  @override
  State<FeatureInfoSheet> createState() => _FeatureInfoSheetState();
}

class _FeatureInfoSheetState extends State<FeatureInfoSheet> {
  bool _coordsExpanded = false;

  FeatureModel get feature => widget.feature;
  LayerModel get layer => widget.layer;

  /// Decode HTML entities in description to get actual HTML
  String get _decodedDescription {
    final desc = feature.attributes['description']?.toString() ?? '';
    // Decode HTML entities (KML often stores &lt; &gt; instead of < >)
    return desc
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// Check if description contains HTML content (table, div, p, br, span, etc.)
  bool get _hasHtmlDescription {
    final desc = _decodedDescription;
    return desc.contains('<table') || desc.contains('<tr') || desc.contains('<td') ||
        desc.contains('<div') || desc.contains('<p>') || desc.contains('<p ') ||
        desc.contains('<br') || desc.contains('<span');
  }

  /// Parse HTML table from description into key-value pairs.
  /// Supports <table> rows and falls back to <br>/<p>/<div> separated lines
  /// containing "key: value" or "key = value" patterns.
  List<MapEntry<String, String>> _parseHtmlTable() {
    final desc = _decodedDescription;
    final result = <MapEntry<String, String>>[];

    // --- Try table-based parsing first ---
    final trRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
    final tdRegex = RegExp(r'<td[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true);
    final thRegex = RegExp(r'<th[^>]*>(.*?)</th>', caseSensitive: false, dotAll: true);

    for (final trMatch in trRegex.allMatches(desc)) {
      final trContent = trMatch.group(1) ?? '';
      if (thRegex.hasMatch(trContent) && !tdRegex.hasMatch(trContent)) continue;

      final tds = tdRegex.allMatches(trContent).toList();
      if (tds.length >= 2) {
        final key = _stripHtml(tds[0].group(1) ?? '').trim();
        final value = _stripHtml(tds[1].group(1) ?? '').trim();
        if (key.isNotEmpty) {
          result.add(MapEntry(key, value));
        }
      }
    }

    // --- Fallback: parse <br>/<p>/<div> separated key-value lines ---
    if (result.isEmpty) {
      // Split on <br>, <br/>, <p>, </p>, <div>, </div> tags
      final lines = desc
          .replaceAll(RegExp(r'<br\s*/?>\s*|</?(p|div)[^>]*>', caseSensitive: false), '\n')
          .split('\n')
          .map((l) => _stripHtml(l).trim())
          .where((l) => l.isNotEmpty);

      final kvRegex = RegExp(r'^(.+?)\s*[:=]\s*(.+)$');
      for (final line in lines) {
        final match = kvRegex.firstMatch(line);
        if (match != null) {
          final key = match.group(1)!.trim();
          final value = match.group(2)!.trim();
          if (key.isNotEmpty) {
            result.add(MapEntry(key, value));
          }
        }
      }
    }

    return result;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .trim();
  }

  Map<String, dynamic> get _filteredAttributes {
    final attrs = Map<String, dynamic>.from(feature.attributes);
    if (_hasHtmlDescription) {
      attrs.remove('description');
    }
    return attrs;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _hasHtmlDescription ? 0.55 : 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.dividerOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              _buildHeader(),

              const SizedBox(height: 12),

              // Action buttons - Edit Attributes (A) + Edit Geometry (shape)
              _buildActionButtons(context),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // HTML Description table (KML popup)
              if (_hasHtmlDescription) ...[
                _buildHtmlDescriptionTable(),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
              ],

              // System info
              _buildSystemInfo(),

              // User attributes
              if (_filteredAttributes.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildAttributesSection(),
              ],

              // Coordinates (collapsed by default)
              const SizedBox(height: 16),
              _buildCoordinatesSection(),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// Build the HTML description as a styled table
  Widget _buildHtmlDescriptionTable() {
    final entries = _parseHtmlTable();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Green header "Thong tin"
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
              ),
              child: const Text(
                'Th\u00f4ng tin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Data rows
            ...entries.asMap().entries.map((indexed) {
              final idx = indexed.key;
              final entry = indexed.value;
              final isHighlighted = _isHighlightedField(entry.key);
              final bgColor = isHighlighted
                  ? AppColors.error.withValues(alpha: 0.08)
                  : (idx % 2 == 0
                      ? AppColors.cardOf(context)
                      : AppColors.backgroundOf(context));

              return Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderOf(context), width: 0.5),
                  ),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Key column (flex 2 ~ 35%)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: AppColors.borderOf(context), width: 0.5),
                            ),
                          ),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isHighlighted
                                  ? AppColors.error
                                  : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                      // Value column (flex 3 ~ 65%)
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400,
                              color: isHighlighted
                                  ? AppColors.error
                                  : AppColors.textPrimaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  bool _isHighlightedField(String key) {
    final lower = key.toLowerCase();
    return lower.contains('di\u1ec7n t\u00edch kt') ||
        lower.contains('dien tich kt') ||
        lower.contains('dt\u00edch kt');
  }

  Widget _buildHeader() {
    final IconData typeIcon;
    final String typeName;
    final Color typeColor;

    switch (layer.geometryType) {
      case GeometryType.point:
        typeIcon = Icons.location_on;
        typeName = '\u0110i\u1ec3m';
        typeColor = AppColors.pointColor;
        break;
      case GeometryType.line:
        typeIcon = Icons.timeline;
        typeName = '\u0110\u01b0\u1eddng';
        typeColor = AppColors.lineColor;
        break;
      case GeometryType.polygon:
        typeIcon = Icons.pentagon_outlined;
        typeName = 'V\u00f9ng';
        typeColor = AppColors.polygonStroke;
        break;
    }

    final featureName = feature.attributes['name']?.toString() ??
        feature.attributes['Name']?.toString() ??
        layer.name;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(typeIcon, color: typeColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                featureName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${layer.name} \u2022 $typeName \u2022 ${feature.coordinates.length} \u0111\u1ec9nh',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondaryOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (feature.gpsAccuracy != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accuracyColor(feature.gpsAccuracy!).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gps_fixed,
                    size: 12,
                    color: _accuracyColor(feature.gpsAccuracy!)),
                const SizedBox(width: 4),
                Text(
                  '${feature.gpsAccuracy!.toStringAsFixed(1)}m',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _accuracyColor(feature.gpsAccuracy!),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _accuracyColor(double accuracy) {
    if (accuracy <= 5) return AppColors.gpsGood;
    if (accuracy <= 15) return AppColors.gpsModerate;
    return AppColors.gpsPoor;
  }

  /// Action buttons: Edit Attributes (A icon) + Edit Geometry (shape icon)
  Widget _buildActionButtons(BuildContext context) {
    final readOnly = layer.isReadOnly;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Read-only badge
        if (readOnly)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.borderOf(context).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 4),
                Text(
                  'Ch\u1ec9 xem (${layer.sourceFormat?.toUpperCase() ?? ""})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        // Edit Attributes - icon "A"
        if (!readOnly)
          _ActionChip(
            icon: Icons.text_fields,
            label: 'Thu\u1ed9c t\u00ednh',
            color: AppColors.primary,
            onTap: widget.onEditAttributes,
          ),
        // Edit Geometry - shape icon
        if (!readOnly)
          _ActionChip(
            icon: Icons.polyline_outlined,
            label: '\u0110\u1ed3 h\u00ecnh',
            color: AppColors.secondary,
            onTap: widget.onEditGeometry,
          ),
         _ActionChip(
           icon: Icons.navigation_outlined,
           label: 'D\u1eabn \u0111\u01b0\u1eddng',
           color: AppColors.info,
           onTap: widget.onNavigate,
         ),
        // Split polygon
        if (!readOnly && layer.geometryType == GeometryType.polygon)
          _ActionChip(
            icon: Icons.content_cut,
            label: 'C\u1eaft l\u00f4',
            color: Colors.orange,
            onTap: widget.onSplit,
          ),
        // Merge polygons
        if (!readOnly && layer.geometryType == GeometryType.polygon)
          _ActionChip(
            icon: Icons.merge,
            label: 'G\u1ed9p l\u00f4',
            color: Colors.blueAccent,
            onTap: widget.onMerge,
          ),
        // Delete
        if (!readOnly)
          InkWell(
            onTap: () => _confirmDelete(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
            ),
          ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('X\u00f3a \u0111\u1ed1i t\u01b0\u1ee3ng'),
        content: const Text(
            'B\u1ea1n c\u00f3 ch\u1eafc mu\u1ed1n x\u00f3a \u0111\u1ed1i t\u01b0\u1ee3ng n\u00e0y? H\u00e0nh \u0111\u1ed9ng kh\u00f4ng th\u1ec3 ho\u00e0n t\u00e1c.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('H\u1ee7y'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('X\u00f3a'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) Navigator.of(context).pop();
      widget.onDelete?.call();
    }
  }

  Widget _buildSystemInfo() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Th\u00f4ng tin h\u1ec7 th\u1ed1ng',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.access_time,
          label: 'Thu th\u1eadp',
          value: dateFormat.format(feature.collectedAt),
        ),
        if (feature.collectedBy != null)
          _InfoRow(
            icon: Icons.person_outline,
            label: 'Ng\u01b0\u1eddi d\u00f9ng',
            value: feature.collectedBy!,
          ),
        _InfoRow(
          icon: Icons.fingerprint,
          label: 'ID',
          value: feature.id.substring(0, 8),
        ),
      ],
    );
  }

  Widget _buildAttributesSection() {
    final attrs = _filteredAttributes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Thu\u1ed9c t\u00ednh',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const Spacer(),
            if (widget.onEditAttributes != null && !layer.isReadOnly)
              TextButton.icon(
                onPressed: widget.onEditAttributes,
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('S\u1eeda', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Builder(builder: (context) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.backgroundOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            children: attrs.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
        }),
      ],
    );
  }

  /// Coordinates section - collapsed by default, tap to expand
  Widget _buildCoordinatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _coordsExpanded = !_coordsExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _coordsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppColors.textSecondaryOf(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Tọa độ — Danh sách đỉnh (${feature.coordinates.length} vertex)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const Spacer(),
                if (!_coordsExpanded)
                  Text(
                    'B\u1ea5m \u0111\u1ec3 xem',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Centroid display for line/polygon features
        if (feature.coordinates.length >= 2) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.center_focus_strong, size: 14, color: AppColors.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  'Tọa độ trung tâm: ${feature.centroid.latitude.toStringAsFixed(6)}, ${feature.centroid.longitude.toStringAsFixed(6)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                children: List.generate(
                  feature.coordinates.length.clamp(0, 20),
                  (i) {
                    final c = feature.coordinates[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${i + 1}.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryOf(context),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )..addAll(
                    feature.coordinates.length > 20
                        ? [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '... v\u00e0 ${feature.coordinates.length - 20} \u0111\u1ec9nh n\u1eefa',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ]
                        : [],
                  ),
              ),
            ),
          ),
          crossFadeState: _coordsExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
