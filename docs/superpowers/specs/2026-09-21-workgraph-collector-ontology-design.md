# WorkGraph 설계 — 수집 · 온톨로지 저장 · 그래프 시각화

- 작성일: 2026-09-21
- 범위: macOS 백그라운드 앱 1차 구현 (수집 → L0 저장 → LLM 온톨로지화 → 그래프 저장 → 옵시디언식 시각화)
- 범위 밖: 보고서, 재개, 이탈 알림, 기억 기반 검색, export, SOP, Windows
- `WorkGraph`는 임시 작업명. 서비스명 정해지면 교체

## 1. 한 줄 요약

- 백그라운드에서 "지금 뭘 보고 있나"를 계속 기록하고
- 5분마다 LLM이 한 번 읽어서 "이건 어떤 업무고, 뭐랑 관련 있나"만 뽑아 그래프에 upsert
- 앱을 열면 옵시디언 그래프 뷰처럼 보인다

## 2. 기술 선택

| 항목 | 선택 | 이유 |
|---|---|---|
| 언어/UI | Swift, SwiftUI + AppKit | 수집 API가 전부 Apple 프레임워크 |
| 빌드 | SwiftPM + `scripts/make-app.sh` | Xcode 없이 CLI로 빌드·테스트, Xcode에서 Package.swift 열어도 됨 |
| 저장 | SQLite (GRDB), 파일 1개, WAL | L0와 그래프를 한 트랜잭션으로 묶음 |
| 그래프 DB | SQLite 프로퍼티 그래프 (`nodes` / `edges` + JSON 속성 + 재귀 CTE) | 아래 2.1 |
| LLM | 앱 안에서 ChatGPT 로그인 후 Codex 백엔드 직접 호출 (기본 모델 `gpt-5.6-luna`). 대안: OpenAI 호환 서버 | 프록시 불필요. 함수 호출로 구조화 출력. 11절 |
| 시각화 | WKWebView + force-graph (번들, 오프라인) | 옵시디언 그래프 뷰와 같은 d3-force 계열 |

### 2.1 그래프 DB 선정

후보 비교:

| | SQLite 그래프 | LadybugDB (Kùzu 포크) | Kùzu | Neo4j |
|---|---|---|---|---|
| 임베디드 | O | O | O | X (JVM 서버) |
| Swift에서 사용 | GRDB, 안정적 | 패키지 있음. C++ 수백 파일 직접 컴파일 + 사전 스크립트 필요 | 2025-10 개발 중단·아카이브 | 드라이버 없음 |
| 스키마 | 자유 (라벨·속성 추가에 DDL 불필요) | 노드/관계 테이블 선언 필수, 다중 라벨 불가 | 동일 | 자유 |
| L0와 원자적 커밋 | O (같은 파일) | X | X | X |
| 동시 접근 | WAL로 읽기 동시 가능 (DB 브라우저로 바로 열어봄) | 쓰기 프로세스 1개만 | 동일 | O |
| 가변 길이 경로 | 재귀 CTE | Cypher `[*1..3]` | 동일 | 동일 |

결정: **SQLite 프로퍼티 그래프**.
- 규모가 작다 (1년 써도 노드 10만 미만). 성능은 어느 쪽이든 문제없음
- 우리 장점은 "스키마를 자주 안 바꿔도 된다"인데, Kùzu 계열은 관계 타입마다 DDL이 필요해서 그 장점이 사라짐
- "밀린 이벤트 재처리해도 중복 없음"을 DB 트랜잭션으로 보장할 수 있음
- 대신: Cypher를 못 씀 → `CypherExporter`로 같은 그래프를 Neo4j Desktop에 올려 발표·탐색용으로 병행
- 교체 가능성: `GraphStore` 프로토콜 뒤에 둠. 나중에 Ladybug 백엔드를 끼울 수 있음

## 3. 구조

```
WorkGraph/
  Package.swift
  scripts/make-app.sh            빌드 → .app 번들 → 서명
  Sources/
    WorkGraphCore/               순수 로직 (AppKit 없음, 테스트 대상)
      Models/ Storage/ Ontology/ LLM/ Export/
    WorkGraphCollectors/         macOS 수집기 (AX, ScreenCaptureKit, Vision, FSEvents)
    WorkGraphApp/                메뉴바 앱 + 그래프 창
      Resources/graph/           index.html, graph.js, style.css, vendor/force-graph.min.js
    wgctl/                       개발용 CLI (데모 시드, 배치 1회, 그래프 export, 통계)
  Tests/WorkGraphCoreTests/
```

