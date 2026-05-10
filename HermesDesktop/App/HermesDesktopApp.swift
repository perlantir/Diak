import SwiftUI

@main
struct HermesDesktopApp: App {
    @StateObject private var daemon: DaemonStatusViewModel
    @StateObject private var engineViewModel: HermesEngineViewModel
    @StateObject private var onboarding = OnboardingViewModel()

    init() {
        // M0: real client by default; an offline daemon surfaces as the
        // offline/reconnect sheet rather than a crash.
        let client: HermesAPIClient = URLSessionHermesAPIClient()
        let daemonVM = DaemonStatusViewModel(client: client)
        _daemon = StateObject(wrappedValue: daemonVM)
        _engineViewModel = StateObject(wrappedValue: HermesEngineViewModel(daemon: daemonVM))
    }

    var body: some Scene {
        WindowGroup("Hermes Desktop") {
            RootView(daemon: daemon,
                     engineViewModel: engineViewModel,
                     onboarding: onboarding)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private struct RootView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @ObservedObject var onboarding: OnboardingViewModel

    var body: some View {
        Group {
            if onboarding.hasCompleted {
                AppShellView(daemon: daemon, engineViewModel: engineViewModel)
            } else {
                OnboardingShellView(viewModel: onboarding, daemon: daemon)
            }
        }
        .preferredColorScheme(nil)
    }
}
