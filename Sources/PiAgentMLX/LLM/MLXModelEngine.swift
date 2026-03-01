import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import PiCoreTypes

@globalActor
public actor MLXModelEngineActor {
    public static let shared = MLXModelEngineActor()
}

@MLXModelEngineActor
public class MLXModelEngine {
    private var modelContainer: ModelContainer?
    private var isLoaded: Bool = false
    private var loadedModelId: String?
    
    public init() {}
    
    public func load(modelId: String) async throws {
        // Skip reload if the same model is already loaded
        if isLoaded, loadedModelId == modelId, modelContainer != nil {
            return
        }
        
        let resolvedPath = (modelId as NSString).expandingTildeInPath
        let modelConfiguration: ModelConfiguration
        
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory), isDirectory.boolValue {
            modelConfiguration = ModelConfiguration(directory: URL(fileURLWithPath: resolvedPath))
        } else {
            modelConfiguration = ModelConfiguration(id: modelId)
        }
        
        let container = try await MLXLMCommon.loadModelContainer(configuration: modelConfiguration)
        self.modelContainer = container
        self.isLoaded = true
        self.loadedModelId = modelId
    }
    
    public func unload() {
        self.modelContainer = nil
        self.isLoaded = false
    }
    
    public func generateStream(
        prompt: String,
        maxTokens: Int = 4096,
        temperature: Float = 0.7
    ) async throws -> AsyncStream<Generation> {
        guard let container = modelContainer else {
            throw MLXLocalError.modelNotLoaded
        }
        
        let parameters = GenerateParameters(
            temperature: temperature
        )
        // parameters.maxTokens is a let or var? In older versions, it might be mutable.
        // Actually we can pass maxTokens in the GenerateParameters init if available, or just use a local var inside the closure.
        
        return try await container.perform { context in
            var localParams = parameters
            localParams.maxTokens = maxTokens
            let tokenInput = try await context.processor.prepare(input: UserInput(prompt: prompt))
            return try await generate(
                input: tokenInput,
                parameters: localParams,
                context: context
            )
        }
    }
}

public enum MLXLocalError: Error, LocalizedError {
    case modelNotLoaded
    
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX Model is not loaded into memory."
        }
    }
}
