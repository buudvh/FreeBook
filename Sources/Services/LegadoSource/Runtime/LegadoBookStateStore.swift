import Foundation
import CryptoKit

/// Kho trạng thái theo truyện của nguồn Legado (`LegadoBookState`: `tocUrl`, biến sách, biến chương — spec §5.7).
///
/// Hai tầng:
/// - **Bộ nhớ** — khoá `packageId + "\n" + bookUrl` (bookUrl nguyên văn đã trim, **giữ** khối option `,{…}`: hai sách
///   chỉ khác thân POST là hai sách). Gồm cả biến của mục tìm kiếm/khám phá chưa lên kệ. Có chỉ mục `bookId → khoá`
///   để lời gọi thiếu `bookUrl` (TTS) vẫn tìm thấy. Giới hạn `memoryCapacity` mục, bỏ mục cũ nhất.
/// - **Đĩa** — `applicationSupport/legado_state/<sha256(bookId)>.json`, **chỉ** cho sách đã lên kệ (caller quyết định
///   qua `persist`, xem `LegadoSourceRuntime.shouldPersist`). Sách chưa lên kệ nhận UUID mới mỗi lần mở trang chi tiết,
///   ghi theo id đó sẽ để lại file mồ côi. Chỉ ghi khi trạng thái thật sự khác bản đã ghi.
///
/// Mọi thay đổi áp theo **từng khoá** (`LegadoBookStateDelta`) dưới lock nên hai phiên song song không đè nhau.
/// Ghi file trên queue nền tuần tự (atomic); mọi đường dẫn qua `validatePathSafety(for:)`.
final class LegadoBookStateStore: @unchecked Sendable {
    static let shared = LegadoBookStateStore()
    static let memoryCapacity = 300

    private struct Entry {
        var state: LegadoBookState
        var bookId: String?
        /// Bản đã ghi xuống đĩa gần nhất (`nil` = chưa ghi lần nào trong phiên này).
        var persisted: LegadoBookState?
        /// Đã thử đọc file theo `bookId` (có hay không có file).
        var diskChecked: Bool
        var touched: UInt64
    }

