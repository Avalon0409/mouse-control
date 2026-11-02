import XCTest
import OpenSnekCore
import OpenSnekAppSupport
import OpenSnekHardware
@testable import MouseControlTestHost

final class MouseIdentityTests: XCTestCase {
    private func mouse(_ id: String, transport: DeviceTransportKind, serial: String?) -> MouseDevice {
        let profile = transport == .usb ? DeviceProfiles.orochiV2USB : DeviceProfiles.orochiV2Bluetooth
        return MouseDevice(id: id, vendor_id: 0x1532, product_id: transport == .usb ? 0x0094 : 0x0095, product_name: "Orochi V2", transport: transport, path_b64: "", serial: serial, firmware: nil, profile_id: .orochiV2, button_layout: profile.buttonLayout)
    }

    func testSamePhysicalMouseSharesPreferencesAcrossTransports() {
        let name = "identity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DevicePreferenceStore(defaults: defaults)
        let usb = mouse("receiver-one", transport: .usb, serial: "SN-ONE")
        let bluetooth = mouse("bluetooth-one", transport: .bluetooth, serial: "sn-one")
        XCTAssertEqual(DevicePersistenceKeys.key(for: usb), DevicePersistenceKeys.key(for: bluetooth))
        store.persistConnectBehavior(.restoreOpenSnekSettings, device: usb)
        XCTAssertEqual(store.loadConnectBehavior(device: bluetooth), .restoreOpenSnekSettings)
        let profile = UUID()
        store.persistSelectedLocalProfileID(profile, device: usb)
        XCTAssertEqual(store.loadSelectedLocalProfileID(device: bluetooth), profile)
        store.persistSelectedLocalProfileID(nil, device: bluetooth)
        XCTAssertNil(store.loadSelectedLocalProfileID(device: usb))
    }

    func testIdenticalModelsWithoutValidSerialKeepSeparateSettings() {
        let name = "identity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DevicePreferenceStore(defaults: defaults)
        let first = mouse("receiver-one", transport: .usb, serial: "00000000")
        let second = mouse("receiver-two", transport: .usb, serial: nil)
        XCTAssertNotEqual(DevicePersistenceKeys.key(for: first), DevicePersistenceKeys.key(for: second))
        store.persistConnectBehavior(.restoreOpenSnekSettings, device: first)
        XCTAssertNil(store.loadConnectBehavior(device: second))
    }

    func testLegacyPreferenceRemainsReadableAfterIdentityUpgrade() {
        let name = "identity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DevicePreferenceStore(defaults: defaults)
        let device = mouse("receiver-one", transport: .usb, serial: "SN-ONE")
        defaults.set(DeviceConnectBehavior.useMouseSettings.rawValue, forKey: "connectBehavior.\(DevicePersistenceKeys.priorModelKey(for: device))")
        XCTAssertEqual(store.loadConnectBehavior(device: device), .useMouseSettings)
        store.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        XCTAssertEqual(store.loadConnectBehavior(device: device), .restoreOpenSnekSettings)
        XCTAssertEqual(defaults.string(forKey: "connectBehavior.\(DevicePersistenceKeys.priorModelKey(for: device))"), DeviceConnectBehavior.useMouseSettings.rawValue)
    }

    func testLegacySettingsStayWithTheirFirstResolvedMouseWhenSamePortIsReused() {
        let name = "identity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DevicePreferenceStore(defaults: defaults)
        let anonymous = mouse("same-port", transport: .usb, serial: nil)
        let first = anonymous.withMetadata(serial: "SN-ONE", firmware: nil)
        let second = anonymous.withMetadata(serial: "SN-TWO", firmware: nil)
        store.persistConnectBehavior(.restoreOpenSnekSettings, device: anonymous)
        store.migrateResolvedIdentity(from: anonymous, to: first)
        store.migrateResolvedIdentity(from: anonymous, to: second)
        XCTAssertEqual(store.loadConnectBehavior(device: first), .restoreOpenSnekSettings)
        XCTAssertNil(store.loadConnectBehavior(device: second))
    }

    func testReceiverAndBluetoothResolveSameFamilyAndButtons() throws {
        let usb = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x0094, transport: .usb))
        let bluetooth = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x0095, transport: .bluetooth))
        XCTAssertEqual(usb.id, bluetooth.id)
        XCTAssertEqual(usb.buttonLayout, bluetooth.buttonLayout)
        XCTAssertTrue(usb.supportedLightingEffects.isEmpty)
        XCTAssertFalse(usb.supportsLightingStateReads)
    }

    func testFallbackBluetoothIdentityIsDeterministicAndPreservesSerial() {
        let identifier = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let summary = OpenSnekHardware.BLEVendorTransportClient.ConnectedPeripheralSummary(name: "Orochi V2", identifier: identifier, serial: "SN-ONE")
        let first = BridgeClient.makeBluetoothFallbackDevice(summary: summary)
        let second = BridgeClient.makeBluetoothFallbackDevice(summary: summary)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.serial, "SN-ONE")
        XCTAssertEqual(first.bluetooth_peripheral_id, identifier)
        XCTAssertEqual(first.withMetadata(serial: "SN-ONE", firmware: "1.0").bluetooth_peripheral_id, identifier)
        XCTAssertNotEqual(first.location_id, DevicePersistenceKeys.stablePeripheralLocationID(UUID(uuidString: "00000000-0000-4000-8000-000000000002")!))
    }

    func testBluetoothIdentityResolutionRejectsDuplicateNamesAndUsesVerifiedSerial() {
        let first = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "Orochi V2", identifier: UUID(), serial: "SN-ONE")
        let second = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "Orochi V2", identifier: UUID(), serial: "SN-TWO")
        XCTAssertNil(BridgeClient.uniqueBluetoothPeripheral(name: "Orochi V2", serial: "00000000", peripherals: [first, second]))
        XCTAssertEqual(BridgeClient.uniqueBluetoothPeripheral(name: "Orochi V2", serial: "sn-two", peripherals: [first, second])?.identifier, second.identifier)
    }

    func testResolvedSerialPromotesExistingConfigurationWithoutOverwritingSharedValues() {
        let name = "identity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DevicePreferenceStore(defaults: defaults)
        let before = mouse("bluetooth-one", transport: .bluetooth, serial: nil)
        let resolved = before.withMetadata(serial: "SN-ONE", firmware: nil)
        let usb = mouse("receiver-one", transport: .usb, serial: "SN-ONE")
        store.persistConnectBehavior(.restoreOpenSnekSettings, device: before)
        store.migrateResolvedIdentity(from: before, to: resolved)
        XCTAssertEqual(store.loadConnectBehavior(device: usb), .restoreOpenSnekSettings)
        store.persistConnectBehavior(.useMouseSettings, device: usb)
        store.migrateResolvedIdentity(from: before, to: resolved)
        XCTAssertEqual(store.loadConnectBehavior(device: resolved), .useMouseSettings)
    }
}
