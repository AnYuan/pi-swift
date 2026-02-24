import Foundation
import PiAI
import PiTUI

public enum PiCodingAgentInteractiveOverlay: String, Codable, Equatable, Sendable {
    case none
    case settings
    case modelSelector
}

public struct PiCodingAgentInteractiveSnapshot: Equatable, Sendable {
    public var overlay: PiCodingAgentInteractiveOverlay
    public var currentModelQualifiedID: String?
    public var submittedPrompts: [String]
    public var editorText: String

    public init(
        overlay: PiCodingAgentInteractiveOverlay,
        currentModelQualifiedID: String?,
        submittedPrompts: [String],
        editorText: String
    ) {
        self.overlay = overlay
        self.currentModelQualifiedID = currentModelQualifiedID
        self.submittedPrompts = submittedPrompts
        self.editorText = editorText
    }
}

public final class PiCodingAgentInteractiveMode {
    private let settings: PiCodingAgentSettingsManager
    private let modelRegistry: PiCodingAgentModelRegistry
    private let editor = PiTUIEditorComponent()

    private var overlay: PiCodingAgentInteractiveOverlay = .none
    private var statusMessage: String = "Ready"
    private var submittedPrompts: [String] = []
    private var currentModel: PiAIModel?
    private var modelSelectorItems: [PiAIModel] = []
    private var modelSelectorIndex: Int = 0

    public init(
        settings: PiCodingAgentSettingsManager,
        modelRegistry: PiCodingAgentModelRegistry
    ) {
        self.settings = settings
        self.modelRegistry = modelRegistry
        self.currentModel = PiCodingAgentModelResolver.findInitialModel(settings: settings, registry: modelRegistry)

        editor.onSubmit = { [weak self] text in
            self?.submit(text: text)
        }
        editor.onEscape = { [weak self] in
            self?.handleKeyID("escape")
        }
    }

    public func snapshot() -> PiCodingAgentInteractiveSnapshot {
        .init(
            overlay: overlay,
            currentModelQualifiedID: currentModel?.qualifiedID,
            submittedPrompts: submittedPrompts,
            editorText: editor.getText()
        )
    }

    public func setDraftText(_ text: String) {
        editor.setText(text)
    }

    public func handleTextInput(_ data: String) {
        guard overlay == .none else { return }
        editor.handleInput(data)
    }

    public func handleInput(_ data: String) {
        if let keyID = PiTUIKeys.parseKey(data) {
            switch keyID {
            case "ctrl+s":
                handleKeyID("f2")
                return
            case "ctrl+m":
                handleKeyID("f3")
                return
            case "up", "down", "left", "right", "enter", "escape", "tab", "backspace":
                handleKeyID(keyID)
                return
            default:
                break
            }
        }
        guard overlay == .none else { return }
        editor.handleInput(data)
    }

    public func handleKeyID(_ keyID: String) {
        let normalized = keyID.lowercased()

        switch overlay {
        case .settings:
            if normalized == "escape" || normalized == "f2" {
                overlay = .none
                statusMessage = "Closed settings"
            }
            return
        case .modelSelector:
            handleModelSelectorKey(normalized)
            return
        case .none:
            break
        }

        switch normalized {
        case "f2":
            overlay = .settings
            statusMessage = "Opened settings"
        case "f3":
            openModelSelector()
        case "enter":
            editor.handleInput("\r")
        case "escape":
            statusMessage = "Ready"
        default:
            break
        }
    }

    public func render(width: Int) -> [String] {
        let width = max(1, width)
        var lines: [String] = []

        lines.append(contentsOf: transcriptLines(width: width))
        lines.append(statusBarLine(width: width))
        lines.append(contentsOf: editor.render(width: width))

        switch overlay {
        case .none:
            break
        case .settings:
            lines.append(contentsOf: renderSettingsOverlay(width: width))
        case .modelSelector:
            lines.append(contentsOf: renderModelSelectorOverlay(width: width))
        }

        return lines.map { PiTUIANSIText.truncateToVisibleWidth($0, maxWidth: width) }
    }

