import Foundation

extension Data {
    /// Đọc `UInt32` little-endian. Bản port của `sea-g2p` cần nó để bóc header + bảng offset của
    /// `sea_g2p.bin`. Đã kiểm FreeBook chưa có hàm trùng tên trước khi mang vào.
    func readUInt32Le(at offset: Int) -> UInt32 {
        guard offset + 4 <= self.count else { return 0 }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

/// Bộ chuyển chữ → phoneme (G2P) tiếng Việt, đọc trực tiếp `sea_g2p.bin` (62.829.820 byte).
///
/// **Nguồn gốc**: port thuần Swift do chủ dự án viết, mang nguyên từ `VieNeuTTS-Offline`
/// (`VieNeuTTS-Offline/Services/SeaG2P.swift`) — cùng file đã chạy trong app đó. Mang sang đây vì
/// `text_encoder.onnx` của Nano ăn **phoneme id**, và bảng id đó (`config.json`) dùng đúng bộ ký hiệu
/// IPA mà `sea_g2p.bin` phát ra: đã đối chiếu, cả **42** ký tự non-ASCII của vocab đều có trong file nhị
/// phân này (8 ký tự còn lại là `①`…`⑧`, tức emotion tag chứ không phải phoneme).
///
/// **Tách thành 2 file**: bản gốc 509 dòng, vượt trần 400 dòng vật lý của repo. Phần "chữ → token →
/// phoneme" nằm ở `SeaG2P+Phonemize.swift`; các thành viên mà file đó dùng buộc phải hạ từ `private`
/// xuống `internal` (trong Swift, `private` là phạm vi **file**) — đúng tiền lệ đã ghi ở
/// `Docs/CodeGraph/09_dependency_rules.md:120`.
///
/// **Không an toàn đa luồng**: các cache `mergedCache`/`commonCache`/`segmentationCache` là `var` trần,
/// không khoá. Chỉ dùng nó từ trong `VieNeuTTSEngine` — nơi một `NSLock` bọc trọn lượt tổng hợp.
final class SeaG2P {
    private let data: Data
    private let stringCount: UInt32
    private let mergedCount: UInt32
    private let commonCount: UInt32
    private let stringOffsetsPos: Int
    private let mergedPos: Int
    private let commonPos: Int
    /// Byte đầu của **blob chuỗi** (mọi offset trong bảng tính từ đây).
    ///
    /// Bản port đầu tiên hardcode `32 + offset`. Sai: `write_bin_v2` ghi header **48** byte cho định dạng
    /// v2 (4 magic + 4 version + 12 count + 12 vị trí + 8 bảng section + 8 reserved) rồi mới tới blob.
    /// Lệch 16 byte nghĩa là mọi chuỗi đọc ra đều là *đuôi của chuỗi trước + đầu của chuỗi sau* ⇒
    /// phoneme rác ⇒ model đọc ra thứ không phải tiếng Việt, trong khi mọi thứ khác (shape, tensor, độ
    /// dài audio) đều đúng nên rất khó đoán ra.
    private let stringBase: Int

    // Cache — xem ghi chú "không an toàn đa luồng" ở doc của type.
    var mergedCache: [String: String] = [:]
    var commonCache: [String: (String, String)] = [:]
    var missingMerged: Set<String> = []
    var missingCommon: Set<String> = []
    var segmentationCache: [String: String?] = [:]

    static let reToken = try! NSRegularExpression(pattern: "(?i)(<en>.*?</en>)|(\\w+(?:['’]\\w+)*)|([^\\w\\s])", options: [])
    static let reTagContent = try! NSRegularExpression(pattern: "(\\w+(?:['’]\\w+)*)|([^\\w\\s])", options: [])
    static let reTagStrip = try! NSRegularExpression(pattern: "(?i)</?en>", options: [])
    static let viAccents = Set("àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ")

    static let emotionTags: [String: Int] = [
        "chuckle": 1, "cười": 1, "cuoi": 1,
        "sigh": 2, "thở dài": 2, "tho dai": 2,
        "clear throat": 3, "hắng giọng": 3, "hang giong": 3
    ]

    static let reEmotionSplit = try! NSRegularExpression(pattern: "(\\[[^\\]]+\\]|<\\|emotion_\\d+\\|>)", options: [])

    init(binURL: URL) throws {
        self.data = try Data(contentsOf: binURL, options: .mappedIfSafe)

        guard data.count >= 32 else {
            throw NSError(domain: "SeaG2P", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid dictionary file size"])
        }

        let magic = data.subdata(in: 0..<4)
        guard magic == Data([0x53, 0x45, 0x41, 0x50]) else { // "SEAP"
            throw NSError(domain: "SeaG2P", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid magic signature in dictionary"])
        }

        self.stringCount = data.readUInt32Le(at: 8)
        self.mergedCount = data.readUInt32Le(at: 12)
        self.commonCount = data.readUInt32Le(at: 16)

        // V1 dùng header 32 byte; v2 thêm 8 byte bảng section + 8 byte reserved ⇒ 48.
        let version = data.readUInt32Le(at: 4)
        self.stringBase = version >= 2 ? 48 : 32
        self.stringOffsetsPos = Int(data.readUInt32Le(at: 20))
        self.mergedPos = Int(data.readUInt32Le(at: 24))
        self.commonPos = Int(data.readUInt32Le(at: 28))
    }

    private func getString(id: UInt32) -> String {
        if id >= stringCount { return "" }
        let offPtr = stringOffsetsPos + Int(id) * 4
        let offset = Int(data.readUInt32Le(at: offPtr))
        let start = stringBase + offset

        var end = start
        while end < data.count && data[end] != 0 {
            end += 1
        }

        return String(decoding: data[start..<end], as: UTF8.self)
    }

    /// So sánh theo **thứ tự byte UTF-8**.
    ///
    /// `write_bin_v2` sắp bảng bằng `sorted(..., key=lambda kv: kv[0].encode("utf-8"))`, tức thứ tự byte
    /// UTF-8. `String.<` của Swift dùng Unicode canonical ordering — không bảo đảm trùng, nên tìm nhị
    /// phân bằng `<` có thể trượt dù khoá **có** trong bảng. Dùng `utf8` tại chỗ, không cấp phát mảng.
    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private func lookupMerged(word: String) -> String? {
        var low = 0
        var high = Int(mergedCount) - 1

        while low <= high {
            let mid = (low + high) / 2
            let ptr = mergedPos + (mid * 8)
            let wId = data.readUInt32Le(at: ptr)
            let currentWord = getString(id: wId)

            if currentWord == word {
                let pId = data.readUInt32Le(at: ptr + 4)
                return getString(id: pId)
            } else if Self.utf8Less(currentWord, word) {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    private func lookupCommon(word: String) -> (String, String)? {
        var low = 0
        var high = Int(commonCount) - 1

        while low <= high {
            let mid = (low + high) / 2
            let ptr = commonPos + (mid * 12)
            let wId = data.readUInt32Le(at: ptr)
            let currentWord = getString(id: wId)

            if currentWord == word {
                let viId = data.readUInt32Le(at: ptr + 4)
                let enId = data.readUInt32Le(at: ptr + 8)
                return (getString(id: viId), getString(id: enId))
            } else if Self.utf8Less(currentWord, word) {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    func cachedLookupMerged(word: String) -> String? {
        if let cached = mergedCache[word] { return cached }
        if missingMerged.contains(word) { return nil }

        if let s = lookupMerged(word: word) {
            if mergedCache.count >= 10000 { mergedCache.removeAll() }
            mergedCache[word] = s
            return s
        } else {
            if missingMerged.count < 50000 { missingMerged.insert(word) }
            return nil
        }
    }

    func cachedLookupCommon(word: String) -> (String, String)? {
        if let cached = commonCache[word] { return cached }
        if missingCommon.contains(word) { return nil }

        if let pair = lookupCommon(word: word) {
            if commonCache.count >= 5000 { commonCache.removeAll() }
            commonCache[word] = pair
            return pair
        } else {
            if missingCommon.count < 50000 { missingCommon.insert(word) }
            return nil
        }
    }

    private func resolveSegmentPhone(segment: String, lang: String) -> String? {
        let lw = segment.lowercased()
        if let p = cachedLookupMerged(word: lw) {
            return p.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let (vi, en) = cachedLookupCommon(word: lw) {
            let phone = (lang == "en" && !en.isEmpty) ? en : (!vi.isEmpty ? vi : en)
            return phone.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func hasVowelAndConsonant(_ s: String) -> Bool {
        var hasV = false
        var hasC = false
        let vowelSet = Set("aeiouyàáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ")

        for c in s.lowercased() {
            if vowelSet.contains(c) {
                hasV = true
            } else if c.isLetter {
                hasC = true
            }
            if hasV && hasC { return true }
        }
        return false
    }

    func segmentOOV(word: String, lang: String) -> String? {
        let cacheKey = "\(word)_\(lang)"
        if let cached = segmentationCache[cacheKey] {
            return cached
        }

        let chars = Array(word)
        let n = chars.count

        var dp = [String?](repeating: nil, count: n + 1)
        dp[0] = ""

        for i in 0..<n {
            if dp[i] == nil { continue }

            for j in stride(from: n, through: i + 1, by: -1) {
                let segment = String(chars[i..<j])
                if !hasVowelAndConsonant(segment) { continue }

                if let phone = resolveSegmentPhone(segment: segment, lang: lang) {
                    let prev = dp[i]!
                    let newPhone = prev.isEmpty ? phone : "\(prev) \(phone)"
                    if dp[j] == nil {
                        dp[j] = newPhone
                    }
                }
            }
        }

        let result = dp[n]
        if segmentationCache.count >= 5000 { segmentationCache.removeAll() }
        segmentationCache[cacheKey] = result
        return result
    }

    func charFallback(content: String, lang: String) -> String {
        var result: [String] = []
        for c in content {
            let cl = String(c).lowercased()
            if let cp = cachedLookupMerged(word: cl) {
                result.append(cp.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
            } else if let (v, e) = cachedLookupCommon(word: cl) {
                let p = (lang == "en" && !e.isEmpty) ? e : (!v.isEmpty ? v : e)
                result.append(p.replacingOccurrences(of: "<en>", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                result.append(cl)
            }
        }
        return result.joined(separator: "")
    }

    struct Token {
        var lang: String
        var content: String
        var phone: String?
        var isExplicitEn: Bool
    }
}
