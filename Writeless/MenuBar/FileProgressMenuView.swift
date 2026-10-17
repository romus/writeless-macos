import AppKit
import WritelessCore

/// The block in the menu while a file is being transcribed: name, bar,
/// position and estimate. Plain AppKit, refreshed from the status item's
/// `refresh()`, which the 20 Hz tick already drives while the menu is open.
final class FileProgressMenuView: NSView {
    static let width: CGFloat = 232
    static let height: CGFloat = 58

    private let titleLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let positionLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        autoresizingMask = [.width]

        titleLabel.font = .systemFont(ofSize: 11.5)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small

        for label in [positionLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
        }
        remainingLabel.alignment = .right
        positionLabel.setContentHuggingPriority(.init(249), for: .horizontal)
        remainingLabel.setContentHuggingPriority(.init(251), for: .horizontal)

        let footer = NSStackView(views: [positionLabel, remainingLabel])
        footer.orientation = .horizontal
        footer.alignment = .firstBaseline
        footer.distribution = .fill

        let stack = NSStackView(views: [titleLabel, bar, footer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 5
        // Where an item's title starts, so the block lines up with the menu.
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FileProgressMenuView is built in code")
    }

    func update(_ progress: FileTranscriptionProgress, now: Date) {
        titleLabel.stringValue = progress.title
        bar.doubleValue = progress.fraction
        positionLabel.stringValue = progress.positionLabel ?? ""
        remainingLabel.stringValue = progress.remainingLabel(now: now) ?? ""
    }
}
