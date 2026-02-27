public final class PiUndoStack<State> {
    private var stack: [State] = []
    private let clone: (State) -> State
    private let maxSize: Int

    public init(maxSize: Int = 200, clone: @escaping (State) -> State = { $0 }) {
        self.maxSize = max(1, maxSize)
        self.clone = clone
    }

    public var length: Int {
        stack.count
    }

    public func push(_ state: State) {
        stack.append(clone(state))
        if stack.count > maxSize {
            stack.removeFirst(stack.count - maxSize)
        }
    }

    public func pop() -> State? {
        stack.popLast()
    }

    public func clear() {
        stack.removeAll(keepingCapacity: false)
    }
}
