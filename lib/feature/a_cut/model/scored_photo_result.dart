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
      status == ScoreStatus.success && evaluation?.acutLabel == '추천';

  String get rankLabel => rank == null ? '-' : '#$rank';

  String get highlightLabel {
    if (isBestShot) return 'BEST';
    if (isTopThree) return 'TOP ${rank!}';
    if (isACut) return 'A컷 후보';
    if (status == ScoreStatus.failed) return '실패';
    if (status == ScoreStatus.pending) return '분석 중';
    return rankLabel;
  }

  String get acutLabel {
    if (status == ScoreStatus.failed) return '실패';
    if (status == ScoreStatus.pending) return '분석 중';
    return evaluation?.acutLabel ?? '-';
  }

  String get recommendationLabel {
    if (status == ScoreStatus.failed) return '분석에 실패했어요';
    if (status == ScoreStatus.pending) return '추천 순위를 계산 중이에요';
    return switch (acutLabel) {
      '추천' => '추천 후보로 볼 만한 컷이에요',
      '아쉬움' => '조금 아쉬운 후보예요',
      '탈락' => '이번 선택에서는 제외하는 편이 좋아요',
      _ => '순위를 확인해 보세요',
    };
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
