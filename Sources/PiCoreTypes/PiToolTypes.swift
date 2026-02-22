import Foundation

public enum PiSchemaType: String, Codable, Sendable {
    case object
    case array
    case string
    case number
    case integer
    case boolean
    case null
}

public final class PiToolParameterSchema: Codable, Equatable, Sendable {
    public let type: PiSchemaType
    public let description: String?
    public let properties: [String: PiToolParameterSchema]?
    public let required: [String]?
    public let items: PiToolParameterSchema?
    public let enumValues: [String]?
    public let additionalProperties: Bool?

    public init(
        type: PiSchemaType,
        description: String? = nil,
        properties: [String: PiToolParameterSchema]? = nil,
        required: [String]? = nil,
        items: PiToolParameterSchema? = nil,
        enumValues: [String]? = nil,
        additionalProperties: Bool? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items
        self.enumValues = enumValues
        self.additionalProperties = additionalProperties
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case required
        case items
        case enumValues = "enum"
        case additionalProperties
    }

    public static func == (lhs: PiToolParameterSchema, rhs: PiToolParameterSchema) -> Bool {
        lhs.type == rhs.type &&
            lhs.description == rhs.description &&
            lhs.properties == rhs.properties &&
            lhs.required == rhs.required &&
            lhs.items == rhs.items &&
            lhs.enumValues == rhs.enumValues &&
            lhs.additionalProperties == rhs.additionalProperties
    }
}

public struct PiToolDefinition: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: PiToolParameterSchema

    public init(name: String, description: String, parameters: PiToolParameterSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct PiToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct PiToolResult: Codable, Equatable, Sendable {
    public var toolCallID: String
    public var content: JSONValue
    public var isError: Bool

    public init(toolCallID: String, content: JSONValue, isError: Bool = false) {
        self.toolCallID = toolCallID
        self.content = content
        self.isError = isError
    }
}
