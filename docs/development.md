# 개발 가이드

[README로 돌아가기](../README.md)

## 빌드와 권한

```bash
./scripts/make-app.sh
open build/Sillog.app
```

빌드 스크립트는 소스를 임시 경로에 복사해 컴파일하고 앱 번들을 서명합니다. 완성된 앱은 `~/Applications/Sillog.app`에 설치하며, `build/Sillog.app`은 설치된 앱으로 연결되는 심볼릭 링크입니다. 컴파일과 서명은 Documents 동기화의 영향을 피하면서, 실행과 권한 등록에는 일정한 설치 경로를 사용합니다.

서명 인증서는 `SIGN_IDENTITY` 지정값 → `Capstone Prototype Dev` → `Apple Development` → ad-hoc 순서로 선택합니다.

```bash
SIGN_IDENTITY="Apple Development: 인증서 이름" ./scripts/make-app.sh
```

이름 변경 후에도 번들 ID는 `com.capstone.workgraph`를 유지합니다. 같은 번들 ID만으로 권한 유지가 보장되는 것은 아니며, **동일한 서명 인증서도 필요합니다.** ad-hoc 서명에서는 재빌드 후 권한을 다시 허용해야 할 수 있습니다.

문제가 생겼을 때:

- **화면 기록 목록에 앱이 없음**: 시스템 설정의 화면 기록 목록에 `~/Applications/Sillog.app`을 직접 추가하고 허용한 뒤 앱을 종료하고 다시 실행합니다.
- **시스템 설정은 허용인데 앱은 권한 없음**: ad-hoc 서명으로 다시 빌드하면 기존 권한에 저장된 서명과 달라질 수 있습니다. 앱을 종료하고 화면 기록 목록의 Sillog 항목을 제거한 뒤, 설치된 앱을 다시 추가·허용하고 실행합니다. 재빌드 후에도 권한을 유지하려면 같은 개발자 인증서로 서명합니다.
- **이미 실행 중 안내**: 같은 DB를 사용하는 기존 앱 또는 `swift run WorkGraphApp` 프로세스를 종료합니다. 수집 중인 DB에 두 인스턴스가 동시에 쓰지 않도록 잠금이 걸립니다.
- **`no such module 'XCTest'`**: 전체 Xcode와 개발자 경로를 확인합니다. Command Line Tools만 설치한 환경에는 XCTest가 없을 수 있습니다. 앱 빌드 성공과 단위 테스트 통과는 별도로 확인해야 합니다.
- **실행·권한·정리 오류 확인**: `~/Library/Application Support/WorkGraph/app.log`를 확인합니다. 로그에 화면 내용이나 토큰은 기록하지 않습니다.

## 환경변수

기존 실행 설정과 호환되도록 `WORKGRAPH_*` 이름을 유지합니다. OAuth 변수는 [플러그인 설정](plugins.md)을 참고하세요.

| 변수 | 용도 |
| --- | --- |
| `WORKGRAPH_BUILD_DIR` | 빌드 캐시·소스 복사본·앱 번들을 준비할 경로 |
| `SIGN_IDENTITY` | 앱 서명 인증서. `-`는 ad-hoc |
| `WORKGRAPH_DB` | 기본값 대신 사용할 SQLite 파일 |
| `WORKGRAPH_CODEX_AUTH` | 앱 전용 ChatGPT 인증 파일 경로 |
| `WORKGRAPH_SHOW_WINDOW=1` | 시작 시 메인 창 표시 |
| `WORKGRAPH_REQUEST_PERMISSIONS=1` | 시작 시 손쉬운 사용·화면 기록 권한 요청 |
| `WORKGRAPH_TAB` | 시작 탭: `graph`, `tasks`, `files`, `library`, `activity`, `chat`, `settings` |

## 테스트와 CLI

```bash
swift build
swift test
swift run wgctl
```

`wgctl`은 앱과 같은 코어 로직을 사용하는 개발 도구입니다. 기본 DB는 실제 사용자 기록이므로, 실험에는 `--db`로 별도 DB를 지정하세요. 그래프 재생성·업무 병합처럼 데이터를 변경하는 명령은 앱을 종료하고 백업 후 실행해야 합니다.

### 모델 없이 흐름 확인

