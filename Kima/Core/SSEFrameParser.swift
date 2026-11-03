import Foundation

/// Server-sent-events framing, byte by byte: lines end at "\n" (a trailing "\r" is dropped) and a blank line
/// ends an event. Byte-level on purpose — `URLSession.AsyncBytes.lines` drops empty lines, so it never
/// sees the separator.
struct SSEFrameParser {
    struct Event: Equatable { let name: String; let data: String }

    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventName = "message"

    /// Feed one byte; returns an event when this byte completes one.
    mutating func feed(_ byte: UInt8) -> Event? {
        guard byte == 0x0A else { lineBuffer.append(byte); return nil }
        if lineBuffer.last == 0x0D { lineBuffer.removeLast() }
        let line = String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll(keepingCapacity: true)
        return feed(line: line)
    }

    /// Feed one line (no terminator).
    mutating func feed(line: String) -> Event? {
        if line.isEmpty {
            let event = dataLines.isEmpty ? nil : Event(name: eventName, data: dataLines.joined(separator: "\n"))
            dataLines = []
            eventName = "message"
            return event
        }
        if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        } else if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        return nil   // ":" heartbeats and unknown fields are ignored
    }
}
