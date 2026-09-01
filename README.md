# headset_key_to_claude_for_mac

Bluetoothヘッドセットの物理ボタンで、macOS上の [Claude Desktop](https://claude.ai/download) の音声入力を開始・停止・送信できるメニューバー常駐アプリです。

キーボードやマウスに触れずに、ヘッドセットのボタンだけで「話して送る」を完結できます。

## 何が起きるか

```
ヘッドセットのボタンを押す
  ↓ (Bluetooth AVRCP)
macOS のメディアコマンド
  ↓
本アプリが捕捉 (Now Playing クレーム)
  ↓
Claude Desktop が最前面のとき:
  1回目のボタン → 現在の会話で音声入力を開始
  2回目のボタン → 録音を停止 (文字起こしを確認できます)
  3回目のボタン → 送信
  ※入力欄にテキストがある状態では、ボタン1回で送信します
Claude Desktop が最前面でないとき:
  何もせず素通しします (YouTube 等が従来どおり反応します)
```

- キーボードの入力処理には一切介入しません。修飾キー設定(Caps Lock→Control 等)はそのまま動きます
- Karabiner-Elements や Hammerspoon は使いません

## 動作要件

- macOS 13 (Ventura) 以降 / Apple Silicon
- Claude Desktop (デスクトップアプリ)
- Command Line Tools (`xcode-select --install` で入ります。Xcode本体は不要です)
- アクセシビリティ権限 (イベント捕捉と Claude Desktop のボタン操作に必要です)

## インストール

ターミナルで次の1行を実行してください。ソースの取得からビルド、/Applications への配置まで自動で行います。

```bash
curl -fsSL https://raw.githubusercontent.com/omatoro/headset_key_to_claude_for_mac/main/install.sh | bash
```

初回起動時にアクセシビリティ権限の許可を求められます。
**システム設定 → プライバシーとセキュリティ → アクセシビリティ** で「headset_key_to_claude_for_mac」をオンにして、アプリを起動し直してください。

ログイン時に自動起動させたい場合は、**システム設定 → 一般 → ログイン項目** に `/Applications/headset_key_to_claude_for_mac.app` を追加してください。

### 手動でビルドする場合

```bash
git clone https://github.com/omatoro/headset_key_to_claude_for_mac.git
cd headset_key_to_claude_for_mac
bash build.sh release
cp -R build/headset_key_to_claude_for_mac.app /Applications/
```

## 使い方

1. Claude Desktop で会話を開き、最前面にします
2. ヘッドセットのボタンを押すと音声入力が始まります
3. 話し終えたらもう一度押すと録音が止まり、文字起こしが入力欄に入ります
4. 内容を確認して、もう一度押すと送信されます

### マイクの選択 (メニューバーのアイコンから)

| 選択 | 動作 |
|---|---|
| **ヘッドセットで話す** (初期設定) | 集音はヘッドセットのマイクです。Bluetoothの仕様上、録音中はボタンが効かないため、停止と送信はマウスで行ってください |
| **デフォルトマイクで話す** | 集音はMac側のマイクに自動で切り替わります。開始・停止・送信のすべてをボタンで完結できます |

## 謝辞

本アプリは [rayhatfield/mac-media-keys](https://github.com/rayhatfield/mac-media-keys) (MIT License) を基にした改造版です。メディアキーイベントの捕捉と Now Playing クレームの仕組みは同プロジェクトの実装に負っています。素晴らしい土台を公開してくださった Ray Hatfield 氏に感謝します。

## ライセンス

MIT License です。詳細は [LICENSE](LICENSE) をご覧ください。
