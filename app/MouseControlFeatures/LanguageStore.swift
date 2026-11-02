import Foundation
import SwiftUI

@MainActor final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    @Published var language: String {
        didSet {
            guard Self.supported.contains(language) else { language = oldValue; return }
            defaults.set(language, forKey: "mouseControl.language")
        }
    }
    private let defaults: UserDefaults
    static let supported = ["zh-Hans", "en"]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "mouseControl.language") ?? ""
        language = Self.supported.contains(saved) ? saved : "zh-Hans"
    }
    var locale: Locale { Locale(identifier: language) }
    func reload() {
        let saved = defaults.string(forKey: "mouseControl.language") ?? ""
        let value = Self.supported.contains(saved) ? saved : "zh-Hans"
        if value != language { language = value }
    }
}

func localized(_ value: String) -> String {
    let language = UserDefaults.standard.string(forKey: "mouseControl.language") ?? "zh-Hans"
    guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return value }
    return bundle.localizedString(forKey: value, value: value, table: nil)
}

func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), locale: Locale(identifier: UserDefaults.standard.string(forKey: "mouseControl.language") ?? "zh-Hans"), arguments: arguments)
}
