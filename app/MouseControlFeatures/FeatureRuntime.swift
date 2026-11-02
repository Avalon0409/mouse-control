import AppKit
import OpenSnekCore
import UserNotifications

struct NativeBatterySummary: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let devicePercent: Int?
    let systemPercent: Int?
    let message: String
}

@MainActor final class FeatureRuntime: ObservableObject {
    static let shared = FeatureRuntime()
    let scroll = ScrollRuntime()
    let macros = MacroRuntime()
    let nativeBattery = NativeBatteryPublisher()
    @Published private(set) var notificationStatus = "通知未开启"
    @Published private(set) var profileStatus = "应用配置切换未开启"
    @Published private(set) var nativeSummaries: [NativeBatterySummary] = []
    private weak var appState: AppState?
    private var loop: Task<Void, Never>?
    private var warnedDevices = Set<String>()
    private var lastRule: UUID?
    private var applyingRule = false

    func attach(_ appState: AppState) {
        self.appState = appState
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    private func tick() async {
        LanguageStore.shared.reload()
        IconStore.shared.reload()
        let store = FeatureStore.shared
        store.reload()
        let settings = store.settings
        guard (try? settings.validate()) != nil, let appState else { return }
        // The existing background service owns event taps and automation. The full window edits preferences.
        let ownsRuntime = appState.runtimeStore.isServiceProcess || !BackgroundServiceCoordinator.shared.backgroundServiceEnabled
        guard ownsRuntime else {
            scroll.refreshFromPreferences(status: UserDefaults.standard.string(forKey: "mouseControl.scrollRuntimeStatus"))
            macros.pauseShortcuts()
            if let data = UserDefaults.standard.data(forKey: "mouseControl.nativeBatteryStatus"), let summaries = try? JSONDecoder().decode([NativeBatterySummary].self, from: data) { nativeSummaries = summaries }
            return
        }
        let detected = appState.deviceStore.detectedDevices
        scroll.configureDeviceIdentities(detected.isEmpty ? appState.deviceStore.devices : detected, states: appState.deviceStore.stateByDeviceID)
        scroll.synchronize(enabled: settings.scrollEnabled)
        scroll.configure(settings.scrollingSettings(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        if UserDefaults.standard.string(forKey: "mouseControl.scrollRuntimeStatus") != scroll.status { UserDefaults.standard.set(scroll.status, forKey: "mouseControl.scrollRuntimeStatus") }
        macros.synchronize(enabled: settings.macrosEnabled, macros: settings.macros)
        let readings = appState.deviceStore.devices.map { device in
            let state = appState.deviceStore.stateByDeviceID[device.id] ?? (device.id == appState.deviceStore.selectedDeviceID ? appState.deviceStore.state : nil)
            return NativeBatteryReading(identity: NativeBatteryDeviceIdentity(id: device.id, name: device.product_name, vendorID: device.vendor_id, productID: device.product_id, transport: device.transport == .bluetooth ? .bluetoothLE : .usb), percent: state?.battery_percent, charging: state?.charging,
                                        connected: appState.deviceStore.connectionState(for: device) == .connected, observedAt: appState.deviceStore.lastTelemetryUpdate(for: device) ?? .distantPast)
        }
        nativeBattery.synchronize(readings: readings, enabled: settings.nativeBatteryIntegration)
        let summaries = nativeBattery.statuses.map { NativeBatterySummary(id: $0.id, name: $0.name, devicePercent: $0.devicePercent, systemPercent: $0.systemPercent, message: $0.message) }
        if summaries != nativeSummaries {
            nativeSummaries = summaries
            if let data = try? JSONEncoder().encode(summaries) { UserDefaults.standard.set(data, forKey: "mouseControl.nativeBatteryStatus") }
        }
        await notifyLowBatteries(appState: appState, settings: settings)
        await applyApplicationRule(appState: appState, settings: settings)
    }

    func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationStatus = granted ? "低电量通知已授权" : "通知权限未开启"
        } catch { notificationStatus = error.localizedDescription }
    }

    private func notifyLowBatteries(appState: AppState, settings: FeaturePreferences) async {
        guard settings.lowBatteryNotifications else { warnedDevices.removeAll(); return }
        let center = UNUserNotificationCenter.current()
        let permission = await center.notificationSettings()
        guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else { notificationStatus = "需要通知权限"; return }
        for device in appState.deviceStore.devices {
            guard appState.deviceStore.connectionState(for: device) == .connected else { continue }
            guard let state = appState.deviceStore.stateByDeviceID[device.id] ?? (appState.deviceStore.state?.device.id == device.id ? appState.deviceStore.state : nil),
                  let percent = state.battery_percent else { continue }
            if percent > settings.lowBatteryThreshold + 5 || state.charging == true { warnedDevices.remove(device.id); continue }
            guard percent <= settings.lowBatteryThreshold, state.charging != true, !warnedDevices.contains(device.id) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "鼠标电量较低"
            content.body = "\(device.product_name)：\(percent)%"
            content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "mouse-low-\(device.id)", content: content, trigger: nil))
                warnedDevices.insert(device.id)
                notificationStatus = "已发送低电量提醒"
            } catch { notificationStatus = error.localizedDescription }
        }
    }

    private func applyApplicationRule(appState: AppState, settings: FeaturePreferences) async {
        guard settings.applicationProfilesEnabled else { lastRule = nil; return }
        guard !applyingRule, let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, bundle != Bundle.main.bundleIdentifier else { return }
        guard let rule = settings.applicationRules.first(where: { $0.bundleIdentifier == bundle }) else { lastRule = nil; return }
        guard rule.id != lastRule,
              appState.deviceStore.devices.contains(where: { $0.id == rule.deviceID && appState.deviceStore.connectionState(for: $0) == .connected }) else { return }
        applyingRule = true
        defer { applyingRule = false }
        appState.deviceStore.selectDevice(rule.deviceID)
        await appState.deviceStore.refreshState()
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle,
              let profile = appState.editorStore.localProfiles.first(where: { $0.id == rule.profileID }),
              appState.editorStore.localProfileCanApply(profile) else { profileStatus = "规则配置暂不可应用"; return }
        await appState.editorStore.replaceSelectedProfile(with: profile.id)
        if let error = appState.deviceStore.errorMessage { profileStatus = error }
        else { lastRule = rule.id; profileStatus = "已应用：\(profile.name)" }
    }

    func stop() { loop?.cancel(); loop = nil; scroll.stop(); macros.stop(); nativeBattery.stop() }
}
