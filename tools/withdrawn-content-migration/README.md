# CAFEIN Withdrawn Content Migration (1회성 · 수동)

과거 회원탈퇴로 `authorWithdrawn == true`이지만 `authorId`가 여전히
실제 Kakao UID인 posts/comments를 `deleted_*`로 분리하는 도구입니다.

- Flutter 앱과 연결되지 않습니다.
- Cloud Function으로 등록되지 않습니다.
- **기본은 dry-run**이며, `--apply` 없이 Firestore를 **쓰지 않습니다**.
- **콘텐츠/집계 필드는 수정하지 않습니다** (author identity만).

관련 배경: [`docs/withdraw-account-migration.md`](../../docs/withdraw-account-migration.md)

---

## 대상 조건

| 포함 | 제외 |
|------|------|
| `authorWithdrawn == true` | `authorWithdrawn != true` (정상 사용자 콘텐츠) |
| `authorId`가 `deleted_`로 **시작하지 않음** | 이미 `authorId`가 `deleted_*` |
| posts + collectionGroup comments | likes / poll / topic / notifications |

**재가입 사용자:** `users/{legacyUid}`가 다시 존재해도  
`authorWithdrawn == true`인 legacy 콘텐츠는 **반드시** migration 대상입니다.

---

## deletedId 규칙

- 형식: `deleted_` + `crypto.randomUUID()` (하이픈 제거)
- **Kakao UID 해시 사용 금지**
- **legacy UID당 1개** deletedId → 해당 UID의 posts + comments가 동일 ID 공유
- dry-run preview JSON에 `legacyUid → deletedId` 매핑이 기록됨

---

## Apply 시 변경 필드만

**posts**

- `authorId` → deletedId
- `authorWithdrawn` → `true`
- `authorNickname` / `nickname` → `탈퇴한 사용자`
- `authorProfileImage` → `""`

**comments**

- `authorId` → deletedId
- `authorWithdrawn` → `true`
- `authorNickname` → `탈퇴한 사용자`
- `authorProfileImage` → `""`

**변경하지 않음:** content, likeCount, commentCount, likedBy, poll, pollVoters,
topicId, topicName, createdAt, **updatedAt**, tags 등.

---

## Topic usageCount 영향

`functions/topic_usage.js`의 `onPostUpdated`는 **`topicId`가 바뀔 때만**
usageCount를 조정합니다 (`beforeId === afterId`이면 early return).

이 migration은 `topicId`를 건드리지 않으므로 **usageCount는 변하지 않습니다.**
(업데이트 이벤트는 발생해도 no-op)

---

## Rules / ownership

Admin SDK로 쓰므로 live Rules와 무관합니다. Rules는 **수정하지 않습니다.**

migration 후:

```
resource.data.authorId == request.auth.uid
```

재가입 UID(`123`) ≠ `deleted_*` → 기존 글/댓글 **수정·삭제 permission-denied**.

---

## 설치

```bash
cd tools/withdrawn-content-migration
npm install
```

서비스 계정:

```bash
# Windows PowerShell
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\serviceAccount.json"

# bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
```

프로젝트 id 기본값: `truestory-9eb36`  
(`GCLOUD_PROJECT` / `FIREBASE_PROJECT_ID`로 덮어쓸 수 있음)

---

## 실행 명령

### 1) Dry-run (기본 · 먼저 실행)

```bash
npm run migrate:dry-run
# 동일: node migrate.js
```

- Firestore **쓰기 없음** (읽기만)
- UID별 preview + RE-REGISTERED 강조
- `withdrawn_content_migration_preview_YYYY-MM-DD_HHMMSS.json` 저장

### 2) Apply (명시적 플래그 필수)

```bash
npm run migrate:apply
# 동일: node migrate.js --apply
```

`node migrate.js`만으로는 **절대 write하지 않습니다.**

Apply 전 dry-run JSON을 검토하세요.

---

## Dry-run 출력 예시

```
[migrate] mode=DRY-RUN
[migrate] Firestore will NOT be modified.

=== Withdrawn content migration preview ===

UID: 123
users/123 exists: true
→ RE-REGISTERED (withdrawn content still points at live uid)
deletedId: deleted_abc...

posts:
  3 document(s)

comments:
  5 document(s)

--------------------------------

Stats:
  legacyWithdrawnPosts: ...
  legacyWithdrawnComments: ...
  reRegisteredUids: ...
  orphanUids: ...

[dry-run] No writes.
```

---

## 재실행 안전성 (idempotent)

1차 apply:

```
authorId=123 → deleted_ABC
```

2차 dry-run / apply:

```
authorId=deleted_ABC → skip (already migrated)
```

UID 단위로 posts→comments를 처리합니다.  
중간에 실패한 UID는 다음 apply에서 **남은** `authorId==legacyUid` 문서만
새 deletedId로 이어서 처리합니다.

---

## 검증 시나리오 (apply 후 수동)

전제:

- `users/123` 존재 (재가입, nickname=진)
- legacy post: `authorId=123`, `authorWithdrawn=true`

apply 후:

1. 해당 post: `authorId=deleted_*`, `authorWithdrawn=true`, 화면 「탈퇴한 사용자」
2. UID 123으로 해당 post **수정/삭제** → `permission-denied`
3. UID 123으로 **새** post 작성 → `authorId=123`, 표시 「진」
4. likeCount / commentCount / poll / topicId **불변**

---

## 예상 비용 (대략)

| 작업 | 규모 |
|------|------|
| Read posts | `authorWithdrawn==true` post 수 (페이지 300) |
| Read comments | `authorWithdrawn==true` comment 수 (collectionGroup) |
| Read users | unique legacy UID 수 (`getAll`) |
| Write (--apply) | legacy post + comment 수 (batch 400, identity만) |

인덱스: `authorWithdrawn` + `__name__` 복합 인덱스가 필요하면  
콘솔 링크가 에러에 표시됩니다. (posts / collectionGroup comments)

---

## 권장 순서

1. `withdrawAccount` CF 배포 (신규 탈퇴부터 deleted_* 사용)
2. `npm run migrate:dry-run` → preview JSON 검토 (특히 RE-REGISTERED)
3. `npm run migrate:apply`
4. `npm run migrate:dry-run` → `legacyWithdrawnPosts/Comments == 0` 확인
5. 기기에서 재가입 ownership / 닉네임 시나리오 확인

---

## 배포 / 앱 코드

이 폴더만 사용합니다.  
`firebase deploy`, Rules, Flutter, Functions 변경과 무관합니다.
