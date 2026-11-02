import AppKit
import SwiftUI

enum AppIconStyle: String, CaseIterable, Identifiable {
    case mouse, psyduck
    var id: String { rawValue }
    var title: String { self == .mouse ? "鼠标" : "可达鸭" }
    var resource: String { self == .mouse ? "mouse-app-icon" : "psyduck-app-icon" }
    func image(in bundle: Bundle = .main) -> NSImage? {
        guard let url = bundle.url(forResource: resource, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

@MainActor final class IconStore: ObservableObject {
    static let shared = IconStore()
    @Published var style: AppIconStyle {
        didSet {
            guard style != oldValue else { return }
            defaults.set(style.rawValue, forKey: "mouseControl.icon")
            apply()
        }
    }
    private let defaults: UserDefaults
    private let bundle: Bundle
    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        style = AppIconStyle(rawValue: defaults.string(forKey: "mouseControl.icon") ?? "") ?? .mouse
    }
    func apply() {
        guard let image = style.image(in: bundle), NSApp != nil else { return }
        NSApp.applicationIconImage = image
    }
    func reload() {
        let newStyle = AppIconStyle(rawValue: defaults.string(forKey: "mouseControl.icon") ?? "") ?? .mouse
        if newStyle != style { style = newStyle }
    }
}
