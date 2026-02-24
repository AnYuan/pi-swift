import Foundation
import PiCoreTypes

public enum PiCodingAgentCLIExecutor {
    public static func execute(
        argv: [String],
        env: PiCodingAgentCLIEnvironment = .init(),
        modeRunner: PiCodingAgentModeRunner = .init()
    ) -> PiCodingAgentCLIResult {
        var result = PiCodingAgentCLIApp.run(argv: argv, env: env)
        guard result.exitCode == 0 else { return result }

        switch result.action {
        case .startPrint(let prompt, let pipedInput):
            result.stdout += modeRunner.runPrint(.init(prompt: prompt, pipedInput: pipedInput)) + "\n"
        case .startJSON(let prompt, let pipedInput):
            result.stdout += modeRunner.runJSON(.init(prompt: prompt, pipedInput: pipedInput)) + "\n"
        case .startRPC:
            if let request = env.pipedStdin?.trimmingCharacters(in: .whitespacesAndNewlines), !request.isEmpty {
                do {
                    result.stdout += try modeRunner.handleRPC(request) + "\n"
                } catch {
                    result.stdout += rpcInvalidRequestResponse(error: error) + "\n"
                }
            }
        case .showHelp, .showVersion, .startInteractive, .usageError:
            break
        }

        return result
    }

    private static func rpcInvalidRequestResponse(error: Error) -> String {
        let payload: [String: JSONValue] = [
            "id": .null,
            "error": .object([
                "code": .string("invalid_request"),
                "message": .string(String(describing: error)),
            ])
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
