import SwiftUI

/// Semantic colors derived from
/// `Docs/DesignPackage/hermes_desktop_design_package/tokens/hermes_notion_inspired_tokens.json`.
///
/// Each color resolves to a different value in light vs dark appearance using
/// `Color(NSColor(name:dynamicProvider:))`. Always reference colors through
/// `HermesColors` so theme changes stay centralized.
public enum HermesColors {
    public static let bg            = dynamic(light: 0xF7F6F3, dark: 0x171717)
    public static let canvas        = dynamic(light: 0xEFEEEA, dark: 0x111111)
    public static let surface       = dynamic(light: 0xFFFFFF, dark: 0x202020)
    public static let card          = dynamic(light: 0xFFFFFF, dark: 0x242424)
    public static let sidebar       = dynamic(light: 0xF1F0EC, dark: 0x1D1D1D)
    public static let field         = dynamic(light: 0xF7F6F2, dark: 0x262626)
    public static let selected      = dynamic(light: 0xE9E7E3, dark: 0x2E2D2A)
    public static let hover         = dynamic(light: 0xF5F4F0, dark: 0x292929)
    public static let border        = dynamic(light: 0xE2DFD8, dark: 0x363636)
    public static let text          = dynamic(light: 0x2F2F2D, dark: 0xEDEDEB)
    public static let muted         = dynamic(light: 0x787774, dark: 0xA7A39E)
    public static let subtle        = dynamic(light: 0xA7A49E, dark: 0x77736E)
    public static let invert        = dynamic(light: 0xFFFFFF, dark: 0x111111)
    public static let accent        = dynamic(light: 0x2F2F2D, dark: 0xF4F4F2)

    public static let success       = dynamic(light: 0x2E7D55, dark: 0x6EC28F)
    public static let successBg     = dynamic(light: 0xEDF7F1, dark: 0x1F3329)
    public static let warning       = dynamic(light: 0xA15C00, dark: 0xE5A64A)
    public static let warningBg     = dynamic(light: 0xFFF3E1, dark: 0x3A2D1C)
    public static let danger        = dynamic(light: 0xC33A3A, dark: 0xF07878)
    public static let dangerBg      = dynamic(light: 0xFDECEC, dark: 0x3A2323)
    public static let info          = dynamic(light: 0x4E6791, dark: 0x94A9C9)
    public static let infoBg        = dynamic(light: 0xEEF3F8, dark: 0x1F2C3A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
