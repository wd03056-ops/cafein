# CAFEIN Firestore Screenshot Seed

Play Store 스크린샷용 **수동** Firestore 시드입니다.  
Flutter 앱에는 연결되지 않으며, 앱 실행 시 자동으로 데이터를 만들지 않습니다.

검색은 Firestore `posts`만 사용합니다. 이 시드 도구와 앱 검색 코드는 연결되어 있지 않습니다.

---

## 코드가 기대하는 Firestore 구조 (요약)

| 경로 | 용도 |
|------|------|
| `topics/{topicId}` | `name`, `nameKey`, `usageCount`, `createdAt`, `updatedAt` |
| `topic_names/{nameKey}` | `topicId`, `name`, `updatedAt` (이름 → id) |
| `posts/{postId}` | 본문·메타·`topicId`/`topicName`·임베디드 `poll`·`likeCount`/`commentCount` |
| `posts/{postId}/comments/{commentId}` | 댓글 (상위 `commentCount`와 동기화) |

- **게시글 제목(`title`) 없음** — `content`만 사용
- **soft delete 없음** — 시드 삭제는 hard delete
- **비슷한 글:** `posts.where(topicId == …).orderBy(createdAt desc)`
- **홈 피드:** `posts.orderBy(createdAt desc).limit(30)`
- Poll 옵션 카운트 필드명: **`voteCount`**

시드 문서는 모두 `seedTag: "cafein_play_screenshot"` + `screenshot_*` id를 가집니다.

---

## 생성 수량

| 종류 | 수 |
|------|----|
| Topic | **8** |
| Post | **24** |
| Comment | **59** |
| Poll (게시글에 임베디드) | **6** |

---

## topicId 연결 (비슷한 글)

각 주제당 게시글 **3개** → 상세에서 “비슷한 글” 표시 가능.

```
screenshot_topic_jinsang   (진상손님)
  ├─ screenshot_post_002
  ├─ screenshot_post_009
  └─ screenshot_post_010

screenshot_topic_weekly    (주휴수당)
  ├─ screenshot_post_003
  ├─ screenshot_post_011
  └─ screenshot_post_012

screenshot_topic_close     (마감)
  ├─ screenshot_post_001
  ├─ screenshot_post_013
  └─ screenshot_post_014

screenshot_topic_pay       (급여)
  ├─ screenshot_post_006
  ├─ screenshot_post_015
  └─ screenshot_post_016

screenshot_topic_hardship  (알바고충)
  ├─ screenshot_post_005
  ├─ screenshot_post_017
  └─ screenshot_post_018

screenshot_topic_open      (오픈)
  ├─ screenshot_post_004
  ├─ screenshot_post_019
  └─ screenshot_post_020

screenshot_topic_quit      (퇴사)
  ├─ screenshot_post_008
  ├─ screenshot_post_021
  └─ screenshot_post_022

screenshot_topic_tips      (카페꿀팁)
  ├─ screenshot_post_007
  ├─ screenshot_post_023
  └─ screenshot_post_024
```

Poll 게시글: `001`, `003`, `007`, `010`, `016`, `018`

---

## 사전 준비

1. Firebase 프로젝트 **서비스 계정 JSON** 발급  
   (Console → Project settings → Service accounts → Generate new private key)
2. 이 JSON은 **커밋하지 말 것**

```powershell
cd tools\firestore-screenshot-seed
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\serviceAccount.json"
# 선택: $env:FIREBASE_PROJECT_ID = "truestory-9eb36"
```

기본 projectId는 `firebase.json`과 동일하게 `truestory-9eb36`입니다.

---

## 시드 실행

```powershell
npm run seed
```

성공 시 `MANIFEST.generated.json`이 생성됩니다.

### topic_names 충돌

같은 한글 주제명이 운영에 이미 있으면, **운영 `topic_names`는 덮어쓰지 않습니다.**  
게시글은 여전히 `screenshot_topic_*` id로 연결되어 홈/비슷한 글/주제 피드(아이디 기준)는 동작합니다.

---

## 삭제 방법

```powershell
npm run delete
```

삭제 대상:

- 모든 `screenshot_post_*` (+ 하위 `comments`)
- 모든 `screenshot_topic_*`
- `seedTag == cafein_play_screenshot` 인 `topic_names` / leftover posts·topics  
- 운영 `topic_names`는 screenshot topic을 가리킬 때만 삭제

콘솔에서 수동 삭제할 때: 문서 필드 `seedTag` = `cafein_play_screenshot` 로 필터하거나 아래 ID 목록을 사용하세요.

---

## 생성한 문서 ID 목록

### Topics (`topics/{id}`)

- `screenshot_topic_jinsang`
- `screenshot_topic_weekly`
- `screenshot_topic_close`
- `screenshot_topic_pay`
- `screenshot_topic_hardship`
- `screenshot_topic_open`
- `screenshot_topic_quit`
- `screenshot_topic_tips`

### Posts (`posts/{id}`)

`screenshot_post_001` … `screenshot_post_024`

### Comments (`posts/{postId}/comments/{id}`)

형식: `screenshot_cmt_{post번호}_{n}`  
예: `screenshot_cmt_001_1`, `screenshot_cmt_002_4`, …

전체 목록은 `data.js`의 `POSTS[].comments` 또는 시드 후 `MANIFEST.generated.json`을 참고하세요.

### Fake authors (문서 미생성, post/comment 필드만)

- `screenshot_author_01` … `screenshot_author_08`

---

## 스크린샷 체크리스트

1. 앱 재시작 후 **홈** — 최신순으로 마감/진상/주휴/오픈/고충/급여/팁/퇴사 믹스
2. **투표 글** 열어 퍼센트·총 참여 수 확인
3. **댓글** 목록·배지(`cafeType`/`experience`) 확인
4. 같은 주제 글에서 **비슷한 글** 섹션 확인
5. 주제 필 탭 → **주제 피드**에 글 3개

촬영 후 반드시 `npm run delete`로 정리하세요.
