import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/project_model.dart';

/// Dialog for creating a new survey project
class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final project = ProjectModel(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
      );
      Navigator.pop(context, project);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primarySurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.forest, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSizes.sm),
          const Text(AppStrings.newProject),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: AppStrings.projectName,
                  hintText: 'Ví dụ: Khảo sát VQG Ba Vì',
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                ),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.requiredField;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: AppStrings.projectDescription,
                  hintText: 'Mô tả ngắn về dự án',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 20),
          label: const Text('Tạo dự án'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 44),
          ),
        ),
      ],
    );
  }
}
