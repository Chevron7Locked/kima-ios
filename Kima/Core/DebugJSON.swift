#if DEBUG
import Foundation

/// DEBUG: any JSON value, so a server row can be saved as it came and compared later (DebugServerState).
enum DebugJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DebugJSON])
    case object([String: DebugJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([DebugJSON].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: DebugJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    subscript(key: String) -> DebugJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var array: [DebugJSON]? { if case .array(let value) = self { return value }; return nil }

    /// The same object without `key`; other values are returned as they are.
    func removing(_ key: String) -> DebugJSON {
        guard case .object(var fields) = self else { return self }
        fields[key] = nil
        return .object(fields)
    }
}
#endif
