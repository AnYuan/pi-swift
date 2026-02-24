public final class PiKillRing {
    public struct PushOptions {
        public var prepend: Bool
        public var accumulate: Bool

        public init(prepend: Bool, accumulate: Bool = false) {
            self.prepend = prepend
            self.accumulate = accumulate
        }
    }

    private var ring: [String] = []

    public init() {}

    public var length: Int {
        ring.count
    }

    public func push(_ text: String, options: PushOptions) {
        guard !text.isEmpty else { return }

        if options.accumulate, let last = ring.popLast() {
            ring.append(options.prepend ? text + last : last + text)
        } else {
            ring.append(text)
        }
    }

    public func peek() -> String? {
        ring.last
    }

    public func rotate() {
        guard ring.count > 1, let last = ring.popLast() else { return }
        ring.insert(last, at: 0)
    }
}
