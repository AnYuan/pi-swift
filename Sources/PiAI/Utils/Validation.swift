import Foundation
import PiCoreTypes

public enum PiAIValidation {
    public static func validateToolCall(tools: [PiAITool], toolCall: PiAIToolCallContent) throws -> [String: JSONValue] {
        guard let tool = tools.first(where: { $0.name == toolCall.name }) else {
            throw PiAIValidationError("Tool \"\(toolCall.name)\" not found")
        }
        return try validateToolArguments(tool: tool, toolCall: toolCall)
    }

    public static func validateToolArguments(tool: PiAITool, toolCall: PiAIToolCallContent) throws -> [String: JSONValue] {
        guard case .object(let object) = JSONValue.object(toolCall.arguments) else {
            throw PiAIValidationError("Validation failed for tool \"\(toolCall.name)\": root arguments must be an object")
        }
        try validate(value: .object(object), schema: tool.parameters, path: "root")
        return object
    }

    private static func validate(value: JSONValue, schema: PiToolParameterSchema, path: String) throws {
        switch schema.type {
        case .object:
            guard case .object(let object) = value else {
                throw PiAIValidationError("Validation failed: \(path) must be object")
            }
            let props = schema.properties ?? [:]
            let required = Set(schema.required ?? [])
            for name in required where object[name] == nil {
                throw PiAIValidationError("Validation failed: missing required property \(propertyPath(path, name))")
            }
            if schema.additionalProperties == false {
                let allowed = Set(props.keys)
                if let unexpected = object.keys.first(where: { !allowed.contains($0) }) {
                    throw PiAIValidationError("Validation failed: unexpected property \(propertyPath(path, unexpected))")
                }
            }
            for (name, nestedSchema) in props {
                guard let nestedValue = object[name] else { continue }
                try validate(value: nestedValue, schema: nestedSchema, path: path == "root" ? name : "\(path).\(name)")
            }

        case .array:
            guard case .array(let array) = value else {
                throw PiAIValidationError("Validation failed: \(path) must be array")
            }
            if let itemSchema = schema.items {
                for (index, element) in array.enumerated() {
                    try validate(value: element, schema: itemSchema, path: "\(path)[\(index)]")
                }
            }

        case .string:
            guard case .string(let stringValue) = value else {
                throw PiAIValidationError("Validation failed: \(path) must be string")
            }
            if let enumValues = schema.enumValues, !enumValues.contains(stringValue) {
                throw PiAIValidationError("Validation failed: \(path) must be one of \(enumValues.joined(separator: ", "))")
            }

        case .number:
            guard case .number = value else {
                throw PiAIValidationError("Validation failed: \(path) must be number")
            }

        case .integer:
            guard case .number(let number) = value else {
                throw PiAIValidationError("Validation failed: \(path) must be integer")
            }
            if !number.isFinite || number.rounded(.towardZero) != number {
                throw PiAIValidationError("Validation failed: \(path) must be integer")
            }

        case .boolean:
            guard case .bool = value else {
                throw PiAIValidationError("Validation failed: \(path) must be boolean")
            }

        case .null:
            guard case .null = value else {
                throw PiAIValidationError("Validation failed: \(path) must be null")
            }
        }
    }

    private static func propertyPath(_ base: String, _ key: String) -> String {
        base == "root" ? key : "\(base).\(key)"
    }
}

public struct PiAIValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}
