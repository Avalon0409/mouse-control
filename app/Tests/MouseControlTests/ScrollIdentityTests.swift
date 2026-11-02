import XCTest
@testable import MouseControlTestHost

@MainActor final class ScrollIdentityTests: XCTestCase {
    private func source(transport: String, product: Int, serial: String = "00000000", location: Int = 1, physical: String? = nil, vendor: Int = 5426) -> ScrollSource {
        var properties: [String: Any] = ["Product": "Mouse", "VendorID": vendor, "ProductID": product, "Transport": transport, "SerialNumber": serial, "LocationID": location]
        if let physical { properties["MouseControlPhysicalIdentity"] = physical }
        return ScrollSource.deviceSources(kind: ScrollSourceKind(rawValue: 0)!, properties: properties, trackpadDriver: false)[0]
    }

    func testPhysicalIdentitySharesWheelRulesAcrossProductIDsAndTransports() {
        let usb = source(transport: "USB", product: 148, physical: "serial:sn-one")
        let bluetooth = source(transport: "Bluetooth Low Energy", product: 149, physical: "serial:sn-one")
        XCTAssertEqual(usb.key, bluetooth.key)
        XCTAssertNotEqual(usb.key, source(transport: "USB", product: 148, physical: "serial:sn-two").key)
    }

    func testNativeSerialAndAnonymousDevicesHaveSafeIdentity() {
        XCTAssertEqual(source(transport: "USB", product: 148, serial: "SN-ONE").key, source(transport: "Bluetooth", product: 149, serial: "sn-one", vendor: 0x068e).key)
        XCTAssertEqual(source(transport: "USB", product: 148, serial: "SN-ONE").key, source(transport: "Bluetooth", product: 149, physical: "serial:sn-one").key)
        XCTAssertNotEqual(source(transport: "USB", product: 148, location: 1).key, source(transport: "USB", product: 148, location: 2).key)
    }

    func testLegacySourceMigrationPreservesWheelSettingsAndUnknownFields() throws {
        let name = "scroll-identity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = "device|USB|5426|148|sn:00000000#discrete"
        defaults.set([legacy: ["Kind": 0, "Category": 1, "Continuous": false, "VerticalMode": 2, "HorizontalMode": 0, "StepSize": 5, "StepSizeEnabled": true, "FutureSetting": "keep"]], forKey: "Sources")
        let table = SourceTable(userDefaults: defaults)
        let resolved = source(transport: "USB", product: 148, physical: "serial:sn-one")
        let row = table.record(resolved, natural: true, amount: 1)
        XCTAssertEqual(row.stepSize, 5)
        XCTAssertEqual(row.verticalMode.rawValue, 2)
        table.save()
        let sources = try XCTUnwrap(defaults.dictionary(forKey: "Sources"))
        XCTAssertNil(sources[legacy])
        XCTAssertEqual((sources[resolved.key] as? [String: Any])?["FutureSetting"] as? String, "keep")
        let bluetooth = source(transport: "Bluetooth", product: 149, physical: "serial:sn-one")
        XCTAssertEqual(table.record(bluetooth, natural: true, amount: 1).stepSize, 5)
    }
}
