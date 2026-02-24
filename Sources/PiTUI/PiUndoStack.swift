public final class PiUndoStack<State> {
    private var stack: [State] = []
    private let clone: (State) -> State

    public init(clone: @escaping (State) -> State = { $0 }) {
        self.clone = clone
    }

    public var length: Int {
        stack.count
    }

    public func push(_ state: State) {
        stack.append(clone(state))
    }

    public func pop() -> State? {
        stack.popLast()
    }

    public func clear() {
        stack.removeAll(keepingCapacity: false)
    }
}
