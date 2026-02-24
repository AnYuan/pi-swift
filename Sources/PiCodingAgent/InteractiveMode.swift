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

public final class PiCodingAgentInteractiveMode: PiTUIComponent {
    private let settings: PiCodingAgentSettingsManager
    private let modelRegistry: PiCodingAgentModelRegistry
    private let editor = PiTUIEditorComponent()
    private var settingsList: PiTUISettingsList?
    private var modelSelectorList: PiTUISelectList?

    private var overlay: PiCodingAgentInteractiveOverlay = .none
    private var statusMessage: String = "Ready"
    private var submittedPrompts: [String] = []
    private var currentModel: PiAIModel?
    private var modelSelectorItemsByValue: [String: PiAIModel] = [:]

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
        if overlay == .settings {
            if let keyID = PiTUIKeys.parseKey(data), keyID == "f2" {
                handleKeyID("f2")
                return
            }
            settingsList?.handleInput(data)
            return
        }
        if overlay == .modelSelector {
            if let keyID = PiTUIKeys.parseKey(data), keyID == "f3" {
                handleKeyID("f3")
                return
            }
            modelSelectorList?.handleInput(data)
            return
        }

        if let keyID = PiTUIKeys.parseKey(data) {
            switch keyID {
            case "ctrl+s":
                handleKeyID("f2")
                return
            case "ctrl+p":
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
            if let raw = rawInput(forKeyID: normalized) {
                settingsList?.handleInput(raw)
            } else if normalized == "f2" {
                overlay = .none
                statusMessage = "Closed settings"
            }
            return
        case .modelSelector:
            if let raw = rawInput(forKeyID: normalized) {
                modelSelectorList?.handleInput(raw)
            } else if normalized == "f3" {
                overlay = .none
                statusMessage = "Closed model selector"
            }
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

    public func invalidate() {}

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
        ensureSettingsList()
        var lines = ["Settings"]
        lines.append(contentsOf: settingsList?.render(width: width) ?? ["  No settings available"])
        return lines.map { PiTUIANSIText.truncateToVisibleWidth($0, maxWidth: width) }
    }

    private func renderModelSelectorOverlay(width: Int) -> [String] {
        var lines = ["Model Selector"]
        lines.append(contentsOf: modelSelectorList?.render(width: width) ?? ["  No models available"])
        return lines.map { PiTUIANSIText.truncateToVisibleWidth($0, maxWidth: width) }
    }

    private func openModelSelector() {
        var models = modelRegistry.getAvailable()
        if models.isEmpty { models = modelRegistry.getAll() }
        models.sort { $0.qualifiedID.localizedCaseInsensitiveCompare($1.qualifiedID) == .orderedAscending }
        modelSelectorItemsByValue = Dictionary(uniqueKeysWithValues: models.map { ($0.qualifiedID, $0) })

        let list = PiTUISelectList(
            items: models.map { .init(value: $0.qualifiedID, label: $0.qualifiedID) },
            maxVisible: 8
        )
        if let currentModel,
           let idx = models.firstIndex(where: { $0.qualifiedID == currentModel.qualifiedID }) {
            list.setSelectedIndex(idx)
        }
        list.onSelect = { [weak self] item in
            guard let self, let selected = self.modelSelectorItemsByValue[item.value] else { return }
            self.currentModel = selected
            self.settings.setDefaultProvider(selected.provider)
            self.settings.setDefaultModel(selected.id)
            self.overlay = .none
            self.statusMessage = "Selected model \(selected.qualifiedID)"
        }
        list.onCancel = { [weak self] in
            self?.overlay = .none
            self?.statusMessage = "Closed model selector"
        }
        modelSelectorList = list
        overlay = .modelSelector
        statusMessage = "Select a model"
    }

    private func ensureSettingsList() {
        guard settingsList == nil else {
            refreshSettingsListItems()
            return
        }
        let list = PiTUISettingsList(
            items: makeSettingsItems(),
            maxVisible: 8,
            options: .init(enableSearch: false)
        )
        list.onChange = { [weak self] id, value in
            guard let self else { return }
            self.applySettingChange(id: id, value: value)
            self.statusMessage = "Updated \(id) = \(value)"
            self.refreshSettingsListItems()
        }
        list.onCancel = { [weak self] in
            self?.overlay = .none
            self?.statusMessage = "Closed settings"
        }
        settingsList = list
    }

    private func refreshSettingsListItems() {
        settingsList?.setItems(makeSettingsItems())
    }

    private func makeSettingsItems() -> [PiTUISettingItem] {
        [
            .init(
                id: "theme",
                label: "theme",
                description: "Color theme for interactive TUI rendering",
                currentValue: settings.getTheme() ?? "dark",
                values: ["dark", "light"]
            ),
            .init(
                id: "defaultThinkingLevel",
                label: "defaultThinkingLevel",
                description: "Default reasoning level for interactive prompts",
                currentValue: settings.getDefaultThinkingLevel() ?? "medium",
                values: PiCodingAgentThinkingLevel.allCases.map(\.rawValue)
            ),
            .init(
                id: "defaultProvider",
                label: "defaultProvider",
                description: "Provider used for initial model selection",
                currentValue: settings.getDefaultProvider() ?? "(auto)"
            ),
            .init(
                id: "defaultModel",
                label: "defaultModel",
                description: "Model used for initial session state",
                currentValue: settings.getDefaultModel() ?? "(auto)"
            ),
        ]
    }

    private func applySettingChange(id: String, value: String) {
        switch id {
        case "theme":
            settings.setTheme(value)
        case "defaultThinkingLevel":
            settings.setDefaultThinkingLevel(value)
        case "defaultProvider":
            settings.setDefaultProvider(value == "(auto)" ? nil : value)
        case "defaultModel":
            settings.setDefaultModel(value == "(auto)" ? nil : value)
        default:
            break
        }
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

    private func rawInput(forKeyID keyID: String) -> String? {
        switch keyID {
        case "up": return "\u{001B}[A"
        case "down": return "\u{001B}[B"
        case "left": return "\u{001B}[D"
        case "right": return "\u{001B}[C"
        case "enter": return "\r"
        case "escape": return "\u{001B}"
        case "space": return " "
        default: return nil
        }
    }
}
