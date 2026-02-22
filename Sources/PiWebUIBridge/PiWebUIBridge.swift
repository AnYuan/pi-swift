import PiAI
import PiAgentCore
import PiCoreTypes

public enum PiWebUIBridgeModule {
    public static let moduleName = "PiWebUIBridge"
    public static let dependencies = [
        PiCoreTypesModule.moduleName,
        PiAIModule.moduleName,
        PiAgentCoreModule.moduleName,
    ]
}
