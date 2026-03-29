import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'coaching_result.dart';

/// 픽셀 휘도 기반 즉각 밝기 분석 서비스.
/// JPEG 프레임을 64×64로 축소 후 BT.601 휘도를 계산하여
/// 어둠·역광·노출과다 여부를 반환한다. 정상이면 null.
class PixelAnalysisService {
  Future<CoachingResult?> analyze(List<int> jpegBytes) =>
      compute(_analyze, Uint8List.fromList(jpegBytes));
}

CoachingResult? _analyze(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final small = img.copyResize(decoded, width: 64, height: 64);

  double totalLum = 0;
  double centerLum = 0;
  double edgeLum = 0;
  int centerCount = 0;
  int edgeCount = 0;

  for (int y = 0; y < 64; y++) {
    for (int x = 0; x < 64; x++) {
      final p = small.getPixel(x, y);
      final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
      totalLum += lum;
      final isCenter = x >= 16 && x < 48 && y >= 16 && y < 48;
      if (isCenter) {
        centerLum += lum;
        centerCount++;
      } else {
        edgeLum += lum;
        edgeCount++;
      }
    }
  }

  final avg = totalLum / (64 * 64);
  final centerAvg = centerCount > 0 ? centerLum / centerCount : avg;
  final edgeAvg = edgeCount > 0 ? edgeLum / edgeCount : avg;

  // 카메라 미준비 빈 프레임 무시
  if (avg < 0.01) return null;

  debugPrint('[Pixel] avg=${avg.toStringAsFixed(3)} center=${centerAvg.toStringAsFixed(3)} edge=${edgeAvg.toStringAsFixed(3)}');

  // 전체가 매우 어두움 (실내 정상값 0.45~0.60 기준)
  if (avg < 0.10) {
    return const CoachingResult(
      guidance: '플래시를 켜고 찍어보세요',
      level: CoachingLevel.warning,
      subGuidance: '전체적으로 너무 어둡게 나오고 있어요',
    );
  }

  // 역광: 배경이 밝고 중심부가 매우 어두움
  if (centerAvg < 0.20 && edgeAvg - centerAvg > 0.30) {
    return const CoachingResult(
      guidance: '플래시를 켜면 더 밝게 찍혀요',
      level: CoachingLevel.caution,
      subGuidance: '역광으로 어둡게 찍히고 있어요',
    );
  }

  // 노출 과다
  if (avg > 0.87) {
    return const CoachingResult(
      guidance: '조금 더 밝은 곳으로 이동해보세요',
      level: CoachingLevel.caution,
      subGuidance: '화면이 너무 밝게 나오고 있어요',
    );
  }

  return null; // 밝기 정상 → VLM이 구도 판단
}
