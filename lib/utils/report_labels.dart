import '../models/report.dart';

/// Korean display labels for admin report UI.
/// Does **not** change Firestore / Cloud Functions enum strings.

String reportStatusLabel(ReportStatus status) {
  switch (status) {
    case ReportStatus.pending:
      return '대기';
    case ReportStatus.reviewing:
      return '검토 중';
    case ReportStatus.resolved:
      return '처리 완료';
    case ReportStatus.dismissed:
      return '기각';
  }
}

String reportStatusLabelFromRaw(String? raw) {
  return reportStatusLabel(ReportStatus.fromFirestore(raw));
}

String reportActionLabel(ReportAction action) {
  switch (action) {
    case ReportAction.none:
      return '조치 없음';
    case ReportAction.contentDeleted:
      return '콘텐츠 삭제';
    case ReportAction.userWarned:
      return '사용자 경고';
    case ReportAction.userSuspended:
      return '사용자 이용 제한';
  }
}

String reportActionLabelFromRaw(String? raw) {
  return reportActionLabel(ReportAction.fromFirestore(raw));
}

String reportTargetTypeLabel(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'post':
      return '게시글';
    case 'comment':
      return '댓글';
    case 'user':
      return '사용자';
    case '':
      return '—';
    default:
      return raw!.trim();
  }
}

/// Field name labels on the admin report detail screen.
String reportFieldLabel(String key) {
  switch (key) {
    case 'status':
      return '상태';
    case 'action':
      return '조치';
    case 'targetType':
      return '대상 유형';
    case 'targetId':
      return '대상 ID';
    case 'targetAuthorId':
      return '대상 작성자 ID';
    case 'reporterId':
      return '신고자 ID';
    case 'parentPostId':
      return '원 게시글 ID';
    case 'reason':
      return '신고 사유';
    case 'createdAt':
      return '신고일';
    case 'reviewedBy':
      return '처리 관리자';
    case 'reviewedAt':
      return '처리일';
    case 'reporterNotified':
      return '신고자 알림';
    case 'reportedUserNotified':
      return '대상자 알림';
    case 'adminNote':
      return '관리자 메모';
    default:
      return key;
  }
}

String reportBoolLabel(bool value) => value ? '예' : '아니오';
