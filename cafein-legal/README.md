# CAFEIN Legal / Policy Site

Google Play 제출용 **정적** 정책·계정 삭제 안내 사이트입니다.  
Flutter CAFEIN 앱과 **완전히 별개**이며, 백엔드·DB·계정 삭제 API는 없습니다.

## 페이지

| 경로 | 내용 |
|------|------|
| `/` | 계정 삭제 요청 안내 |
| `/privacy/` | 개인정보처리방침 |
| `/terms/` | 이용약관 |

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

Python이 있다면:

```bash
cd cafein-legal
python -m http.server 8080
```

- http://localhost:8080/
- http://localhost:8080/privacy/
- http://localhost:8080/terms/

## Vercel 배포

1. [Vercel](https://vercel.com)에 로그인합니다.
2. **Add New Project** → 이 `cafein-legal` 폴더만 배포합니다.
   - Git에 올린 뒤 Root Directory를 `cafein-legal`로 지정하거나
   - CLI: `cd cafein-legal && npx vercel`
3. Framework Preset: **Other** (정적 파일)
4. Build Command: 비움 / Output: `.` (기본)

배포 후 확인 URL (도메인은 Vercel이 부여):

- `https://<your-project>.vercel.app/`
- `https://<your-project>.vercel.app/privacy/`
- `https://<your-project>.vercel.app/terms/`

> `/privacy`와 `/privacy/` 모두 동작하도록 폴더형 `index.html`을 사용했습니다.

## 운영 문의 이메일

현재 사이트에 적용된 주소: `wd03056@gmail.com`  
변경 시 `index.html`, `privacy/index.html`, `terms/index.html`의 mailto 링크를 함께 수정하세요.

## 법률·운영 검토가 필요한 부분

각 페이지의 **TODO** 박스:

- 운영 주체 / 사업자 정보 / 개인정보 보호책임자
- 개인정보 보관 기간(법령 근거)
- 처리 위탁·국외 이전(Firebase/카카오 리전 등)
- UGC 라이선스·면책·제재 단계의 법적 표현
- Google Play Console에 등록할 최종 URL

본 문서는 초안이며 법률 자문이 아닙니다.

## Google Play Console에 넣을 URL

배포 후:

1. **계정 삭제 URL** → `/` (계정 삭제 요청 페이지)
2. **개인정보처리방침 URL** → `/privacy/`
3. (필요 시) 이용약관 → `/terms/`

앱 설정 화면의 Notion 링크를 이 사이트로 바꾸려면 Flutter 앱에서 별도 작업이 필요합니다. 이 프로젝트만으로는 앱을 수정하지 않습니다.
