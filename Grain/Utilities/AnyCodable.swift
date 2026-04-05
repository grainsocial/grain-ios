import Foundation

/// Type-erased Codable wrapper for AT Protocol's "unknown" typed fields.
struct AnyCodable: Codable, Sendable {
    private enum Storage: Sendable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case dict([String: AnyCodable])
    }

    private let storage: Storage

    init(_ value: some Sendable) {
        switch value {
        case let b as Bool: storage = .bool(b)
        case let i as Int: storage = .int(i)
        case let d as Double: storage = .double(d)
        case let s as String: storage = .string(s)
        case let a as [AnyCodable]: storage = .array(a)
        case let d as [String: AnyCodable]: storage = .dict(d)
        case let d as [String: String]:
            storage = .dict(d.mapValues { AnyCodable($0) })
        default: storage = .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            storage = .null
        } else if let bool = try? container.decode(Bool.self) {
            storage = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            storage = .int(int)
        } else if let double = try? container.decode(Double.self) {
            storage = .double(double)
        } else if let string = try? container.decode(String.self) {
            storage = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            storage = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            storage = .dict(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    var dictValue: [String: AnyCodable]? {
        if case let .dict(d) = storage { return d }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch storage {
        case .null: try container.encodeNil()
        case let .bool(v): try container.encode(v)
        case let .int(v): try container.encode(v)
        case let .double(v): try container.encode(v)
        case let .string(v): try container.encode(v)
        case let .array(v): try container.encode(v)
        case let .dict(v): try container.encode(v)
        }
    }
}
