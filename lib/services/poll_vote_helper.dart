import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/poll.dart';
import '../models/post.dart';
import '../screens/auth_required_screen.dart';
import 'auth_service.dart';
import 'post_service.dart';
import 'posts_firestore_service.dart';

/// In-flight vote locks (per postId) — blocks duplicate callable writes.
final Set<String> _pendingVotes = <String>{};

Future<bool> _ensureKakaoWriter(BuildContext context) async {
  final auth = AuthService.instance;
  if (auth.canWriteContent) return true;

  final ready = await AuthRequiredScreen.ensureWriter(context);
  if (!ready || !context.mounted) return false;
  return auth.canWriteContent;
}

/// Local optimistic poll mutation (mirrors server castVote scenarios).
Poll? _optimisticPoll(Poll poll, String optionId) {
  final optId = optionId.trim();
  if (optId.isEmpty) return null;
  if (!poll.options.any((o) => o.id == optId)) return null;

  String? previousId;
  for (final o in poll.options) {
    if (o.selectedByMe) {
      previousId = o.id;
      break;
    }
  }

  if (previousId == optId) {
    return poll.copyWith(
      hasVoted: false,
      options: [
        for (final o in poll.options)
          o.copyWith(
            selectedByMe: false,
            votes: o.id == optId
                ? (o.votes - 1).clamp(0, 1 << 30)
                : o.votes,
          ),
      ],
    );
  }

  return poll.copyWith(
    hasVoted: true,
    options: [
      for (final o in poll.options)
        o.copyWith(
          selectedByMe: o.id == optId,
          votes: () {
            var next = o.votes;
            if (previousId != null && o.id == previousId) {
              next = (o.votes - 1).clamp(0, 1 << 30);
            } else if (o.id == optId) {
              next = o.votes + 1;
            }
            return next;
          }(),
        ),
    ],
  );
}

/// Poll vote — Kakao writer + Firebase Auth → Cloud Function `castVote`.
///
/// Optimistic UI first (like/post pattern); rolls back on callable failure.
Future<void> castPostVote(
  BuildContext context, {
  required Post post,
  required String optionId,
}) async {
  if (!await _ensureKakaoWriter(context) || !context.mounted) return;

  final kakaoId = AuthService.instance.kakaoUserId?.trim();
  if (kakaoId == null || kakaoId.isEmpty) return;

  final postId = post.id.trim();
  final optId = optionId.trim();
  if (postId.isEmpty || optId.isEmpty) return;
  if (_pendingVotes.contains(postId)) return;
  _pendingVotes.add(postId);

  final baseline = PostService.instance.getById(postId) ??
      PostsFirestoreService.instance.peekCachedPostStale(postId) ??
      post;
  final baselinePoll = baseline.poll?.clone();
  if (baselinePoll == null) {
    _pendingVotes.remove(postId);
    return;
  }

  final optimisticPoll = _optimisticPoll(baselinePoll, optId);
  if (optimisticPoll == null) {
    _pendingVotes.remove(postId);
    return;
  }
  final optimistic = baseline.copyWith(poll: optimisticPoll);
  PostService.instance.upsertRemotePost(optimistic);
  PostsFirestoreService.instance.applyLocalPostUpdate(optimistic);

  try {
    final updated = await PostsFirestoreService.instance.castVote(
      postId: postId,
      optionId: optId,
    );
    PostService.instance.upsertRemotePost(updated);
    PostsFirestoreService.instance.applyLocalPostUpdate(updated);
  } catch (e) {
    debugPrint('투표 저장 실패: $e');
    final rolled = baseline.copyWith(poll: baselinePoll);
    PostService.instance.upsertRemotePost(rolled);
    PostsFirestoreService.instance.applyLocalPostUpdate(rolled);
    if (!context.mounted) return;
    final message = e is FirebaseFunctionsException
        ? _userMessageForVoteError(e)
        : '투표를 저장하지 못했어요. 다시 시도해주세요.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } finally {
    _pendingVotes.remove(postId);
  }
}

String _userMessageForVoteError(FirebaseFunctionsException e) {
  switch (e.code) {
    case 'unauthenticated':
      return '로그인이 필요해요. 다시 로그인한 뒤 시도해주세요.';
    case 'permission-denied':
      return '투표 권한이 없어요.';
    case 'not-found':
      return '글을 찾을 수 없어요.';
    case 'failed-precondition':
    case 'invalid-argument':
      return '투표를 할 수 없는 상태예요.';
    default:
      return '투표를 저장하지 못했어요. 다시 시도해주세요.';
  }
}
