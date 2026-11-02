import AppKit
import Combine
import CryptoKit
import Foundation
import IOKit.ps
import OSLog

/// Identity used only for native power-source matching; it does not depend on the hardware bridge.
struct NativeBatteryDeviceIdentity: Hashable, Sendable {
    enum Transport: String, Hashable, Sendable {
        case bluetoothLE
        case bluetooth
        case usb

        fileprivate var powerSourceValue: String {
            switch self {
            case .bluetoothLE: "Bluetooth LE"
            case .bluetooth: "Bluetooth"
            case .usb: "USB"
            }
        }

        fileprivate func matches(_ value: String) -> Bool {
            switch self {
            case .bluetooth, .bluetoothLE:
                value.localizedCaseInsensitiveContains("Bluetooth")
            case .usb:
                value.caseInsensitiveCompare("USB") == .orderedSame
            }
        }
    }

    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let transport: Transport
    /// Supply this only when it is the actual system Accessory Identifier, not a guessed serial/UUID.
    var accessoryIdentifier: String? = nil
    var vendorIDSource: Int = 2

    fileprivate var ownedAccessoryIdentifier: String {
        // Keep raw serials and Bluetooth identifiers out of the published app-owned identifier.
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "local.mousecontrol.native-battery.\(digest)"
    }

    fileprivate var valid: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...65_535).contains(vendorID) && (0...65_535).contains(productID)
    }
}

struct NativeBatteryReading: Sendable {
    let identity: NativeBatteryDeviceIdentity
    let percent: Int?
    let charging: Bool?
    let connected: Bool
    let observedAt: Date
}

struct NativeBatteryFailure: Equatable, Sendable {
    let operation: String
    let code: UInt32?
    let message: String
}

struct NativeBatteryStatus: Identifiable, Equatable, Sendable {
    enum Mode: String, Sendable {
        case disabled
        case disconnected
        case observingSystem
        case publishing
        case waitingForTelemetry
        case duplicateRisk
        case unavailable
    }

    let id: String
    let name: String
    let mode: Mode
    let devicePercent: Int?
    let systemPercent: Int?
    /// Time the system snapshot was copied, not the time the mouse measured its battery.
    let systemReadAt: Date?
    let message: String
    let failure: NativeBatteryFailure?

    var telemetryDisagrees: Bool {
        guard let devicePercent, let systemPercent else { return false }
        return devicePercent != systemPercent
    }
}

/// Observes an existing native mouse source, or publishes an app-owned source when none exists.
/// Private IOPowerSources APIs are loaded dynamically and can fail on a future macOS release.
/// This class never writes another process's source, a BLE characteristic, or a HID property.
@MainActor
final class NativeBatteryPublisher: ObservableObject {
    @Published private(set) var statuses: [NativeBatteryStatus] = []
    @Published private(set) var lastFailure: NativeBatteryFailure?

    private let resources: NativeBatteryResources
    private let maximumReadingAge: TimeInterval
    private var readings: [NativeBatteryReading] = []
    private var enabled = false

    init(maximumReadingAge: TimeInterval = 300) {
        self.maximumReadingAge = max(1, maximumReadingAge)
        resources = NativeBatteryResources(api: NativeBatterySystemAPI())
    }

    /// Caller supplies the complete currently known device list. Missing/disconnected devices release
    /// any source owned by this object. Hardware telemetry remains under the caller's control.
    func synchronize(readings: [NativeBatteryReading], enabled: Bool) {
        self.readings = readings
        self.enabled = enabled
        if enabled {
            startObservingIfNeeded()
            refresh()
        } else {
            stop()
        }
    }

