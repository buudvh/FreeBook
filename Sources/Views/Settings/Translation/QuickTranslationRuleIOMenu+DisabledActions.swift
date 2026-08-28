import Foundation
import SwiftUI

/// Phần thao tác cho tab **Đã tắt** của menu rule chung, tách file để modifier chính không vượt 400 dòng.
@MainActor
extension QuickTranslationRuleIOMenu {
    var currentDisabledPatterns: [String] {
        switch scope {
        case .global: return QuickTranslationRuleDisableStore.shared.disabledPatterns(for: .global)
        case .book(let bookId): return QuickTranslationRuleDisableStore.shared.disabledPatterns(for: .book(bookId))
        }
    }

    var isDisabledListEmpty: Bool { currentDisabledPatterns.isEmpty }

    @ViewBuilder
    var disabledRuleMenuItems: some View {
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
        .disabled(isDisabledListEmpty)

        Button {
            showingReenableConfirm = true
        } label: {
            Label("Bật lại tất cả rule đã tắt", systemImage: "play.circle")
        }
        .disabled(isDisabledListEmpty)

        Button(role: .destructive) {
            showingDeleteDisabledConfirm = true
        } label: {
            Label("Xoá tất cả rule đã tắt", systemImage: "trash")
        }
        .disabled(isDisabledListEmpty)
    }

    func readDisabledImport(from url: URL?) {
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

    func applyDisabledImport(mode: DataImportMode) {
        guard let imported = pendingDisabledPatterns else { return }
        pendingDisabledPatterns = nil

        let outcome = QuickTranslationRuleDisableStore.shared.importPatterns(
            imported: imported,
            mode: mode,
            scope: scope
        )
        switch outcome {
        case .success:
            ToastManager.shared.show(
                message: "Đã nhập — đang tắt \(QuickTranslationRuleDisableStore.shared.disabledPatterns(for: scope).count) mẫu ở bộ \(scopeLabel).",
                type: .success
            )
            onChanged()
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    func exportDisabledRules() {
        let text = QuickTranslationRuleDisableFile.serialize(currentDisabledPatterns)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(QuickTranslationRuleDisableStore.fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sharedDisabledFile = SharedFile(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }

    func reenableAllDisabledRules() {
        let outcome = QuickTranslationRuleDisableStore.shared.clearDisabled(scope: scope)
        switch outcome {
        case .success:
            ToastManager.shared.show(message: "Đã bật lại mọi rule trong bộ \(scopeLabel).", type: .success)
            onChanged()
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    func deleteAllDisabledRules() {
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
            let clearOutcome = QuickTranslationRuleDisableStore.shared.clearDisabled(scope: scope)
            if case .failure(let msg) = clearOutcome {
                ToastManager.shared.show(message: "Đã xoá \(patterns.count) rule, nhưng không dọn được danh sách tắt: \(msg)", type: .info)
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
