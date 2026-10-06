# 기록 정리·요약(주간·월간 다이제스트) Implementation Plan

> 이 문서는 구현 코드 전문 대신 데이터 모델, 처리 흐름, 파일 구조, 테스트 목록, 검증 방법을 고정한다. 코드의 정본은 저장소다. 단계는 체크박스(`- [ ]`)로 추적한다.

**Goal:** 오래된 원시 기록을 주·월 단위 요약과 결정적 집계로 바꿔 저장 공간을 상한 안에 둔다. 동시에 과거 기간에 대한 검색, 채팅 답변, 보고서 품질은 유지한다.

**Architecture:** 기억을 세 층으로 나눈다. 원문 층(관측·화면 텍스트·스크린샷·배치 로그)은 보관 기간 동안만 둔다. 일별 사용 시간 기록(날짜·업무·자료별 사용 시간, 이하 '사용 시간 기록')은 원문이 있을 때 코드로 계산해 영구 보관한다. 다이제스트(업무별 주간·월간 요약)는 LLM이 서술하고 수치는 사용 시간 기록에서 가져온다. 업무·자료·문제·할 일 그래프는 계속 유지한다. 정리는 "요약 생성 → 검증 → 유예 → 삭제" 순서로, 앱이 유휴일 때 실행한다.

**Tech Stack:** 기존과 동일하다. GRDB 7, SQLite FTS5(trigram), 정리용 LLM(OpenAI 호환·Codex).

**관련 문서:** `docs/superpowers/specs/2026-09-21-workgraph-collector-ontology-design.md`, `docs/superpowers/specs/2026-09-23-screen-memory-cards-design.md`, `docs/prompts/chat-system-prompt.md`

---

## 1. 현재 관리 방식

2026-10-05 기준으로 코드와 개발자 Mac의 실제 데이터에서 확인한 내용이다.

### 1.1 저장 위치

```text
~/Library/Application Support/WorkGraph/
├── workgraph.sqlite (+ -wal)   기록·그래프·채팅·결과물·예약
├── captures/YYYY-MM-DD/*.jpg   스크린샷
├── library/                    보관함 파일 복사본·생성 결과물
└── app.log                     실행 로그
```

### 1.2 데이터별 정리 방식

| 데이터 | 현재 정리 방식 | 코드 |
|---|---|---|
| 스크린샷 | `retentionDays`(기본 7일, 설정 1~90일)가 지난 날짜 폴더를 6시간마다 삭제 | `CollectorCoordinator.swift:174`, `:322`, `SettingsView.swift:34` |
| 화면 텍스트(`text_snapshots`) | 같은 텍스트는 해시로 한 번만 저장한다. 삭제는 없다 | `EventStore.upsertText` |
| 관측, 화면 카드, 배치 로그, AI 도구 요청, 파일 이벤트, 유휴 구간 | 삭제 없음 | — |
| 그래프 | 재구성할 때 어느 세션도 참조하지 않는 자료 노드만 정리. 재구성은 개발 CLI(`wgctl`)에서만 호출된다 | `GraphTx.pruneOrphanResources`, `wgctl/main.swift:238` |
| 채팅 대화·보관함 | 사용자가 직접 삭제할 때만 | — |
| 로그 | 1MB를 넘으면 회전 | `AppLog.swift:26` |
| DB 파일 | `auto_vacuum = 0`. 행을 지워도 파일 크기가 줄지 않는다 (현재 빈 페이지 87개) | `PRAGMA auto_vacuum` |

설정 화면의 보관 기간은 실제로는 **스크린샷에만** 적용된다.

### 1.3 실측

개발자 Mac에서 활동한 4일(9/26, 10/2~10/4) 동안 쌓인 양이다.

전체 25MB = 스크린샷 14MB(120장) + DB 약 9.4MB(dbstat 페이지 합계).

| DB 구성 | 크기 | 비중 |
|---|---|---|
| 화면 텍스트 검색 색인 (`text_snapshots_chat_fts`, trigram) | 3.6MB | 39% |
| 배치 로그 (`batches`: 프롬프트·응답 전문) | 2.4MB | 26% |
| 화면 텍스트 원문 (`text_snapshots`, 268건, 텍스트 1.2MB) | 2.0MB | 22% |
| 화면 카드 + 색인 | 0.3MB | 3% |
| 관측 (`observations`, 746건) | 0.2MB | 2% |
| 그래프 노드·엣지·색인 | 0.27MB | 3% |
| 기타 (인덱스, AI 도구 요청, 파일 이벤트 등) | 약 0.5MB | 6% |