    /// Re-read the system snapshot without requesting hardware updates or changing Bluetooth state.
    func refresh() {
        guard enabled else { return }
        let now = Date()
        var unique: [String: NativeBatteryReading] = [:]
        var duplicateIDs: Set<String> = []
        for reading in readings {
            let id = reading.identity.id
            if unique[id] != nil || duplicateIDs.contains(id) {
                duplicateIDs.insert(id)
                unique.removeValue(forKey: id)
            } else {
                unique[id] = reading
            }
        }

        let retainedIDs = Set(unique.values.filter(\.connected).map { $0.identity.id })
        for id in Array(resources.owned.keys) where !retainedIDs.contains(id) {
            record(resources.release(id: id))
        }

        let sources: [[String: Any]]
        do {
            sources = try resources.api.copyAccessorySources()
        } catch let failure as NativeBatteryAPIError {
            record(failure.failure)
            // A failed inventory cannot establish that it is safe to publish a new source.
            for id in Array(resources.owned.keys) { record(resources.release(id: id)) }
            statuses = readings.map { status($0, mode: .unavailable, message: failure.failure.message, failure: failure.failure) }
            return
        } catch {
            let failure = NativeBatteryFailure(operation: "copy-sources", code: nil, message: "读取系统外设电池来源失败")
            record(failure)
            for id in Array(resources.owned.keys) { record(resources.release(id: id)) }
            statuses = readings.map { status($0, mode: .unavailable, message: failure.message, failure: failure) }
            return
        }

        let ownedIdentifiers = Set(resources.owned.values.map(\.accessoryIdentifier))
        let externalSources = sources.filter {
            guard let identifier = $0["Accessory Identifier"] as? String else { return true }
            return !ownedIdentifiers.contains(identifier)
        }
        var result: [NativeBatteryStatus] = []
        for reading in unique.values.sorted(by: { $0.identity.id < $1.identity.id }) {
            let identity = reading.identity
            guard identity.valid else {
                record(resources.release(id: identity.id))
                result.append(status(reading, mode: .unavailable, message: "设备身份不完整，未发布系统电池来源"))
                continue
            }
            guard reading.connected else {
                result.append(status(reading, mode: .disconnected, message: "设备已断开，已释放应用持有的来源"))
                continue
            }

            switch matchingSource(identity: identity, sources: externalSources, readings: Array(unique.values)) {
            case .matched(let source):
                // A standard source appearing after publication takes precedence. Release ours first.
                let releaseFailure = resources.release(id: identity.id)
                record(releaseFailure)
                let systemPercent = Self.percent(in: source)
                result.append(status(reading, mode: .observingSystem, systemPercent: systemPercent, systemReadAt: now,
                                     message: "已复用系统蓝牙/USB电池来源；设备读数有差异时保留双方读数", failure: releaseFailure))
            case .ambiguous:
                let releaseFailure = resources.release(id: identity.id)
                record(releaseFailure)
                result.append(status(reading, mode: .duplicateRisk, message: "已有同型号电池来源，身份匹配有歧义，暂停发布以避免重复图标", failure: releaseFailure))
            case .absent:
                let age = now.timeIntervalSince(reading.observedAt)
                guard let percent = reading.percent, (0...100).contains(percent),
                      age >= -30, age <= maximumReadingAge else {
                    let releaseFailure = resources.release(id: identity.id)
                    record(releaseFailure)
                    result.append(status(reading, mode: .waitingForTelemetry, message: "等待设备提供有效的新电量读数，未发布推算值", failure: releaseFailure))
                    continue
                }
                let failure = publish(reading, percent: percent)
                record(failure)
                let observedSource = sources.first {
                    ($0["Accessory Identifier"] as? String) == identity.ownedAccessoryIdentifier
                }
                result.append(status(reading, mode: failure == nil ? .publishing : .unavailable,
                                     systemPercent: failure == nil ? observedSource.flatMap(Self.percent) : nil,
                                     systemReadAt: failure == nil && observedSource != nil ? now : nil,
                                     message: failure?.message ?? "已发布应用持有的外设电池来源；原生组件显示仍由系统决定", failure: failure))
            }
        }
        for id in duplicateIDs.sorted() {
            guard let reading = readings.first(where: { $0.identity.id == id }) else { continue }
            result.append(status(reading, mode: .duplicateRisk, message: "输入包含重复设备标识，暂停该设备的来源发布"))
        }
        statuses = result
    }

    /// Call on application termination. Resource destruction also releases every app-owned source.
    func stop() {
        enabled = false
        resources.stopObserving()
        var failures: [String: NativeBatteryFailure] = [:]
        for id in Array(resources.owned.keys) {
            if let failure = resources.release(id: id) {
                failures[id] = failure
                record(failure)
            }
        }
        statuses = readings.map {
            let failure = failures[$0.identity.id]
            return status($0, mode: .disabled,
                          message: failure == nil ? "原生电池接入已关闭，已释放应用持有的来源" : "原生电池接入已关闭；系统来源清理失败，详见诊断",
                          failure: failure)
        }
    }

