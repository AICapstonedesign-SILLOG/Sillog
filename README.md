# WorkGraph

PC 활동을 백그라운드에서 기록하고, 5분마다 LLM 이 한 번 읽어 온톨로지 그래프로 정리한 뒤, 옵시디언 그래프 뷰처럼 보여주는 macOS 메뉴바 앱. (`WorkGraph` 는 임시 이름)

```
수집 (3초마다 앱·창·URL 확인)  →  observations (SQLite, 원시 로그)
        ↓ 5분 배치, LLM 호출 1회
nodes / edges (같은 SQLite 파일, 프로퍼티 그래프)  →  그래프 뷰 (WKWebView + force-graph)
```

## 빠른 시작

```bash
./scripts/make-app.sh          # release 빌드 → build/WorkGraph.app → 서명
open build/WorkGraph.app
```

- 처음 실행하면 온보딩이 뜬다. **ChatGPT 로그인을 해야 쓸 수 있다.** 로그인 전에는 아무것도 기록하지 않고, 메뉴바에도 "시작하기"만 보인다
  1. 로그인: 코드가 뜨고 브라우저가 열린다 → 코드 입력 → 자동으로 다음 단계
  2. 권한: 손쉬운 사용, 화면 기록을 허용 (화면 기록은 허용 후 "앱 다시 실행"). 건너뛰고 시작해도 되고 나중에 설정 탭에서 줄 수 있다
- 끝나면 수집이 시작된다. 앱은 **Dock 아이콘**으로 찾는다 (누르면 창이 열림). 메뉴바 아이콘도 있지만 메뉴바가 붐비면 노치 뒤로 가려진다. Dock 아이콘은 설정에서 끌 수 있다
- 메뉴바 메뉴: 그래프 열기 / 지금 정리 / 수집 일시정지 / 종료. 로그인 항목으로 자동 실행될 때만 창 없이 조용히 뜬다
- 설정에서 로그아웃하면 수집이 멈추고 다시 로그인 화면으로 돌아간다
- 시스템 설정의 "화면 및 시스템 오디오 녹음" 목록에 WorkGraph 가 안 보이면: 목록 아래 **+** 를 눌러 `build/WorkGraph.app` 을 직접 추가하고 켠 뒤 앱을 다시 실행한다. 앱은 macOS 에 권한을 요청한 뒤에야 그 목록에 등록된다 (온보딩의 "허용하기" 가 요청을 보낸다)
- 무슨 일이 있었는지는 `~/Library/Application Support/WorkGraph/app.log` 에 남는다 (단계 전환, 권한 요청 결과, 정리 성공·실패. 화면 내용이나 토큰은 쓰지 않는다)
- 같은 데이터로 두 번째 인스턴스를 띄우면(예: `.app` 이 떠 있는데 `swift run WorkGraphApp`) 수집하지 않고 "이미 실행 중" 안내만 보여준다. 행이 중복으로 쌓이는 것을 막기 위해서다
- 권한이 없어도 앱 이름은 기록된다. 허용하면 창 제목, URL, 문서 경로, 화면 텍스트, 스크린샷이 붙는다
- 서명 인증서가 고정돼 있어야 다시 빌드해도 권한이 유지된다 (스크립트가 `Capstone Prototype Dev` → `Apple Development` → ad-hoc 순으로 고름)

## LLM 연결 (앱 안에서 ChatGPT 로그인)

프록시 없이 앱이 Codex 백엔드를 직접 부른다. ChatGPT 구독 계정만 있으면 된다.

