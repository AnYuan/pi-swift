public enum PiCoreTypesModule {
    public static let moduleName = "PiCoreTypes"

    public struct Marker: Equatable, Sendable {
        public let value: String

        public init(value: String) {
            self.value = value
        }
    }
}
