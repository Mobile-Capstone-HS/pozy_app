import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/layer/scoring/image_scoring_service.dart';
import '../feature/a_cut/model/photo_type_mode.dart';
import '../feature/a_cut/model/scored_photo_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class ACutResultScreen extends StatefulWidget {
  final List<AssetEntity> selectedAssets;
  final PhotoTypeMode initialPhotoTypeMode;

  const ACutResultScreen({
    super.key,
    required this.selectedAssets,
    required this.initialPhotoTypeMode,
  });

  @override
  State<ACutResultScreen> createState() => _ACutResultScreenState();
}

class _ACutResultScreenState extends State<ACutResultScreen> {
  static const double _defaultTopPercent = 0.2;

  final ImageScoreService _scoreService = NimaImageScoreService();

  List<ScoredPhotoResult> _results = const [];
  PhotoTypeMode _photoTypeMode = PhotoTypeMode.auto;

  bool _isScoring = false;
  int _doneCount = 0;
  int _totalCount = 0;
  int _jobToken = 0;

  @override
  void initState() {
    super.initState();
    _photoTypeMode = widget.initialPhotoTypeMode;
    _startScoring();
  }

  Future<void> _startScoring() async {
    if (widget.selectedAssets.isEmpty) {
      setState(() {
        _isScoring = false;
        _results = const [];
        _doneCount = 0;
        _totalCount = 0;
      });
      return;
    }

    final currentToken = ++_jobToken;

    setState(() {
      _isScoring = true;
      _doneCount = 0;
      _totalCount = widget.selectedAssets.length;
      _results = const [];
    });

    await _scoreService.scoreAssets(
      assets: widget.selectedAssets,
      photoTypeMode: _photoTypeMode,
      topPercent: _defaultTopPercent,
      onProgress: (snapshot, done, total) {
        if (!mounted || currentToken != _jobToken) {
          return;
        }
        setState(() {
          _results = snapshot;
          _doneCount = done;
          _totalCount = total;
          _isScoring = done < total;
        });
      },
    );

    if (!mounted || currentToken != _jobToken) {
      return;
    }

    setState(() {
      _isScoring = false;
    });
  }

  void _changeType(PhotoTypeMode mode) {
    if (_photoTypeMode == mode || _isScoring) {
      return;
    }
    setState(() {
      _photoTypeMode = mode;
    });
    _startScoring();
  }

  @override
  Widget build(BuildContext context) {
    final completed = _totalCount > 0
        ? (_doneCount / _totalCount).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: 'A컷 결과',
                onBack: () => Navigator.of(context).pop(),
                trailingWidth: 90,
                trailing: GestureDetector(
                  onTap: _isScoring ? null : _startScoring,
                  child: Text(
                    '재분석',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _isScoring
                          ? AppColors.lightText
                          : AppColors.primaryText,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _PhotoTypeRow(selected: _photoTypeMode, onSelected: _changeType),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '분석 진행: $_doneCount/$_totalCount',
                        style: AppTextStyles.body13,
                      ),
                      const Spacer(),
                      Text(
                        '${(completed * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: completed,
                      backgroundColor: AppColors.track,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _results.isEmpty
                  ? const Center(
                      child: Text('선택된 사진이 없습니다.', style: AppTextStyles.body14),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return _ResultCard(result: result);
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemCount: _results.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScoredPhotoResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.status == ScoreStatus.success;
    final isFailed = result.status == ScoreStatus.failed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 84,
              height: 84,
              child: FutureBuilder<Uint8List?>(
                future: result.asset.thumbnailDataWithSize(
                  const ThumbnailSize(280, 280),
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data == null) {
                    return Container(
                      color: const Color(0xFFEDEFF3),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.lightText,
                      ),
                    );
                  }
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    if (result.isACut)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryText,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'A컷',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (isSuccess)
                  Text(
                    '점수 ${result.finalScore!.toStringAsFixed(4)}  |  순위 #${result.rank}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                if (isFailed)
                  Text(
                    '실패: ${result.errorMessage ?? '알 수 없는 오류'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                if (!isSuccess && !isFailed)
                  const Text(
                    '점수 계산 중...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTypeRow extends StatelessWidget {
  final PhotoTypeMode selected;
  final ValueChanged<PhotoTypeMode> onSelected;

  const _PhotoTypeRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: PhotoTypeMode.values.map((mode) {
          final active = selected == mode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelected(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 38,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFEFEFEF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        color: active ? Colors.white : const Color(0xFF5A5A5A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
