import SwiftUI
import WritelessCore

/// The six-line "page" beside the Paragraphs switch, from the design: one
/// block when off, three blocks when on, dimmed when the switch cannot be
/// used, and a light running down the lines while Apple Intelligence is still
/// downloading. The frame never changes, so the switch never moves.
struct ParagraphGlyph: View {
    let isOn: Bool
    let availability: ParagraphsAvailability

    private static let width: CGFloat = 26
    private static let height: CGFloat = 24
    private static let lineWidths: [CGFloat] = [1, 0.88, 1, 0.7, 1, 0.56]
    /// Lines that start a new "paragraph" when the switch is on.
    private static let breaks: Set<Int> = [2, 4]
    private static let scanStep: TimeInterval = 0.16
    private static let scanPeriod = 9

    var body: some View {
        if availability == .downloading {
            TimelineView(.periodic(from: .now, by: Self.scanStep)) { context in
                lines(scan: Int(context.date.timeIntervalSinceReferenceDate / Self.scanStep) % Self.scanPeriod)
            }
        } else {
            lines(scan: nil)
        }
    }

    private func lines(scan: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.lineWidths.indices, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: Self.width * Self.lineWidths[index], height: 2)
                    .opacity(opacity(line: index, scan: scan))
                    .padding(.top, gap(before: index))
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityHidden(true)
    }

    private func gap(before index: Int) -> CGFloat {
        if index == 0 { return 0 }
        return isOn && availability == .available && Self.breaks.contains(index) ? 4 : 2
    }

    private func opacity(line: Int, scan: Int?) -> Double {
        switch availability {
        case .available:
            0.5
        case .turnedOff, .unsupported:
            0.22
        case .downloading:
            if let scan, abs(line - scan + 1) < 2 { 0.6 } else { 0.16 }
        }
    }
}
