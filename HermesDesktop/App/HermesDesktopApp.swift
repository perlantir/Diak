import SwiftUI
import AppKit

@main
struct HermesDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: Path B production state
    //
    // Owned at the App level so each tab/window observes the same instance.
    // - `supervisor` manages the real `hermes dashboard` subprocess (WU2).
    // - `sessionStore` is Diak's local SwiftData persistence (WU5).
    // - `dashboardClient` is the typed HTTP client against Hermes' dashboard
    //   surface (WU3). Created once with a `TokenProvider` closure that
    //   reads `supervisor.health` lazily, so token rotation across
    //   dashboard restarts is handled without reconstructing the client.
    // - `apiServerClient` is the inference backend client (WU4). It needs
    //   a persistent API key from the Keychain; lazily produced when the
    //   chat composer asks for one. Phase 1 holds it via `apiServerKey`.
    @StateObject private var supervisor: HermesProcessSupervisor
    @StateObject private var sessionStore: DiakSessionStore
    @StateObject private var hermesState: HermesState
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

    // Legacy HermesAPIClient (mock) is still used by view models for
    // Diak-owned features (approvals, automations, memory, connectors)
    // whose real implementations land in Phase 3/4/5. Per Path B / WU6
    // direction: real Hermes-owned data flows via `dashboardClient`;
    // legacy `client` is restricted to placeholder fixtures until the
    // owning views move to Diak-native implementations.
    private let client: HermesAPIClient
    private let dashboardClient: HermesDashboardClient
    private let apiServerClient: HermesAPIServerClient?

    init() {
        // Initialize supervisor first — it owns the dashboard process
        // lifecycle. Default port 9119 + default executable
        // `~/.local/bin/hermes`.
        let supervisorInstance = HermesProcessSupervisor()
        _supervisor = StateObject(wrappedValue: supervisorInstance)

        // Dashboard HTTP client — TokenProvider closure reads the
        // supervisor's live `.health` so token rotation across
        // dashboard restarts is transparent to callers. `weak` capture
        // prevents a retain cycle (supervisor outlives the client by
        // virtue of being held by the @StateObject machinery).
        let dashboardInstance = HermesDashboardClient(
            tokenProvider: { @Sendable [weak supervisorInstance] _ in
                let snapshot = await MainActor.run { supervisorInstance?.health ?? .stopped }
                if case let .running(_, _, token) = snapshot {
                    return token
                }
                throw HermesDashboardClient.ClientError.notAuthenticated(
                    reason: "Hermes dashboard supervisor reports \(snapshot)"
                )
            }
        )
        self.dashboardClient = dashboardInstance

        // API Server client — only constructed when an API_SERVER_KEY
        // is present in the Keychain (WU4). Phase 1 ships without
        // automatic enablement; Nick sets the key once outside the app,
        // we read it here at launch. Absence is the normal path until
        // Nick signals API_SERVER_ENABLED=true on his machine.
        var apiServerInstance: HermesAPIServerClient?
        do {
            let keychainStore = APIServerKeychainStore()
            if let key = try keychainStore.loadKey(), !key.isEmpty {
                apiServerInstance = HermesAPIServerClient(apiKey: key)
            }
        } catch {
            // Keychain read failed — surface as offline chat (per WU6
            // ChatViewModel offline placeholder path) rather than
            // crashing.
            apiServerInstance = nil
        }
        self.apiServerClient = apiServerInstance

        // Session store — falls back to in-memory if the disk store
        // can't be opened (extremely rare; surfaces as a UI message).
        let store: DiakSessionStore
        do {
            store = try DiakSessionStore()
        } catch {
            // SwiftData failure on the user's disk should not crash
            // the app. Fall back to in-memory so the rest of WU6's
            // wiring continues to work; the user will see chat
            // history disappear across restarts.
            store = (try? DiakSessionStore(inMemory: true))
                ?? (try! DiakSessionStore(inMemory: true))
        }
        _sessionStore = StateObject(wrappedValue: store)

        // Legacy mock client for Diak-owned placeholder view models.
        let legacyClient: HermesAPIClient = MockHermesAPIClient()
        self.client = legacyClient

        // Phase 2 WU2.2: HermesState is canonical. Construct it
        // before any view model that observes it. The daemon view
        // model is the WU2.2 proof-of-pattern — it derives status
        // from HermesState's dashboard + supervisorHealth slices.
        let hermesStateInstance = HermesState()
        _hermesState = StateObject(wrappedValue: hermesStateInstance)

        let daemonVM = DaemonStatusViewModel(
            hermesState: hermesStateInstance,
            dashboardClient: dashboardInstance,
            legacyClient: legacyClient
        )
        let routerInstance = AppRouter()
        _daemon = StateObject(wrappedValue: daemonVM)
        _engineViewModel = StateObject(wrappedValue: HermesEngineViewModel(
            daemon: daemonVM,
            supervisor: supervisorInstance
        ))
        _approvals = StateObject(wrappedValue: ApprovalsViewModel(client: legacyClient))
        _menuBarVM = StateObject(wrappedValue: MenuBarViewModel(client: legacyClient))
        _quickPrompt = StateObject(wrappedValue: QuickPromptViewModel(client: legacyClient, router: routerInstance))
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
                     supervisor: supervisor,
                     sessionStore: sessionStore,
                     dashboardClient: dashboardClient,
                     apiServerClient: apiServerClient,
                     openQuickPrompt: openQuickPromptWindow)
            .environmentObject(hermesState)
            .environmentObject(supervisor)
            .environmentObject(sessionStore)
            .task {
                // Start the dashboard once on app launch. If the binary is
                // missing or the server fails to bind, supervisor.health
                // surfaces .crashed; the UI shows the offline path.
                do {
                    try await supervisor.start()
                } catch {
                    // Logged through supervisor.health = .crashed already;
                    // do not crash the app.
                }
            }
            .onReceive(supervisor.$health) { newHealth in
                // Phase 2 WU2.2: bridge supervisor → HermesState so
                // the reducer sees process lifecycle transitions.
                // The DaemonStatusViewModel reads
                // `hermesState.supervisorHealth` to compose its
                // banner status.
                hermesState.dispatch(.supervisorHealthChanged(newHealth))
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                // SCOPE.md WU6 acceptance #6: "No orphan Hermes or bridge
                // processes after Cmd-Q". applicationWillTerminate is
                // synchronous, so use the sync SIGTERM helper.
                supervisor.terminateImmediately()
            }
            .onOpenURL { url in
                _ = DeepLinkParser.parse(url)
            }
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
    @ObservedObject var supervisor: HermesProcessSupervisor
    @ObservedObject var sessionStore: DiakSessionStore
    let dashboardClient: HermesDashboardClient
    let apiServerClient: HermesAPIServerClient?
    let openQuickPrompt: () -> Void

    var body: some View {
        Group {
            if onboarding.hasCompleted {
                AppShellView(daemon: daemon,
                             engineViewModel: engineViewModel,
                             approvals: approvals,
                             router: router,
                             compactWindow: compactWindow,
                             supervisor: supervisor,
                             sessionStore: sessionStore,
                             dashboardClient: dashboardClient,
                             apiServerClient: apiServerClient,
                             client: client,
                             openQuickPrompt: openQuickPrompt)
            } else {
                OnboardingShellView(viewModel: onboarding, daemon: daemon)
            }
        }
        .preferredColorScheme(nil)
    }
}