데이터 위치: `~/Library/Application Support/WorkGraph/` (`workgraph.sqlite`, `captures/YYYY-MM-DD/*.jpg`)

## 4. 수집 (L0)

무엇을, 언제:

| 소스 | API | 권한 | 시점 |
|---|---|---|---|
| 앱 전환 | NSWorkspace 알림 | 없음 | 즉시 |
| 창 제목 · URL · 문서 경로 | 접근성 API (AXTitle, AXURL, AXDocument) | 손쉬운 사용 | 앱 전환 시 + 3초 폴링 |
| 화면 텍스트 | 접근성 트리 순회 (깊이·노드 수·시간 예산) | 손쉬운 사용 | 컨텍스트가 바뀌었을 때 |
| 스크린샷 | ScreenCaptureKit `SCScreenshotManager` | 화면 기록 | 컨텍스트 변경 1.5초 후 + 60초 주기(내용 바뀐 경우만), 최소 간격 10초 |
| OCR | Vision (한국어+영어) | 화면 기록 | 접근성 텍스트가 거의 없을 때만 |
| 파일 생성 | FSEvents (`~/Downloads`) + `kMDItemWhereFroms`(다운로드 출처) | 폴더 접근 | 이벤트 |
| 유휴 | 마지막 입력 후 경과 시간 | 없음 | 5초 폴링, 120초 넘으면 유휴 |

규칙:
- 같은 (앱, 창 제목, URL)이 이어지면 60초마다 생존 신호 행만 남긴다. 체류시간은 다음 행과의 시각 차이로 계산 (간격이 90초를 넘으면 앱이 꺼져 있던 것으로 보고 자른다)
- 제목만 계속 바뀌는 창(터미널 스피너, 재생 시간)은 10초에 한 번만 새 행
- 텍스트는 해시로 중복 제거해서 `text_snapshots`에 한 번만 저장
- 제외: 비밀번호 관리자 등 기본 제외 앱, 보안 입력 필드, 시크릿/프라이빗 창, 사용자 지정 제외 앱
- 권한이 없으면 그 수집기만 꺼지고 나머지는 계속 돈다 (앱 이름만으로도 동작)
- 메뉴바에서 일시정지 가능

테이블:
- `observations(id, ts, trigger, app_bundle, app_name, window_title, url, doc_path, text_id, screenshot_path, batch_id)`
- `text_snapshots(id, hash UNIQUE, source ax|ocr, text)`
- `file_events(id, ts, path, kind, origin_url, observation_id)`
- `idle_spans(id, start_ts, end_ts)`
- `batches(id, started_at, finished_at, from_obs, to_obs, status, model, tokens, error, raw_response)`

## 5. 온톨로지

### 5.1 클래스 층 (T-Box) — 코드에 정의, 그래프에 노드로 시드

```
TaskType      정보수집(문헌조사, 시장조사) / 산출물작성(문서작성, 발표자료, 코드작성)
              / 커뮤니케이션(회의, 메신저대응) / 학습(강의수강, 복습) / 반복작업(데이터정리) / 기타
ResourceType  참고자료(Documentation, QnA, Paper, Video, AIChat, WebPage)
              / 산출물(CodeFile, Note, Document, Design)
              / Preview / Message
그 외 클래스   Task, Session, App, Topic, Problem, Project, File, Folder, LaterItem
```

### 5.2 인스턴스 층 (A-Box)

엣지:
```
(Session)-[PART_OF]->(Task)-[INSTANCE_OF]->(TaskType)-[SUBCLASS_OF]->(TaskType)
(Session)-[USED {seconds}]->(App)
(Session)-[TOUCHED {dwell, count}]->(Resource)-[INSTANCE_OF]->(ResourceType)
(Task)-[ABOUT]->(Topic)      (Resource)-[BELONGS_TO]->(Project)
(Session)-[HIT]->(Problem)-[RESOLVED_BY]->(Resource)
(Session)-[SWITCHED_TO {kind: planned|drift|blocked}]->(Session)
(LaterItem)-[FOR]->(Task)    (File)-[CREATED_DURING]->(Session)   (File)-[DERIVED_FROM]->(Resource)
```

