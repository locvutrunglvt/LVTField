import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/form_field_model.dart';
import '../../../data/models/layer_model.dart';

/// Full-screen page for creating a new data layer with a 2-step wizard.
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

  /// Show as a full-screen page and return a result map, or null if cancelled.
  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    String projectId,
  ) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddLayerDialog(projectId: projectId),
      ),
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

  List<Map<String, dynamic>> _buildDefaultFields(GeometryType type) {
    final fields = <Map<String, dynamic>>[
      {'fieldName': 'TT', 'label': 'TT', 'fieldType': 'numberAuto', 'autoSource': 'auto_increment', 'sortOrder': 0},
    ];

    switch (type) {
      case GeometryType.point:
        fields.addAll([
          {'fieldName': 'Ten', 'label': 'Tên điểm', 'fieldType': 'text', 'sortOrder': 1},
          {'fieldName': 'lat', 'label': 'Vĩ độ', 'fieldType': 'number', 'autoSource': 'lat_7', 'sortOrder': 2},
          {'fieldName': 'long', 'label': 'Kinh độ', 'fieldType': 'number', 'autoSource': 'long_7', 'sortOrder': 3},
        ]);
        break;
      case GeometryType.line:
        fields.addAll([
          {'fieldName': 'Ten', 'label': 'Tên đường', 'fieldType': 'text', 'sortOrder': 1},
          {'fieldName': 'dai_m', 'label': 'Chiều dài (m)', 'fieldType': 'number', 'autoSource': 'length_m', 'sortOrder': 2},
          {'fieldName': 'Ghichu', 'label': 'Ghi chú', 'fieldType': 'text', 'sortOrder': 3},
        ]);
        break;
      case GeometryType.polygon:
        fields.addAll([
          {'fieldName': 'Ten', 'label': 'Tên vùng', 'fieldType': 'text', 'sortOrder': 1},
          {'fieldName': 'dt_ha', 'label': 'Diện tích (ha)', 'fieldType': 'number', 'autoSource': 'area_ha', 'sortOrder': 2},
          {'fieldName': 'Ghichu', 'label': 'Ghi chú', 'fieldType': 'text', 'sortOrder': 3},
        ]);
        break;
    }
    return fields;
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStep == 0 ? 'Thêm lớp mới' : 'Cấu hình trường dữ liệu'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_currentStep == 1)
            TextButton(
              onPressed: _onSubmit,
              child: const Text('Tạo lớp', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _currentStep == 0 ? _buildStep1() : _buildStep2(),
    );
  }

  // ─── Step 1 — Name + Geometry Type ────────────────────────────────

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
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
            ),
            const SizedBox(height: 24),
            Text('Loại hình học',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 8),
            _buildGeometryTypeSelector(),
            const Spacer(),
            FilledButton.icon(
              onPressed: _goToStep2,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Tiếp theo'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeometryTypeSelector() {
    return Row(
      children: [
        Expanded(child: _buildTypeButton(type: GeometryType.point, icon: Icons.location_on, label: AppStrings.addPoint, color: AppColors.pointColor)),
        const SizedBox(width: 8),
        Expanded(child: _buildTypeButton(type: GeometryType.line, icon: Icons.timeline, label: AppStrings.addLine, color: AppColors.lineColor)),
        const SizedBox(width: 8),
        Expanded(child: _buildTypeButton(type: GeometryType.polygon, icon: Icons.pentagon, label: AppStrings.addPolygon, color: AppColors.polygonStroke)),
      ],
    );
  }

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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
            Icon(icon, size: 28, color: isSelected ? color : AppColors.textSecondaryOf(context)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? color : AppColors.textSecondaryOf(context),
            )),
          ],
        ),
      ),
    );
  }

  void _goToStep2() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _fields = _buildDefaultFields(_selectedType);
      _currentStep = 1;
    });
  }

  // ─── Step 2 — Field list ──────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.primary.withValues(alpha: 0.08),
          child: Text(
            'Lớp: ${_nameController.text.trim()} — ${_fields.length} trường',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondaryOf(context)),
          ),
        ),

        // Field list
        Expanded(
          child: _fields.isEmpty
              ? Center(
                  child: Text(
                    'Chưa có trường.\nBấm nút bên dưới để thêm.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _fields.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, index) => _buildFieldRow(index),
                ),
        ),

        // Bottom actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _addFieldViaBottomSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm trường mới'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _currentStep = 0),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      child: const Text('Quay lại'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _onSubmit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Tạo lớp'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Add field using BottomSheet with field name validation
  Future<void> _addFieldViaBottomSheet() async {
    final nameCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    String selType = 'text';
    String? nameError;

    final existingNames = _fields.map((f) => f['fieldName'] as String).toList();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (bsCtx) {
        return StatefulBuilder(
          builder: (bsCtx, setBsState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(bsCtx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Thêm trường mới',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: 'Tên trường (max 8 ký tự)',
                      hintText: 'VD: Ghichu, loai',
                      helperText: 'Chỉ a-z, A-Z, 0-9, _',
                      errorText: nameError,
                      border: const UnderlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final sanitized = FormFieldModel.sanitizeFieldName(v);
                      if (v.isNotEmpty && v != sanitized) {
                        nameCtrl.text = sanitized;
                        nameCtrl.selection = TextSelection.collapsed(offset: sanitized.length);
                      }
                      setBsState(() {
                        if (existingNames.contains(sanitized)) {
                          nameError = 'Tên "$sanitized" đã tồn tại';
                        } else {
                          nameError = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nhãn hiển thị (tự do)',
                      hintText: 'VD: Ghi chú, Loại cây',
                      border: UnderlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selType,
                    decoration: const InputDecoration(
                      labelText: 'Loại dữ liệu',
                      border: UnderlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('Văn bản')),
                      DropdownMenuItem(value: 'textMultiline', child: Text('Nhiều dòng')),
                      DropdownMenuItem(value: 'number', child: Text('Số')),
                      DropdownMenuItem(value: 'dropdown', child: Text('Danh sách')),
                      DropdownMenuItem(value: 'date', child: Text('Ngày')),
                      DropdownMenuItem(value: 'checkbox', child: Text('Checkbox')),
                    ],
                    onChanged: (v) {
                      if (v != null) setBsState(() => selType = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(bsCtx).pop(),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final n = FormFieldModel.sanitizeFieldName(nameCtrl.text.trim());
                          final l = labelCtrl.text.trim();
                          if (n.isEmpty || l.isEmpty) return;
                          if (existingNames.contains(n)) return;
                          Navigator.of(bsCtx).pop({
                            'fieldName': n,
                            'label': l,
                            'fieldType': selType,
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                        ),
                        child: const Text('Thêm'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      debugPrint('AddLayerDialog: Added field "${result['fieldName']}" type=${result['fieldType']}');
      setState(() {
        result['sortOrder'] = _fields.length;
        _fields.add(result);
      });
      debugPrint('AddLayerDialog: Total fields now: ${_fields.length}');
    }
  }

  /// A single field row with delete button
  Widget _buildFieldRow(int index) {
    final field = _fields[index];
    final fieldName = field['fieldName'] as String;
    final label = field['label'] as String;
    final fieldType = field['fieldType'] as String;
    final isTT = fieldName == 'TT';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Text('${index + 1}',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context))),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text('$fieldName • ${_typeDisplayName(fieldType)}',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context))),
      trailing: isTT
          ? const Icon(Icons.lock_outline, size: 16, color: Colors.grey)
          : IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: () => setState(() {
                _fields.removeAt(index);
                _reindexSortOrder();
              }),
            ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  void _reindexSortOrder() {
    for (int i = 0; i < _fields.length; i++) {
      _fields[i]['sortOrder'] = i;
    }
  }

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

  void _onSubmit() {
    debugPrint('AddLayerDialog._onSubmit: ${_fields.length} fields');
    for (final f in _fields) {
      debugPrint('  → ${f['fieldName']} (${f['fieldType']})');
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
    super.dispose();
  }
}
