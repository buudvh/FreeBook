import Foundation

/// Nhánh nguồn Legado của `SourceRuntime`: tra nguồn theo `localPath` và bọc log quanh mỗi lời gọi.
extension SourceRuntime {
    /// Nguồn Legado đã nạp của `localPath`; `nil` khi là tiện ích JS. Ném khi là nguồn Legado nhưng loại không chạy được
    /// ("Nguồn Legado loại … chưa hỗ trợ ở bản này") hoặc không đọc được `source.json`.
    func legadoTarget(_ localPath: String) throws -> LegadoSourceRuntime.Target? {
        do {
            return try LegadoSourceTargetResolver.shared.target(localPath: localPath)
        } catch {
            AppLogger.shared.log("❌ [SourceRuntime][Legado] \(URL(fileURLWithPath: localPath).lastPathComponent): \(LegadoCorpusErrorClassifier.redact(error.localizedDescription))")
            throw error
        }
    }

    /// Ghi log một lời gọi nguồn Legado (dòng thường theo công tắc log; lỗi có `❌`, trừ huỷ). Không log nội dung chương.
    /// Lỗi của `search` không gắn `❌`: "tìm mọi nguồn" chạy hàng trăm nguồn, nguồn hỏng sẽ làm tràn file log.
    ///
    /// `interactive` (= `SourceRuntimeContext.isInteractive`): chạy `operation` trong ngữ cảnh **có người dùng**
    /// (`LegadoInteraction.isInteractive`) để `java.startBrowser*` / `getVerificationCode` / toast được trình bày.
    /// Lời gọi đã nằm trong ngữ cảnh đó (call site tự bọc) thì giữ nguyên.
    func legadoCall<T>(_ action: String, _ detail: String, interactive: Bool = false,
                       _ operation: () async throws -> T) async throws -> T {
        guard interactive, !LegadoInteraction.isInteractive else {
            return try await loggedLegadoCall(action, detail, operation)
        }
        return try await LegadoInteraction.$isInteractive.withValue(true) {
            try await loggedLegadoCall(action, detail, operation)
        }
    }

    /// Bọc lời gọi của call site **không có** `SourceRuntimeContext` (danh mục khám phá, trang khám phá đang xem,
    /// nguồn phát video đang xem) vào ngữ cảnh có người dùng. Tiện ích JS không bị ảnh hưởng.
    static func userInitiated<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await LegadoInteraction.$isInteractive.withValue(true, operation: operation)
    }

    private func loggedLegadoCall<T>(_ action: String, _ detail: String,
                                     _ operation: () async throws -> T) async throws -> T {
        AppLogger.shared.log("🔍 [SourceRuntime][Legado] \(action): \(detail.prefix(300))")
        do {
            return try await operation()
        } catch {
            if !(error is CancellationError) {
                let category = LegadoRuntimeError.categoryName(of: error)
                let marker = action == "search" ? "" : "❌ "
                // Thông điệp lỗi có thể chứa URL kèm query (token phiên…) ⇒ redact trước khi ghi file.
                AppLogger.shared.log("\(marker)[SourceRuntime][Legado] \(action) lỗi (\(category)): \(LegadoCorpusErrorClassifier.redact(error.localizedDescription))")
            }
            throw error
        }
    }
}
