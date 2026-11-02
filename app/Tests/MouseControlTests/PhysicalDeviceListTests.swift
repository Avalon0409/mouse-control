import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import MouseControlTestHost

final class PhysicalDeviceListTests: XCTestCase {
    func testVerifiedReceiverIdentitySurvivesAppRestartAndRejectsRepluggedOrRebootedInstance() {
        let suite = "PhysicalDeviceListTests.USBIdentity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = DevicePreferenceStore(defaults: defaults)
        first.persistVerifiedUSBSerial(" Shared ", connectionInstance: "boot-one:100")
        let restarted = DevicePreferenceStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restarted.verifiedUSBSerial(connectionInstance: "boot-one:100"), "shared")
        XCTAssertNil(restarted.verifiedUSBSerial(connectionInstance: "boot-one:101"))
        XCTAssertNil(restarted.verifiedUSBSerial(connectionInstance: "boot-two:100"))
        restarted.persistVerifiedUSBSerial("0000", connectionInstance: "boot-one:101")
        XCTAssertNil(restarted.verifiedUSBSerial(connectionInstance: "boot-one:101"))
        restarted.persistVerifiedUSBSerial("Other", connectionInstance: "boot-two:100")
        XCTAssertEqual(restarted.verifiedUSBSerial(connectionInstance: "boot-two:100"), "other")
        XCTAssertNil(restarted.verifiedUSBSerial(connectionInstance: "boot-one:100"))
    }

    private func mouse(_ id: String, serial: String?, transport: DeviceTransportKind = .usb, generic: Bool = false) -> MouseDevice {
        MouseDevice(id: id, vendor_id: generic ? 0x413c : 0x1532, product_id: generic ? 0x301a : (transport == .usb ? 0x0094 : 0x0095),
                    product_name: generic ? "Dell MS116 USB Optical Mouse" : "Orochi V2", transport: transport, path_b64: "", serial: serial, firmware: nil,
                    location_id: 1, profile_id: generic ? nil : .orochiV2, uses_generic_controls: generic)
    }

    @MainActor func testSameSerialHasOneRowAndRetainsBothConnections() {
        let app = AppState(launchRole: .app, autoStart: false)
        let usb = mouse("usb", serial: "Shared")
        let bluetooth = mouse("bluetooth", serial: " shared ", transport: .bluetooth)
        app.deviceStore.devices = [usb, bluetooth]
        app.deviceStore.selectedDeviceID = bluetooth.id
        XCTAssertEqual(app.deviceStore.visibleDevices.map(\.id), [bluetooth.id])
        XCTAssertEqual(app.deviceStore.devices.count, 2)
    }

    @MainActor func testSameModelWithDifferentOrMissingSerialsStaysSeparate() {
        let app = AppState(launchRole: .app, autoStart: false)
        app.deviceStore.devices = [mouse("one", serial: "First"), mouse("two", serial: "Second"),
                                  mouse("three", serial: nil), mouse("four", serial: "0000"), mouse("five", serial: "FFFF")]
        XCTAssertEqual(app.deviceStore.visibleDevices.count, 5)
    }

    @MainActor func testReceiverIdleShowsBluetoothAndReceiverRecoveryShowsUSB() {
        let app = AppState(launchRole: .app, autoStart: false)
        let usb = mouse("usb", serial: "Shared")
        let bluetooth = mouse("bluetooth", serial: "Shared", transport: .bluetooth)
        app.deviceStore.devices = [usb, bluetooth]
        app.deviceStore.selectedDeviceID = usb.id
        app.deviceController.usbControlAvailabilityByDeviceID[usb.id] = .receiverPresentMouseUnavailable
        app.deviceController.lastPassiveHeartbeatAtByDeviceID[bluetooth.id] = Date()
        XCTAssertEqual(app.deviceStore.visibleDevices.first?.transport, .bluetooth)
        app.deviceController.lastPassiveHeartbeatAtByDeviceID[bluetooth.id] = nil
        app.deviceController.unavailableDeviceIDs.insert(bluetooth.id)
        app.deviceController.usbControlAvailabilityByDeviceID[usb.id] = .receiverPresentMouseReachable
        app.deviceController.lastPassiveHeartbeatAtByDeviceID[usb.id] = Date()
        XCTAssertEqual(app.deviceStore.visibleDevices.first?.transport, .usb)
    }

    @MainActor func testLateSerialResolutionMergesExistingConnectionsAndSelectsLiveConnection() {
        let app = AppState(launchRole: .app, autoStart: false)
        let usb = mouse("usb", serial: "Shared")
        let unresolvedBluetooth = mouse("bluetooth", serial: nil, transport: .bluetooth)
        let resolvedBluetooth = mouse("bluetooth", serial: "Shared", transport: .bluetooth)
        app.deviceStore.devices = [usb, unresolvedBluetooth]
        app.deviceStore.selectedDeviceID = usb.id
        app.deviceController.usbControlAvailabilityByDeviceID[usb.id] = .receiverPresentMouseUnavailable
        app.deviceController.lastPassiveHeartbeatAtByDeviceID[resolvedBluetooth.id] = Date()
        _ = app.deviceController.applyDeviceList([usb, resolvedBluetooth], source: "test")
        XCTAssertEqual(app.deviceStore.visibleDevices.count, 1)
        XCTAssertEqual(app.deviceStore.selectedDeviceID, resolvedBluetooth.id)
    }

    @MainActor func testGenericMouseAppearsConnectedWithoutHardwareControls() {
        let app = AppState(launchRole: .app, autoStart: false)
        let dell = mouse("dell", serial: nil, generic: true)
        app.deviceStore.devices = [dell, mouse("orochi", serial: "Shared")]
        XCTAssertEqual(app.deviceStore.visibleDevices.count, 2)
        XCTAssertEqual(app.deviceController.connectionState(for: dell), .connected)
        XCTAssertFalse(dell.supportsDPIControls)
        XCTAssertFalse(dell.showsLightingControls)
        let state = BridgeClient.genericMouseState(device: dell)
        XCTAssertNil(state.dpi)
        XCTAssertFalse(state.capabilities.button_remap)
        XCTAssertFalse(state.capabilities.dpi_stages)
    }

    func testRemovingPhysicalMouseHidesBothConnectionsAndRestoringKeepsPreferences() {
        let suite = "PhysicalDeviceListTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DevicePreferenceStore(defaults: defaults)
        let usb = mouse("usb", serial: "Shared")
        let bluetooth = mouse("bluetooth", serial: "Shared", transport: .bluetooth)
        defaults.set(["serial:shared": ["StepSize": 10, "UnknownField": "keep"]], forKey: "Sources")
        store.hideDevice(usb)
        XCTAssertTrue(store.isDeviceHidden(usb))
        XCTAssertTrue(store.isDeviceHidden(bluetooth))
        XCTAssertFalse(store.isDeviceHidden(mouse("dell", serial: nil, generic: true)))
        store.restoreHiddenDevices()
        XCTAssertFalse(store.isDeviceHidden(usb))
        XCTAssertFalse(store.isDeviceHidden(bluetooth))
        let saved = defaults.dictionary(forKey: "Sources")?["serial:shared"] as? [String: Any]
        XCTAssertEqual(saved?["StepSize"] as? Int, 10)
        XCTAssertEqual(saved?["UnknownField"] as? String, "keep")
    }
}
