# CAFEIN Legal / Organization Site

Google Play 제출용 **정적** 사이트입니다.

- **조직 웹사이트** (`/`) — Play Console 조직 계정용 공식 소개
- **개인정보처리방침** (`/privacy/`)
- **이용약관** (`/terms/`)
- **계정 삭제 요청** (`/account-deletion/`) — Play 계정 삭제 URL용

Flutter CAFEIN 앱과 **완전히 별개**이며, 백엔드·DB·계정 삭제 API는 없습니다.

## 페이지

| 경로 | 내용 |
|------|------|
| `/` | CAFEIN 공식 소개 (조직 웹사이트) |
| `/privacy/` | 개인정보처리방침 |
| `/terms/` | 이용약관 |
| `/account-deletion/` | 계정 삭제 요청 안내 |

## 로컬에서 실행

이 폴더(`cafein-legal`)를 문서 루트로 정적 서버를 띄웁니다.

```bash
cd cafein-legal
npx --yes serve .
```

브라우저에서 확인:

- http://localhost:3000/
- http://localhost:3000/privacy/
- http://localhost:3000/terms/
- http://localhost:3000/account-deletion/

Python이 있다면:

```bash
cd cafein-legal
python -m http.server 8080
```

- http://localhost:8080/
- http://localhost:8080/privacy/
- http://localhost:8080/terms/
- http://localhost:8080/account-deletion/

빌드 단계 없음 (정적 HTML). `npx serve`로 렌더링·링크만 확인하면 됩니다.

## Vercel 배포

1. [Vercel](https://vercel.com)에 로그인합니다.
2. **Add New Project** → 이 `cafein-legal` 폴더만 배포합니다.
   - Git에 올린 뒤 Root Directory를 `cafein-legal`로 지정하거나
   - CLI: `cd cafein-legal && npx vercel`
3. Framework Preset: **Other** (정적 파일)
4. Build Command: 비움 / Output: `.` (기본)

배포 후 확인 URL (예: 기존 배포 `cafein-five.vercel.app`):

- `https://cafein-five.vercel.app/` — **조직 웹사이트**
- `https://cafein-five.vercel.app/privacy/`
- `https://cafein-five.vercel.app/terms/`
- `https://cafein-five.vercel.app/account-deletion/` — **계정 삭제 URL**

> `/privacy`와 `/privacy/` 모두 동작하도록 폴더형 `index.html`을 사용했습니다.  
> `vercel.json`의 `cleanUrls` / `trailingSlash` 설정을 유지합니다.

## 운영 정보

사이트 전체에 적용된 운영 연락처:

| 항목 | 값 |
|------|-----|
| 조직명 | 백손 |
| 대표/운영자 | 백재윤 |
| 문의 이메일 | `baekson777@gmail.com` |

메인(`/`), 계정 삭제(`/account-deletion/`), 개인정보처리방침(`/privacy/`),
이용약관(`/terms/`)의 표시·mailto가 위 이메일로 통일되어 있습니다.

## 법률·운영 검토가 필요한 부분

각 법률 페이지의 **TODO** 박스(있는 경우):

- 운영 주체 / 사업자 정보 / 개인정보 보호책임자
- 개인정보 보관 기간(법령 근거)
- 처리 위탁·국외 이전(Firebase/카카오 리전 등)
- UGC 라이선스·면책·제재 단계의 법적 표현

본 문서는 초안이며 법률 자문이 아닙니다.

## Google Play Console에 넣을 URL

배포 후:

1. **조직 웹사이트** → `/` (예: `https://cafein-five.vercel.app/`)
2. **개인정보처리방침 URL** → `/privacy/`
3. **계정 삭제 URL** → `/account-deletion/`
4. (필요 시) 이용약관 → `/terms/`

앱 설정 화면의 링크를 이 사이트로 바꾸려면 Flutter 앱에서 별도 작업이 필요합니다.
이 프로젝트만으로는 앱을 수정하지 않습니다.
