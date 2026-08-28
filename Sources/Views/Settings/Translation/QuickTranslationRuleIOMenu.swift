import SwiftUI
import UniformTypeIdentifiers

/// Modifier **Nhập / Xuất / Xoá** cho rule của một phạm vi (riêng hoặc chung).
/// Nội dung menu đổi theo tab hiện tại: tab Đang bật thao tác bộ rule, tab Đã tắt thao tác danh sách tắt.
///
/// **Lý do dùng ViewModifier thay View gắn toolbar:**
/// - `DocumentPickerPresenter` là `UIViewControllerRepresentable`; khi đặt `.background`
///   lên nội dung toolbar thì anchor VC bị nhúng vào bar button custom view.
///   Khi pop trong NavigationStack nằm trong sheet, việc teardown bar item kẹt transition
///   → màn trắng (bug 1.3.281). Giống `DictionaryListView`, mọi presenter/presentation
///   phải gắn lên **body chính** (`List`), chỉ `Menu` thuần nằm trong toolbar.
/// - Modifier cho phép giữ logic tách biệt (không bloat `QuickTranslationRuleListView`)
///   mà vẫn đặt presentation đúng chỗ.
@MainActor
struct QuickTranslationRuleIOMenu: ViewModifier {
    let scope: QuickTranslationRuleScope
    let showingDisabled: Bool
    let onChanged: () -> Void

    struct SharedFile: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @State private var showingImporter = false
    @State private var showingImportModes = false
    @State private var showingDeleteConfirm = false
    @State private var pendingImportText: String? = nil
    @State private var pendingPreview: (added: Int, overlapping: Int, machineOnly: Int) = (0, 0, 0)
    @State private var sharedFile: SharedFile? = nil

    @State var showingDisabledImporter = false
    @State var showingDisabledImportModes = false
    @State var pendingDisabledPatterns: [String]? = nil
    @State var pendingDisabledPreview: (added: Int, overlapping: Int, machineOnly: Int) = (0, 0, 0)
    @State var sharedDisabledFile: SharedFile? = nil
    @State var showingReenableConfirm = false
    @State var showingDeleteDisabledConfirm = false

    private var currentSourceText: String? {
        switch scope {
        case .global: return QuickTranslationRuleStore.shared.currentSourceText()
        case .book(let bookId): return QuickTranslationRuleBookStore.shared.currentSourceText(for: bookId)
        }
    }

    private var hasRuleFile: Bool {
        switch scope {
        case .global: return QuickTranslationRuleStore.shared.hasRuleFile
        case .book(let bookId): return QuickTranslationRuleBookStore.shared.hasRuleFile(for: bookId)
        }
    }

    var scopeLabel: String {
        scope.isGlobal ? "chung" : "riêng"
    }

