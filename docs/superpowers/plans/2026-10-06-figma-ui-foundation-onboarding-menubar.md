# Figma UI 1차 (바탕, 메뉴 막대, 온보딩) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 인성님 브랜치(Figma 디자인 적용)를 합치고, 메뉴 막대와 온보딩을 Figma 화면 그대로 만든다. 글꼴(SUIT·Jost)을 앱에 넣어 어느 Mac 에서나 같게 보이게 한다.

**Architecture:** 상태를 고르는 규칙(메뉴 막대 화면, 온보딩 단계, 알림 문구)은 `WorkGraphCore` 에 순수 함수로 두고 XCTest 로 고정한다. 화면은 `WorkGraphApp` 의 SwiftUI 뷰가 그 규칙을 읽어 그린다. 화면 확인은 앱을 띄우지 않는 스냅샷 실행(`WORKGRAPH_SNAPSHOT`)으로 상태별 PNG 를 만들어 Figma PNG 와 나란히 본다.

**Tech Stack:** SwiftPM(swift-tools 5.10, macOS 14, Swift 5 모드), SwiftUI, CoreText, XCTest, 헤드리스 Chrome(그래프 페이지 확인용)

**Spec:** `docs/superpowers/specs/2026-10-06-figma-ui-foundation-onboarding-menubar-design.md`

## Global Constraints

- 플랫폼·도구: macOS 14 이상, Swift 5 모드, 새 패키지 의존성 없음.
- Figma 가 기준이다: 파일 `wuNWJI6TT6TLml7pGaxn65`, 페이지 `4:2565`. 문구는 Figma 그대로(해요체).
- 글꼴: SUIT(400·500·600·700)와 Jost(400, 큰 숫자 200). 파일은 `Sources/WorkGraphApp/Resources/Brand/Fonts`, OFL 라이선스 파일을 같이 둔다. 프로세스 범위로만 등록한다(시스템에 설치하지 않음).
- 커밋·푸시하지 않는다(사용자가 요청할 때만). 인성님 브랜치는 `git merge --no-commit` 으로 합쳐 둔다. 작업 중 `git add` 하지 않는다 — 나중에 "합치기 커밋"(지금 인덱스)과 "작업 커밋"을 나누기 위해서다.
- 사용자가 쓰는 앱(`~/Applications/Sillog.app`)과 데이터(`~/Library/Application Support/WorkGraph`)는 건드리지 않는다. `scripts/make-app.sh` 는 설치까지 하므로 돌리지 않는다.
- Figma 토큰은 `~/.figma-token`. 출력하지도, 저장소에 넣지도 않는다.
- 경로 약속: `SCRATCH=/private/tmp/claude-501/-Users-suhwan-Desktop-5-1-ai-------2/eed2b7a1-5b4f-4efa-ad08-b3ac1b928982/scratchpad` (세션 스크래치, 공백 없음). Figma PNG 는 `$SCRATCH/figma/out/<화면>.png`.

## Review Focus

1. 이미 온보딩을 마친 계정이 로그아웃 후 다시 로그인 → 시트가 1단계에서 "로그인 완료, 다음"을 켜고, 누르면 2단계로 가지 않고 닫혀야 한다. (Task 3 `testReloginOfFinishedAccountShowsSuccessThenCloses`)
2. 온보딩 2단계에서 "다시 실행" → 새 실행이 1단계가 아니라 2단계를 띄우고, '이미 실행 중'(W3)에 막히지 않아야 한다. (Task 3 `testRelaunchDuringPermissionsReopensStepTwo`, 기존 `InstanceLockTests`, Task 4 의 잠금 먼저 놓기)
3. 앱이 막 켜져 수집기가 권한을 아직 알려 주지 않은 순간 → 메뉴가 W6(권한 경고)로 깜빡이지 않아야 한다. (Task 3 `testPermissionsUnknownBeforeFirstReportDoNotWarn`)
4. 기록이 1000개를 넘거나 업무 이름이 아주 길 때 → 큰 숫자는 줄바꿈 없이 줄어들고, 업무 이름은 한 줄로 잘려야 한다. (Task 3 `testTwoDigitsKeepsLargeNumbers`, Task 5 스냅샷 `OUT-06-long`)
5. 글꼴 폴더를 못 찾는 실행 → 앱은 시스템 글꼴로 그대로 떠야 한다. (Task 2 `testMissingFolderRegistersNothing`)

## 이미 정한 것 (스펙에 없던 세부)

- Jost 파일은 indestructible-type/Jost(커밋 35f141c, OFL)의 `Jost-400-Book.otf`·`Jost-200-Thin.otf`. 패밀리 이름이 "Jost*" 라서 PostScript 이름(`Jost-Book`, `Jost-Thin`)으로 부른다. SUIT 는 sun-typeface/SUIT(커밋 55118d9)의 static otf.
- W1·W5 의 Inter 500 눈썹 글씨는 Jost 400 으로 그린다.
- OUT-02 의 "이 코드는 미리보기용…" 줄은 Figma 시안용 문구라 뺀다. 기기 코드 상자에 취소·회전 표시는 Figma 대로 두지 않는다. 코드를 받은 뒤 "ChatGPT로 로그인"은 승인 페이지를 다시 연다.
- 로그인을 마친 뒤 1단계에는 로그인 버튼 대신 "SIGNED IN" 상자(계정 이메일)를 둔다(Figma 에 없는 상태).
- "수집 시작"은 언제나 누를 수 있고, 두 권한이 있고 다시 실행할 일이 없을 때만 진하다(Figma OUT-03·04·05 모두 흐림). 화면 기록을 이번 실행에서 요청했으면 "다시 실행" 줄을 늘 보인다(OUT-05).
- 시트는 시스템 sheet 가 아니라 창 안 덮개(overlay)로 그린다. 시스템 sheet 는 제목 줄에 붙어 Figma 위치(탭 막대 아래)가 안 나온다.
- 제목 줄의 "■ 기록 중"은 준비된 뒤에만 보인다(Figma OUT-01 은 온보딩 중에도 보이지만 사실과 다르다).
- 메뉴 W2 문구: 권한 단계 중이면 "시작하려면 권한 설정을 마쳐 주세요", 시작 실패면 "Sillog을 시작하지 못했어요".
- 보관함 탭은 그대로 둔다(Figma 6탭). 파일 탭 옆에 대기 제안 수 배지를 단다.
- 파일 정리 알림: 부제(이유)는 뺀다. 폴더는 "문서 / 통계학" 처럼 보인다. 을/를은 마지막 한글 받침으로, 확장자로 끝나면 Figma 처럼 "을".
- 그래프: 인성님 페이지는 분야를 '상위 분류'로 묶어 기본 보기(연결망)에서 무리 이름으로 그리고, 상세 카드에 분야 점·이름을 붙인다. 스펙의 graph.js 용 항목(분야 노드 크기, 이름이 보이는 거리, 연결 간격, 연결 목록 문구)은 이 페이지에 해당 요소가 없어 따로 하지 않는다. 메뉴에 없는 숨은 `sky` 보기는 손대지 않는다.
- 확인은 앱을 하나 더 띄우는 대신 스냅샷 실행으로 한다(창·DB·잠금을 만들지 않음). 제목 줄 크롬은 스냅샷에 안 나온다.

---

### Task 1: 인성님 브랜치 합치기, 그래프 페이지에 분야 옮기기

인성님 `graph/index.html` 은 업무를 '상위 분류'(THEMES)로 묶어 모든 보기(연결망·업무 지도·원형 비중·가지 도표)와 왼쪽 CATEGORY 목록을 그린다. 지금은 업무 종류(TaskType)의 최상위로 묶는다. 이것을 분야(`Task PART_OF Theme`)로 바꾸면 모든 보기에 분야가 나온다. 분야가 하나도 없으면(분야 붙이기를 끈 경우) 예전처럼 업무 종류로 묶는다.

**Files:**
- Merge: `origin/인성/CAT-58` (23개 파일, 충돌 없음 — `git merge-tree` 로 확인함)
- Modify: `Sources/WorkGraphApp/Resources/graph/index.html` (합친 뒤의 `loadGraph`)
- Create (작업 폴더, git 에 들어가지 않음): `$WS/graph-check.sh`

**Interfaces:**
- Consumes: 없음
- Produces: 합친 트리(인성님 `BrandStyle.swift` 의 `Brand`, `Eyebrow`, `BehindWindowGlass`, `glassPill`, `Color(hex:opacity:)`, `Resources/Brand/wordmark.png`, `MenuBarView`, `OnboardingView`, `MainWindow`). 이후 Task 가 이 파일들을 고친다.

- [ ] **Step 1: 합치기 (커밋하지 않음)**

```bash
cd "/Users/suhwan/Desktop/5-1/ai 캡스톤디자인2/WorkGraph"
git merge --no-commit --no-ff origin/인성/CAT-58
git status --short | head -30
```
Expected: `Automatic merge went well; stopped before committing as requested`, 23개 파일이 staged.

- [ ] **Step 2: 빌드와 전체 테스트**

```bash
swift build --product WorkGraphApp 2>&1 | tail -15
swift test 2>&1 | tail -3
```
Expected: 빌드 성공, `Executed 245 tests, with 0 failures`. 인성님 뷰가 우리 쪽에서 바뀐 API 를 불러 컴파일 오류가 나면, 인성님 화면 동작을 유지하는 가장 작은 수정을 하고 ledger 에 Ruling 으로 남긴다.

- [ ] **Step 3: 그래프 페이지 확인 스크립트 작성**

`$WS/graph-check.sh` (`WS` 는 `sdd-workspace` 가 알려 준 작업 폴더):

```bash
#!/bin/bash
# 그래프 페이지(index.html)에 작은 그래프를 넣고 헤드리스 Chrome 으로 그려, 업무 지도(map) 보기의
# 통계 줄과 CATEGORY(상위 분류) 목록을 출력한다. 사용: graph-check.sh <출력 폴더>
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
OUT="${1:?출력 폴더}"
mkdir -p "$OUT"
python3 - "$ROOT/Sources/WorkGraphApp/Resources/graph/index.html" "$OUT" <<'PY'
import json, sys, time, pathlib
src, out = pathlib.Path(sys.argv[1]).read_text(), pathlib.Path(sys.argv[2])
now = time.time()
def node(i, label, title, **props):
    return {"id": i, "label": label, "key": f"{label}:{title}", "title": title, "subtype": None, "props": props}
nodes = [node(1, "TaskType", "정보수집"), node(2, "TaskType", "문헌조사"),
         node(10, "Task", "캡스톤 보고서"), node(11, "Task", "자기소개서"),
         node(20, "Theme", "캡스톤"), node(21, "Theme", "취업 준비"),
         node(30, "Session", "s1", start=now - 7200, end=now - 5400, summary="보고서 초안"),
         node(31, "Session", "s2", start=now - 3600, end=now - 1800, summary="자기소개서 수정")]
links = [{"source": 2, "target": 1, "type": "SUBCLASS_OF"},
         {"source": 10, "target": 2, "type": "INSTANCE_OF"}, {"source": 11, "target": 2, "type": "INSTANCE_OF"},
         {"source": 10, "target": 20, "type": "PART_OF"}, {"source": 11, "target": 21, "type": "PART_OF"},
         {"source": 30, "target": 10, "type": "PART_OF"}, {"source": 31, "target": 11, "type": "PART_OF"}]
def page(name, data):
    inject = "<script>window.__WG_DATA__=" + json.dumps(data, ensure_ascii=False) + ";</script>"
    (out / f"{name}.html").write_text(src.replace("<script>", inject + "<script>", 1))
page("with-themes", {"nodes": nodes, "links": links})
page("without-themes", {"nodes": [n for n in nodes if n["label"] != "Theme"],
                        "links": [l for l in links if l["target"] not in (20, 21)]})
PY
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for name in with-themes without-themes; do
  URI=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$OUT/$name.html")
  "$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
    --user-data-dir="$OUT/profile" --virtual-time-budget=5000 --dump-dom "$URI?mode=map" > "$OUT/$name.dom" 2>/dev/null
  python3 - "$name" "$OUT/$name.dom" <<'PY'
import html, re, sys
name, dom = sys.argv[1], open(sys.argv[2]).read()
stats = re.search(r'<p id="stats"[^>]*>(.*?)</p>', dom, re.S)
legend = re.search(r'<ul class="legend" id="themes">(.*?)</ul>', dom, re.S)
print(f"{name}: stats=" + (html.unescape(stats.group(1)) if stats else "없음"))
print(f"{name}: legend=" + (" ".join(re.sub(r"<[^>]+>", " ", html.unescape(legend.group(1))).split()) if legend else "없음"))
PY
done
```

