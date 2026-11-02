import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt64
    var title: String
    var onRecord: ((UInt16, UInt64) -> Void)?

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.recording { button.title = localized(title) + " · " + Self.display(keyCode: keyCode, flags: modifiers) }
        button.onRecord = { key, flags, label in
            if let onRecord { onRecord(key, flags) }
            else { keyCode = key; modifiers = flags }
            button.title = label
        }
    }

    static func display(keyCode: UInt16, flags: UInt64) -> String {
        let names: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"Return",37:"L",38:"J",40:"K",45:"N",46:"M",48:"Tab",49:"Space",51:"Delete",53:"Escape",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",114:"Help",115:"Home",116:"Page Up",117:"Delete",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(flags))
        let prefix = (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
        return prefix + (names[keyCode] ?? localized("按键"))
    }

    final class RecorderButton: NSButton {
        var recording = false
        var onRecord: ((UInt16, UInt64, String) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            recording = true
            title = "按下要使用的按键…"
            window?.makeFirstResponder(self)
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { recording = false; title = "录制按键"; return }
            let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            let flags = event.modifierFlags.intersection(mask)
            let prefix = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            let special: [UInt16: String] = [36:"Return", 48:"Tab", 49:"Space", 51:"Delete", 123:"←", 124:"→", 125:"↓", 126:"↑"]
            let label = prefix + (special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "按键")
            recording = false
            onRecord?(event.keyCode, UInt64(flags.rawValue), label)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
    }
}
