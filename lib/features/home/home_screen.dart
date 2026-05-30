import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/project_model.dart';
import '../../data/repositories/project_repository.dart';
import 'widgets/project_card.dart';
import 'widgets/create_project_dialog.dart';

/// Home screen showing list of survey projects
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _projectRepo = ProjectRepository();
  List<ProjectModel> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final projects = await _projectRepo.getAll();
      setState(() {
        _projects = projects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorOccurred}: $e')),
        );
      }
    }
  }

  Future<void> _createProject() async {
    final result = await showDialog<ProjectModel>(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    );

    if (result != null) {
      await _projectRepo.insert(result);
      await _loadProjects();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.savedSuccessfully),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _deleteProject(ProjectModel project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.confirmDelete),
        content: Text('Dự án "${project.name}" sẽ bị xóa vĩnh viễn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _projectRepo.delete(project.id);
      await _loadProjects();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.deletedSuccessfully),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.forest, size: 24),
            ),
            const SizedBox(width: AppSizes.sm),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.appName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(AppStrings.appTagline, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w300)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: AppStrings.importFromFile,
            onPressed: () {
              // TODO: Import .lvtfield file
            },
          ),
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Nhóm tuần tra',
            onPressed: () => context.push('/team'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppStrings.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? _buildEmptyState()
              : _buildProjectList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.newProject),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forest_outlined,
              size: 64,
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              AppStrings.noProjects,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              AppStrings.createFirstProject,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList() {
    return RefreshIndicator(
      onRefresh: _loadProjects,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSizes.md),
        itemCount: _projects.length,
        itemBuilder: (context, index) {
          final project = _projects[index];
          return ProjectCard(
            project: project,
            onTap: () => context.push('/map/${project.id}'),
            onDelete: () => _deleteProject(project),
          );
        },
      ),
    );
  }
}