- [ ] **Step 4: 바꾸기 전에 돌려서 실패 확인**

```bash
bash "$WS/graph-check.sh" "$SCRATCH/graph-check"
```
Expected (RED): `with-themes: stats=업무 2개, 상위 분류 1개, …`, legend 에 `정보수집` 만 있고 `캡스톤`·`취업 준비` 가 없다.

- [ ] **Step 5: `loadGraph` 를 분야 기준으로 바꾸기**

`index.html` 의 `loadGraph` 안, 이 부분을

```js
    const themeOf = new Map(), tops = new Map();
    links.forEach(l => {
      if (l.type !== 'INSTANCE_OF' || !N.get(l.source) || N.get(l.source).label !== 'Task') return;
      const t = top(l.target); themeOf.set(l.source, t); if (N.get(t)) tops.set(t, N.get(t));
    });
```

이렇게 바꾼다:

```js
    // 상위 분류 = 업무가 속한 분야(Task PART_OF Theme). 분야가 하나도 없으면(분야 붙이기를 끈 경우) 업무 종류의 최상위로 묶는다
    const themeOf = new Map(), tops = new Map();
    const isField = l => l.type === 'PART_OF' && N.get(l.source) && N.get(l.source).label === 'Task' && N.get(l.target) && N.get(l.target).label === 'Theme';
    const byField = links.some(isField);
    links.forEach(l => {
      if (byField) {
        if (isField(l)) { themeOf.set(l.source, l.target); tops.set(l.target, N.get(l.target)); }
        return;
      }
      if (l.type !== 'INSTANCE_OF' || !N.get(l.source) || N.get(l.source).label !== 'Task') return;
      const t = top(l.target); themeOf.set(l.source, t); if (N.get(t)) tops.set(t, N.get(t));
    });
```

그리고 위 설명 주석 두 줄 중 `// 업무 = Task, 상위 분류 = 업무 종류(TaskType)의 최상위, …` 를 `// 업무 = Task, 상위 분류 = 분야(Theme, 없으면 업무 종류의 최상위), …` 로 고친다.

- [ ] **Step 6: 다시 돌려서 통과 확인**

```bash
bash "$WS/graph-check.sh" "$SCRATCH/graph-check"
```
Expected (GREEN): `with-themes: stats=업무 2개, 상위 분류 2개, 세션 2개`, legend 에 `캡스톤`·`취업 준비`. `without-themes: … 상위 분류 1개`, legend 에 `정보수집`.

- [ ] **Step 7: 체크포인트 (커밋 안 함)**

```bash
git status --short | head -40; git diff --stat
```
Expected: staged 23개(합치기) + unstaged `index.html`.

---

### Task 2: SUIT·Jost 글꼴 넣고 등록하기

**Files:**
- Create: `Sources/WorkGraphApp/Resources/Brand/Fonts/` 에 `SUIT-Regular.otf`, `SUIT-Medium.otf`, `SUIT-SemiBold.otf`, `SUIT-Bold.otf`, `Jost-400-Book.otf`, `Jost-200-Thin.otf`, `OFL-SUIT.txt`, `OFL-Jost.txt`
- Create: `Sources/WorkGraphCore/Storage/FontRegistry.swift`
- Create: `Tests/WorkGraphCoreTests/FontRegistryTests.swift`
- Modify: `Sources/WorkGraphApp/Views/BrandStyle.swift` (Jost 이름, `paper`, `jostLight`, `BrandFonts`)
- Modify: `Sources/WorkGraphApp/WorkGraphApp.swift` (`@main` 을 `AppEntry` 로)

**Interfaces:**
- Consumes: Task 1 의 `BrandStyle.swift`
- Produces: `FontRegistry.register(directory: URL) -> [String]` (Core), `BrandFonts.register() -> [String]` (@discardableResult), `Brand.jost(_:)` = "Jost-Book", `Brand.jostLight(_:)` = "Jost-Thin", `Brand.paper` = #F6F5F4, `@main enum AppEntry`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/WorkGraphCoreTests/FontRegistryTests.swift`:

```swift
import CoreText
import XCTest
@testable import WorkGraphCore

final class FontRegistryTests: XCTestCase {
    /// 앱에 넣은 글꼴 폴더 (저장소 안 경로)
    private var brandFonts: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WorkGraphApp/Resources/Brand/Fonts", isDirectory: true)
    }

    func testBundledFontsRegisterUnderTheNamesTheViewsUse() {
        let names = Set(FontRegistry.register(directory: brandFonts))
        // BrandStyle 의 Brand.suit(…) 은 "SUIT-<굵기>", Brand.jost 는 "Jost-Book", Brand.jostLight 는 "Jost-Thin" 을 부른다
        XCTAssertEqual(names, ["SUIT-Regular", "SUIT-Medium", "SUIT-SemiBold", "SUIT-Bold", "Jost-Book", "Jost-Thin"])
        for name in names {
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name, "\(name) 이 다른 글꼴로 대체됨")
        }
    }

    func testRegisteringTwiceStillReportsTheFonts() {
        _ = FontRegistry.register(directory: brandFonts)
        XCTAssertEqual(FontRegistry.register(directory: brandFonts).count, 6)
    }

    func testMissingFolderRegistersNothing() {
        XCTAssertEqual(FontRegistry.register(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")), [])
    }
}
```

- [ ] **Step 2: 돌려서 실패 확인**

Run: `swift test --filter FontRegistryTests 2>&1 | tail -5`
Expected: 컴파일 실패 `cannot find 'FontRegistry' in scope`.

- [ ] **Step 3: 글꼴 파일과 라이선스 넣기**

```bash
F="Sources/WorkGraphApp/Resources/Brand/Fonts"; mkdir -p "$F"
for w in Regular Medium SemiBold Bold; do
  curl -sSfL -m 60 -o "$F/SUIT-$w.otf" "https://raw.githubusercontent.com/sun-typeface/SUIT/55118d9813/fonts/static/otf/SUIT-$w.otf"
done
for f in Jost-400-Book Jost-200-Thin; do
  curl -sSfL -m 60 -o "$F/$f.otf" "https://raw.githubusercontent.com/indestructible-type/Jost/35f141c970/fonts/otf/$f.otf"
done
curl -sSfL -m 30 -o "$F/OFL-SUIT.txt" https://raw.githubusercontent.com/sun-typeface/SUIT/55118d9813/LICENSE
curl -sSfL -m 30 -o "$F/OFL-Jost.txt" https://raw.githubusercontent.com/indestructible-type/Jost/35f141c970/OFL.txt
ls -la "$F"; file "$F"/*.otf
```
Expected: otf 6개(`OpenType font data`), txt 2개. (같은 파일이 `$SCRATCH/fonts` 에 이미 있으면 복사해도 된다.)

- [ ] **Step 4: `FontRegistry` 구현**

`Sources/WorkGraphCore/Storage/FontRegistry.swift`:

```swift
import CoreText
import Foundation

/// 앱에 넣은 글꼴 파일을 이 프로세스에서만 쓰도록 등록한다 (시스템에 설치하지 않는다)
public enum FontRegistry {
    /// Args: directory — .otf/.ttf 파일이 든 폴더.
    /// Returns: 등록됐거나 이미 등록·설치돼 있던 글꼴의 PostScript 이름. 폴더가 없으면 빈 목록.
    /// Raises: 없음. 읽지 못한 파일은 건너뛴다.
    public static func register(directory: URL) -> [String] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["otf", "ttf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var names: [String] = []
        for file in files {
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error)
            let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
            let usable = registered
                || code == CTFontManagerError.alreadyRegistered.rawValue
                || code == CTFontManagerError.duplicatedName.rawValue
            if usable { names += postScriptNames(file) }
        }
        return names
    }

    static func postScriptNames(_ file: URL) -> [String] {
        let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor]) ?? []
        return descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    }
}
```

- [ ] **Step 5: 돌려서 통과 확인**

Run: `swift test --filter FontRegistryTests 2>&1 | tail -5`
Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 6: `Brand` 와 앱 시작에 연결**

`BrandStyle.swift` 맨 위 import 에 `import WorkGraphCore` 를 더한다. `enum Brand` 안의

```swift
    /// 영문 눈썹 글씨와 숫자 Jost
    static func jost(_ size: CGFloat) -> Font { .custom("Jost", size: size) }
```

를 이렇게 바꾼다:

```swift
    static let paper = Color(hex: 0xF6F5F4)        // 칩과 오류 상자 바탕, 예전 스타일 창 바탕 (OUT-W1)

    /// 영문 눈썹 글씨와 숫자 Jost 400. 앱에 넣은 Jost* 판에서 400 의 이름은 "Jost-Book" (FontRegistryTests 가 확인)
    static func jost(_ size: CGFloat) -> Font { .custom("Jost-Book", size: size) }
    /// 큰 숫자 Jost 200 (Figma 의 ExtraLight, 앱에 넣은 판의 이름은 "Jost-Thin")
    static func jostLight(_ size: CGFloat) -> Font { .custom("Jost-Thin", size: size) }
```

`enum Brand { … }` 바로 아래에 더한다:

```swift
/// 앱에 넣은 SUIT·Jost 글꼴(Resources/Brand/Fonts)을 이 프로세스에만 등록한다. 못 찾으면 시스템 글꼴로 그려진다.
enum BrandFonts {
    @discardableResult
    static func register() -> [String] {
        // .app 은 Contents/Resources/Brand, swift run 은 리소스 번들. 앞이 있으면 뒤(Bundle.module)는 읽지 않는다
        let directory = Bundle.main.url(forResource: "Fonts", withExtension: nil, subdirectory: "Brand")
            ?? Bundle.module.url(forResource: "Fonts", withExtension: nil, subdirectory: "Brand")
        return directory.map { FontRegistry.register(directory: $0) } ?? []
    }
}
```

`WorkGraphApp.swift`: import 에 `import WorkGraphCore` 를 더하고, `@main struct WorkGraphApp: App {` 에서 `@main` 을 지운 뒤 파일 맨 위(import 아래)에 넣는다:

```swift
/// 시작점: 글꼴을 먼저 등록하고 SwiftUI 앱을 띄운다
@main
enum AppEntry {
    static func main() {
        let fonts = BrandFonts.register()
        if fonts.count < 6 { AppLog.write("글꼴 \(fonts.count)/6개만 등록됨: \(fonts.sorted())") }
        WorkGraphApp.main()
    }
}
```

- [ ] **Step 7: 빌드와 전체 테스트**

```bash
swift build --product WorkGraphApp 2>&1 | tail -5
swift test 2>&1 | tail -3
```
Expected: 빌드 성공, `Executed 248 tests, with 0 failures`. (실제 등록은 Task 4 스냅샷 출력의 `fonts:` 줄로 확인한다.)

---

### Task 3: 화면 규칙 (메뉴 막대, 온보딩, 알림 문구)

**Files:**
- Create: `Sources/WorkGraphCore/Models/MenuBarModel.swift`
- Create: `Sources/WorkGraphCore/Models/OnboardingFlow.swift`
- Create: `Sources/WorkGraphCore/Files/FileSuggestionCopy.swift`
- Modify: `Sources/WorkGraphCore/LLM/Codex/CodexAuthModels.swift` (`deviceLoginNotEnabled` 문구)
- Test: `Tests/WorkGraphCoreTests/MenuBarModelTests.swift`, `Tests/WorkGraphCoreTests/OnboardingFlowTests.swift`, `Tests/WorkGraphCoreTests/FileSuggestionCopyTests.swift`, `Tests/WorkGraphCoreTests/CodexAuthTests.swift` (테스트 1개 추가)

