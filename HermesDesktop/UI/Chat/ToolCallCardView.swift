import SwiftUI

/// Inline tool-call card rendered within an assistant message stream.
/// WU3.4 deliverable per Phase 3 SCOPE.md.
///
/// **Visual contract** (matches WU3.1 Finding 5 "Cursor / Claude /
/// ChatGPT" convergent pattern): a single horizontal row with
/// icon + tool name + status badge + live elapsed time, default
/// collapsed. Click toggles an expanded body showing the preview
/// (file path / command / etc) and any error message. Errored
/// calls auto-expand on arrival so the user sees the failure
/// without an extra click.
///
/// **Four states**, all rendered today (Decision #17 honor):
/// - `.running`           — animated icon, ticking elapsed timer,
///                          neutral/info badge
/// - `.completed`         — checkmark icon, frozen duration, success
///                          badge (or danger if `hadError`)
/// - `.interrupted`       — slash-through icon, distinct warning
///                          treatment ("stopped before finishing")
/// - `.alreadyExecuted`   — checkmark-shield icon, "executed
///                          before stop arrived" treatment to honor
///                          Decision #17's UI-must-not-lie rule
///
/// **Field set strictly bounded** to what `/v1/runs/{id}/events`
/// actually delivers per WU3.1 byte-level evidence:
/// `toolName`, `preview` (from `tool.started`), `durationSeconds`,
/// `hadError` (from `tool.completed`). No speculative fields.
public struct ToolCallCardView: View {

    public let call: InlineToolCall
    @State private var isExpanded: Bool = false
    @State private var now: Date = Date()

    public init(call: InlineToolCall) {
        self.call = call
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            if isExpanded {
                detailBody
                    .padding(.top, HermesSpacing.xs)
                    .padding(.leading, 26)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(HermesSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .fill(HermesColors.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        .onAppear {
            if call.hadError || isAutoExpandStatus {
                isExpanded = true
            }
            if call.status == .running {
                startTicking()
            }
        }
        .onChange(of: call.status) { newStatus in
            if newStatus != .running { stopTicking() }
            if (call.hadError && !isExpanded) || (isAutoExpandStatus && !isExpanded) {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded = true }
            }
        }
        .accessibilityIdentifier("toolCard.\(call.toolName).\(call.status.rawValue)")
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: HermesSpacing.sm) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(call.toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HermesColors.text)
                if let preview = call.preview, !preview.isEmpty, !isExpanded {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: HermesSpacing.sm)
            elapsedReadout
            StatusBadge(call.status.displayName, tone: badgeTone)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HermesColors.muted)
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            if let preview = call.preview, !preview.isEmpty {
                Text(preview)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.text)
                    .textSelection(.enabled)
                    .padding(HermesSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HermesColors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            }
            if call.hadError {
                HStack(spacing: HermesSpacing.xs) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(HermesColors.danger)
                    Text("Tool reported an error.")
                        .font(.system(size: 12))
                        .foregroundStyle(HermesColors.text)
                }
            }
            if call.status == .interrupted {
                HStack(spacing: HermesSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HermesColors.warning)
                    Text("Stopped before finishing — server may still be cleaning up.")
                        .font(.system(size: 12))
                        .foregroundStyle(HermesColors.text)
                }
            }
            if call.status == .alreadyExecuted {
                HStack(spacing: HermesSpacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(HermesColors.info)
                    Text("Already executed before stop arrived.")
                        .font(.system(size: 12))
                        .foregroundStyle(HermesColors.text)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch call.status {
        case .running:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HermesColors.info)
                .symbolEffect(.pulse, options: .repeating, value: now)
        case .completed:
            Image(systemName: call.hadError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(call.hadError ? HermesColors.danger : HermesColors.success)
        case .interrupted:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HermesColors.warning)
        case .alreadyExecuted:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HermesColors.info)
        }
    }

    private var elapsedReadout: some View {
        Text(formatElapsed(call.elapsedSeconds(at: now)))
            .font(HermesTypography.mono.monospacedDigit())
            .foregroundStyle(HermesColors.muted)
            .accessibilityIdentifier("toolCard.elapsed")
    }

    // MARK: - Status mapping

    private var badgeTone: HermesStatusTone {
        switch call.status {
        case .running:           return .info
        case .completed:         return call.hadError ? .danger : .success
        case .interrupted:       return .warning
        case .alreadyExecuted:   return .info
        }
    }

    private var borderColor: Color {
        switch call.status {
        case .running:           return HermesColors.info.opacity(0.4)
        case .completed:         return call.hadError ? HermesColors.danger.opacity(0.5) : HermesColors.border
        case .interrupted:       return HermesColors.warning.opacity(0.5)
        case .alreadyExecuted:   return HermesColors.info.opacity(0.5)
        }
    }

    private var isAutoExpandStatus: Bool {
        // Errors always auto-expand; interrupted and alreadyExecuted
        // do too, since both are surprising and the user needs the
        // disambiguating context (per Decision #17).
        call.hadError ||
        call.status == .interrupted ||
        call.status == .alreadyExecuted
    }

    // MARK: - Live-ticking elapsed timer

    private func startTicking() {
        // 100 ms cadence is comfortable for human-perception elapsed
        // readouts and 10× cheaper than 16 ms (60 Hz). One Task per
        // running card; auto-cancels when the view goes away.
        Task { @MainActor in
            while call.status == .running {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { break }
                now = Date()
            }
        }
    }

    private func stopTicking() {
        // The Task above checks `call.status` and exits naturally; we
        // poke `now` once more so the final frozen value reflects the
        // completion instant.
        now = Date()
    }

    private func formatElapsed(_ seconds: Double) -> String {
        if seconds < 1.0 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m\(secs)s"
        }
    }
}
