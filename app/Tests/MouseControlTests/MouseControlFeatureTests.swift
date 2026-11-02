import AppKit
import XCTest
@testable import MouseControlTestHost

@MainActor final class MouseControlFeatureTests: XCTestCase {
    func testBothApplicationIconsLoadAndMenuMaskHasTransparency() throws {
        for style in AppIconStyle.allCases {
            let image = try XCTUnwrap(style.image())
            XCTAssertGreaterThan(image.size.width, 0)
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "psyduck-menu-template", withExtension: "png"))
        let representation = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        XCTAssertTrue(representation.hasAlpha)
        XCTAssertEqual(try XCTUnwrap(representation.colorAt(x: 0, y: 0)).alphaComponent, 0)
    }
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "mousecontrol-tests-\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    func testIconSelectionPersistsAndReloadsAcrossStores() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let bundle = Bundle(for: Self.self)
        let window = IconStore(defaults: defaults, bundle: bundle)
        let service = IconStore(defaults: defaults, bundle: bundle)
        XCTAssertEqual(window.style, .mouse)
        window.style = .psyduck
        service.reload()
        XCTAssertEqual(service.style, .psyduck)
        service.style = .mouse
        window.reload()
        XCTAssertEqual(window.style, .mouse)
        XCTAssertEqual(IconStore(defaults: defaults, bundle: bundle).style, .mouse)
    }

    func testInvalidSavedIconFallsBackToMouse() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("removed-icon", forKey: "mouseControl.icon")
        XCTAssertEqual(IconStore(defaults: defaults).style, .mouse)
    }

    func testChineseDefaultAndLanguagePersistence() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = LanguageStore(defaults: defaults)
        let second = LanguageStore(defaults: defaults)
        XCTAssertEqual(first.language, "zh-Hans")
        first.language = "en"
        second.reload()
        XCTAssertEqual(second.language, "en")
        second.language = "unsupported"
        XCTAssertEqual(second.language, "en")
        XCTAssertEqual(defaults.string(forKey: "mouseControl.language"), "en")
    }

    func testInvalidStoredLanguageRecoversToChinese() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("unsupported", forKey: "mouseControl.language")
        XCTAssertEqual(LanguageStore(defaults: defaults).language, "zh-Hans")
    }

    func testInvalidSettingEditKeepsLastValidConfiguration() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FeatureStore(defaults: defaults, domainName: name)
        store.settings.scrollMultiplier = 1.4
        store.settings.scrollMultiplier = .nan
        XCTAssertEqual(store.settings.scrollMultiplier, 1.4)
        let data = try XCTUnwrap(defaults.data(forKey: FeatureStore.key))
        XCTAssertEqual(try JSONDecoder().decode(FeaturePreferences.self, from: data).scrollMultiplier, 1.4)
        XCTAssertNotNil(store.message)
    }

    func testSettingsReloadAcrossWindowAndService() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let window = FeatureStore(defaults: defaults, domainName: name)
        let service = FeatureStore(defaults: defaults, domainName: name)
        window.settings.smoothScrolling = true
        service.reload()
        XCTAssertTrue(service.settings.smoothScrolling)
        service.settings.scrollEnabled = false
        service.settings.scrollMultiplier = 1.2
        window.reload()
        XCTAssertTrue(window.settings.smoothScrolling)
        XCTAssertEqual(window.settings.scrollMultiplier, 1.2)
    }

    func testImportPreservesLocalRuntimeAndDisablesAutomaticHardwareChanges() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "backgroundServiceEnabled")
        defaults.set(false, forKey: "launchServiceAtStartup")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imported: [String: Any] = ["backgroundServiceEnabled": false, "launchServiceAtStartup": true,
            "connectBehavior.device": "restore_last_profile", "softwareLightingApplyOnConnect.device": true,
            "mouseControl.icon": "psyduck", "openSnekLocalProfiles": Data([1, 2, 3])]
        var settings = FeaturePreferences()
        settings.scrollEnabled = true
        settings.macrosEnabled = true
        settings.nativeBatteryIntegration = true
        settings.applicationProfilesEnabled = true
        let plist = try PropertyListSerialization.data(fromPropertyList: imported, format: .binary, options: 0)
        let archive = try JSONEncoder().encode(ConfigurationArchive(version: 1, settings: settings, preferences: plist))
        let store = FeatureStore(defaults: defaults, domainName: name)
        try store.importArchiveData(archive, backupDirectory: directory)
        XCTAssertTrue(defaults.bool(forKey: "backgroundServiceEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "launchServiceAtStartup"))
        XCTAssertEqual(defaults.string(forKey: "connectBehavior.device"), "use_mouse_settings")
        XCTAssertFalse(defaults.bool(forKey: "softwareLightingApplyOnConnect.device"))
        XCTAssertEqual(defaults.string(forKey: "mouseControl.icon"), "psyduck")
        XCTAssertEqual(defaults.data(forKey: "openSnekLocalProfiles"), Data([1, 2, 3]))
        XCTAssertFalse(store.settings.scrollEnabled)
        XCTAssertFalse(store.settings.macrosEnabled)
        XCTAssertFalse(store.settings.nativeBatteryIntegration)
        XCTAssertFalse(store.settings.applicationProfilesEnabled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count, 1)
    }

    func testBadArchiveDoesNotMutateSettingsOrCreateBackup() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FeatureStore(defaults: defaults, domainName: name)
        store.settings.scrollMultiplier = 1.3
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["mouseControl.icon": "psyduck"], format: .binary, options: 0)
        let archive = try JSONEncoder().encode(ConfigurationArchive(version: 99, settings: FeaturePreferences(), preferences: plist))
        XCTAssertThrowsError(try store.importArchiveData(archive, backupDirectory: directory))
        XCTAssertEqual(store.settings.scrollMultiplier, 1.3)
        XCTAssertNil(defaults.string(forKey: "mouseControl.icon"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testExportOmitsRuntimeConnectionAndStatusValues() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(123, forKey: "backgroundServicePID")
        defaults.set("runtime", forKey: "backgroundServiceEndpoint")
        defaults.set("status", forKey: "mouseControl.nativeBatteryStatus")
        defaults.set("psyduck", forKey: "mouseControl.icon")
        let store = FeatureStore(defaults: defaults, domainName: name)
        let archive = try JSONDecoder().decode(ConfigurationArchive.self, from: store.archiveData())
        let values = try XCTUnwrap(try PropertyListSerialization.propertyList(from: archive.preferences, format: nil) as? [String: Any])
        XCTAssertNil(values["backgroundServicePID"])
        XCTAssertNil(values["backgroundServiceEndpoint"])
        XCTAssertNil(values["mouseControl.nativeBatteryStatus"])
        XCTAssertEqual(values["mouseControl.icon"] as? String, "psyduck")
    }

    func testMacroValidationRejectsDuplicateChordsAndExcessiveDelay() {
        let first = InputMacro(shortcutKeyCode: 99)
        let second = InputMacro(shortcutKeyCode: 99)
        XCTAssertThrowsError(try FeaturePreferences(macros: [first, second]).validate())
        let excessive = InputMacro(steps: (0..<6).map { _ in MacroStep(kind: .delay, milliseconds: 60_000) })
        XCTAssertThrowsError(try FeaturePreferences(macros: [excessive]).validate())
        XCTAssertNoThrow(try FeaturePreferences(macros: [InputMacro(steps: [MacroStep(kind: .delay, milliseconds: 500)])]).validate())
    }

    func testMacroValidationRejectsDuplicateStepIDsAndInvalidKeys() {
        let step = MacroStep()
        XCTAssertThrowsError(try FeaturePreferences(macros: [InputMacro(steps: [step, step])]).validate())
        XCTAssertThrowsError(try FeaturePreferences(macros: [InputMacro(shortcutKeyCode: 255)]).validate())
        XCTAssertThrowsError(try FeaturePreferences(macros: [InputMacro(steps: [MacroStep(modifiers: UInt64.max)])]).validate())
    }

    func testSourceSavePreservesOtherProcessSettingsAndUnknownFields() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let source: [String: Any] = ["Kind": 0, "Category": 1, "Continuous": false, "VerticalMode": 2, "HorizontalMode": 0, "StepSize": 3, "StepSizeEnabled": true, "FutureSetting": "keep"]
        defaults.set(["mouse": source], forKey: "Sources")
        let stale = SourceTable(userDefaults: defaults)
        let window = SourceTable(userDefaults: defaults)
        let windowRow = try XCTUnwrap(window.rows.first)
        windowRow.verticalMode = ScrollDirectionMode(rawValue: 1)!
        window.save()
        let staleRow = try XCTUnwrap(stale.rows.first)
        staleRow.stepSize = 5
        stale.save()
        let saved = try XCTUnwrap(defaults.dictionary(forKey: "Sources")?["mouse"] as? [String: Any])
        XCTAssertEqual(saved["VerticalMode"] as? Int, 1)
        XCTAssertEqual(saved["StepSize"] as? Int, 5)
        XCTAssertEqual(saved["FutureSetting"] as? String, "keep")
        staleRow.customName = "My mouse"
        stale.save()
        let again = try XCTUnwrap(defaults.dictionary(forKey: "Sources")?["mouse"] as? [String: Any])
        XCTAssertEqual(again["VerticalMode"] as? Int, 1)
    }

    func testSourceSaveDoesNotResurrectRemovedRow() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["mouse": ["Kind": 0, "Category": 1, "VerticalMode": 2, "HorizontalMode": 0]], forKey: "Sources")
        let stale = SourceTable(userDefaults: defaults)
        let window = SourceTable(userDefaults: defaults)
        window.removeRow(try XCTUnwrap(window.rows.first))
        window.save()
        stale.rows.first?.customName = "old"
        stale.save()
        XCTAssertNil(defaults.dictionary(forKey: "Sources")?["mouse"])
    }

    func testApplicationScrollRuleFallsBackToGlobalOnExitAndWhenDisabled() throws {
        var preferences = FeaturePreferences()
        preferences.scrollMultiplier = 1.2
        preferences.applicationProfilesEnabled = true
        preferences.applicationRules = [ApplicationProfileRule(bundleIdentifier: "test.editor", deviceID: "mouse", profileID: UUID(), scroll: ApplicationScrollSettings(multiplier: 2.0))]
        XCTAssertEqual(preferences.scrollingSettings(for: "test.editor").scrollMultiplier, 2.0)
        XCTAssertEqual(preferences.scrollingSettings(for: "test.other").scrollMultiplier, 1.2)
        preferences.applicationProfilesEnabled = false
        XCTAssertEqual(preferences.scrollingSettings(for: "test.editor").scrollMultiplier, 1.2)
        preferences.applicationRules[0].scroll?.acceleration = .infinity
        XCTAssertThrowsError(try preferences.validate())
    }
}