**Interfaces:**
- Consumes: `AppPhase` (.login/.permissions/.ready)
- Produces:
  - `enum MenuBarMode { case notReady, paused, permissionMissing, normal }`
  - `MenuBarModel.mode(phase:startupFailed:paused:running:accessibility:screenRecording:) -> MenuBarMode`
  - `MenuBarModel.notReadyMessage(phase:startupFailed:) -> String`
  - `MenuBarModel.statusText(mode:running:idle:) -> String?`
  - `MenuBarModel.twoDigits(_: Int) -> String`
  - `MenuBarModel.batchSummary(clock:newTasks:resources:) -> String`
  - `enum OnboardingStep { case login, permissions }`, `struct PermissionGrants(accessibility:screenRecording:)` + `.all`
  - `OnboardingFlow.step(after: OnboardingStep?, phase:) -> OnboardingStep?`, `.canAdvance(from:phase:) -> Bool`, `.advance(from:phase:) -> OnboardingStep?`, `.close(_: OnboardingStep?, phase:) -> OnboardingStep?`, `.startLooksReady(_: PermissionGrants, askedScreenRecording:) -> Bool`, `.sheetTop(available: CGFloat, card: CGFloat) -> CGFloat`
  - `FileSuggestionCopy.title`, `.body(fileName:folder:home:) -> String`, `.objectParticle(_:) -> String`, `.folderLabel(_:home:) -> String`

- [ ] **Step 1: 메뉴 막대 규칙 테스트 작성**

`Tests/WorkGraphCoreTests/MenuBarModelTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

final class MenuBarModelTests: XCTestCase {
    private func mode(_ phase: AppPhase = .ready, failed: Bool = false, paused: Bool = false, running: Bool = true,
                      ax: Bool = true, screen: Bool = true) -> MenuBarMode {
        MenuBarModel.mode(phase: phase, startupFailed: failed, paused: paused, running: running,
                          accessibility: ax, screenRecording: screen)
    }

    func testNotReadyWinsOverEverything() {
        XCTAssertEqual(mode(.login, paused: true, ax: false), .notReady)
        XCTAssertEqual(mode(.permissions), .notReady)
        XCTAssertEqual(mode(.ready, failed: true), .notReady)
    }

    func testPausedWinsOverMissingPermission() {
        XCTAssertEqual(mode(paused: true, ax: false, screen: false), .paused)
    }

    func testMissingEitherPermissionWarns() {
        XCTAssertEqual(mode(ax: false), .permissionMissing)
        XCTAssertEqual(mode(screen: false), .permissionMissing)
    }

    func testNormalWhenReadyWithBothPermissions() {
        XCTAssertEqual(mode(), .normal)
    }

    func testPermissionsUnknownBeforeFirstReportDoNotWarn() {
        // 앱이 막 켜져 수집기가 아직 권한을 알려 주지 않은 순간: 기본값(false) 때문에 W6 가 깜빡이면 안 된다
        XCTAssertEqual(mode(running: false, ax: false, screen: false), .normal)
    }

    func testTwoDigits() {
        XCTAssertEqual(MenuBarModel.twoDigits(0), "00")
        XCTAssertEqual(MenuBarModel.twoDigits(6), "06")
        XCTAssertEqual(MenuBarModel.twoDigits(9), "09")
        XCTAssertEqual(MenuBarModel.twoDigits(10), "10")
        XCTAssertEqual(MenuBarModel.twoDigits(62), "62")
        XCTAssertEqual(MenuBarModel.twoDigits(-3), "00")
    }

    func testTwoDigitsKeepsLargeNumbers() {
        XCTAssertEqual(MenuBarModel.twoDigits(1234), "1234")
    }

    func testBatchSummaryMatchesFigma() {
        XCTAssertEqual(MenuBarModel.batchSummary(clock: "14:05", newTasks: 1, resources: 3), "14:05 정리 완료(새 업무 1개, 자료 3개)")
    }

    func testNotReadyMessage() {
        XCTAssertEqual(MenuBarModel.notReadyMessage(phase: .login, startupFailed: false), "시작하려면 ChatGPT 로그인이 필요해요")
        XCTAssertEqual(MenuBarModel.notReadyMessage(phase: .permissions, startupFailed: false), "시작하려면 권한 설정을 마쳐 주세요")
        XCTAssertEqual(MenuBarModel.notReadyMessage(phase: .ready, startupFailed: true), "Sillog을 시작하지 못했어요")
    }

    func testStatusText() {
        XCTAssertNil(MenuBarModel.statusText(mode: .notReady, running: false, idle: false))
        XCTAssertEqual(MenuBarModel.statusText(mode: .paused, running: true, idle: false), "일시정지됨")
        XCTAssertEqual(MenuBarModel.statusText(mode: .permissionMissing, running: true, idle: false), "■ 수집 중")
        XCTAssertEqual(MenuBarModel.statusText(mode: .normal, running: true, idle: false), "■ 기록 중")
        XCTAssertEqual(MenuBarModel.statusText(mode: .normal, running: true, idle: true), "자리 비움")
        XCTAssertEqual(MenuBarModel.statusText(mode: .normal, running: false, idle: false), "시작하는 중")
    }
}
```

- [ ] **Step 2: 온보딩 규칙 테스트 작성**

`Tests/WorkGraphCoreTests/OnboardingFlowTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

final class OnboardingFlowTests: XCTestCase {
    func testFirstLoginStaysOnStepOneUntilNext() {
        XCTAssertEqual(OnboardingFlow.step(after: .login, phase: .permissions), .login)
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .login, phase: .permissions))
        XCTAssertEqual(OnboardingFlow.advance(from: .login, phase: .permissions), .permissions)
    }

    func testNextIsDisabledBeforeLogin() {
        XCTAssertFalse(OnboardingFlow.canAdvance(from: .login, phase: .login))
        XCTAssertEqual(OnboardingFlow.advance(from: .login, phase: .login), .login)
    }

    func testRelaunchDuringPermissionsReopensStepTwo() {
        XCTAssertEqual(OnboardingFlow.step(after: nil, phase: .permissions), .permissions)
    }

    func testFinishingPermissionsClosesSheet() {
        XCTAssertNil(OnboardingFlow.step(after: .permissions, phase: .ready))
    }

    func testReloginOfFinishedAccountShowsSuccessThenCloses() {
        XCTAssertEqual(OnboardingFlow.step(after: .login, phase: .ready), .login)
        XCTAssertTrue(OnboardingFlow.canAdvance(from: .login, phase: .ready))
        XCTAssertNil(OnboardingFlow.advance(from: .login, phase: .ready))
    }

    func testLogoutAlwaysReturnsToLogin() {
        XCTAssertEqual(OnboardingFlow.step(after: nil, phase: .login), .login)
        XCTAssertEqual(OnboardingFlow.step(after: .permissions, phase: .login), .login)
    }

    func testReadyLaunchShowsNoSheet() {
        XCTAssertNil(OnboardingFlow.step(after: nil, phase: .ready))
    }

    func testCloseKeepsUnfinishedStep() {
        XCTAssertEqual(OnboardingFlow.close(.permissions, phase: .permissions), .permissions)
        XCTAssertEqual(OnboardingFlow.close(.login, phase: .login), .login)
        XCTAssertNil(OnboardingFlow.close(.login, phase: .ready))
    }

    func testStartLooksReadyOnlyWithBothGrantsAndNoPendingRelaunch() {
        let both = PermissionGrants(accessibility: true, screenRecording: true)
        XCTAssertTrue(OnboardingFlow.startLooksReady(both, askedScreenRecording: false))
        XCTAssertFalse(OnboardingFlow.startLooksReady(both, askedScreenRecording: true), "OUT-05: 다시 실행 전")
        XCTAssertFalse(OnboardingFlow.startLooksReady(PermissionGrants(accessibility: true, screenRecording: false), askedScreenRecording: false))
        XCTAssertFalse(OnboardingFlow.startLooksReady(PermissionGrants(accessibility: false, screenRecording: false), askedScreenRecording: false))
    }

    func testSheetSitsBelowTabsOrCentersWhenTooTall() {
        XCTAssertEqual(OnboardingFlow.sheetTop(available: 716, card: 624), 53, "OUT-01: 탭 막대 바로 아래")
        XCTAssertEqual(OnboardingFlow.sheetTop(available: 700, card: 680), 10, "안 들어가면 가운데")
        XCTAssertEqual(OnboardingFlow.sheetTop(available: 716, card: 741), 0, "창보다 높으면 맨 위에서 스크롤")
    }
}
```

- [ ] **Step 3: 알림 문구 테스트와 로그인 오류 문구 테스트 작성**

`Tests/WorkGraphCoreTests/FileSuggestionCopyTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

final class FileSuggestionCopyTests: XCTestCase {
    func testBodyMatchesFigmaExample() {
        XCTAssertEqual(FileSuggestionCopy.title, "파일을 정리할까요?")
        XCTAssertEqual(FileSuggestionCopy.body(fileName: "통계학_수업자료.pdf", folder: "/Users/me/Documents/통계학", home: "/Users/me"),
                       "통계학_수업자료.pdf을 문서 / 통계학 폴더로 옮겨 보세요.")
    }

    func testParticleFollowsLastHangulSyllable() {
        XCTAssertEqual(FileSuggestionCopy.objectParticle("보고서"), "를")
        XCTAssertEqual(FileSuggestionCopy.objectParticle("논문"), "을")
        XCTAssertEqual(FileSuggestionCopy.objectParticle("report.pdf"), "을")
        XCTAssertEqual(FileSuggestionCopy.objectParticle(""), "을")
    }

    func testFolderLabel() {
        let home = "/Users/me"
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me/Downloads", home: home), "다운로드")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me/Documents/통계학/", home: home), "문서 / 통계학")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me/프로젝트/캡스톤", home: home), "프로젝트 / 캡스톤")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/me", home: home), "홈")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Volumes/USB/자료", home: home), "Volumes / USB / 자료")
        XCTAssertEqual(FileSuggestionCopy.folderLabel("/Users/meow/a", home: home), "Users / meow / a", "이름만 홈으로 시작하는 다른 폴더")
    }
}
```

`Tests/WorkGraphCoreTests/CodexAuthTests.swift` 의 클래스 안에 더한다:

```swift
    func testDeviceLoginDisabledMessageMatchesLoginErrorScreen() {
        // Figma OUT-W1 의 오류 상자 문구
        XCTAssertEqual(CodexAuthError.deviceLoginNotEnabled.description,
                       "이 계정은 기기 코드 로그인이 꺼져 있어요. ChatGPT 설정의 보안 항목에서 켜 주세요.")
    }
```

- [ ] **Step 4: 돌려서 실패 확인**

Run: `swift test --filter "MenuBarModelTests|OnboardingFlowTests|FileSuggestionCopyTests|CodexAuthTests" 2>&1 | tail -8`
Expected: 컴파일 실패 (`cannot find 'MenuBarModel'`, `'OnboardingFlow'`, `'FileSuggestionCopy'`).

- [ ] **Step 5: `MenuBarModel` 구현**

`Sources/WorkGraphCore/Models/MenuBarModel.swift`:

```swift
import Foundation

/// 메뉴 막대 드롭다운이 그릴 화면 (Figma OUT-W2, OUT-W7, OUT-W6, OUT-06)
public enum MenuBarMode: Equatable, Sendable {
    /// W2: 로그인 전, 권한 단계를 마치기 전, 시작 실패
    case notReady
    /// W7: 수집 일시정지
    case paused
    /// W6: 손쉬운 사용이나 화면 기록이 꺼져 있음
    case permissionMissing
    /// OUT-06: 정상
    case normal
}

/// 메뉴 막대에 보일 화면과 문구
public enum MenuBarModel {
    /// 고르는 순서: 준비 전 → 일시정지 → 권한 빠짐 → 정상.
    /// 권한은 수집기가 처음 알려 주기 전(running == false)에는 모르는 값이라 경고하지 않는다.
    public static func mode(phase: AppPhase, startupFailed: Bool, paused: Bool, running: Bool,
                            accessibility: Bool, screenRecording: Bool) -> MenuBarMode {
        if startupFailed || phase != .ready { return .notReady }
        if paused { return .paused }
        if running, !accessibility || !screenRecording { return .permissionMissing }
        return .normal
    }

    /// W2 의 안내 한 줄
    public static func notReadyMessage(phase: AppPhase, startupFailed: Bool) -> String {
        if startupFailed { return "Sillog을 시작하지 못했어요" }
        return phase == .login ? "시작하려면 ChatGPT 로그인이 필요해요" : "시작하려면 권한 설정을 마쳐 주세요"
    }

    /// 오른쪽 위 상태 글씨. 준비 전에는 없다
    public static func statusText(mode: MenuBarMode, running: Bool, idle: Bool) -> String? {
        switch mode {
        case .notReady: return nil
        case .paused: return "일시정지됨"
        case .permissionMissing: return "■ 수집 중"
        case .normal: return idle ? "자리 비움" : running ? "■ 기록 중" : "시작하는 중"
        }
    }

    /// 큰 숫자: 10 미만은 "06" 처럼 두 자리, 음수는 0
    public static func twoDigits(_ value: Int) -> String {
        let n = max(0, value)
        return n < 10 ? "0\(n)" : "\(n)"
    }

    /// 마지막 정리 요약: "14:05 정리 완료(새 업무 1개, 자료 3개)"
    public static func batchSummary(clock: String, newTasks: Int, resources: Int) -> String {
        "\(clock) 정리 완료(새 업무 \(newTasks)개, 자료 \(resources)개)"
    }
}
```

