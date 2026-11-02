import AppKit
import ApplicationServices

@MainActor final class MacroRuntime: ObservableObject {
    @Published private(set) var status = "宏未运行"
    private var execution: Task<Void, Never>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var macros: [InputMacro] = []
    private var shortcutsEnabled = false
    private let modifierMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue

    func synchronize(enabled: Bool, macros: [InputMacro]) {
        self.macros = macros
        let wasEnabled = shortcutsEnabled
        shortcutsEnabled = enabled
        guard AXIsProcessTrusted() else { stop(); return }
        guard enabled else {
            if wasEnabled { cancel() }
            removeMonitors()
            return
        }
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat, execution == nil else { return }
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != 0x4D434D4143524F else { return }
        let modifiers = UInt64(event.modifierFlags.rawValue) & modifierMask
        guard let macro = macros.first(where: { $0.shortcutKeyCode == event.keyCode && ($0.shortcutModifiers & modifierMask) == modifiers }) else { return }
        run(macro)
    }

    func run(_ macro: InputMacro) {
        guard AXIsProcessTrusted() else { status = "运行宏需要辅助功能权限"; return }
        guard execution == nil else { status = "已有宏正在运行"; return }
        guard (try? FeaturePreferences(macros: [macro]).validate()) != nil else { status = "宏超过执行限制"; return }
        status = "正在运行：\(macro.name)"
        execution = Task { [weak self] in
            defer { self?.execution = nil }
            for step in macro.steps {
                guard !Task.isCancelled else { self?.status = "宏已停止"; return }
                switch step.kind {
                case .key:
                    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: step.keyCode, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: step.keyCode, keyDown: false) else { self?.status = "无法创建按键事件"; return }
                    down.flags = CGEventFlags(rawValue: step.modifiers)
                    up.flags = down.flags
                    down.setIntegerValueField(.eventSourceUserData, value: 0x4D434D4143524F)
                    up.setIntegerValueField(.eventSourceUserData, value: 0x4D434D4143524F)
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                case .delay:
                    do { try await Task.sleep(for: .milliseconds(max(0, min(60_000, step.milliseconds)))) }
                    catch { self?.status = "宏已停止"; return }
                case .openApplication:
                    let url = URL(fileURLWithPath: step.applicationPath)
                    guard url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path) else { self?.status = "宏中的应用路径无效"; return }
                    do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
                    catch { self?.status = "打开应用失败：\(error.localizedDescription)"; return }
                }
            }
            self?.status = "宏已完成：\(macro.name)"
        }
    }

    func cancel() { execution?.cancel() }
    func pauseShortcuts() { removeMonitors() }
    func stop() { cancel(); removeMonitors() }
    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
