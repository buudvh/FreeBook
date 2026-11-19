import SwiftUI

/// Trạng thái + thao tác của 5 thẻ **Từ điển chung** ở Cài đặt dịch thuật (VietPhrase.txt / Name.txt / PhienAm.txt /
/// Pronouns.txt / Rule dịch). Mỗi thẻ là một `Menu` hệ thống thả xuống (`GlobalDictionaryCardMenu`): Sửa, Nhập file,
/// Xuất file, Làm mới dữ liệu, Xoá. Phần trình bày (popup chọn cách nhập, bộ chọn file, bảng chia sẻ, hộp xác nhận xoá,
/// trang Sửa) gắn ở thân màn qua `GlobalDictionaryCardPresentations` — không gắn trong ô lưới của `Form`.
///
/// Lớp View (được gọi `ToastManager`); việc file nằm ở Service: `GlobalDictionaryImporter` (nhập 3 chế độ / xoá từ điển
/// gốc), `GlobalDictionaryTextExporter` (xuất TXT), `QuickTranslationRuleStore` + `QuickTranslationRuleExporter` (rule).
/// "Đang nhập" giữ ở `TranslationImportState.shared` (sống lâu hơn màn) theo mã thẻ `Kind.rawValue`.
@MainActor
final class GlobalDictionaryCardController: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case vietPhrase = "vietphrase"
        case names
        case phienAm = "phienam"
        case pronouns
        case rules

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vietPhrase: return "VietPhrase.txt"
            case .names: return "Name.txt"
            case .phienAm: return "PhienAm.txt"
            case .pronouns: return "Pronouns.txt"
            case .rules: return "Rule dịch"
            }
        }

        /// Mọi thẻ đều có màn danh sách để "Sửa": VP / Name ⇒ `GlobalBaseDictionaryListView` (từ điển gốc `.dat` + lớp sửa
        /// đổi Chung, ghi vào lớp sửa đổi), PhienAm / Pronouns ⇒ `BaseDictionaryListView` (sửa thẳng file gốc), Rule dịch ⇒
        /// danh sách bộ rule chung.
        var hasEditor: Bool { true }
    }

    /// File tạm chờ chia sẻ — xoá khi đóng bảng chia sẻ.
    struct SharedExport: Identifiable {
        let url: URL
        let title: String
        var id: String { url.absoluteString }
    }

    @Published var showingImportModes = false
    @Published var showingFilePicker = false
    @Published var importKind: Kind = .vietPhrase
    @Published var sharedExport: SharedExport?
    @Published var exportingKind: Kind?
    @Published var deleteKind: Kind?
    /// Trang "Sửa" đang đẩy (`navigationDestination(item:)`).
    @Published var editKind: Kind?

    private var pendingMode: DataImportMode = .overwriteExisting
    private let importState = TranslationImportState.shared

    // MARK: - Trạng thái thẻ

    func isBusy(_ kind: Kind) -> Bool {
        importState.importingTypes.contains(kind.rawValue) || exportingKind == kind
    }

    /// Mọi thẻ khoá trong lúc làm mới dữ liệu dịch hoặc đang xuất (một lượt xuất một lúc).
    var isLocked: Bool {
        importState.importingTypes.contains("refresh") || exportingKind != nil
    }

    // MARK: - Nhập

    func requestImport(_ kind: Kind) {
        importKind = kind
        showingImportModes = true
    }

    /// Popup đã đóng hẳn (`dataImportModePopup`) ⇒ mở bộ chọn file ngay.
    func confirmImportMode(_ mode: DataImportMode) {
        pendingMode = mode
        showingFilePicker = true
    }

    func handlePickedFile(_ url: URL?) {
        guard let url else { return }
        let kind = importKind
        let mode = pendingMode
        if kind == .rules {
            importRules(from: url, mode: mode)
            return
        }
        importState.importingTypes.insert(kind.rawValue)
        Task {
            do {
                // Qua hàng đợi chung của từ điển gốc: không chen với lượt sửa ở danh sách Phiên âm / Pronouns.
                let outcome = try await GlobalDictionaryEditor.shared.importFile(at: url, type: kind.rawValue, mode: mode)
                DictionaryCache.shared.invalidateAll()
                let message = mode == .replaceAll
                    ? "Đã thay \(kind.title) bằng \(outcome.importedCount) từ."
                    : "Đã nhập \(kind.title): thêm \(outcome.added), cập nhật \(outcome.updated)."
                ToastManager.shared.show(message: message, type: .success)
            } catch {
                AppLogger.shared.log("❌ Lỗi nhập \(kind.title): \(error.localizedDescription)")
                ToastManager.shared.show(message: "Lỗi nhập \(kind.title): \(error.localizedDescription)", type: .error)
            }
            importState.importingTypes.remove(kind.rawValue)
        }
    }

    private func importRules(from url: URL, mode: DataImportMode) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule (cần UTF-8).", type: .error)
            return
        }
        let store = QuickTranslationRuleStore.shared
        let preview = QuickTranslationRuleRecordStore.importCounts(current: store.currentSourceText() ?? "", imported: text, mode: mode)
        switch store.importRules(text: text, mode: mode) {
        case .success(let ruleCount, let warningCount):
            let suffix = warningCount > 0 ? ", \(warningCount) cảnh báo" : ""
            let message: String
            switch mode {
            case .replaceAll:
                message = "Đã thay bộ rule chung — hiện có \(ruleCount) rule\(suffix)."
            case .overwriteExisting, .keepExisting:
                message = "Đã nhập rule: thêm \(preview.added), cập nhật \(preview.updated) — bộ chung có \(ruleCount) rule\(suffix)."
            }
            ToastManager.shared.show(message: message, type: .success)
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(message: "File có lỗi nặng (\(detail)) — bộ rule chung không đổi.", type: .error)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    // MARK: - Xuất

    func export(_ kind: Kind) {
        guard exportingKind == nil, !isBusy(kind) else { return }
        if kind == .rules {
            switch QuickTranslationRuleExporter.writeTemporaryFile(scope: .global) {
            case .file(let url, _, _):
                present(url, title: kind.title)
            case .noRuleSet:
                ToastManager.shared.show(message: "Chưa có bộ rule chung để xuất.", type: .error)
            case .allDisabled(let count):
                ToastManager.shared.show(message: "Cả \(count) rule chung đang tắt — không có rule nào để xuất.", type: .info)
            case .failure(let message):
                ToastManager.shared.show(message: message, type: .error)
            }
            return
        }
        exportingKind = kind
        Task {
            // Duyệt cây VietPhrase (trăm nghìn – triệu từ) mất vài giây ⇒ ra khỏi main thread.
            let type = kind.rawValue
            let result = await Task.detached(priority: .userInitiated) {
                Result { try GlobalDictionaryTextExporter.export(type: type) }
            }.value
            exportingKind = nil
            switch result {
            case .success(let url):
                present(url, title: kind.title)
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                AppLogger.shared.log("❌ Lỗi xuất \(kind.title): \(message)")
                ToastManager.shared.show(message: "Lỗi xuất \(kind.title): \(message)", type: .error)
            }
        }
    }

    /// File tạm của lượt chia sẻ đang mở — `sheet(item:)` đã đặt `nil` trước `onDismiss` nên giữ URL riêng để xoá.
    private var sharedExportURL: URL?

    private func present(_ url: URL, title: String) {
        // File rule xuất luôn trùng tên (`QuickTranslateRules.txt`) — vừa ghi đè thì đừng xoá chính nó.
        if sharedExportURL != url { cleanUpSharedExport() }
        sharedExportURL = url
        sharedExport = SharedExport(url: url, title: title)
    }

    /// Đóng bảng chia sẻ ⇒ xoá file tạm.
    func cleanUpSharedExport() {
        guard let url = sharedExportURL else { return }
        try? FileManager.default.removeItem(at: url)
        sharedExportURL = nil
    }

    // MARK: - Làm mới + xoá

    /// **Một** hàm cho nút "Làm mới dữ liệu dịch" của màn và mục "Làm mới dữ liệu" của mọi thẻ.
    func refreshTranslationData() {
        guard importState.importingTypes.isEmpty else { return }
        importState.importingTypes.insert("refresh")
        Task {
            do {
                try await TranslationManager.shared.loadAllDictionaries()
                TranslationManager.shared.clearBookDictCache()
                TranslateUtils.clearCache()
                DictionaryCache.shared.invalidateAll()
                ToastManager.shared.show(message: "Đã làm mới dữ liệu dịch thành công", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi làm mới dữ liệu dịch: \(error.localizedDescription)", type: .error)
            }
            importState.importingTypes.remove("refresh")
        }
    }

    func confirmDelete(_ kind: Kind) {
        if kind == .rules {
            let existed = QuickTranslationRuleStore.shared.deleteRules()
            ToastManager.shared.show(message: existed ? "Đã xoá bộ rule chung." : "Máy chưa có bộ rule chung.", type: .info)
            return
        }
        importState.importingTypes.insert(kind.rawValue)
        Task {
            do {
                try await GlobalDictionaryEditor.shared.deleteBase(type: kind.rawValue)
                DictionaryCache.shared.invalidateAll()
                ToastManager.shared.show(message: "Đã xoá \(kind.title).", type: .info)
            } catch {
                AppLogger.shared.log("❌ Lỗi xoá \(kind.title): \(error.localizedDescription)")
                ToastManager.shared.show(message: "Lỗi xoá \(kind.title): \(error.localizedDescription)", type: .error)
            }
            importState.importingTypes.remove(kind.rawValue)
        }
    }

    /// Nội dung hộp xác nhận xoá — nói rõ xoá gì, giữ gì.
    static func deleteMessage(for kind: Kind) -> String {
        switch kind {
        case .vietPhrase:
            return "Xoá file gốc VietPhrase (VietPhrase.txt + VietPhrase.dat). Các từ đã sửa ở VietPhrase Chung được giữ. Có lại bằng Nhập file hoặc Tải từ điển mặc định."
        case .names:
            return "Xoá file gốc Names (Names.txt + Names.dat). Các tên đã sửa ở Names Chung được giữ."
        case .phienAm:
            return "Xoá file phiên âm ChinesePhienAmWords.txt. Chữ không có trong từ điển sẽ không còn phiên âm Hán-Việt tới khi nhập lại."
        case .pronouns:
            return "Xoá file gốc Pronouns (Pronouns.txt + Pronouns.dat)."
        case .rules:
            return "Xoá bộ rule chung (\(QuickTranslationRuleStore.ruleFileName)); việc dịch quay về thuần từ điển. Bộ rule tên chương và bộ rule riêng của từng truyện không bị ảnh hưởng."
        }
    }
}
