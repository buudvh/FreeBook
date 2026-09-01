import Foundation

/// Lưu trạng thái phụ của một truyện đến từ nguồn Legado: túi biến và `tocUrl`.
///
/// **Vì sao là file riêng chứ không phải cột DB**: `Book`/`Chapter` là 2 trong 5 `@Model` của schema
/// SwiftData, mà schema này **không có** `SchemaMigrationPlan`; còn `chapter_metadata` trong
/// `chapters/chapter_store.sqlite` là store **dùng chung** với sách VBook (`user_version = 1`), thêm
/// cột ở đó là đặt cả kệ sách vào rủi ro chỉ để phục vụ một loại nguồn.
///
/// Mỗi truyện một file `legado_state/<sha256(bookId)>.json`, chỉ sinh ra khi rule thật sự `put` biến.
/// Đặt tất cả trong **một** thư mục (không chia theo nguồn) để `BookStorageManager` xoá được chỉ với
/// `bookId` — đúng luồng xoá sách hiện có.
public actor LegadoBookStateStore {
    public static let shared = LegadoBookStateStore()

    private struct State: Codable {
        var tocUrl: String?
        var book: [String: String]
        var chapters: [String: [String: String]]
    }

    private var cache: [String: State] = [:]

    private init() {}

    // MARK: - Đường dẫn

    private func stateDirectory() -> URL? {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let root = paths.first else { return nil }
        let directory = root.appendingPathComponent("legado_state", isDirectory: true)
        guard LegadoPathSafety.validate(directory, mustBeUnder: root) else { return nil }
        return directory
    }

    private func stateFile(bookId: String) -> URL? {
        guard let directory = stateDirectory(), !bookId.isEmpty else { return nil }
        let url = directory.appendingPathComponent(bookId.sha256() + ".json", isDirectory: false)
        guard LegadoPathSafety.validate(url, mustBeUnder: directory) else { return nil }
        return url
    }

    // MARK: - Đọc / ghi

    private func load(bookId: String) -> State {
        if let cached = cache[bookId] { return cached }
        var state = State(tocUrl: nil, book: [:], chapters: [:])
        if let url = stateFile(bookId: bookId),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        }
        cache[bookId] = state
        return state
    }

    private func persist(_ state: State, bookId: String) {
        cache[bookId] = state
        guard let directory = stateDirectory(), let url = stateFile(bookId: bookId) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [LegadoBookState] Không ghi được state: \(error.localizedDescription)")
        }
    }

    // MARK: - API

    public func variables(packageId: String, bookId: String) -> [String: String] {
        load(bookId: bookId).book
    }

    public func chapterVariables(
        packageId: String,
        bookId: String,
        chapterIndex: Int
    ) -> [String: String] {
        load(bookId: bookId).chapters[String(chapterIndex)] ?? [:]
    }

    public func tocUrl(packageId: String, bookId: String) -> String? {
        load(bookId: bookId).tocUrl
    }

    public func save(
        packageId: String,
        bookId: String,
        bookVariables: [String: String]? = nil,
        chapterIndex: Int? = nil,
        chapterVariables: [String: String]? = nil,
        tocUrl: String? = nil
    ) {
        guard !bookId.isEmpty else { return }
        var state = load(bookId: bookId)
        var changed = false

        if let bookVariables, !bookVariables.isEmpty, bookVariables != state.book {
            state.book = bookVariables
            changed = true
        }
        if let chapterIndex, let chapterVariables, !chapterVariables.isEmpty {
            let key = String(chapterIndex)
            if state.chapters[key] != chapterVariables {
                state.chapters[key] = chapterVariables
                changed = true
            }
        }
        if let tocUrl, !tocUrl.isEmpty, tocUrl != state.tocUrl {
            state.tocUrl = tocUrl
            changed = true
        }

        guard changed else { return }
        persist(state, bookId: bookId)
    }

    /// Xoá state khi xoá truyện. Gọi từ `BookStorageManager` — điều phối viên xoá duy nhất.
    /// Không ném lỗi: state là dữ liệu phụ, mất nó chỉ khiến nguồn phải bóc tách lại.
    public func removeState(bookId: String) {
        cache.removeValue(forKey: bookId)
        guard let url = stateFile(bookId: bookId),
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLogger.shared.log("⚠️ [LegadoBookState] Xoá state thất bại: \(error.localizedDescription)")
        }
    }
}