- **배치 1건이 약 32KB를 차지한다.** 시스템 프롬프트 6.0KB, 사용자 프롬프트 5.2KB, 원본 응답 19.3KB, 패치 1.2KB다. 시스템 프롬프트는 서로 다른 값이 **2개뿐인데 71번 저장**됐다.
- **trigram 색인이 원문 텍스트의 약 3배다.**
- **DB 증가량은 활동일당 약 2.5MB다.** 연 250일 활동을 가정하면 **연 약 600MB가 상한 없이 쌓인다.**
- **스크린샷은 활동일당 약 7MB다.** 보관 7일이면 35~50MB에서 멈추지만, 설정 최대치인 90일이면 400~600MB까지 늘어난다.
- 이 수치는 개발 중 4일 사용량을 외삽한 것이다. 하루 8시간 이상, 텍스트가 많은 앱을 쓰는 사용자는 비례해서 늘어난다.

### 1.4 문제점

1. DB가 상한 없이 늘고, 그중 약 86%가 원문 층(화면 텍스트 + 색인 + 배치 로그)이다.
2. 지워도 파일이 줄지 않는다 (`auto_vacuum` 꺼짐).
3. 스크린샷이 삭제된 뒤에도 `observations.screenshot_path`와 `screen_cards.screenshot_path`가 없는 파일을 가리킨다.
4. 오래된 기간을 대표할 요약 단위가 없다. 채팅은 원문 검색 샘플(쿼리당 노드 12건, 관측 10건)에 의존한다.
5. `GraphRebuilder`는 세션과 세션 엣지를 모두 지우고 관측 전체로 다시 만든다(`GraphRebuilder.swift:34-39`). 업무 시간(`active_seconds`)도 0으로 초기화한 뒤 다시 계산한다. **원문을 지우면 그 기간의 세션과 시간이 사라진다.** 정리 기능의 가장 큰 제약이다.

---

## 2. 설계 원칙

1. **요약이 먼저, 삭제는 나중이다.** 다이제스트가 만들어지고 검증된 뒤 유예 기간이 지나야 원문을 지운다. 삭제는 되돌릴 수 없기 때문이다.
2. **숫자는 코드가, 문장은 LLM이 만든다.** 시간과 건수는 원문이 남아 있을 때 SQL로 계산해 사용 시간 기록에 고정한다. LLM이 쓴 문장에 들어간 숫자는 사용 시간 기록 값과 일치할 때만 통과시킨다. ChatGPT Work의 주요 실패 유형인 집계 오류를 구조적으로 막는 장치다.
3. **근거 사슬을 유지한다.** 다이제스트의 문장은 안정적인 앵커를 가리킨다. 앵커는 업무·자료의 `key`, URL, 파일 경로, 커밋 해시다. 세션 node ID는 재구성할 때 바뀌므로 앵커로 쓰지 않는다.
4. **그래프는 오래 남긴다.** 노드와 엣지는 작고(현재 0.27MB), 관계 정보의 뼈대다.
5. **사용자가 통제한다.** 정책 프리셋, 정리 미리보기, 보존 핀, 내보내기를 제공한다. 첫 삭제는 명시적 동의를 받은 뒤에만 한다.
6. **접근 범위를 그대로 상속한다.** 프로젝트 전용 모드의 격리를 다이제스트에도 똑같이 적용한다.
7. **언제 중단돼도 안전하다.** 모든 단계는 멱등이고 재개할 수 있다. 트랜잭션 단위는 하루 또는 한 주다.

---

## 3. 기억 계층과 기본 보관 정책

| 층 | 데이터 | 기본 보관 | 정리 후 대신 남는 것 |
|---|---|---|---|
| 원문 | 스크린샷 | 7일 (현행 유지) | 화면 카드 |
| 원문 | 화면 텍스트 + 검색 색인 | 30일 | 다이제스트, 화면 카드, 세션 요약 |
| 원문 | 배치 로그의 프롬프트·응답 전문 | 14일 | 배치 통계(토큰·건수·오류·적용 패치)는 영구 |
| 원문 | 관측 메타데이터(앱·창 제목·URL·시각) | 90일 | 사용 시간 기록 |
| 원문 | 유휴 구간 | 90일 | 사용 시간 기록에 반영됨 |
| 중간 | 화면 카드 | 180일 | 월간 다이제스트 |
| 중간 | AI 도구 요청(`chat_messages`) | 365일 | 주간 다이제스트의 요청 목록 |
| 중간 | 파일 이벤트·정리 제안 | 365일 | 그래프의 File 노드 |
| 장기 | 사용 시간 기록(`usage_ledger`) | 영구 | — |
| 장기 | 다이제스트(주·월) | 영구 | — |
| 장기 | 그래프 노드·엣지(세션 포함) | 영구 | — |
| 사용자 자료 | 채팅 대화·보관함·결과물 | 자동 삭제 안 함 | 저장 공간 화면에서 수동 정리 |

**일 단위 다이제스트는 따로 만들지 않는다.** 세션마다 이미 `summaries`(정리 배치마다 한 줄씩, 최대 40개)가 쌓이고, 사용 시간 기록이 일 단위 수치를 갖고 있기 때문이다.

**프리셋**

| 프리셋 | 화면 텍스트 보관 | 비고 |
|---|---|---|
| 가볍게 | 14일 | |
| 기본 | 30일 | |
| 길게 | 90일 | |
| 원문 무기한 | 삭제 안 함 | 요약만 만든다 |