- 앱: 온보딩 첫 화면의 **ChatGPT 로 로그인**. 코드가 뜨고 브라우저가 열린다 → 코드 입력 → 자동으로 로그인됨 (코드는 클립보드에도 복사됨). 로그아웃은 설정 탭
- 터미널: `swift run wgctl codex-login` → `codex-status` / `codex-models` / `codex-logout`
- 확인: `swift run wgctl llm-test`
- 사용량: 설정 탭의 "사용량" 또는 `swift run wgctl codex-usage` (5시간 한도, 주간 한도 대비 %). 자세한 내역은 https://chatgpt.com/codex/settings/usage . 배치별 토큰 수는 활동 로그 탭의 정리 기록에 남는다
- 모델: 계정마다 쓸 수 있는 목록이 다르다. 로그인하면 설정에서 고를 수 있고 기본값은 `gpt-5.6-luna` (가벼운 배치용). 데모 하루치 전체가 입력 1만 3천 토큰 정도
- 기기 코드 방식이라 로컬 포트를 안 쓴다 (VS Code 의 Codex 확장이 1455 포트를 잡고 있어도 됨). 로그인 버튼에서 "기기 코드 로그인이 꺼져 있다"고 나오면 ChatGPT 설정의 보안 항목에서 켠다
- 토큰은 `~/Library/Application Support/WorkGraph/codex-auth.json` (권한 600)에만 저장된다. **Codex CLI(`~/.codex/auth.json`)나 gpt-proxy 와 파일을 공유하지 않는다.** refresh token 은 한 번 쓰면 새것으로 바뀌어서, 같은 토큰을 두 곳이 들고 있으면 나중에 쓰는 쪽이 "이미 사용된 토큰"을 보내 세션 전체가 무효가 된다 (gpt-proxy 가 주기적으로 죽던 원인). 앱과 CLI 가 동시에 갱신하지 않도록 파일 잠금도 건다
- 만료 5분 전, 또는 마지막 갱신에서 8일이 지나면 자동 갱신. 서버가 401 을 주면 한 번 갱신하고 재시도. 갱신이 영구 실패하면 "다시 로그인" 안내가 뜬다
- LLM 이 죽어 있거나 로그인이 안 돼 있어도 수집은 계속된다. 행은 미처리로 남았다가 연결되면 밀린 만큼 처리된다
- 주의: 이 엔드포인트는 공개 API 가 아니라 Codex CLI 가 쓰는 백엔드다. 규격이 예고 없이 바뀔 수 있고 사용량은 ChatGPT 구독의 Codex 한도에서 빠진다. 프로토타입·개인 사용에는 충분하지만, 배포용이면 아래의 API 키 방식이 정식 경로다

다른 서버를 쓰고 싶으면 설정에서 연결 방식을 **OpenAI 호환 서버**로 바꾼다 (`/chat/completions` 를 지원하면 됨: OpenAI API 키, gpt-proxy, Ollama, LM Studio).

```bash
swift run wgctl llm-test --base-url http://localhost:11434/v1 --model qwen3.5:2b    # Ollama 예시
```

## 모델 없이 전체 흐름 보기

```bash
DB=/tmp/workgraph-demo/workgraph.sqlite
swift run wgctl --db $DB seed-demo                 # 하루치 가짜 활동 (공부 / 서류 작업 / 프론트 개발 / 같은 프로젝트의 다른 업무)
swift run wgctl --db $DB batch --all --demo-llm    # 규칙 기반 가짜 LLM 으로 온톨로지화
swift run wgctl --db $DB stats
WORKGRAPH_DB=$DB WORKGRAPH_SHOW_WINDOW=1 build/WorkGraph.app/Contents/MacOS/WorkGraph   # 앱에서 그래프 보기
```

- `--demo-llm` 은 진짜 모델이 아니라 데모 시드를 키워드로 나누는 가짜다. 분류 품질 확인용이 아니라 흐름 시연·테스트용
- 실제 DB 위치: `~/Library/Application Support/WorkGraph/workgraph.sqlite` (스크린샷은 옆의 `captures/`)

## AI 코딩 도구 대화도 데이터로 쓴다

Claude Code 와 Codex CLI 는 대화를 로컬 파일에 남긴다. 사용자가 AI 에게 한 말은 "지금 뭘 하려는지"를 그대로 담고 있어서, 업무 제목과 주제를 잡는 데 가장 강한 단서다.

