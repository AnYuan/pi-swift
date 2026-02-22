import PiAI
import PiAgentCore
import PiCoreTypes

public enum PiPodsModule {
    public static let moduleName = "PiPods"
    public static let dependencies = [
        PiCoreTypesModule.moduleName,
        PiAIModule.moduleName,
        PiAgentCoreModule.moduleName,
    ]
}
