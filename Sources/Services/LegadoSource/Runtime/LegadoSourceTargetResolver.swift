import Foundation

/// `localPath` (thư mục tiện ích, đúng tham số mà call site truyền cho `SourceRuntime`) → nguồn Legado đã nạp.
///
/// - Nhận diện theo `Extension.type` họ `legado*` của bản ghi đã cài (bảng chụp có lock, không `await`). Thư mục ngoài
///   kho (bản nháp của công cụ gỡ lỗi) thì đọc `metadata.type` của `plugin.json`.
/// - `source.json` được parse một lần cho mỗi `(localPath, version)` rồi giữ trong bộ nhớ: chương đọc liên tục
///   (Reader, TTS, tải truyện) không phải parse lại JSON nguồn mỗi lần.
/// - Nguồn đang **tắt** vẫn chạy được thông tin/mục lục/nội dung (sách đã ở trên kệ vẫn đọc tiếp); việc lọc nguồn tắt
///   khỏi Tìm kiếm/Khám phá là của call site (`LegadoSourcePolicy`).
final class LegadoSourceTargetResolver: @unchecked Sendable {
    static let shared = LegadoSourceTargetResolver()
    private static let capacity = 64

    private struct Cached {
        let version: Int
        let target: LegadoSourceRuntime.Target
    }

    private let lock = NSLock()
    private var cache: [String: Cached] = [:]

    /// `true` khi `localPath` là thư mục của một nguồn Legado. Đồng bộ, gọi được từ thread/actor bất kỳ.
    func isLegado(localPath: String) -> Bool {
        let path = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        if let packageId = ExtensionLibraryRepository.packageId(forLocalPath: path) {
            guard let ext = ExtensionLibraryRepository.snapshot(packageId: packageId) else { return false }
            return LegadoSourceIdentity.isLegado(ext)
        }
        guard let type = ExtensionManifestReader.metadata(localPath: path)?["type"] as? String else { return false }
        return LegadoSourceIdentity.isLegado(type: type)
    }

    /// Nguồn Legado của `localPath`, `nil` khi không phải nguồn Legado. Ném khi là nguồn Legado nhưng loại chưa hỗ trợ
    /// ở đợt này (tranh/video) hoặc không đọc được `source.json`.
    func target(localPath: String) throws -> LegadoSourceRuntime.Target? {
        let path = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if let packageId = ExtensionLibraryRepository.packageId(forLocalPath: path) {
            guard let ext = ExtensionLibraryRepository.snapshot(packageId: packageId),
                  LegadoSourceIdentity.isLegado(ext) else { return nil }
            let kind = LegadoSourceIdentity.kind(of: ext) ?? .unsupported
            guard LegadoSourcePolicy.isSupportedInCurrentPhase(kind) else {
                throw LegadoRuntimeError.unsupportedKind(kind.label)
            }
            return try cachedTarget(path: path, packageId: packageId, version: ext.version)
        }
        // Thư mục ngoài kho (bản nháp): không đệm — nội dung có thể đổi bất cứ lúc nào.
        guard let type = ExtensionManifestReader.metadata(localPath: path)?["type"] as? String,
              LegadoSourceIdentity.isLegado(type: type) else { return nil }
        let source = try loadSource(path: path)
        guard LegadoSourcePolicy.isSupportedInCurrentPhase(source.kind) else {
            throw LegadoRuntimeError.unsupportedKind(source.kind.label)
        }
        return LegadoSourceRuntime.Target(source: source)
    }

    private func cachedTarget(path: String, packageId: String, version: Int) throws -> LegadoSourceRuntime.Target {
        lock.lock()
        if let cached = cache[path], cached.version == version, cached.target.packageId == packageId {
            lock.unlock()
            return cached.target
        }
        lock.unlock()

        let target = LegadoSourceRuntime.Target(packageId: packageId, source: try loadSource(path: path))
        lock.lock()
        if cache.count >= Self.capacity { cache.removeAll(keepingCapacity: true) }
        cache[path] = Cached(version: version, target: target)
        lock.unlock()
        return target
    }

    private func loadSource(path: String) throws -> LegadoBookSource {
        do {
            return try LegadoSourceStore.loadSource(localPath: path)
        } catch {
            throw LegadoRuntimeError.sourceUnavailable(error.localizedDescription)
        }
    }
}