- [ ] **Step 6: `OnboardingFlow` 구현**

`Sources/WorkGraphCore/Models/OnboardingFlow.swift`:

```swift
import CoreGraphics
import Foundation

/// 온보딩 시트의 단계 (Figma OUT-01~05)
public enum OnboardingStep: Equatable, Sendable {
    /// 01 로그인
    case login
    /// 02 권한
    case permissions
}

/// 온보딩 권한 단계가 읽는 두 권한
public struct PermissionGrants: Equatable, Sendable {
    public var accessibility: Bool
    public var screenRecording: Bool

    public init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    public var all: Bool { accessibility && screenRecording }
}

/// 온보딩 시트를 언제, 어느 단계로 보여 줄지. 로그인이 끝나도 사용자가 "로그인 완료, 다음" 을 누를 때까지 1단계에 머문다.
public enum OnboardingFlow {
    /// 앱 단계(phase)가 정해지거나 바뀐 뒤 보여 줄 단계. nil 이면 시트가 없다
    public static func step(after current: OnboardingStep?, phase: AppPhase) -> OnboardingStep? {
        switch phase {
        case .login: return .login                             // 로그아웃하면 언제든 1단계부터
        case .permissions: return current ?? .permissions     // 방금 로그인했으면 1단계에 머물고, 다시 실행했으면 2단계
        case .ready: return current == .login ? .login : nil  // 마친 계정이 다시 로그인했으면 성공을 보여 준 뒤 닫는다
        }
    }

    /// "로그인 완료, 다음" 을 누를 수 있는가
    public static func canAdvance(from step: OnboardingStep, phase: AppPhase) -> Bool {
        step == .login && phase != .login
    }

    /// "로그인 완료, 다음": 권한 단계가 남았으면 2단계, 이미 마친 계정이면 닫는다
    public static func advance(from step: OnboardingStep, phase: AppPhase) -> OnboardingStep? {
        guard canAdvance(from: step, phase: phase) else { return step }
        return phase == .permissions ? .permissions : nil
    }

    /// 닫기(×): 창은 닫히고, 남은 단계가 있으면 창을 다시 열 때 그 단계가 보인다
    public static func close(_ step: OnboardingStep?, phase: AppPhase) -> OnboardingStep? {
        phase == .ready ? nil : step
    }

    /// "수집 시작" 을 진하게 보일지 (누르는 것은 언제나 된다).
    /// 두 권한이 있고 다시 실행할 일이 없을 때만 진하다 (OUT-05 는 다시 실행 전이라 흐림)
    public static func startLooksReady(_ grants: PermissionGrants, askedScreenRecording: Bool) -> Bool {
        grants.all && !askedScreenRecording
    }

    /// 시트 위치: 탭 막대(54) 바로 아래(53)에 붙이고, 창이 낮아 안 들어가면 가운데, 그래도 넘치면 맨 위(넘친 만큼은 스크롤)
    public static func sheetTop(available: CGFloat, card: CGFloat) -> CGFloat {
        let belowTabs: CGFloat = 53
        if belowTabs + card <= available { return belowTabs }
        return max(0, (available - card) / 2)
    }
}
```

- [ ] **Step 7: `FileSuggestionCopy` 구현과 로그인 오류 문구 바꾸기**

`Sources/WorkGraphCore/Files/FileSuggestionCopy.swift`:

```swift
import Foundation

/// 파일 정리 알림 문구 (Figma OUT-07). 알림 버튼은 옮기기·무시
public enum FileSuggestionCopy {
    public static let title = "파일을 정리할까요?"

    /// "통계학_수업자료.pdf을 문서 / 통계학 폴더로 옮겨 보세요."
    public static func body(fileName: String, folder: String, home: String) -> String {
        "\(fileName)\(objectParticle(fileName)) \(folderLabel(folder, home: home)) 폴더로 옮겨 보세요."
    }

    /// 을/를: 마지막 글자가 한글이면 받침으로 고르고, 그 밖(확장자로 끝나는 파일 이름 등)은 Figma 처럼 "을"
    public static func objectParticle(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "을" }
        return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }

    /// 폴더를 "문서 / 통계학" 처럼 보여 준다. 홈 바로 아래 기본 폴더는 Finder 의 한국어 이름, 홈 자체는 "홈"
    public static func folderLabel(_ path: String, home: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        if trimmed == home { return "홈" }
        guard trimmed.hasPrefix(home + "/") else { return trimmed.split(separator: "/").joined(separator: " / ") }
        var parts = trimmed.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        if let first = parts.first, let name = homeFolders[first] { parts[0] = name }
        return parts.joined(separator: " / ")
    }

    static let homeFolders = ["Desktop": "데스크탑", "Documents": "문서", "Downloads": "다운로드",
                              "Movies": "동영상", "Music": "음악", "Pictures": "사진"]
}
```

`CodexAuthModels.swift` 에서

```swift
        case .deviceLoginNotEnabled: return "이 계정은 기기 코드 로그인이 꺼져 있습니다. ChatGPT 설정의 보안 항목에서 켜 주세요"
```

를

```swift
        case .deviceLoginNotEnabled: return "이 계정은 기기 코드 로그인이 꺼져 있어요. ChatGPT 설정의 보안 항목에서 켜 주세요."
```

로 바꾼다.

- [ ] **Step 8: 돌려서 통과 확인**

Run: `swift test --filter "MenuBarModelTests|OnboardingFlowTests|FileSuggestionCopyTests|CodexAuthTests" 2>&1 | tail -5`
Expected: 모두 통과 (`with 0 failures`).

- [ ] **Step 9: 전체 테스트**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 272 tests, with 0 failures` (248 + 10 + 10 + 3 + 1).

---

### Task 4: 앱 상태 연결과 스냅샷 실행

**Files:**
- Modify: `Sources/WorkGraphApp/AppState.swift`
- Create: `Sources/WorkGraphApp/Snapshots/SnapshotRunner.swift`
- Create: `Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift`
- Modify: `Sources/WorkGraphApp/WorkGraphApp.swift` (`AppEntry` 에 스냅샷 분기)

**Interfaces:**
- Consumes: Task 3 의 `OnboardingFlow`, `OnboardingStep`, `PermissionGrants`, `MenuBarModel.batchSummary`; Task 2 의 `BrandFonts.register()`
- Produces (AppState):
  - `@Published var onboardingStep: OnboardingStep?`, `@Published var loginBlocked: Bool`, `@Published var permissionGrants: PermissionGrants`, `@Published var askedScreenRecording: Bool`
  - `func advanceOnboarding()`, `func closeOnboarding()`, `func refreshPermissionGrants()`
  - `init(preview configure: (AppState) -> Void)`, `static let alreadyRunningMessage: String`
  - 스냅샷: `WORKGRAPH_SNAPSHOT=<폴더> swift run WorkGraphApp` → `<폴더>/<화면>.png` (이름: OUT-W2, OUT-W7, OUT-W6, OUT-06, OUT-06-long, OUT-01, OUT-02, OUT-02-signed-in, OUT-03, OUT-04, OUT-05, OUT-W1, OUT-W3, OUT-W4, OUT-W5)

- [ ] **Step 1: AppState 에 새 상태 더하기**

`@Published var chat: ChatState?` 아래에:

```swift
    /// 온보딩 시트가 보여 줄 단계. nil 이면 시트가 없다 (OnboardingFlow 가 정한다)
    @Published var onboardingStep: OnboardingStep?
    /// 기기 코드 로그인이 꺼진 계정이라 로그인을 시작하지 못했다. 창이 OUT-W1 카드를 보여 준다
    @Published var loginBlocked = false
    /// 온보딩 권한 단계가 1초마다 직접 읽는 권한 (이때는 수집기가 아직 돌지 않는다)
    @Published var permissionGrants = PermissionGrants(accessibility: false, screenRecording: false)
    /// 이번 실행에서 화면 기록 권한을 요청했다. 허용해도 다시 실행해야 적용된다 (OUT-05)
    @Published var askedScreenRecording = false
```

`private var bootstrapLogged = false` 아래에:

```swift
    /// 스냅샷용 미리보기 상태. DB·잠금·수집기·권한 읽기를 하지 않는다
    private var isPreview = false
```

`private static let onboardingKey = …` 아래에:

```swift
    /// Figma OUT-W3 문구
    static let alreadyRunningMessage = "Sillog이 이미 실행 중이에요. 메뉴 막대의 아이콘을 확인해 주세요."
```

- [ ] **Step 2: 시작 실패 문구, 미리보기 init, bootstrap**

`init()` 의

```swift
        guard instanceLock.acquire() else {
            startupError = "Sillog이 이미 실행 중입니다. 메뉴바의 아이콘을 확인하세요. 터미널에서 swift run 으로 띄운 것이 있다면 그쪽을 먼저 끄세요."
            return
        }
```

를

```swift
        guard instanceLock.acquire() else {
            startupError = Self.alreadyRunningMessage
            AppLog.write("이미 실행 중인 Sillog 이 있어 시작하지 않음 (터미널에서 swift run 으로 띄운 실행도 확인)")
            return
        }
```

로 바꾸고, `init()` 이 끝난 바로 뒤에 더한다:

```swift
    /// 개발용 미리보기 (SnapshotCatalog). DB·실행 잠금·수집기를 만들지 않고, configure 가 화면에 필요한 값만 채운다
    init(preview configure: (AppState) -> Void) {
        settings = AppSettings()
        isPreview = true
        bootstrapped = true
        configure(self)
    }
```

`bootstrap()` 의 `guard !bootstrapped else { return }` 를 `guard !bootstrapped, !isPreview else { return }` 로 바꾼다.

- [ ] **Step 3: 온보딩 단계, 권한 읽기, 다시 실행**

`updatePhase()` 에서 `phase = AppPhase.decide(…)` 문장 바로 다음 줄에:

```swift
        onboardingStep = OnboardingFlow.step(after: onboardingStep, phase: phase)
```

`completeOnboarding()` 바로 아래에:

```swift
    /// 온보딩 1단계의 "로그인 완료, 다음"
    func advanceOnboarding() {
        guard let step = onboardingStep else { return }
        onboardingStep = OnboardingFlow.advance(from: step, phase: phase)
    }

    /// 온보딩 시트의 닫기(×). 창은 화면 쪽이 닫는다
    func closeOnboarding() {
        onboardingStep = OnboardingFlow.close(onboardingStep, phase: phase)
    }

    /// 온보딩 권한 단계가 1초마다 부른다. 값이 같으면 화면을 건드리지 않는다
    func refreshPermissionGrants() {
        guard !isPreview else { return }
        let now = PermissionGrants(accessibility: Permissions.accessibility(prompt: false), screenRecording: Permissions.screenRecording())
        if now != permissionGrants { permissionGrants = now }
    }
```

`relaunch()` 맨 앞에:

```swift
        // 새 실행이 잠금을 먼저 잡으려 하므로 미리 놓는다. 놓지 않으면 새 실행이 '이미 실행 중'(W3)으로 막힌다.
        // 다시 실행은 온보딩(수집기가 돌기 전)에서만 쓴다
        instanceLock.release()
