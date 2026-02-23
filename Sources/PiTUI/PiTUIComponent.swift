public protocol PiTUIComponent: AnyObject {
    func render(width: Int) -> [String]
    func invalidate()
}

public class PiTUIContainer: PiTUIComponent {
    public private(set) var children: [PiTUIComponent] = []

    public init() {}

    public func addChild(_ component: PiTUIComponent) {
        children.append(component)
    }

    public func removeChild(_ component: PiTUIComponent) {
        children.removeAll { $0 === component }
    }

    public func clearChildren() {
        children.removeAll()
    }

    public func invalidate() {
        for child in children {
            child.invalidate()
        }
    }

    public func render(width: Int) -> [String] {
        children.flatMap { $0.render(width: width) }
    }
}
