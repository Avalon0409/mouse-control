import Foundation

/// Defines device persistence keys values.
public enum DevicePersistenceKeys {
    public static func normalizedStableSerial(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let alphanumeric = lowered.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        guard !alphanumeric.isEmpty else { return nil }

        if alphanumeric.allSatisfy({ $0 == "0" }) || alphanumeric.allSatisfy({ $0 == "f" }) { return nil }

        return lowered
    }

    public static func key(for device: MouseDevice) -> String {
        if let serial = normalizedStableSerial(device.serial) { return "serial:\(serial)" }
        return "device:\(device.id)"
    }

    public static func legacyKey(for device: MouseDevice) -> String { device.id }

    public static func priorModelKey(for device: MouseDevice) -> String { String(format: "vp:%04x:%04x:%@", device.vendor_id, device.product_id, device.transport.rawValue) }

    public static func readKeys(for device: MouseDevice) -> [String] {
        var keys: [String] = []
        for candidate in [key(for: device), "device:\(device.id)", legacyKey(for: device), priorModelKey(for: device)] where !keys.contains(candidate) { keys.append(candidate) }
        return keys
    }

    public static func stablePeripheralLocationID(_ identifier: UUID) -> Int {
        let hash = identifier.uuidString.lowercased().utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return Int(hash)
    }
}