나머지 항목의 보관일은 "고급"에서 따로 조정할 수 있다.

---

## 4. 데이터 모델 (마이그레이션 `v15-consolidation`)

```sql
-- 일·업무·대상별 사용 시간. 원문이 있을 때 코드로 계산하고, 원문이 정리된 날은 동결한다.
CREATE TABLE usage_ledger (
  day TEXT NOT NULL,                 -- 현지 날짜 YYYY-MM-DD
  task_key TEXT NOT NULL DEFAULT '', -- '' = 미배정·업무 외
  target_kind TEXT NOT NULL,         -- 'task' | 'resource' | 'app'
  target_key TEXT NOT NULL,          -- 업무 key, 자료 URI, 앱 번들
  seconds REAL NOT NULL,
  first_at REAL NOT NULL,
  last_at REAL NOT NULL,
  hits INTEGER NOT NULL DEFAULT 0,
  frozen INTEGER NOT NULL DEFAULT 0, -- 1 = 원문 정리됨, 재계산 금지
  PRIMARY KEY (day, task_key, target_kind, target_key)
);

-- 업무별 주간·월간 요약. 전체 요약은 저장하지 않고 조회할 때 접근 범위에 맞춰 조합한다.
CREATE TABLE digests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL,               -- 'week' | 'month'
  period TEXT NOT NULL,              -- '2026-W41' | '2026-10'
  period_start REAL NOT NULL,
  period_end REAL NOT NULL,
  tz TEXT NOT NULL,
  task_key TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,                -- 렌더링된 Markdown
  structured TEXT NOT NULL,          -- LLM 출력 JSON (검증 통과본)
  metrics TEXT NOT NULL,             -- 사용 시간 기록에서 계산한 수치 JSON
  anchors TEXT NOT NULL,             -- 자료 key·URL·파일·커밋·할 일 key
  status TEXT NOT NULL,              -- 'draft' | 'verified' | 'edited'
  model TEXT,
  prompt_version INTEGER NOT NULL,
  input_hash TEXT NOT NULL,          -- 입력이 바뀌면 재생성 대상
  created_at REAL NOT NULL,
  verified_at REAL,
  UNIQUE (level, period, task_key)
);
CREATE VIRTUAL TABLE digests_fts USING fts5(title, body,
  content='digests', content_rowid='id', tokenize='trigram');
-- digests_ai / digests_ad / digests_au 트리거: screen_cards_fts와 같은 방식

CREATE TABLE consolidation_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- ledger_until, week_until, month_until, sealed_until,
-- text_pruned_until, batches_pruned_until, observations_pruned_until, first_prune_consented_at

CREATE TABLE retention_pins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,                -- 'task' | 'period'
  key TEXT NOT NULL,                 -- 업무 key 또는 'YYYY-MM-DD..YYYY-MM-DD'
  created_at REAL NOT NULL,
  UNIQUE (kind, key)
);

-- 배치 시스템 프롬프트 중복 제거 (71회 저장 → 2개)
CREATE TABLE prompt_blobs (hash TEXT PRIMARY KEY, text TEXT NOT NULL);
ALTER TABLE batches ADD COLUMN system_prompt_hash TEXT;
```

**마이그레이션에서 같이 할 일**
- 기존 `batches.system_prompt`를 `prompt_blobs`로 옮기고 해시만 남긴다. 활동 로그 화면은 해시로 원문을 조회하게 바꾼다.

**마이그레이션 밖에서 할 일**
- `auto_vacuum = INCREMENTAL` 전환은 전체 `VACUUM`이 한 번 필요하다. `VACUUM`은 트랜잭션 안에서 실행할 수 없으므로, 첫 정리를 실행할 때 따로 수행한다(6.4).

**외래 키 주의**
- `observations.text_id → text_snapshots`, `observations.batch_id → batches`, `file_events.observation_id → observations`, `chat_messages.batch_id → batches` 참조가 있다.
- 따라서 참조하는 쪽을 먼저 `NULL`로 바꾼 뒤에 삭제한다.

---

## 5. 처리 흐름

### 5.1 실행 조건 (`Consolidator` actor)

**트리거**
- 앱 시작 10분 뒤, 그 뒤로 하루 한 번 실행한다.
- 실행 조건은 세 가지다. 유휴 5분 이상(`IdleMonitor`), 수집이 일시정지 상태가 아님, 전원 연결 또는 배터리 50% 이상.

**한 번 실행할 때의 순서**
1. 사용 시간 기록 갱신
2. 주간 다이제스트
3. 월간 다이제스트
4. 정리
5. 공간 회수

**처리량 상한:** 한 번 실행할 때 최대 2주와 1개월만 처리한다. 밀린 기간이 있으면 다음 실행에서 이어서 처리한다.

