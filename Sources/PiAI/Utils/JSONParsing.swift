import Foundation
import PiCoreTypes

public enum PiAIJSON {
    public static func parseStreamingJSON(_ partialJSON: String?) -> JSONValue {
        guard let partialJSON, !partialJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .object([:])
        }

        if let parsed = parseExact(partialJSON) {
            return parsed
        }

        if let repaired = parseRepaired(partialJSON) {
            return repaired
        }

        return .object([:])
    }

    private static func parseExact(_ json: String) -> JSONValue? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return convertJSON(object)
    }

    private static func parseRepaired(_ json: String) -> JSONValue? {
        var candidate = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        for _ in 0..<64 {
            let repaired = appendMissingClosers(to: candidate)
            if let parsed = parseExact(repaired) {
                return parsed
            }
            guard !candidate.isEmpty else { break }
            candidate.removeLast()
        }
        return nil
    }

    private static func appendMissingClosers(to json: String) -> String {
        var stack: [Character] = []
        var inString = false
        var escaping = false

        for ch in json {
            if inString {
                if escaping {
                    escaping = false
                    continue
                }
                if ch == "\\" {
                    escaping = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }

            switch ch {
            case "\"":
                inString = true
            case "{":
                stack.append("}")
            case "[":
                stack.append("]")
            case "}":
                if stack.last == "}" { _ = stack.popLast() }
            case "]":
                if stack.last == "]" { _ = stack.popLast() }
            default:
                break
            }
        }

        var repaired = json
        if inString {
            repaired.append("\"")
        }

        while let closer = stack.popLast() {
            repaired.append(closer)
        }
        return repaired
    }

    private static func convertJSON(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull:
            return .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(value.map(convertJSON))
        case let value as [String: Any]:
            return .object(value.mapValues(convertJSON))
        default:
            return .null
        }
    }
}
