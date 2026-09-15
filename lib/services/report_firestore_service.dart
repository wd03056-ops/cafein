import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Firestore `reports/{id}` — moderation queue for Console review.
class ReportFirestoreService {
  ReportFirestoreService._();
  static final ReportFirestoreService instance = ReportFirestoreService._();

  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('reports');

  /// Doc id prevents rapid duplicate reports of the same target by one user.
  String _docId({
    required String reporterId,
    required String targetType,
    required String targetId,
  }) =>
      '${reporterId}_${targetType}_$targetId';

  /// Saves or refreshes a report. Same user + target updates reason/time.
  Future<void> submitReport({
    required String targetType,
    required String targetId,
    required String reason,
    String? targetAuthorId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final reporterId = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (reporterId.isEmpty) {
      throw StateError('로그인이 필요해요.');
    }
    final type = targetType.trim();
    final id = targetId.trim();
    final why = reason.trim();
    if (type.isEmpty || id.isEmpty || why.isEmpty) {
      throw ArgumentError('신고 정보가 올바르지 않아요.');
    }

    final docId = _docId(
      reporterId: reporterId,
      targetType: type,
      targetId: id,
    );

    try {
      await _reports.doc(docId).set({
        'reporterId': reporterId,
        'targetType': type,
        'targetId': id,
        'targetAuthorId': targetAuthorId?.trim() ?? '',
        'reason': why,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('신고 저장 실패: $e');
      rethrow;
    }
  }
}
