import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/layer_model.dart';

/// A beautiful dialog to configure layer styling:
/// - Stroke color (outline)
/// - Fill color
/// - Stroke width
/// - Label field (from available attribute columns)
/// - Label color & font size
///
/// Author: Loc Vu Trung
class LayerStyleDialog extends StatefulWidget {
  final LayerModel layer;
  final List<String> availableFields;

  const LayerStyleDialog({
    super.key,
    required this.layer,
    required this.availableFields,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required LayerModel layer,
    required List<String> availableFields,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LayerStyleDialog(
        layer: layer,
        availableFields: availableFields,
      ),
    );
  }

  @override
  State<LayerStyleDialog> createState() => _LayerStyleDialogState();
}

class _LayerStyleDialogState extends State<LayerStyleDialog> {
  late Color _strokeColor;
  late Color _fillColor;
  late double _strokeWidth;
  late double _fillOpacity;
  late String? _labelField;
  late String? _labelField2;
  late String? _labelSuffix2;
  late Color _labelColor;
  late double _labelFontSize;

  // Preset color palette for quick selection
  static const _presetColors = [
    Color(0xFF00FF80), // green (QField default)
    Color(0xFF00FF00), // lime
    Color(0xFF00BFFF), // deep sky blue
    Color(0xFFFF6B35), // orange
    Color(0xFFFF0000), // red
    Color(0xFFFFFF00), // yellow
    Color(0xFFFF00FF), // magenta
    Color(0xFF8B00FF), // violet
    Color(0xFFFFFFFF), // white
    Color(0xFF00CED1), // dark turquoise
    Color(0xFFE63946), // crimson
    Color(0xFF457B9D), // steel blue
    Color(0xFF40916C), // sea green
    Color(0xFF0054D9), // blue
    Color(0xFFF77F00), // amber
    Color(0xFF2D6A4F), // forest green
  ];

  @override
  void initState() {
    super.initState();
    final style = widget.layer.styleConfig;
    _strokeColor = widget.layer.strokeColor;
    _fillColor = Color(widget.layer.fillColor.value | 0xFF000000); // opaque base color
    _strokeWidth = widget.layer.strokeWidth;
    _fillOpacity = (style['fillOpacity'] as num?)?.toDouble() ?? widget.layer.opacity;
    _labelField = style['labelField'] as String?;
    _labelField2 = style['labelField2'] as String?;
    _labelSuffix2 = style['labelSuffix2'] as String?;
    _labelColor = widget.layer.labelColor;
    _labelFontSize = widget.layer.labelFontSize;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.70,
          maxWidth: 420,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.palette, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kiểu hiển thị — ${widget.layer.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(20),
                shrinkWrap: true,
                children: [
                  // ── Stroke Color ──
                  _sectionTitle('Màu viền (đường lô)', Icons.border_color),
                  const SizedBox(height: 8),
                  _buildColorPicker(_strokeColor, (c) => setState(() => _strokeColor = c)),

                  const SizedBox(height: 20),

                  // ── Fill Color ── (only for polygons)
                  if (widget.layer.geometryType == GeometryType.polygon) ...[
                    _sectionTitle('Màu nền', Icons.format_color_fill),
                    const SizedBox(height: 8),
                    _buildColorPicker(_fillColor, (c) => setState(() => _fillColor = c)),
                    const SizedBox(height: 16),
                    // ── Fill Opacity ──
                    _sectionTitle('Độ mờ nền (${(_fillOpacity * 100).toInt()}%)', Icons.opacity),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('0%', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: AppColors.primary,
                              thumbColor: AppColors.primary,
                              inactiveTrackColor: Colors.grey.shade200,
                            ),
                            child: Slider(
                              value: _fillOpacity,
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              label: '${(_fillOpacity * 100).toInt()}%',
                              onChanged: (v) => setState(() => _fillOpacity = v),
                            ),
                          ),
                        ),
                        const Text('100%', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Stroke Width ──
                  _sectionTitle('Độ rộng nét (${_strokeWidth.toStringAsFixed(1)})', Icons.line_weight),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppColors.primary,
                      thumbColor: AppColors.primary,
                      inactiveTrackColor: Colors.grey.shade200,
                    ),
                    child: Slider(
                      value: _strokeWidth,
                      min: 0.5,
                      max: 8.0,
                      divisions: 15,
                      label: _strokeWidth.toStringAsFixed(1),
                      onChanged: (v) => setState(() => _strokeWidth = v),
                    ),
                  ),

                  const Divider(height: 32),

                  // ── Label Configuration ──
                  _sectionTitle('Nhãn lô rừng', Icons.label_outline),
                  const SizedBox(height: 12),

                  // Primary label field
                  _buildFieldDropdown(
                    'Trường nhãn chính',
                    _labelField,
                    (v) => setState(() => _labelField = v),
                  ),
                  const SizedBox(height: 10),

                  // Secondary label field
                  _buildFieldDropdown(
                    'Trường nhãn phụ',
                    _labelField2,
                    (v) => setState(() => _labelField2 = v),
                  ),

                  // Suffix for field2
                  if (_labelField2 != null && _labelField2!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Hậu tố nhãn phụ',
                        hintText: 'Ví dụ: " ha"',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      controller: TextEditingController(text: _labelSuffix2 ?? ''),
                      style: const TextStyle(fontSize: 14),
                      onChanged: (v) => _labelSuffix2 = v,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Label color
                  if (_labelField != null && _labelField!.isNotEmpty) ...[
                    _sectionTitle('Màu nhãn', Icons.format_color_text),
                    const SizedBox(height: 8),
                    _buildColorPicker(_labelColor, (c) => setState(() => _labelColor = c)),
                    const SizedBox(height: 16),

                    // Label font size
                    _sectionTitle('Cỡ chữ nhãn (${_labelFontSize.toStringAsFixed(0)})', Icons.format_size),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.primary,
                        thumbColor: AppColors.primary,
                        inactiveTrackColor: Colors.grey.shade200,
                      ),
                      child: Slider(
                        value: _labelFontSize,
                        min: 8,
                        max: 24,
                        divisions: 16,
                        label: _labelFontSize.toStringAsFixed(0),
                        onChanged: (v) => setState(() => _labelFontSize = v),
                      ),
                    ),
                  ],

