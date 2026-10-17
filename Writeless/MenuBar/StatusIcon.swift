import AppKit

/// The menu bar glyph, with a thin progress line under it while a file is
/// being transcribed.
///
/// `nonisolated`: the drawing handler of a composed `NSImage` may run on
/// whatever thread the image is drawn on, so it must not be a MainActor
/// closure, and it captures nothing but a symbol name and a number.
nonisolated enum StatusIcon {
    static func image(symbol: String, progress: Double?) -> NSImage? {
        guard let progress else {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Write Less")
            image?.isTemplate = true
            return image
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular, scale: .medium)
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            {
                // The glyph sits above the line, centred in what is left.
                let area = NSRect(x: 0, y: 4, width: rect.width, height: rect.height - 4)
                let scale = min(area.width / glyph.size.width, area.height / glyph.size.height, 1)
                let drawn = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
                let origin = NSPoint(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2)
                glyph.draw(in: NSRect(origin: origin, size: drawn))
            }

            // A template image is alpha only, so the two alphas become two
            // greys of whatever tint the menu bar uses.
            let track = NSRect(x: 1, y: 0.5, width: rect.width - 2, height: 1.5)
            NSColor.black.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: track, xRadius: 0.75, yRadius: 0.75).fill()
            let fraction = min(1, max(0, progress))
            if fraction > 0 {
                let fill = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: fill, xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Write Less"
        return image
    }
}
