import Foundation
import Observation

/// Chữ dịch bằng **tiện ích dịch** cho một màn có nhiều mẩu chữ hiện trong `body` (1.3.852): đầu trang / mục lục
/// Reader, Chi tiết, Khám phá, tên chương truyện tranh…
///
/// Cách dùng: màn giữ một store (`@State`), gọi `update(options:request:)` khi cấu hình dịch / bộ dịch đổi (ngoài
/// `body`: `.task(id:)`, `.onChange`, `onAppear`) — `options` = cấu hình chữ của màn, `request` =
/// `ChineseTextExtensionTranslator.request(…)` (`nil` = QT ⇒ store chỉ trả chữ QT) — rồi trong `body` hiện
/// `store.text(chữ, kind:)`:
/// - đã có bản tiện ích ⇒ trả bản đó;
/// - chưa có ⇒ trả bản **QT** (đường `ChineseTextPipeline`, phồn → giản trước) và xếp mẩu vào hàng chờ. Sau một nhịp
///   ngắn (`flushDelay`), mọi mẩu xin trong nhịp đó đi **một** lượt `ChineseTextExtensionTranslator` (gom lô theo
///   `max_line` / `max_length`) ⇒ `translations` đổi ⇒ màn vẽ lại với bản tiện ích.
///
/// `text(_:kind:)` gọi được trong `body`: chỉ ghi các trường `@ObservationIgnored` (không đổi trạng thái quan sát lúc
/// đang vẽ). Mẩu lỗi giữ bản QT tới khi đổi `request` (không xin lại mỗi lượt vẽ). Bản dịch chỉ ở RAM.
@MainActor
@Observable
final class ExtensionTextTranslationStore {
    typealias Kind = ChineseTextExtensionTranslator.Kind

    /// Cấu hình chữ của màn (phồn → giản + dịch QT) — dùng cho bản QT.
    private(set) var options: ChineseTextPipeline.Options = .passthrough
    /// Lượt dịch tiện ích hiện tại; `nil` = bộ dịch QT hoặc tắt dịch.
    private(set) var request: ChineseTextExtensionTranslator.Request?
    /// Lỗi gần nhất của tiện ích (đã lùi QT) — màn muốn báo thì đọc.
    private(set) var fallbackStatus: TranslationFallbackStatus?
    private var translations: [Key: String] = [:]

    @ObservationIgnored private var queued: [Key] = []
    @ObservationIgnored private var queuedKeys = Set<Key>()
    @ObservationIgnored private var requested = Set<Key>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private static let flushDelay: UInt64 = 150_000_000
    /// Trần số bản dịch giữ trong store; vượt ⇒ xoá hết (lượt sau lấy lại từ cache RAM của tiện ích, không gọi lại).
    private static let maxEntries = 3000

    private struct Key: Hashable {
        let kind: Kind
        let text: String
    }

    init() {}

    /// Đổi cấu hình / lượt dịch; giống cũ ⇒ không làm gì. Đổi ⇒ bỏ bản dịch cũ, huỷ lượt đang chờ.
    func update(options: ChineseTextPipeline.Options, request: ChineseTextExtensionTranslator.Request?) {
        guard options != self.options || request != self.request else { return }
        self.options = options
        self.request = request
        reset()
    }

    /// Chữ hiển thị cho `text`: bản tiện ích nếu đã có, không thì bản QT (và xin dịch nền khi đang dùng tiện ích).
    /// `quick` = bản QT do màn tự dựng (vd đã ưu tiên `title_trans`); `nil` ⇒ `ChineseTextExtensionTranslator.quickTranslation`.
    func text(_ text: String, kind: Kind, quick: String? = nil) -> String {
        guard let request else {
            return quick ?? ChineseTextExtensionTranslator.quickTranslation(text, kind: kind, options: options)
        }
        let key = Key(kind: kind, text: text)
        if let hit = translations[key] { return hit }
        enqueue(key)
        return quick ?? ChineseTextExtensionTranslator.quickTranslation(text, kind: kind, options: options)
    }

    /// Có bản tiện ích cho `text` chưa (màn muốn tự quyết thứ tự ưu tiên).
    func translation(of text: String, kind: Kind) -> String? {
        translations[Key(kind: kind, text: text)]
    }

    // MARK: - Nội bộ

    private func reset() {
        generation &+= 1
        flushTask?.cancel()
        flushTask = nil
        queued.removeAll()
        queuedKeys.removeAll()
        requested.removeAll()
        translations.removeAll()
        fallbackStatus = nil
    }

    private func enqueue(_ key: Key) {
        guard !requested.contains(key), !queuedKeys.contains(key),
              TranslationExtensionBatchPlanner.needsTranslation(key.text) else { return }
        queued.append(key)
        queuedKeys.insert(key)
        guard flushTask == nil else { return }
        let token = generation
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.flushDelay)
            await self?.flush(token: token)
        }
    }

    private func flush(token: Int) async {
        flushTask = nil
        guard token == generation, let request, !queued.isEmpty else { return }
        let batch = queued
        queued.removeAll()
        queuedKeys.removeAll()
        requested.formUnion(batch)

        let output: ChineseTextExtensionTranslator.Output
        do {
            output = try await ChineseTextExtensionTranslator.translate(batch.map(\.text), request: request)
        } catch {
            // Huỷ (màn đóng / đổi lượt) — không phải lỗi; mẩu chưa dịch được xin lại ở lượt vẽ sau.
            if token == generation { requested.subtract(batch) }
            return
        }
        guard token == generation else { return }
        if translations.count + batch.count > Self.maxEntries {
            // Xoá cả dấu "đã xin" — không thì mẩu bị đẩy ra sẽ hiện QT mãi (`enqueue` bỏ qua mẩu đã xin).
            translations.removeAll()
            requested = Set(batch)
        }
        for (key, value) in zip(batch, output.texts) {
            if let value { translations[key] = value }
        }
        if let status = output.fallbackStatus { fallbackStatus = status }
        // Mẩu xin thêm trong lúc chờ lượt này ⇒ lượt kế.
        if !queued.isEmpty, flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.flushDelay)
                await self?.flush(token: token)
            }
        }
    }
}
