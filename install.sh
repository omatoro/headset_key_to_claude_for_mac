#!/bin/bash
# headset_key_to_claude_for_mac のワンライナーインストーラ。
# 使い方(READMEに記載):
#   curl -fsSL https://raw.githubusercontent.com/omatoro/headset_key_to_claude_for_mac/main/install.sh | bash
# ソースを取得してローカルでビルドし、/Applications へ配置します。
# ローカルビルドのため Gatekeeper の隔離属性が付かず、そのまま起動できます。
set -euo pipefail

REPO="https://github.com/omatoro/headset_key_to_claude_for_mac.git"
APP_NAME="headset_key_to_claude_for_mac"
DEST="${HEADSET_INSTALL_DEST:-/Applications/${APP_NAME}.app}"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Command Line Tools が見つかりません。先に次のコマンドを実行し、"
  echo "インストール完了後にもう一度お試しください:"
  echo "  xcode-select --install"
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "ソースコードを取得しています..."
git clone --quiet --depth 1 "$REPO" "$WORK/src"

echo "ビルドしています(初回は30秒ほどかかります)..."
cd "$WORK/src"
bash build.sh release >/dev/null

echo "配置しています: $DEST"
pkill -f "MacOS/${APP_NAME}" 2>/dev/null || true
rm -rf "$DEST"
cp -R "build/${APP_NAME}.app" "$DEST"

open "$DEST"
echo ""
echo "インストールが完了しました。メニューバーにヘッドセットのアイコンが表示されます。"
echo "初回はアクセシビリティ権限の許可が必要です:"
echo "  システム設定 → プライバシーとセキュリティ → アクセシビリティ →"
echo "  「${APP_NAME}」をオンにして、アプリを起動し直してください。"
