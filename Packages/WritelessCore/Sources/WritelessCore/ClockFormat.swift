import Foundation

/// "0:07" — the elapsed time shown in the menu and the pill.
public enum ClockFormat {
    public static func elapsed(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.rounded(.down)))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

/// "312 of 627 MB" — the model download readout.
public enum ByteFormat {
    public static func progress(downloaded: Int64, total: Int64) -> String {
        let megabytes = { (bytes: Int64) in Int((Double(bytes) / 1_000_000).rounded()) }
        return "\(megabytes(min(downloaded, total))) of \(megabytes(total)) MB"
    }

    /// "2.1 GB", "627 MB" — a size on its own, for the model cache row.
    ///
    /// Decimal units, like `progress` and like the sizes the catalog quotes, and
    /// `String(format:)` so the separator is a dot whatever the locale says.
    /// The GB cutoff is on the *rounded* megabytes: comparing raw bytes instead
    /// prints 999_999_999 as "1000 MB", a four-digit megabyte count that appears
    /// nowhere else in the app.
    public static func size(_ bytes: Int64) -> String {
        let bytes = max(0, bytes)
        let megabytes = (Double(bytes) / 1_000_000).rounded()
        if megabytes >= 1000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        if megabytes < 1, bytes > 0 {
            return "\(max(1, Int((Double(bytes) / 1_000).rounded()))) KB"
        }
        return "\(Int(megabytes)) MB"
    }
}
