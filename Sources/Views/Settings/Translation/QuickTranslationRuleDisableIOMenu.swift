import SwiftUI
import UniformTypeIdentifiers

/// Menu **Nhập / Xuất / Bật lại / Xoá** cho danh sách rule tắt của một phạm vi (riêng hoặc chung).
///
/// Tách riêng khỏi `QuickTranslationRuleIOMenu` để mỗi ViewModifier chỉ lo một loại dữ liệu
/// (bộ rule vs danh sách tắt), giữ file < 400 dòng. Áp lên `List` chính cùng lượt với IO menu rule.
struct QuickTranslationRuleDisableIOMenu: ViewModifier {
    let scope: QuickTranslationRuleScope
    let onChanged: () -> Void

    private struct SharedFile: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @ObservedObject private var store = QuickTranslationRuleStore.shared
    @ObservedObject private var bookStore = QuickTranslationRuleBookStore.shared
    @ObservedObject private var disableStore = QuickTranslationRuleDisableStore.shared

    @State private var showingDisabledImporter = false
    @State private var showingDisabledImportModes = false
    @State private var pendingDisabledPatterns: [String]? = nil
    @State private var pendingDisabledPreview: (added: Int, overlapping: Int, machineOnly: Int) = (0, 0, 0)
    @State private var sharedDisabledFile: SharedFile? = nil

    @State private var showingReenableConfirm = false
    @State private var showingDeleteDisabledConfirm = false

    private var currentDisabledPatterns: [String] {
        switch scope {
        case .global: return disableStore.disabledPatterns(for: .global)
        case .book(let bookId): return disableStore.disabledPatterns(for: .book(bookId))
        }
    }

    private var isEmpty: Bool { currentDisabledPatterns.isEmpty }

    private var scopeLabel: String { scope.isGlobal ? "chung" : "riêng" }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Divider()

                        Button {
                            showingDisabledImporter = true
                        } label: {
                            Label("Nhập file rule tắt (.txt)", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            exportDisabledRules()
                        } label: {
                            Label("Xuất danh sách rule tắt", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isEmpty)

                        Button {
                            showingReenableConfirm = true
                        } label: {
                            Label("Bật lại tất cả rule đã tắt", systemImage: "play.circle")
                        }
                        .disabled(isEmpty)

                        Button(role: .destructive) {
                            showingDeleteDisabledConfirm = true
                        } label: {
                            Label("Xoá tất cả rule đã tắt", systemImage: "trash")
                        }
                        .disabled(isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .background(
                DocumentPickerPresenter(
                    isPresented: $showingDisabledImporter,
                    allowedContentTypes: [.plainText, .text],
                    allowsMultipleSelection: false,
                    onPick: { urls in readDisabledImport(from: urls.first) },
                    onCancel: nil
                )
            )
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
                    let outcome = disableStore.clearDisabled(scope: scope)
                    switch outcome {
                    case .success:
                        ToastManager.shared.show(message: "Đã bật lại mọi rule trong bộ \(scopeLabel).", type: .success)
                        onChanged()
                    case .failure(let message):
                        ToastManager.shared.show(message: message, type: .error)
                    }
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

    private func readDisabledImport(from url: URL?) {
        guard let url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule tắt (cần UTF-8).", type: .error)
            return
        }

        let imported = QuickTranslationRuleDisableFile.parse(text)
        pendingDisabledPatterns = imported
        pendingDisabledPreview = QuickTranslationRuleDisableFile.importPreview(
            current: currentDisabledPatterns,
            imported: imported
        )
        showingDisabledImportModes = true
    }

    private func applyDisabledImport(mode: DataImportMode) {
        guard let imported = pendingDisabledPatterns else { return }
        pendingDisabledPatterns = nil

        let outcome = disableStore.importPatterns(
            imported: imported,
            mode: mode,
            scope: scope
        )
        switch outcome {
        case .success:
            ToastManager.shared.show(
                message: "Đã nhập — đang tắt \(disableStore.disabledPatterns(for: scope).count) mẫu ở bộ \(scopeLabel).",
                type: .success
            )
            onChanged()
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    private func exportDisabledRules() {
        let text = QuickTranslationRuleDisableFile.serialize(currentDisabledPatterns)
        let fileName = QuickTranslationRuleDisableStore.fileName
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sharedDisabledFile = SharedFile(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }

    private func deleteAllDisabledRules() {
        let patterns = Set(currentDisabledPatterns)
        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch scope {
        case .global:
            outcome = QuickTranslationRuleStore.shared.deleteRules(patterns: patterns)
        case .book(let bookId):
            outcome = QuickTranslationRuleBookStore.shared.deleteRules(patterns: patterns, bookId: bookId)
        }

        switch outcome {
        case .success(let ruleCount, _):
            let clearOutcome = disableStore.clearDisabled(scope: scope)
            if case .failure(let msg) = clearOutcome {
                ToastManager.shared.show(message: "Đã xoá \(patterns.count) rule, nhưng không dọn được danh sách tắt: \(msg)", type: .warning)
            } else {
                ToastManager.shared.show(message: "Đã xoá \(patterns.count) rule đã tắt. Bộ \(scopeLabel) còn \(ruleCount) rule.", type: .success)
            }
            onChanged()
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(message: "File còn lỗi nặng (\(detail)); không xoá được.", type: .error)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }
}

extension View {
    /// Gắn menu Nhập/Xuất/Bật lại/Xoá danh sách rule tắt cho phạm vi `scope` vào view (thường là `List`).
    func quickTranslationRuleDisableIOMenu(
        scope: QuickTranslationRuleScope,
        onChanged: @escaping () -> Void
    ) -> some View {
        modifier(QuickTranslationRuleDisableIOMenu(scope: scope, onChanged: onChanged))
    }
}