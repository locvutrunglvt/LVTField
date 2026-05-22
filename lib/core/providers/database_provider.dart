import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/layer_repository.dart';
import '../../data/repositories/feature_repository.dart';

/// Project repository provider
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

/// Layer repository provider
final layerRepositoryProvider = Provider<LayerRepository>((ref) {
  return LayerRepository();
});

/// Feature repository provider
final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
  return FeatureRepository();
});
