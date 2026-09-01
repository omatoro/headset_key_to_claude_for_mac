#!/bin/bash
# swiftc直組みビルド(Xcode不要・Command Line Toolsのみ)
# 使い方: bash build.sh          # debugビルド(-DDEBUG: /tmp/macmediakeys.log へ常時ログ)
#         bash build.sh release  # releaseビルド(-O・ログはアプリ設定のDebug Logging準拠)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-debug}"
APP_NAME="headset_key_to_claude_for_mac"
BUNDLE_ID="com.omatoro.headset-key-to-claude-for-mac"
DISPLAY_NAME="headset_key_to_claude_for_mac"
VERSION="0.1.0"
BUILD_NUM="1"
TARGET="arm64-apple-macos13.0"
APP="build/${APP_NAME}.app"

SWIFT_FLAGS=(-swift-version 5 -target "$TARGET")
if [ "$MODE" = "release" ]; then
  SWIFT_FLAGS+=(-O)
else
  SWIFT_FLAGS+=(-DDEBUG -Onone)
fi

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 1. コンパイル(ソース全量)
xcrun swiftc "${SWIFT_FLAGS[@]}" MacMediaKeys/*.swift -o "$APP/Contents/MacOS/$APP_NAME"

# 2. Info.plist(xcodebuildの変数展開を実値で再現)
sed -e "s/\$(PRODUCT_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUM/g" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/g" \
    -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/13.0/g" \
    MacMediaKeys/Info.plist > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true

# 3. PkgInfo
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 4. アイコン(assets/icon.svg が原本。PNGはChrome headlessで書き出したもの)
ICON_SRC="assets/icon_1024.png"
if [ -f "$ICON_SRC" ]; then
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" \
    || echo "[build] iconutil失敗。アイコン無しで続行(機能に影響なし)"
fi

# 4b. メニューバー用テンプレート画像(アプリアイコンと同一モチーフの黒単色版)
cp assets/menubar_72.png "$APP/Contents/Resources/menubar.png"

# 5. 署名(entitlements込み)
# ローカル自己署名identityがあればそれで署名する。署名が固定されるため、
# リビルドしてもアクセシビリティ権限が維持される(ad-hocは毎回変わり再付与が必要)。
# identityの作り方は docs/運用_ヘッドセット音声入力.md を参照。
SIGN_IDENTITY="headset-key-dev-sign"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$SIGN_IDENTITY" --entitlements MacMediaKeys/MacMediaKeys.entitlements "$APP"
else
  echo "[build] 署名identity($SIGN_IDENTITY)が無い — ad-hocで署名(リビルド毎に要再付与)"
  codesign --force --sign - --entitlements MacMediaKeys/MacMediaKeys.entitlements "$APP"
fi

# 6. 検証ハーネス(メディアキー合成送出CLI)
xcrun swiftc -swift-version 5 -target "$TARGET" tools/inject_play.swift -o build/inject_play

echo "[build] 完了: $APP ($MODE)"
