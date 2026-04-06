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
        case let boolVal as Bool: storage = .bool(boolVal)
        case let intVal as Int: storage = .int(intVal)
        case let doubleVal as Double: storage = .double(doubleVal)
        case let stringVal as String: storage = .string(stringVal)
        case let arrayVal as [AnyCodable]: storage = .array(arrayVal)
        case let stringArray as [String]:
            storage = .array(stringArray.map { AnyCodable($0) })
        case let dictArray as [[String: AnyCodable]]:
            storage = .array(dictArray.map { AnyCodable($0) })
        case let dictVal as [String: AnyCodable]: storage = .dict(dictVal)
        case let dictVal as [String: String]:
            storage = .dict(dictVal.mapValues { AnyCodable($0) })
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
        if case let .dict(dictVal) = storage { return dictVal }
        return nil
    }

    var stringValue: String? {
        if case let .string(s) = storage { return s }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch storage {
        case .null: try container.encodeNil()
        case let .bool(val): try container.encode(val)
        case let .int(val): try container.encode(val)
        case let .double(val): try container.encode(val)
        case let .string(val): try container.encode(val)
        case let .array(val): try container.encode(val)
        case let .dict(val): try container.encode(val)
        }
    }
}
