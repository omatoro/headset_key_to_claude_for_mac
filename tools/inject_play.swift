import Cocoa

// 検証ハーネス: Play/PauseメディアキーのkeyDown/keyUpをNX_SYSDEFINED(subtype 8)として合成し
// HIDイベントタップへ流す。キーボード実機なしでCGEventTap経路の生存確認に使う。
// 実行にはこのバイナリを起動するプロセス(ターミナル等)へのアクセシビリティ権限が必要。

let NX_KEYTYPE_PLAY = 16

func postPlay(keyDown: Bool) -> Bool {
    let keyState = keyDown ? 0xA : 0xB
    let data1 = (NX_KEYTYPE_PLAY << 16) | (keyState << 8)
    guard let ev = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
    ), let cg = ev.cgEvent else {
        return false
    }
    cg.post(tap: .cghidEventTap)
    return true
}

if postPlay(keyDown: true) {
    usleep(50_000)
    _ = postPlay(keyDown: false)
    print("Play keyDown/keyUp を合成送出した")
} else {
    print("イベント生成に失敗した")
    exit(1)
}
