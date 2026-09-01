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
  ボタン → 現在の会話で音声入力を開始
  (以降の操作はマイクの選択によって変わります。下の表をご覧ください)
Claude Desktop が最前面でないとき:
  何もせず素通しします (YouTube 等が従来どおり反応します)
```

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

Claude Desktop で会話を開き、最前面にした状態でヘッドセットのボタンを押すと音声入力が始まります。その先の操作は、メニューバーのアイコンで選べる「マイクの選択」によって変わります。

| 選択 | ボタンの動き |
|---|---|
| **ヘッドセットで話す** (初期設定) | ボタン → 録音開始。集音はヘッドセットのマイクです。Bluetoothの仕様で録音中はボタンの信号がMacに届かないため、停止はマウスで行ってください。停止後にもう一度ボタンを押すと送信します |
| **デフォルトマイクで話す** | ボタン → 開始、もう一度 → 停止 (文字起こしを確認できます)、もう一度 → 送信。集音はMac側のマイクに自動で切り替わり、すべてボタンで完結します |

どちらの選択でも、入力欄にテキストがある状態でボタンを押すとそのまま送信します。

## 謝辞

本アプリは [rayhatfield/mac-media-keys](https://github.com/rayhatfield/mac-media-keys) (MIT License) を基にした改造版です。メディアキーイベントの捕捉と Now Playing クレームの仕組みは同プロジェクトの実装に負っています。素晴らしい土台を公開してくださった Ray Hatfield 氏に感謝します。

## ライセンス

MIT License です。詳細は [LICENSE](LICENSE) をご覧ください。
