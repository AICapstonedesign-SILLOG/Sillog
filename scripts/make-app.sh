#!/bin/bash
# release 빌드 → build/WorkGraph.app 번들 → 코드 서명.
# 서명 인증서를 고정해 두면 다시 빌드해도 macOS 권한(손쉬운 사용·화면 기록)이 유지된다.
#   SIGN_IDENTITY="Apple Development: ..." scripts/make-app.sh   # 인증서 지정
#   SIGN_IDENTITY=- scripts/make-app.sh                          # ad-hoc (빌드할 때마다 권한을 다시 줘야 함)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product WorkGraphApp
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/build/WorkGraph.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WorkGraphApp" "$APP/Contents/MacOS/WorkGraph"
cp -R "$ROOT/Sources/WorkGraphApp/Resources/graph" "$APP/Contents/Resources/graph"
[ -f "$ROOT/Sources/WorkGraphApp/Resources/AppIcon.icns" ] || swift "$ROOT/scripts/make-icon.swift" "$ROOT/Sources/WorkGraphApp/Resources/AppIcon.icns"
cp "$ROOT/Sources/WorkGraphApp/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.capstone.workgraph</string>
  <key>CFBundleName</key><string>WorkGraph</string>
  <key>CFBundleDisplayName</key><string>WorkGraph</string>
  <key>CFBundleExecutable</key><string>WorkGraph</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>새로 내려받은 파일을 하던 업무와 연결해 기록합니다.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST

# 서명: 지정값 → "Capstone Prototype Dev" → "Apple Development" → ad-hoc 순으로 고른다.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  AVAILABLE="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for candidate in "Capstone Prototype Dev" "Apple Development"; do
    if echo "$AVAILABLE" | grep -q "\"$candidate"; then
      IDENTITY="$(echo "$AVAILABLE" | grep "\"$candidate" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
      break
    fi
  done
fi
IDENTITY="${IDENTITY:--}"

sign() {   # 키체인 확인 창에서 멈추는 경우를 대비해 25초 제한
  codesign --force --sign "$1" "$APP" &
  local pid=$!
  ( sleep 25; kill "$pid" 2>/dev/null ) &
  local watchdog=$!
  local status=0
  wait "$pid" || status=$?
  kill "$watchdog" 2>/dev/null || true
  return "$status"
}

if [ "$IDENTITY" != "-" ] && sign "$IDENTITY"; then
  echo "서명: $IDENTITY"
else
  [ "$IDENTITY" != "-" ] && echo "'$IDENTITY' 서명 실패 → ad-hoc 으로 서명합니다 (다시 빌드하면 권한을 다시 줘야 합니다)"
  codesign --force --sign - "$APP"
  echo "서명: ad-hoc"
fi

echo "완성: $APP"
echo "실행: open \"$APP\""