- 읽는 곳: `~/.claude/projects/**/*.jsonl` (type=user 줄), `~/.codex/history.jsonl` (작업 폴더는 `~/.codex/sessions/**` 의 session_meta 에서)
- 사용자가 입력한 메시지만 저장한다. 도구 결과, 서브에이전트, 주입된 안내(`<…>`로 시작), 중단 표시는 버리고 2,000자를 넘으면 자른다
- 처음 켜면 최근 24시간 것만 가져온다. 이후엔 파일이 바뀔 때마다 새 줄만 읽는다 (읽은 위치는 `chat_cursors` 에 기억)
- 정리할 때 같은 세션의 메시지가 체류 0초짜리 행 하나로 들어간다 (앱 시간 집계에는 안 들어감). 그래프에는 `AIChat` 자료 노드가 되고, 작업 폴더가 있으면 프로젝트에 연결된다
- 설정 → 수집 → "AI 코딩 도구 대화 읽기" 로 끈다. 저장된 메시지는 `v_chats` 뷰

## 기록하지 않을 앱

설정 → "기록하지 않을 앱". 기본은 비밀번호 관리자와 시스템 화면(로그인 창, 화면 보호기)이다. 실행 중인 앱에서 고르거나 `.app` 파일을 선택해 추가한다. 제외한 앱은 **이름과 시간만** 남고 창 제목·주소·화면 텍스트·스크린샷은 기록되지 않는다. WorkGraph 자신도 같은 규칙이다.

## 데이터 직접 보기

**앱에서**: 활동 로그 탭. 위 표는 원시 행(관측), 아래 표는 정리 기록. 행을 누르면 오른쪽에 모든 필드와 화면 텍스트 전문, 스크린샷이 보이고, 정리 기록을 누르면 LLM 이 받은 것(그 배치의 활동 행 + 시스템 프롬프트), 돌려준 것(구조화 JSON), 다듬은 뒤 반영한 것, 원본 응답이 보인다.

**DBeaver 에서** (또는 SQLite 를 여는 아무 도구):
1. 새 연결 → SQLite → Path 에 `~/Library/Application Support/WorkGraph/workgraph.sqlite`
2. 연결 설정의 **Read-only connection** 을 켠다. 앱이 계속 쓰는 파일이라 도구에서 고치면 안 된다 (읽기는 동시에 해도 된다, WAL 모드)
3. 처음이면 SQLite 드라이버 다운로드 창이 뜬다 → Download
4. 터미널 한 줄로도 된다: `/Applications/DBeaver.app/Contents/MacOS/dbeaver -con "driver=sqlite|database=$HOME/Library/Application Support/WorkGraph/workgraph.sqlite|name=WorkGraph|readonly=true"`

읽기 좋은 뷰가 미리 들어 있다 (Views 폴더):

| 뷰 | 내용 |
|---|---|
| `v_rows` | 원시 행 + 현지 시각 + 화면 텍스트 전문 (`text`) + 스크린샷 경로 + 어느 배치가 처리했는지 |
| `v_chats` | AI 코딩 도구에 입력한 메시지 (도구, 세션, 작업 폴더, 본문) |
| `v_batches` | 정리 기록 + `user_prompt`(LLM 이 받은 활동 행), `system_prompt`, `llm_patch`(돌려준 JSON), `applied_patch`(반영한 JSON), 토큰, 오류 |
| `v_sessions` | 세션을 업무 이름·시작·끝·작업 초·요약으로 |
| `v_nodes`, `v_edges` | 그래프. 엣지는 양쪽 노드의 라벨과 제목을 붙여서 |

```sql
SELECT * FROM v_rows ORDER BY id DESC LIMIT 200;                     -- 최근 원시 행
SELECT id, time, status, row_count, llm_patch FROM v_batches ORDER BY id DESC;   -- LLM 이 돌려준 것
SELECT user_prompt FROM v_batches WHERE id = 26;                     -- 그 배치에 보낸 프롬프트 전문
SELECT * FROM v_sessions ORDER BY start_time;                        -- 업무별 세션
SELECT * FROM v_edges WHERE type = 'RESOLVED_BY';                    -- 문제 → 해결 자료
```