```

- [ ] **Step 4: 로그인 오류(W1)와 마지막 정리 문구**

`startCodexLogin()` 에서 `codexMessage = nil` 다음 줄에 `loginBlocked = false` 를 더하고,

```swift
            } catch let error as CodexAuthError {
                self.codexMessage = error == .cancelled ? nil : error.description
```

다음 줄에 `self.loginBlocked = error == .deviceLoginNotEnabled` 를 더한다.

`runBatch` 의

```swift
                lastBatchText = "\(Self.clock.string(from: Date())) 정리 완료 (업무 \(stats.tasksCreated)개 새로, 자료 \(stats.resources)개)"
```

를

```swift
                lastBatchText = MenuBarModel.batchSummary(clock: Self.clock.string(from: Date()), newTasks: stats.tasksCreated, resources: stats.resources)
```

로 바꾼다.

- [ ] **Step 5: 빌드**

Run: `swift build --product WorkGraphApp 2>&1 | tail -5`
Expected: 빌드 성공.

- [ ] **Step 6: 스냅샷 실행기 작성**

`Sources/WorkGraphApp/Snapshots/SnapshotRunner.swift`:

```swift
import AppKit
import SwiftUI

/// 개발용 스냅샷: `WORKGRAPH_SNAPSHOT=<폴더> swift run WorkGraphApp` 로 실행하면 창을 띄우지 않고
/// 상태별 화면(SnapshotCatalog)을 PNG 로 그린 뒤 끝난다. DB·실행 잠금·수집기를 만들지 않아 실행 중인 앱과 데이터에 영향이 없다.
@MainActor
enum SnapshotRunner {
    static func run(into directory: String) -> Never {
        let out = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // 혹시 실제 경로를 읽는 코드가 있어도 사용자 데이터가 아니라 스냅샷 폴더를 보게 한다
        setenv("WORKGRAPH_DB", out.appendingPathComponent("snapshot.sqlite").path, 1)
        setenv("WORKGRAPH_CODEX_AUTH", out.appendingPathComponent("no-auth.json").path, 1)
        NSApplication.shared.setActivationPolicy(.prohibited)
        print("fonts: \(BrandFonts.register().sorted().joined(separator: ", "))")
        var failures = 0
        for shot in SnapshotCatalog.all {
            if render(shot, to: out.appendingPathComponent("\(shot.name).png")) {
                print("ok \(shot.name)")
            } else {
                failures += 1
                print("FAIL \(shot.name)")
            }
        }
        exit(failures == 0 ? 0 : 1)
    }

    private static func render(_ shot: Snapshot, to url: URL) -> Bool {
        let host = NSHostingView(rootView: shot.view)
        host.frame.size = shot.size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.frame.size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<3 {                                   // SwiftUI 가 상태를 반영해 다시 그릴 시간을 준다
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if shot.size == nil {                              // 폭이 고정된 화면(메뉴)은 내용 높이에 맞춘다
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}

/// 그릴 화면 하나: 이름(Figma 화면 번호), 크기(nil 이면 화면이 정한 크기), 화면
struct Snapshot {
    let name: String
    let size: CGSize?
    let view: AnyView
}
```

- [ ] **Step 7: 스냅샷 목록 작성**

`Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift`:

```swift
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 스냅샷으로 그릴 화면 목록. 이름은 Figma 화면 번호를 따른다 ($SCRATCH/figma/out/<이름>.png 와 나란히 본다)
@MainActor
enum SnapshotCatalog {
    static var all: [Snapshot] { menus + windows }

    /// Figma 창(760) 에서 제목 줄(44)을 뺀 내용 영역
    static let window = CGSize(width: 1180, height: 716)

    static var menus: [Snapshot] {
        [
            shot("OUT-W2", MenuBarView()) { s in s.phase = .login },
            shot("OUT-W7", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(paused: true)
                s.todayCount = 8; s.pendingCount = 2; s.lastBatchText = "14:05 정리 완료(새 업무 2개, 자료 5개)"
            },
            shot("OUT-W6", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(accessibility: false)
                s.todayCount = 8; s.pendingCount = 2; s.lastBatchText = "14:05 정리 완료(새 업무 1개, 자료 3개)"
            },
            shot("OUT-06", MenuBarView()) { s in
                s.phase = .ready; s.status = collector()
                s.todayCount = 62; s.pendingCount = 6; s.notificationsDenied = true
                s.fileSuggestions = pendingFiles(2); s.taskList = recentTasks
            },
            // 리뷰 포커스 4: 큰 숫자와 긴 업무 이름
            shot("OUT-06-long", MenuBarView()) { s in
                s.phase = .ready; s.status = collector()
                s.todayCount = 1234; s.pendingCount = 0
                s.taskList = [TaskSummary(id: 9, key: "long", title: "아주 긴 업무 이름이 메뉴 폭을 넘어가면 한 줄로 잘려야 하는지 보는 업무",
                                          taskType: nil, activeSeconds: 60, lastActive: todayAt(9, 5), sessionCount: 1)]
            },
        ]
    }

    static var windows: [Snapshot] {
        [
            shot("OUT-01", MainWindow(), size: window) { s in loginStep(s) },
            shot("OUT-02", MainWindow(), size: window) { s in loginStep(s); s.deviceCode = sampleCode },
            shot("OUT-02-signed-in", MainWindow(), size: window) { s in
                loginStep(s); s.phase = .permissions
                s.codexStatus = .loggedIn(email: "sillog@example.com", plan: nil, expiresAt: nil)
            },
            shot("OUT-03", MainWindow(), size: window) { s in permissionStep(s, PermissionGrants(accessibility: false, screenRecording: false)) },
            shot("OUT-04", MainWindow(), size: window) { s in permissionStep(s, PermissionGrants(accessibility: true, screenRecording: false)) },
            shot("OUT-05", MainWindow(), size: window) { s in
                permissionStep(s, PermissionGrants(accessibility: true, screenRecording: true)); s.askedScreenRecording = true
            },
            shot("OUT-W1", MainWindow(), size: window) { s in s.phase = .login; s.loginBlocked = true },
            shot("OUT-W3", MainWindow(), size: window) { s in s.startupError = AppState.alreadyRunningMessage },
            shot("OUT-W4", MainWindow(), size: window) { s in s.bootstrapped = false },
            shot("OUT-W5", MainWindow(), size: window) { s in
                s.phase = .ready; s.status = collector(); s.batchRunning = true; s.pendingCount = 6
                s.fileSuggestions = pendingFiles(2); s.taskList = recentTasks; s.selectedTab = .tasks
            },
        ]
    }

    // MARK: 예시 상태

    private static func shot<V: View>(_ name: String, _ view: V, size: CGSize? = nil, _ configure: (AppState) -> Void) -> Snapshot {
        let state = AppState(preview: configure)
        return Snapshot(name: name, size: size, view: AnyView(view.environmentObject(state)))
    }

    /// 시트 뒤에는 업무 탭(그래프 탭은 웹 보기라 스냅샷에 안 그려진다)
    private static func loginStep(_ s: AppState) {
        s.phase = .login; s.onboardingStep = .login; s.selectedTab = .tasks
        s.taskList = recentTasks; s.fileSuggestions = pendingFiles(2); s.pendingCount = 6
    }

    private static func permissionStep(_ s: AppState, _ grants: PermissionGrants) {
        s.phase = .permissions; s.onboardingStep = .permissions; s.permissionGrants = grants; s.selectedTab = .tasks
        s.taskList = recentTasks; s.fileSuggestions = pendingFiles(2); s.pendingCount = 6
    }

    private static func collector(accessibility: Bool = true, screenRecording: Bool = true, paused: Bool = false) -> CollectorStatus {
        var status = CollectorStatus()
        status.running = true
        status.accessibility = accessibility
        status.screenRecording = screenRecording
        status.paused = paused
        return status
    }

    private static func todayAt(_ hour: Int, _ minute: Int) -> Double {
        (Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()).timeIntervalSince1970
    }

    private static var recentTasks: [TaskSummary] {
        [TaskSummary(id: 1, key: "flask", title: "Flask 웹앱 개발", taskType: nil, activeSeconds: 9600, lastActive: todayAt(14, 32), sessionCount: 3),
         TaskSummary(id: 2, key: "stats", title: "통계학 수업", taskType: nil, activeSeconds: 3000, lastActive: todayAt(12, 10), sessionCount: 1),
         TaskSummary(id: 3, key: "report", title: "분기 성과 보고서", taskType: nil, activeSeconds: 4500, lastActive: todayAt(11, 45), sessionCount: 1)]
    }

    private static func pendingFiles(_ count: Int) -> [FileSuggestion] {
        (0..<count).map {
            FileSuggestion(id: Int64($0 + 1), ts: 0, path: "/tmp/file\($0).pdf", fileName: "file\($0).pdf", originUrl: nil,
                           suggestedFolder: "/tmp", confidence: 0.9, reason: nil, source: "llm")
        }
    }

    private static var sampleCode: DeviceCode {
        DeviceCode(verificationURL: URL(string: "https://auth.openai.com/codex/device")!, userCode: "SILL-OG26",
                   deviceAuthId: "preview", interval: 5, expiresAt: Date().timeIntervalSince1970 + 900)
    }
}
```

- [ ] **Step 8: 시작점에 스냅샷 분기**

`WorkGraphApp.swift` 의 `AppEntry.main()` 맨 앞에:

```swift
        // 개발용: 창 없이 상태별 화면을 PNG 로 그리고 끝난다 (SnapshotRunner)
        if let directory = ProcessInfo.processInfo.environment["WORKGRAPH_SNAPSHOT"], !directory.isEmpty {
            MainActor.assumeIsolated { SnapshotRunner.run(into: directory) }
        }
```

- [ ] **Step 9: 스냅샷을 돌려 보고, 실제 데이터가 그대로인지 확인**

```bash
LOG="$HOME/Library/Application Support/WorkGraph/app.log"
before=$(stat -f %m "$LOG" 2>/dev/null || echo none)
WORKGRAPH_SNAPSHOT="$SCRATCH/snap-task4" swift run WorkGraphApp 2>&1 | tail -20; echo "exit=${PIPESTATUS[0]}"
after=$(stat -f %m "$LOG" 2>/dev/null || echo none)
echo "app.log before=$before after=$after"
ls "$SCRATCH/snap-task4" | head -20
```
Expected: `fonts: Jost-Book, Jost-Thin, SUIT-Bold, SUIT-Medium, SUIT-Regular, SUIT-SemiBold`, `ok …` 15줄, `exit=0`, 15개 PNG. 실행 중인 앱이 그 사이 로그를 쓸 수 있으므로 `app.log` 시각이 바뀌었으면 마지막 줄을 열어 스냅샷이 쓴 줄(`단계:` 등)이 아닌지 본다. 이때 화면은 아직 인성님 화면이다(Task 5·6 에서 바꾼다). `OUT-06.png` 와 `OUT-01.png` 를 Read 로 열어 글꼴이 SUIT·Jost 로 그려졌는지 본다.

- [ ] **Step 10: 전체 테스트**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 272 tests, with 0 failures`.

---

### Task 5: 메뉴 막대 (OUT-06, W2, W6, W7)

**Files:**
- Modify (전부 새로 씀): `Sources/WorkGraphApp/Views/MenuBarView.swift`

**Interfaces:**
- Consumes: `MenuBarModel.mode/notReadyMessage/statusText/twoDigits` (Task 3), `Brand.jost/jostLight/suit/line/hairline/ink/gray/tabText/text` (Task 1·2), `Eyebrow`, `SuggestionNotifier.openSystemSettings()`, `AppState.prepareResume(taskId:)`, `AppState.runBatch(force:)`, `AppState.togglePause()`, `AppState.clock`
- Produces: `struct MenuBarView: View` (이름 그대로, WorkGraphApp 이 쓴다)

- [ ] **Step 1: MenuBarView 새로 쓰기**

`Sources/WorkGraphApp/Views/MenuBarView.swift` 전체:

```swift
import AppKit
import SwiftUI
import WorkGraphCore

/// 메뉴 막대 드롭다운. 상태(MenuBarModel.mode)에 따라 Figma 네 화면 중 하나를 그린다.
///   OUT-W2 준비 전, OUT-W7 일시정지, OUT-W6 권한 경고: 버튼 메뉴 (폭 336, 흰 바탕)
///   OUT-06 정상: 큰 숫자 메뉴 (폭 344, 흰색 94%)
/// `.window` 스타일 MenuBarExtra 안에서 그려진다.
struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    private var mode: MenuBarMode {
        MenuBarModel.mode(phase: state.phase, startupFailed: state.startupError != nil, paused: state.status.paused,
                          running: state.status.running, accessibility: state.status.accessibility,
                          screenRecording: state.status.screenRecording)
    }

    private var status: String? {
        MenuBarModel.statusText(mode: mode, running: state.status.running, idle: state.status.idle)
    }

    var body: some View {
        if mode == .normal {
            MenuBarDashboard(status: status, openMain: openMain)
        } else {
            MenuBarButtons(mode: mode, status: status, openMain: openMain)
        }
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 머리: 왼쪽 SILLOG 로고, 오른쪽 상태 글씨, 아래 구분선
private struct MenuBarHeader: View {
    let height: CGFloat
    let logoHeight: CGFloat
    let status: String?
    let statusFont: Font
    let line: Color

    var body: some View {
        HStack {
            if let mark = Brand.wordmark {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: logoHeight).accessibilityLabel("SILLOG")
            } else {
                Text("SILLOG").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
            }
            Spacer()
            if let status { Text(status).font(statusFont).foregroundStyle(Brand.gray) }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }
}

// MARK: OUT-W2 · OUT-W6 · OUT-W7

/// 요약 한두 줄과 큰 버튼 (흰 바탕, 폭 336, 안쪽 여백 24)
private struct MenuBarButtons: View {
    @EnvironmentObject private var state: AppState
    let mode: MenuBarMode
    let status: String?
    let openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarHeader(height: 64, logoHeight: 22, status: status, statusFont: Brand.suit(11), line: Brand.line)
            if mode == .notReady {
                notice(icon: "info.circle", MenuBarModel.notReadyMessage(phase: state.phase, startupFailed: state.startupError != nil))
                    .padding(.top, 18).padding(.bottom, 22)
                divider
                MenuPrimaryButton(title: "시작하기…", action: openMain)
                    .padding(.top, 18).padding(.bottom, 16)
            } else {
                summary
                divider
                VStack(spacing: 10) {
                    MenuPrimaryButton(title: "그래프 열기") {
                        state.selectedTab = .graph
                        openMain()
                    }
                    HStack(spacing: 8) {
                        MenuSecondaryButton(title: state.batchRunning ? "정리하는 중…" : "지금 정리") {
                            Task { await state.runBatch(force: true) }
                        }
                        .disabled(state.batchRunning)
                        MenuSecondaryButton(title: state.status.paused ? "수집 다시 시작" : "수집 일시정지") { state.togglePause() }
                    }
                }
                .padding(.vertical, 16)
            }
            divider
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 13))
                    Text("Sillog 종료").font(Brand.suit(13))
                }
                .foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity).frame(height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16).padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(width: 336)
        .background(.white)
    }

    /// W6·W7: 오늘 숫자, 마지막 정리, (W6) 권한 경고
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("오늘 기록 \(state.todayCount)개, 정리 대기 \(state.pendingCount)개")
                .font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
            Text(state.lastBatchText).font(Brand.suit(12)).foregroundStyle(Brand.gray).lineLimit(2)
                .padding(.top, 8)
            if mode == .permissionMissing {
                notice(icon: "exclamationmark.circle", "권한이 빠져 있어 일부만 수집 중이에요").padding(.top, 20)
            }
        }
        .padding(.top, 18).padding(.bottom, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.ink)
            Text(text).font(Brand.suit(13)).foregroundStyle(Brand.ink)
        }
    }

    private var divider: some View { Rectangle().fill(Brand.line).frame(height: 1) }
}

/// 주색 큰 버튼 (288×42, 모서리 8, SUIT 500 14)
private struct MenuPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Brand.suit(14, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.ink))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 흰 바탕 테두리 버튼 (140×42, 모서리 8, SUIT 500 13)
private struct MenuSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: OUT-06

/// 큰 숫자 두 개, 알림·파일 제안 줄, 최근 업무 3개, [지금 정리], 일시정지·종료 (흰색 94%, 폭 344, 안쪽 여백 23)
private struct MenuBarDashboard: View {
    @EnvironmentObject private var state: AppState
    let status: String?
    let openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarHeader(height: 60, logoHeight: 21, status: status, statusFont: Brand.suit(10), line: Brand.hairline)
            stats
            if state.notificationsDenied { notificationRow }
            if state.pendingFileSuggestions > 0 { fileRow }
            if !state.taskList.isEmpty { recentWork }
            bottom
        }
        .padding(.horizontal, 23)
        .frame(width: 344)
        .background(.white.opacity(0.94))
    }

    /// TODAY·WAITING: 눈썹 글씨 17, 숫자 76 (Jost 200 54), 설명 15. 사이에 세로선
    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            number("TODAY", state.todayCount, "오늘 기록").frame(width: 149, alignment: .leading)
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 107)
            number("WAITING", state.pendingCount, "정리 대기").padding(.leading, 23)
            Spacer(minLength: 0)
        }
        .padding(.top, 21)
        .frame(height: 153, alignment: .top)
        .overlay(alignment: .bottom) { hairline }
    }

    private func number(_ eyebrow: String, _ value: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(eyebrow).frame(height: 17, alignment: .leading)
            Text(MenuBarModel.twoDigits(value))
                .font(Brand.jostLight(54)).foregroundStyle(Brand.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(height: 76, alignment: .leading)
            Text(caption).font(Brand.suit(10)).foregroundStyle(Brand.gray).frame(height: 15, alignment: .leading)
        }
    }

    /// 알림 권한이 꺼져 있으면: 누르면 시스템 설정의 알림
    private var notificationRow: some View {
        Button { SuggestionNotifier.openSystemSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Brand.ink)
                Text("파일 제안 알림 권한이 꺼져 있어요").font(Brand.suit(10)).foregroundStyle(Brand.tabText)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.tabText)
            }
            .frame(height: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
    }

    /// 파일 정리 제안이 있으면: 누르면 파일 탭
    private var fileRow: some View {
        Button {
            state.selectedTab = .files
            openMain()
        } label: {
            HStack(spacing: 0) {
                Text("파일 정리 제안").font(Brand.suit(11)).foregroundStyle(Brand.text)
                Spacer()
                Text("\(state.pendingFileSuggestions)").font(Brand.jost(15)).foregroundStyle(Brand.text)
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.tabText).padding(.leading, 18)
            }
            .padding(.trailing, 25)
            .frame(height: 55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
    }

    /// 최근 업무 3개. 누르면 다시 열기 (prepareResume 이 창을 연다)
    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("RECENT WORK").frame(height: 17, alignment: .leading)
            Text("최근 업무 다시 열기").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 5)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(state.taskList.prefix(3)) { task in
                    Button { state.prepareResume(taskId: task.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(task.title).font(Brand.suit(12)).foregroundStyle(Brand.text).lineLimit(1)
                                    .frame(height: 18, alignment: .leading)
                                Text(Self.timeText(task.lastActive)).font(Brand.suit(9)).foregroundStyle(Brand.gray)
                                    .frame(height: 14, alignment: .leading)
                                    .padding(.top, 23)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(Brand.ink)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)
        }
        .padding(.top, 20).padding(.bottom, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// [지금 정리] 와 일시정지·종료. 최근 업무가 있을 때만 위에 선을 긋는다 (다른 줄은 아래에 선이 있다)
    private var bottom: some View {
        VStack(spacing: 0) {
            Button { Task { await state.runBatch(force: true) } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .medium))
                    Text(state.batchRunning ? "정리하는 중…" : "지금 정리").font(Brand.suit(12, .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.batchRunning)
            HStack(spacing: 0) {
                footerButton("pause", "일시정지") { state.togglePause() }
                footerButton("rectangle.portrait.and.arrow.right", "종료") { NSApp.terminate(nil) }
            }
            .frame(height: 35)
            .padding(.top, 11)
        }
        .padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .top) { if !state.taskList.isEmpty { hairline } }
    }

    private func footerButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(Brand.suit(10))
            }
            .foregroundStyle(Brand.tabText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hairline: some View { Rectangle().fill(Brand.hairline).frame(height: 1) }

    static func timeText(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let time = AppState.clock.string(from: date)
        if Calendar.current.isDateInToday(date) { return "오늘 \(time)" }
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 \(time)"
    }
}
```

- [ ] **Step 2: 빌드**

Run: `swift build --product WorkGraphApp 2>&1 | tail -5`
Expected: 빌드 성공.

- [ ] **Step 3: 스냅샷을 Figma 와 나란히 보기**

```bash
WORKGRAPH_SNAPSHOT="$SCRATCH/snap-task5" swift run WorkGraphApp 2>&1 | tail -3
```
Expected: `exit 0`. 그리고 Read 로 두 장씩 연다: `snap-task5/OUT-W2.png` ↔ `figma/out/OUT-W2.png`, W7, W6, OUT-06. 확인 항목:
- W2/W6/W7: 폭 336, 머리 64(로고 22, 오른쪽 상태 글씨 11), 구분선 #E5E2DF, 버튼 288×42·140×42, "Sillog 종료" 가운데. W6 만 경고 줄, W7 은 "일시정지됨"·"수집 다시 시작".
- OUT-06: 폭 344, 머리 60, TODAY 62 / WAITING 06 (가는 Jost 54, 두 자리), 세로선, 알림 줄 ↗, "파일 정리 제안 2 ↗", RECENT WORK 3개(⟲), [⟲ 지금 정리] 298×38, 일시정지·종료.
- `OUT-06-long`: "1234" 가 한 줄, 긴 업무 이름이 "…" 로 잘림.
다르면 이 파일에서 값을 고치고 다시 찍는다. 고친 값마다 ledger 에 남길 필요는 없다(Figma 에 맞추는 것이 이 Task 의 일).

- [ ] **Step 4: 전체 테스트**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 272 tests, with 0 failures`.

---

### Task 6: 온보딩 시트(OUT-01~05), 로그인 오류(W1), 시작 실패(W3), 불러오는 중(W4)

**Files:**
- Modify (전부 새로 씀): `Sources/WorkGraphApp/Views/OnboardingView.swift`
- Create: `Sources/WorkGraphApp/Views/LoginBlockedView.swift`
- Modify: `Sources/WorkGraphApp/Views/MainWindow.swift` (본문, 덮개)

**Interfaces:**
- Consumes: Task 3 `OnboardingFlow.canAdvance/startLooksReady/sheetTop`, `OnboardingStep`; Task 4 `AppState.onboardingStep/loginBlocked/permissionGrants/askedScreenRecording/advanceOnboarding()/closeOnboarding()/refreshPermissionGrants()`, `AppState.startCodexLogin()/copyDeviceCode()/completeOnboarding()/relaunch()`, `CodexAuthError.deviceLoginNotEnabled.description`, `Permissions` (WorkGraphCollectors)
- Produces: `struct OnboardingOverlay: View` (init `step:`), `struct OnboardingSheet: View`, `struct LoginBlockedView: View`, `struct BrandLoadingView`, `struct BrandStartupErrorView(message:)`. 옛 `OnboardingView` 는 없어진다.

- [ ] **Step 1: OnboardingView.swift 새로 쓰기**

`Sources/WorkGraphApp/Views/OnboardingView.swift` 전체:

```swift
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 온보딩 시트를 띄우는 덮개: 창 전체를 옅게 덮고 카드(760)를 탭 막대 바로 아래에 둔다 (Figma OUT-01~05).
/// 창이 낮아 카드가 다 들어가지 않으면 가운데로 올리고, 그래도 넘치면 스크롤한다.
struct OnboardingOverlay: View {
    let step: OnboardingStep
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(hex: 0x141210, opacity: 0.16)
                ScrollView {
                    OnboardingSheet(step: step)
                        .background(GeometryReader { Color.clear.preference(key: SheetHeightKey.self, value: $0.size.height) })
                        .padding(.top, OnboardingFlow.sheetTop(available: geo.size.height, card: cardHeight))
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onPreferenceChange(SheetHeightKey.self) { cardHeight = $0 }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 온보딩 카드: 머리(눈썹 글씨, 제목, 닫기), 본문(1 로그인 / 2 권한), 바닥(단계 표시, 다음 버튼)
struct OnboardingSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    let step: OnboardingStep
    @State private var deviceHelpOpen = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var loggedIn: Bool { state.phase != .login }

    var body: some View {
        VStack(spacing: 0) {
            header
            if step == .login { loginBody } else { permissionBody }
            footer
        }
        .frame(width: 760)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x141210, opacity: 0.12)))
        .shadow(color: Color(hex: 0x141210, opacity: 0.15), radius: 21, y: 14)
        .onAppear { state.refreshPermissionGrants() }
        .onReceive(poll) { _ in if step == .permissions { state.refreshPermissionGrants() } }
    }

    // MARK: 머리 (105)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(step == .login ? "GET STARTED / 01" : "GET STARTED / 02").frame(height: 17, alignment: .leading)
            Text(step == .login ? "당신의 일을 기억하는 시작" : "기록을 위한 두 가지 권한")
                .font(Brand.suit(22)).tracking(-0.77).foregroundStyle(Brand.ink)
                .padding(.top, 9)
        }
        .padding(.leading, 28).padding(.top, 26)
        .frame(maxWidth: .infinity, minHeight: 105, maxHeight: 105, alignment: .topLeading)
        .background(.white.opacity(0.95))
        .overlay(alignment: .topTrailing) {
            // 닫기: 창만 닫는다. 메뉴 막대는 준비 전(W2)으로 남고, 거기서 다시 열 수 있다
            Button {
                state.closeOnboarding()
                dismissWindow(id: "main")
            } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .light)).foregroundStyle(Brand.tabText)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("닫기").accessibilityLabel("닫기")
            .padding(.top, 19).padding(.trailing, 18)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    // MARK: 1. 로그인

    private var loginBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                brandColumn
                    .frame(width: 260).frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
                loginColumn.frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            privacyNote
        }
    }

    private var brandColumn: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 112, height: 112)
            Group {
                if let mark = Brand.wordmark {
                    Image(nsImage: mark).resizable().scaledToFit().frame(height: 26).accessibilityLabel("SILLOG")
                } else {
                    Text("SILLOG").font(Brand.suit(18, .semibold)).foregroundStyle(Brand.ink)
                }
            }
            .padding(.top, 33)
            Text("흩어진 기록을 모아,\n다음 일의 맥락으로.")
                .font(Brand.suit(13)).foregroundStyle(Brand.gray).multilineTextAlignment(.center).lineSpacing(8)
                .padding(.top, 34)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loginColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("내 ChatGPT 계정으로 연결해요.").font(Brand.suit(17, .medium)).foregroundStyle(Brand.ink)
            Text("별도의 Sillog 계정 없이 시작할 수 있어요.\n로그인 토큰은 이 기기에만 저장돼요.")
                .font(Brand.suit(12)).foregroundStyle(Brand.gray).lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
            if loggedIn {
                signedInBox.padding(.top, 21)
            } else {
                Button { loginAction() } label: {
                    HStack(spacing: 8) {
                        Text("ChatGPT로 로그인")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryStyle(height: 42))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 21)
                if let code = state.deviceCode { deviceCodeBox(code).padding(.top, 15) }
            }
            apiKeyRow.padding(.top, 16)
            if !loggedIn, let message = state.codexMessage { errorBox(message).padding(.top, 14) }
            deviceHelp.padding(.top, 15)
        }
        .padding(.horizontal, 31).padding(.vertical, 30)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 코드를 받기 전에는 로그인을 시작하고, 받은 뒤에는 승인 페이지를 다시 연다
    private func loginAction() {
        if let code = state.deviceCode { NSWorkspace.shared.open(code.verificationURL) } else { state.startCodexLogin() }
    }

    private func deviceCodeBox(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("DEVICE CODE").frame(height: 17, alignment: .leading)
            HStack {
                Text(code.userCode).font(Brand.jost(23)).tracking(2.99).foregroundStyle(Brand.ink).textSelection(.enabled)
                Spacer()
                Button { state.copyDeviceCode() } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(Brand.tabText)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("기기 코드 복사").accessibilityLabel("기기 코드 복사")
            }
            .frame(height: 38)
            .padding(.top, 5)
            Text("15분 안에 브라우저에서 승인해요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 5)
        }
        .padding(.horizontal, 17).padding(.top, 15).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    /// 로그인을 마친 뒤: 로그인 버튼 자리에 연결한 계정 (Figma 에 없는 상태)
    private var signedInBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("SIGNED IN").frame(height: 17, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                Text(signedInName).font(Brand.suit(15, .medium)).lineLimit(1)
            }
            .foregroundStyle(Brand.ink)
            .padding(.top, 9)
            Text("로그인을 마쳤어요. 아래 버튼으로 다음 단계로 넘어가요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 8)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    private var signedInName: String {
        if case .loggedIn(let email, _, _) = state.codexStatus, let email, !email.isEmpty { return email }
        return "ChatGPT 계정"
    }

    /// API 키 로그인은 아직 없다: '예정' 표시만, 누를 수 없다
    private var apiKeyRow: some View {
        HStack(spacing: 7) {
            Text("API 키로 시작").font(Brand.suit(11)).foregroundStyle(Brand.tabText)
            Text("예정").font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
                .frame(width: 31, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Brand.paper))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
        }
        .padding(.leading, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("API 키로 시작, 예정")
    }

    private func errorBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Brand.gray)
            Text(message).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.paper))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
    }

    private var deviceHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { deviceHelpOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(deviceHelpOpen ? "▾" : "▸").font(.system(size: 8))
                    Text("기기 코드 로그인이 꺼져 있나요?").font(Brand.suit(10))
                }
                .foregroundStyle(Brand.gray)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if deviceHelpOpen {
                Text("ChatGPT 계정에서 기기 코드 로그인을 켠 뒤 다시 시도해 주세요.").font(Brand.suit(10)).foregroundStyle(Brand.gray)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(Brand.ink).frame(width: 15)
            VStack(alignment: .leading, spacing: 8) {
                Text("무엇이 기기 밖으로 나가나요?").font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink)
                Text("기록은 Mac에 저장돼요. 업무를 정리할 때 창 제목, 주소, 화면 텍스트와 대표 화면 이미지가 연결한 AI로 전송돼요. 채팅에서 조회한 원문, 코드, 문서도 전송될 수 있어요. 허용한 웹 검색과 플러그인은 외부 서비스와 통신해요.")
                    .font(Brand.suit(11)).foregroundStyle(Brand.gray).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 40).padding(.trailing, 31).padding(.top, 31).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    // MARK: 2. 권한

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("기록할 범위를 직접 정할 수 있어요.\n권한은 언제든 macOS 설정에서 바꿀 수 있어요.")
                .font(Brand.suit(13)).foregroundStyle(Brand.gray).lineSpacing(8)
                .padding(.bottom, 16)
            permissionRow("cursorarrow", "손쉬운 사용", detail: "앱 이름, 창 제목과 화면 텍스트를 읽어요.",
                          granted: state.permissionGrants.accessibility) {
                _ = Permissions.accessibility(prompt: true)
                Permissions.openSettings(.accessibility)
            }
            permissionRow("display", "화면 기록", detail: "활성 창의 스크린샷과 화면 내용을 기록해요.",
                          granted: state.permissionGrants.screenRecording) {
                Permissions.requestScreenRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
                state.askedScreenRecording = true
            }
            if state.askedScreenRecording { relaunchRow }       // OUT-05: 허용 여부와 상관없이 이번 실행에서 요청했으면
        }
        .padding(.horizontal, 30).padding(.top, 32).padding(.bottom, 43)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(_ icon: String, _ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Brand.tabText)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Brand.suit(15, .medium)).foregroundStyle(Brand.ink)
                Text(detail).font(Brand.suit(12)).foregroundStyle(Brand.gray)
            }
            .padding(.leading, 20)
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
                    Text("허용됨")
                }
                .font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
                .padding(.horizontal, 12).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            } else {
                Button("허용하기", action: action).buttonStyle(OnboardingSecondaryStyle())
            }
        }
        .frame(height: 105)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var relaunchRow: some View {
        HStack {
            Text("화면 기록 권한은 앱을 다시 실행해야 적용돼요.").font(Brand.suit(11)).foregroundStyle(Brand.gray)
            Spacer()
            Button { state.relaunch() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    Text("다시 실행")
                }
            }
            .buttonStyle(OnboardingSecondaryStyle())
        }
        .frame(height: 68)
    }

    // MARK: 바닥 (73)

    private var footer: some View {
        HStack {
            HStack(spacing: 0) {
                stepLabel("01 로그인", on: step == .login)
                Rectangle().fill(Brand.line).frame(width: 24, height: 1).padding(.leading, 15).padding(.trailing, 12)
                stepLabel("02 권한", on: step == .permissions)
            }
            Spacer()
            if step == .login {
                let canGo = OnboardingFlow.canAdvance(from: .login, phase: state.phase)
                Button { state.advanceOnboarding() } label: { arrowLabel("로그인 완료, 다음") }
                    .buttonStyle(OnboardingPrimaryStyle(height: 38))
                    .fixedSize()
                    .opacity(canGo ? 1 : 0.38)
                    .disabled(!canGo)
                    .keyboardShortcut(canGo ? .defaultAction : nil)
            } else {
                // 권한이 없어도 시작할 수 있어야 해서 누르는 것은 늘 되고, 준비되지 않았으면 흐리게만 보인다
                Button { state.completeOnboarding() } label: { arrowLabel("수집 시작") }
                    .buttonStyle(OnboardingPrimaryStyle(height: 38))
                    .fixedSize()
                    .opacity(OnboardingFlow.startLooksReady(state.permissionGrants, askedScreenRecording: state.askedScreenRecording) ? 1 : 0.38)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 25)
        .frame(height: 73)
        .background(.white.opacity(0.95))
        .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }

    private func stepLabel(_ text: String, on: Bool) -> some View {
        Text(text).font(Brand.suit(10, on ? .semibold : .regular)).foregroundStyle(on ? Brand.ink : Brand.gray)
    }

    private func arrowLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
        }
    }
}

