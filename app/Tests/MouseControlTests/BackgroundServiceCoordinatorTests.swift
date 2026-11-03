import AppKit
import XCTest
@testable import MouseControlTestHost

/// Exercises background service coordinator behavior.
final class BackgroundServiceCoordinatorTests: XCTestCase {
    @MainActor func testBackgroundOnlyPersistsAndKeepsMenuBarAvailable() {
        let suite = "BackgroundOnly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = BackgroundServiceCoordinator(defaults: defaults)
        coordinator.setBackgroundServiceEnabled(false)
        coordinator.setBackgroundOnly(true)
        let restarted = BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(restarted.backgroundOnly)
        XCTAssertTrue(restarted.backgroundServiceEnabled)
        coordinator.setBackgroundOnly(false)
        XCTAssertFalse(coordinator.backgroundOnly)
        XCTAssertTrue(coordinator.backgroundServiceEnabled)
    }

    @MainActor func testDisablingMenuBarLeavesBackgroundOnlyMode() {
        let suite = "BackgroundOnly.Disable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = BackgroundServiceCoordinator(defaults: defaults)
        coordinator.setBackgroundOnly(true)
        coordinator.setBackgroundServiceEnabled(false)
        XCTAssertFalse(coordinator.backgroundOnly)
        XCTAssertFalse(coordinator.backgroundServiceEnabled)
    }

    func testMenuBarReusesAccessoryWindowClientAndExcludesBackgroundService() {
        let applications: [BackgroundServiceCoordinator.RunningAppSnapshot] = [
            .init(processIdentifier: 101, activationPolicy: .accessory, isActive: true, isTerminated: false),
            .init(processIdentifier: 102, activationPolicy: .accessory, isActive: false, isTerminated: false),
            .init(processIdentifier: 103, activationPolicy: .accessory, isActive: false, isTerminated: true)
        ]
        let match = BackgroundServiceCoordinator.preferredReusableApplication(in: applications, excluding: 999, serviceProcessIdentifier: 101, includeAccessory: true)
        XCTAssertEqual(match?.processIdentifier, 102)
        XCTAssertNil(BackgroundServiceCoordinator.preferredReusableApplication(in: applications, excluding: 999))
    }
    func testFreshInstallDefaultsEnableMenuBarIcon() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!) }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        let launchAtStartupEnabled = await MainActor.run { coordinator.launchAtStartupEnabled }

        XCTAssertTrue(backgroundServiceEnabled)
        XCTAssertFalse(launchAtStartupEnabled)
    }

    func testExistingExplicitFalseSettingIsPreservedOnUpgrade() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: BackgroundServiceCoordinator.backgroundServiceEnabledDefaultsKey)

        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!) }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        XCTAssertFalse(backgroundServiceEnabled)
    }

    func testExistingExplicitTrueSettingIsPreservedOnUpgrade() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: BackgroundServiceCoordinator.backgroundServiceEnabledDefaultsKey)

        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!) }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        XCTAssertTrue(backgroundServiceEnabled)
    }

    func testQuittingCurrentServiceProcessDoesNotMutateStoredPreferences() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: BackgroundServiceCoordinator.backgroundServiceEnabledDefaultsKey)
        defaults.set(true, forKey: BackgroundServiceCoordinator.launchAtStartupDefaultsKey)

        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!) }
        let appState = await MainActor.run { AppState(launchRole: .service, serviceCoordinator: coordinator, autoStart: false) }

        await MainActor.run { appState.runtimeStore.prepareForCurrentServiceProcessTermination() }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        let launchAtStartupEnabled = await MainActor.run { coordinator.launchAtStartupEnabled }
        XCTAssertTrue(backgroundServiceEnabled)
        XCTAssertTrue(launchAtStartupEnabled)
    }

    func testPreferredReusableApplicationPrefersActiveRegularApp() {
        let selected = BackgroundServiceCoordinator.preferredReusableApplication(
            in: [
                .init(processIdentifier: 101, activationPolicy: .accessory, isActive: true, isTerminated: false), .init(processIdentifier: 102, activationPolicy: .regular, isActive: false, isTerminated: false),
                .init(processIdentifier: 103, activationPolicy: .regular, isActive: true, isTerminated: false)
            ], excluding: 101)

        XCTAssertEqual(selected?.processIdentifier, 103)
    }

    func testPreferredReusableApplicationExcludesCurrentAndTerminatedProcesses() {
        let selected = BackgroundServiceCoordinator.preferredReusableApplication(
            in: [
                .init(processIdentifier: 201, activationPolicy: .regular, isActive: true, isTerminated: false), .init(processIdentifier: 202, activationPolicy: .regular, isActive: false, isTerminated: true),
                .init(processIdentifier: 203, activationPolicy: .accessory, isActive: false, isTerminated: false)
            ], excluding: 201)

        XCTAssertNil(selected)
    }

    func testOtherRunningApplicationsToTerminateIncludesAllOtherLiveInstances() {
        let targets = BackgroundServiceCoordinator.otherRunningApplicationsToTerminate(
            in: [
                .init(processIdentifier: 301, activationPolicy: .accessory, isActive: true, isTerminated: false), .init(processIdentifier: 302, activationPolicy: .regular, isActive: true, isTerminated: false),
                .init(processIdentifier: 303, activationPolicy: .accessory, isActive: false, isTerminated: false), .init(processIdentifier: 304, activationPolicy: .regular, isActive: false, isTerminated: true)
            ], excluding: 301)

        XCTAssertEqual(targets.map(\.processIdentifier), [302, 303])
    }

    func testSynchronizeLaunchAgentUpdatesLegacyBundlePathWhenEnabled() async throws {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: BackgroundServiceCoordinator.launchAtStartupDefaultsKey)

        let launchAgentsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: launchAgentsDirectory) }

        let launchAgentURL = launchAgentsDirectory.appendingPathComponent("local.mousecontrol.MouseControl.service.plist")
        let legacyPlist = BackgroundServiceCoordinator.launchAgentPropertyList(executablePath: "/Applications/Open Snek.app/Contents/MacOS/OpenSnek", workingDirectoryPath: "/Applications/Open Snek.app/Contents/MacOS")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacyPlist, format: .xml, options: 0)
        try legacyData.write(to: launchAgentURL, options: .atomic)

        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!, launchAgentsDirectoryURL: launchAgentsDirectory) }

        try await MainActor.run { try coordinator.synchronizeLaunchAgentIfNeeded(executablePath: "/Applications/OpenSnek.app/Contents/MacOS/OpenSnek", workingDirectoryPath: "/Applications/OpenSnek.app/Contents/MacOS") }

        let plist = try XCTUnwrap(NSDictionary(contentsOf: launchAgentURL) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Applications/OpenSnek.app/Contents/MacOS/OpenSnek", "--service-mode", "--login-start"])
        XCTAssertEqual(plist["WorkingDirectory"] as? String, "/Applications/OpenSnek.app/Contents/MacOS")
    }
}
