# CAFEIN Firestore Security Phase 2 — Analysis (draft only, NOT deployed)

Identity premise: Firebase Auth Custom Token uid == Kakao user id (`request.auth.uid`).

Live `firestore.rules` remains open. Apply draft from `firestore.rules.draft` only after server-side admin migration + device test.

---

## 1. Collection structure (code-verified)

| Path | Purpose |
|------|---------|
| `users/{kakaoUid}` | Profile, FCM, notificationSettings |
| `users/{uid}/moderation_actions/{reportId}` | Warning history (admin client today) |
| `nicknames/{nickname}` | Unique nickname index (`uid`) |
| `topics/{topicId}` | Topic + `usageCount` |
| `topic_names/{nameKey}` | Unique topic name → topicId |
| `posts/{postId}` | Posts; embedded `poll` / `pollVoters` / `likedBy` |
| `posts/{postId}/comments/{commentId}` | Comments |
| `posts/{postId}/likes/{uid}` | Post like docs |
| `posts/{postId}/comments/{cid}/likes/{uid}` | Comment like docs |
| `posts/{postId}/poll_votes/{uid}` | Legacy vote docs (read fallback only) |
| `reports/{reporterId}_{type}_{id}` | Reports |
| `blocks/{blockerId}_{blockedId}` | Blocks |
| `notifications/{deterministicId}` | Inbox (CF write) |

No top-level `fcmTokens` collection (fields on `users` only).

---

## 2. Access matrix (target design)

| Collection | public read | auth read | own write | admin/server write |
|------------|-------------|-----------|-----------|--------------------|
| posts (+ comments) | yes (guest feed) | yes | create/update/delete own content; engagement updates (like/vote/commentCount) | CF read; admin delete → **must move to server** |
| posts/.../likes | yes (list for cascade) | yes | create/delete own like doc | — |
| topics / topic_names | yes | yes | auth create + usageCount adjust | — |
| nicknames | auth (availability) | yes | claim/release own `uid` | — |
| users | no (PII) | get others for profile enrich; own full | own doc only | CF read tokens |
| moderation_actions | no | optional own later | **deny client** | **Admin SDK / CF** |
| reports | no | own (`reporterId`) | create + reason update + withdraw | moderation fields → **CF**; notify flags → CF `onReportUpdated` |
| blocks | no | own (`blockerId`) | own create/delete | — |
| notifications | no | own recipient (withdraw query) | delete own only | CF create/update/prune |
| poll_votes (legacy) | no | own doc get | deny create; allow delete if post author cascade | — |

---

## 3. Features that break if Rules locked naively / with this draft

| Feature | Why it breaks |
|---------|----------------|
| Admin report list (`listAllReports`) | Needs read-all reports; no `request.auth.token.admin` yet |
| `reviewReport` / `resolveReport` / dismiss | Client writes `status/action/reviewedBy/...` |
| `resolveByWarning` | Client writes `moderation_actions` |
| `resolveByDeletingContent` | `deletePost` has **no** authorId check; deletes others' content |
| Post delete cascade | Author deletes **all** likes/comments under post (needs post-author delete on foreign docs) |
| Counter integrity | Client still updates `likeCount` / `commentCount` / poll `voteCount` — Rules can constrain ±1 / own map keys but not fully replace CF |
| Topic `usageCount` spam | Any authed user can increment via topic APIs |
| Guest `users/{id}` enrich | If users not public-read, guest comment profile enrich fails softly |

---

## 4. Required structure changes before production deploy

1. Move admin moderation (resolve/warn/delete content) to **callable Cloud Functions** (Admin SDK).
2. Optionally move post cascade delete + engagement counters to CF (stronger integrity).
3. Add Firebase Auth **custom claims** (`admin: true`) for operators — never `AdminAccess.adminKakaoUserIds` alone.
4. Keep Custom Token bridge mandatory before locking Rules.
5. Copy `firestore.rules.draft` → `firestore.rules` only after (1)+(3)+device tests.

---

## 5–7. See companion draft + chat summary for rules text, server-only list, A/B test plan.
