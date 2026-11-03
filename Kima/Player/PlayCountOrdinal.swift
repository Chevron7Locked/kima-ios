import Foundation

enum PlayCountOrdinal {
    /// 1 -> "1st", 2 -> "2nd", 11 -> "11th", 21 -> "21st" (port of the web's `ordinal`).
    static func string(_ n: Int) -> String {
        let lastTwo = n % 100
        if (11...13).contains(lastTwo) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
