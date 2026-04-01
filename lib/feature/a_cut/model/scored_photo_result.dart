import 'package:photo_manager/photo_manager.dart';

import 'photo_evaluation_result.dart';
import 'photo_type_mode.dart';

enum ScoreStatus { pending, success, failed }

class ScoredPhotoResult {
  final AssetEntity asset;
  final String fileName;
  final int selectedIndex;
  final ScoreStatus status;
  final PhotoEvaluationResult? evaluation;
  final int? rank;
  final bool isACut;
  final String? errorMessage;
  final PhotoTypeMode photoTypeMode;

  const ScoredPhotoResult({
    required this.asset,
    required this.fileName,
    required this.selectedIndex,
    required this.status,
    required this.photoTypeMode,
    this.evaluation,
    this.rank,
    this.isACut = false,
    this.errorMessage,
  });

  double? get finalScore => evaluation?.finalScore;

  double? get technicalScore => evaluation?.technicalScore;

  bool get isBestShot => status == ScoreStatus.success && rank == 1;

  ScoredPhotoResult copyWith({
    ScoreStatus? status,
    PhotoEvaluationResult? evaluation,
    bool clearEvaluation = false,
    int? rank,
    bool? isACut,
    String? errorMessage,
    bool clearErrorMessage = false,
    PhotoTypeMode? photoTypeMode,
  }) {
    return ScoredPhotoResult(
      asset: asset,
      fileName: fileName,
      selectedIndex: selectedIndex,
      status: status ?? this.status,
      evaluation: clearEvaluation ? null : (evaluation ?? this.evaluation),
      rank: rank,
      isACut: isACut ?? this.isACut,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      photoTypeMode: photoTypeMode ?? this.photoTypeMode,
    );
  }
}
