import 'package:photo_manager/photo_manager.dart';

import 'photo_type_mode.dart';

enum ScoreStatus { pending, success, failed }

class ScoredPhotoResult {
  final AssetEntity asset;
  final String fileName;
  final int selectedIndex;
  final ScoreStatus status;
  final double? aestheticScore;
  final List<double>? aestheticDistribution;
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
    this.aestheticScore,
    this.aestheticDistribution,
    this.rank,
    this.isACut = false,
    this.errorMessage,
  });

  double? get finalScore => aestheticScore;

  ScoredPhotoResult copyWith({
    ScoreStatus? status,
    double? aestheticScore,
    List<double>? aestheticDistribution,
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
      aestheticScore: aestheticScore ?? this.aestheticScore,
      aestheticDistribution:
          aestheticDistribution ?? this.aestheticDistribution,
      rank: rank,
      isACut: isACut ?? this.isACut,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      photoTypeMode: photoTypeMode ?? this.photoTypeMode,
    );
  }
}
