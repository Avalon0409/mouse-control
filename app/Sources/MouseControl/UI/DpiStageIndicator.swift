import OpenSnekCore
import SwiftUI

enum DpiStageIndicator {
    // Orochi V2 master guide: stages 1–5 use red, green, blue, cyan, yellow.
    // The indicator follows the slot, even when its DPI value is edited.
    static func colorName(stage: Int, profileID: DeviceProfileID?) -> String? {
        guard profileID == .orochiV2, (1...5).contains(stage) else { return nil }
        return ["Red", "Green", "Blue", "Cyan", "Yellow"][stage - 1]
    }

    static func color(stage: Int, profileID: DeviceProfileID?) -> Color {
        guard colorName(stage: stage, profileID: profileID) != nil else { return MouseTheme.accent }
        return [Color.red, Color.green, Color.blue, Color.cyan, Color.yellow][stage - 1]
    }
}
