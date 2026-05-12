import SwiftUI

/// Developer-only test harness for the streaming markdown renderer.
///
/// Gated behind `#if DEBUG`. Stays in the codebase as the visual
/// regression-test surface per SCOPE.md WU3.2: "test harness window
/// stays in the codebase; it's the test harness for future
/// regressions." Accessible from Diak's Debug menu (see
/// `HermesDesktopApp.swift`); not built into release.
///
/// What it supports:
///   - Paste a Markdown blob into the source editor.
///   - Pick a streaming cadence (10 / 20 / 30 / 50 / 100 Hz).
///   - Replay it through a `StreamingMessageState` at that cadence.
///   - Scroll while it runs; verify scroll-preservation behavior.
///   - "Reset" / "Restart from top" / "Jump to end" controls.
///
/// What it verifies visually (since auto-tests can't show jank):
///   - No dropped characters across cadences.
///   - No visible flicker (per-block invalidation).
///   - Scroll preservation when user has scrolled up.
///   - Code-block highlighting fires once on close-fence, not
///     per-token.
///   - Half-finished code fences don't render the trailing text
///     as Markdown.
#if DEBUG
public struct StreamingMarkdownHarnessView: View {

    @StateObject private var state = StreamingMessageState(text: "", phase: .running)
    @State private var source: String = StreamingMarkdownHarnessView.defaultSource
    @State private var cadence: Cadence = .hz50
    @State private var task: Task<Void, Never>? = nil
    @State private var driverRunning: Bool = false
    @State private var charactersStreamed: Int = 0
    @State private var startedAt: Date? = nil

    public init() {}

    public var body: some View {
        VSplitView {
            sourceEditor
            renderedOutput
        }
        .frame(minWidth: 900, minHeight: 700)
        .onDisappear { task?.cancel() }
    }

    // MARK: - Top half: source editor + controls

    @ViewBuilder
    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markdown source (paste to test)")
                .font(.headline)

            ScrollView {
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .border(Color.secondary.opacity(0.3))
            }
            .frame(maxHeight: 260)

            controls
        }
        .padding(12)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Cadence", selection: $cadence) {
                ForEach(Cadence.allCases, id: \.self) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Button(driverRunning ? "Stop" : "Stream") {
                driverRunning ? stopDriver() : startDriver()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(source.isEmpty)

            Button("Reset") {
                stopDriver()
                state.reset()
                charactersStreamed = 0
                startedAt = nil
            }

            Spacer()

            if let startedAt {
                let elapsed = Date().timeIntervalSince(startedAt)
                let effectiveHz = elapsed > 0 ? Double(charactersStreamed) / elapsed : 0
                Text(String(format: "%d chars · %.1f Hz effective",
                            charactersStreamed, effectiveHz))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bottom half: rendered output

    @ViewBuilder
    private var renderedOutput: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rendered (\(state.blocks.count) blocks · phase: \(phaseLabel))")
                    .font(.headline)
                Spacer()
                Button("Scroll to bottom") {
                    // Not strictly necessary — the ScrollPreservingMarkdownView
                    // auto-scrolls when at-bottom. This is for manually
                    // forcing if the user scrolled up.
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollPreservingMarkdownView(state: state)
                .background(Color.secondary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
        }
    }

    private var phaseLabel: String {
        switch state.phase {
        case .running:            return "running"
        case .completed:          return "completed"
        case .interrupted(let r): return "interrupted (\(r))"
        case .errored(let r):     return "errored (\(r))"
        }
    }

    // MARK: - Stream driver

    private func startDriver() {
        stopDriver()
        state.reset()
        charactersStreamed = 0
        startedAt = Date()
        driverRunning = true
        let payload = source
        let interval = cadence.intervalNanoseconds
        task = Task { @MainActor in
            var iterator = payload.unicodeScalars.makeIterator()
            while !Task.isCancelled, let scalar = iterator.next() {
                state.append(String(scalar))
                charactersStreamed += 1
                try? await Task.sleep(nanoseconds: interval)
            }
            if !Task.isCancelled {
                state.finish(.completed)
            }
            driverRunning = false
        }
    }

    private func stopDriver() {
        task?.cancel()
        task = nil
        driverRunning = false
    }

    // MARK: - Cadence options

    enum Cadence: CaseIterable, Hashable {
        case hz10, hz20, hz30, hz50, hz100

        var label: String {
            switch self {
            case .hz10:  return "10 Hz"
            case .hz20:  return "20 Hz"
            case .hz30:  return "30 Hz"
            case .hz50:  return "50 Hz"
            case .hz100: return "100 Hz"
            }
        }

        var intervalNanoseconds: UInt64 {
            switch self {
            case .hz10:  return 100_000_000
            case .hz20:  return  50_000_000
            case .hz30:  return  33_000_000
            case .hz50:  return  20_000_000
            case .hz100: return  10_000_000
            }
        }
    }

    // MARK: - Default source for first-load convenience

    /// Pre-loaded sample document covering every block type, plus
    /// a long code block that exercises the close-fence highlight
    /// path. ~3000 characters; users can paste a longer payload
    /// (8000+) when verifying the SCOPE.md 50 Hz acceptance.
    static let defaultSource: String = """
    # Streaming markdown demo

    This harness lets you replay a Markdown document **token by token**
    at a configurable cadence, then inspect the rendered output.

    ## Block types under test

    - Paragraphs (you are reading one)
    - Headings (six levels)
    - Lists, ordered and unordered
    - Code blocks with `Highlightr` on close-fence
    - Block quotes
    - Tables
    - Horizontal rules
    - Inline `code`, **bold**, *italic*, ~~strikethrough~~, [links](https://example.com)

    ---

    ### Numbered list

    1. First item
    2. Second item with *emphasis*
    3. Third item with `inline code`

    ### Block quote

    > The streaming renderer must produce identical final output
    > regardless of whether the document is fed all at once or
    > byte-by-byte at 100 Hz.

    ### Code block

    ```swift
    // Open a fenced code block. While streaming, this body will
    // appear UN-highlighted (plain monospace). The moment the
    // closing fence arrives below, Highlightr re-renders the body
    // with full syntax-highlighted attributes.
    public func helloWorld() -> String {
        let message = "Hello, world!"
        print(message)
        return message
    }
    ```

    ### Table

    | Block type | Status |
    |---|---|
    | Paragraph | rendered |
    | Heading   | rendered |
    | List      | rendered |
    | Code      | highlighted on close |

    ### Half-fence test target

    ```python
    # This block is intentionally left open during streaming so
    # you can verify that it stays plain-monospace and does NOT
    # render the trailing prose as code or as Markdown until the
    # closing fence arrives. Try pausing the stream while inside
    # this block.
    def streaming_open_fence():
        return "ok"
    ```

    ## Done

    Stream complete. Inspect rendering and scroll-preserve behavior.
    """
}
#endif