**기간을 닫을 수 있는 조건** (셋 다 만족해야 한다)
- 기간 끝으로부터 48시간이 지났다. 늦게 도착하는 배치와 사용자 수정을 반영하기 위해서다.
- 그 기간의 관측이 모두 정리 배치에 들어갔다. 마지막 배치의 `to_obs`가 기간 안 마지막 관측 ID 이상이고, 진행 중인 배치가 없어야 한다.
- 정리용 LLM 연결이 정상이다. 비정상이면 결정적 다이제스트만 만든다(5.3).

**기간 기준**
- 주는 ISO 주(월~일), 월은 달력 월이며, 둘 다 현지 시간대를 따른다.
- 한 주가 두 달에 걸치면 월간 수치는 사용 시간 기록(일 단위)에서 다시 계산한다.

### 5.2 사용 시간 기록 갱신 (결정적)

- **계산 방식:** `GraphRebuilder`와 같은 방식으로 관측을 행으로 압축하고(`EventCompressor`), 유휴 구간을 빼고, 행의 `dwell`을 day × task × target으로 합산한다.
- **계산 코드 공유:** 행에서 시간을 계산하는 부분을 `GraphRebuilder`에서 떼어 `ActivityTally`로 분리한다. 재구성과 사용 시간 기록이 같은 코드를 써서, 세션 시간과 사용 시간 기록 합계가 항상 일치하게 한다.
- **멱등:** 하루 단위로 `DELETE` 후 `INSERT`한다. `frozen = 1`인 날은 건드리지 않는다.

### 5.3 주간 다이제스트 (업무별)

**입력** (구조화된 JSON, 업무당 약 6k 토큰 이하)
- 업무: `key`, 제목, `goal`, `status`
- 사용 시간 기록 수치: 주간 합계, 일별 분포, 자료 상위 10개(초·URL·제목), 앱 상위 5개
- 그 주에 걸친 세션들의 `summaries`
- 문제: 새로 생김·해결됨(해결 자료 포함)·미해결
- 할 일(LaterItem): 새로 생김·남음
- 새 파일: 출처 URL 포함
- AI 도구 요청 목록: 요청 텍스트 요약과 시각, 같은 기간 커밋과 짝지어졌는지 여부
- 그 업무와 연결된 화면 카드 상위 N개
- 그 주 Sillog 대화에서 그 업무에 관한 결정(있을 때만)

**제외:** 업무 외(off-task) 행, 제외 앱, 비공개 창. 원래 원문이 없는 데이터다.

**출력:** OntologyBatcher처럼 함수 호출 JSON 스키마로 받는다.

```json
{
  "summary": "3~5문장",
  "progress": [{"text": "...", "status": "evidenced|in_progress|requested", "anchors": ["key"]}],
  "problems": [{"text": "...", "state": "resolved|open", "anchors": ["key"]}],
  "open_items": [{"text": "...", "anchors": ["key"]}],
  "decisions": [{"text": "...", "anchors": ["message:..."]}],
  "numbers_used": [{"name": "active_seconds", "value": 21600}]
}
```

`body`(Markdown)는 코드가 `structured`와 `metrics`로 렌더링한다. 시간 문구("약 6시간")도 코드가 만든다.

**검증 (`DigestValidator`, 코드)**
1. 서술에 나온 모든 숫자·시간·날짜는 `metrics` 값(반올림 허용)이거나 입력 텍스트에 그대로 있던 값이어야 한다.
2. `anchors`는 입력에 있던 key만 허용한다.
3. `evidenced` 상태는 입력에서 근거 플래그(커밋·파일·사용자 표시)가 있는 항목에만 허용한다. 활동 기록이 곧 완료의 증거는 아니라는 원칙을 코드로 강제하는 장치다.
4. 길이 상한: `summary` 600자, 각 목록 8개.

**실패하면**
- 한 번 다시 생성한다.
- 그래도 실패하면 결정적 다이제스트(수치와 세션 요약 나열)로 대체하고 `status = 'draft'`로 둔다.
- `draft` 기간의 원문은 삭제하지 않는다.

**LLM을 생략하는 경우:** 그 주 활동이 10분 미만인 업무는 결정적 한 줄 요약만 만든다.

**프롬프트 (`DigestPrompt`):** 시스템 프롬프트의 근거 원칙을 따른다(활동 ≠ 성과, 요청 ≠ 완료, 수치 생성 금지). 한국어로 출력하고, `prompt_version`으로 관리한다.

### 5.4 월간 다이제스트 (업무별)

- **입력:** 그 달에 걸친 주간 다이제스트들의 `structured`, 사용 시간 기록 월 합계, 문제와 할 일의 월초 대비 월말 변화.
- **출력:** 한 달의 흐름, 진척, 해결된 것, 남은 것. 같은 스키마와 같은 검증을 쓴다.

### 5.5 재생성과 수정

- **재생성 대상:** `input_hash`가 바뀌어 다르게 나올 수 있는 경우다. 예를 들어 사용자가 업무를 병합·이름 변경했거나, 늦게 도착한 배치가 들어온 경우다.
- **원문이 남아 있는 기간만 재생성한다.**
- 원문이 정리된 기간은 재생성할 수 없다. 그래서 정리 전에 유예 기간을 둔다.
- 사용자가 업무 화면에서 요약을 고치면 `status = 'edited'`가 되고, 이후 자동 재생성 대상에서 빠진다.