    private let rootURL: URL
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var keyByBookId: [String: String] = [:]
    private var savedBookIds: Set<String> = []
    private var deletedBookIds: Set<String> = []
    private var clock: UInt64 = 0
    private let writeQueue = DispatchQueue(label: "FreeBook.LegadoBookState", qos: .utility)

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootURL = base.appendingPathComponent("legado_state", isDirectory: true)
        }
    }

    // MARK: - API tĩnh cho tầng ngoài

    /// Xoá trạng thái của một sách (gọi khi xoá sách khỏi kệ, sau khi DB đã lưu). Đồng bộ, không ném; `true` khi có gì
    /// bị xoá. Sau lời gọi này `bookId` không bao giờ được ghi lại trong phiên chạy app.
    @discardableResult
    static func deleteState(bookId: String) -> Bool {
        shared.delete(bookId: bookId)
    }

    static func memoryKey(packageId: String, bookUrl: String) -> String {
        packageId + "\n" + bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Đọc

    /// Trạng thái hiện hành (không bao giờ `nil`; chưa có gì ⇒ trạng thái rỗng). Có `bookId` mà chưa đọc đĩa ⇒ đọc
    /// file một lần rồi gộp với bản trong bộ nhớ (bộ nhớ mới hơn).
    func state(packageId: String, bookUrl: String?, bookId: String?) -> LegadoBookState {
        let id = Self.nonEmpty(bookId)
        let url = Self.nonEmpty(bookUrl) ?? ""
        lock.lock()
        guard let key = resolveKey(packageId: packageId, bookUrl: url, bookId: id) else {
            lock.unlock()
            return LegadoBookState(packageId: packageId, bookUrl: url)
        }
        var entry = takeEntry(key: key, packageId: packageId, bookUrl: url, bookId: id)
        store(entry, key: key)
        if id == nil || entry.diskChecked {
            lock.unlock()
            return entry.state
        }
        lock.unlock()

        let disk = id.flatMap { readFile(bookId: $0) }
        lock.lock()
        defer { lock.unlock() }
        entry = takeEntry(key: key, packageId: packageId, bookUrl: url, bookId: id)
        mergeDisk(disk, into: &entry)
        store(entry, key: key)
        return entry.state
    }

    /// Đã biết sách này nằm trên kệ (đã có file, hoặc caller đã xác nhận qua `markSaved`).
    func isKnownSaved(bookId: String) -> Bool {
        lock.lock()
        if deletedBookIds.contains(bookId) {
            lock.unlock()
            return false
        }
        if savedBookIds.contains(bookId) {
            lock.unlock()
            return true
        }
        lock.unlock()
        let fileURL = stateFileURL(bookId: bookId)
        guard (try? validatePathSafety(for: fileURL)) != nil,
              FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        markSaved(bookId: bookId)
        return true
    }

    func markSaved(bookId: String) {
        lock.lock()
        if !deletedBookIds.contains(bookId) { savedBookIds.insert(bookId) }
        lock.unlock()
    }

    // MARK: - Ghi

    /// Áp `delta` lên trạng thái hiện hành. `persist` (sách đã lên kệ) ⇒ ghi file nếu trạng thái khác bản đã ghi.
    func commit(_ delta: LegadoBookStateDelta, packageId: String, bookUrl: String?, bookId: String?, persist: Bool) {
        let id = Self.nonEmpty(bookId)
        let url = Self.nonEmpty(bookUrl) ?? ""
        var pendingWrite: (bookId: String, state: LegadoBookState)?
        lock.lock()
        guard let key = resolveKey(packageId: packageId, bookUrl: url, bookId: id) else {
            lock.unlock()
            return
        }
        var entry = takeEntry(key: key, packageId: packageId, bookUrl: url, bookId: id)
        if !delta.isEmpty {
            entry.state = delta.applied(to: entry.state)
        }
        if persist, let id, !deletedBookIds.contains(id) {
            if !entry.diskChecked {
                // Hiếm: chưa đọc đĩa mà đã ghi — gộp file cũ trước để không đè mất biến đã lưu.
                mergeDisk(readFile(bookId: id), into: &entry)
            }
            savedBookIds.insert(id)
            if entry.state.hasContent, entry.state != entry.persisted {
                entry.persisted = entry.state
                pendingWrite = (id, entry.state)
            }
        }
        store(entry, key: key)
        lock.unlock()
        if let pendingWrite {
            writeQueue.async { [self] in
                writeFile(bookId: pendingWrite.bookId, state: pendingWrite.state)
            }
        }
    }

    private func delete(bookId: String) -> Bool {
        guard let id = Self.nonEmpty(bookId) else { return false }
        lock.lock()
        deletedBookIds.insert(id)
        savedBookIds.remove(id)
        let keys = entries.filter { $0.value.bookId == id }.map { $0.key }
        for key in keys { entries.removeValue(forKey: key) }
        let bare = entries.removeValue(forKey: Self.bareKey(id)) != nil
        keyByBookId.removeValue(forKey: id)
        lock.unlock()

        let fileURL = stateFileURL(bookId: id)
        // `sync` sau mọi lệnh ghi đang chờ của sách này: không để lệnh ghi cũ tạo lại file sau khi xoá.
        let fileRemoved: Bool = writeQueue.sync {
            guard (try? validatePathSafety(for: fileURL)) != nil,
                  FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            do {
                try FileManager.default.removeItem(at: fileURL)
                return true
            } catch {
                AppLogger.shared.log("❌ [LegadoBookState] Không xoá được trạng thái truyện: \(error.localizedDescription)")
                return false
            }
        }
        return fileRemoved || bare || !keys.isEmpty
    }

    // MARK: - Bộ nhớ (gọi khi đang giữ `lock`)

    /// Khoá bộ nhớ: theo URL khi có; thiếu URL ⇒ khoá đã gắn với `bookId`, không có thì khoá riêng theo `bookId`.
    private func resolveKey(packageId: String, bookUrl: String, bookId: String?) -> String? {
        if !bookUrl.isEmpty { return Self.memoryKey(packageId: packageId, bookUrl: bookUrl) }
        guard let bookId else { return nil }
        return keyByBookId[bookId] ?? Self.bareKey(bookId)
    }

    /// Lấy (hoặc tạo) mục của `key`, gắn `bookId`, và hút mục "chỉ theo bookId" (tạo lúc chưa biết URL) vào mục theo URL.
    private func takeEntry(key: String, packageId: String, bookUrl: String, bookId: String?) -> Entry {
        var entry = entries[key] ?? Entry(state: LegadoBookState(packageId: packageId, bookUrl: bookUrl), bookId: nil,
                                          persisted: nil, diskChecked: false, touched: 0)
        guard let bookId else { return entry }
        entry.bookId = bookId
        let bareKey = Self.bareKey(bookId)
        if key != bareKey, let bare = entries.removeValue(forKey: bareKey) {
            entry.state = LegadoBookState.merged(base: entry.state, overlay: bare.state)
            entry.persisted = bare.persisted ?? entry.persisted
            entry.diskChecked = entry.diskChecked || bare.diskChecked
        }
        if !bookUrl.isEmpty || keyByBookId[bookId] == nil {
            keyByBookId[bookId] = key
        }
        return entry
    }

    private func mergeDisk(_ disk: LegadoBookState?, into entry: inout Entry) {
        guard !entry.diskChecked else { return }
        entry.diskChecked = true
        guard let disk else { return }
        entry.state = LegadoBookState.merged(base: disk, overlay: entry.state)
        entry.persisted = disk
    }

    private func store(_ entry: Entry, key: String) {
        var entry = entry
        clock += 1
        entry.touched = clock
        entries[key] = entry
        guard entries.count > Self.memoryCapacity else { return }
        let overflow = entries.count - Self.memoryCapacity * 4 / 5
        let oldest = entries.sorted { $0.value.touched < $1.value.touched }.prefix(overflow).map { $0.key }
        for oldKey in oldest where oldKey != key {
            entries.removeValue(forKey: oldKey)
        }
        keyByBookId = keyByBookId.filter { entries[$0.value] != nil }
    }

    private static func bareKey(_ bookId: String) -> String {
        "#bookId\n" + bookId
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - File

    private func stateFileURL(bookId: String) -> URL {
        let digest = SHA256.hash(data: Data(bookId.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(digest + ".json")
    }

    private func readFile(bookId: String) -> LegadoBookState? {
        let fileURL = stateFileURL(bookId: bookId)
        guard (try? validatePathSafety(for: fileURL)) != nil,
              FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(LegadoBookState.self, from: data)
        } catch {
            AppLogger.shared.log("❌ [LegadoBookState] Không đọc được trạng thái truyện: \(error.localizedDescription)")
            return nil
        }
    }

    /// Chạy trên `writeQueue`.
    private func writeFile(bookId: String, state: LegadoBookState) {
        lock.lock()
        let deleted = deletedBookIds.contains(bookId)
        lock.unlock()
        guard !deleted else { return }
        let fileURL = stateFileURL(bookId: bookId)
        do {
            try validatePathSafety(for: fileURL)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [LegadoBookState] Không lưu được trạng thái truyện: \(error.localizedDescription)")
        }
    }

    /// Đường dẫn phải nằm **trong** `legado_state/` (sau khi chuẩn hoá và giải symlink).
    private func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootURL.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.count > canonicalRoot.pathComponents.count,
              canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục legado_state bị từ chối."])
        }
    }
}
