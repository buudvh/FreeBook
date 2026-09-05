import Foundation

/// Chủ sở hữu **cấu hình engine riêng của từng truyện**:
/// `translate/books/<bookId>/QuickTranslateEngineConfig.json`.
///
/// Giữ hai thứ trong **một** file vì mỗi lượt rewrite cần cả hai — một file là một lần đọc, một lần
/// cache:
///
/// - thứ tự ưu tiên rule (`QuickTranslationRulePriorityConfiguration`),
/// - trạng thái riêng của 10 token DSL.
///
/// **Ngữ nghĩa kế thừa, không phải bản copy.** Trường vắng mặt = *theo cài đặt chung*, nên sửa cấu
/// hình chung vẫn lan tới truyện chưa đặt riêng. Nếu lưu bản copy thì lần đầu mở màn cấu hình của
/// một truyện là truyện đó đóng băng giá trị hiện tại — một lớp bug im lặng.
///
/// `rewrite` chạy theo **từng dòng văn** nên bắt buộc cache trong RAM có khoá; chạm đĩa mỗi dòng là
/// tự sát. Cùng khuôn `globalPatterns`/`bookPatterns` của `QuickTranslationRuleDisableStore`.
///
/// Ranh giới tầng: Service ⇒ **không** `import SwiftUI`, **không** `ToastManager` — trả `Outcome`,
/// View tự phát toast.
///
/// Không phải `ObservableObject`: hai màn cấu hình đọc lại state khi `body` chạy và chỉ có chúng sửa
/// file này, nên thêm `@Published revision` là dựng một đường refresh không ai dùng.
public final class QuickTranslationBookEngineConfigStore {
    public static let shared = QuickTranslationBookEngineConfigStore()

    public static let fileName = "QuickTranslateEngineConfig.json"

    public enum Outcome: Sendable {
        case success
        case failure(message: String)
    }

    /// Trạng thái của một token trong phạm vi truyện. `inherit` là mặc định và **không** ghi vào file.
    public enum TokenOverride: String, CaseIterable, Hashable, Sendable {
        case inherit
        case enabled
        case disabled

        public var title: String {
            switch self {
            case .inherit: return "Theo cài đặt chung"
            case .enabled: return "Bật riêng"
            case .disabled: return "Tắt riêng"
            }
        }

        /// Bản ngắn cho `Picker` kiểu `.segmented` — nhãn dài bị cắt mất chữ ở máy nhỏ.
        public var shortTitle: String {
            switch self {
            case .inherit: return "Chung"
            case .enabled: return "Bật"
            case .disabled: return "Tắt"
            }
        }
    }

    private let lock = NSLock()
    /// Có khoá trong dictionary = đã đọc đĩa. Giá trị rỗng = truyện không có file hoặc không đặt gì.
    private nonisolated(unsafe) var cached: [String: Overrides] = [:]

    private init() {}

    /// Nội dung file. **Mọi trường optional**: vắng mặt = kế thừa bộ chung.
    ///
    /// Thứ tự ưu tiên lưu dạng chuỗi thay vì mảng enum để dùng đúng hàm mã hoá của
    /// `QuickTranslationRulePriorityConfiguration` — một chỗ hiểu định dạng, không phải hai.
    struct Overrides: Codable, Equatable {
        var priorityOrder: String?
        var priorityDescending: String?
        /// Khoá là `QuickTranslationRuleTokenSettings.Kind.rawValue`; giá trị là bật/tắt tường minh.
        var tokens: [String: Bool]?

        var isEmpty: Bool {
            (priorityOrder ?? "").isEmpty && (tokens?.isEmpty ?? true)
        }
    }

    // MARK: - Đường dẫn

    public func fileURL(for bookId: String) -> URL {
        TranslationManager.shared.translateDirectory
            .appendingPathComponent("books")
            .appendingPathComponent(bookId)
            .appendingPathComponent(Self.fileName)
    }

    // MARK: - Đọc

    /// `nil` khi `bookId` rỗng — mọi API công khai đều coi đó là phạm vi chung.
    private func overrides(for bookId: String?) -> Overrides? {
        guard let bookId, !bookId.isEmpty else { return nil }

        lock.lock()
        if let hit = cached[bookId] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let loaded = readFile(for: bookId)
        lock.lock()
        cached[bookId] = loaded
        lock.unlock()
        return loaded
    }

