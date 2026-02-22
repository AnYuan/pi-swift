import PiAI
import PiAgentCore
import PiCoreTypes
import PiTUI

public enum PiCodingAgentModule {
    public static let moduleName = "PiCodingAgent"
    public static let dependencies = [
        PiCoreTypesModule.moduleName,
        PiAIModule.moduleName,
        PiAgentCoreModule.moduleName,
        PiTUIModule.moduleName,
    ]

    public static func bootMessage() -> String {
        "\(moduleName) skeleton initialized"
    }
}
