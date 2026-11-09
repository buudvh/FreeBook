import Foundation

/// Ghi chú thay đổi của **bản đang chạy** cho sheet "Có gì mới ở bản này" (nút "?" ở Cài đặt › Thông Tin, 1.3.810).
///
/// Thứ tự nguồn:
/// 1. `ReleaseNotes.txt` trong bundle app — CI (`build-ipa.yml`, bước đóng gói IPA) ghi danh sách commit của lượt build
///    (`- <subject>` mỗi dòng, bỏ dòng trùng — cùng định dạng ghi chú release / `apps.json`). Bản build tay không có file.
/// 2. `apps.json` của nguồn cập nhật (`AppUpdateSourceClient.fetchVersion`), bản có `buildVersion` = `CFBundleVersion`
///    đang chạy — nguồn chỉ giữ 5 bản gần nhất.
/// 3. Không có ⇒ mảng rỗng (sheet hiện "Không còn ghi chú cho bản này").
enum AppReleaseNotesLoader {
    static let bundledFileName = "ReleaseNotes"

    /// Dòng ghi chú trong bundle; thiếu file / đọc lỗi / rỗng ⇒ `[]`.
    static func bundledNotes() -> [String] {
        guard let url = Bundle.main.url(forResource: bundledFileName, withExtension: "txt") else { return [] }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return AppUpdateInfo.notes(fromDescription: text)
        } catch {
            AppLogger.shared.log("❌ [AppUpdate] Không đọc được \(bundledFileName).txt trong bundle: \(error.localizedDescription)")
            return []
        }
    }

    /// Bundle trước, không có thì hỏi nguồn cập nhật theo số build đang chạy. Không bao giờ ném lỗi — lỗi mạng chỉ log.
    static func load() async -> [String] {
        let bundled = bundledNotes()
        if !bundled.isEmpty { return bundled }
        guard let build = Int((AppVersionInfo.buildNumber ?? "").trimmingCharacters(in: .whitespaces)), build > 1 else {
            // Bản build tay mang số build mặc định 1 — nguồn cập nhật không có bản này.
            return []
        }
        do {
            let notes = try await AppUpdateSourceClient.fetchVersion(build: build)?.notes ?? []
            AppLogger.shared.log("🆕 [AppUpdate] Ghi chú bản đang chạy từ nguồn cập nhật: \(notes.count) dòng (build \(build))")
            return notes
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [AppUpdate] Không lấy được ghi chú bản \(build) từ nguồn cập nhật: \(error.localizedDescription)")
            }
            return []
        }
    }
}
