import AppKit
import ApplicationServices
import OpenSnekCore

@MainActor final class ScrollRuntime: ObservableObject {
    @Published private(set) var rows: [SourceRow] = []
    @Published private(set) var status = "滚动处理未开启"
    private var sourceTable = SourceTable(userDefaults: .standard)
    private var tap: MouseTap?
    private var lastSettingsFingerprint: Data?
    private var deviceIdentities: [String: String] = [:]

    private func settingsFingerprint() -> Data? {
        let sources = UserDefaults.standard.dictionary(forKey: "Sources") ?? [:]
        let fields = Set(["VerticalMode", "HorizontalMode", "StepSize", "StepSizeEnabled", "CustomName"])
        let settings = sources.mapValues { value -> [String: Any] in
            (value as? [String: Any] ?? [:]).filter { fields.contains($0.key) }
        }
        return try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
    }

    func synchronize(enabled: Bool) {
        guard enabled else { stop(); return }
        let conflict = NSRunningApplication.runningApplications(withBundleIdentifier: "com.pilotmoon.scroll-reverser").contains { !$0.isTerminated }
        guard !conflict else { stop(); status = "请退出 Scroll Reverser 后开启，避免重复反转。"; return }
        let fingerprint = settingsFingerprint()
        if tap != nil, fingerprint != lastSettingsFingerprint {
            // Another app process edited settings. Release the old tap without saving stale rows.
            tap?.isActive = false
            tap = nil
            sourceTable.discardPendingSave()
        }
        if tap == nil {
            sourceTable = SourceTable(userDefaults: .standard)
            guard let newTap = MouseTap(sourceTable: sourceTable) else { status = "无法创建滚动处理器"; return }
            newTap.deviceIdentities = deviceIdentities
            newTap.isActive = true
            guard newTap.isActive else {
                status = AXIsProcessTrusted() ? "滚动事件入口未启动" : "需要辅助功能权限"
                rows = sourceTable.rows
                return
            }
            tap = newTap
        }
        tap?.enable()
        rows = sourceTable.rows
        lastSettingsFingerprint = fingerprint
        status = tap?.isActive == true ? "滚动处理运行中" : "滚动事件入口未启动"
    }

    func stop() {
        let wasRunning = tap != nil
        tap?.isActive = false
        tap = nil
        if wasRunning { sourceTable.save() }
        rows = sourceTable.rows
        status = "滚动处理未开启"
    }

    func reloadSources() { stop(); sourceTable = SourceTable(userDefaults: .standard); rows = sourceTable.rows }
    func refreshFromPreferences(status: String? = nil) {
        if tap != nil { stop() }
        let fingerprint = settingsFingerprint()
        if fingerprint != lastSettingsFingerprint {
            sourceTable.discardPendingSave()
            sourceTable = SourceTable(userDefaults: .standard)
            rows = sourceTable.rows
            lastSettingsFingerprint = fingerprint
        }
        if let status { self.status = status }
    }
    func remove(_ row: SourceRow) { sourceTable.removeRow(row); sourceTable.save(); rows = sourceTable.rows }
    func save() { sourceTable.save(); lastSettingsFingerprint = settingsFingerprint(); objectWillChange.send() }
    func configure(_ settings: FeaturePreferences) {
        tap?.smoothScrolling = settings.smoothScrolling
        tap?.smoothDuration = settings.smoothDuration
        tap?.scrollMultiplier = settings.scrollMultiplier
        tap?.scrollAcceleration = settings.scrollAcceleration
    }

    func configureDeviceIdentities(_ devices: [MouseDevice], states: [String: MouseState]) {
        var identities: [String: String] = [:]
        let groups = Dictionary(grouping: devices) { device in String(format: "%04x:%04x:*:%@", device.vendor_id, device.product_id, device.transport.rawValue) }
        for device in devices {
            let serial = DevicePersistenceKeys.normalizedStableSerial(states[device.id]?.device.serial) ?? DevicePersistenceKeys.normalizedStableSerial(device.serial)
            let identity = serial.map { "serial:\($0)" } ?? DevicePersistenceKeys.key(for: device)
            identities[device.id] = identity
            let group = String(format: "%04x:%04x:*:%@", device.vendor_id, device.product_id, device.transport.rawValue)
            if groups[group]?.count == 1 { identities[group] = identity }
        }
        guard identities != deviceIdentities else { return }
        deviceIdentities = identities
        tap?.deviceIdentities = identities
    }

    private func sources(for device: MouseDevice) -> [ScrollSource] {
        let properties: [String: Any] = ["Product": device.product_name, "VendorID": device.vendor_id, "ProductID": device.product_id,
                                        "Transport": device.transport == .usb ? "USB" : "Bluetooth Low Energy", "LocationID": device.location_id,
                                        "SerialNumber": device.serial ?? "", "MouseControlPhysicalIdentity": DevicePersistenceKeys.key(for: device)]
        return ScrollSource.deviceSources(kind: ScrollSourceKind(rawValue: 0)!, properties: properties, trackpadDriver: false)
    }

    func deviceRow(for device: MouseDevice) -> SourceRow? {
        let keys = Set(sources(for: device).map(\.key))
        return rows.filter { keys.contains($0.key) }.max { $0.lastSeen < $1.lastSeen }
    }

    func prepareDeviceRow(for device: MouseDevice) {
        if tap == nil { sourceTable.discardPendingSave(); sourceTable = SourceTable(userDefaults: .standard) }
        let source = sources(for: device)[0]
        _ = sourceTable.record(source, natural: true, amount: 0)
        sourceTable.save()
        rows = sourceTable.rows
        lastSettingsFingerprint = settingsFingerprint()
    }

    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