원본 테이블: `observations`, `text_snapshots`, `file_events`, `idle_spans`, `chat_messages`, `batches`, `nodes`, `edges`. 시각은 Unix 초.

터미널: `swift run wgctl rows --last 50 --text`, `wgctl batches`, `wgctl batch-show 26`, `wgctl dump report.md --since-hours 24 --text` (전부 마크다운 한 파일로).

## 그래프에 물어보기

DB 는 그냥 SQLite 라서 아무 도구로나 열린다.

```sql
-- React 업무에서 자료 "상위 분류"별로 쓴 시간. 클래스 층(SUBCLASS_OF)이 있어야 나오는 집계
SELECT COALESCE(parent.title, rtype.title) AS 분류, rtype.title AS 종류, CAST(SUM(t.weight)/60 AS INT) AS 분
FROM nodes topic
JOIN edges about ON about.dst = topic.id AND about.type = 'ABOUT'
JOIN edges part  ON part.dst = about.src AND part.type = 'PART_OF'
JOIN edges t     ON t.src = part.src AND t.type = 'TOUCHED'
JOIN edges inst  ON inst.src = t.dst AND inst.type = 'INSTANCE_OF'
JOIN nodes rtype ON rtype.id = inst.dst
LEFT JOIN edges sub ON sub.src = rtype.id AND sub.type = 'SUBCLASS_OF'
LEFT JOIN nodes parent ON parent.id = sub.dst
WHERE topic.label = 'Topic' AND topic.key = 'react'
GROUP BY 분류, 종류 ORDER BY 분 DESC;
-- 데모 결과: 산출물/CodeFile 59분, 참고자료/Documentation 25분, 참고자료/QnA 9분 …

-- 한 업무에서 3다리 안에 닿는 모든 것 (Cypher 의 -[*1..3]- 에 해당, 인수인계 export 의 핵심)
WITH RECURSIVE reach(id, depth) AS (
  SELECT id, 0 FROM nodes WHERE label = 'Task' AND title = '대시보드 필터 UI 구현'
  UNION
  SELECT CASE WHEN e.src = r.id THEN e.dst ELSE e.src END, r.depth + 1
  FROM reach r JOIN edges e ON e.src = r.id OR e.dst = r.id WHERE r.depth < 3)
SELECT n.label, n.title FROM reach JOIN nodes n ON n.id = reach.id;
```

- **온톨로지 정의 보기**: `swift run wgctl schema` — 클래스 12개(표준 상위 클래스 포함)와 관계 14개(허용되는 출발 → 도착 쌍, 뜻, 표준 어휘 대응). 정의는 `Sources/WorkGraphCore/Ontology/RelationSchema.swift` 한 곳에 있고, 저장소가 이 정의 밖의 관계(모르는 관계, 잘못된 방향)를 거부한다
- **표준 RDF 로 내보내기**: `swift run wgctl export-rdf graph.ttl` — PROV-O·SKOS·Dublin Core 에 매핑한 Turtle. 세션은 prov:Activity, 자료는 prov:Entity, 앱은 prov:SoftwareAgent, "봤다"는 prov:used(+ 체류시간이 붙은 qualifiedUsage). 우리 어휘(wg:)는 표준 클래스·속성의 하위로 선언돼 있어 rdflib, Protégé, GraphDB 같은 표준 도구가 그대로 읽는다. 예: `?a a prov:Activity ; prov:used ?e` 로 우리 어휘를 몰라도 질의 가능, `rdfs:subClassOf*` 로 "참고자료" 상위 종류 집계 가능
- CLI 로도 된다: `swift run wgctl neighbors Resource "https://ui.shadcn.com/docs/components/card" --hops 2`
- Neo4j 에서 보고 싶으면: `swift run wgctl export-cypher graph.cypher` → Neo4j Browser 에 붙여 넣기 (발표·탐색용)

