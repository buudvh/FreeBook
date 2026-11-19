import SwiftUI

/// Import truyện từ trình duyệt đôi khi báo "Không tìm thấy tiện ích bóc tách của truyện này!", bấm "Thử lại" thì được
/// (anh Bửu, 2026-11-20). Chi tiết tra tiện ích (`ext`) **đúng một lần** lúc màn hiện và báo lỗi ngay — trong khi lát sau
/// tra lại thì có: màn được dựng trước khi mã tiện ích của lượt Import kịp tới, hoặc danh mục tiện ích đang dựng lại đúng lúc
/// đó (log chưa ghi đủ để phân biệt).
///
/// Nay: chưa tra được tiện ích thì **chưa báo lỗi** — giữ vòng xoay đang tải, chờ tối đa `extensionWaitTimeout`; tiện ích
/// xuất hiện (mã tiện ích của màn đổi, hoặc danh mục có thêm — `.onChange(of: ext?.localPath)` ở `BookDetailView`) ⇒ nạp
/// luôn phần đang chờ. Hết giờ mới báo lỗi như cũ, kèm log ❌ (mã tiện ích, số tiện ích đã cài / trong danh mục). Đã báo lỗi
/// mà sau đó tiện ích mới có ⇒ tự nạp lại, khỏi bấm "Thử lại". Tiện ích thật sự đã gỡ thì lỗi hiện chậm ~1,5 s.
extension BookDetailView {
    enum ExtensionWaitTarget: Hashable {
        case detail
        case toc
    }

    static let missingExtensionMessage = "Không tìm thấy tiện ích bóc tách của truyện này!"
    private static let extensionWaitTimeout: UInt64 = 1_500_000_000

    /// Nhánh "không có `ext`" của `loadBookDetailOnly` / `loadTOCDataOnly`: chờ tiện ích thay vì báo lỗi ngay.
    func waitForExtension(_ target: ExtensionWaitTarget) {
        switch target {
        case .detail:
            isLoadingDetail = true
            setDetailError("")
        case .toc:
            isLoadingTOC = true
            setTOCError("")
        }
        let isFirstWaiter = extensionWaitTargets.isEmpty
        extensionWaitTargets.insert(target)
        guard isFirstWaiter else { return }
        let packageId = extensionPackageId
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.extensionWaitTimeout)
            // Tiện ích đã tới (`reloadIfExtensionAppeared` đã dọn tập chờ) ⇒ thôi.
            guard !extensionWaitTargets.isEmpty else { return }
            let targets = extensionWaitTargets
            extensionWaitTargets = []
            let repository = ExtensionLibraryRepository.shared
            AppLogger.shared.log(
                "❌ [BookDetail] Không tìm thấy tiện ích bóc tách sau \(Self.extensionWaitTimeout / 1_000_000) ms: "
                    + "packageId=\(packageId.isEmpty ? "(rỗng)" : packageId) đã cài=\(repository.installed.count) "
                    + "danh mục=\(repository.catalog.count) "
                    + "có trong đã cài=\(repository.installedExtension(packageId: packageId) != nil ? "có" : "không")"
            )
            if targets.contains(.detail) {
                setDetailError(Self.missingExtensionMessage)
                isLoadingDetail = false
            }
            if targets.contains(.toc) {
                setTOCError(Self.missingExtensionMessage)
                isLoadingTOC = false
            }
        }
    }

    /// `.onChange(of: ext?.localPath)`: tiện ích vừa tra được ⇒ nạp phần đang chờ, hoặc phần đã báo lỗi "không tìm thấy".
    func reloadIfExtensionAppeared() {
        guard let ext, !ext.localPath.isEmpty else { return }
        var targets = extensionWaitTargets
        if detailErrorMessage == Self.missingExtensionMessage { targets.insert(.detail) }
        if tocErrorMessage == Self.missingExtensionMessage { targets.insert(.toc) }
        guard !targets.isEmpty else { return }
        extensionWaitTargets = []
        AppLogger.shared.log("ℹ️ [BookDetail] Đã tra được tiện ích \(ext.packageId) sau khi chờ ⇒ nạp lại \(targets.count) phần")
        if targets.contains(.detail) { loadBookDetailOnly() }
        if targets.contains(.toc) { loadTOCDataOnly() }
    }
}
