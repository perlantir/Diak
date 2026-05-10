import Foundation
import SwiftUI

/// Compact-mode UI state (design screen 47). Compact mode collapses
/// the sidebar and inspector so the composer + transcript become the
/// primary surface — useful for floating-window/picture-in-picture
/// workflows. Daemon behavior is unchanged; this is purely local UI
/// state.
///
/// Approval modals continue to render even in compact mode — the
/// design explicitly preserves safety affordances when the layout
/// shrinks.
@MainActor
public final class CompactWindowViewModel: ObservableObject {
    public static let standardMinSize  = CGSize(width: 960, height: 600)
    public static let compactMinSize   = CGSize(width: 540, height: 480)
    public static let compactIdealSize = CGSize(width: 620, height: 540)

    @Published public private(set) var isCompact: Bool = false

    public init(initialIsCompact: Bool = false) {
        self.isCompact = initialIsCompact
    }

    public var hidesSidebar: Bool   { isCompact }
    public var hidesInspector: Bool { isCompact }

    public var minSize: CGSize {
        isCompact ? Self.compactMinSize : Self.standardMinSize
    }

    public var idealSize: CGSize {
        isCompact ? Self.compactIdealSize : Self.standardMinSize
    }

    public func toggle() {
        isCompact.toggle()
    }

    public func enter() {
        isCompact = true
    }

    public func exit() {
        isCompact = false
    }

    /// Adjust compact state from a window resize. Used by the
    /// optional `.onChange(of: frame.size)` hook on the host scene
    /// so the layout collapses when the user drags the window narrow.
    /// Pure: tests can call this without an NSWindow.
    public func adjust(forWidth width: CGFloat) {
        let breakpoint = Self.compactIdealSize.width + 60
        let nextCompact = width < breakpoint
        if nextCompact != isCompact {
            isCompact = nextCompact
        }
    }
}