---

## 6. 정리(삭제) 엔진

### 6.1 삭제 조건

데이터별 기준일은 "지금 − 보관일"이다. 다만 하루 D의 원문은 다음을 **모두** 만족할 때만 지운다.

1. D가 속한 주의 다이제스트가 그 주의 활동 업무 전부에 대해 `verified` 또는 `edited`다.
2. 검증 후 유예 기간 7일이 지났다.
3. D의 사용 시간 기록이 갱신 완료 상태다.
4. 사용자가 첫 정리에 동의했다(`first_prune_consented_at`).

**핀 처리:** 핀이 걸린 업무의 관측과 텍스트는 남기고 나머지만 지운다. 핀이 걸린 기간은 통째로 건너뛴다.

### 6.2 삭제 순서 (하루 단위 트랜잭션)

1. **사용 시간 기록 동결:** D의 사용 시간 기록 행을 `frozen = 1`로 바꾼다.
2. **화면 텍스트:** D의 관측이 참조하는 `text_id` 중, 보관 기간 안의 다른 관측이나 핀이 참조하지 않는 것만 지운다(해시 중복 제거 때문에 여러 날이 같은 텍스트를 공유할 수 있다). 먼저 `observations.text_id = NULL`로 바꾼다. 검색 색인은 삭제 트리거(`text_snapshots_chat_fts_ad`)가 자동으로 지운다.
3. **배치 로그(14일):** `user_prompt`, `raw_response`, `llm_patch`, `system_prompt`를 `NULL`로 바꾼다. 해시, 통계, 토큰, 오류, `applied_patch`는 남긴다.
4. **관측(90일):** `file_events.observation_id`를 `NULL`로 바꾼 뒤 관측을 지운다.
5. **유휴 구간(90일), 화면 카드(180일), AI 도구 요청과 파일 이벤트(365일):** 같은 방식으로 지운다.
6. **스크린샷 경로:** 스크린샷 폴더가 삭제된 날의 `observations.screenshot_path`와 `screen_cards.screenshot_path`를 `NULL`로 바꾼다. 기존 `cleanupOldCaptures`에도 같은 처리를 추가해 현행 끊긴 경로 문제(1.4-3)를 함께 고친다.
7. `sealed_until`과 `*_pruned_until`을 갱신한다.

### 6.3 재구성 보호 (`GraphRebuilder` 수정)

**지금은** 세션과 세션 엣지를 모두 지우고 업무 시간을 0으로 초기화한다(1.4-5).

**바꾼 뒤에는**
- `sealed_until` 이전에 시작한 세션과 그 엣지는 지우지 않는다. 그 이후의 관측만 다시 계산한다.
- 업무의 `active_seconds`는 동결된 사용 시간 기록 합계에 재계산분을 더한 값이다. `project_seconds`도 같은 방식이다.
- 앱에 재구성 기능을 붙일 계획이 있다면 이 보호가 먼저 들어가야 한다.

### 6.4 공간 회수

**첫 정리 때 한 번**
- `PRAGMA auto_vacuum = INCREMENTAL;`을 설정하고 `VACUUM`을 실행한다(GRDB `DatabasePool.vacuum()`).
- DB 크기만큼 임시 공간이 필요하므로, 디스크 여유가 DB 크기의 2배 미만이면 건너뛰고 다음에 다시 시도한다.

**매번 정리 뒤**
- `PRAGMA incremental_vacuum(N)`로 빈 페이지를 반환한다.
- 각 FTS 테이블에 `INSERT INTO <fts>(<fts>) VALUES('optimize')`로 세그먼트를 병합한다.
- `PRAGMA wal_checkpoint(TRUNCATE)`를 실행한다.

### 6.5 미리보기와 내보내기

- **미리보기:** `Pruner.plan(now:)`가 지울 행 수, 기간, 예상 회수 바이트를 돌려준다. `wgctl consolidate --dry-run`과 앱의 미리보기 화면이 같은 함수를 쓴다.
- **내보내기(선택, 기본 꺼짐):** 지우기 전에 그 주의 원문을 `exports/raw-2026-W41.jsonl.gz`로 남긴다. 켜면 용량 절감 효과가 줄어든다는 점을 설정 화면에 표시한다.

---

## 7. 채팅·보고서 연결

### 7.1 새 출처 유형 `digest:`

- **검색:** `ContextSearch.search`가 `digests_fts`도 검색한다. 제목은 "주간 요약 · {업무명} · 2026-W41" 형식이다.
- **접근 필터:** `task_key`를 업무 ID로 바꿔, 기존 `taskRestriction`을 그대로 적용한다.
- **읽기:** `read_context("digest:ID")`는 body, metrics, anchors를 돌려준다. 첫 줄에는 "AI 요약 · 수치는 사용 시간 기록 · 원문은 {날짜} 이전 정리됨"을 표시한다.
- **출처 칩:** 채팅 출처 칩과 "확인되지 않은 근거" 판정이 인식하는 접두어 목록에 `digest:`를 추가한다(`ChatMessageText.swift`).