테이블:
- `nodes(id, label, key, subtype, title, props JSON, created_at, updated_at, UNIQUE(label, key))`
- `edges(id, src, dst, type, props JSON, weight, first_at, last_at, UNIQUE(src, dst, type))`
- upsert = `INSERT … ON CONFLICT DO UPDATE` (Cypher의 MERGE와 같은 역할). 같은 배치를 두 번 돌려도 결과가 같다

### 5.3 예시 (프론트 개발 90분)

| 원시 행 | 규칙 분류 | key |
|---|---|---|
| Cursor — TaskCard.tsx | CodeFile | `file:~/proj/dashboard/src/components/TaskCard.tsx` |
| Chrome — ui.shadcn.com/docs/components/card | Documentation | `https://ui.shadcn.com/docs/components/card` |
| Chrome — localhost:3000 | Preview | `local:3000/` |
| Chrome — stackoverflow "React key prop" | QnA | `https://stackoverflow.com/questions/…` |
| Slack — 디자인팀 | Message | (App만 기록) |

LLM이 채우는 것: 이 행들이 "대시보드 카드 UI 구현"이라는 Task 하나라는 것, 주제(React, shadcn/ui), key prop 경고가 SO 글로 해결됐다는 관계, Slack의 "간격 16px"이 나중에 할 일이라는 것.

## 6. 쓰기 경로

1. 규칙 (LLM 없음): uri 정규화 → ResourceType 분류 → Project 추정(코드 파일의 상위 `package.json`, `.git` 등)
2. 압축: 연속된 같은 컨텍스트를 한 행으로 합치고 체류시간 계산. 2초 미만은 버림
3. 배치 조건: 처리 안 된 행이 있고 (가장 오래된 행이 5분 경과 **또는** 수동 실행). 한 번에 최대 30분 · 150행. 지금 보고 있는 마지막 행은 체류시간이 아직 안 정해졌으므로 다음 배치로 넘긴다
4. LLM 호출 1회: 입력 = 열린 Task 최대 5개 + 클래스 목록 + 압축된 행. 출력 = 함수 호출 `record_activity`의 JSON
   ```json
   {"segments":[{"rows":[1,6],"task":{"match":"new","title":"대시보드 카드 UI 구현","task_type":"코드작성"},
     "summary":"TaskCard 구현, key prop 경고 해결","topics":["React","shadcn/ui"],
     "problems":[{"row":4,"kind":"build","message":"React key prop warning","resolved_by_row":5}],
     "later_items":[{"row":6,"text":"카드 간격 16px로 조정"}],"switch_kind":null}]}
   ```
5. 반영: 한 트랜잭션에서 노드·엣지 upsert + 해당 행에 `batch_id` 기록
   - 직전 Session과 Task가 같고 간격이 5분 미만이면 새 Session을 만들지 않고 이어 붙임
6. 실패: 행은 미처리로 남김. 1→2→4…최대 30분 간격으로 재시도. 수집은 멈추지 않음. 사용자에게 묻지 않음
   - 서버 다운·토큰 만료는 끝까지 기다린다. LLM 이 쓸 수 없는 답을 5번 연속 주는 구간만 건너뛴다
   - 작은 모델의 흔들림(segments 래퍼 누락, 중첩 값을 문자열로 감싸기)은 파서가 받아준다

## 7. 시각화

- 어두운 배경, 점 크기 = 연결 수, 색 = 라벨, 줌 인하면 라벨 표시
- 호버: 해당 노드와 이웃만 밝게, 나머지는 흐리게
- 클릭: 우측 패널에 속성·연결 목록, URL/파일 열기
- 필터: 라벨별 토글, 검색, 기간(오늘/7일/전체), "클래스 층 보기" 토글(기본 꺼짐 — 켜면 TaskType/ResourceType 허브가 보임)
- 로컬 그래프: 노드 선택 후 깊이 1~3
- Swift → JS: `window.WG.setGraph(json)`. JS → Swift: `open`, `refresh` 메시지만