## 구조

| 위치 | 역할 |
|---|---|
| `Sources/WorkGraphCore` | 순수 로직. DB, uri 정규화, 규칙 분류, 압축, LLM 클라이언트(ChatGPT 로그인 · OpenAI 호환), 반영기, 배치, 내보내기. 권한 없이 테스트됨 |
| `Sources/WorkGraphCollectors` | macOS 수집기. 접근성 API, ScreenCaptureKit, Vision OCR, FSEvents, 유휴 감지 |
| `Sources/WorkGraphApp` | 메뉴바 앱 + 창(그래프 / 활동 로그 / 설정). 그래프 화면은 `Resources/graph` 의 HTML·JS |
| `Sources/wgctl` | 개발용 CLI. `swift run wgctl` 로 도움말 |
| `docs/superpowers/specs` | 설계 문서 (그래프 DB 선정 이유 포함) |

업무가 잘게 쪼개지지 않게 하는 규칙 (`SegmentNormalizer`, LLM 응답을 반영하기 직전에 적용):
- 3분 미만인데 새 업무를 만들려는 구간만 건드린다. 긴 구간과 기존 업무 매칭은 LLM 판단 그대로
- 짧은 구간끼리 비슷하면 묶고, 합이 3분을 넘으면 업무 하나로 승격 (메신저 확인 4번 → 업무 1개)
- 비슷한 기존 업무가 있으면 그쪽으로, 같은 업무 사이에 낀 끼어들기는 그 업무로, 어디에도 안 맞으면 "자잘한 확인" / "짧은 딴짓" 으로
- 실제 50분 활동 기준 업무 16개 → 5개
- 분류 로직을 바꾼 뒤에는 앱을 끄고 `swift run wgctl rebuild-graph --yes && swift run wgctl batch --all` 로 그래프를 원시 행에서 다시 만든다 (원시 행·스크린샷은 그대로)

핵심 규칙:
- LLM 없이 하는 것: uri 정규화(같은 자료 = 같은 노드), 자료 종류 분류, 체류시간 계산
- LLM 이 하는 것: 행을 업무 구간으로 나누기, 업무 제목·종류·주제, 문제–해결 관계, 나중에 할 일, 전환 종류(계획/막힘/딴짓)
- 반영은 upsert 라서 같은 자료를 100번 봐도 노드는 하나. 반영과 "처리 완료 표시"는 한 트랜잭션

## 개발

```bash
swift build
swift test                                        # 111개
swift run wgctl --db /tmp/wg/test.sqlite collect --seconds 20   # 수집기만 터미널에서 돌려보기 (권한은 터미널 앱 기준)
```

- 환경변수: `WORKGRAPH_REQUEST_PERMISSIONS=1`(실행하자마자 두 권한 요청, 예: `open --env WORKGRAPH_REQUEST_PERMISSIONS=1 build/WorkGraph.app`), `WORKGRAPH_DB`(DB 경로), `WORKGRAPH_CODEX_AUTH`(로그인 토큰 파일 경로), `WORKGRAPH_SHOW_WINDOW=1`(시작 시 창 열기), `WORKGRAPH_TAB=activity|settings`(시작 탭)
- 클래스 층 바꾸기: `Sources/WorkGraphCore/Ontology/TBox.swift`. 자료 분류 규칙: `RuleClassifier.swift`. 프롬프트: `OntologyPrompt.swift`
- 그래프 화면만 브라우저에서 보기: `swift run wgctl export-graph g.json --tbox` 후 `index.html?data=g.json` 을 로컬 서버로 열기

## 아직 없는 것

- 보고서, 재개, 이탈 알림, 기억 기반 검색, export UI, SOP — 데이터와 그래프는 준비됨
- 입력 이벤트(클릭·타이핑 멈춤) 기반 캡처. 지금은 3초 폴링 + 앱 전환 알림
- Windows