/// 온보딩 카드 안 주색 버튼 (주색 바탕, 흰 글씨 12 Medium, 모서리 6)
struct OnboardingPrimaryStyle: ButtonStyle {
    var height: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.suit(12, .medium)).foregroundStyle(.white)
            .padding(.horizontal, 20).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// 흰 바탕 테두리 버튼 (허용하기, 다시 실행)
struct OnboardingSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.suit(11, .medium)).foregroundStyle(Brand.tabText)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: 시작 상태 화면 (Figma OUT-W4, OUT-W3)

/// 불러오는 중: 흰 바탕 가운데 회전 표시
struct BrandLoadingView: View {
    var body: some View {
        ProgressView().controlSize(.regular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
    }
}

/// 시작 실패: 경고 아이콘, 제목, 원인 문장
struct BrandStartupErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 30, weight: .light)).foregroundStyle(Brand.gray)
            Text("시작하지 못했어요").font(Brand.suit(22, .bold)).foregroundStyle(Brand.ink).padding(.top, 30)
            Text(message).font(Brand.suit(14)).foregroundStyle(Brand.gray).multilineTextAlignment(.center)
                .textSelection(.enabled).padding(.top, 17)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }
}
```

- [ ] **Step 2: LoginBlockedView 작성 (W1)**

`Sources/WorkGraphApp/Views/LoginBlockedView.swift`:

```swift
import SwiftUI
import WorkGraphCore

