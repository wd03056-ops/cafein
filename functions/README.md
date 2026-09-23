# Cloud Functions (FCM push + Auth bridge + admin report moderation)

Deploy after enabling Blaze plan (if required) and Cloud Functions API.

```bash
cd functions
npm install
cd ..
firebase deploy --only functions,firestore:indexes
```

Region: **asia-northeast3**.

## Auth bridge

- **`createFirebaseCustomToken`** (callable)
  - Input: `{ kakaoAccessToken }`
  - Verifies via Kakao `GET /v2/user/me`
  - Returns `{ customToken, uid }`
  - If `uid` is in server param **`ADMIN_UIDS`**, Custom Token includes claim `{ admin: true }`

## Admin report moderation (Phase 3)

Server-only. Client must be Firebase Auth signed-in (Custom Token).  
Admin check: `request.auth.token.admin === true` **or** `request.auth.uid` ∈ **`ADMIN_UIDS`**  
(Never trust client `isAdmin` / `AdminAccess.adminKakaoUserIds`.)

Set param (deploy prompt or `functions/.env` for emulator) — see `.env.example`:

```text
ADMIN_UIDS=your_kakao_user_id
```

Callables:

| Function | Purpose |
|----------|---------|
| `adminListReports` | `{ status? }` → `{ reports: [...] }` |
| `adminGetReport` | `{ reportId }` → `{ report, target? }` |
| `adminResolveReport` | `{ reportId, action, status?, adminNote? }` |

`adminResolveReport` actions:

- `none` + `status=reviewing|dismissed` — review / dismiss
- `content_deleted` — Admin SDK deletes post/comment cascade, then resolves  
  (triggers existing `onReportUpdated` notifications)
- `user_warned` — writes `users/{target}/moderation_actions/{reportId}`, then resolves
- `user_suspended` — **unimplemented** (explicit error; no fake freeze)

Idempotent: re-resolving the same `resolved` + same action returns without re-deleting.

**Firestore Rules stay open this phase.** Do not deploy locked rules yet.

## Notification triggers

- `onCommentCreated` — `posts/{postId}/comments/{commentId}`
- `onLikeCreated` — `posts/{postId}/likes/{userId}` (create only; unlike does not notify)
- `onCommentLikeCreated` — `posts/{postId}/comments/{commentId}/likes/{userId}`
- `onReportUpdated` — `reports/{reportId}` when `status=resolved` and
  `action` is `content_deleted` **or** `user_warned`
  - Notifies reporter (`report_result` / audience=reporter) — generic copy
  - Notifies target author (`audience=reported`) — delete vs warn copy
  - Sets `reporterNotified` / `reportedUserNotified` after inbox write (idempotent)
  - `user_warned` history is written by **`adminResolveReport`** (Admin SDK)

Respects `users/{uid}.notificationSettings.comment|like` for social notifications.
Report-result push is **not** gated by those toggles (moderation notice).
Also writes inbox docs under `notifications/`.

## Inbox safeguards

1. **Self-action filter** — if actor UID === recipient UID, no inbox doc and no FCM.
2. **Duplicate prevention** — deterministic doc id  
   `{recipient}__{type}__{postId}__{commentId}__{actor}`.  
   If an **unread** doc already exists, only `updatedAt` / `expireAt` / `message` are updated (no extra doc, no extra push).
3. **Growth cap** — after create/reopen, prune oldest docs so each recipient keeps at most **50** inbox items (requires composite index on `recipientUserId` + `createdAt`).
4. **TTL** — each inbox doc sets `expireAt` = now + **30 days**. Enable Firestore TTL on that field so old docs are deleted automatically.

### Enable Firestore TTL (one-time)

Indexes deploy may already set TTL via `firestore.indexes.json` (`fieldOverrides.expireAt.ttl`).

If TTL is not active yet, enable in Console or CLI:

```bash
gcloud firestore fields ttls update expireAt \
  --collection-group=notifications \
  --enable-ttl
```

TTL deletes are eventually consistent (often within 24h after `expireAt`).

Reply notifications are not implemented (no reply feature in the app yet).