## 8. 앱

- 메뉴바 상주 (Dock 아이콘 없음). 메뉴: 상태, 오늘 기록 수, 그래프 열기, 지금 정리, 일시정지, 종료
- 창 탭: 그래프 / 활동 로그(최근 행 + 배치 결과·에러) / 설정(권한 상태, LLM 주소·모델·연결 테스트, 수집 토글, 제외 앱)

## 9. 테스트

- 단위: uri 정규화, 규칙 분류, 압축, 그래프 upsert 멱등성·k-hop, LLM 응답 파싱(함수 호출/본문 JSON/코드펜스), 반영기(프론트 개발 시나리오 픽스처), 배치(성공·실패·재실행)
- 통합: `wgctl seed-demo` → `wgctl batch` (실제 LLM) → `wgctl export-graph` → 그래프 페이지를 헤드리스 브라우저로 렌더해 확인
- 앱: `.app` 빌드·실행 → observations 행이 쌓이는지 확인

## 10. 정해야 할 것

- [x] LLM 연결 → 앱 안 ChatGPT 로그인으로 해결 (11절). gpt-proxy 는 더 이상 필요 없음
- [ ] 팀원 계정에서 기기 코드 로그인이 켜져 있는지 확인
- [ ] 서비스명 · 번들 ID
- [ ] 스크린샷 보관 기간 (기본 7일)
- [ ] LLM에 화면 텍스트를 얼마나 보낼지 (기본: 체류 상위 행만 앞 300자)

## 11. LLM 연결: 앱 안 ChatGPT 로그인 (2026-09-21 추가)

왜:
- gpt-proxy 는 토큰이 주기적으로 죽었다. 원인은 같은 `auth.json` 을 Codex CLI 와 프록시가 나눠 쓴 것. refresh token 은 1회용이라 나중에 쓰는 쪽이 "이미 사용된 토큰"을 보내면 세션 전체가 무효가 된다 (Codex CLI 소스의 `refresh_token_reused`)
- 앱이 자기 로그인을 따로 가지면 이 문제가 구조적으로 없어지고, 도커·프록시 없이 앱만 설치하면 된다

어떻게 (규격은 공개된 Codex CLI `codex-rs/login` 과 동일):
1. `POST auth.openai.com/api/accounts/deviceauth/usercode` → 사용자 코드
2. 사용자가 `auth.openai.com/codex/device` 에서 코드 입력
3. `POST …/deviceauth/token` 을 승인될 때까지 반복 (403·404 = 아직, 15분 제한)
4. `POST …/oauth/token` 으로 코드 교환 → id / access / refresh token
5. 호출: `POST chatgpt.com/backend-api/codex/responses` (SSE). 강제 함수 호출로 `record_activity` 인자를 받는다
6. 모델 목록: `GET chatgpt.com/backend-api/codex/models?client_version=…` — 계정마다 다름 (`gpt-5.4-mini` 는 이 계정에서 거절됨)

결정:
- 기기 코드 방식만 구현. 브라우저 리다이렉트 방식은 1455 포트를 VS Code Codex 확장이 점유하는 환경이 있어 제외
- 토큰은 앱 전용 파일(600) + 프로세스 간 파일 잠금. 키체인은 CLI·앱이 같은 항목을 읽을 때 매번 허용 창이 떠서 프로토타입 단계에서는 보류
- 비공개 백엔드라 규격이 바뀔 수 있음 → `CodexResponsesClient` 한 파일에 격리. OpenAI 호환 방식은 그대로 유지

검증 (2026-09-21): 실제 인증 서버에서 코드 발급 확인. 실제 백엔드에 `gpt-5.6-luna` 로 데모 하루치 10배치 전부 성공 (배치당 4~11초, 합계 입력 13,098 / 출력 1,484 토큰). 코드 승인 → 토큰 교환 → 저장 구간은 사람이 브라우저에서 승인해야 해서 스텁 테스트로만 확인

## 12. 온보딩: 로그인해야 쓸 수 있다 (2026-09-22 추가)

