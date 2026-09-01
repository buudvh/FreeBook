import Foundation

/// Máy quét độ sâu ngoặc + nháy dùng cho `LegadoRuleLexer`.
///
/// Tách riêng khỏi lexer vì `MULTI_PRIMARY_TYPES` chỉ cho một type chính mỗi file, và vì trạng thái
/// này còn được `LegadoJsoupDialect` dùng lại khi tách chỉ số `[…]` khỏi selector.
public struct BalanceScanner {
    private var squareDepth = 0
    private var roundDepth = 0
    private var curlyDepth = 0
    private var inSingleQuote = false
    private var inDoubleQuote = false

    /// Ký tự vừa gặp là `\` ngoài nháy ⇒ caller phải bỏ qua ký tự kế tiếp.
    public var skipNextScalar = false

    public init() {}

    /// Đang ở mức ngoài cùng: không trong nháy, không trong ngoặc nào.
    public var isAtTopLevel: Bool {
        !inSingleQuote && !inDoubleQuote && squareDepth == 0 && roundDepth == 0 && curlyDepth == 0
    }

    public var isBalanced: Bool {
        squareDepth == 0 && roundDepth == 0 && curlyDepth == 0 && !inSingleQuote && !inDoubleQuote
    }

    public mutating func consume(_ scalar: Unicode.Scalar) {
        skipNextScalar = false

        if scalar == "'" && !inDoubleQuote {
            inSingleQuote.toggle()
            return
        }
        if scalar == "\"" && !inSingleQuote {
            inDoubleQuote.toggle()
            return
        }
        if inSingleQuote || inDoubleQuote { return }

        if scalar == "\\" {
            skipNextScalar = true
            return
        }

        switch scalar {
        case "[": squareDepth += 1
        case "]": if squareDepth > 0 { squareDepth -= 1 }
        case "(": roundDepth += 1
        case ")": if roundDepth > 0 { roundDepth -= 1 }
        case "{": curlyDepth += 1
        case "}": if curlyDepth > 0 { curlyDepth -= 1 }
        default: break
        }
    }
}
