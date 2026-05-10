import Foundation

/// Deterministic accessibility identifier vocabulary for the Chat +
/// Canvas split workspace. Centralized so SwiftUI views and XCTest
/// targets resolve the same strings — tests can assert against the
/// identifier surface without forking the convention.
public enum CanvasAccessibilityID {
    public static let chatRootSplit       = "chat-root-split"
    public static let chatTranscriptPane  = "chat-transcript-pane"
    public static let chatCanvasPane      = "chat-canvas-pane"
    public static let canvasHeader        = "canvas-header"
    public static let canvasTitle         = "canvas-title"
    public static let canvasTabStrip      = "canvas-tab-strip"
    public static let canvasActivityFeed  = "canvas-activity-feed"

    public static func canvasTab(_ tab: HermesCanvasTab) -> String {
        "canvas-tab-\(tab.rawValue)"
    }

    public static func canvasPrimaryPreview(_ tab: HermesCanvasTab) -> String {
        "canvas-primary-\(tab.rawValue)"
    }

    public static func canvasSecondaryList(_ tab: HermesCanvasTab) -> String {
        "canvas-secondary-list-\(tab.rawValue)"
    }

    public static func canvasArtifact(_ artifactID: String) -> String {
        "canvas-artifact-\(artifactID)"
    }

    public static func canvasSecondaryArtifact(_ artifactID: String) -> String {
        "canvas-secondary-artifact-\(artifactID)"
    }

    public static func canvasEmpty(_ tab: HermesCanvasTab) -> String {
        "canvas-empty-\(tab.rawValue)"
    }

    public static func canvasLoading(_ tab: HermesCanvasTab) -> String {
        "canvas-loading-\(tab.rawValue)"
    }

    public static func canvasError(_ tab: HermesCanvasTab) -> String {
        "canvas-error-\(tab.rawValue)"
    }

    public static func canvasActivityRow(_ activityID: String) -> String {
        "canvas-activity-\(activityID)"
    }
}

/// Deterministic visual structure of `HermesCanvasState` at a moment in
/// time. Built so XCTest can assert what the canvas *would* render —
/// which tabs have a typed primary preview, which secondary artifacts
/// trail it, and which empty/loading/error hints would be visible —
/// without touching SwiftUI or macOS Accessibility/TCC. Cron-safe.
public struct HermesCanvasVisualSnapshot: Equatable, Sendable {
    public enum TabFallback: Equatable, Sendable {
        case typedPrimary
        case scaffolding
        case loading
        case error(String)
        case empty
    }

    public struct TabSnapshot: Equatable, Sendable {
        public let tab: HermesCanvasTab
        public let primaryArtifactID: String?
        public let secondaryArtifactIDs: [String]
        /// What the user actually sees when this tab is rendered.
        /// `typedPrimary` wins when an artifact pinned to this tab
        /// exists. Document and Board fall back to `scaffolding` (the
        /// bootstrap sections / task board) instead of an empty hint.
        public let fallback: TabFallback

        public var primaryAccessibilityID: String? {
            primaryArtifactID.map { CanvasAccessibilityID.canvasArtifact($0) }
        }
    }

    public let activeTab: HermesCanvasTab
    public let documentTitle: String
    public let tabs: [TabSnapshot]
    public let activityIDs: [String]
    public let artifactBoundaryNote: String?

    public func tab(_ tab: HermesCanvasTab) -> TabSnapshot {
        tabs.first { $0.tab == tab } ?? TabSnapshot(
            tab: tab,
            primaryArtifactID: nil,
            secondaryArtifactIDs: [],
            fallback: .empty
        )
    }
}

public extension HermesCanvasState {
    /// Snapshot the visible canvas surface for a given load context. The
    /// returned snapshot is deterministic for a given state + load
    /// inputs and is the testability seam for Chat + Canvas QA.
    func visualSnapshot(artifactLoadError: String? = nil,
                        isLoadingArtifacts: Bool = false) -> HermesCanvasVisualSnapshot {
        let tabSnapshots = HermesCanvasTab.allCases.map { tab in
            let primary = primaryArtifact(for: tab)
            let secondary = secondaryArtifacts(for: tab).map(\.id)
            let fallback: HermesCanvasVisualSnapshot.TabFallback = {
                if primary != nil { return .typedPrimary }
                switch tab {
                case .document, .board:
                    return .scaffolding
                case .browser, .code, .design:
                    if let error = artifactLoadError { return .error(error) }
                    if isLoadingArtifacts { return .loading }
                    return .empty
                }
            }()
            return HermesCanvasVisualSnapshot.TabSnapshot(
                tab: tab,
                primaryArtifactID: primary?.id,
                secondaryArtifactIDs: secondary,
                fallback: fallback
            )
        }
        return HermesCanvasVisualSnapshot(
            activeTab: activeTab,
            documentTitle: documentTitle,
            tabs: tabSnapshots,
            activityIDs: activities.map(\.id),
            artifactBoundaryNote: artifactBoundaryNote
        )
    }
}