/// 기기 코드 로그인이 꺼진 계정이라 로그인을 시작하지 못했을 때 (Figma OUT-W1, 예전 스타일 카드 그대로).
/// "ChatGPT로 로그인"을 다시 누르면 오류가 지워지고 탭과 온보딩 시트로 돌아간다.
struct LoginBlockedView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                card
                    .frame(width: 1000)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .background(Brand.paper)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                brand
                    .frame(width: 340).frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
                login.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 351)
            privacy
            footer
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.line))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GET STARTED / 01").font(Brand.jost(11)).tracking(1.6).foregroundStyle(Brand.gray)
            Text("ChatGPT 계정으로 시작하기").font(Brand.suit(26, .bold)).foregroundStyle(Brand.ink).padding(.top, 7)
        }
        .padding(.leading, 40).padding(.top, 30)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var brand: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 78, height: 78)
            if let mark = Brand.wordmark {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: 27).padding(.top, 33).accessibilityLabel("SILLOG")
            }
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mac에서 한 일을 기록하고 업무 단위로 정리해요.\n시작하려면 로그인해 주세요.")
                .font(Brand.suit(14)).foregroundStyle(Brand.gray).lineSpacing(6)
            Button { state.startCodexLogin() } label: {
                HStack(spacing: 8) {
                    Text("ChatGPT로 로그인")
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
                }
                .font(Brand.suit(14, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.ink))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 32)
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Brand.gray)
                Text(CodexAuthError.deviceLoginNotEnabled.description).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.paper))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
            .padding(.top, 20)
        }
        .frame(width: 563)
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield").font(.system(size: 14)).foregroundStyle(Brand.ink).frame(width: 14)
            VStack(alignment: .leading, spacing: 13) {
                Text("무엇이 기기 밖으로 나가나요?").font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                Text("기록과 스크린샷은 이 Mac에 저장돼요. 정리할 때 창 제목, 주소, 화면 텍스트 일부가 ChatGPT로 전송돼요.")
                    .font(Brand.suit(12)).foregroundStyle(Brand.gray)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 48).padding(.top, 29).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    /// 예전 스타일 단계 표시: ① 로그인 —— ② 권한
    private var footer: some View {
        HStack(spacing: 0) {
            stepDot("1", on: true)
            Text("로그인").font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink).padding(.leading, 11)
            Rectangle().fill(Brand.line).frame(width: 28, height: 1).padding(.horizontal, 12)
            stepDot("2", on: false)
            Text("권한").font(Brand.suit(13)).foregroundStyle(Brand.sub).padding(.leading, 11)
            Spacer()
        }
        .padding(.leading, 39)
        .frame(height: 63)
        .background(Brand.paper)
    }

    private func stepDot(_ number: String, on: Bool) -> some View {
        Text(number).font(Brand.suit(11, .medium)).foregroundStyle(on ? Color.white : Brand.sub)
            .frame(width: 18, height: 18)
            .background(Circle().fill(on ? Brand.ink : Color.clear))
            .overlay(Circle().strokeBorder(on ? Brand.ink : Brand.sub))
    }
}
```

- [ ] **Step 3: MainWindow 를 탭 + 덮개 구조로**

`MainWindow.swift` 에서

```swift
    private var ready: Bool { state.startupError == nil && state.bootstrapped && state.phase == .ready }

    var body: some View {
        VStack(spacing: 0) {
            if ready { BrandTabBar() }                         // 온보딩 중에는 탭을 숨긴다
            Group {
                if let error = state.startupError {
                    BrandStartupErrorView(message: error)
                } else if !state.bootstrapped {
                    BrandLoadingView()
                } else if state.phase != .ready {
                    OnboardingView()
                } else {
```

를

```swift
    private var ready: Bool { state.startupError == nil && state.bootstrapped && state.phase == .ready }
    /// 기기 코드 로그인이 꺼진 계정: 탭 대신 OUT-W1 카드
    private var loginBlocked: Bool { state.loginBlocked && state.phase == .login }
    /// 시작 실패·불러오는 중·로그인 오류가 아니면 탭이 보이고, 온보딩은 그 위에 시트로 뜬다
    private var showsTabs: Bool { state.startupError == nil && state.bootstrapped && !loginBlocked }

    var body: some View {
        VStack(spacing: 0) {
            if showsTabs { BrandTabBar() }
            Group {
                if let error = state.startupError {
                    BrandStartupErrorView(message: error)
                } else if !state.bootstrapped {
                    BrandLoadingView()
                } else if loginBlocked {
                    LoginBlockedView()
                } else {
```

로 바꾸고, `.frame(minWidth: 900, minHeight: 560)` 바로 앞(바깥 VStack 이 닫힌 뒤)에 더한다:

```swift
        .overlay {
            if showsTabs, let step = state.onboardingStep { OnboardingOverlay(step: step) }
        }
```

- [ ] **Step 4: 빌드**

Run: `swift build --product WorkGraphApp 2>&1 | tail -5`
Expected: 빌드 성공 (`OnboardingView` 를 부르는 곳이 남아 있으면 오류 — `grep -rn "OnboardingView()" Sources` 로 찾아 지운다).

- [ ] **Step 5: 스냅샷을 Figma 와 나란히 보기**

```bash
WORKGRAPH_SNAPSHOT="$SCRATCH/snap-task6" swift run WorkGraphApp 2>&1 | tail -3
```
Expected: `exit 0`. Read 로 짝지어 연다: OUT-01·02·03·04·05·W1·W3·W4 (Figma 쪽은 제목 줄 44 만큼 아래에 있다). 확인 항목:
- 시트: 폭 760, 탭 막대 바로 아래(OUT-02 는 창보다 높아 맨 위), 머리 105(GET STARTED / 01, "당신의 일을 기억하는 시작", ×), 왼쪽 260 칸(아이콘·로고·문구), 오른쪽 "내 ChatGPT 계정으로 연결해요.", 로그인 버튼 438×42, (OUT-02) DEVICE CODE 상자와 복사 버튼, "API 키로 시작 [예정]", "▸ 기기 코드 로그인이 꺼져 있나요?", 개인정보 114, 바닥 73(01 로그인 — 02 권한, 흐린 "로그인 완료, 다음 →").
- `OUT-02-signed-in`: SIGNED IN 상자와 진한 "로그인 완료, 다음 →".
- 권한: 설명 두 줄, 105 높이 줄 둘, "허용하기"/"✓ 허용됨", OUT-05 의 "다시 실행" 줄, 흐린 "수집 시작 →".
- W1: 베이지 바탕, 1000×620 카드, 오류 상자 문구, ① 로그인 —— ② 권한. W3: 경고 아이콘, "시작하지 못했어요", Figma 문구. W4: 흰 바탕 회전 표시.
다르면 고쳐서 다시 찍는다.

- [ ] **Step 6: 전체 테스트**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 272 tests, with 0 failures`.

---

### Task 7: 창 틀(W5, 파일 배지), 파일 정리 알림 문구, 마지막 확인

**Files:**
- Modify: `Sources/WorkGraphApp/Views/MainWindow.swift` (`BrandTabBar`, `FileBadge`)
- Modify: `Sources/WorkGraphApp/SuggestionNotifier.swift` (`notify` 의 제목·본문)
- Create (스크래치): `$WS/board.swift` (Figma 와 스냅샷을 나란히 붙인 비교 이미지)

**Interfaces:**
- Consumes: `FileSuggestionCopy.title/body` (Task 3), `AppState.pendingFileSuggestions/batchRunning/pendingCount`
- Produces: 없음 (마지막 Task)

- [ ] **Step 1: 탭 막대에 파일 배지와 정리 중 표시**

`BrandTabBar` 의 `ForEach` 안 `Button { state.selectedTab = tab } label: { … }` 의 label 을

```swift
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(Brand.suit(12, on ? .semibold : .regular))
                            .foregroundStyle(on ? Brand.ink : Brand.tabText)
                        if tab == .files, state.pendingFileSuggestions > 0 { FileBadge(count: state.pendingFileSuggestions) }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 35)
                    .glassPill(on)
                    .contentShape(Rectangle())
```

로 바꾸고, `Spacer(minLength: 12)` 뒤의 "지금 정리" 버튼 전체를

```swift
            if state.batchRunning {
                HStack(spacing: 8) {                          // OUT-W5: 정리하는 동안 오른쪽 위에 회전 표시
                    ProgressView().controlSize(.mini)
                    Text("정리하는 중…").font(Brand.suit(12)).foregroundStyle(Brand.sub)
                }
            } else {
                Button { Task { await state.runBatch(force: true) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                        Text("지금 정리").font(Brand.suit(11))
                        if state.pendingCount > 0 {
                            Text("\(state.pendingCount)").font(Brand.jost(12)).foregroundStyle(Brand.gray)
                        }
                    }
                    .foregroundStyle(Brand.tabText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("아직 정리되지 않은 활동을 지금 바로 그래프에 반영합니다")
            }
```

로 바꾼다. 파일 아래쪽(`BrandTabBar` 뒤)에 더한다:

```swift
/// 파일 탭 옆 대기 중인 정리 제안 수 (Figma OUT-01 탭 막대: Jost 10, 하늘색 테두리)
private struct FileBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(Brand.jost(10)).foregroundStyle(Brand.tabText)
            .padding(.horizontal, 5).frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(Brand.sky.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.sky))
    }
}
```

- [ ] **Step 2: 알림 문구를 Figma 로 (OUT-07)**

`SuggestionNotifier.notify` 의

```swift
            content.title = suggestion.fileName
            content.body = "→ " + Self.short(suggestion.suggestedFolder, home: home)
            if let reason = suggestion.reason, !reason.isEmpty { content.subtitle = reason }
```

를

```swift
            content.title = FileSuggestionCopy.title
            content.body = FileSuggestionCopy.body(fileName: suggestion.fileName, folder: suggestion.suggestedFolder, home: home)
```

로 바꾼다. (`short` 는 다른 곳에서 쓰면 그대로 둔다: `grep -rn "SuggestionNotifier.short\|\.short(" Sources`.)

- [ ] **Step 3: 빌드와 W5 스냅샷**

```bash
swift build --product WorkGraphApp 2>&1 | tail -5
WORKGRAPH_SNAPSHOT="$SCRATCH/snap-final" swift run WorkGraphApp 2>&1 | tail -3
```
Expected: 빌드 성공, `exit 0`. `snap-final/OUT-W5.png` 오른쪽 위에 회전 표시와 "정리하는 중…"(#AAAAAA), `OUT-01.png` 탭 막대의 "파일 [2]" 배지.

- [ ] **Step 4: 비교 이미지 만들기**

`$WS/board.swift`:

```swift
import AppKit

// 사용: swift board.swift <figma 폴더> <스냅샷 폴더> <출력 폴더> 이름...
// 이름마다 왼쪽 Figma, 오른쪽 스냅샷을 같은 높이로 붙인 PNG 를 만든다.
let args = CommandLine.arguments
let figma = URL(fileURLWithPath: args[1]), snap = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for name in args.dropFirst(4) {
    guard let a = NSImage(contentsOf: figma.appendingPathComponent("\(name).png")),
          let b = NSImage(contentsOf: snap.appendingPathComponent("\(name).png")) else { print("skip \(name)"); continue }
    let height = max(a.size.height, b.size.height)
    let wa = a.size.width * height / a.size.height, wb = b.size.width * height / b.size.height
    let size = NSSize(width: wa + wb + 24, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    a.draw(in: NSRect(x: 0, y: 0, width: wa, height: height))
    b.draw(in: NSRect(x: wa + 24, y: 0, width: wb, height: height))
    image.unlockFocus()
    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: out.appendingPathComponent("\(name).png")); print("board \(name)")
    }
}
```

```bash
swift "$WS/board.swift" "$SCRATCH/figma/out" "$SCRATCH/snap-final" "$SCRATCH/board" OUT-W2 OUT-W6 OUT-W7 OUT-06 OUT-01 OUT-02 OUT-03 OUT-04 OUT-05 OUT-W1 OUT-W3 OUT-W4 OUT-W5
```
Expected: `board …` 13줄. 몇 장을 Read 로 열어 마지막으로 본다.

- [ ] **Step 5: 마지막 확인**

```bash
swift test 2>&1 | tail -3
bash "$WS/graph-check.sh" "$SCRATCH/graph-check"
git status --short | head -40
```
Expected: `Executed 272 tests, with 0 failures`; 그래프 확인은 Task 1 Step 6 과 같음; staged 는 합치기 23개 그대로, 나머지는 unstaged·untracked (커밋 없음).

---

## 실행 뒤 (이 계획 밖)

- 앱에 반영하려면 `scripts/make-app.sh` 가 `~/Applications/Sillog.app` 을 바꿔 설치한다 — 사용자에게 먼저 묻는다.
- 커밋을 요청받으면: `git commit` (지금 인덱스 = 합치기만) → `git add -A` 후 작업 커밋. 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