### 7.2 새 도구 `summarize_period(from, to, task?)`

- 사용 시간 기록으로 기간·업무별 시간, 자료 상위, 앱 분포를 결정적으로 계산하고, 문제와 할 일의 변화는 그래프에서 계산한다.
- 보고서 프롬프트 개선 때 필요하다고 정리한 기간 집계 도구와 같은 것이다. 원문이 있는 기간이든 없는 기간이든 같은 수치를 돌려준다.

### 7.3 시스템 프롬프트 초안 (`docs/prompts/chat-system-prompt.md`) 수정

| 섹션 | 수정 |
|---|---|
| Grounding의 출처 신뢰도 목록 | 다음 항목을 추가한다: "Weekly and monthly digests: AI summaries of periods whose raw records were removed. Their numbers come from the usage ledger and are reliable; their wording is not original." |
| Reports from the user's context의 Numbers | 기간 시간과 건수는 `summarize_period`를 우선 쓰도록 바꾼다. |
| 기록이 없을 때의 표현 | 원문이 정리된 기간에는 "원문은 정리되어 요약만 남아 있습니다"라고 쓰게 한다. |
| `<runtime_context>` | `raw_records_since: {{date}}`를 추가해 모델이 원문이 언제부터 있는지 알게 한다. |

---

## 8. UI·설정

- **설정 > 저장 공간**
  - 범주별 사용량: 스크린샷, 화면 텍스트, 배치 로그, 요약·사용 시간 기록, 그래프, 채팅·보관함
  - 최근 30일 증가량
  - 보관 정책 프리셋과 고급 항목별 보관일
  - "지금 정리" 버튼과 미리보기
  - 기존 "스크린샷 보관 N일" 스테퍼는 이 화면으로 옮기고, 라벨을 실제 대상에 맞게 고친다.
- **첫 정리 확인 시트:** 정리될 기간, 항목, 회수 용량, 만들어진 요약 미리보기를 보여주고 동의를 받는다. 동의한 뒤부터 자동으로 정리한다.
- **업무 화면 "요약" 탭:** 업무별 주간·월간 다이제스트 목록이다. 편집할 수 있고, 편집하면 `edited` 상태가 된다.
- **보존 핀:** 업무 상세에서 "원문 보존", 활동 로그에서 "이 기간 보존"으로 건다.
- **README:** 개인정보·보관 기간 설명을 새 정책에 맞게 고친다.

---

## 9. 개인정보·접근 범위

- **데이터 최소화:** 정리는 화면 텍스트 원문을 지우므로 데이터 최소화 효과가 있다. 사용자에게 알릴 이점이다.
- **추가 전송:** 다이제스트를 만들 때 업무 요약과 자료 제목을 정리용 LLM에 다시 보낸다. 설정의 정리용 LLM 설명에 이 사실을 넣고, 다이제스트 서술을 끄는 옵션을 둔다. 끄면 결정적 다이제스트만 만든다.
- **프로젝트 전용 모드:** 다이제스트는 업무별로만 저장하므로 `project_tasks` 기준 필터가 그대로 적용된다. 여러 업무를 묶은 전체 요약은 조회할 때 접근 범위 안에서만 조합한다.
- **업무 삭제·병합:** 업무를 삭제하면 해당 다이제스트와 사용 시간 기록 행을 지운다. 병합하면 `task_key`를 새 key로 바꾼다(`TaskMerger` 경로에 훅을 단다).

---

## 10. 예외 상황

| 상황 | 처리 |
|---|---|
| 주말 내내 앱이 꺼져 있었음 | 다음 실행 때 밀린 기간을 순서대로 처리한다(실행당 2주 상한) |
| LLM 실패·로그인 만료 | 결정적 다이제스트로 대체하고 `draft`로 둔다. 원문은 지우지 않고 다음 실행에서 재시도한다 |
| 정리 배치가 밀려 있음 | 기간을 닫지 않는다 |
| 시간대 변경·서머타임 | 기간은 생성 시점의 현지 날짜 문자열과 `tz`로 저장한다. 사용 시간 기록의 `day`도 현지 날짜다 |
| 업무 이름 변경·병합 | 원문이 남은 기간은 재생성하고, 정리된 기간은 key만 바꾼다 |
| 디스크 여유 부족 | 전체 `VACUUM`은 건너뛰고 `incremental_vacuum`만 실행한다 |
| 앱이 동시에 두 개 실행됨 | `InstanceLock`을 가진 인스턴스에서만 `Consolidator`를 실행한다 |
| 핀이 걸린 업무와 다른 업무가 섞인 날 | 핀이 걸린 업무의 관측과 텍스트만 남긴다 |
| 수집 일시정지·제외 앱 | 원래 원문이 없다. 다이제스트에는 "기록 없음"으로 표시하고 활동이 없었다고 쓰지 않는다 |

