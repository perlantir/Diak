import SwiftUI

@main
struct HermesDesktopApp: App {
    @StateObject private var daemon: DaemonStatusViewModel
    @StateObject private var engineViewModel: HermesEngineViewModel
    @StateObject private var onboarding = OnboardingViewModel()
    @StateObject private var router = AppRouter()
    @StateObject private var approvals: ApprovalsViewModel
    @StateObject private var menuBarVM: MenuBarViewModel
    @StateObject private var quickPrompt: QuickPromptViewModel
    @StateObject private var compactWindow = CompactWindowViewModel()
    @StateObject private var notifications: LocalNotificationCenter

    @Environment(\.openWindow) private var openWindow

    private let client: HermesAPIClient
    private let bridgeManager: HermesBridgeProcessManager

    init() {
        // Real client by default; if the endpoint is offline, the daemon view
        // model asks the bridge manager to launch the production local bridge
        // and then retries the same health/version checks.
        let bridgeManager = HermesBridgeProcessManager()
        let client: HermesAPIClient = URLSessionHermesAPIClient()
        self.client = client
        self.bridgeManager = bridgeManager
        let daemonVM = DaemonStatusViewModel(client: client, bridgeManager: bridgeManager)
        let routerInstance = AppRouter()
        _daemon = StateObject(wrappedValue: daemonVM)
        _engineViewModel = StateObject(wrappedValue: HermesEngineViewModel(daemon: daemonVM))
        _approvals = StateObject(wrappedValue: ApprovalsViewModel(client: client))
        _menuBarVM = StateObject(wrappedValue: MenuBarViewModel(client: client))
        _quickPrompt = StateObject(wrappedValue: QuickPromptViewModel(client: client, router: routerInstance))
        _router = StateObject(wrappedValue: routerInstance)
        _notifications = StateObject(wrappedValue: LocalNotificationCenter(router: routerInstance))
    }

    var body: some Scene {
        WindowGroup(AppBrand.windowTitle) {
            RootView(daemon: daemon,
                     engineViewModel: engineViewModel,
                     onboarding: onboarding,
                     router: router,
                     approvals: approvals,
                     compactWindow: compactWindow,
                     client: client,
                     openQuickPrompt: openQuickPromptWindow)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .windowArrangement) {
                Button("Quick Prompt") {
                    openQuickPromptWindow()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button(compactWindow.isCompact ? "Expand Standard Window" : "Compact Window") {
                    compactWindow.toggle()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }

        Window(AppBrand.quickPromptTitle, id: HermesDesktopApp.quickPromptWindowID) {
            QuickPromptView(viewModel: quickPrompt) {
                quickPrompt.dismiss()
            }
            .onAppear { quickPrompt.show() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarPopoverView(menuBarVM: menuBarVM,
                               router: router,
                               quickPrompt: quickPrompt,
                               compactWindow: compactWindow,
                               notifications: notifications,
                               openMainWindow: openMainWindow,
                               openQuickPromptWindow: openQuickPromptWindow)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    static let quickPromptWindowID = "hermes-quick-prompt"

    private func openQuickPromptWindow() {
        quickPrompt.show()
        openWindow(id: HermesDesktopApp.quickPromptWindowID)
    }

    private func openMainWindow() {
        // The main window is the default WindowGroup; bringing it forward
        // is handled by AppKit when a window-bound action runs.
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let badge = menuBarVM.badgeText {
            Image(systemName: "sparkles")
                .overlay(alignment: .topTrailing) {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
                .accessibilityLabel(menuBarVM.badgeAccessibilityLabel)
        } else {
            Image(systemName: "sparkles")
                .accessibilityLabel(menuBarVM.badgeAccessibilityLabel)
        }
    }
}

private struct RootView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @ObservedObject var onboarding: OnboardingViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var approvals: ApprovalsViewModel
    @ObservedObject var compactWindow: CompactWindowViewModel
    let client: HermesAPIClient
    let openQuickPrompt: () -> Void

    var body: some View {
        Group {
            if onboarding.hasCompleted {
                AppShellView(daemon: daemon,
                             engineViewModel: engineViewModel,
                             approvals: approvals,
                             router: router,
                             compactWindow: compactWindow,
                             client: client,
                             openQuickPrompt: openQuickPrompt)
            } else {
                OnboardingShellView(viewModel: onboarding, daemon: daemon)
            }
        }
        .task { await daemon.refresh() }
        .preferredColorScheme(nil)
    }
}