    private var scopeLongLabel: String {
        scope.isGlobal ? "Rule chung" : "Rule riêng"
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if showingDisabled {
                            disabledRuleMenuItems
                        } else {
                            Button {
                                showingImporter = true
                            } label: {
                                Label("Nhập file rule (.txt)", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                exportRules()
                            } label: {
                                Label("Xuất bộ rule \(scopeLabel)", systemImage: "square.and.arrow.up")
                            }
                            .disabled(!hasRuleFile)

                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Label("Xoá bộ rule \(scopeLabel)", systemImage: "trash")
                            }
                            .disabled(!hasRuleFile)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .background(
                DocumentPickerPresenter(
                    isPresented: $showingImporter,
                    allowedContentTypes: [.plainText, .text],
                    allowsMultipleSelection: false,
                    onPick: { urls in readImport(from: urls.first) },
                    onCancel: nil
                )
            )
            .background(
                DocumentPickerPresenter(
                    isPresented: $showingDisabledImporter,
                    allowedContentTypes: [.plainText, .text],
                    allowsMultipleSelection: false,
                    onPick: { urls in readDisabledImport(from: urls.first) },
                    onCancel: nil
                )
            )
            .sheet(item: $sharedFile) { file in
                ShareSheet(activityItems: [file.url]) { _, completed, _, error in
                    if completed {
                        ToastManager.shared.show(message: "Đã xuất bộ rule \(scopeLabel).", type: .success)
                    } else if let error = error {
                        ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                    }
                }
            }
            .sheet(item: $sharedDisabledFile) { file in
                ShareSheet(activityItems: [file.url]) { _, completed, _, error in
                    if completed {
                        ToastManager.shared.show(message: "Đã xuất danh sách rule tắt.", type: .success)
                    } else if let error = error {
                        ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                    }
                }
            }
            .confirmationDialog(
                "Nhập bộ rule \(scopeLabel) thế nào?",
                isPresented: $showingImportModes,
                titleVisibility: .visible
            ) {
                ForEach(DataImportMode.allCases, id: \.self) { mode in
                    Button(mode.actionTitle, role: mode.isDestructive ? .destructive : nil) {
                        applyImport(mode: mode)
                    }
                }
                Button("Hủy", role: .cancel) { pendingImportText = nil }
            } message: {
                Text(
                    "File có \(pendingPreview.added + pendingPreview.overlapping) rule:"
                    + " \(pendingPreview.overlapping) trùng mẫu với bộ \(scopeLabel) đang có, \(pendingPreview.added) mẫu mới."
                    + " Bộ \(scopeLabel) trên máy có \(pendingPreview.machineOnly) mẫu không nằm trong file."
                )
            }
            .confirmationDialog(
                "Xoá bộ rule \(scopeLabel)\(scope.isGlobal ? " khỏi máy" : " của truyện")?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Xoá bộ rule \(scopeLabel)", role: .destructive) {
                    let existed: Bool
                    switch scope {
                    case .global:
                        existed = QuickTranslationRuleStore.shared.deleteRules()
                    case .book(let bookId):
                        existed = QuickTranslationRuleBookStore.shared.deleteRules(for: bookId)
                    }
                    ToastManager.shared.show(
                        message: existed
                            ? "Đã xoá bộ rule \(scopeLabel)."
                            : scope.isGlobal
                                ? "Máy chưa có bộ rule nào."
                                : "Truyện này chưa có bộ rule riêng.",
                        type: .info
                    )
                    onChanged()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                if scope.isGlobal {
                    Text("File \(QuickTranslationRuleStore.ruleFileName) sẽ bị xoá và việc dịch quay về thuần từ điển. Tải lại được bất cứ lúc nào.")
                } else {
                    Text("Truyện này sẽ quay về dùng thuần bộ rule chung. Bộ chung không bị ảnh hưởng.")
                }
            }
            .confirmationDialog(
                "Nhập danh sách rule tắt thế nào?",
                isPresented: $showingDisabledImportModes,
                titleVisibility: .visible
            ) {
                ForEach(DataImportMode.allCases, id: \.self) { mode in
                    Button(mode.actionTitle, role: mode.isDestructive ? .destructive : nil) {
                        applyDisabledImport(mode: mode)
                    }
                }
                Button("Hủy", role: .cancel) { pendingDisabledPatterns = nil }
            } message: {
                Text(
                    "File có \(pendingDisabledPreview.added + pendingDisabledPreview.overlapping) mẫu:"
                    + " \(pendingDisabledPreview.overlapping) mẫu đã tắt sẵn, \(pendingDisabledPreview.added) mẫu mới sẽ tắt."
                    + " Máy đang tắt \(pendingDisabledPreview.machineOnly) mẫu không nằm trong file."
                )
            }
            .confirmationDialog(
                "Bật lại tất cả rule đã tắt ở bộ \(scopeLabel)?",
                isPresented: $showingReenableConfirm,
                titleVisibility: .visible
            ) {
                Button("Bật lại tất cả", role: .destructive) {
                    reenableAllDisabledRules()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Mọi rule trong bộ \(scopeLabel) sẽ được bật lại. Danh sách tắt sẽ rỗng.")
            }
            .confirmationDialog(
                "Xoá tất cả rule đã tắt khỏi bộ \(scopeLabel)?",
                isPresented: $showingDeleteDisabledConfirm,
                titleVisibility: .visible
            ) {
                Button("Xoá tất cả rule đã tắt", role: .destructive) {
                    deleteAllDisabledRules()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("\(currentDisabledPatterns.count) rule đang tắt sẽ bị xoá hẳn khỏi file rule \(scopeLabel) và danh sách tắt được dọn sạch. Không hoàn tác được.")
            }
    }

    // MARK: - Thao tác

    /// Đọc file rồi **hỏi chế độ trước khi ghi** — chọn file không tự động là "thay thế toàn bộ".
    private func readImport(from url: URL?) {
        guard let url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule (cần UTF-8).", type: .error)
            return
        }

        pendingImportText = text
        pendingPreview = QuickTranslationRuleRecordStore.importPreview(
            current: currentSourceText ?? "",
            imported: text
        )
        showingImportModes = true
    }

    private func applyImport(mode: DataImportMode) {
        guard let text = pendingImportText else { return }
        pendingImportText = nil

        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch scope {
        case .global:
            outcome = QuickTranslationRuleStore.shared.importRules(text: text, mode: mode)
        case .book(let bookId):
            outcome = QuickTranslationRuleBookStore.shared.importRules(text: text, mode: mode, bookId: bookId)
        }

        switch outcome {
        case .success(let ruleCount, let warningCount):
            let suffix = warningCount > 0 ? ", \(warningCount) cảnh báo" : ""
            ToastManager.shared.show(
                message: "Đã nhập — bộ \(scopeLabel) hiện có \(ruleCount) rule\(suffix).",
                type: .success
            )
            onChanged()
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(
                message: "File có lỗi nặng (\(detail)) — bộ \(scopeLabel) không đổi.",
                type: .error
            )
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    private func exportRules() {
        guard let text = currentSourceText else {
            ToastManager.shared.show(message: "Không có bộ rule \(scopeLabel) nào để xuất.", type: .error)
            return
        }
        let fileName = scope.isGlobal ? QuickTranslationRuleStore.ruleFileName : QuickTranslationRuleBookStore.ruleFileName
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sharedFile = SharedFile(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }
}

extension View {
    /// Gắn menu Nhập/Xuất/Xoá rule cho phạm vi `scope` vào view (thường là `List`).
    func quickTranslationRuleIOMenu(
        scope: QuickTranslationRuleScope,
        showingDisabled: Bool,
        onChanged: @escaping () -> Void
    ) -> some View {
        modifier(QuickTranslationRuleIOMenu(scope: scope, showingDisabled: showingDisabled, onChanged: onChanged))
    }
}
