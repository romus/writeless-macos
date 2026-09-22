import SwiftUI
import WritelessCore

/// Recording indicator: a red dot, a live waveform and the elapsed time.
struct PillView: View {
    let state: AppState

    private let barCount = 13

    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
            .animation(.easeOut(duration: 0.18), value: state.phase)
            .animation(.easeOut(duration: 0.18), value: state.notice)
    }

    @ViewBuilder
    private var content: some View {
        if let notice = state.notice {
            HStack(spacing: 10) {
                Image(systemName: notice.symbolName)
                    .foregroundStyle(.secondary)
                Text(notice.text)
                    .font(.system(size: 13))
            }
        } else if state.phase == .transcribing {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                dot
                waveform
                Text(ClockFormat.elapsed(state.elapsedSeconds))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Red and pulsing once audio flows; grey until then, because starting the
    /// engine can take a moment, especially on Bluetooth. The pulse is a
    /// function of the elapsed time rather than an animation, so it stays in
    /// step with the dot in the menu header.
    private var dot: some View {
        let indicator = state.indicator
        return Circle()
            .fill(indicator.dotColor.map(Color.init(nsColor:)) ?? Color.secondary.opacity(0.5))
            .frame(width: 8, height: 8)
            .opacity(indicator.pulses ? StatusIndicator.pulseOpacity(at: state.elapsedSeconds) : 1)
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(state.levels.values.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: 3, height: 3 + CGFloat(level) * 17)
            }
        }
        .frame(width: CGFloat(barCount) * 5 - 2, height: 20)
        .animation(.linear(duration: 0.06), value: state.levels)
    }
}
