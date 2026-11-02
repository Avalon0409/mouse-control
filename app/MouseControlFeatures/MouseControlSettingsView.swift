import AppKit
import SwiftUI

struct MouseControlSettingsView: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let runtimeStore: RuntimeStore
    @ObservedObject private var store = FeatureStore.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject private var icons = IconStore.shared

    var body: some View {
        TabView {
            appearance.tabItem { Label("外观", systemImage: "paintpalette") }
            ScrollPreferencesView().tabItem { Label("滚动", systemImage: "arrow.up.arrow.down") }
            AutomationPreferencesView(deviceStore: deviceStore, editorStore: editorStore).tabItem { Label("应用与宏", systemImage: "command") }
            batteryAndConfiguration.tabItem { Label("电量与配置", systemImage: "battery.100percent") }
            SettingsView(deviceStore: deviceStore, runtimeStore: runtimeStore).tabItem { Label("应用", systemImage: "gearshape") }
        }.frame(width: 760, height: 620)
    }

    private var appearance: some View {
        Form {
            Section("语言") {
                Picker("界面语言", selection: $language.language) { Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }.pickerStyle(.segmented)
            }
            Section("图标") {
                HStack(spacing: 16) {
                    ForEach(AppIconStyle.allCases) { style in
                        Button { icons.style = style } label: {
                            VStack(spacing: 10) {
                                if let image = style.image() { Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: 88, height: 88) }
                                HStack(spacing: 6) {
                                    Image(systemName: icons.style == style ? "checkmark.circle.fill" : "circle").foregroundStyle(icons.style == style ? MouseTheme.accent : MouseTheme.secondary)
                                    Text(localized(style.title)).foregroundStyle(.primary)
                                }
                            }.padding(16).frame(maxWidth: .infinity)
                                .background(icons.style == style ? MouseTheme.accent.opacity(0.07) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(icons.style == style ? MouseTheme.accent.opacity(0.3) : MouseTheme.border))
                        }.buttonStyle(.plain).accessibilityLabel(localized(style.title)).accessibilityValue(icons.style == style ? localized("已选择") : localized("未选择"))
                    }
                }
                Text("应用图标与菜单栏同步切换，下次启动继续使用。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding()
    }

    private var batteryAndConfiguration: some View {
        Form {
            Section("电量") {
                Toggle("接入系统电池来源", isOn: $store.settings.nativeBatteryIntegration)
                Text("已有系统鼠标来源会直接复用；缺少来源时补充设备上报的电量。").font(.caption).foregroundStyle(.secondary)
                Toggle("低电量通知", isOn: $store.settings.lowBatteryNotifications)
                Stepper("提醒阈值：\(store.settings.lowBatteryThreshold)%", value: $store.settings.lowBatteryThreshold, in: 1...99)
                Button("开启通知权限") { Task { await features.requestNotifications() } }
                Text(localized(features.notificationStatus)).font(.caption)
                NativeBatteryStatusView(runtime: features)
            }
            Section("配置") {
                HStack {
                    Button("导出配置") { store.exportConfiguration() }
                    Button("导入配置") { store.importConfiguration() }
                    Button("复制原滚动设置") { store.importScrollReverserSettings(); features.scroll.reloadSources() }
                }
                if let message = store.message { Text(localized(message)).font(.caption) }
            }
            DisclosureGroup("开发设置") {
                TextField("GitHub 仓库（owner/repo）", text: $store.settings.updateRepository)
                TextField("签名更新 Feed URL", text: $store.settings.updateFeedURL)
            }
        }.formStyle(.grouped).padding()
    }
}

private struct NativeBatteryStatusView: View {
    @ObservedObject var runtime: FeatureRuntime
    var body: some View {
        ForEach(runtime.nativeSummaries) { status in
            VStack(alignment: .leading) {
                Text(localized(status.name))
                Text("设备 \(status.devicePercent.map { "\($0)%" } ?? "—") · 系统 \(status.systemPercent.map { "\($0)%" } ?? "—")").font(.caption)
                Text(localized(status.message)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScrollPreferencesView: View {
    @ObservedObject private var store = FeatureStore.shared
    @ObservedObject private var scroll = FeatureRuntime.shared.scroll
    var body: some View {
        Form {
            Section("滚动处理") {
                Toggle("开启独立滚动设置", isOn: $store.settings.scrollEnabled)
                Text(localized(scroll.status)).font(.caption)
                Button("开启辅助功能权限") { scroll.requestPermission() }
            }
            Section("鼠标和触控板") {
                if scroll.rows.isEmpty { Text("开启后滚动鼠标或触控板，即可识别来源；也可以复制原 Scroll Reverser 设置。").foregroundStyle(.secondary) }
                ForEach(scroll.rows, id: \.key) { row in ScrollSourceRowView(row: row, scroll: scroll) }
            }
            Section("鼠标滚轮手感") {
                Toggle("平滑滚动", isOn: $store.settings.smoothScrolling)
                LabeledContent("平滑时长") { Slider(value: $store.settings.smoothDuration, in: 0.04...0.6); Text(String(format: "%.2fs", store.settings.smoothDuration)) }
                LabeledContent("滚动速度") { Slider(value: $store.settings.scrollMultiplier, in: 0.1...5); Text(String(format: "%.1f×", store.settings.scrollMultiplier)) }
                LabeledContent("速度加速") { Slider(value: $store.settings.scrollAcceleration, in: 0...2); Text(String(format: "%.1f", store.settings.scrollAcceleration)) }
                Text("这些选项只处理鼠标离散滚轮，触控板连续滚动保留当前手感。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding()
    }
}

struct ScrollSourceRowView: View {
    let row: SourceRow
    @ObservedObject var scroll: ScrollRuntime
    var showsRemoveButton = true
    private func value<T>(_ keyPath: ReferenceWritableKeyPath<SourceRow, T>) -> Binding<T> {
        Binding(get: { row[keyPath: keyPath] }, set: { row[keyPath: keyPath] = $0; scroll.save() })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.customName ?? row.reportedName ?? localized("未识别来源")).fontWeight(.semibold)
                if row.isScrolling { Circle().fill(.green).frame(width: 6, height: 6) }
                Spacer()
                if showsRemoveButton { Button("移除") { scroll.remove(row) } }
            }
            HStack {
                Picker("垂直", selection: value(\.verticalMode)) {
                    Text("保持").tag(ScrollDirectionMode(rawValue: 0)!)
                    if row.hasDeviceDirection {
                        Text("自然").tag(ScrollDirectionMode(rawValue: 1)!)
                        Text("传统").tag(ScrollDirectionMode(rawValue: 2)!)
                    } else { Text("反转").tag(ScrollDirectionMode(rawValue: 3)!) }
                }
                Picker("水平", selection: value(\.horizontalMode)) {
                    Text("保持").tag(ScrollDirectionMode(rawValue: 0)!)
                    Text("反转").tag(ScrollDirectionMode(rawValue: 3)!)
                    Text("跟随垂直").tag(ScrollDirectionMode(rawValue: 4)!)
                }
            }
            if !row.continuous {
                HStack {
                    Toggle("固定步长", isOn: value(\.stepSizeEnabled))
                    Stepper("每格 \(row.stepSize) 行", value: value(\.stepSize), in: 1...30)
                }
            }
            TextField("自定义名称", text: Binding(get: { row.customName ?? "" }, set: { row.customName = $0; scroll.save() })).textFieldStyle(.roundedBorder)
        }
    }
}

private struct AutomationPreferencesView: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    @ObservedObject private var store = FeatureStore.shared
    @ObservedObject private var macroRuntime = FeatureRuntime.shared.macros
    @State private var selectedProfile: UUID?

    var body: some View {
        Form {
            Section("按应用切换配置") {
                Toggle("自动切换", isOn: $store.settings.applicationProfilesEnabled)
                Picker("配置", selection: $selectedProfile) {
                    Text("选择配置").tag(Optional<UUID>.none)
                    ForEach(editorStore.localProfiles) { profile in Text(localized(profile.name)).tag(Optional(profile.id)) }
                }
                Button("添加应用规则") { addApplicationRule() }.disabled(selectedProfile == nil || deviceStore.selectedDeviceID == nil)
                ForEach($store.settings.applicationRules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                      HStack {
                        Text(localized(rule.bundleIdentifier))
                        Spacer()
                        Text(editorStore.localProfiles.first(where: { $0.id == rule.profileID })?.name ?? "配置已移除")
                        Button("删除") { store.settings.applicationRules.removeAll { $0.id == rule.id } }
                      }
                      Toggle("为此应用单独设置滚轮手感", isOn: Binding(get: { rule.scroll != nil }, set: { enabled in
                          rule.scroll = enabled ? ApplicationScrollSettings(smoothScrolling: store.settings.smoothScrolling, smoothDuration: store.settings.smoothDuration, multiplier: store.settings.scrollMultiplier, acceleration: store.settings.scrollAcceleration) : nil
                      }))
                      if rule.scroll != nil {
                          Toggle("平滑滚动", isOn: Binding(get: { rule.scroll?.smoothScrolling ?? false }, set: { rule.scroll?.smoothScrolling = $0 }))
                          LabeledContent("滚动速度") { Slider(value: Binding(get: { rule.scroll?.multiplier ?? 1 }, set: { rule.scroll?.multiplier = $0 }), in: 0.1...5) }
                          LabeledContent("速度加速") { Slider(value: Binding(get: { rule.scroll?.acceleration ?? 0 }, set: { rule.scroll?.acceleration = $0 }), in: 0...2) }
                      }
                    }
                }
            }
            Section("宏") {
                Toggle("启用宏快捷键", isOn: $store.settings.macrosEnabled)
                Button("新建宏") {
                    let used = Set(store.settings.macros.map(\.shortcutKeyCode))
                    if let key = (99...127).map(UInt16.init).first(where: { !used.contains($0) }) { store.settings.macros.append(InputMacro(shortcutKeyCode: key)) }
                }.disabled(store.settings.macros.count >= 29)
                Text(localized(macroRuntime.status)).font(.caption)
                ForEach($store.settings.macros) { $macro in MacroEditorView(macro: $macro, runtime: macroRuntime, remove: { store.settings.macros.removeAll { $0.id == macro.id } }) }
            }
        }.formStyle(.grouped).padding()
    }

    private func addApplicationRule() {
        guard let profile = selectedProfile, let device = deviceStore.selectedDeviceID else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        store.settings.applicationRules.removeAll { $0.bundleIdentifier == identifier && $0.deviceID == device }
        store.settings.applicationRules.append(ApplicationProfileRule(bundleIdentifier: identifier, deviceID: device, profileID: profile))
    }
}

private struct MacroEditorView: View {
    @Binding var macro: InputMacro
    @ObservedObject var runtime: MacroRuntime
    let remove: () -> Void
    var body: some View {
        DisclosureGroup {
            TextField("名称", text: $macro.name)
            ShortcutRecorder(keyCode: $macro.shortcutKeyCode, modifiers: $macro.shortcutModifiers, title: "录制宏快捷键", onRecord: { key, flags in
                var updated = macro
                updated.shortcutKeyCode = key
                updated.shortcutModifiers = flags
                macro = updated
            }).frame(height: 28)
            Text("可在鼠标按键设置中绑定同一快捷键，触发这个宏。").font(.caption)
            ForEach($macro.steps) { $step in
                HStack {
                    Picker("动作", selection: $step.kind) { Text("按键").tag(MacroStep.Kind.key); Text("等待").tag(MacroStep.Kind.delay); Text("打开应用").tag(MacroStep.Kind.openApplication) }
                    switch step.kind {
                    case .key: ShortcutRecorder(keyCode: $step.keyCode, modifiers: $step.modifiers, title: "录制动作按键").frame(height: 28)
                    case .delay: Stepper("\(step.milliseconds) ms", value: $step.milliseconds, in: 0...60_000, step: 50)
                    case .openApplication:
                        Button(step.applicationPath.isEmpty ? "选择应用" : URL(fileURLWithPath: step.applicationPath).deletingPathExtension().lastPathComponent) {
                            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            if panel.runModal() == .OK, let url = panel.url, url.pathExtension == "app" { step.applicationPath = url.path }
                        }
                    }
                    Button("删除") { macro.steps.removeAll { $0.id == step.id } }
                }
            }
            HStack {
                Button("添加动作") { macro.steps.append(MacroStep()) }
                Button("运行") { runtime.run(macro) }
                Button("停止") { runtime.cancel() }
                Spacer()
                Button("删除宏", action: remove)
            }
        } label: { Text(localized(macro.name)) }
    }
}