- 단계: `login`(필수) → `permissions`(처음 한 번) → `ready`. 판단은 `AppPhase.decide(loggedIn:onboardingCompleted:)`
- `ready` 가 아니면 수집기도 배치도 돌지 않는다. 메뉴바에는 "시작하기"만, 창에는 탭 대신 온보딩이 보인다
- 로그아웃하면 `login` 으로 돌아가고 수집이 멈춘다. 다시 로그인하면 권한 단계는 건너뛴다
- 화면 기록 권한은 허용 후 재실행이 필요해서 온보딩에 "앱 다시 실행" 버튼을 둔다
- 중복 실행 방지: DB 옆 잠금 파일(`workgraph.sqlite.instance.lock`, flock). 같은 데이터로 두 번째 인스턴스가 뜨면 DB 를 열지 않고 안내만 띄운다
  - 계기: `.app` 과 터미널의 `swift run WorkGraphApp` 이 동시에 돌면서 같은 DB 에 기록하던 것을 실제로 겪음

## 13. 실사용에서 나온 보완 (2026-09-22)

- **업무 과분할**: 실제 50분 활동이 업무 16개로 쪼개짐 (0~2분짜리, "팀 채널 확인" 류 중복). 반영 직전에 `SegmentNormalizer` 를 둔다
  - 대상: 3분 미만 + 새 업무. 순서: 짧은 구간끼리 묶어 합이 3분 넘으면 승격 → 비슷한 기존 업무로 → 같은 업무 사이 끼어들기 흡수 → 공용 업무("자잘한 확인"/"짧은 딴짓")
  - 비슷함 = 업무 종류 0.25 + 제목 단어 0.30 + 주제 0.25 + 본 자료 0.35(없으면 쓴 앱 0.25). 기준 0.5
  - 배치에 구간이 하나뿐이면 공용 업무로 보내지 않는다 (막 시작한 업무일 수 있음)
  - 프롬프트도 기존 업무 재사용을 우선하도록 강화, 후보 업무 5 → 8개
  - 결과: 같은 260행이 업무 5개 · 세션 7개
- **그래프는 파생 데이터**: `wgctl rebuild-graph` 로 원시 행에서 언제든 다시 만든다. 로직을 바꿀 때마다 과거 데이터에 다시 적용할 수 있는 것이 L0/그래프 분리의 이점
- **앱을 찾는 경로**: 메뉴바 아이콘이 노치 뒤로 가려지는 것을 실제로 겪음 → Dock 아이콘 기본 표시, Dock 클릭·재실행 시 창 열기, 로그인 항목 실행만 조용히
- **사용량**: `GET chatgpt.com/backend-api/wham/usage` (Codex CLI `/status` 와 같은 출처). 설정 탭과 `wgctl codex-usage`
- **화면 문구**: 구현 설명은 화면에 쓰지 않는다. 남기는 것은 "무엇이 ChatGPT 로 전송되는지" 한 줄

## 14. 온톨로지 층 보강: 관계 스키마 + 표준 어휘 (2026-09-22)

계기: "우리 서비스가 온톨로지를 쓰는 게 맞나"라는 질문. 답은 "가벼운 온톨로지(분류 체계 + 관계 스키마 + 인스턴스)"였고, 약한 부분 두 가지를 보강했다.

**1. 관계 스키마 (`RelationSchema.swift`)**
- 클래스 12개(`ClassSchema`): 라벨, 한국어 이름, 표준 상위 클래스, 뜻
- 관계 14개(`RelationSchema`): 허용되는 (출발, 도착) 쌍의 집합. `INSTANCE_OF` 는 Task→TaskType, Resource→ResourceType 만, `BELONGS_TO` 는 Resource→Project, File→Folder 만
- 저장소(`GraphTx.upsertEdge`)가 검증: 모르는 관계는 `unknownRelation`, 방향이 틀리면 `invalidRelation` 으로 거부. 에러에 허용 쌍이 같이 나온다
- 이로써 클래스 층에 "무엇이 있는가"뿐 아니라 "무엇이 무엇과 어떻게 연결될 수 있는가"가 들어가고, 그래프가 정의된 어휘 밖으로 벗어날 수 없다

**2. 표준 어휘 매핑 + RDF 내보내기 (`RDFExporter.swift`, `wgctl export-rdf`)**

