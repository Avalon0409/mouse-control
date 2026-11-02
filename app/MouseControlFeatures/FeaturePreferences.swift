import AppKit
import Foundation

struct ApplicationProfileRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleIdentifier: String
    var deviceID: String
    var profileID: UUID
    var scroll: ApplicationScrollSettings?
}

struct ApplicationScrollSettings: Codable, Equatable {
    var smoothScrolling = false
    var smoothDuration = 0.16
    var multiplier = 1.0
    var acceleration = 0.0
}

struct MacroStep: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case key, delay, openApplication }
    var id = UUID()
    var kind: Kind = .key
    var keyCode: UInt16 = 0
    var modifiers: UInt64 = 0
    var milliseconds: Int = 100
    var applicationPath: String = ""
}

struct InputMacro: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "新宏"
    var shortcutKeyCode: UInt16 = 99
    var shortcutModifiers: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
    var steps: [MacroStep] = []
}

struct FeaturePreferences: Codable, Equatable {
    static let defaultUpdateRepository = "Avalon0409/mouse-control"
    var scrollEnabled = false
    var smoothScrolling = false
    var smoothDuration = 0.16
    var scrollMultiplier = 1.0
    var scrollAcceleration = 0.0
    var lowBatteryNotifications = false
    var lowBatteryThreshold = 15
    var nativeBatteryIntegration = false
    var applicationProfilesEnabled = false
    var applicationRules: [ApplicationProfileRule] = []
    var macrosEnabled = false
    var macros: [InputMacro] = []
    var updateRepository = Self.defaultUpdateRepository
    var updateFeedURL = ""

    func scrollingSettings(for bundleIdentifier: String?) -> FeaturePreferences {
        guard applicationProfilesEnabled, let bundleIdentifier,
              let scroll = applicationRules.first(where: { $0.bundleIdentifier == bundleIdentifier })?.scroll else { return self }
        var effective = self
        effective.smoothScrolling = scroll.smoothScrolling
        effective.smoothDuration = scroll.smoothDuration
        effective.scrollMultiplier = scroll.multiplier
        effective.scrollAcceleration = scroll.acceleration
        return effective
    }

    func validate() throws {
        guard smoothDuration.isFinite, (0.04...0.6).contains(smoothDuration),
              scrollMultiplier.isFinite, (0.1...5).contains(scrollMultiplier), scrollAcceleration.isFinite, (0...2).contains(scrollAcceleration),
              (1...99).contains(lowBatteryThreshold), applicationRules.count <= 100,
              applicationRules.allSatisfy({ rule in
                  guard let scroll = rule.scroll else { return true }
                  return scroll.smoothDuration.isFinite && (0.04...0.6).contains(scroll.smoothDuration) &&
                      scroll.multiplier.isFinite && (0.1...5).contains(scroll.multiplier) &&
                      scroll.acceleration.isFinite && (0...2).contains(scroll.acceleration)
              }),
              macros.count <= 100, macros.allSatisfy({ $0.steps.count <= 200 && $0.steps.allSatisfy { (0...60_000).contains($0.milliseconds) } }) else {
            throw FeatureConfigurationError.invalid
        }
        let chords = macros.map { "\($0.shortcutKeyCode):\($0.shortcutModifiers)" }
        guard Set(chords).count == chords.count else { throw FeatureConfigurationError.duplicateShortcut }
        let allowedModifiers = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
        guard Set(macros.map(\.id)).count == macros.count,
              Set(applicationRules.map(\.id)).count == applicationRules.count,
              macros.allSatisfy({ macro in
                  macro.shortcutKeyCode <= 127 && macro.shortcutModifiers & ~allowedModifiers == 0 &&
                  Set(macro.steps.map(\.id)).count == macro.steps.count &&
                  macro.steps.filter { $0.kind == .delay }.reduce(0, { $0 + $1.milliseconds }) <= 300_000 &&
                  macro.steps.allSatisfy { $0.kind != .key || ($0.keyCode <= 127 && $0.modifiers & ~allowedModifiers == 0) }
              }) else { throw FeatureConfigurationError.invalid }
    }
}