    /// File vắng, hỏng, hoặc không giải mã được ⇒ `Overrides()` rỗng. Không bao giờ throw ra ngoài:
    /// cấu hình hỏng phải làm truyện chạy theo bộ chung, chứ không được làm truyện không dịch được.
    private func readFile(for bookId: String) -> Overrides {
        let url = fileURL(for: bookId)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Overrides.self, from: data) else {
            return Overrides()
        }
        return decoded
    }

    // MARK: - Phân giải cho một lượt rewrite

    public typealias Priority = QuickTranslationRulePriorityConfiguration
    public typealias TokenKind = QuickTranslationRuleTokenSettings.Kind

    /// Thứ tự ưu tiên áp cho truyện: phần đặt riêng nếu có, không thì cấu hình chung.
    public func priorityConfiguration(bookId: String?) -> Priority.Configuration {
        let global = Priority.globalConfiguration()
        guard let overrides = overrides(for: bookId) else { return global }
        return Priority.decode(
            order: overrides.priorityOrder,
            descending: overrides.priorityDescending
        ) ?? global
    }

    public func hasPriorityOverride(bookId: String?) -> Bool {
        !((overrides(for: bookId)?.priorityOrder ?? "").isEmpty)
    }

    /// Công tắc token áp cho truyện: token nào có đặt riêng thì theo đó, còn lại theo cài đặt chung.
    public func tokenConfiguration(bookId: String?) -> QuickTranslationRuleTokenSettings.Configuration {
        let overrides = overrides(for: bookId)
        var enabled: Set<TokenKind> = []
        for kind in TokenKind.allCases {
            let isOn = overrides?.tokens?[kind.rawValue]
                ?? QuickTranslationRuleTokenSettings.isEnabled(kind)
            if isOn { enabled.insert(kind) }
        }
        return QuickTranslationRuleTokenSettings.Configuration(enabledKinds: enabled)
    }

    public func tokenOverride(for kind: TokenKind, bookId: String?) -> TokenOverride {
        guard let value = overrides(for: bookId)?.tokens?[kind.rawValue] else { return .inherit }
        return value ? .enabled : .disabled
    }

    /// Số token đang đặt riêng — dùng cho nhãn phụ ở Cài đặt trình đọc.
    public func overriddenTokenCount(bookId: String?) -> Int {
        overrides(for: bookId)?.tokens?.count ?? 0
    }

    // MARK: - Ghi

    /// `nil` = xoá phần đặt riêng, truyện quay về kế thừa cấu hình chung.
    public func setPriority(_ configuration: Priority.Configuration?, bookId: String) -> Outcome {
        mutate(bookId: bookId) { overrides in
            guard let configuration else {
                overrides.priorityOrder = nil
                overrides.priorityDescending = nil
                return
            }
            overrides.priorityOrder = Priority.encodeOrder(configuration)
            overrides.priorityDescending = Priority.encodeDescending(configuration)
        }
    }

    public func setTokenOverride(_ override: TokenOverride, for kind: TokenKind, bookId: String) -> Outcome {
        mutate(bookId: bookId) { overrides in
            var tokens = overrides.tokens ?? [:]
            switch override {
            case .inherit: tokens.removeValue(forKey: kind.rawValue)
            case .enabled: tokens[kind.rawValue] = true
            case .disabled: tokens[kind.rawValue] = false
            }
            overrides.tokens = tokens.isEmpty ? nil : tokens
        }
    }

    /// Xoá toàn bộ phần đặt riêng của truyện.
    public func reset(bookId: String) -> Outcome {
        mutate(bookId: bookId) { $0 = Overrides() }
    }

    private func mutate(bookId: String, _ change: (inout Overrides) -> Void) -> Outcome {
        guard !bookId.isEmpty else { return .failure(message: "Thiếu mã truyện") }
        var next = overrides(for: bookId) ?? Overrides()
        change(&next)
        do {
            try persist(next, bookId: bookId)
        } catch {
            return .failure(message: "Không ghi được cấu hình riêng của truyện: \(error.localizedDescription)")
        }
        lock.lock()
        cached[bookId] = next
        lock.unlock()
        return .success
    }

    /// Rỗng thì **xoá file** thay vì ghi `{}` — truyện quay về kế thừa thì không nên còn file rác.
    private func persist(_ overrides: Overrides, bookId: String) throws {
        let url = fileURL(for: bookId)
        guard !overrides.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(overrides).write(to: url, options: .atomic)
    }

    // MARK: - Dọn cache RAM

    /// Gọi khi file bị sửa ngoài store: phục hồi backup, xoá truyện. `nil` = dọn hết.
    public func invalidate(bookId: String?) {
        lock.lock()
        if let bookId, !bookId.isEmpty {
            cached.removeValue(forKey: bookId)
        } else {
            cached.removeAll()
        }
        lock.unlock()
    }
}
