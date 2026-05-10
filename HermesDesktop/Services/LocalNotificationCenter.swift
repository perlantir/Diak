import Foundation
import SwiftUI

/// Typed local "notification inbox" for M7. The Diak app
/// does **not** send real macOS notifications from this code path —
/// real banners remain a packaging/M8 concern. This service models
/// the deep-link surface only:
///
/// - `deliver(_:)` records a payload (used by the daemon mock and
///   tests to simulate the daemon delivering a notification).
/// - `userOpened(_:)` simulates the user clicking a notification —
///   the only place that drives the router. Tests assert the router
///   advances to the right sidebar section + focus id.
///
/// The split keeps "the user opened a notification" explicit and
/// excludes incidental side effects from background polling.
@MainActor
public final class LocalNotificationCenter: ObservableObject {
    /// Most recent notifications, newest first.
    @Published public private(set) var inbox: [HermesNotificationDeepLink] = []

    /// The last payload delivered by the daemon, regardless of whether
    /// the user has clicked it. Used by the menu bar popover header.
    @Published public private(set) var lastDelivered: HermesNotificationDeepLink?

    public let inboxLimit: Int

    private let router: AppRouter

    public init(router: AppRouter, inboxLimit: Int = 32) {
        self.router = router
        self.inboxLimit = inboxLimit
    }

    /// Record a typed notification payload. No real `UNNotification`
    /// is posted here — the daemon owns notification permission/UX.
    public func deliver(_ link: HermesNotificationDeepLink) {
        inbox.removeAll { $0.id == link.id }
        inbox.insert(link, at: 0)
        if inbox.count > inboxLimit {
            inbox = Array(inbox.prefix(inboxLimit))
        }
        lastDelivered = link
    }

    /// User explicitly clicked / activated a notification entry.
    /// Drives the router so the main window lands on the right route.
    public func userOpened(_ link: HermesNotificationDeepLink) {
        router.handle(link)
        inbox.removeAll { $0.id == link.id }
    }

    /// User dismissed the entry without opening it (swipe / clear).
    public func dismiss(_ link: HermesNotificationDeepLink) {
        inbox.removeAll { $0.id == link.id }
    }

    public func clearAll() {
        inbox.removeAll()
        lastDelivered = nil
    }

    public var unreadCount: Int { inbox.count }
}
