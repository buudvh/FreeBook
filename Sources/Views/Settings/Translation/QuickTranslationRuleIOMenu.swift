import SwiftUI
import UniformTypeIdentifiers

/// Modifier **Nhập / Xuất / Xoá** cho rule của một phạm vi (riêng, tên chương hoặc chung).
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
    /// Mở sheet chọn truyện để chia sẻ **cả bộ** rule riêng. `nil` = không hiện mục đó.
    ///
    /// Sheet do **presenter** (`QuickTranslationRuleListView`) gắn trên body chính, không gắn ở đây:
    /// nội dung toolbar không phải chỗ đặt presenter.
    let onShareAll: (() -> Void)?

    struct SharedFile: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    /// Bộ chọn file "Nhập file rule" — chọn xong mới hiện popup chọn cách nhập kèm tên file (`dataImportFilePicker`).
    @State private var showingImporter = false
    @State private var showingDeleteConfirm = false
    @State private var sharedFile: SharedFile? = nil
    @State private var showingOptionsMenu = false // Ngăn kéo "…"

    @State var showingDisabledImporter = false
    @State var showingReenableConfirm = false
    @State var showingDeleteDisabledConfirm = false

    private var currentSourceText: String? {
        switch scope {
        case .global: return QuickTranslationRuleStore.shared.currentSourceText()
        case .chapterTitle: return QuickTranslationRuleChapterStore.shared.currentSourceText()
        case .book(let bookId): return QuickTranslationRuleBookStore.shared.currentSourceText(for: bookId)
        }
    }

    private var hasRuleFile: Bool {
        switch scope {
        case .global: return QuickTranslationRuleStore.shared.hasRuleFile
        case .chapterTitle: return QuickTranslationRuleChapterStore.shared.hasRuleFile
        case .book(let bookId): return QuickTranslationRuleBookStore.shared.hasRuleFile(for: bookId)
        }
    }

    var scopeLabel: String {
        scope.label.lowercased()
    }

    private var scopeLongLabel: String {
        "Rule \(scopeLabel)"
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Chỉ nút bật ngăn kéo nằm trong toolbar; ngăn kéo gắn lên body chính như các presenter khác.
                    Button {
                        showingOptionsMenu = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .sideDrawerMenu(isPresented: $showingOptionsMenu, title: showingDisabled ? "\(scopeLongLabel) đã tắt" : scopeLongLabel) {
                if showingDisabled {
                    disabledRuleMenuItems
                } else {
                    SideDrawerActionRow("Nhập file rule (.txt)", systemImage: "square.and.arrow.down") { showingImporter = true }
                    // Một file, đã bỏ rule đang tắt (`QuickTranslationRuleExporter`) — không còn xuất danh sách tắt riêng.
                    SideDrawerActionRow("Xuất bộ rule \(scopeLabel)", systemImage: "square.and.arrow.up") { exportRules() }
                        .disabled(!hasRuleFile)
                    if scope.bookId != nil, let onShareAll {
                        SideDrawerActionRow("Chia sẻ bộ rule riêng sang truyện khác…", systemImage: "arrowshape.turn.up.right") {
                            onShareAll()
                        }
                        .disabled(!hasRuleFile)
                    }
                    SideDrawerActionRow("Xoá bộ rule \(scopeLabel)", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                    .disabled(!hasRuleFile)
                }
            }
            // Chọn file trước, popup chọn cách nhập hiện sau kèm tên file.
            .dataImportFilePicker(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText, .text],
                title: "Nhập bộ rule \(scopeLabel)"
            ) { url, mode in
                readImport(from: url, mode: mode)
            }
            .dataImportFilePicker(
                isPresented: $showingDisabledImporter,
                allowedContentTypes: [.plainText, .text],
                title: "Nhập danh sách rule tắt (bộ \(scopeLabel))"
            ) { url, mode in
                readDisabledImport(from: url, mode: mode)
            }
            .sheet(item: $sharedFile) { file in
                ShareSheet(activityItems: [file.url]) { _, completed, _, error in
                    if completed {
                        ToastManager.shared.show(message: "Đã xuất bộ rule \(scopeLabel).", type: .success)
                    } else if let error = error {
                        ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                    }
                }
            }
            .confirmationDialog(
                "Xoá bộ rule \(scopeLabel)\(scope.bookId == nil ? " khỏi máy" : " của truyện")?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Xoá bộ rule \(scopeLabel)", role: .destructive) {
                    let existed: Bool
                    switch scope {
                    case .global:
                        existed = QuickTranslationRuleStore.shared.deleteRules()
                    case .chapterTitle:
                        existed = QuickTranslationRuleChapterStore.shared.deleteRules()
                    case .book(let bookId):
                        existed = QuickTranslationRuleBookStore.shared.deleteRules(for: bookId)
                    }
                    ToastManager.shared.show(
                        message: existed ? "Đã xoá bộ rule \(scopeLabel)." : missingRuleSetMessage,
                        type: .info
                    )
                    onChanged()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                if scope.isGlobal {
                    Text("File \(QuickTranslationRuleStore.ruleFileName) sẽ bị xoá và việc dịch quay về thuần từ điển. Tải lại được bất cứ lúc nào.")
                } else if scope.isChapterTitle {
                    Text("File \(QuickTranslationRuleChapterStore.ruleFileName) sẽ bị xoá; tên chương quay về dịch bằng bộ riêng, bộ chung và từ điển. Hai bộ đó không bị ảnh hưởng.")
                } else {
                    Text("Truyện này sẽ quay về dùng thuần bộ rule chung. Bộ chung không bị ảnh hưởng.")
                }
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

    /// File + cách nhập đã chọn (popup hiện **sau** bộ chọn file) ⇒ đọc file rồi ghi luôn, toast "thêm X, cập nhật Y".
    private func readImport(from url: URL, mode: DataImportMode) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule (cần UTF-8).", type: .error)
            return
        }

        let preview = QuickTranslationRuleRecordStore.importCounts(current: currentSourceText ?? "", imported: text, mode: mode)
        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch scope {
        case .global:
            outcome = QuickTranslationRuleStore.shared.importRules(text: text, mode: mode)
        case .chapterTitle:
            outcome = QuickTranslationRuleChapterStore.shared.importRules(text: text, mode: mode)
        case .book(let bookId):
            outcome = QuickTranslationRuleBookStore.shared.importRules(text: text, mode: mode, bookId: bookId)
        }

        switch outcome {
        case .success(let ruleCount, let warningCount):
            let suffix = warningCount > 0 ? ", \(warningCount) cảnh báo" : ""
            let counts = mode == .replaceAll
                ? "thay toàn bộ"
                : "thêm \(preview.added), cập nhật \(preview.updated)"
            ToastManager.shared.show(
                message: "Đã nhập (\(counts)) — bộ \(scopeLabel) hiện có \(ruleCount) rule\(suffix).",
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

    /// Xuất một file đã bỏ rule đang tắt của bộ này.
    private func exportRules() {
        switch QuickTranslationRuleExporter.writeTemporaryFile(scope: scope) {
        case .file(let url, _, _):
            sharedFile = SharedFile(url: url)
        case .noRuleSet:
            ToastManager.shared.show(message: "Không có bộ rule \(scopeLabel) nào để xuất.", type: .error)
        case .allDisabled(let count):
            ToastManager.shared.show(message: "Cả \(count) rule \(scopeLabel) đang tắt — không có rule nào để xuất.", type: .info)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    /// Toast khi bấm xoá cả bộ mà máy chưa có file của phạm vi này.
    private var missingRuleSetMessage: String {
        switch scope {
        case .global: return "Máy chưa có bộ rule nào."
        case .chapterTitle: return "Máy chưa có bộ rule tên chương."
        case .book: return "Truyện này chưa có bộ rule riêng."
        }
    }
}

extension View {
    /// Gắn menu Nhập/Xuất/Xoá rule cho phạm vi `scope` vào view (thường là `List`).
    func quickTranslationRuleIOMenu(
        scope: QuickTranslationRuleScope,
        showingDisabled: Bool,
        onShareAll: (() -> Void)? = nil,
        onChanged: @escaping () -> Void
    ) -> some View {
        modifier(QuickTranslationRuleIOMenu(
            scope: scope,
            showingDisabled: showingDisabled,
            onChanged: onChanged,
            onShareAll: onShareAll
        ))
    }
}
