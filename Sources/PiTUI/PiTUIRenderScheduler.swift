public protocol PiTUIRenderScheduler: AnyObject {
    func schedule(_ task: @escaping () -> Void)
}

public final class PiTUIImmediateRenderScheduler: PiTUIRenderScheduler {
    public init() {}

    public func schedule(_ task: @escaping () -> Void) {
        task()
    }
}

public final class PiTUIManualRenderScheduler: PiTUIRenderScheduler {
    private var pendingTasks: [() -> Void] = []

    public init() {}

    public var pendingCount: Int {
        pendingTasks.count
    }

    public func schedule(_ task: @escaping () -> Void) {
        pendingTasks.append(task)
    }

    public func flush() {
        let tasks = pendingTasks
        pendingTasks.removeAll()
        for task in tasks {
            task()
        }
    }
}
