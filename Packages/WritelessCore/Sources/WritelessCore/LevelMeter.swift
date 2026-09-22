import Foundation

/// Maps microphone RMS onto the 0...1 bar heights the pill draws.
public enum LevelMeter {
    public static func normalized(
        rms: Float,
        floorDecibels: Float = -60,
        ceilingDecibels: Float = -12
    ) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        let normalized = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        return min(1, max(0, normalized))
    }

    /// How many of `count` segments the Settings meter lights, for a level that
    /// `normalized(rms:)` has already put on 0...1.
    public static func litSegments(level: Float, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let clamped = min(1, max(0, level))
        return Int((clamped * Float(count)).rounded())
    }
}

/// Fixed-length history of levels, newest last — one value per waveform bar.
public struct LevelHistory: Sendable, Equatable {
    public private(set) var values: [Float]

    public let capacity: Int

    public init(capacity: Int = 13) {
        self.capacity = max(1, capacity)
        self.values = Array(repeating: 0, count: self.capacity)
    }

    public mutating func push(_ level: Float) {
        values.removeFirst()
        values.append(min(1, max(0, level)))
    }

    public mutating func reset() {
        values = Array(repeating: 0, count: capacity)
    }
}
