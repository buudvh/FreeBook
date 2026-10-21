import Foundation

/// `java.getString/getStringList/getElements/setContent/put/get/toNumChapter` (spec §6.4.2).
/// Nội dung mặc định = nội dung hiện hành của đoạn JS đang chạy (khung rule trên cùng của phiên).
extension LegadoJSRuntime {
    func nativeRule(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        switch command {
        case "getString":
            let analyzer = session.frameAnalyzer(content: contentArgument(arguments[1]))
            let rule = text(of: arguments[0])
            if arguments.bool(2) { return try analyzer.url(rule) }
            return try analyzer.string(rule)
        case "getStringList":
            let analyzer = session.frameAnalyzer(content: contentArgument(arguments[1]))
            let rule = text(of: arguments[0])
            let values = try (arguments.bool(2) ? analyzer.urls(rule) : analyzer.strings(rule))
            return Self.jsonArray(values)
        case "getElements":
            let analyzer = session.frameAnalyzer(content: contentArgument(arguments[1]))
            let items = try analyzer.elements(text(of: arguments[0]))
            return descriptor(for: .list(items)).compactText
        case "setContent":
            session.setFrameContent(contentArgument(arguments[0]), baseUrl: arguments.plainString(1))
            return ""
        case "putVar":
            session.putRuleVariable(text(of: arguments[0]), text(of: arguments[1]))
            return ""
        case "getVar":
            return session.ruleVariable(text(of: arguments[0]))
        case "toNumChapter":
            return LegadoChineseNumber.toNumChapter(text(of: arguments[0]))
        default:
            return nil
        }
    }
}