---

## 11. 파일 구조

```text
Sources/WorkGraphCore/
  Storage/StorageUsage.swift        범주별 사용량 (dbstat, 없으면 SUM(LENGTH) 추정) + 폴더 크기
  Storage/RetentionPolicy.swift     프리셋·항목별 보관일·핀
  Storage/Pruner.swift              plan(now:) / execute(plan:) / reclaimSpace()
  Memory/ActivityTally.swift        관측 → 행 → dwell 합산 (GraphRebuilder와 공용)
  Memory/LedgerBuilder.swift        usage_ledger 일 단위 갱신·동결
  Memory/DigestInput.swift          업무·주 단위 입력 조립
  Memory/DigestPrompt.swift         프롬프트 + JSON 스키마 + prompt_version
  Memory/DigestBuilder.swift        LLM 호출·렌더링·결정적 대체
  Memory/DigestValidator.swift      숫자·앵커·근거 상태·길이 검증
  Memory/Consolidator.swift         actor. 트리거·기간 닫힘 판정·처리량 상한·순서
  Chat/ChatTools.swift              summarize_period 추가, digest: 읽기
  Chat/ContextSearch.swift          digests_fts 검색, 접근 필터
  Ontology/GraphRebuilder.swift     sealed_until 보호, ActivityTally 사용
  Ontology/OntologyBatcher.swift    system_prompt_hash 저장
Sources/WorkGraphCollectors/
  CollectorCoordinator.swift        스크린샷 삭제 시 경로 NULL 처리
Sources/WorkGraphApp/
  Views/StorageSettingsView.swift   저장 공간·정책·미리보기·첫 동의
  Views/TasksView.swift             요약 탭
Sources/wgctl/main.swift            storage, consolidate [--dry-run], digest show
Tests/WorkGraphCoreTests/
  StorageUsageTests.swift  LedgerTests.swift  DigestValidatorTests.swift
  ConsolidatorTests.swift  PrunerTests.swift  RebuildSealTests.swift
```

---

## 12. 단계별 구현

순서대로 진행한다. 각 단계가 끝날 때마다 `swift build && swift test`가 통과해야 하고, 단계별 검증 명령을 실행한다.

### Phase 0. 측정과 가시화

- [ ] `StorageUsage`: 범주별 바이트를 계산한다. 앱이 링크한 SQLite에 `dbstat`이 있는지 먼저 확인하고, 없으면 `SUM(LENGTH())`와 페이지 수로 추정한다.
- [ ] `wgctl storage`: 범주별 크기, 최근 30일 일평균 증가량, 빈 페이지 수를 출력한다.
- [ ] 설정에 저장 공간 섹션을 추가한다(읽기 전용).
- [ ] 스크린샷 삭제 시 끊긴 경로를 `NULL`로 바꾼다(현행 버그).
- [ ] 테스트: 범주 합계가 파일 크기와 오차 범위 안에서 일치, 경로 정리.
- **검증:** `swift run wgctl storage`의 출력이 1.3의 실측과 일치한다.

### Phase 1. 사용 시간 기록과 배치 로그 경량화

- [ ] 마이그레이션 `v15-consolidation`: `usage_ledger`, `consolidation_state`, `retention_pins`, `prompt_blobs`, `batches.system_prompt_hash`
- [ ] `ActivityTally`를 분리하고 `GraphRebuilder`가 사용하게 한다.
- [ ] `LedgerBuilder`: 일 단위 멱등 갱신, `frozen` 존중
- [ ] `OntologyBatcher`가 시스템 프롬프트를 해시로 저장하게 하고, 기존 행을 이관한다. 활동 로그 화면 조회도 수정한다.
- [ ] `summarize_period` 도구를 추가한다(ChatTools, 도구 설명, 표시 이름).
- [ ] 테스트
  - 같은 입력에서 사용 시간 기록 업무 합계 = 세션 `active_seconds` 합계
  - 같은 날을 두 번 갱신해도 결과가 같음
  - 자정·시간대 경계
  - 프롬프트 이관 후 활동 로그 표시
- **검증:** `swift run wgctl consolidate --ledger-only` 실행 뒤, 업무 화면의 시간과 사용 시간 기록 합계를 비교한다.

### Phase 2. 다이제스트

- [ ] 마이그레이션: `digests`, `digests_fts`와 트리거
- [ ] `DigestInput`, `DigestPrompt`, `DigestBuilder`(주·월), 렌더러
- [ ] `DigestValidator`
- [ ] `Consolidator`: 트리거, 기간 닫힘 조건, 처리량 상한, 결정적 대체
- [ ] `ContextSearch`와 `read_context`에 `digest:` 출처를 추가하고, 접근 필터와 출처 칩 접두어를 반영한다.
- [ ] 시스템 프롬프트 초안 수정(7.3)
- [ ] 테스트
  - 검증기가 거부하는 경우: 없는 숫자, 없는 앵커, 근거 없는 `evidenced`, 길이 초과
  - 기간 닫힘 조건 세 가지
  - 프로젝트 전용 격리
  - 업무 병합 뒤 key
  - LLM 실패 시 `draft`