| 우리 | 표준 |
|---|---|
| Session, Task | prov:Activity (Task 는 dcterms:isPartOf 로 세션을 묶음) |
| Resource, Problem, LaterItem, File | prov:Entity |
| App | prov:SoftwareAgent |
| Project, Folder | prov:Collection (prov:hadMember) |
| Topic | skos:Concept (dcterms:subject) |
| TaskType / ResourceType 계층 | rdfs:Class + rdfs:subClassOf (최상위는 wg:Task / wg:Resource 의 하위) |
| INSTANCE_OF | rdf:type |
| TOUCHED (체류 초) | prov:used + prov:qualifiedUsage [prov:Usage; prov:entity; prov:atTime; wg:dwellSeconds] |
| USED (초) | prov:wasAssociatedWith + prov:qualifiedAssociation |
| HIT, CREATED_DURING | prov:wasGeneratedBy |
| DERIVED_FROM | prov:wasDerivedFrom |
| RESOLVED_BY | wg:resolvedBy ⊂ prov:wasInfluencedBy (정의역 Problem, 치역 Resource) |
| SWITCHED_TO (kind) | wg:switchedTo + 도착 세션의 wg:arrivedBy |

- IRI: 어휘 `urn:workgraph:ontology:`, 인스턴스 `urn:workgraph:node:n<id>`. 한글 클래스명은 Turtle 로컬 이름으로 그대로 씀 (`wg:TaskType_코드작성`)
- 검증(2026-09-22): 실제 그래프(노드 145, 엣지 265)를 내보내 rdflib 7.6 으로 파싱(트리플 1,488), SPARQL 로 (a) prov: 어휘만으로 활동·자료·체류시간 조회, (b) `rdfs:subClassOf*` 로 참고자료/산출물 상위 종류 집계(918초 / 175초), (c) wg 클래스가 전부 W3C 표준 클래스의 하위임을 확인

**여전히 아닌 것**: 추론기(OWL reasoner)는 없다. 계층 집계는 질의 시 `subClassOf*` 로 한다. 심사 답변: "분류 체계와 관계 스키마를 정의하고 인스턴스를 연결한 지식 그래프. PROV-O 로 매핑되어 표준 도구와 호환. 형식 추론기는 미사용."

## 15. AI 대화 기록 활용 · 제외 앱 설정 (2026-09-22)

**AI 코딩 도구 대화 (사용자 제안)**
- 소스: Claude Code 세션 JSONL(`type=user`, `isSidechain=false`, 텍스트 파트만), Codex CLI `history.jsonl`(실제 입력한 프롬프트) + rollout 첫 줄 session_meta 의 cwd
- 저장: `chat_messages(ts, tool, session_id, cwd, text)` UNIQUE(tool, session_id, ts). 읽은 위치는 `chat_cursors(path, offset)`. 최초 24시간 백필
- 왜 관측 행에 안 섞고 따로 두나: 관측 행 사이에 끼우면 앞 행의 체류시간을 잘라 앱 시간 집계가 틀어진다. 대신 배치 때 창 안의 메시지를 세션별 **체류 0초 행**으로 합쳐 넣는다(`EventCompressor.merge`). 시간 집계 불변, LLM 은 `text:` 로 메시지를 본다
- 그래프: `Resource(subtype AIChat, key chat:<tool>:<session>)`, 세션이 TOUCHED(가중치 0), cwd 의 프로젝트 루트(없으면 cwd)에 BELONGS_TO. 도구는 App 노드로 만들지 않는다
- 프롬프트: AIChat 행은 "사용자가 자기 말로 밝힌 의도"이니 업무 제목·주제의 최우선 근거로 쓰고 같은 프로젝트 작업과 한 구간에 두라고 지시
- 검증: 실제 Claude Code 세션 26건 자동 수집

**제외 앱**
- 설정 화면에서 편집(실행 중인 앱 선택 / .app 파일 선택 / 기본값 복원). 저장 즉시 수집기에 반영
- 변경: 제외 앱 행에 앱 이름·번들을 남긴다(전에는 "제외된 앱"으로만). 창 제목·URL·텍스트·스크린샷은 여전히 기록하지 않음. 이유: 사용자가 어떤 앱이 제외됐는지 알 수 있어야 설정을 고칠 수 있다. WorkGraph 자신이 제외되는 것도 이제 이름으로 보인다
