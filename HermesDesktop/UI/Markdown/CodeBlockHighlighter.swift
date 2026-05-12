import Foundation
import AppKit
import SwiftUI
import Highlightr

/// Wraps Highlightr behind a cached, MainActor-isolated interface.
///
/// SCOPE.md acceptance #3: "Code blocks render with Highlightr
/// syntax highlighting on close-fence." SCOPE.md performance
/// requirement (from WU3.1 finding 6): "Highlightr fires once per
/// code block, on close-fence detection. Not per-token. This is
/// critical for performance — syntax highlighting on every token
/// would tank the streaming hot path."
///
/// **Caching strategy.** Keyed by `(language, body)`. A code block's
/// `body` is stable once the close fence arrives; the same key
/// hashes to the same highlighted output forever, so we memoize.
/// The cache is per-instance (one instance lives on the
/// `StreamingMarkdownRenderer`'s environment).
///
/// **Theme selection.** Hard-coded to a dark-friendly theme that
/// fits Diak's color palette (`HermesColors.canvas` background).
/// Phase 3 SCOPE.md doesn't authorize a theme-picker UI; one is
/// chosen at construction time and used everywhere.
///
/// **Failure mode.** If Highlightr returns `nil` (init failed,
/// language not in its bundled set, etc.), the renderer falls
/// back to plain monospace text. No crash, no flicker — just an
/// unhighlighted code block.
@MainActor
public final class CodeBlockHighlighter {

    public static let shared = CodeBlockHighlighter()

    private let highlightr: Highlightr?
    private let themeName: String
    private var cache: [CacheKey: AttributedString] = [:]

    /// Theme tuned for a dark-on-light reading surface. Diak's
    /// chat canvas uses `HermesColors.canvas` (warm off-white);
    /// Atom One Light reads well there. Switch to a dark theme if
    /// the app gains dark mode support.
    public init(themeName: String = "atom-one-light") {
        self.highlightr = Highlightr()
        self.themeName = themeName
        _ = self.highlightr?.setTheme(to: themeName)
    }

    /// Highlight a (language, body) pair. Returns an
    /// `AttributedString` ready for SwiftUI `Text`. Cached.
    /// `nil` means Highlightr couldn't produce output — caller
    /// must render plain monospace fallback.
    public func highlight(language: String?, body: String) -> AttributedString? {
        let key = CacheKey(language: language ?? "", body: body)
        if let cached = cache[key] {
            return cached
        }
        guard let highlightr else { return nil }
        let lang = language?.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved: String? = (lang?.isEmpty ?? true) ? nil : lang
        guard let nsAttributed = highlightr.highlight(body, as: resolved, fastRender: true) else {
            return nil
        }
        let attributed = AttributedString(nsAttributed)
        cache[key] = attributed
        return attributed
    }

    /// Drop cached entries. Tests call this to ensure successive
    /// runs are independent.
    public func clearCache() {
        cache.removeAll(keepingCapacity: true)
    }

    private struct CacheKey: Hashable {
        let language: String
        let body: String
    }
}