```bash
SILLOG_TEST_DIR=$(mktemp -d)
SILLOG_TEST_DB="$SILLOG_TEST_DIR/workgraph.sqlite"
swift run wgctl --db "$SILLOG_TEST_DB" seed-demo
swift run wgctl --db "$SILLOG_TEST_DB" batch --all --demo-llm
swift run wgctl --db "$SILLOG_TEST_DB" stats
WORKGRAPH_DB="$SILLOG_TEST_DB" WORKGRAPH_SHOW_WINDOW=1 build/Sillog.app/Contents/MacOS/Sillog
```

`--demo-llm`은 시드 데이터를 규칙으로 분류하는 가짜 모델입니다. 수집→분류→그래프 흐름을 확인하는 용도이며 실제 LLM 품질 평가에 사용할 수 없습니다. 앱의 로그인·온보딩을 우회하지는 않습니다.

### 자주 쓰는 읽기 명령

```bash
swift run wgctl rows --last 50 --text
swift run wgctl batches
swift run wgctl cards --last 20
swift run wgctl tasks
swift run wgctl schema
swift run wgctl dump report.md --since-hours 24 --text
swift run wgctl export-graph graph.json --tbox
swift run wgctl export-rdf graph.ttl
swift run wgctl export-cypher graph.cypher
```

덤프와 내보내기에는 개인 기록이 포함될 수 있으므로 저장소에 커밋하지 마세요.

## 데이터 구조

```text
앱·창·URL·화면·파일·AI 사용자 요청 수집
                    ↓
SQLite 원시 기록 + 화면 기억 카드
                    ↓ LLM 배정
업무·자료·주제 + 시간 기반 세션·관계
                    ↓
그래프 탐색 · 업무 재개 · 채팅 검색·결과물
```

- 앱·창·URL은 3초마다 확인합니다. 화면 캡처는 활성 창을 대상으로 하며, 캡처 도중 창이 바뀌면 저장하지 않습니다.
- LLM 정리는 기본 5분 배치로 실행하지만, 업무 판단 단위는 개별 관측 행입니다. 목표에 기여하는 행, 집중 이탈, 내용 없는 화면을 구분합니다.
- 화면 기억 카드는 대표 스크린샷의 내용을 요약합니다. 업무 배정과 채팅 검색에 활용하며 설정에서 끌 수 있습니다.
- 세션은 같은 업무의 관측을 시간으로 묶습니다. URI 정규화·체류시간·세션 구성·프로젝트 연결은 LLM 없이 계산합니다.
- AI 코딩 도구 로그는 Claude Code·Codex의 로컬 기록에서 사용자 입력만 읽습니다. 처음에는 최근 24시간, 이후에는 새로 추가된 내용을 읽습니다. 앱 채팅과는 별도 데이터입니다.

SQLite 도구로 열 때는 **읽기 전용 연결**을 사용하세요. 앱이 WAL 모드로 계속 기록하는 파일입니다.

| 조회 뷰 | 내용 |
| --- | --- |
| `v_rows` | 관측 행, 현지 시각, 화면 텍스트, 캡처 경로, 처리 배치 |
| `v_row_tasks` | 관측 행의 업무 배정·이탈·자료 판정과 이유 |
| `v_chats` | 외부 AI 코딩 도구의 사용자 메시지 |
| `v_batches` | 정리 입력·프롬프트·응답·반영 결과·토큰·오류 |
| `v_cards` | 화면 기억 카드 |
| `v_sessions` | 업무별 세션과 작업 시간·요약 |
| `v_nodes`, `v_edges` | 그래프 노드·관계 |
| `v_file_suggestions` | 파일 이동 제안·결정·결과 |

앱 채팅은 `app_conversations`, `app_messages`, `app_automations`에 저장됩니다. 원시 활동·외부 AI 대화와 분리되어 있으며, 시각은 Unix 초를 사용합니다.

CHAT-110의 목표별 프로젝트는 `app_projects`, 업무 소속은 `project_tasks`, 대화 소속은 `app_conversations.project_id`에 저장합니다. 기존 그래프의 저장소·폴더 `Project` 노드와는 별개입니다. 대기 중인 후보는 `project_proposals`, 검토·무시·수동 이동 이력은 `project_reviewed`에 남깁니다. 최초 검토는 기존 항목을 40개씩 처리하고, 이후 새 항목을 판단할 때 이전 미분류 항목도 연결 근거로 제공합니다. 사용자가 수락하기 전에는 소속을 변경하지 않습니다.

