# CAFEIN Topic usageCount Migration (1회성 · 수동)

Firestore `topics/{topicId}.usageCount`를 **현재 살아있는 `posts`의 `topicId` 개수**로 재설정하는 도구입니다.

- Flutter 앱과 연결되지 않습니다.
- Cloud Function으로 등록되지 않습니다.
- **기본은 dry-run**이며, `--apply` 없이 Firestore를 쓰지 않습니다.
- **posts / topic_usage_ledger / topic 문서 삭제·생성은 하지 않습니다.**

---

## 코드 기준 (확인됨)

| 항목 | 내용 |
|------|------|
| Count 기준 | `posts/{postId}.topicId` (문자열 doc id) |
| 사용 안 함 | `topicName`만으로 추정·집계하지 않음 |
| Soft delete | **없음** — `deletePost`는 hard delete. 존재하는 post만 count |
| Topic 스키마 | `name`, `nameKey`, `usageCount`, `createdAt`, `updatedAt` |
| Ledger | `topic_usage_ledger/{postId}` — **이 스크립트는 수정하지 않음** |

Trigger (`functions/topic_usage.js`)는 post create/update/delete 시에만 count를 바꿉니다.  
이 migration은 **topics만 update**하므로 post trigger가 재실행되지 않습니다.

---

## 설치

```bash
cd tools/topic-usage-migration
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

### 1) Dry-run (기본 · 권장 먼저)

```bash
npm run migrate:dry-run
# 동일: node migrate.js
```

- Firestore **쓰기 없음**
- mismatch / orphan / legacy 목록 출력
- `topic_usage_migration_preview_YYYY-MM-DD_HHMMSS.json` 저장

### 2) Verify

```bash
npm run migrate:verify
```

- dry-run과 동일하게 계산
- `mismatchCount !== 0`이면 exit code 1

### 3) Apply (명시적 플래그 필수)

```bash
npm run migrate:apply
# 동일: node migrate.js --apply
```

- **mismatch인 topics만** `usageCount = expected`, `updatedAt = serverTimestamp()`
- `usageCount = expected`로 **절대값 설정** (increment 아님 → 재실행 안전)
- orphan topicId에 대해 topic 문서를 **생성하지 않음**
- ledger **미변경**

`node migrate.js`만 실행하면 apply되지 않습니다.

---

## 처리 규칙

### Count

```
expected[topicId] = count(posts where topicId == topicId)
```

모든 `topics/{id}`에 대해:

- post에 등장 → 그 개수
- post에 없음 → **0** (문서는 유지)

### Orphan topicId

`post.topicId`는 있는데 `topics/{id}`가 없으면:

- 리포트에만 출력
- **자동 생성하지 않음**

### Legacy (topicName only)

`topicId` 없고 `topicName`만 있으면:

- count에 **포함하지 않음**
- legacy 목록으로만 보고

### Soft-deleted

해당 필드/플래그 없음 → 제외 로직 불필요.

### topic_usage_ledger

이번 스크립트는 **건드리지 않습니다.**

이유:

- live post의 ledger를 전부 재작성하는 작업은 trigger 재배포·타이밍과 결합하면 위험
- count 정합만 먼저 맞추는 것이 목표

migration apply 후 update/delete trigger가 ledger와 어긋나면  
**별도 ledger reconciliation**이 필요할 수 있습니다.  
(예: live post마다 ledger.topicId = post.topicId, 삭제분은 cleared)

---

## 재실행 안전성

여러 번 `--apply`해도:

```
usageCount := expectedCount
```

이므로 두 번째 실행에서 delta=0이면 write 없음.

---

## 예상 비용 (대략)

| 작업 | 규모 |
|------|------|
| Read posts | 전체 post 수 (페이지 300, `select topicId,topicName`) |
| Read topics | 전체 topic 수 |
| Write topics | mismatch 개수만 (최대 batch 400) |

posts는 수정하지 않으므로 usage trigger는 발화하지 않습니다.

---

## 배포 / 앱 코드

이 폴더만 사용합니다.  
`firebase deploy`, Rules, Flutter, `functions/topic_usage.js` 변경과 무관합니다.

---

## 권장 순서

1. Functions의 topic usage 트랜잭션 수정분을 **배포** (A→B 버그 수정)
2. `npm run migrate:dry-run` → preview JSON 검토
3. `npm run migrate:apply`
4. `npm run migrate:verify` → mismatchCount=0
5. (선택) ledger reconciliation 별도 작업
