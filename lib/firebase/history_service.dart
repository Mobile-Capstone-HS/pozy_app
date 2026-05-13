import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../feature/a_cut/model/multi_photo_ranking_result.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../feature/a_cut/model/scored_photo_result.dart';

enum HistoryType { acut, single }

// A컷 랭킹에서 직렬화 가능한 항목
class HistoryRankedItem {
  final String fileName;
  final String? assetId;
  final int? rank;
  final bool isACut;
  final bool isBestShot;
  final PhotoEvaluationResult? evaluation;

  const HistoryRankedItem({
    required this.fileName,
    this.assetId,
    required this.rank,
    required this.isACut,
    required this.isBestShot,
    this.evaluation,
  });

  Map<String, dynamic> toMap() => {
    'fileName': fileName,
    if (assetId != null) 'assetId': assetId,
    'rank': rank,
    'isACut': isACut,
    'isBestShot': isBestShot,
    'evaluation': evaluation?.toJson(),
  };

  factory HistoryRankedItem.fromMap(Map<String, dynamic> m) {
    final evalMap = m['evaluation'] as Map<String, dynamic>?;
    return HistoryRankedItem(
      fileName: m['fileName'] as String? ?? '',
      assetId: m['assetId'] as String?,
      rank: m['rank'] as int?,
      isACut: m['isACut'] as bool? ?? false,
      isBestShot: m['isBestShot'] as bool? ?? false,
      evaluation: evalMap != null
          ? PhotoEvaluationResult.fromJson(evalMap)
          : null,
    );
  }
}

class HistoryEntry {
  final String id;
  final HistoryType type;
  final DateTime analyzedAt;
  final int photoCount;
  final String? bestFileName;
  final String? bestAssetId;
  final bool pinned;
  final String? assetId;
  // 단일 평가 결과
  final PhotoEvaluationResult? evaluation;
  // A컷 랭킹 결과
  final List<HistoryRankedItem> rankedItems;

  const HistoryEntry({
    required this.id,
    required this.type,
    required this.analyzedAt,
    required this.photoCount,
    this.bestFileName,
    this.bestAssetId,
    this.pinned = false,
    this.assetId,
    this.evaluation,
    this.rankedItems = const [],
  });

  String get typeLabel => type == HistoryType.acut ? 'A컷 랭킹' : '단일 평가';

  String get subtitle {
    if (type == HistoryType.acut) {
      return '사진 $photoCount장 분석';
    }
    return bestFileName ?? '사진 1장 평가';
  }

  factory HistoryEntry.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final evalMap = data['evaluation'] as Map<String, dynamic>?;
    final rankedRaw = data['rankedItems'] as List<dynamic>?;

    return HistoryEntry(
      id: doc.id,
      type: data['type'] == 'acut' ? HistoryType.acut : HistoryType.single,
      analyzedAt: (data['analyzedAt'] as Timestamp).toDate(),
      photoCount: data['photoCount'] as int? ?? 1,
      bestFileName: data['bestFileName'] as String?,
      bestAssetId: data['bestAssetId'] as String?,
      pinned: data['pinned'] as bool? ?? false,
      assetId: data['assetId'] as String?,
      evaluation: evalMap != null
          ? PhotoEvaluationResult.fromJson(evalMap)
          : null,
      rankedItems:
          rankedRaw
              ?.map((e) => HistoryRankedItem.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class HistoryService {
  static final HistoryService _instance = HistoryService._();
  static HistoryService get instance => _instance;
  HistoryService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('history');
  }

  Future<void> saveACut({required MultiPhotoRankingResult ranking}) async {
    final col = _col;
    if (col == null) return;

    final rankedItems = ranking.items
        .where((e) => e.status == ScoreStatus.success)
        .map(
          (e) => HistoryRankedItem(
            fileName: e.fileName,
            assetId: e.asset.id,
            rank: e.rank,
            isACut: e.isACut,
            isBestShot: e.isBestShot,
            evaluation: e.evaluation,
          ).toMap(),
        )
        .toList();

    await col.add({
      'type': 'acut',
      'analyzedAt': FieldValue.serverTimestamp(),
      'photoCount': ranking.items.length,
      'bestFileName': ranking.bestShot?.fileName,
      'bestAssetId': ranking.bestShot?.asset.id,
      'pinned': false,
      'rankedItems': rankedItems,
    });
  }

  Future<void> saveSingle({
    required PhotoEvaluationResult result,
    String? assetId,
  }) async {
    final col = _col;
    if (col == null) return;
    await col.add({
      'type': 'single',
      'analyzedAt': FieldValue.serverTimestamp(),
      'photoCount': 1,
      'bestFileName': result.fileName,
      'bestAssetId': assetId,
      'pinned': false,
      'assetId': assetId,
      'evaluation': result.toJson(),
    });
  }

  Future<void> togglePin(String id, bool current) async {
    final col = _col;
    if (col == null) return;
    await col.doc(id).update({'pinned': !current});
  }

  Future<void> delete(String id) async {
    final col = _col;
    if (col == null) return;
    await col.doc(id).delete();
  }

  Stream<List<HistoryEntry>> watchHistory() {
    final col = _col;
    if (col == null) return const Stream.empty();
    return col
        .orderBy('analyzedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
          final all = snap.docs.map(HistoryEntry.fromDoc).toList();
          final pinned = all.where((e) => e.pinned).toList();
          final rest = all.where((e) => !e.pinned).toList();
          return [...pinned, ...rest];
        });
  }
}