수락 대기 중인 업무의 자동 병합은 보류합니다. 수락한 뒤에도 서로 다른 프로젝트의 업무와 사용자가 직접 분류에서 뺀 업무는 병합으로 소속을 바꾸지 않습니다. 프로젝트를 삭제하면 대화와 예약의 프로젝트 소속만 해제합니다.

프로젝트의 `memoryMode`는 `allRecords`(기본) 또는 `projectOnly`입니다. 기본 모드는 현재 프로젝트의 대화를 우선하고 전용 프로젝트를 제외한 기록을 검색합니다. 전용 모드는 해당 프로젝트의 업무·대화·자료만 허용하며, 일반 채팅에서도 제외됩니다. 검색과 직접 읽기 모두 같은 범위를 검사하고, 공유 자료의 관계를 따라갈 때도 전용 업무·세션으로 확장하지 않습니다. 공개·전용 활동이 섞인 화면 카드는 요약을 노출하지 않습니다.

v13의 `app_library`에는 파일 메타데이터와 추출 텍스트, `library_project_sources`와 `library_conversation_sources`에는 명시적인 연결을 저장합니다. 파일 복사본은 DB 옆 `library/<자료 ID>/`에 둡니다. 프로젝트·대화 삭제 시 연결만 제거하고 보관함 원본은 유지합니다. `library_deleted_origins`는 사용자가 삭제한 생성 결과물이 다음 앱 실행에서 다시 수집되지 않게 합니다. 기존 경로는 그대로 유지하며 다른 대화의 경로를 자동 공유하지 않습니다.

v14의 `app_messages_fts`는 완료된 메시지와 결과물 본문 전체를 색인하고 저장·상태 변경·삭제 트리거로 갱신합니다. 검색은 일치한 메시지 ID를 반환하고 `read_context`로 원문을 문자 위치별로 이어 읽습니다. 대화 ID 조회는 시작 메시지 번호부터 20개씩 반환합니다. 저장 자료와 관련 과거 기록 일부는 실행 시작 시 제공하며 추가 원문은 도구로 읽습니다. 프로젝트 공통 지침은 사용자 설정이고 검색된 내용은 지시가 아닌 자료로 전달합니다.

## 구현 위치

- **스키마·관계**: `Sources/WorkGraphCore/Ontology/TBox.swift`, `RelationSchema.swift`
- **업무 배정**: `OntologyPrompt.swift`, `AssignmentApplier.swift`, `SessionBuilder.swift`
- **자료 분류**: `RuleClassifier.swift`, `URINormalizer.swift`
- **채팅 실행**: `Sources/WorkGraphCore/Chat/ChatRunner.swift`, `ChatTools.swift`
- **채팅 시스템 프롬프트**: `Sources/WorkGraphCore/Chat/Prompts/chat-system-prompt.md`(원문), `ChatSystemPrompt.swift`(끝의 `{{…}}` 칸 채우기)
- **스킬**: `Sources/WorkGraphCore/Chat/Skills/catalog.json`과 각 Markdown 지침
- **대화·예약 상태**: `Sources/WorkGraphApp/Chat/ChatState.swift`
- **프로젝트 제안·소속**: `Sources/WorkGraphCore/Chat/ProjectOrganizer.swift`, `ProjectStore.swift`, `Sources/WorkGraphApp/Chat/ProjectState.swift`
- **자료 보관·추출**: `Sources/WorkGraphCore/Chat/LibraryStore.swift`, `FileTextExtractor.swift`, `Sources/WorkGraphApp/Chat/LibraryState.swift`, `Views/LibraryView.swift`
- **그래프 화면**: `Sources/WorkGraphApp/Resources/graph`

채팅 하위 에이전트는 독립적인 대화와 읽기 도구를 사용하고, 재위임하지 않습니다. 시스템 프롬프트는 주 에이전트와 같지만 `agent_role`에 역할 이름이 들어가고 스킬·프로젝트·기억 자료 블록은 빠집니다. 주·하위 작업은 한 요청의 실행 예산을 공유합니다. OpenAI 호환 방식은 모델 호출 최대 24회, Codex 방식은 에이전트 실행 최대 24회와 실행별 앱 도구 호출 최대 32회입니다. 사용자가 중단하면 실행을 취소합니다.
