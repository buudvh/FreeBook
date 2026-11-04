import Foundation

/// Chủ sở hữu **bộ ngoặc** của token `<[>` / `<]>` (1.3.692).
///
/// - **Bộ chung**: `UserDefaults` khoá `quickTranslateRuleBracketPairs`, chuỗi JSON
///   `[{open, close, name, enabled}]`. Khoá **vắng** = bộ mặc định (`QuickTranslationRuleBracketDefaults`),
///   nên cặp mặc định thêm ở bản sau vẫn tới người chưa sửa. Khoá chữ thường nên Backup tự gói.
/// - **Bộ riêng truyện**: trường `brackets` của `QuickTranslateEngineConfig.json`, đọc/ghi qua
///   `QuickTranslationBookEngineConfigStore` (cùng file với công tắc token riêng). Vắng = theo bộ chung;
///   có = truyện dùng **trọn** danh sách riêng đó (kể cả danh sách rỗng).
///
/// `bracketSet(bookId:)` chạy mỗi lần chụp `TranslationReadContext` (và theo từng dòng khi không có bản
/// chụp), nên giữ cache bản chụp bất biến: bộ chung được kiểm còn đúng bằng cách so **chuỗi JSON thô** với
/// `UserDefaults` — bước khôi phục cài đặt của Backup ghi thẳng vào `UserDefaults` mà không qua store này.
/// Không giải mã JSON theo từng dòng văn.
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`.
public final class QuickTranslationRuleBracketStore {
    public static let shared = QuickTranslationRuleBracketStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    public static let userDefaultsKey = "quickTranslateRuleBracketPairs"

    private let lock = NSLock()
    /// Chuỗi JSON đã dựng ra `cachedGlobal`; `nil` = khoá vắng (bộ mặc định).
    private nonisolated(unsafe) var cachedRaw: String?
    private nonisolated(unsafe) var cachedGlobal: QuickTranslationRuleBracketSet?

    private init() {}

    // MARK: - Bộ chung

    /// Danh sách cặp của bộ chung, theo đúng thứ tự người dùng xếp. Khoá vắng hoặc JSON hỏng ⇒ bộ mặc định.
    public func globalPairs() -> [QuickTranslationRuleBracketPair] {
        Self.decodePairs(UserDefaults.standard.string(forKey: Self.userDefaultsKey))
            ?? QuickTranslationRuleBracketDefaults.pairs
    }

    /// `true` khi bộ chung đã được sửa (khoá có mặt và đọc được) — màn cấu hình dùng để hiện "Khôi phục mặc định".
    public var isGlobalCustomized: Bool {
        Self.decodePairs(UserDefaults.standard.string(forKey: Self.userDefaultsKey)) != nil
    }

    /// Ghi **trọn** danh sách (kể cả rỗng = không cặp nào). Dọn cache bản chụp + cache dịch rồi phát một tín
    /// hiệu rule đã đổi, đúng như công tắc token chung.
    public func setGlobalPairs(_ pairs: [QuickTranslationRuleBracketPair]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(pairs), let raw = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("❌ [BracketStore] Không mã hoá được bộ ngoặc chung (\(pairs.count) cặp)")
            return
        }
        UserDefaults.standard.set(raw, forKey: Self.userDefaultsKey)
        didChangeGlobal()
    }

    /// Xoá khoá ⇒ quay về bộ mặc định (và nhận luôn cặp mặc định mới ở bản sau).
    public func resetGlobalToDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        didChangeGlobal()
    }

    private func didChangeGlobal() {
        lock.lock()
        cachedRaw = nil
        cachedGlobal = nil
        lock.unlock()
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyRulesDidUpdate()
    }

    // MARK: - Bản chụp cho một lượt dịch

    /// Bộ ngoặc có hiệu lực cho truyện: bộ riêng nếu truyện có đặt, không thì bộ chung.
    public func bracketSet(bookId: String?) -> QuickTranslationRuleBracketSet {
        QuickTranslationBookEngineConfigStore.shared.bookBracketSet(bookId: bookId) ?? globalSet()
    }

    private func globalSet() -> QuickTranslationRuleBracketSet {
        let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
        lock.lock()
        if let hit = cachedGlobal, cachedRaw == raw {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let set = Self.decodePairs(raw).map(QuickTranslationRuleBracketSet.init(pairs:)) ?? .defaults
        lock.lock()
        cachedRaw = raw
        cachedGlobal = set
        lock.unlock()
        return set
    }

    private static func decodePairs(_ raw: String?) -> [QuickTranslationRuleBracketPair]? {
        guard let data = raw?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([QuickTranslationRuleBracketPair].self, from: data)
    }

    // MARK: - Kiểm tra khi lưu một cặp

    /// Lỗi của cặp `open`/`close` khi đặt vào `pairs` (bỏ qua ô `excludingIndex` — chính cặp đang sửa);
    /// `nil` = hợp lệ.
    ///
    /// So bằng **đơn vị UTF-16** như matcher, không so `Character`: so `Character` áp chuẩn hoá Unicode nên
    /// `〈` U+2329 sẽ bị coi là trùng `〈` U+3008 dù matcher thấy hai ký tự khác nhau. Mọi cặp đều được xét,
    /// kể cả cặp đang tắt — bật lại sau sẽ đụng nhau.
    public static func validationError(
        open: String,
        close: String,
        in pairs: [QuickTranslationRuleBracketPair],
        excludingIndex: Int?
    ) -> String? {
        guard !open.isEmpty else { return "Chưa nhập ngoặc mở" }
        guard !close.isEmpty else { return "Chưa nhập ngoặc đóng" }
        guard open.count == 1, let openUnit = QuickTranslationRuleBracketPair.singleUnit(of: open) else {
            return "Ngoặc mở phải là đúng một ký tự (một đơn vị UTF-16)"
        }
        guard close.count == 1, let closeUnit = QuickTranslationRuleBracketPair.singleUnit(of: close) else {
            return "Ngoặc đóng phải là đúng một ký tự (một đơn vị UTF-16)"
        }
        guard openUnit != closeUnit else { return "Ngoặc mở và ngoặc đóng phải khác nhau" }

        for (index, pair) in pairs.enumerated() where index != excludingIndex {
            let units = [pair.open, pair.close].compactMap(QuickTranslationRuleBracketPair.singleUnit(of:))
            let label = "\(pair.open) \(pair.close)" + (pair.name.isEmpty ? "" : " (\(pair.name))")
            if units.contains(openUnit) { return "Ký tự \(open) đã có trong cặp \(label)" }
            if units.contains(closeUnit) { return "Ký tự \(close) đã có trong cặp \(label)" }
        }
        return nil
    }
}