- **검증:** `swift run wgctl digest show --week 2026-W40`으로 데모 데이터의 다이제스트를 확인한다.

### Phase 3. 정리 엔진

- [ ] `RetentionPolicy`(프리셋, 항목별 일수), 핀
- [ ] `Pruner.plan`, `execute`, `reclaimSpace`
- [ ] `GraphRebuilder`의 `sealed_until` 보호와 업무 시간 합산 방식 변경
- [ ] `auto_vacuum` 전환(1회 `VACUUM`, 디스크 여유 확인), `incremental_vacuum`, FTS `optimize`, WAL `TRUNCATE`
- [ ] `wgctl consolidate [--dry-run]`
- [ ] 테스트
  - 다이제스트가 `draft`인 기간은 삭제 안 함
  - 유예 7일
  - 핀(업무·기간)
  - 해시를 공유하는 텍스트는 보존
  - 외래 키 순서
  - 재구성 뒤에도 동결 기간 세션과 업무 시간 유지
  - 정리 뒤 파일 크기 감소
- **검증:** 실제 DB 사본으로 `--dry-run`을 돌리고, 실행한 뒤 `wgctl storage`로 회수량을 확인한다.

### Phase 4. UI

- [ ] `StorageSettingsView`: 사용량, 프리셋, 고급, 미리보기, 첫 동의 시트
- [ ] 업무 화면 요약 탭, 편집
- [ ] 핀 UI(업무 상세, 활동 로그)
- [ ] README 개인정보·보관 기간 문구

### Phase 5. 평가와 출시

- [ ] **요약 충실도:** `docs/eval`의 세 페르소나 데이터로, 원문으로 답할 수 있는 질문 20개를 요약만으로 답하게 하고 정답률을 잰다. 시간·건수 질문은 100% 일치해야 통과다.
- [ ] **보고서 품질:** 같은 기간 주간 보고서를 원문 기반과 요약 기반으로 만들어 비교한다. 채점 기준은 보고서 프롬프트 평가표를 쓴다.
- [ ] **기존 사용자 이관:** 첫 실행에서는 밀린 기간의 요약만 만들고, 삭제는 동의 뒤에 한다.
- [ ] **출시 후 측정:** 2주 사용 뒤 DB 크기 추이와 다이제스트 토큰 사용량을 확인한다.

---

## 13. 기대 효과 (추정)

1.3의 실측을 활동일 250일/년으로 외삽했다. 기본 프리셋(화면 텍스트 30일) 기준이다.

| 항목 | 현재 방식, 1년 뒤 | 정리 후, 1년 뒤 |
|---|---|---|
| 화면 텍스트 + 색인 | 약 355MB | 약 30MB (최근 30일분) |
| 배치 로그 | 약 150MB | 약 6MB (전문 14일분 + 통계) |
| 관측 | 약 13MB | 약 3MB (90일분) |
| 화면 카드 | 약 20MB | 약 10MB (180일분) |
| 그래프 | 약 17MB | 약 17MB (유지) |
| 사용 시간 기록 + 다이제스트 | — | 약 2MB |
| 기타 (AI 도구 요청, 파일 이벤트, 인덱스) | 약 35MB | 약 12MB |
| **DB 합계** | **약 600MB, 계속 증가** | **약 80MB, 이후 연 20MB 내외 증가** |
| 스크린샷 | 35~50MB (7일) | 변화 없음 |

**LLM 사용량:** 주간 다이제스트 입력은 업무당 6k 토큰 이하다. 주당 활성 업무가 5~10개라고 가정하면 주 30~60k 입력 토큰이고, 월간 다이제스트는 그보다 작다. Phase 5에서 실측한다.

---

## 14. 위험과 결정할 사항

| 항목 | 내용 | 제안 |
|---|---|---|
| 요약 품질이 원문을 대신할 만한가 | Phase 5 평가로 판단한다 | 기준에 못 미치면 기본 프리셋을 "길게(90일)"로 올린다 |
| 기본값 | 화면 텍스트 30일, 유예 7일, 관측 90일, 카드 180일 | 팀 결정 필요 |
| 첫 정리 동의 방식 | 확인 시트 1회 vs 매번 알림 | 1회 동의 + 매 정리 후 결과 알림 |
| `dbstat` 가용성 | 앱이 링크한 SQLite에서 확인 필요 | 없으면 추정치 사용 |
| 다이제스트 서술 생성 | 정리용 LLM에 요약을 다시 보낸다 | 끌 수 있는 옵션 제공 |
| 원문을 계속 남기고 싶은 사용자 | — | "원문 무기한" 프리셋 |
| 앱 내 재구성 기능 | 현재는 `wgctl`에만 있다 | 앱에 넣기 전에 6.3 보호가 필수 |
| 채팅·보관함 용량 | 사용자 자료라 자동 정리 대상이 아니다 | 저장 공간 화면에 크기만 표시하고 수동 정리 |
