import SwiftUI

public enum HermesTypography {
    public static let caption    = Font.system(size: 11, weight: .medium)
    public static let body       = Font.system(size: 13, weight: .regular)
    public static let bodyStrong = Font.system(size: 13, weight: .semibold)
    public static let section    = Font.system(size: 14, weight: .semibold)
    public static let title      = Font.system(size: 22, weight: .bold)
    public static let display    = Font.system(size: 30, weight: .bold)
    public static let mono       = Font.system(.body, design: .monospaced)
}

public extension View {
    func hermesCaption() -> some View {
        font(HermesTypography.caption).foregroundStyle(HermesColors.muted)
    }
    func hermesBody() -> some View {
        font(HermesTypography.body).foregroundStyle(HermesColors.text)
    }
    func hermesBodyStrong() -> some View {
        font(HermesTypography.bodyStrong).foregroundStyle(HermesColors.text)
    }
    func hermesSection() -> some View {
        font(HermesTypography.section).foregroundStyle(HermesColors.text)
    }
    func hermesTitle() -> some View {
        font(HermesTypography.title).foregroundStyle(HermesColors.text)
    }
    func hermesDisplay() -> some View {
        font(HermesTypography.display).foregroundStyle(HermesColors.text)
    }
}
