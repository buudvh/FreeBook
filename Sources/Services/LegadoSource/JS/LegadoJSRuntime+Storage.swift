import Foundation

/// `source.*`, `book.*`, `chapter.*`, `cookie.*`, `cache.*` (spec §5.7, §6.5–§6.7).
extension LegadoJSRuntime {
    func nativeStorage(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        let sourceKey = session.source.key
        switch command {
        case "sourceInfo":
            return session.source.jsObject.compactText
        case "sourceGetVar":
            return session.store.sourceVariable(sourceKey: sourceKey)
        case "sourceSetVar":
            session.store.setSourceVariable(text(of: arguments[0]), sourceKey: sourceKey)
            return ""
        case "sourcePut":
            session.store.setSourceValue(text(of: arguments[1]), forKey: text(of: arguments[0]), sourceKey: sourceKey)
            return ""
        case "sourceGet":
            let value = session.store.sourceValue(forKey: text(of: arguments[0]), sourceKey: sourceKey)
            return value.map { LegadoEngineJSON.quoted($0) } ?? "null"
        case "sourceHeaders":
            let headers = try session.sourceHeaders(baseUrl: session.currentFrameBaseUrl)
            return LegadoEngineJSON.object(headers.map { (key: $0.name, value: LegadoEngineJSON.string($0.value)) }).compactText

        case "book.get":
            return (session.book?.jsValue(field: text(of: arguments[0])) ?? .null).compactText
        case "book.getVar":
            return session.book?.variable(text(of: arguments[0])) ?? ""
        case "book.putVar":
            session.book?.setVariable(arguments.isNull(1) ? nil : text(of: arguments[1]), forKey: text(of: arguments[0]))
            return ""
        case "chapter.get":
            return (session.chapter?.jsValue(field: text(of: arguments[0])) ?? .null).compactText
        case "chapter.getVar":
            return session.chapter?.variable(text(of: arguments[0])) ?? ""
        case "chapter.putVar":
            session.chapter?.setVariable(arguments.isNull(1) ? nil : text(of: arguments[1]), forKey: text(of: arguments[0]))
            return ""

        case "cookieGet":
            let url = text(of: arguments[0])
            if let name = arguments.plainString(1) {
                return session.cookieJar.value(forURL: url, name: name)
            }
            return session.cookieJar.cookieString(forURL: url)
        case "cookieSet":
            session.cookieJar.setCookies(fromString: text(of: arguments[1]), url: text(of: arguments[0]),
                                         replace: arguments.bool(2))
            return ""
        case "cookieRemove":
            session.cookieJar.removeCookies(forURL: text(of: arguments[0]))
            return ""

        case "cachePut":
            let seconds = arguments.number(2)
            session.store.setCacheValue(text(of: arguments[1]), forKey: text(of: arguments[0]), sourceKey: sourceKey,
                                        ttl: seconds.flatMap { $0 > 0 ? $0 : nil })
            return ""
        case "cacheGet":
            let value = session.store.cacheValue(forKey: text(of: arguments[0]), sourceKey: sourceKey)
            return value.map { LegadoEngineJSON.quoted($0) } ?? "null"
        case "cacheDelete":
            session.store.removeCacheValue(forKey: text(of: arguments[0]), sourceKey: sourceKey)
            return ""
        case "memPut":
            session.memory.setMemoryValue(text(of: arguments[1]), forKey: text(of: arguments[0]))
            return ""
        case "memGet":
            return session.memory.memoryValue(forKey: text(of: arguments[0])) ?? ""
        case "memDelete":
            session.memory.removeMemoryValue(forKey: text(of: arguments[0]))
            return ""
        default:
            return nil
        }
    }
}
