# 플러그인 설정

[README로 돌아가기](../README.md)

Sillog의 플러그인은 Gmail·Google Drive·GitHub·Notion의 자료를 검색하고 읽기 위한 계정 연결입니다. 메일 발송, 파일 수정, 저장소 변경은 지원하지 않습니다.

## 제공자와 사용자 역할

**앱 제공자**가 각 서비스에 OAuth 앱을 등록하고 클라이언트 ID를 설정합니다. **사용자**는 Sillog에서 설치할 플러그인을 고른 뒤 서비스의 로그인·권한 승인 화면만 거칩니다. 일반 사용자가 OAuth 앱을 직접 등록하는 방식이 아닙니다.

ChatGPT 플러그인 연결은 별개입니다. 해당 권한이나 토큰을 Sillog에 복사할 수 없습니다.

현재 설치·승인 UI, 토큰 저장·갱신, 검색·읽기 코드가 구현되어 있습니다. 공급자 등록 정보가 없어 **실제 로그인·비공개 자료 조회는 아직 검증하지 못했습니다.** 설정이 없는 플러그인은 준비되지 않았다는 안내를 표시하고 설치 완료로 처리하지 않습니다.

## Google: Gmail · Google Drive

- [데스크톱 앱용 OAuth 클라이언트](https://developers.google.com/identity/protocols/oauth2/native-app)를 등록합니다.
- Gmail·Drive API를 사용할 수 있도록 프로젝트를 설정합니다. 현재 접근 범위는 Gmail·Drive 읽기 전용입니다.
- 빌드할 때 `WORKGRAPH_GOOGLE_CLIENT_ID`를 설정합니다.
- 사용자는 필요한 Gmail·Drive 항목만 고르고 Google에서 승인합니다. 선택한 항목에 해당하는 권한을 요청합니다.
- 로컬 콜백은 `http://127.0.0.1:8765/callback`입니다. 승인 중 앱이 실행되고 포트를 사용할 수 있어야 합니다.

```bash
WORKGRAPH_GOOGLE_CLIENT_ID="등록한 클라이언트 ID" ./scripts/make-app.sh
```

## GitHub

- [GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)을 등록하고 디바이스 인증을 활성화합니다.
- 저장소 **Contents**, **Pull requests** 접근을 읽기 전용으로 설정합니다.
- 빌드할 때 `WORKGRAPH_GITHUB_CLIENT_ID`를 설정합니다.
- 사용자는 Sillog에 표시된 코드를 GitHub 승인 페이지에 입력합니다. 로컬 콜백 포트는 사용하지 않습니다.

```bash
WORKGRAPH_GITHUB_CLIENT_ID="등록한 클라이언트 ID" ./scripts/make-app.sh
```

만료 토큰 자동 갱신에는 앱 비밀키를 안전하게 처리하는 별도 서버가 필요합니다. 서버가 없는 현재 구성에서는 토큰이 만료되면 다시 연결해야 합니다.

## Notion

- [공개 통합](https://developers.notion.com/guides/get-started/authorization)을 등록합니다.
- 리다이렉트 URI를 `http://127.0.0.1:8765/callback`으로 설정합니다.
- 빌드할 때 `WORKGRAPH_NOTION_CLIENT_ID`를 설정합니다.
- 토큰 교환 비밀키는 개발 환경의 `WORKGRAPH_NOTION_CLIENT_SECRET` 또는 기존 개발용 Keychain 설정에서 읽습니다. 비밀키를 Info.plist나 저장소에 넣지 마세요.
- 사용자가 통합에 공유한 페이지만 검색하고 읽을 수 있습니다.

```bash
WORKGRAPH_NOTION_CLIENT_ID="등록한 클라이언트 ID" ./scripts/make-app.sh
```

**배포 전에는 서버 측 토큰 교환을 추가해야 합니다.** 데스크톱 앱에 비밀키를 포함하면 안전하게 보호할 수 없으며, 개발용 비밀키 환경변수만으로 일반 사용자 배포가 완성되는 것은 아닙니다.

## 인증 정보와 배포

- 공개 클라이언트 ID만 빌드 시 앱 번들에 넣습니다. 각 변수는 함께 설정할 수 있습니다.
- 승인 후 받은 플러그인 토큰은 macOS Keychain에 저장합니다.
- 계정 연결·해제 상태는 플러그인 화면에서 확인합니다. 연결한 서비스도 대화의 자료 설정에서 사용을 허용해야 조회합니다.
- 공급자 앱 등록과 필요한 검증·권한 설정이 끝나기 전에는 실제 연결을 사용할 수 없습니다.
- Google·Notion은 승인 중 로컬 포트 8765를 사용합니다. 같은 포트를 쓰는 다른 실행이 있으면 먼저 종료해야 합니다.
