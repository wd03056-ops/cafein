import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/report.dart';
import 'firebase_auth_bridge.dart';

/// Admin report moderation via Cloud Functions (Admin SDK).
///
/// Does **not** write moderation fields from the Flutter client.
/// Server verifies Firebase Auth + admin claim / ADMIN_UIDS.
///
/// Normal users still use [ReportFirestoreService] for create / list-mine / withdraw.
class ReportModerationService {
  ReportModerationService._();
  static final ReportModerationService instance = ReportModerationService._();

  static const _region = FirebaseAuthBridge.region;

  HttpsCallable _callable(String name) {
    return FirebaseFunctions.instanceFor(region: _region).httpsCallable(name);
  }

  /// Ensure Custom Token session exists before admin callables.
  Future<void> _ensureFirebaseAuth() async {
    if (FirebaseAuthBridge.instance.isSignedIn) return;
    final ok = await FirebaseAuthBridge.instance.signInWithCurrentKakaoToken();
    if (!ok || !FirebaseAuthBridge.instance.isSignedIn) {
      throw StateError(
        'Firebase Auth 세션이 없어 운영 기능을 사용할 수 없어요. '
        '카카오 로그인 후 다시 시도해 주세요.',
      );
    }
  }

  Report _reportFromMap(Map<String, dynamic> map) {
    return Report.fromFirestore(map['id']?.toString() ?? '', map);
  }

  Map<String, dynamic> _asStringKeyMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Future<Report> _resolve({
    required String reportId,
    required String action,
    required String status,
    String? adminNote,
  }) async {
    await _ensureFirebaseAuth();
    final id = reportId.trim();
    if (id.isEmpty) {
      throw ArgumentError('reportId가 비어 있어요.');
    }

    final payload = <String, dynamic>{
      'reportId': id,
      'action': action,
      'status': status,
    };
    if (adminNote != null) {
      payload['adminNote'] = adminNote.trim();
    }

    try {
      final result = await _callable('adminResolveReport').call(payload);
      final data = _asStringKeyMap(result.data);
      final reportMap = _asStringKeyMap(data['report']);
      if (reportMap.isEmpty) {
        throw StateError('서버 응답에 report가 없어요.');
      }
      final report = _reportFromMap(reportMap);
      if (data['idempotent'] == true) {
        debugPrint(
          '[REPORT_MODERATION] adminResolveReport idempotent '
          'reportId=$id action=$action',
        );
      }
      return report;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[REPORT_MODERATION] adminResolveReport FAILED '
        'code=${e.code} message=${e.message}',
      );
      rethrow;
    }
  }

  /// Mark a report as under review.
  Future<Report> reviewReport({
    required String reportId,
    required String reviewedBy,
    String? adminNote,
  }) {
    // reviewedBy ignored — server uses request.auth.uid.
    return _resolve(
      reportId: reportId,
      action: ReportAction.firestoreNone,
      status: ReportStatus.firestoreReviewing,
      adminNote: adminNote,
    );
  }

  /// Resolve with status fields only (not content_deleted / user_warned).
  Future<Report> resolveReport({
    required String reportId,
    required String reviewedBy,
    required ReportAction action,
    String? adminNote,
    bool? reporterNotified,
    bool? reportedUserNotified,
  }) {
    if (action == ReportAction.none) {
      throw ArgumentError('resolveReport requires a non-none action.');
    }
    if (action == ReportAction.contentDeleted) {
      throw ArgumentError(
        'content_deleted는 resolveByDeletingContent()를 사용하세요.',
      );
    }
    if (action == ReportAction.userWarned) {
      throw ArgumentError(
        'user_warned는 resolveByWarning()를 사용하세요.',
      );
    }
    if (action == ReportAction.userSuspended) {
      throw UnsupportedError(
        'user_suspended는 아직 지원하지 않아요.',
      );
    }
    // No other concrete actions today.
    throw UnsupportedError('지원하지 않는 action: ${action.firestoreValue}');
  }

  /// Warn target user via CF (moderation_actions + resolve). No content delete.
  Future<Report> resolveByWarning({
    required String reportId,
    required String reviewedBy,
    String? adminNote,
  }) {
    return _resolve(
      reportId: reportId,
      action: ReportAction.firestoreUserWarned,
      status: ReportStatus.firestoreResolved,
      adminNote: adminNote,
    );
  }

  /// Delete reported content via CF Admin SDK, then resolve content_deleted.
  Future<Report> resolveByDeletingContent({
    required String reportId,
    required String reviewedBy,
    String? adminNote,
  }) {
    return _resolve(
      reportId: reportId,
      action: ReportAction.firestoreContentDeleted,
      status: ReportStatus.firestoreResolved,
      adminNote: adminNote,
    );
  }

  /// Dismiss without punitive action.
  Future<Report> dismissReport({
    required String reportId,
    required String reviewedBy,
    String? adminNote,
    bool? reporterNotified,
    bool? reportedUserNotified,
  }) {
    return _resolve(
      reportId: reportId,
      action: ReportAction.firestoreNone,
      status: ReportStatus.firestoreDismissed,
      adminNote: adminNote,
    );
  }

  /// All reports for admin UI (server-filtered).
  Future<List<Report>> listAllReports({ReportStatus? status}) async {
    await _ensureFirebaseAuth();
    try {
      final payload = <String, dynamic>{};
      if (status != null) {
        payload['status'] = status.firestoreValue;
      }
      final result = await _callable('adminListReports').call(payload);
      final data = _asStringKeyMap(result.data);
      final rawList = data['reports'];
      if (rawList is! List) return const [];
      return [
        for (final item in rawList)
          _reportFromMap(_asStringKeyMap(item)),
      ];
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[REPORT_MODERATION] adminListReports FAILED '
        'code=${e.code} message=${e.message}',
      );
      rethrow;
    }
  }

  /// Single report for admin detail (live content + snapshots).
  Future<AdminReportDetailData?> getReport(String reportId) async {
    await _ensureFirebaseAuth();
    final id = reportId.trim();
    if (id.isEmpty) return null;
    try {
      final result = await _callable('adminGetReport').call({
        'reportId': id,
      });
      final data = _asStringKeyMap(result.data);
      final reportMap = _asStringKeyMap(data['report']);
      if (reportMap.isEmpty) return null;
      final report = _reportFromMap(reportMap);
      return AdminReportDetailData(
        report: report,
        liveTarget: _liveSnapshot(data['target']),
        liveParentPost: _liveSnapshot(data['parentPost']),
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') return null;
      debugPrint(
        '[REPORT_MODERATION] adminGetReport FAILED '
        'code=${e.code} message=${e.message}',
      );
      rethrow;
    }
  }

  ReportContentSnapshot? _liveSnapshot(Object? raw) {
    final map = _asStringKeyMap(raw);
    if (map.isEmpty) return null;
    if (map['exists'] == false) return null;
    return ReportContentSnapshot.tryParse(map);
  }
}

/// Admin detail payload: report doc + optional live Firestore content.
class AdminReportDetailData {
  const AdminReportDetailData({
    required this.report,
    this.liveTarget,
    this.liveParentPost,
  });

  final Report report;
  final ReportContentSnapshot? liveTarget;
  final ReportContentSnapshot? liveParentPost;
}
