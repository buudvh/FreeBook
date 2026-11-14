import Foundation

/// Tách chữ của một chunk TTS thành token cho luật thay thế (1.3.920, anh Bửu chốt 2026-11-14).
///
/// - **Từ**: chữ / số liền nhau. Một `-` hoặc `.` **kẹp giữa hai chữ / số** (không dấu cách) vẫn thuộc từ —
///   `Kamar-Taj`, `S.H.I.E.L.D`, `3.14` đều là một token.
/// - **Ký hiệu**: dãy ký tự không phải chữ / số / khoảng trắng liền nhau — `,`, `..!?`, `.”`.
/// - **Khoảng trắng**: dãy khoảng trắng liền nhau (kể cả xuống dòng); không luật nào khớp.
///
/// Ví dụ `Vào Kamar-Taj, gặp Kamar.` ⇒ `Vào` · `␣` · `Kamar-Taj` · `,` · `␣` · `gặp` · `␣` · `Kamar` · `.`
///
/// Làm việc trên `Character` (cụm grapheme) nên chữ Việt dựng sẵn hay tổ hợp đều là một ký tự.
enum TTSReplacementTokenizer {
    enum Kind: Equatable, Sendable {
        case word
        case symbol
        case space
    }

    struct Token: Equatable, Sendable {
        let kind: Kind
        let text: String
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Ký tự nối — chỉ thuộc từ khi kẹp giữa hai chữ / số; đứng một mình hay đứng mép thì là ký hiệu.
    static func isJoiner(_ character: Character) -> Bool {
        character == "-" || character == "."
    }

    /// Token theo đúng thứ tự trong chữ; ghép `text` của mọi token lại ra đúng chuỗi ban đầu.
    static func tokens(in text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let characters = Array(text)
        var result: [Token] = []
        var start = 0
        var currentKind = kind(at: 0, in: characters)
        for index in 1..<characters.count {
            let next = kind(at: index, in: characters)
            guard next != currentKind else { continue }
            result.append(Token(kind: currentKind, text: String(characters[start..<index])))
            start = index
            currentKind = next
        }
        result.append(Token(kind: currentKind, text: String(characters[start...])))
        return result
    }

    /// Token duy nhất của `pattern`; `nil` khi `pattern` rỗng, là / có khoảng trắng, hoặc tách ra hơn một token
    /// (`Hàn Lập`, `Taj,`, `Kamar-`) — luật như vậy là luật sai.
    static func singleToken(_ pattern: String) -> Token? {
        let parts = tokens(in: pattern)
        guard parts.count == 1, let token = parts.first, token.kind != .space else { return nil }
        return token
    }

    private static func kind(at index: Int, in characters: [Character]) -> Kind {
        let character = characters[index]
        if isWordCharacter(character) { return .word }
        if character.isWhitespace { return .space }
        if isJoiner(character),
           index > 0, index + 1 < characters.count,
           isWordCharacter(characters[index - 1]),
           isWordCharacter(characters[index + 1]) {
            return .word
        }
        return .symbol
    }
}
