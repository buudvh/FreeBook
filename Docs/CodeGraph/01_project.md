---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 2
---

# Kiến trúc Tổng thể & Quy tắc Thiết kế

Tài liệu này phác thảo kiến trúc tổng thể, sơ đồ thư mục, các tính năng cốt lõi và các quy tắc kiến trúc đang được áp dụng trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Pham vi moi: app co mot server LAN, chi bat bang tay (1.3.303)

* **Day la lan dau app mo mot cong nghe.** Truoc 1.3.303 moi thu la client. Nay co `NWListener` + Bonjour, nen `project.yml` phai khai `NSLocalNetworkUsageDescription` va `NSBonjourServices` (`_freebook-extdebug._tcp`) - hai khoa Info.plist dau tien lien quan mang noi bo.
* **Threat model di kem, khong phai tuy chon**: mac dinh tat, chi bat bang thao tac trong Cai Dat, foreground-only (`MainTabView` tat khi roi foreground), port ngau nhien, toi da mot client, token dung mot lan + het han 3 phut, va phai xac nhan tren thiet bi. Xem `10_risk_report`.
* **Them mot thu muc du lieu**: `applicationSupportDirectory/extension-drafts/` cho snapshot nhap va `.backup/` cho ban truoc khi cai. Ca hai la du lieu tam - staging bi xoa sach moi lan mo app; `.backup` giu toi lan cai ke tiep de rollback duoc.
* **Them mot package khong thuoc build iOS**: `Tools/VSCode/FreeBookExtDebug` (TypeScript). CI hien tai chi `xcodegen` + `xcodebuild`, nen package nay **khong duoc bien dich boi CI** - trang thai do la co y va duoc ghi o README cua no.

## Architecture & Refactor Summary (v4.1/v4.2/v5.0)

Dự án FreeBook đã hoàn tất tái cấu trúc kiến trúc v4.1/v5.0 với các điểm chính:
1. **Phân tách Monolith & Trích xuất File**:
   - `TTSManager.swift` được tách thành các file mở rộng chuyên biệt trong `Sources/Services/TTS/Extensions/` (`TTSManager+Playback`, `+NowPlaying`, `+Interruption`, `+PrefetchCache`, `+NghiEnergy`, `+Telemetry`) cùng với `TTSAudioEngineController` và `DisplayTextFormatter`.
   - Trình đọc `ReaderView.swift` & `ReaderViewModel.swift` trích xuất `ReaderScrollCoordinator`, `ReaderSelectionCoordinator`, `ReaderProgressScheduler`, và các extension theo nhóm chức năng.
   - Quản lý kho `RepositoryManagerView.swift` trích xuất `RepositoryFilterPolicy`, `RepositoryManagerView+Actions`, `RepositoryManagerView+RepoOps`.
   - Tiền xử lý chi tiết sách `BookDetailView.swift` trích xuất `BookDetailLoader`, `BookDetailView+TOCPreparation`, `BookDetailView+Extensions`.
   - Xử lý văn bản & dịch thuật `TranslateUtils.swift` trích xuất `TranslateUtils+Tokenization` và `VietPhraseTokenizer`.
2. **Loại bỏ SwiftData Mutations trong View Layer**:
   - SwiftUI Views không được thực hiện các thao tác ghi trực tiếp (`modelContext.insert`, `delete`, `save` hoặc gán thuộc tính `@Model`).
   - Mọi thao tác ghi được chuyển giao cho `BookTransactionCoordinator` và `ExtensionTransactionCoordinator` thông qua các Command DTO bất biến (`AddBookToShelfCommand`, `UpsertExtensionCommand`, `ExtensionConfigCommand`, `UpdateExtensionFolderCommand`).
3. **Luồng Sự Kiện Presentation (Presentation Event Center)**:
   - Các Service tầng dưới (`TTSManager`, `DownloadManager`) phát sự kiện giao diện thông qua `AsyncStream` Event Centers (`TTSPresentationEventCenter`, `DownloadPresentationEventCenter`).
   - `AppLaunchRootView` (`FreeBookApp.swift`) là điểm duy nhất trong ứng dụng đăng ký lắng nghe và hiển thị Toast trên UI.
4. **Hệ Thống Kiểm Tra Kiến Trúc Fail-Closed**:
   - `Scripts/check_architecture.py` (v2 fail-closed schema validation) kiểm tra giới hạn dòng (<= 400 dòng cho file mới), 1 loại chính/file, cấm ghi `@Model` trong View, và cấm Service phụ thuộc direct ToastManager/SwiftUI.
