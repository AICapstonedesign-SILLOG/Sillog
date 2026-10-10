#!/bin/bash
# release 빌드 → 코드 서명 → ~/Applications/Sillog.app 설치.
# 서명 인증서를 고정해 두면 다시 빌드해도 macOS 권한(손쉬운 사용·화면 기록)이 유지된다.
#   SIGN_IDENTITY="Apple Development: ..." scripts/make-app.sh   # 인증서 지정
#   SIGN_IDENTITY=- scripts/make-app.sh                          # ad-hoc (빌드할 때마다 권한을 다시 줘야 함)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Documents의 동기화 파일 때문에 SwiftPM 의존성 체크아웃이 멈추지 않도록 임시 빌드 경로를 쓴다.
BUILD_DIR="${WORKGRAPH_BUILD_DIR:-${TMPDIR:-/tmp}/Sillog-swift-build}"
mkdir -p "$BUILD_DIR/cache" "$BUILD_DIR/config" "$BUILD_DIR/security" "$BUILD_DIR/clang-cache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD_DIR/clang-cache}"
# 동기화 중인 Documents 원본의 메타데이터가 컴파일 도중 바뀌지 않도록 소스를 임시 경로에 고정한다.
STAGE_DIR="$BUILD_DIR/source"
mkdir -p "$STAGE_DIR/Sources" "$STAGE_DIR/Tests"
rsync -a --delete "$ROOT/Sources/" "$STAGE_DIR/Sources/"
rsync -a --delete "$ROOT/Tests/" "$STAGE_DIR/Tests/"
cp "$ROOT/Package.swift" "$ROOT/Package.resolved" "$STAGE_DIR/"
swift build --package-path "$STAGE_DIR" -c release --product WorkGraphApp --scratch-path "$BUILD_DIR" --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --disable-sandbox -j 2
BIN_DIR="$(swift build --package-path "$STAGE_DIR" -c release --show-bin-path --scratch-path "$BUILD_DIR" --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --disable-sandbox)"
APP="$BUILD_DIR/Sillog.app"
APP_LINK="$ROOT/build/Sillog.app"
INSTALLED_APP="$HOME/Applications/Sillog.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WorkGraphApp" "$APP/Contents/MacOS/Sillog"
cp -R "$ROOT/Sources/WorkGraphApp/Resources/graph" "$APP/Contents/Resources/graph"
cp -R "$ROOT/Sources/WorkGraphApp/Resources/PluginIcons" "$APP/Contents/Resources/PluginIcons"
cp -R "$ROOT/Sources/WorkGraphApp/Resources/Brand" "$APP/Contents/Resources/Brand"
cp -R "$BIN_DIR/WorkGraph_WorkGraphCore.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/SwiftMath_SwiftMath.bundle" "$APP/Contents/Resources/"    # 채팅 수식 글꼴 (없으면 수식을 그릴 때 앱이 멈춘다)
chmod -R u+w "$APP/Contents/Resources/SwiftMath_SwiftMath.bundle"                    # 패키지 체크아웃에서 읽기 전용으로 오므로 서명 전 xattr 정리가 되게
[ -f "$ROOT/Sources/WorkGraphApp/Resources/AppIcon.icns" ] || swift "$ROOT/scripts/make-icon.swift" "$ROOT/Sources/WorkGraphApp/Resources/AppIcon.icns"
cp "$ROOT/Sources/WorkGraphApp/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.capstone.workgraph</string>
  <key>CFBundleName</key><string>Sillog</string>
  <key>CFBundleDisplayName</key><string>Sillog</string>
  <key>CFBundleExecutable</key><string>Sillog</string>
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

# 공개 OAuth 클라이언트 ID는 앱 제공자가 빌드할 때 설정한다. 비밀키는 번들에 넣지 않는다.
for key in WORKGRAPH_GOOGLE_CLIENT_ID WORKGRAPH_GITHUB_CLIENT_ID WORKGRAPH_NOTION_CLIENT_ID; do
  if [ -n "${!key:-}" ]; then
    plutil -insert "$key" -string "${!key}" "$APP/Contents/Info.plist"
  fi
done

# File Provider의 Finder 메타데이터가 서명을 깨므로 번들에서 제거한다.
xattr -cr "$APP"

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

mkdir -p "$(dirname "$INSTALLED_APP")" "$ROOT/build"
if [ "$APP" != "$INSTALLED_APP" ]; then
  rm -rf "$INSTALLED_APP"
  mv "$APP" "$INSTALLED_APP"
fi
rm -rf "$APP_LINK"
ln -s "$INSTALLED_APP" "$APP_LINK"
echo "설치: $INSTALLED_APP"
echo "완성: $APP_LINK"
echo "실행: open \"$APP_LINK\""
