import Foundation
import SwiftUI

/// Single source of truth for cross-scene navigation. Lifted out of
/// `AppShellView` so the menu bar popover, the quick prompt window,
/// and the local notification center can all drive the main window's
/// selection without owning their own copy of state.
///
/// The router is intentionally a pure reducer — methods mutate
/// published state and never reach across the boundary into the
/// daemon. This keeps deep-link routing testable without rendering UI.
@MainActor
public final class AppRouter: ObservableObject {
    @Published public var selection: SidebarNavSection = .home
    @Published public var inspectorVisible: Bool = true

    /// Optional focus targets set by deep-link routing. Each route
    /// only sets the slot it needs and clears the others; the views
    /// observe whichever slot is meaningful for the active selection.
    @Published public private(set) var focusedApprovalID: String?
    @Published public private(set) var focusedAutomationID: String?
    @Published public private(set) var focusedConnectorID: String?
    @Published public private(set) var focusedSessionID: String?

    /// The most recent deep-link the router applied. Useful for
    /// banner/toast surfaces and for tests asserting routing history.
    @Published public private(set) var lastDeepLink: HermesNotificationDeepLink?

    public init() {}

    /// Apply a deep-link to the navigation state. Any prior focus
    /// slots are cleared first so an old approval id doesn't bleed
    /// into a new automation route.
    public func handle(_ link: HermesNotificationDeepLink) {
        clearFocus()
        lastDeepLink = link
        switch link.route {
        case .actionCenter(let approvalID):
            selection = .actionCenter
            focusedApprovalID = approvalID
        case .automations(let focusID):
            selection = .automations
            focusedAutomationID = focusID
        case .connectors(let focusID):
            selection = .connectors
            focusedConnectorID = focusID
        case .sessions(let sessionID):
            selection = .sessions
            focusedSessionID = sessionID
        case .settings:
            selection = .settings
        }
    }

    /// Direct selection change — used by the sidebar binding and by
    /// the menu bar's quick actions.
    public func go(to section: SidebarNavSection) {
        clearFocus()
        selection = section
    }

    /// Reset every focus slot. Called by `handle(_:)` and by views
    /// that consume a focus value.
    public func clearFocus() {
        focusedApprovalID = nil
        focusedAutomationID = nil
        focusedConnectorID = nil
        focusedSessionID = nil
    }

    public func toggleInspector() {
        inspectorVisible.toggle()
    }
}