    private func startObservingIfNeeded() {
        guard resources.timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        resources.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        resources.terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
            guard let context else { return }
            let publisher = Unmanaged<NativeBatteryPublisher>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { publisher.refresh() }
        }
        if let createNotification = resources.api.createNotification,
           let source = createNotification(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            resources.notificationSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private enum SourceMatch {
        case matched([String: Any])
        case absent
        case ambiguous
    }

    private func matchingSource(identity: NativeBatteryDeviceIdentity, sources: [[String: Any]], readings: [NativeBatteryReading]) -> SourceMatch {
        // Some accessory sources omit numeric identity or transport fields. A matching name/model
        // makes those entries a duplicate risk; incomplete metadata must not trigger publication.
        let incompleteCandidates = sources.filter { source in
            let vendor = Self.integer(source["Vendor ID"]), product = Self.integer(source["Product ID"])
            let transport = source["Transport Type"] as? String ?? ""
            let sameNumbers = vendor == identity.vendorID && product == identity.productID
            let sameName = (source["Name"] as? String)?.caseInsensitiveCompare(identity.name) == .orderedSame
            let incompleteNumbers = vendor == nil || product == nil
            let compatibleNumbers = (vendor == nil || vendor == identity.vendorID) && (product == nil || product == identity.productID)
            return (sameNumbers && transport.isEmpty) ||
                (sameName && incompleteNumbers && compatibleNumbers && (transport.isEmpty || identity.transport.matches(transport)))
        }
        let candidates = sources.filter {
            Self.integer($0["Vendor ID"]) == identity.vendorID &&
            Self.integer($0["Product ID"]) == identity.productID &&
            identity.transport.matches($0["Transport Type"] as? String ?? "")
        }
        if !incompleteCandidates.isEmpty { return .ambiguous }
        if let identifier = identity.accessoryIdentifier, !identifier.isEmpty {
            let exact = candidates.filter {
                ($0["Accessory Identifier"] as? String)?.caseInsensitiveCompare(identifier) == .orderedSame
            }
            if exact.count == 1, let source = exact.first { return .matched(source) }
            // A same-model source with a different/unavailable identifier must not be overwritten.
            if !candidates.isEmpty { return .ambiguous }
            return .absent
        }
        let sameModelCount = readings.filter {
            $0.connected && $0.identity.vendorID == identity.vendorID && $0.identity.productID == identity.productID &&
            identity.transport.matches($0.identity.transport.powerSourceValue)
        }.count
        if candidates.count == 1, sameModelCount == 1, let source = candidates.first { return .matched(source) }
        return candidates.isEmpty ? .absent : .ambiguous
    }

    private func publish(_ reading: NativeBatteryReading, percent: Int) -> NativeBatteryFailure? {
        let identity = reading.identity
        var details: [String: Any] = [
            "Name": identity.name, "Type": "Accessory Source", "Transport Type": identity.transport.powerSourceValue,
            "Accessory Category": "Mouse", "Accessory Identifier": identity.ownedAccessoryIdentifier,
            "Vendor ID": identity.vendorID, "Product ID": identity.productID, "Vendor ID Source": identity.vendorIDSource,
            "Current Capacity": percent, "Max Capacity": 100, "Power Source State": "Battery Power", "Is Present": true
        ]
        if let charging = reading.charging { details["Is Charging"] = charging }

        if let owned = resources.owned[identity.id], owned.details.isEqual(to: details) { return nil }
        do {
            if resources.owned[identity.id] == nil {
                let handle = try resources.api.createSource()
                resources.owned[identity.id] = NativeBatteryOwnedSource(handle: handle, accessoryIdentifier: identity.ownedAccessoryIdentifier, details: [:])
            }
            guard var owned = resources.owned[identity.id] else {
                return NativeBatteryFailure(operation: "create-source", code: nil, message: "系统未返回可用的电池来源句柄")
            }
            try resources.api.setDetails(handle: owned.handle, details: details)
            owned.details = details as NSDictionary
            resources.owned[identity.id] = owned
            return nil
        } catch let error as NativeBatteryAPIError {
            record(resources.release(id: identity.id))
            return error.failure
        } catch {
            record(resources.release(id: identity.id))
            return NativeBatteryFailure(operation: "publish-source", code: nil, message: "发布系统电池来源失败")
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func percent(in source: [String: Any]) -> Int? {
        guard let current = source["Current Capacity"] as? NSNumber,
              let maximum = source["Max Capacity"] as? NSNumber else { return nil }
        let currentValue = current.doubleValue, maximumValue = maximum.doubleValue
        guard currentValue.isFinite, maximumValue.isFinite, maximumValue > 0,
              currentValue >= 0, currentValue <= maximumValue else { return nil }
        return Int((currentValue / maximumValue * 100).rounded())
    }

    private func status(_ reading: NativeBatteryReading, mode: NativeBatteryStatus.Mode, systemPercent: Int? = nil,
                        systemReadAt: Date? = nil, message: String, failure: NativeBatteryFailure? = nil) -> NativeBatteryStatus {
        NativeBatteryStatus(id: reading.identity.id, name: reading.identity.name, mode: mode, devicePercent: reading.percent,
                            systemPercent: systemPercent, systemReadAt: systemReadAt, message: message, failure: failure)
    }

    private func record(_ failure: NativeBatteryFailure?) {
        guard let failure else { return }
        lastFailure = failure
        NativeBatteryResources.log(failure)
    }

    isolated deinit {
        // Invalidate callback contexts on the same actor that services their run-loop source.
        stop()
    }
}

private struct NativeBatteryOwnedSource {
    let handle: UnsafeMutableRawPointer
    let accessoryIdentifier: String
    var details: NSDictionary
}

/// Non-actor resource holder permits synchronous cleanup even when its owner is deallocated.
private final class NativeBatteryResources {
    let api: NativeBatterySystemAPI
    var owned: [String: NativeBatteryOwnedSource] = [:]
    var timer: Timer?
    var terminationObserver: NSObjectProtocol?
    var notificationSource: CFRunLoopSource?
    private static let logger = Logger(subsystem: "local.mousecontrol.MouseControl", category: "NativeBattery")

    init(api: NativeBatterySystemAPI) { self.api = api }

    func release(id: String) -> NativeBatteryFailure? {
        guard let source = owned.removeValue(forKey: id) else { return nil }
        // The private API frees its tracking handle even if the server reports an error. Never retry it.
        return api.releaseSource(handle: source.handle)
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
        if let notificationSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), notificationSource, .commonModes)
            CFRunLoopSourceInvalidate(notificationSource)
        }
        notificationSource = nil
    }

