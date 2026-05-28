import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/layer_model.dart';

/// Dialog for creating a new data layer with a 2-step wizard.
///
/// **Step 1** — Layer name + geometry type selection.
/// **Step 2** — Preview/edit default fields, add custom fields.
///
/// Returns a `Map<String, dynamic>` with keys:
/// - `layer`  : the [LayerModel]
/// - `fields` : `List<Map<String, dynamic>>` field definitions
///
/// Author: Lộc Vũ Trung
class AddLayerDialog extends StatefulWidget {
  final String projectId;

  const AddLayerDialog({
    super.key,
    required this.projectId,
  });

  /// Show the dialog and return a result map, or null if cancelled.
  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    String projectId,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddLayerDialog(projectId: projectId),
    );
  }

  @override
  State<AddLayerDialog> createState() => _AddLayerDialogState();
}

class _AddLayerDialogState extends State<AddLayerDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  GeometryType _selectedType = GeometryType.point;

  /// Current wizard step: 0 = name+type, 1 = fields.
  int _currentStep = 0;

  /// Editable list of field definitions for Step 2.
  List<Map<String, dynamic>> _fields = [];

  // ─── Default fields by geometry type ──────────────────────────────

  /// Build the default field list for the selected geometry type.
  List<Map<String, dynamic>> _buildDefaultFields(GeometryType type) {
    switch (type) {
      case GeometryType.polygon:
        return [
          {
            'fieldName': 'TT',
            'label': 'TT',
            'fieldType': 'numberAuto',
            'autoSource': 'auto_increment',
            'sortOrder': 0,
          },
          {
            'fieldName': 'Ten_Vung',
            'label': 'Tên vùng',
            'fieldType': 'text',
            'sortOrder': 1,
          },
          {
            'fieldName': 'Dientich',
            'label': 'Diện tích (ha)',
            'fieldType': 'number',
            'autoSource': 'area_ha',
            'hint': 'Tự động tính',
            'sortOrder': 2,
          },
        ];

      case GeometryType.point:
        return [
          {
            'fieldName': 'TT',
            'label': 'TT',
            'fieldType': 'numberAuto',
            'autoSource': 'auto_increment',
            'sortOrder': 0,
          },
          {
            'fieldName': 'Ten_Diem',
            'label': 'Tên điểm',
            'fieldType': 'text',
            'sortOrder': 1,
          },
          {
            'fieldName': 'Lat',
            'label': 'Vĩ độ',
            'fieldType': 'number',
            'autoSource': 'lat_7',
            'hint': 'Tự động tính (7 chữ số)',
            'sortOrder': 2,
          },
          {
            'fieldName': 'Long',
            'label': 'Kinh độ',
            'fieldType': 'number',
            'autoSource': 'long_7',
            'hint': 'Tự động tính (7 chữ số)',
            'sortOrder': 3,
          },
        ];

      case GeometryType.line:
        return [
          {
            'fieldName': 'TT',
            'label': 'TT',
            'fieldType': 'numberAuto',
            'autoSource': 'auto_increment',
            'sortOrder': 0,
          },
          {
            'fieldName': 'Ten_line',
            'label': 'Tên đường',
            'fieldType': 'text',
            'sortOrder': 1,
          },
          {
            'fieldName': 'Long',
            'label': 'Chiều dài (m)',
            'fieldType': 'number',
            'autoSource': 'length_m',
            'hint': 'Tự động tính',
            'sortOrder': 2,
          },
        ];
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.80,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: _currentStep == 0 ? _buildStep1() : _buildStep2(),
        ),
      ),
    );
  }

  // ─── Step 1 — Name + Geometry Type ────────────────────────────────

  Widget _buildStep1() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTitle(),
          const SizedBox(height: AppSizes.lg),
          _buildNameField(),
          const SizedBox(height: AppSizes.lg),
          _buildGeometryTypeLabel(),
          const SizedBox(height: AppSizes.sm),
          _buildGeometryTypeSelector(),
          const SizedBox(height: AppSizes.lg),
          _buildStep1Actions(),
        ],
      ),
    );
  }

  /// Dialog title
  Widget _buildTitle() {
    return Text(
      _currentStep == 0 ? 'Thêm lớp mới' : 'Cấu hình trường dữ liệu',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryOf(context),
      ),
    );
  }

  /// Layer name text field with validation
  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Tên lớp dữ liệu',
        hintText: 'VD: Lô rừng, Cây cá thể...',
        prefixIcon: const Icon(Icons.edit_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return AppStrings.requiredField;
        }
        return null;
      },
    );
  }

  /// Label above geometry type buttons
  Widget _buildGeometryTypeLabel() {
    return Text(
      'Loại hình học',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryOf(context),
      ),
    );
  }

  /// Three large geometry type selection buttons
  Widget _buildGeometryTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildTypeButton(
            type: GeometryType.point,
            icon: Icons.location_on,
            label: AppStrings.addPoint,
            color: AppColors.pointColor,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _buildTypeButton(
            type: GeometryType.line,
            icon: Icons.timeline,
            label: AppStrings.addLine,
            color: AppColors.lineColor,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _buildTypeButton(
            type: GeometryType.polygon,
            icon: Icons.pentagon,
            label: AppStrings.addPolygon,
            color: AppColors.polygonStroke,
          ),
        ),
      ],
    );
  }

  /// Individual geometry type selection button
  Widget _buildTypeButton({
    required GeometryType type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: AppSizes.md,
          horizontal: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : AppColors.backgroundOf(context),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: isSelected ? color : AppColors.borderOf(context),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppSizes.iconLg,
              color: isSelected ? color : AppColors.textSecondaryOf(context),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? color : AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 1 actions: Cancel + Tiếp theo
  Widget _buildStep1Actions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            AppStrings.cancel,
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        FilledButton.icon(
          onPressed: _goToStep2,
          icon: const Icon(Icons.arrow_forward, size: AppSizes.iconSm),
          label: const Text('Tiếp theo'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg,
              vertical: AppSizes.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  /// Validate Step 1 and advance to Step 2.
  void _goToStep2() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _fields = _buildDefaultFields(_selectedType);
      _currentStep = 1;
    });
  }

  // ─── Step 2 — Field list ──────────────────────────────────────────

  /// Inline add-field controllers
  final _addFieldNameCtrl = TextEditingController();
  final _addFieldLabelCtrl = TextEditingController();
  String _addFieldType = 'text';
  bool _showAddForm = false;

  Widget _buildStep2() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(),
        const SizedBox(height: 4),
        Text(
          'Lớp: ${_nameController.text.trim()} — ${_fields.length} trường',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 8),

        // Scrollable content: field list + inline add form
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Field list
                if (_fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Chưa có trường.\nBấm "+ Thêm trường" bên dưới.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 13),
                    ),
                  )
                else
                  ...List.generate(_fields.length, (index) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFieldRow(index),
                        if (index < _fields.length - 1) const Divider(height: 1),
                      ],
                    );
                  }),

                const SizedBox(height: 8),

                // Inline add field form (toggle)
                if (_showAddForm) _buildInlineAddField(),

                // Add button
                if (!_showAddForm)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        debugPrint('AddLayerDialog: Show add field form. Current fields: ${_fields.length}');
                        setState(() {
                          _showAddForm = true;
                          _addFieldNameCtrl.clear();
                          _addFieldLabelCtrl.clear();
                          _addFieldType = 'text';
                        });
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Thêm trường'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        _buildStep2Actions(),
      ],
    );
  }

  /// Inline form to add a new field — no nested dialog
  Widget _buildInlineAddField() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Thêm trường mới', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _addFieldNameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tên trường',
              hintText: 'VD: ghi_chu',
              border: UnderlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _addFieldLabelCtrl,
            decoration: const InputDecoration(
              labelText: 'Nhãn hiển thị',
              hintText: 'VD: Ghi chú',
              border: UnderlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _addFieldType,
            decoration: const InputDecoration(
              labelText: 'Loại',
              border: UnderlineInputBorder(),
              isDense: true,
            ),
            style: TextStyle(fontSize: 13, color: AppColors.textPrimaryOf(context)),
            items: const [
              DropdownMenuItem(value: 'text', child: Text('Văn bản')),
              DropdownMenuItem(value: 'textMultiline', child: Text('Nhiều dòng')),
              DropdownMenuItem(value: 'number', child: Text('Số')),
              DropdownMenuItem(value: 'dropdown', child: Text('Danh sách')),
              DropdownMenuItem(value: 'date', child: Text('Ngày')),
              DropdownMenuItem(value: 'checkbox', child: Text('Checkbox')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _addFieldType = v);
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _showAddForm = false),
                child: const Text('Hủy', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  final name = _addFieldNameCtrl.text.trim();
                  final label = _addFieldLabelCtrl.text.trim();
                  if (name.isEmpty || label.isEmpty) {
                    debugPrint('AddLayerDialog: name or label empty, not adding');
                    return;
                  }
                  debugPrint('AddLayerDialog: Adding field "$name" ($label) type=$_addFieldType');
                  setState(() {
                    _fields.add({
                      'fieldName': name,
                      'label': label,
                      'fieldType': _addFieldType,
                      'sortOrder': _fields.length,
                    });
                    _showAddForm = false;
                    _addFieldNameCtrl.clear();
                    _addFieldLabelCtrl.clear();
                    _addFieldType = 'text';
                  });
                  debugPrint('AddLayerDialog: Now has ${_fields.length} fields total');
                },
                child: const Text('Thêm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A single field row
  Widget _buildFieldRow(int index) {
    final field = _fields[index];
    final fieldName = field['fieldName'] as String;
    final label = field['label'] as String;
    final fieldType = field['fieldType'] as String;
    final isTT = fieldName == 'TT';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(fieldName,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimaryOf(context)),
              overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondaryOf(context)),
              overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Text(_typeDisplayName(fieldType),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
          if (!isTT)
            InkWell(
              onTap: () => setState(() {
                _fields.removeAt(index);
                _reindexSortOrder();
              }),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.red),
              ),
            )
          else
            const SizedBox(width: 24),
        ],
      ),
    );
  }

  /// Step 2 actions: Back + Tạo lớp.
  Widget _buildStep2Actions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => setState(() => _currentStep = 0),
          child: Text('Quay lại', style: TextStyle(color: AppColors.textSecondaryOf(context))),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
          ),
          child: const Text('Tạo lớp'),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  /// Re-index sortOrder after removing a field.
  void _reindexSortOrder() {
    for (int i = 0; i < _fields.length; i++) {
      _fields[i]['sortOrder'] = i;
    }
  }

  /// Display name for a field type string.
  String _typeDisplayName(String type) {
    switch (type) {
      case 'text': return 'Văn bản';
      case 'textMultiline': return 'Nhiều dòng';
      case 'number': return 'Số';
      case 'numberAuto': return 'Tự động';
      case 'dropdown': return 'Danh sách';
      case 'checkbox': return 'Checkbox';
      case 'date': return 'Ngày';
      default: return type;
    }
  }

  // ─── Submit ───────────────────────────────────────────────────────

  /// Build the layer + field definitions and return them.
  void _onSubmit() {
    debugPrint('AddLayerDialog: _onSubmit with ${_fields.length} fields');
    for (final f in _fields) {
      debugPrint('  Field: ${f['fieldName']} (${f['fieldType']})');
    }

    final layer = LayerModel(
      projectId: widget.projectId,
      name: _nameController.text.trim(),
      geometryType: _selectedType,
    );

    Navigator.of(context).pop({
      'layer': layer,
      'fields': List<Map<String, dynamic>>.from(_fields),
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addFieldNameCtrl.dispose();
    _addFieldLabelCtrl.dispose();
    super.dispose();
  }
}
