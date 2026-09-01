import Foundation

/// Một bước trong biểu thức XPath đã phân tích.
public struct LegadoXPathStep {
    public enum Axis {
        /// `/` — con trực tiếp.
        case child
        /// `//` — mọi cấp con.
        case descendant
    }

    public enum NodeTest {
        case element(String)
        case anyElement
        case text
        case attribute(String)
    }

    public enum Predicate {
        /// `[3]` — chỉ số 1-based.
        case position(Int)
        /// `[last()]`
        case last
        /// `[@class]`
        case hasAttribute(String)
        /// `[@class='x']` / `[@class!='x']`
        case attributeEquals(name: String, value: String, negated: Bool)
        /// `[contains(@class,'x')]`, `[contains(text(),'x')]`
        case contains(target: Target, value: String)
        /// `[starts-with(@href,'x')]`
        case startsWith(target: Target, value: String)
        /// Vị ngữ ngoài tập con — giữ nguyên chuỗi để báo lên báo cáo tương thích.
        case unsupported(String)
    }

    public enum Target {
        case attribute(String)
        case text
    }

    public let axis: Axis
    public let nodeTest: NodeTest
    public let predicates: [Predicate]

    public init(axis: Axis, nodeTest: NodeTest, predicates: [Predicate]) {
        self.axis = axis
        self.nodeTest = nodeTest
        self.predicates = predicates
    }

    public var hasUnsupportedPredicate: Bool {
        predicates.contains { predicate in
            if case .unsupported = predicate { return true }
            return false
        }
    }
}
