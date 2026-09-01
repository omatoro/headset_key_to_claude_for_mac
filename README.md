# headset_key_to_claude_for_mac

Bluetoothヘッドセットの物理ボタンで、macOS上の [Claude Desktop](https://claude.ai/download) の音声入力を開始・送信するメニューバー常駐アプリ。

キーボードやマウスに触れず、ヘッドセットのボタンだけで「話して送る」を完結させる。

## 何が起きるか

```
ヘッドセットのボタンを押す
  ↓ (Bluetooth AVRCP)
macOS のメディアコマンド
  ↓
本アプリが捕捉 (Now Playing クレーム)
  ↓
Claude Desktop が最前面のとき:
  現在開いている会話の音声入力を開始
  もう一度押すと送信
Claude Desktop が最前面でないとき:
  何もせず素通し (YouTube 等が従来どおり反応)
```

- キーボードの入力処理には一切介入しない。修飾キー設定(Caps Lock→Control 等)はそのまま動く
- Karabiner-Elements や Hammerspoon は使わない

## 動作要件

- macOS 13 (Ventura) 以降 / Apple Silicon
- Claude Desktop (通常アプリ。CLI の Claude Code ではない)
- Xcode 不要。Command Line Tools の swiftc だけでビルドできる
- アクセシビリティ権限 (イベント捕捉と Claude Desktop のマイクボタン操作に必要)

## セットアップ

工事中。ビルドスクリプトと手順は実装の進行に合わせて追記する。

```bash
git clone https://github.com/omatoro/headset_key_to_claude_for_mac.git
cd headset_key_to_claude_for_mac
bash build.sh
```

## 謝辞

本アプリは [rayhatfield/mac-media-keys](https://github.com/rayhatfield/mac-media-keys) (MIT License) を基にした改造版である。メディアキーイベントの捕捉と Now Playing クレームの仕組みは同プロジェクトの実装に負っている。素晴らしい土台を公開してくれた Ray Hatfield 氏に感謝する。

## ライセンス

MIT License。詳細は [LICENSE](LICENSE) を参照。
