import SwiftUI

/// Stores OpenSnek app data.
@main struct MouseControlApp: App {
    private static let minimumMainWindowWidth: CGFloat = 900
    private static let minimumMainWindowHeight: CGFloat = 600
    private static let defaultMainWindowWidth: CGFloat = 1250
    private static let defaultMainWindowHeight: CGFloat = 800
    private let isUnitTestRun: Bool

    static var runningUnitTests: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestBundlePath"] != nil || environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appLifecycle
    @State private var appState: AppState
    @StateObject private var language = LanguageStore.shared
    @StateObject private var icons = IconStore.shared

    init() {
        isUnitTestRun = Self.runningUnitTests
        let launchRole = OpenSnekProcessRole.current
        if !isUnitTestRun, BackgroundServiceCoordinator.shared.backgroundOnly {
            BackgroundServiceCoordinator.shared.setBackgroundServiceEnabled(true)
        }
        let isUITestRun: Bool
        #if DEBUG
            isUITestRun = OpenSnekUITestSupport.isEnabled
            if isUITestRun { OpenSnekUITestSupport.recordLaunch(role: launchRole) }
        #else
            isUITestRun = false
        #endif

        let initialAppState = AppState(launchRole: launchRole, shouldCheckForReleaseUpdates: (isUITestRun || isUnitTestRun) ? false : ReleaseUpdateChecker.shouldCheckForUpdates(), autoStart: !isUnitTestRun)
        _appState = State(initialValue: initialAppState)
        if !isUnitTestRun { Task { @MainActor in FeatureRuntime.shared.attach(initialAppState) } }

        #if DEBUG
            if isUITestRun, !launchRole.isService {
                Task { @MainActor in
                    await initialAppState.runtimeController.start()
                    await initialAppState.runtimeController.refreshHIDAccessStatus(forceRefresh: false)
                }
            }
        #endif
    }

    var body: some Scene {
        WindowGroup("") {
            Group {
                if isUnitTestRun {
                    Color.clear
                } else if appState.runtimeStore.isServiceProcess {
                    ServiceWindowSuppressorView()
                } else {
                    ContentView(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore).frame(minWidth: Self.minimumMainWindowWidth, minHeight: Self.minimumMainWindowHeight).background(WindowChromeConfigurator().frame(width: 0, height: 0))
                        .background(SettingsOpenBridgeView(runtimeStore: appState.runtimeStore).frame(width: 0, height: 0))
                }
            }.openSnekFixedAppearance().environment(\.locale, language.locale)
        }.defaultSize(width: Self.defaultMainWindowWidth, height: Self.defaultMainWindowHeight)

        MenuBarExtra(isInserted: .constant(appState.runtimeStore.isServiceProcess)) {
            ServiceMenuBarView(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore).openSnekFixedAppearance().environment(\.locale, language.locale)
        } label: {
            ServiceMenuBarStatusItemLabel(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore).id(icons.style)
        }.menuBarExtraStyle(.window)

        Settings { MouseControlSettingsView(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore).openSnekFixedAppearance().environment(\.locale, language.locale) }
    }
}

/// Stores service window suppressor view data.
private struct ServiceWindowSuppressorView: NSViewRepresentable {
    func makeNSView(context: Context) -> SuppressorView { SuppressorView() }

    func updateNSView(_ nsView: SuppressorView, context: Context) {}

    /// Coordinates suppressor view behavior.
    final class SuppressorView: NSView {
        private weak var suppressedWindow: NSWindow?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            guard let newWindow else { return }
            suppress(window: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            suppress(window: window)
        }

        private func suppress(window: NSWindow) {
            guard suppressedWindow !== window else { return }
            suppressedWindow = window

            // The service process uses a WindowGroup only to satisfy SwiftUI scene
            // requirements. Hide that transient window before AppKit can present it.
            window.alphaValue = 0
            window.hasShadow = false
            window.animationBehavior = .none
            window.ignoresMouseEvents = true
            window.orderOut(nil)

            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                window.orderOut(nil)
                window.close()
            }
        }
    }
}

/// Stores settings open bridge view data.
private struct SettingsOpenBridgeView: View {
    let runtimeStore: RuntimeStore

    @Environment(\.openSettings) private var openSettings
    @State private var didHandleLaunchSettingsRequest = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear { handleLaunchSettingsRequestIfNeeded() }.onChange(of: runtimeStore.openSettingsRequestCount) { _, count in
            guard count > 0 else { return }
            openSettings()
        }
    }

    private func handleLaunchSettingsRequestIfNeeded() {
        guard !didHandleLaunchSettingsRequest else { return }
        guard ProcessInfo.processInfo.arguments.contains("--open-settings") else { return }
        didHandleLaunchSettingsRequest = true
        DispatchQueue.main.async { openSettings() }
    }
}
