import AppKit
import SwiftUI

/// Defines OpenSnek appearance values.
enum OpenSnekAppearance {
    @MainActor static func apply(to application: NSApplication = .shared) { application.appearance = nil }
    @MainActor static func apply(to window: NSWindow) { window.appearance = nil }
}

/// Adds scoped helpers for `View`.
extension View { func openSnekFixedAppearance() -> some View { tint(MouseTheme.accent) } }

enum MouseTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let text = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let border = Color.primary.opacity(0.10)
    static let accent = Color(nsColor: .systemBlue)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
}
