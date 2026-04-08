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

  bool get isTopThree =>
      status == ScoreStatus.success && rank != null && rank! <= 3;

  bool get isRecommendedPick =>
      status == ScoreStatus.success && (isBestShot || isTopThree || isACut);

  String get rankLabel => rank == null ? '-' : '#$rank';

  String get highlightLabel {
    if (isBestShot) return 'BEST';
    if (isTopThree) return 'TOP ${rank!}';
    if (isACut) return '추천 컷';
    if (status == ScoreStatus.failed) return '실패';
    if (status == ScoreStatus.pending) return '분석 중';
    return rankLabel;
  }

  String get recommendationLabel {
    if (isBestShot) return '가장 추천하는 베스트 컷';
    if (isTopThree) return '상위 추천 컷';
    if (isACut) return 'A컷 후보';
    if (status == ScoreStatus.failed) return '분석에 실패했어요';
    if (status == ScoreStatus.pending) return '추천 순위를 계산 중이에요';
    return '순위를 확인해 보세요';
  }

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
