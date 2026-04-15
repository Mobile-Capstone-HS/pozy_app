import 'package:flutter/material.dart';
import '../models/photo_spot.dart';

/// 촬영 스팟의 지도 썸네일 이미지 위젯.
/// OpenStreetMap 무료 Static Map API를 사용해 실제 지도 이미지를 표시합니다.
/// 로딩 실패 시 카테고리 색상 그라디언트로 폴백합니다.
class SpotMapImage extends StatelessWidget {
  final PhotoSpot spot;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SpotMapImage({
    super.key,
    required this.spot,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  /// OpenStreetMap Static Map URL (무료, 인증 불필요)
  String get _mapUrl {
    final lat = spot.latitude;
    final lng = spot.longitude;
    // @2x 해상도로 요청해 선명하게 표시
    final w = (width * 2).clamp(100, 1280).toInt();
    final h = (height * 2).clamp(100, 1280).toInt();
    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lng'
        '&zoom=14'
        '&size=${w}x$h'
        '&markers=$lat,$lng,red-pushpin'
        '&maptype=mapnik';
  }

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      _mapUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: (width * 2).toInt(),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return _Placeholder(spot: spot, width: width, height: height, loading: true);
      },
      errorBuilder: (_, _, _) =>
          _Placeholder(spot: spot, width: width, height: height, loading: false),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

// ── 폴백 플레이스홀더 ────────────────────────────────────
class _Placeholder extends StatelessWidget {
  final PhotoSpot spot;
  final double width;
  final double height;
  final bool loading;

  const _Placeholder({
    required this.spot,
    required this.width,
    required this.height,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final color = spot.category.color;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.30),
          ],
        ),
      ),
      child: loading
          ? Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: color,
                ),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(spot.category.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    spot.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
