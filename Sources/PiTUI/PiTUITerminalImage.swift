public enum PiTUITerminalImage {
    // Detects terminal image protocol escape sequences embedded anywhere in a line.
    // Used to avoid treating image payload rows as normal text during wrapping/layout.
    public static func isImageLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        // iTerm2 inline image protocol (OSC 1337 File=... BEL/ST)
        if line.contains("\u{001B}]1337;File=") {
            return true
        }
        // Kitty graphics protocol (APC ESC _G ... ST)
        if line.contains("\u{001B}_G") {
            return true
        }
        return false
    }
}
