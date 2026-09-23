import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/report.dart';
import 'auth_service.dart';

/// Firestore `reports/{id}` — user-facing report create / list / withdraw.
///
/// Moderation updates go through [ReportModerationService] (Cloud Functions).
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
  ///
  /// New docs (and refreshes) set [ReportStatus.pending] / [ReportAction.none].
  /// Does not clear admin review fields on merge; those are owned by moderation.
  ///
  /// Captures [targetSnapshot] / [parentPostSnapshot] when missing so admins
  /// can still read content after deletion.
  Future<void> submitReport({
    required String targetType,
    required String targetId,
    required String reason,
    String? targetAuthorId,
    String? parentPostId,
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
      final ref = _reports.doc(docId);
      final existing = await ref.get();
      final existingData = existing.data();
      final existingStatus =
          (existingData?['status'] as String?)?.trim() ?? '';

      final payload = <String, dynamic>{
        'reporterId': reporterId,
        'targetType': type,
        'targetId': id,
        'targetAuthorId': targetAuthorId?.trim() ?? '',
        'reason': why,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final parent = parentPostId?.trim() ?? '';
      if (parent.isNotEmpty) {
        payload['parentPostId'] = parent;
      }

      // New docs + legacy docs without status → pending / none.
      // Do not reset reviewing / resolved / dismissed on reason refresh.
      if (!existing.exists || existingStatus.isEmpty) {
        payload['status'] = ReportStatus.firestorePending;
        payload['action'] = ReportAction.firestoreNone;
        payload['reporterNotified'] = false;
        payload['reportedUserNotified'] = false;
      }

      final needsSnapshot = !existing.exists ||
          existingData?['targetSnapshot'] == null;
      if (needsSnapshot) {
        final snaps = await _buildSnapshots(
          targetType: type,
          targetId: id,
          parentPostId: parent.isEmpty ? null : parent,
        );
        if (snaps.target != null) {
          payload['targetSnapshot'] = _snapshotWriteMap(snaps.target!);
        }
        if (snaps.parent != null) {
          payload['parentPostSnapshot'] = _snapshotWriteMap(snaps.parent!);
        }
      }

      await ref.set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('신고 저장 실패: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _snapshotWriteMap(ReportContentSnapshot snap) {
    final map = snap.toMap();
    final created = map['createdAt'];
    if (created is DateTime) {
      map['createdAt'] = Timestamp.fromDate(created);
    }
    return map;
  }

  Future<({ReportContentSnapshot? target, ReportContentSnapshot? parent})>
      _buildSnapshots({
    required String targetType,
    required String targetId,
    String? parentPostId,
  }) async {
    final type = targetType.toLowerCase();
    try {
      if (type == 'post') {
        final snap =
            await _firestore.collection('posts').doc(targetId).get();
        if (!snap.exists || snap.data() == null) {
          return (target: null, parent: null);
        }
        return (target: _snapshotFromPostData(snap.data()!), parent: null);
      }
      if (type == 'comment') {
        final postId = parentPostId?.trim() ?? '';
        if (postId.isEmpty) return (target: null, parent: null);
        final commentSnap = await _firestore
            .collection('posts')
            .doc(postId)
            .collection('comments')
            .doc(targetId)
            .get();
        ReportContentSnapshot? target;
        if (commentSnap.exists && commentSnap.data() != null) {
          target = _snapshotFromCommentData(commentSnap.data()!);
        }
        final postSnap =
            await _firestore.collection('posts').doc(postId).get();
        ReportContentSnapshot? parent;
        if (postSnap.exists && postSnap.data() != null) {
          parent = _snapshotFromPostData(postSnap.data()!);
        }
        return (target: target, parent: parent);
      }
      if (type == 'user') {
        final userSnap =
            await _firestore.collection('users').doc(targetId).get();
        if (!userSnap.exists || userSnap.data() == null) {
          return (target: null, parent: null);
        }
        final d = userSnap.data()!;
        final nick = (d['nickname'] as String?)?.trim() ??
            (d['kakaoNickname'] as String?)?.trim() ??
            '';
        return (
          target: ReportContentSnapshot(
            content: '',
            authorDisplayName: nick.isEmpty ? targetId : nick,
          ),
          parent: null,
        );
      }
    } catch (e) {
      debugPrint('신고 snapshot 수집 실패(무시하고 신고는 진행): $e');
    }
    return (target: null, parent: null);
  }

  ReportContentSnapshot _snapshotFromPostData(Map<String, dynamic> data) {
    final author = (data['authorNickname'] as String?)?.trim() ??
        (data['nickname'] as String?)?.trim() ??
        (data['author'] as String?)?.trim() ??
        '';
    String pollQuestion = '';
    final pollOptions = <String>[];
    final rawPoll = data['poll'];
    if (rawPoll is Map) {
      pollQuestion = (rawPoll['question'] as String?)?.trim() ?? '';
      final opts = rawPoll['options'];
      if (opts is List) {
        for (final item in opts) {
          if (item is Map) {
            final t = (item['text'] as String?)?.trim() ?? '';
            if (t.isNotEmpty) pollOptions.add(t);
          }
        }
      }
    }
    return ReportContentSnapshot(
      content: (data['content'] as String?)?.trim() ?? '',
      topicName: (data['topicName'] as String?)?.trim() ?? '',
      authorDisplayName: author,
      createdAt: _asDateTime(data['createdAt']),
      pollQuestion: pollQuestion,
      pollOptions: pollOptions,
    );
  }

  ReportContentSnapshot _snapshotFromCommentData(Map<String, dynamic> data) {
    final author = (data['authorNickname'] as String?)?.trim() ??
        (data['nickname'] as String?)?.trim() ??
        (data['author'] as String?)?.trim() ??
        '';
    return ReportContentSnapshot(
      content: (data['content'] as String?)?.trim() ?? '',
      authorDisplayName: author,
      createdAt: _asDateTime(data['createdAt']),
    );
  }

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Single report by document id (for moderation / tools).
  Future<Report?> getReport(String reportId) async {
    final id = reportId.trim();
    if (id.isEmpty) return null;
    final snap = await _reports.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return Report.fromFirestore(snap.id, snap.data()!);
  }

  /// Reports filed by the current user (for settings list).
  Future<List<UserReportEntry>> listMyReports() async {
    AuthService.instance.requireKakaoWriter();
    final reporterId = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (reporterId.isEmpty) return const [];

    final snap =
        await _reports.where('reporterId', isEqualTo: reporterId).get();
    final entries = <UserReportEntry>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final targetAuthorId =
          (data['targetAuthorId'] as String?)?.trim() ?? '';
      final reason = (data['reason'] as String?)?.trim() ?? '';
      final targetType = (data['targetType'] as String?)?.trim() ?? '';
      final targetId = (data['targetId'] as String?)?.trim() ?? '';
      DateTime? createdAt;
      final raw = data['createdAt'] ?? data['updatedAt'];
      if (raw is Timestamp) createdAt = raw.toDate();
      entries.add(
        UserReportEntry(
          id: doc.id,
          targetAuthorId: targetAuthorId,
          targetType: targetType,
          targetId: targetId,
          reason: reason,
          createdAt: createdAt,
          status: ReportStatus.fromFirestore(data['status']),
        ),
      );
    }
    entries.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return entries;
  }

  /// Withdraw a report owned by the current user (delete doc).
  Future<void> withdrawReport(String reportId) async {
    AuthService.instance.requireKakaoWriter();
    final reporterId = AuthService.instance.kakaoUserId?.trim() ?? '';
    final id = reportId.trim();
    if (reporterId.isEmpty || id.isEmpty) return;

    final ref = _reports.doc(id);
    final snap = await ref.get();
    if (!snap.exists) return;
    final owner = (snap.data()?['reporterId'] as String?)?.trim() ?? '';
    if (owner != reporterId) {
      throw StateError('본인이 작성한 신고만 철회할 수 있어요.');
    }
    await ref.delete();
  }
}

class UserReportEntry {
  const UserReportEntry({
    required this.id,
    required this.targetAuthorId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.createdAt,
    this.status = ReportStatus.pending,
  });

  final String id;
  final String targetAuthorId;
  final String targetType;
  final String targetId;
  final String reason;
  final DateTime? createdAt;

  /// Present for future UI; settings list does not display it yet.
  final ReportStatus status;
}
