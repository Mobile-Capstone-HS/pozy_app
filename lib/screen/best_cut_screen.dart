import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';

import 'a_cut_result_screen.dart';
import 'best_cut_gallery_screen.dart';
import 'camera_screen.dart';
import 'history_screen.dart';

const _kBg = Color(0xFFF7F8FB);
const _kBlue = Color(0xFF3182F6);
const _kDark = Color(0xFF191F28);
const _kGrey600 = Color(0xFF6B7684);

class BestCutScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback? onBack;

  const BestCutScreen({super.key, required this.onMoveTab, this.onBack});

  @override
  State<BestCutScreen> createState() => _BestCutScreenState();
}

class _BestCutScreenState extends State<BestCutScreen> {
  Future<void> _openCameraForEval() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => CameraScreen(
          onMoveTab: (_) {},
          onBack: () => Navigator.of(routeContext).pop(),
          onCapture: (Uint8List bytes) async {
            final name = 'pozy_${DateTime.now().millisecondsSinceEpoch}';
            await Gal.putImageBytes(bytes, name: name);
            await Future<void>.delayed(const Duration(milliseconds: 600));

            final permission = await PhotoManager.requestPermissionExtend();
            if (!permission.hasAccess || !routeContext.mounted) return;

            final albums = await PhotoManager.getAssetPathList(
              type: RequestType.image,
              filterOption: FilterOptionGroup(
                orders: [
                  const OrderOption(
                    type: OrderOptionType.createDate,
                    asc: false,
                  ),
                ],
              ),
            );
            if (albums.isEmpty || !routeContext.mounted) return;

            final recent = await albums.first.getAssetListRange(
              start: 0,
              end: 1,
            );
            if (recent.isEmpty || !routeContext.mounted) return;

            Navigator.of(routeContext).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => ACutResultScreen(selectedAssets: recent),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── 헤더 ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/pozy_logo2.png',
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const HistoryScreen(),
                        ),
                      ),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              color: _kGrey600,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '분석 기록',
                              style: TextStyle(
                                color: _kGrey600,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            // ── 히어로 배너 (블루 그라데이션) ──
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5BA8FB), Color(0xFF1B5FD1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3182F6).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Pozy AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '내 사진 중에서 가장 잘 나온\n베스트 컷만 골라드려요',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.4,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pozy가 여러 장을 한눈에 비교해드려요!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── 액션 카드 2개 (가로 배치) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // 갤러리 분석
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BestCutGalleryScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEBF4FF),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.photo_library_rounded,
                                  color: _kBlue,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '갤러리에서\n분석하기',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _kDark,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '사진을 골라 비교해요',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: _kGrey600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 촬영 평가
                    Expanded(
                      child: GestureDetector(
                        onTap: _openCameraForEval,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEBF4FF),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: _kBlue,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '촬영 후\n바로 평가받기',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _kDark,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '찍고 바로 평가받아요',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: _kGrey600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── 분석 항목 카드 ──
            const SliverToBoxAdapter(
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pozy가 분석하는 요소',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _AnalysisItem(
                            icon: Icons.grid_on_rounded,
                            label: '구도',
                            color: Color(0xFF3182F6),
                          ),
                        ),
                        Expanded(
                          child: _AnalysisItem(
                            icon: Icons.wb_sunny_rounded,
                            label: '노출',
                            color: Color(0xFF3182F6),
                          ),
                        ),
                        Expanded(
                          child: _AnalysisItem(
                            icon: Icons.palette_rounded,
                            label: '선명도',
                            color: Color(0xFF3182F6),
                          ),
                        ),
                        Expanded(
                          child: _AnalysisItem(
                            icon: Icons.auto_awesome_rounded,
                            label: '분위기',
                            color: Color(0xFF3182F6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── 안내 팁 카드 ──
            SliverToBoxAdapter(
              child: _Card(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lightbulb_outline_rounded,
                        color: _kBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '사진은 여러 장 넣으면 더 정확해요',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '비슷한 구도의 사진끼리 비교하면 효과적이에요',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: _kGrey600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

// ── 카드 래퍼 ──
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── 분석 항목 아이템 ──
class _AnalysisItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _AnalysisItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _kDark,
          ),
        ),
      ],
    );
  }
}
