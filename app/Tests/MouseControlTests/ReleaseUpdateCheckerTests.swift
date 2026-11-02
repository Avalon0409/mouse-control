import XCTest
import OpenSnekAppSupport
@testable import MouseControlTestHost

/// Exercises release update checker behavior.
final class ReleaseUpdateCheckerTests: XCTestCase {
    func testFreshInstallUsesMouseControlReleaseRepository() throws {
        let name = "ReleaseUpdateCheckerTests.Fresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ReleaseUpdateChecker.configuration(defaults: defaults)?.updateRepository, "Avalon0409/mouse-control")
    }

    func testLegacyEmptyRepositoryUsesMouseControlWithoutChangingOtherSettings() throws {
        let name = "ReleaseUpdateCheckerTests.Legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = FeaturePreferences()
        settings.updateRepository = ""
        settings.scrollMultiplier = 2.5
        defaults.set(try JSONEncoder().encode(settings), forKey: FeatureStore.key)
        XCTAssertEqual(ReleaseUpdateChecker.configuration(defaults: defaults)?.updateRepository, "Avalon0409/mouse-control")
        XCTAssertEqual(ReleaseUpdateChecker.configuration(defaults: defaults)?.scrollMultiplier, 2.5)
        XCTAssertEqual(try JSONDecoder().decode(FeaturePreferences.self, from: XCTUnwrap(defaults.data(forKey: FeatureStore.key))).updateRepository, "")
    }

    func testCustomReleaseRepositoryAndFeedRemainConfigured() throws {
        let name = "ReleaseUpdateCheckerTests.Custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = FeaturePreferences()
        settings.updateRepository = "example/custom-mouse"
        settings.updateFeedURL = "https://example.com/appcast.xml"
        defaults.set(try JSONEncoder().encode(settings), forKey: FeatureStore.key)
        XCTAssertEqual(ReleaseUpdateChecker.configuration(defaults: defaults)?.updateRepository, settings.updateRepository)
        XCTAssertEqual(ReleaseUpdateChecker.configuration(defaults: defaults)?.updateFeedURL, settings.updateFeedURL)
    }
    func testReleaseVersionParsesLeadingVPrefix() { XCTAssertEqual(ReleaseVersion.parse("v1.2.3"), ReleaseVersion(components: [1, 2, 3], preRelease: [])) }

    func testReleaseVersionParsesPreReleaseSuffix() { XCTAssertEqual(ReleaseVersion.parse("0.0.0-alpha.5"), ReleaseVersion(components: [0, 0, 0], preRelease: [.textual("alpha"), .numeric(5)])) }

    func testReleaseVersionComparesDifferentComponentLengths() {
        XCTAssertTrue(ReleaseVersion.parse("1.2.1")! > ReleaseVersion.parse("1.2")!)
        XCTAssertTrue(ReleaseVersion.parse("1.2")! == ReleaseVersion.parse("1.2.0")!)
    }

    func testReleaseVersionComparesPreReleaseIterations() { XCTAssertTrue(ReleaseVersion.parse("0.1.0-alpha.3")! > ReleaseVersion.parse("0.1.0-alpha.1")!) }

    func testStableReleaseBeatsPreReleaseOfSameCoreVersion() { XCTAssertTrue(ReleaseVersion.parse("0.1.0")! > ReleaseVersion.parse("0.1.0-alpha.3")!) }

    func testReleaseVersionRejectsNonNumericValues() {
        XCTAssertNil(ReleaseVersion.parse("main"))
        XCTAssertNil(ReleaseVersion.parse("v1.beta.0"))
    }

    func testCurrentBuildChannelDefaultsToReleaseWhenUnset() {
        let bundle = bundleWithInfoDictionary([:])
        XCTAssertEqual(ReleaseUpdateChecker.currentBuildChannel(bundle: bundle), .release)
        XCTAssertEqual(ReleaseUpdateChecker.shouldCheckForUpdates(bundle: bundle), ReleaseUpdateChecker.configuration != nil)
    }

    func testCurrentBuildChannelRecognizesDevBuilds() {
        let bundle = bundleWithInfoDictionary(["OpenSnekBuildChannel": "dev"])
        XCTAssertEqual(ReleaseUpdateChecker.currentBuildChannel(bundle: bundle), .dev)
        XCTAssertFalse(ReleaseUpdateChecker.shouldCheckForUpdates(bundle: bundle))
    }

    func testDryRunAppcastDefaultsToReleaseAssetURL() { XCTAssertEqual(ReleaseUpdateChecker.dryRunAppcastURL(), ReleaseUpdateChecker.defaultDryRunAppcastURL) }

    func testDryRunAppcastUsesDeveloperOverrideURL() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OpenSnek.ReleaseUpdateCheckerTests.dryRunAppcast"))
        defer { defaults.removePersistentDomain(forName: "OpenSnek.ReleaseUpdateCheckerTests.dryRunAppcast") }
        let overrideURL = URL(string: "https://example.com/branch-appcast.xml")!
        defaults.set(overrideURL.absoluteString, forKey: DeveloperRuntimeOptions.releaseUpdateDryRunAppcastURLDefaultsKey)

        XCTAssertEqual(ReleaseUpdateChecker.dryRunAppcastURL(defaults: defaults), overrideURL)
    }
}

/// Stores release update checker test bundle test data.
private final class ReleaseUpdateCheckerTestBundle: Bundle, @unchecked Sendable {
    private let testInfoDictionary: [String: Any]

    init(infoDictionary: [String: Any]) {
        self.testInfoDictionary = infoDictionary
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? { testInfoDictionary[key] }
}

private func bundleWithInfoDictionary(_ infoDictionary: [String: Any]) -> Bundle { ReleaseUpdateCheckerTestBundle(infoDictionary: infoDictionary) }