    static func log(_ failure: NativeBatteryFailure) {
        let code = failure.code.map { String(format: "0x%08X", $0) } ?? "unavailable"
        logger.error("operation=\(failure.operation, privacy: .public) code=\(code, privacy: .public) message=\(failure.message, privacy: .public)")
    }

    deinit {
        stopObserving()
        for id in Array(owned.keys) { if let failure = release(id: id) { Self.log(failure) } }
    }
}

private struct NativeBatteryAPIError: Error {
    let failure: NativeBatteryFailure
}

private final class NativeBatterySystemAPI {
    typealias CopySources = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    typealias CreateSource = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> IOReturn
    typealias SetDetails = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> IOReturn
    typealias ReleaseSource = @convention(c) (UnsafeMutableRawPointer) -> IOReturn
    typealias CreateNotification = @convention(c) (@convention(c) (UnsafeMutableRawPointer?) -> Void, UnsafeMutableRawPointer?) -> Unmanaged<CFRunLoopSource>?

    private let library: UnsafeMutableRawPointer?
    private let copySources: CopySources?
    private let create: CreateSource?
    private let set: SetDetails?
    private let release: ReleaseSource?
    let createNotification: CreateNotification?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
        library = handle
        func symbol<T>(_ name: String, as: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        copySources = symbol("IOPSCopyPowerSourcesByType", as: CopySources.self)
        create = symbol("IOPSCreatePowerSource", as: CreateSource.self)
        set = symbol("IOPSSetPowerSourceDetails", as: SetDetails.self)
        release = symbol("IOPSReleasePowerSource", as: ReleaseSource.self)
        createNotification = symbol("IOPSAccNotificationCreateRunLoopSource", as: CreateNotification.self)
    }

    func copyAccessorySources() throws -> [[String: Any]] {
        guard let copySources else { throw missing("copy-sources") }
        guard let blob = copySources(4)?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            throw NativeBatteryAPIError(failure: .init(operation: "copy-sources", code: nil, message: "系统外设电池来源快照不可用"))
        }
        return try sourceList.map {
            guard let description = IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] else {
                throw NativeBatteryAPIError(failure: .init(operation: "copy-sources", code: nil, message: "系统外设电池来源条目不可读"))
            }
            return description
        }
    }

    func createSource() throws -> UnsafeMutableRawPointer {
        // Refuse creation unless cleanup is also available.
        guard let create, set != nil, release != nil else { throw missing("create-source") }
        var source: UnsafeMutableRawPointer?
        let code = create(&source)
        guard code == kIOReturnSuccess else { throw failure("create-source", code: code, message: "系统拒绝创建应用电池来源") }
        guard let source else { throw NativeBatteryAPIError(failure: .init(operation: "create-source", code: nil, message: "系统未返回电池来源句柄")) }
        return source
    }

    func setDetails(handle: UnsafeMutableRawPointer, details: [String: Any]) throws {
        guard let set else { throw missing("set-details") }
        let code = set(handle, details as CFDictionary)
        guard code == kIOReturnSuccess else { throw failure("set-details", code: code, message: "系统拒绝更新应用持有的电池来源") }
    }

    func releaseSource(handle: UnsafeMutableRawPointer) -> NativeBatteryFailure? {
        guard let release else { return missing("release-source").failure }
        let code = release(handle)
        return code == kIOReturnSuccess ? nil : failure("release-source", code: code, message: "释放应用电池来源时系统返回错误").failure
    }

    private func missing(_ operation: String) -> NativeBatteryAPIError {
        NativeBatteryAPIError(failure: .init(operation: operation, code: nil, message: "当前 macOS 未提供所需的原生电池接入接口"))
    }

    private func failure(_ operation: String, code: IOReturn, message: String) -> NativeBatteryAPIError {
        NativeBatteryAPIError(failure: .init(operation: operation, code: UInt32(bitPattern: code), message: message))
    }

    deinit { if let library { dlclose(library) } }
}