                  // ── Preview ──
                  const SizedBox(height: 12),
                  _buildPreview(),
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Áp dụng'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildColorPicker(Color current, ValueChanged<Color> onChanged) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _presetColors.map((color) {
        final isSelected = (color.value == current.value);
        return GestureDetector(
          onTap: () => onChanged(color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
            child: isSelected
                ? Icon(Icons.check, size: 16,
                    color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFieldDropdown(String label, String? value, ValueChanged<String?> onChanged) {
    final fields = ['', ...widget.availableFields];
    return DropdownButtonFormField<String>(
      value: fields.contains(value) ? value : '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      items: fields.map((f) => DropdownMenuItem(
        value: f,
        child: Text(f.isEmpty ? '— Không hiển thị —' : f, style: const TextStyle(fontSize: 14)),
      )).toList(),
      onChanged: (v) => onChanged(v?.isEmpty == true ? null : v),
    );
  }

  Widget _buildPreview() {
    final previewFill = _fillColor.withValues(alpha: _fillOpacity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Xem trước',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 8),
          // Simple preview box
          Container(
            width: 80,
            height: 50,
            decoration: BoxDecoration(
              color: previewFill,
              border: Border.all(color: _strokeColor, width: _strokeWidth),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: _labelField != null && _labelField!.isNotEmpty
                  ? Text(
                      '${_labelField!}\n${_labelField2 ?? ""}${_labelSuffix2 ?? ""}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _labelFontSize * 0.7,
                        fontWeight: FontWeight.w700,
                        color: _labelColor,
                        shadows: const [
                          Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black54),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final newStyle = Map<String, dynamic>.from(widget.layer.styleConfig);
    newStyle['strokeColor'] = _strokeColor.value;
    // Store fill color as opaque + separate opacity
    newStyle['fillColor'] = (_fillColor.value | 0xFF000000);
    newStyle['fillOpacity'] = _fillOpacity;
    newStyle['strokeWidth'] = _strokeWidth;

    // For lines, also update 'color' and 'width' keys
    if (widget.layer.geometryType == GeometryType.line) {
      newStyle['color'] = _strokeColor.value;
      newStyle['width'] = _strokeWidth;
    }

    // Labels
    newStyle['labelField'] = _labelField;
    newStyle['labelField2'] = _labelField2;
    newStyle['labelSuffix2'] = _labelSuffix2;
    newStyle['labelColor'] = _labelColor.value;
    newStyle['labelFontSize'] = _labelFontSize;

    Navigator.pop(context, newStyle);
  }
}
