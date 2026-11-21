import Foundation

extension URLRequest {
    /// Asks for `bytes` of the resource only (an HTTP `Range` header; the upper bound is exclusive).
    mutating func setByteRange(_ bytes: Range<Int>) {
        setValue("bytes=\(bytes.lowerBound)-\(bytes.upperBound - 1)", forHTTPHeaderField: "Range")
    }
}
