import SwiftUI
import WritelessCore

/// The sixteen-segment input meter from the design: lit segments stand up and
/// turn green, the rest stay as dots. It is the one place that says out loud
/// whether the chosen microphone is actually hearing anything.
struct InputLevelMeter: View {
    /// Read here rather than handed in, so a level arriving twenty times a
    /// second invalidates these sixteen rectangles and nothing else.
    let state: AppState

    private static let segments = 16

    var body: some View {
        let lit = LevelMeter.litSegments(level: state.inputLevel, count: Self.segments)
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < lit ? Color(nsColor: .systemGreen) : Color.primary.opacity(0.17))
                    .frame(width: 3, height: index < lit ? 9 : 3)
            }
        }
        .frame(height: 9)
        .animation(.easeOut(duration: 0.12), value: lit)
        .accessibilityHidden(true)
    }
}
