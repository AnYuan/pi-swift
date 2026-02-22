import PiAI
import PiCoreTypes

public enum PiAgentCoreModule {
    public static let moduleName = "PiAgentCore"
    public static let dependencies = [PiCoreTypesModule.moduleName, PiAIModule.moduleName]
}
