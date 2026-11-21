import Foundation

/// The two test transports' shared reading of an HTTP `Range` request, like the hub's stream route.
enum RangeHeader {
    /// The bytes a `bytes=a-b` or `bytes=a-` value asks for, clamped to a file of `size`; nil when
    /// the value isn't one.
    static func range(_ value: String, size: Int) -> ClosedRange<Int>? {
        guard let m = value.firstMatch(of: /bytes=(\d+)-(\d*)/), let start = Int(m.1) else { return nil }
        return start...min(Int(m.2) ?? size - 1, size - 1)
    }

    /// The bytes a request with `value` (or none) is answered with from a file of `size`: the range
    /// asked for (a partial reply), else the whole file.
    static func served(_ value: String?, size: Int) -> (bytes: ClosedRange<Int>, partial: Bool) {
        if let asked = value.flatMap({ range($0, size: size) }) { return (asked, true) }
        return (0...(size - 1), false)
    }

    /// The `Content-Range` value answering `range` of a file of `size`.
    static func contentRange(_ range: ClosedRange<Int>, size: Int) -> String {
        "bytes \(range.lowerBound)-\(range.upperBound)/\(size)"
    }
}
