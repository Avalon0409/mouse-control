import AppKit
import SwiftUI
import OpenSnekCore

struct BasicMouseDetailView: View {
    let deviceStore: DeviceStore
    let selected: MouseDevice
    @ObservedObject private var scroll = FeatureRuntime.shared.scroll
    @ObservedObject private var store = FeatureStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.product_name).font(.title2.weight(.semibold))
                        Text("普通鼠标配置").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(selected.connectionLabel).font(.caption).foregroundStyle(.secondary)
                    Circle().fill(MouseTheme.success).frame(width: 7, height: 7)
                }
                Card(title: "灵敏度") {
                    HStack { Text("固定一档"); Spacer(); Text("系统指针速度").foregroundStyle(.secondary) }
                    Text("设备未提供硬件 DPI 调节，指针速度使用 macOS 设置。").hintTextStyle()
                    Button("打开系统鼠标设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                }
                Card(title: "滚动设置") {
                    Toggle("开启独立滚动设置", isOn: $store.settings.scrollEnabled)
                    if let row = scroll.deviceRow(for: selected) { ScrollSourceRowView(row: row, scroll: scroll, showsRemoveButton: false) }
                    Text(localized(scroll.status)).font(.caption).foregroundStyle(.secondary)
                }
                Text("此设备的滚动规则单独保存。").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 820, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .top)
        }.task(id: selected.id) { scroll.prepareDeviceRow(for: selected) }
    }
}