5. **Phân hệ Sao lưu/Khôi phục (1.3.246)** — `Sources/Services/Backup/` (+ `GoogleDrive/`) và `Sources/Views/Settings/Backup/`:
   - Tuân thủ đúng chiều phụ thuộc đã có: View → `BackupCoordinator` (`@MainActor ObservableObject`) → actor worker (`BackupExportWorker`, `BackupRestoreWorker`, `GoogleDriveUploader`, `GoogleDriveClient`) → store/repository sẵn có (`ChapterStore`, `BookBinManager`, `DictionaryTextFileStore`, `TranslationManager`).
   - **Không mở đường ghi SwiftData mới**: mọi thay đổi thư viện đi qua `BookTransactionCoordinator` / `ExtensionTransactionCoordinator` với Command DTO bất biến, gom trong `BackupLibraryWriter` (`@MainActor`); `EditBookInfoCommand` là DTO mới duy nhất của lần này.
   - Giữ luật tầng Service: `Sources/Services/Backup/**` không `import SwiftUI` và không gọi `ToastManager.shared` — tiến độ đi ra ngoài bằng `@Published` của coordinator, toast do `BackupHubView` hiển thị.
   - Điểm nạp cấu hình bí mật thứ hai của app, cùng cơ chế với Google TTS: `GOOGLE_DRIVE_CLIENT_ID` (GitHub secret → build setting → Info.plist) với override `UserDefaults("googleDriveClientId")`; thiếu cấu hình thì chỉ tắt kênh Drive, không ảnh hưởng kênh backup local.
6. **Lượt nền định kỳ và appearance toàn cục (1.3.260)**:
   - Lượt **tự động** sao lưu Drive dùng lại đúng khuôn của lượt kiểm tra chương mới: chính sách chạy nằm trong một `enum` UserDefaults (`DriveAutoBackupPolicy`), thân việc nằm ở extension của coordinator (`BackupCoordinator+AutoDrive`) và **trả về** outcome, còn `MainTabView` là nơi duy nhất hoãn qua lúc khởi động rồi hiện toast — Service vẫn không gọi `ToastManager`.
   - `FreeBookApp.init()` là chỗ duy nhất cấu hình appearance proxy UIKit toàn app (`UITabBar`, và từ 1.3.260 thêm `NavigationBarAppearance.applyTitlelessBackButton()` để nút back mọi màn chỉ còn mũi tên). Đây là hiệu ứng toàn cục, không đặt trong View nào.
7. **Cầu UIKit mới cho Reader và lệnh dọn dữ liệu kho (1.3.261)**:
   - `Sources/Views/Reader/Components/` nhận cầu UIKit thứ ba (`ReaderUserScrollDetector`) bên cạnh `ReaderViewModelInvalidationRelay` và `ReaderEnergyDiagnostics`. Nó là `UIViewRepresentable` **không tiêu thụ touch**: gắn `UIPanGestureRecognizer` lên `UIScrollView` bao ngoài chỉ để *quan sát* ngón tay, nên `UITextView` (bôi đen chữ) và pan của chính scroll view giữ nguyên hành vi. Đây là cách duy nhất phân biệt "người cuộn" với cú `ScrollViewProxy.scrollTo` của TTS — quan sát `contentOffset` thì hai thứ đó không khác gì nhau.
   - Kho tiện ích có lệnh **xoá** đầu tiên đi qua Command DTO: `PruneRepositoryExtensionsCommand` + `ExtensionTransactionCoordinator.pruneRepositoryExtensions`. Giữ nguyên luật tầng View (`Sources/Views/**` không `modelContext.delete`) và giữ nguyên hình dạng "một `save()` cho một lượt đồng bộ" — prune là transaction thứ hai, chạy **sau** khi upsert `.success`.
8. **Phân hệ rule dịch Quick Translate (1.3.269)** — `Sources/Services/Translation/Engine/QuickTranslation*.swift` + `Sources/Views/Settings/Translation/QuickTranslation*.swift`:
   - Chiều phụ thuộc không mở đường mới: View → `QuickTranslationRuleStore` (`ObservableObject`, chỉ `import Foundation`/`Combine`) → parser/compiler/matcher thuần Foundation → `TrieDictionary` + `TranslationManager` (tầng Models/Services sẵn có). Không `@Model` nào liên quan nên không có mutation SwiftData.
   - Giữ luật tầng Service: `Sources/Services/Translation/Engine/**` **không** `import SwiftUI` và **không** gọi `ToastManager.shared` — `importRules`/`resetToBundled` trả `LoadOutcome`, `QuickTranslationRulesView` dịch sang toast.
   - Chủ sở hữu duy nhất của bộ rule chung là `QuickTranslationRuleStore`; bộ rule riêng theo truyện thuộc `QuickTranslationRuleBookStore`. Bộ rule **không** đi kèm app: file nằm ở `translate/QuickTranslateRules.txt` hoặc `translate/books/<bookId>/QuickTranslateRules.txt`. Mọi đường ghi đều canonical hoá qua `QuickTranslationRuleRecordStore`: bỏ dòng hỏng, duplicate first-wins, ghi lại `pattern = replacement` rồi phát `generation` đi vào cache dịch.
   - Điểm mở rộng của phân hệ dịch, không phải nhánh song song: rule chạy trong `performTranslation` nên mọi caller cũ (Reader, TTS, export, backfill tiêu đề) hưởng cùng lúc; đường Qt bridge của extension bị loại tường minh bằng tham số `applyingQuickTranslationRules: false`.
<!-- GENERATED END -->
