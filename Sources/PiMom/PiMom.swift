import PiAI
import PiAgentCore
import PiCodingAgent
import PiCoreTypes

public enum PiMomModule {
    public static let moduleName = "PiMom"
    public static let dependencies = [
        PiCoreTypesModule.moduleName,
        PiAIModule.moduleName,
        PiAgentCoreModule.moduleName,
        PiCodingAgentModule.moduleName,
    ]
}
