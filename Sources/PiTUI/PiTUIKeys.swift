import Foundation

public enum PiTUIKeys {
    private final class GlobalState: @unchecked Sendable {
        private let lock = NSLock()
        private var kittyProtocolActive = false

        func setKittyProtocolActive(_ active: Bool) {
            lock.lock()
            kittyProtocolActive = active
            lock.unlock()
        }

        func getKittyProtocolActive() -> Bool {
            lock.lock()
            let value = kittyProtocolActive
            lock.unlock()
            return value
        }
    }

    private static let globalState = GlobalState()

    public static func setKittyProtocolActive(_ active: Bool) {
        globalState.setKittyProtocolActive(active)
    }

    public static func isKittyProtocolActive() -> Bool {
        globalState.getKittyProtocolActive()
    }

    public static func matchesKey(_ data: String, _ keyID: String) -> Bool {
        guard let parsed = parseKey(data) else { return false }
        return canonicalize(parsed) == canonicalize(keyID)
    }

    public static func parseKey(_ data: String) -> String? {
        if let special = parseSpecialSequence(data) {
            return special
        }

        if data == "\u{001B}" { return "escape" }
        if data == "\r" || data == "\n" {
            return isKittyProtocolActive() && data == "\n" ? "shift+enter" : "enter"
        }
        if data == "\t" { return "tab" }
        if data == " " { return "space" }
        if data == "\u{0008}" || data == "\u{007F}" { return "backspace" }

        if let ctrl = parseLegacyCtrl(data) {
            return ctrl
        }

        if let alt = parseLegacyAlt(data) {
            return alt
        }

        if data.count == 1, let ch = data.first {
            if ch.isUppercase, ch.isLetter {
                return "shift+\(String(ch).lowercased())"
            }
            return String(ch)
        }

        return nil
    }

    private static func parseSpecialSequence(_ data: String) -> String? {
        switch data {
        case "\u{001B}[A", "\u{001B}OA": return "up"
        case "\u{001B}[B", "\u{001B}OB": return "down"
        case "\u{001B}[C", "\u{001B}OC": return "right"
        case "\u{001B}[D", "\u{001B}OD": return "left"
        case "\u{001B}OH": return "home"
        case "\u{001B}OF": return "end"
        default: return nil
        }
    }

    private static func parseLegacyCtrl(_ data: String) -> String? {
        guard data.count == 1, let scalar = data.unicodeScalars.first else { return nil }
        let v = scalar.value
        switch v {
        case 0: return "ctrl+space"
        case 1...26:
            let scalarValue = UnicodeScalar(Int(v + 96))!
            return "ctrl+\(String(scalarValue))"
        case 28: return "ctrl+\\"
        case 29: return "ctrl+]"
        case 30: return "ctrl+^"
        case 31: return "ctrl+-"
        default: return nil
        }
    }

    private static func parseLegacyAlt(_ data: String) -> String? {
        guard data.hasPrefix("\u{001B}"), data.count == 2 else { return nil }
        let second = String(data.dropFirst())

        if second == "\u{0008}" || second == "\u{007F}" {
            return "alt+backspace"
        }

        if isKittyProtocolActive() {
            return nil
        }

        if let ctrl = parseLegacyCtrl(second) {
            return ctrl.replacingOccurrences(of: "ctrl+", with: "ctrl+alt+")
        }

        switch second {
        case "B": return "alt+left"
        case "F": return "alt+right"
        case " ": return "alt+space"
        default:
            if let ch = second.first {
                if ch.isUppercase, ch.isLetter {
                    return "alt+shift+\(String(ch).lowercased())"
                }
                return "alt+\(second)"
            }
            return nil
        }
    }

    private static func canonicalize(_ keyID: String) -> String {
        var parts = keyID.lowercased().split(separator: "+").map(String.init)
        guard parts.count > 1 else {
            return canonicalBase(parts.first ?? keyID.lowercased())
        }

        let base = canonicalBase(parts.removeLast())
        let modifiers = Set(parts)
        let ordered = ["ctrl", "alt", "shift"].filter { modifiers.contains($0) }
        if ordered.isEmpty { return base }
        return (ordered + [base]).joined(separator: "+")
    }

    private static func canonicalBase(_ base: String) -> String {
        switch base {
        case "esc": return "escape"
        case "return": return "enter"
        case "_": return "-"
        default: return base
        }
    }
}