enum FeatureConfigurationError: LocalizedError {
    case invalid, duplicateShortcut, incompatibleVersion
    var errorDescription: String? {
        switch self {
        case .invalid: return "配置包含超出范围的参数。"
        case .duplicateShortcut: return "多个宏使用了相同快捷键。"
        case .incompatibleVersion: return "该配置文件版本不受支持。"
        }
    }
}

struct ConfigurationArchive: Codable {
    let version: Int
    let settings: FeaturePreferences
    let preferences: Data
}

@MainActor final class FeatureStore: ObservableObject {
    static let shared = FeatureStore()
    nonisolated static let key = "mouseControl.extendedSettings"
    @Published var settings: FeaturePreferences {
        didSet {
            do { try settings.validate() }
            catch { message = error.localizedDescription; settings = oldValue; return }
            guard let data = try? JSONEncoder().encode(settings) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }
    @Published var message: String?
    private let defaults: UserDefaults
    private let domainName: String?

    init(defaults: UserDefaults = .standard, domainName: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        self.domainName = domainName
        if let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(FeaturePreferences.self, from: data), (try? value.validate()) != nil { settings = value }
        else { settings = FeaturePreferences() }
    }

    func reload() {
        guard let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(FeaturePreferences.self, from: data), value != settings, (try? value.validate()) != nil else { return }
        settings = value
    }

    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MouseControl.mouseconfig"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try archiveData().write(to: url, options: .atomic)
            message = "配置已导出。"
        } catch { message = error.localizedDescription }
    }

    func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 4 * 1024 * 1024 else { throw FeatureConfigurationError.invalid }
            try importArchiveData(Data(contentsOf: url))
            message = "配置已导入；重新打开应用读取配置库，再开启需要的自动功能。"
        } catch { message = error.localizedDescription }
    }

    private func isPortableKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return !lower.contains("launch") && !lower.contains("service") &&
            key != "mouseControl.nativeBatteryStatus" && key != "mouseControl.scrollRuntimeStatus"
    }

    func archiveData() throws -> Data {
        let values = (domainName.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]).filter { isPortableKey($0.key) }
        let preferences = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        return try JSONEncoder().encode(ConfigurationArchive(version: 1, settings: settings, preferences: preferences))
    }

    func importArchiveData(_ data: Data, backupDirectory: URL? = nil) throws {
        guard data.count <= 4 * 1024 * 1024 else { throw FeatureConfigurationError.invalid }
        let archive = try JSONDecoder().decode(ConfigurationArchive.self, from: data)
        guard archive.version == 1 else { throw FeatureConfigurationError.incompatibleVersion }
        try archive.settings.validate()
        guard let values = try PropertyListSerialization.propertyList(from: archive.preferences, format: nil) as? [String: Any] else { throw FeatureConfigurationError.invalid }
        if let domainName, let current = defaults.persistentDomain(forName: domainName) {
            let backup = try PropertyListSerialization.data(fromPropertyList: current, format: .binary, options: 0)
            let directory = backupDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MouseControl/Backups")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try backup.write(to: directory.appendingPathComponent("before-import-\(UUID().uuidString).plist"), options: .atomic)
        }
        for (key, value) in values where isPortableKey(key) && key != Self.key {
            if key.hasPrefix("connectBehavior.") { defaults.set("use_mouse_settings", forKey: key) }
            else if key.hasPrefix("softwareLightingApplyOnConnect.") { defaults.set(false, forKey: key) }
            else { defaults.set(value, forKey: key) }
        }
        var safeSettings = archive.settings
        safeSettings.scrollEnabled = false
        safeSettings.macrosEnabled = false
        safeSettings.applicationProfilesEnabled = false
        safeSettings.nativeBatteryIntegration = false
        settings = safeSettings
    }

    func importScrollReverserSettings() {
        guard let sources = UserDefaults(suiteName: "com.pilotmoon.scroll-reverser")?.dictionary(forKey: "Sources") else { message = "没有找到 Scroll Reverser 的来源设置。"; return }
        defaults.set(sources, forKey: "Sources")
        message = "滚动来源设置已复制。"
    }
}