    private func transcriptLines(width: Int) -> [String] {
        guard !submittedPrompts.isEmpty else { return [] }
        let recent = submittedPrompts.suffix(3)
        return recent.enumerated().map { _, prompt in
            PiTUIANSIText.truncateToVisibleWidth("Submitted prompt: \(prompt)", maxWidth: width)
        }
    }

    private func statusBarLine(width: Int) -> String {
        let modelText = currentModel?.qualifiedID ?? "none"
        let overlayText = overlay == .none ? "" : " | Overlay: \(overlay.rawValue)"
        let text = "Model: \(modelText) | F2 Settings | F3 Models | Enter Submit\(overlayText) | \(statusMessage)"
        return PiTUIANSIText.truncateToVisibleWidth(text, maxWidth: width)
    }

    private func renderSettingsOverlay(width: Int) -> [String] {
        let theme = settings.getTheme() ?? "(default)"
        let provider = settings.getDefaultProvider() ?? "(auto)"
        let model = settings.getDefaultModel() ?? "(auto)"
        return [
            "Settings",
            "  theme: \(theme)",
            "  defaultProvider: \(provider)",
            "  defaultModel: \(model)",
            "  Esc/F2 to close",
        ].map { PiTUIANSIText.truncateToVisibleWidth($0, maxWidth: width) }
    }

    private func renderModelSelectorOverlay(width: Int) -> [String] {
        var lines = ["Model Selector"]
        if modelSelectorItems.isEmpty {
            lines.append("  No models available")
            return lines.map { PiTUIANSIText.truncateToVisibleWidth($0, maxWidth: width) }
        }

        let maxVisible = 6
        let start = max(0, min(modelSelectorIndex - maxVisible / 2, max(0, modelSelectorItems.count - maxVisible)))
        let end = min(modelSelectorItems.count, start + maxVisible)
        for index in start..<end {
            let item = modelSelectorItems[index]
            let prefix = index == modelSelectorIndex ? "→ " : "  "
            lines.append(prefix + item.qualifiedID)
        }
        lines.append("  Enter select · Esc cancel")
        return lines.map { PiTUIANSIText.truncateToVisibleWidth($0, maxWidth: width) }
    }

    private func handleModelSelectorKey(_ keyID: String) {
        guard !modelSelectorItems.isEmpty else {
            if keyID == "escape" || keyID == "f3" { overlay = .none }
            return
        }

        switch keyID {
        case "up":
            modelSelectorIndex = modelSelectorIndex == 0 ? modelSelectorItems.count - 1 : modelSelectorIndex - 1
        case "down":
            modelSelectorIndex = modelSelectorIndex == modelSelectorItems.count - 1 ? 0 : modelSelectorIndex + 1
        case "enter":
            let selected = modelSelectorItems[modelSelectorIndex]
            currentModel = selected
            settings.setDefaultProvider(selected.provider)
            settings.setDefaultModel(selected.id)
            overlay = .none
            statusMessage = "Selected model \(selected.qualifiedID)"
        case "escape", "f3":
            overlay = .none
            statusMessage = "Closed model selector"
        default:
            break
        }
    }

    private func openModelSelector() {
        modelSelectorItems = modelRegistry.getAvailable()
        if modelSelectorItems.isEmpty {
            modelSelectorItems = modelRegistry.getAll()
        }
        modelSelectorItems.sort { $0.qualifiedID.localizedCaseInsensitiveCompare($1.qualifiedID) == .orderedAscending }
        if let currentModel,
           let idx = modelSelectorItems.firstIndex(where: { $0.qualifiedID == currentModel.qualifiedID }) {
            modelSelectorIndex = idx
        } else {
            modelSelectorIndex = 0
        }
        overlay = .modelSelector
        statusMessage = "Select a model"
    }

    private func submit(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Empty prompt ignored"
            return
        }
        submittedPrompts.append(trimmed)
        editor.setText("")
        editor.addToHistory(trimmed)
        statusMessage = "Submitted prompt"
    }
}
