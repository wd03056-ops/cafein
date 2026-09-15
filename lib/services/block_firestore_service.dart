import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Firestore `blocks/{blockerId}_{blockedUserId}`.
class BlockFirestoreService extends ChangeNotifier {
  BlockFirestoreService._();
  static final BlockFirestoreService instance = BlockFirestoreService._();

  final _firestore = FirebaseFirestore.instance;
  final Set<String> _blockedIds = {};
  bool _loaded = false;
  String? _loadedForUid;

  CollectionReference<Map<String, dynamic>> get _blocks =>
      _firestore.collection('blocks');

  Set<String> get blockedUserIds => Set.unmodifiable(_blockedIds);

  bool isBlocked(String? userId) {
    final id = userId?.trim() ?? '';
    if (id.isEmpty) return false;
    return _blockedIds.contains(id);
  }

  String _docId(String blockerId, String blockedUserId) =>
      '${blockerId}_$blockedUserId';

  /// Load blocks for the current Kakao user into memory for feed filtering.
  Future<void> ensureLoaded() async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) {
      _blockedIds.clear();
      _loaded = false;
      _loadedForUid = null;
      return;
    }
    if (_loaded && _loadedForUid == uid) return;

    try {
      final snap = await _blocks.where('blockerId', isEqualTo: uid).get();
      _blockedIds
        ..clear()
        ..addAll(
          snap.docs
              .map((d) => (d.data()['blockedUserId'] as String?)?.trim() ?? '')
              .where((id) => id.isNotEmpty),
        );
      _loaded = true;
      _loadedForUid = uid;
      notifyListeners();
    } catch (e) {
      debugPrint('차단 목록 로드 실패: $e');
    }
  }

  void clearCache() {
    _blockedIds.clear();
    _loaded = false;
    _loadedForUid = null;
    notifyListeners();
  }

  List<T> filterByAuthorId<T>(
    List<T> items,
    String? Function(T item) authorIdOf,
  ) {
    if (_blockedIds.isEmpty) return items;
    return items
        .where((item) => !isBlocked(authorIdOf(item)))
        .toList();
  }

  Future<void> blockUser(String blockedUserId) async {
    AuthService.instance.requireKakaoWriter();
    final blockerId = AuthService.instance.kakaoUserId?.trim() ?? '';
    final blocked = blockedUserId.trim();
    if (blockerId.isEmpty || blocked.isEmpty) {
      throw ArgumentError('차단 정보가 올바르지 않아요.');
    }
    if (blockerId == blocked) {
      throw StateError('자기 자신은 차단할 수 없어요.');
    }

    final ref = _blocks.doc(_docId(blockerId, blocked));
    await ref.set({
      'blockerId': blockerId,
      'blockedUserId': blocked,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _blockedIds.add(blocked);
    notifyListeners();
  }

  Future<void> unblockUser(String blockedUserId) async {
    AuthService.instance.requireKakaoWriter();
    final blockerId = AuthService.instance.kakaoUserId?.trim() ?? '';
    final blocked = blockedUserId.trim();
    if (blockerId.isEmpty || blocked.isEmpty) return;

    await _blocks.doc(_docId(blockerId, blocked)).delete();
    _blockedIds.remove(blocked);
    notifyListeners();
  }

  /// Delete all blocks created by [blockerId] (account withdrawal).
  Future<void> deleteBlocksByBlocker(String blockerId) async {
    final id = blockerId.trim();
    if (id.isEmpty) return;
    try {
      QuerySnapshot<Map<String, dynamic>> page;
      do {
        page = await _blocks.where('blockerId', isEqualTo: id).limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (page.docs.isNotEmpty);
    } catch (e) {
      debugPrint('차단 기록 삭제 실패: $e');
    }
  }
}
