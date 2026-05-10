import SwiftUI
import WebKit

/// Typed canvas artifact previews. Each view renders a single
/// `HermesCanvasArtifact` selected by `HermesCanvasState.primaryArtifact`
/// for its tab. The previews surface daemon-supplied summary/preview/ref
/// metadata in a Mac-native, design-token-aligned layout. They never
/// fetch anything — the daemon owns real browser/code/design execution.

struct CanvasDocumentPreview: View {
    let artifact: HermesCanvasArtifact

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                CanvasArtifactPreviewHeader(artifact: artifact, accent: "Document")
                if let summary = artifact.summary {
                    Text(summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let preview = artifact.preview {
                    Text(preview)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(HermesSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HermesColors.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                                .strokeBorder(HermesColors.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                }
                CanvasArtifactRefRow(ref: artifact.ref)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasArtifact(artifact.id))
    }
}

struct CanvasCodePreview: View {
    let artifact: HermesCanvasArtifact

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                CanvasArtifactPreviewHeader(artifact: artifact, accent: "Code")
                if let summary = artifact.summary {
                    Text(summary)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                pathStrip
                codeBlock
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasArtifact(artifact.id))
    }

    private var pathStrip: some View {
        HStack(spacing: HermesSpacing.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(HermesColors.muted)
            if let path = artifact.codePreviewPath {
                Text(path)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("Untitled file")
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            if let language = artifact.codePreviewLanguage {
                StatusBadge(language, tone: .info)
            }
        }
    }

    @ViewBuilder
    private var codeBlock: some View {
        if let preview = artifact.preview, !preview.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(preview)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.text)
                    .textSelection(.enabled)
                    .padding(HermesSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(HermesColors.field)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        } else {
            Text("No inline preview pinned. Open the file to read the full contents from the daemon.")
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
        }
    }
}

struct CanvasBrowserPreview: View {
    let artifact: HermesCanvasArtifact

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                CanvasArtifactPreviewHeader(artifact: artifact, accent: "Browser")
                if let summary = artifact.summary {
                    Text(summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                urlChrome
                snapshotBlock
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasArtifact(artifact.id))
    }

    private var urlChrome: some View {
        HStack(spacing: HermesSpacing.sm) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(artifact.browserPreviewURL?.scheme == "https" ? HermesColors.success : HermesColors.muted)
            if let url = artifact.browserPreviewURL {
                Text(url.absoluteString)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else if let preview = artifact.preview {
                Text(preview)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("about:blank")
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            if let host = artifact.browserPreviewHost {
                StatusBadge(host, tone: .info)
            }
        }
        .padding(HermesSpacing.sm)
        .background(HermesColors.field)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }

    @ViewBuilder
    private var snapshotBlock: some View {
        if let html = artifact.browserInlineHTML {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                HStack(spacing: HermesSpacing.xs) {
                    Image(systemName: "safari")
                        .foregroundStyle(HermesColors.muted)
                    Text("Rendered preview")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                    Spacer()
                    StatusBadge("HTML", tone: .success)
                }
                CanvasInlineHTMLPreview(html: html)
                    .frame(minHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                            .strokeBorder(HermesColors.border, lineWidth: 1)
                    )
                    .accessibilityIdentifier("canvas-browser-rendered-html-\(artifact.id)")
            }
            .padding(HermesSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesColors.canvas)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                HStack(spacing: HermesSpacing.xs) {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(HermesColors.muted)
                    Text("Snapshot")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                    Spacer()
                }
                Text(artifact.preview ?? "Page snapshot will appear once the daemon captures it.")
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HermesSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesColors.canvas)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        }
    }
}

private struct CanvasInlineHTMLPreview: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

struct CanvasDesignPreview: View {
    let artifact: HermesCanvasArtifact

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                CanvasArtifactPreviewHeader(artifact: artifact, accent: "Design")
                if let summary = artifact.summary {
                    Text(summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                designSurface
                CanvasArtifactRefRow(ref: artifact.ref)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasArtifact(artifact.id))
    }

    private var designSurface: some View {
        VStack(spacing: HermesSpacing.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(HermesColors.subtle)
            if let preview = artifact.preview {
                Text(preview)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else {
                Text("Design preview metadata will land here from the daemon.")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(HermesSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(HermesColors.canvas)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}

struct CanvasBoardPreview: View {
    let artifact: HermesCanvasArtifact

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                CanvasArtifactPreviewHeader(artifact: artifact, accent: "Board")
                if let summary = artifact.summary {
                    Text(summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let preview = artifact.preview {
                    Text(preview)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CanvasArtifactRefRow(ref: artifact.ref)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CanvasAccessibilityID.canvasArtifact(artifact.id))
    }
}

// MARK: - Shared sub-views

private struct CanvasArtifactPreviewHeader: View {
    let artifact: HermesCanvasArtifact
    let accent: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HermesSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                    .lineLimit(2)
                Text(timestampLabel)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            StatusBadge(accent, tone: .info)
        }
    }

    private var timestampLabel: String {
        let date = artifact.updatedAt ?? artifact.createdAt
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let prefix = artifact.updatedAt == nil ? "Captured" : "Updated"
        return "\(prefix) \(formatter.string(from: date))"
    }
}

private struct CanvasArtifactRefRow: View {
    let ref: HermesArtifactRef?

    var body: some View {
        if let ref {
            HStack(spacing: HermesSpacing.sm) {
                ArtifactChip(title: ref.title, kind: chipKind(for: ref.kind))
                if let detail = ref.detail, !detail.isEmpty, detail != ref.title {
                    Text(detail)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
        }
    }

    private func chipKind(for kind: HermesArtifactRef.Kind) -> ArtifactChip.Kind {
        switch kind {
        case .file:    return .file
        case .link:    return .link
        case .command: return .command
        case .message, .generated, .other, .unknown: return .other
        }
    }
}
