# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.529] - 2026-10-16

### feat: luu tien ich va kho bang JSON thay SwiftData, sap xep ghim/vua dung, loc chip chon nhieu

Người dùng: *"tối ưu lại cách lưu tiện ích (cả data lẫn metadata), danh sách kho, không lưu swiftdata nữa"* → phỏng vấn `grill-me` (tham khảo cấu trúc backup vbook iPhone), plan đã duyệt: `Docs/Plans/2026-10-16-plan-extension-store-json.md`; contract API giữa các nhánh: `Docs/Plans/2026-10-16-extension-store-phase1-api.md`.

- **Gỡ `@Model Extension` và `@Model Repository` khỏi schema** (`FreeBookApp.swift`: còn 4 model `Book`, `BookCollection`, `Chapter`, `DownloadTaskModel`). Dữ liệu tiện ích/kho chuyển sang `applicationSupport/extension_store/`: `installed.json` (index **chỉ tiện ích đã cài**, đường dẫn **tương đối** `folder`), `repositories.json`, `registry/<sha256(url)>.json` (cache registry, tiện ích chưa cài chỉ hiện từ đây), `local_storage.json`. Script/icon vẫn là file trong `extensions/<folder>/` — đo trên 39 tiện ích thật: nhét script+icon vào index như vbook là 5,28 MB, index slim ~53 KB.
- **Tầng mới** `Sources/Services/Extensions/Store/` (9 file, đều ≤ 306 dòng): `ExtensionLibraryRepository` (`@MainActor @Observable`, nguồn sự thật; `catalog` = đã cài ∪ registry chưa cài; tầng nền đọc qua `nonisolated static` + `ExtensionLibrarySnapshotTable` có lock), `ExtensionIndexStore`/`ExtensionStoreFileIO` (ghi atomic trên queue nền, file hỏng bị cách ly `.corrupt-<ts>`), `ExtensionLocalStorageStore`, `ExtensionStorePaths`, `ExtensionStoreEnvelope` (`schemaVersion: 1`). Model value type mới ở `Sources/Models/Extensions/`: `Extension` (struct, `pinnedAt`/`lastUsedAt`, `remoteVersion` transient), `ExtensionRepositoryRecord`, `ExtensionRegistrySnapshot`, `ExtensionRegistryItem` (chuyển khỏi `ExtensionManager.swift`), `ExtensionFolderLocator`. Bỏ `isEnabled` (không có chỗ nào bật/tắt).
- **`ExtensionTransactionCoordinator` viết lại** trên repository, bỏ tham số `in context:`; thêm `saveRegistry`, `markUsed`, `uninstallExtension`, `auditInstalledExtensions`; xoá `pruneRepositoryExtensions`, `updateExtensionFolder`, `touchRepositoryLastUpdated`, `repairExtensionPathsAtLaunch`, `applyInstallAudit`. Xoá `ExtensionPathResolver` (đường dẫn tương đối ⇒ hết lớp lỗi đổi gốc thư mục 1.3.523), `PruneRepositoryExtensionsCommand`, `UpdateExtensionFolderCommand`; `ExtensionInstallAudit` rút gọn; `ExtensionSyncCommandBuilder` 169 → 18 dòng (chỉ giữ `packageId(forName:)`).
- **Migrate một lần** (`LegacyExtensionSQLiteMigrator` + `LegacyExtensionSQLiteReader`, chạy trong `FreeBookApp.init` **trước** `ModelContainer`): `wal_checkpoint` → `VACUUM INTO extension_store/legacy/library-pre-ext.sqlite` (chép cả DB, gồm sách — lưới an toàn), đọc sqlite thô `ZEXTENSION`/`ZREPOSITORY` theo tên cột (thiếu cột ⇒ log `❌` + giữ bản chép để bản sau đọc lại), chỉ lấy tiện ích đã cài, chuyển khoá `UserDefaults` `vbook_ext_storage_<md5(localPath)>_*` sang `local_storage.json` theo `packageId`; cờ `migratedFromLegacy` ghi cuối cùng.
- **Làm mới kho = 1 request registry/kho** (bỏ tải `plugin.json` cho từng tiện ích chưa cài, ~95 request với kho 100 tiện ích). Kho chưa có cache vẫn được tải trong cooldown. `hasUpdate` tính bằng cách ghép cache registry của **đúng** kho `repositoryUrl` (không fallback kho khác — tiện ích zip/debug không bị báo cập nhật sai), không lưu `remoteVersion`.
- **Thứ tự ghim (`pinnedAt` tăng) → vừa dùng (`lastUsedAt` giảm) → A-Z** (`ExtensionSortPolicy` mới) ở chọn nguồn Khám phá và tab "Tất cả tiện ích" (sau nhóm có cập nhật → đã cài). `markUsed` khi chọn nguồn, tìm kiếm **một** nguồn, mở chi tiết truyện (`BookDetailView.onAppear`).
- **Sheet "Bộ lọc tiện ích" dạng chip chọn nhiều** (`FilterSheet.swift` dùng `FlowLayout`; luật HOẶC trong nhóm, VÀ giữa nhóm, rỗng = tất cả); khoá mới `extFilterTypes/extFilterLocales/extFilterAuthors` (JSON), tự đọc khoá cũ lần đầu (`ExtensionFilterSelection`).
- **Gỡ tiện ích = xoá sạch** config/ghim/`localStorage`; cập nhật giữ nguyên. `localStorage` của JS (`JSExecutor`) khoá theo namespace `packageId` / `"global"` / `"path:"+md5` qua `ExtensionLocalStorageStore` (ghi gom ~2 s, flush khi vào nền).
- **Backup**: entry mới `library/extension_local_storage.json` (nhóm `.extensions`; restore chỉ thêm namespace máy chưa có); `ExtensionRecord` thêm `pinnedAt?`/`lastUsedAt?` nhưng vẫn ghi `isEnabled`/`isPinned` cho app cũ; `extensions.json` chỉ còn tiện ích đã cài; `BackupSettingsArchiver` chặn tiền tố `vbook_ext_storage_`; fingerprint (`formatVersion` 3) bỏ `lastUsedAt` và `localStorage` để duyệt nguồn / token JS tự làm mới không kích auto-backup.
- **~25 consumer** (Reader, Kệ sách, Bypass, TTS settings, Config, Script Editor, DownloadManager, Debug server…) chuyển từ `@Query`/`FetchDescriptor` sang repository; View giữ `Extension` tra lại theo `packageId` sau khi ghi (`ReaderViewModel` bỏ `cachedExt`, `ExtensionMetadataSection` hết ghi đè tên cũ).
- **Tài liệu**: `rules.md` thêm mục "Extension store invariants (1.3.529)" và sửa các đoạn còn nói SwiftData/plugin.json-per-extension; `CLAUDE.md`/`AGENTS.md` cập nhật bootstrap, thư mục lưu trữ, số violation thật (2).
- **Kiểm chứng**: `check_architecture.py` **2 violation, 0 mới**. Triển khai bằng 1 agent nền móng + 3 session song song + 1 agent rà soát chéo. **Không build tại chỗ** (Windows, không có `swiftc`) — CI xác nhận biên dịch. Rủi ro chính: lightweight migration của SwiftData khi gỡ 2 entity (nếu `ModelContainer` lỗi thì `fatalError`); tên bảng/cột nội bộ là giả định — chỉ kiểm chứng được bằng IPA trên máy thật.
- **Còn lại**: `ttsExtensionLocalPath` (`TTSManager`) vẫn là đường dẫn tuyệt đối; thời điểm xoá `legacy/library-pre-ext.sqlite` chưa chốt.

## [1.3.528] - 2026-10-16

### feat: them bo giai ma script extension Vbook (AES-256-CBC) luc cai dat

Người dùng: dán một JSON `script_data` gồm 10 file `.js` đã mã hoá nhờ decode, rồi yêu cầu *"thêm bộ giải mã vào app để giải mã những script bị mã hoá như thế này"* → phỏng vấn `grill-me` 6 câu, plan đã duyệt: `Docs/Plans/2026-10-15-plan-extension-script-decoder.md`.

- **File mới** `Sources/Services/Extensions/Manager/ExtensionScriptDecoder.swift` (226 dòng, 1 type `enum`, chỉ `import CommonCrypto` / `CryptoKit` / `Foundation`): bỏ token `x0P1Xx` / `x0P2Xx` / `x0P3Xx` về `+` `/` `=` rồi giải **AES-256-CBC** (IV 16 byte `0x00`, padding PKCS#7), key `SHA256(MD5("com.vbook.app" + source + author) dạng hex)`. CryptoKit không có AES-CBC nên dùng CommonCrypto.
- **Móc 2 dòng** vào `ExtensionManager.swift`, ngay sau `findMainExtensionFolder` ở **cả hai** luồng cài — `install(item:packageId:)` và `installFromLocalZip(fileUrl:)`. File 1003 → **1005** dòng (baseline `FILE_SIZE_LIMIT` 1022): toàn bộ logic nằm trong file mới, không nhồi thêm vào file legacy.
- **Cách ghi**: ghi đè nội dung file script (giữ nguyên tên) + đặt `encrypt = false` trong `plugin.json` ⇒ bản đồ `script` không phải sửa, runtime và editor đọc bản rõ luôn, **không giải mã lại ở mỗi lần chạy**.
- **Chốt phạm vi** (đã phỏng vấn): chỉ dùng công thức chuẩn — không ma trận biến thể key, không giải nén payload (tool chính thức của Vbook mã hoá JS thô), không nút giải mã thủ công / migration. File có token mà giải không ra JS ⇒ **ném lỗi để chặn cài**.
- **Kiểm chứng**: công thức đã đối chứng bằng dữ liệu thật 10 file của extension `hhtqvietsub` v10 — key `d476a9f7…292073`, ciphertext khớp **100% từng ký tự** với ZIP công bố của `Darkrai9x/vbook-extensions`. `check_architecture.py`: **2 violation, 0 mới**. `swiftc -parse` sạch cả 2 file. **Không build tại chỗ** (Windows) — CI xác nhận biên dịch.
- **Gap đã biết**: luồng khôi phục extension từ backup (`BackupExtensionInstaller`) chưa móc giải mã.

## [1.3.527] - 2026-10-14

### feat(ai): quet ten rieng giu mot chat Gemini, tu thu lai luot loi, nut thu lai, log chan doan

Người dùng: *"vẫn không cùng chat, thêm nút thử lại các batch lỗi sau khi chạy xong"*, *"tự động thử lại những cái lỗi ít nhất 1 lần"* (log `app_logs (107)` trên bản 1.3.526: lượt 3, 4, 6/15 lỗi `StreamGenerate lỗi sau ~244 000 ms, chunk=5` — Gemini vẫn đang trả lời chậm, request chạm **trần tuyệt đối 240 s**; lượt 1, 2, 5 xong; log thường đang tắt nên không thấy dòng quyết định nối tiếp/mở chat mới).
- **Một chat cho lượt quét (bắt buộc)**: phiên đã có chat Gemini thì lượt quét (`forceContext`) **không bao giờ** mở chat mới — nối tiếp bị từ chối thì chờ 5 s, gửi lại đúng lượt nối tiếp một lần (Google có thể còn đang viết nốt lượt app đã cắt), vẫn lỗi ⇒ tính lượt lỗi. Chỉ đổi model / đổi công tắc lưu lịch sử mới mở chat mới (log ❌ kèm lý do). Chat thường giữ hành vi cũ (bị từ chối ⇒ mở lại một lần).
- **Log chẩn đoán ❌** (luôn ghi dù tắt log): lượt quét mở chat mới dù phiên đã có chat (lý do: chưa có chat / không có cid / đổi model a → b / đổi công tắc / bị từ chối), nối tiếp bị từ chối, mở chat mới mà không lấy được cid. Dòng bắt đầu quét ghi công tắc lưu lịch sử, id phiên và cid hiện có (`GeminiWebClient.conversationCidPrefix`).
- **Trần tuyệt đối theo từng lượt**: `fetchStream(_:idleTimeout:absoluteTimeout:)` (mặc định vẫn 240 s); lượt quét Gemini Web dùng 600 s.
- **Tự thử lại một vòng** đúng các lượt lỗi ở **cuối** lần quét (không thử ngay — lượt vừa bị cắt có thể còn đang chạy phía Google); dải/widget "Đang thử lại: Batch i/k"; toast "k/T lượt vẫn lỗi sau khi thử lại".
- **Nút "Thử lại k lượt lỗi"** (`ReaderAINameScanRetryButton`) dưới tin kết quả, chỉ hiện khi không có lệnh chạy; mỗi lần bấm một vòng, gộp tên vào đúng tin cũ rồi lưu phiên. Danh sách lượt lỗi chỉ giữ trong RAM (`AIRuntimeCoordinator.nameScanRetry`, người dùng chọn) — mất khi thoát app, xoá khi quét mới. Gặp lỗi tài khoản/hạn mức khi bấm thử lại ⇒ giữ nguyên tin và danh sách cũ.
- Code: vòng gửi dùng chung `AINameExtractionBatchProcessor.runTurns` (quét chính / tự thử lại / nút); `AINameScanFailedBatch` (mới); `AINameScanProgress.isRetry`; `AIRuntimeCoordinator+NameScanRetry.swift` (mới). `rules.md` mục Reader AI + Gemini Web.
- Chuyển entry `[1.3.497]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`GeminiWebSessionController.swift` 399/400). Không build tại chỗ (Windows), cần CI. Nguyên nhân gốc của tách chat vẫn **UNKNOWN** tới khi có log ❌ của bản này.

## [1.3.526] - 2026-10-14

### fix: quet ten rieng Gemini Web khong tao chat moi moi batch khi luot bi timeout, badge so thong bao dung goc chuong

**1. Quét tên riêng: mỗi batch một chat trên Gemini** — người dùng: *"bật lưu lịch sử gemini thì để tất cả chung 1 chat … bây giờ tôi test lọc name nhiều chương thì nó tạo mỗi batch 1 chat"* (log `app_logs (106)`).
- **Nguyên nhân (từ log)**: gần như mọi lượt quét kết thúc bằng `StreamGenerate lỗi sau ~51 s, chunk=1: … không phản hồi kịp thời gian chờ` (13/10 và 14/10, lượt 1/2, 1/7, 1/8, 1/10…). Gemini nhận prompt ~40.000 ký tự, gửi **một** gói đầu (có cid — cuộc chat đã được tạo trên web) rồi nghĩ lâu hơn ngưỡng im lặng 45 s ⇒ app huỷ lượt **và vứt luôn metadata** vì `consumeGeneration` chỉ trả metadata khi xong ⇒ lượt sau không có cid để nối tiếp ⇒ mở cuộc chat mới. Kết quả: chat mới trên web mỗi batch, còn trong app lượt đó tính là lỗi.
- **Giữ cid khi lượt lỗi**: `GeminiWebClient.streamGeneration(onMetadata:)` báo metadata ngay khi Google gửi; `runConversationTurn` ghi nhớ cuộc chat qua `rememberPartial` khi lượt timeout/bị huỷ (cả nhánh nối tiếp lẫn nhánh mở mới). `DeltaFlag` gộp thành `TurnObservation` (cờ đã phát chữ + metadata mới nhất).
- **Chờ lâu hơn cho lượt quét**: `idleTimeout` 150 s cho lượt quét Gemini Web (`AINameExtractionBatchProcessor.geminiWebIdleTimeout`, cả nhánh nối tiếp lẫn chat tạm); chat thường giữ 45 s; trần tuyệt đối 240 s không đổi. Tham số `idleTimeout` của hàm `public` là optional (`nil` = mặc định) vì giá trị mặc định của hàm `public` không được tham chiếu hằng `internal`.
- `rules.md` mục Gemini Web: thêm luật "lượt lỗi giữa chừng vẫn giữ cid".

**2. Badge số thông báo** — người dùng gửi ảnh chuông Kệ sách: *"vị trí hiển thị số thông báo chưa đẹp"* (badge đỏ đè thân chuông, cạnh chấm trắng có sẵn của icon).
- `ShelfView`: `bell.badge.fill` → `bell.fill` (bỏ chấm có sẵn — hai badge chồng nhau; chấm của icon vẽ tràn khung nên neo theo khung làm badge số rơi vào thân chuông). Badge tối thiểu 16×16 (1 chữ số tròn), tâm ở góc trên-phải chuông lùi 2pt, số dài mọc sang phải, viền 1,5pt màu nền tách khỏi nét chuông.
- Hub (`FloatingHubItem.systemImage`): mục Thông báo cũng `bell.fill`/`bell` vì nút hub đã có chấm/số đỏ riêng.

- Chuyển entry `[1.3.496]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + log thật; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. Không build tại chỗ (Windows), cần CI; cần thử lại quét trên máy (bật log trong Cài đặt để thấy dòng "Lượt lỗi … nhưng đã có cid").

## [1.3.525] - 2026-10-14

### feat(hub): cham hub dang nep co tu 2 muc thi mo menu ngay

Người dùng: *"nếu 2 widget trở lên khi bấm mở rộng thì hiển thị ngay danh sách widget ở trạng thái mở rộng luôn"*, *"ví dụ chỉ 1 browser thì hiển thị icon browser thay vì icon chung"*, *"trường hợp có thông báo và 1 cái khác ở kệ sách thì tính 1"*.
- **`FloatingHubContainerViewController.handlePrimaryAction`**: chạm khi `.peeking` mà có ≥ 2 mục ⇒ bung **và** `openMenu()` ngay (trước đây phải chạm hai lần). `updateLayout` gán vị trí đích ngay nên `layoutMenu` đặt thẻ đúng cạnh nút đã bung; mở menu bật `disableAutoHide` nên không bị tự thu giữa chừng. 1 mục: giữ nguyên (chạm khi nép chỉ bung, chạm lần nữa mới mở).
- Icon 1 mục = icon của chính mục đó và cách đếm mục ở tab Kệ Sách (không tính Thông báo) **đã đúng từ 1.3.524** (`FloatingHubPresentationReader.makeSnapshot`, `FloatingHubButton.glyphName`) — chỉ ghi rõ thành luật trong `rules.md` mục "Nút hub nổi".
- Chuyển entry `[1.3.495]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. Không build tại chỗ (Windows), cần CI.

## [1.3.524] - 2026-10-14

### feat: gop widget noi thanh nut hub, quet ten rieng noi tiep chat cua phien, icon Lucide sao chep dan, badge 99+ khong vo

Người dùng duyệt 4 plan bằng `/push-ci-monitor thực hiện mỗi plan trong 1 session ... push và theo dõi CI chung`. Mỗi plan do một agent con làm trong worktree riêng, gộp thành một commit. Plan: `Docs/Plans/2026-10-14-plan-ai-batch-name-scan-session-chat.md`, `Docs/Plans/2026-10-14-plan-floating-hub-widget.md`; hai plan còn lại duyệt trong chat.

**1. Quét tên riêng nhiều chương** — người dùng: *"Lỗi từ batch thứ 2 … không có prompt, chỉ có raw"*, *"bị tạo một đoạn chat khác đoạn chat chung của phiên"*, *"số batch thật sự được gửi yêu cầu cũng không chính xác"*, *"khi có lệnh đang chạy hãy disabled prompt nhanh"*, *"nếu bật lưu vào lịch sử chat thì không cần gom nội dung đoạn chat vào prompt"*.
- **Gốc lỗi thiếu prompt**: lượt nối tiếp chỉ kèm khối hệ thống khi băm của nó đổi (`GeminiWebClient+Conversation.runConversationTurn`), mà prompt trích xuất giống hệt giữa các lượt ⇒ lượt 2–5 chỉ gửi raw. Thêm `forceContext`: lượt quét luôn kèm prompt; băm vẫn cập nhật nên chat thường kế tiếp tự gửi lại ngữ cảnh chương.
- **Một chat của phiên**: Gemini Web + bật "Lưu chat vào lịch sử Gemini" ⇒ lượt quét nối tiếp đúng cuộc chat của phiên app (`AIChatSession.id`, `persist: true`), **bỏ** xoay chat mới sau mỗi 5 lượt (nguyên nhân số tin trên Gemini lệch số batch). Tắt công tắc: như cũ (chat tạm từng lượt, đủ prompt).
- **Đếm đúng lượt** (`AINameScanProgress`, `ReaderAIBatchProgressBannerView`): báo tổng ngay sau khi chia lượt (hết "Batch 0/1"), N = lượt **đang gửi**, dòng phụ đếm lượt lỗi; tin gửi có nhãn `(lượt N/T)`, log `gửi lượt N/T`. Xong mà có lượt lỗi ⇒ toast `.error` cả khi màn AI đang mở.
- **Khoá chip prompt nhanh** khi có lệnh AI đang chạy (mờ + không bấm); màn AI không cho bắt đầu quét khi đang chat (trước đây `cancelActiveTask()` huỷ ngang câu trả lời).
- **Chat thường, Gemini Web + bật lưu**: chỉ gửi `[system, tin hiện tại]`, không gom lịch sử trao đổi/tóm tắt ngữ cảnh cũ (kể cả khi phải mở cuộc chat Gemini mới).
- Luồng quét chuyển sang `AIRuntimeCoordinator+BatchExtraction.swift` (file gốc 387/400 dòng); nới `batchRunId`/`activeBatchTask` sang `internal`, setter `isRunning`/`activeTaskTitle` sang `internal(set)`. Nhánh xong/lỗi phải khớp `batchRunId` mới xoá trạng thái.

**2. Nút hub nổi thay 3 widget** — người dùng: *"hiện tại có quá nhiều widget, có cách nào gọn lại không?"*, chọn phương án "một nút hub" (TTS giữ riêng).
- Widget AI, trình duyệt thu nhỏ và Thông báo gộp thành **một** nút 36px, một cửa sổ (`alert - 2`; TTS vẫn `alert - 1`). Thư mục mới `Sources/Views/FloatingHub/` (11 file, ~1.500 dòng); xoá 14 file widget cũ; `NotificationFloatingWidgetPresentationReader` đổi tên thành `NotificationInboxPresenceReader`.
- Hub hiện khi có ≥1 mục (AI đang chạy và màn AI đóng / trình duyệt thu nhỏ còn tab / thông báo chưa đọc hoặc tác vụ chạy, trừ tab Kệ sách). **Luôn xuất hiện nép mép**, không tự bung khi có tin mới; chạm khi nép ⇒ bung; chạm khi bung: 1 mục ⇒ mở thẳng, ≥2 ⇒ menu (Trợ lý AI → Trình duyệt → Thông báo, có dòng phụ); tự nép sau 3 s trừ khi menu mở.
- Chỉ báo: chấm đỏ / số chưa đọc ("99+" một dòng); AI đang chạy ⇒ viền tím tĩnh; trình duyệt tab nằm yên ⇒ nháy đỏ bằng màu; **bỏ** badge số tab và chấm đỏ của trình duyệt.
- Sheet Thông báo chuyển nguyên văn từ widget cũ (nhánh hit-test, móc `.onDisappear`, `.modelContainer`, delegate sau present, giữ cửa sổ sống). Cờ "menu đang mở" được hạ ở mọi đường (ẩn, kéo, đổi số mục, mở sheet, đổi scene) — luật mới trong `rules.md`.
- Vị trí: key mới `floatingHubVerticalRatio`/`floatingHubEdge`, lần đầu lấy từ vị trí widget Thông báo cũ.

**3. Icon sao chép/dán** — người dùng: *"các nút copy và paste … dùng SF Symbols khó phân biệt quá"*, chọn bộ Lucide.
- `doc.on.doc`/`doc.on.clipboard` (23 chỗ, 14 file) ⇒ Lucide `copy` / `clipboard-paste` (asset SVG template, `lucide-static@0.400.0`, ISC — `Docs/ThirdParty/Lucide-LICENSE.txt`); mục "Gốc" của menu chọn chữ ⇒ Lucide `languages`. Nút "Copy" của màn sao chép bản gốc từng dùng nhầm icon dán.
- `AppGlyph` (`Sources/Views/Common/AppGlyph.swift`) là nguồn tên icon duy nhất; cỡ truyền tường minh từng chỗ (asset không co theo `.font()`). Quy ước thêm vào `CLAUDE.md`/`AGENTS.md`.

**4. Badge "99+" trên chuông Kệ sách bị vỡ** — `overlay` chỉ đề xuất đúng khung icon (~20pt) nên "99+" bị ép xuống dòng. `ShelfView`: `.lineLimit(1)` + `.fixedSize()`, neo mép trái badge vào mép phải icon để số dài mọc sang phải.

- Chuyển entry `[1.3.494]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + review phản biện bằng agent con; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI. Cần xem trên máy thật: nét SVG Lucide, hub (chạm xuyên khi menu đóng, mở Reader từ sheet Thông báo ở tab khác). Không đụng `Tests/`.

## [1.3.523] - 2026-10-13

### fix: tu sua duong dan tien ich khi doi goc thu muc, danh sach ten AI dai khong giat, Gemini Web giai phong WebView khi loi

Người dùng duyệt gộp 3 plan bằng `/push-ci-monitor tất cả 1 lượt`.

**1. Tiện ích "bị xoá" — thật ra là đường dẫn hỏng** (`app_logs (105)`: từ 10:38:53 mọi chương chưa tải lỗi `ExtensionManager -3 "plugin.json not found inside extension"`; mở tab Tiện ích thấy trống; tắt mở lại vẫn mất; thư mục plugin trên máy còn đủ; restore backup thì có lại).
- **Cơ chế**: `Extension.localPath` lưu **đường dẫn tuyệt đối** trong `library.db`. Gốc thư mục dữ liệu của app đổi ⇒ mọi `localPath` trỏ về gốc cũ (file vẫn ở `extensions/<packageId>/` hiện tại) ⇒ lỗi -3; rồi `ExtensionInstallAudit` (chạy mỗi lần mở tab Tiện ích) coi là mất file: tiện ích của kho bị đưa `localPath` về rỗng, tiện ích import zip bị **xoá hàng** ⇒ tab trống, lưu luôn trong DB. Restore chữa được vì `BackupExtensionInstaller` giữ file đang có và **tính lại** `localPath` từ thư mục hiện tại. Vì sao gốc đổi: **UNKNOWN** — khớp thời gian với khuyến nghị "Convert to Private App" của 1.3.522 (LiveContainer chuyển thư mục dữ liệu giữa App Group và container riêng), chưa xác nhận.
- **`ExtensionPathResolver`** (mới, `Services/Extensions`): khi `localPath` không còn `plugin.json`, tìm lại theo thứ tự (1) phần sau `/extensions/` của path cũ ghép vào gốc hiện tại, (2) `extensions/<packageId>/` kể cả thư mục con có `plugin.json`. Chỉ nhận thư mục nằm trong `extensions/`, không nhận `..`.
- **`ExtensionInstallAudit`** tìm lại **trước** khi gỡ/xoá (`Plan.relocations`); chỉ gỡ/xoá khi không thấy ở đâu. Tiện ích đã bị đưa `localPath` về rỗng mà thư mục còn `plugin.json` được khôi phục. Đánh đổi có chủ ý: gỡ tiện ích đúng lúc path đang hỏng (thư mục không xoá được) thì nó hiện lại.
- **Lúc mở app** (`AppLaunchRootView.onAppear` → `ExtensionTransactionCoordinator.repairExtensionPathsAtLaunch`): chỉ sửa path, không gỡ/xoá, chạy trước khi Reader/TTS cần tới.
- **Log ❌** (luôn ghi kể cả khi tắt log): một dòng khi sửa path (số tiện ích, gốc cũ → gốc mới, packageId); dòng gỡ/xoá của audit nay cũng có ❌. Lỗi -3 kèm đường dẫn đã tìm (`localPath rỗng` khi rỗng).

**2. AI: hiển thị danh sách tên dài làm giật máy và TTS** (`TTSManager` là `@MainActor`, main thread bận thì TTS khựng).
- **`AIMarkdownMessageView`**: mỗi dòng là một `Text(LocalizedStringKey)` trong `VStack` không lazy, dựng lại cả tin mỗi nhịp stream 50 ms / mỗi batch quét tên. Nay chỉ dựng **100 đoạn cuối**, tự nạp thêm 100 đoạn khi cuộn lên gần mép trên (vòng xoay nhỏ, không nút; đo bằng `GeometryProxy.bounds(of: .scrollView)`, preference `Bool` nên mỗi lần lọt vào vùng nhìn chỉ nạp một đợt). Nạp từ đáy lên vì chat neo đáy (`.defaultScrollAnchor(.bottom)`) và cố ý không dùng `LazyVStack`. Sao chép / Thêm vào VP-Name vẫn dùng toàn bộ nội dung.
- **`hasDictionaryEntries`** (gọi trong `.contextMenu` của mọi tin mỗi lần vẽ): `enumerateLines`, dừng ở dòng `từ=nghĩa` đầu tiên thay vì tách cả tin.
- **Sheet duyệt tên riêng** (`ReaderAINameReviewCardView`): `LazyVStack` — chọn/bỏ chọn trước đây cập nhật lại mọi hàng kèm `TextField`. Nút chọn icon 22 pt, vùng chạm 44×44 (cũ: 16 pt); chạm dòng tên cũng chọn/bỏ chọn; hàng bỏ đệm trái để giữ chiều cao gần như cũ.
- **`AIRuntimeCoordinator`**: bước gắn cờ NE/VP cuối đợt quét (đọc `Names.txt`/`VietPhrase.txt` + tra từ điển cả danh sách) chuyển ra `Task.detached`, kiểm tra huỷ sau khi chờ.

**3. Gemini Web: WebView ẩn không được giải phóng khi `prepare()` lỗi.** `touch()` (hẹn giải phóng sau 10 phút) chỉ chạy ở nhánh thành công; `prepare()` ném (`notSignedIn`/timeout/`protocolChanged`) ⇒ WKWebView + window ẩn sống tới khi app thoát. Nay `touch()` nằm trong `defer` của task (mọi lối ra). Hẹn giờ thêm điều kiện `webView != nil` để không ghi log "Giải phóng WKWebView ẩn" sai khi WebView đã bị giải phóng giữa chừng. Tối đa một WebView (singleton) nên lỗ này không làm fd tăng dần.

- Chuyển entry `[1.3.493]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager 3510), 0 mới; file mới `ExtensionPathResolver.swift` 65 dòng, một type chính. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.522] - 2026-10-13

### docs(fd): ghi nhan nguyen nhan can fd khi nghe TTS o nen la bug Dead10ccFix cua LiveContainer

Người dùng: *"ghi lại changelog để biết lỗi này do LiveContainer"*. Chỉ ghi tài liệu, không đổi code.

- **Lỗi**: nghe TTS (Google) lâu với màn hình khoá ⇒ tiến trình cạn file descriptor (EMFILE, `NSPOSIXErrorDomain 24`, hiện ra thành `NSCocoaErrorDomain 256`): không mở được chương, ảnh bìa, cả file log; chỉ tắt hẳn app mới hết. Điều tra qua 1.3.517 → 1.3.521 (census `[FD]`, `detail`, bộ đo theo bước, nhịp 1 s).
- **Nguyên nhân gốc — không nằm trong code FreeBook**: `LiveContainer/Tweaks/Dead10ccFix.m` (đã đọc source bản mirror, commit `4dbe0f9a`; vòng 2 giây có từ commit `85ca2724`, 2025-07-31). Đoạn này **chỉ được cài khi app chạy dạng Shared App hoặc Multitask (LiveProcess)**. Khi app ở nền mà chưa bị iOS treo (tức đang phát audio), cứ `dispatch_after` **2 giây** nó liệt kê fd của tiến trình (`PROC_PIDLISTFDS`), rồi với mỗi đường dẫn file thường (bỏ `-wal`/`-shm`/`-journal`, bỏ SQLite không khoá, bỏ file có xattr `com.apple.runningboard.can-suspend-locked` ≠ 0) gọi `open(path, O_RDONLY | O_NOCTTY)` + `fcntl(F_GETLKPID)` và **không bao giờ `close`**. Bản mở thừa lại giữ đường dẫn trong danh sách ⇒ file nào đã bị "bắt" một lần là rò mãi, khoảng 30 fd/phút mỗi file.
- **Khớp từng số đo trong log**: chỉ tăng khi app ở nền (trên màn hình ≈ 0; ở nền mà dừng TTS ⇒ app bị treo ⇒ 0); +1 mỗi ~2,1 s theo đồng hồ, không theo đoạn audio (log 104); fd mới là mở mới chỉ-đọc `fl=0x0 off=0 cloexec=0`, không phải bản `dup`; SQLite không bao giờ bị nhân; file đã xoá thì dừng nhân (log 103); file hệ thống `collator.dat`/`Dictionary.dat`/`default.metallib` lúc có lúc không (bị bắt khi tình cờ đang mở đúng vòng 2 s).
- **Vì sao chỉ mới gặp từ 2026-10-12**: commit `bd683b62` (2026-10-09, *"AppLogger giữ file mở có khoá"*) khiến `app_logs.txt` **luôn mở** ⇒ bị bắt ngay vòng đầu mỗi lần xuống nền. Trước đó log mở/ghi/đóng từng dòng nên hầu như không bị bắt. Sao lưu tự động chạy ở nền bắt thêm `books/*.bin`, `.fbbackup`, `VietPhrase.dat` (log 103: cạn 10240 fd sau ~1,5 giờ). Rà 45 commit 2026-10-08 → 2026-10-11: không commit nào tự mở lại file theo nhịp; `bd683b62` chỉ là chỗ khuếch đại.
- **Cách tránh**: (1) phía người dùng — trong LiveContainer chọn **"Convert to Private App"** cho FreeBook và không chạy Multitask ⇒ đoạn lỗi không được cài; (2) trong app — gắn xattr `com.apple.runningboard.can-suspend-locked = 0x01` lên file app giữ mở lâu (Dead10ccFix tự bỏ qua), còn file hệ thống thì nhờ `FileDescriptorSweeper` (1.3.521) dọn bản thừa. Bản sửa phía app đang chờ duyệt.
- **Không phải nguyên nhân** (đã loại trừ bằng số đo): `FD_CLOEXEC`/bản `dup` (giả thuyết của 1.3.520), JSExecutor/WebView (bộ đếm `live=` bằng 0), các bước phát audio `AVAudioPlayer`/Now Playing (bộ đo theo bước của 1.3.521 không thấy tăng), tính năng nhảy về chương đang nghe khi mở lại Reader (`c9e7c20a`).
- **Tham khảo**: [Dead10ccFix.m](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainer/Tweaks/Dead10ccFix.m) · [commit thêm vòng 2 s](https://github.com/LiveContainerMirror/LiveContainer/commit/85ca2724812b5098d67bb5a02317cf94995525bc) · [chỗ cài trong LCBootstrap.m](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainer/LCBootstrap.m#L514-L518) · [gist gốc cũng thiếu `close`](https://gist.github.com/JJTech0130/07e2458df592faad1d2ba72283a0ca50).
- Chuyển entry `[1.3.492]` sang `CHANGELOG.archive.md` để giữ 30 entry.

## [1.3.521] - 2026-10-13

### fix(fd): tu don fd mo coi khi nghe TTS o nen, do fd theo tung buoc doan audio

Người dùng gửi `app_logs (103).txt`, hỏi *"không có cách nào giải phóng…"*, *"bình thường mở file không đóng à"*; duyệt plan gộp (bộ đo + bộ dọn) bằng `/push-ci-monitor`.

- **Phân tích log 103 (bản 1.3.520)**: phiên 07:06 → 08:32 chạm trần 10240 fd, 08:33 `NSPOSIXErrorDomain 24` (EMFILE) khi mở `plugin.json`/chương/bìa = tái hiện lỗi gốc. fd **chỉ tăng khi app ở nền và đang phát TTS** (lúc app trên màn hình gần như 0), ~1 đợt mỗi đoạn audio, mỗi đợt mở thêm **1 fd cho mỗi file** trong một nhóm (`app_logs.txt`; sau sao lưu tự động chạy ở nền thêm `books/*.bin`, `.fbbackup`, `VietPhrase.dat`; có lúc `collator.dat`/`Dictionary.dat`/`default.metallib`). fd mới là **mở mới chỉ-đọc** (`fl=0x0 off=0 cloexec=0`), không phải bản `dup` ⇒ giả thuyết `FD_CLOEXEC` của 1.3.520 **sai**. `live=` toàn 0 ⇒ không phải JS/WebView. File trong thư mục tạm đã xoá dừng ở +4 ⇒ thứ gây rò mở lại **theo đường dẫn**. Code app không có chỗ nào làm vậy ⇒ nghi framework hệ thống được gọi mỗi đoạn audio khi ở nền hoặc LiveContainer — **UNKNOWN**.
- **Bộ đo theo bước (`Services/Logging/FileDescriptorStepProbe.swift`, mới)**: khi app ở nền, trong 60 đoạn audio đầu sau mỗi lần xuống nền, đếm fd trước/sau từng bước — `player.stop`, `session`, `player.init`, `player.play`, `nowPlaying`, `finish.stop`, `finish.next` (`TTSManager.swift`, bọc tại chỗ, **không thêm dòng**: vẫn 3510) và `google.request` (`GoogleTTSService.audioParts`); tăng thì ghi `[FD] step=<bước> +N total=T chunk=C` (tối đa 40 dòng mỗi lần xuống nền). Thêm nhịp 1 giây trong 120 giây đầu ở nền: `[FD] tick t=…s ±N total=T chunk=C` khi tổng đổi — phân biệt rò **trong** một bước (đồng bộ) với rò **giữa** các bước (thứ khác đẩy vào). Đếm bằng `fcntl(F_GETFD)` tới fd lớn nhất từng thấy + 512, không mở fd mới.
- **Bộ dọn fd mồ côi (`Services/Logging/FileDescriptorSweeper.swift`, mới)**: chạy trên queue của census mỗi 20 đoạn audio khi tổng fd ≥ 500. Chỉ đóng fd thoả **hết**: file thường, không phải SQLite (`.db`, `.sqlite`, `-wal`, `-shm`, `-journal`) và không dưới `/dev/`; chỉ-đọc, không `FD_CLOEXEC`, vị trí 0; cùng file (device + inode) có ≥ 4 fd như vậy; đã thấy đúng fd đó cùng file ≥ 45 giây; không phải fd số nhỏ nhất của đống. Ghi `[FD] sweep total=A->B closed=N kept=M top=[…]`. Công tắc **"Tự dọn file mở thừa"** (`fdSweeperEnabled`, mặc định bật) ở Cài đặt → Nhà Phát Triển → Ghi log hệ thống, mục Chẩn Đoán. Rủi ro còn lại (đã nói với người dùng): nếu thứ mở lại thỉnh thoảng dùng/đóng các fd đó thì có thể sinh lỗi lạ — tắt công tắc.
- `FileDescriptorCensus`: `record(event:)` báo `background`/`active` cho bộ đo; `tickChunk()` báo đoạn audio cho bộ đo và gọi bộ dọn; `normalize` bỏ `private` để bộ dọn ghi log.
- `rules.md` §5.9 và `CLAUDE.md`/`AGENTS.md` (mirror): `logAlways` dành cho chẩn đoán fd — census, bộ đo, bộ dọn.
- Chuyển entry `[1.3.491]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager 3510), 0 mới; file mới 157 và 102 dòng, một type chính. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.520] - 2026-10-12

### feat(settings): gon tab Cai dat thanh cac man rieng (dich, TTS, trinh duyet, log, theo doi nhiet), census fd chi tiet

Người dùng (4 phiên `/grill-me` + `/push-ci-monitor`): tạo màn log riêng; tạo màn cài đặt dịch thuật gom mọi section dịch; thêm màn theo dõi nhiệt (có chia sẻ, *"thận trọng lựa chọn cách lưu thông tin để tránh ảnh hưởng hiệu năng"*); *"gộp các nav ở tab setting còn lại vào cho gọn"*. Plan `Docs/Plans/2026-10-12-plan-settings-reorg-diagnostics.md`, mọi mockup duyệt nguyên.

- **Tab Cài đặt** (`SettingsView.swift` 453 → 33 dòng): chỉ còn dòng điều hướng, 4 section — **Đọc & Nghe** (`ReadingSettingsSection`: Cài đặt dịch thuật · "Đang bật/Tắt", Nghe truyện (TTS) · tên engine từ `@AppStorage("ttsTool")`, Trợ lý AI, Trình duyệt hiển thị · "Thu nhỏ/Toàn màn hình"), **Thư Viện** (`LibrarySettingsSection`: chương mới, sao lưu, dọn dẹp — gộp 3 section một dòng), **Nhà Phát Triển** (`DeveloperSettingsSection`: Debug Server, Ghi log hệ thống · trạng thái, Theo dõi nhiệt · mức hiện tại), **Thông Tin**. Xoá `TTSSettingsSection`, `AISettingsSection`, `BrowserSettingsSection`, `NewChapterSettingsSection`, `BackupSettingsSection`, `StaleBookCleanupSettingsSection` (chỉ `SettingsView` dùng). Không đổi khoá UserDefaults nào; View không observe `TTSManager`.
- **Màn mới, nội dung chuyển nguyên văn** (cắt dán theo dòng bằng script, không viết lại): `TranslationSettingsView` (2 section dịch + trình chọn file nhập từ điển + `getStatusText`), `DictionaryCard` (file riêng), `TTSSettingsHubView` (3 nhóm TTS, tiêu đề nhóm rút gọn; `engineName(for:)` dùng chung), `VisibleBrowserSettingsView` (công tắc thu nhỏ), `LogSettingsView` (3 công tắc + 3 nút + 3 alert; thêm "File đang mở N / giới hạn" từ `FileDescriptorCensus.openCount()` và danh sách file log chỉ xem).
- **Theo dõi nhiệt (mới)**: `Services/Diagnostics/DeviceThermalMonitor.swift` — `@MainActor`, bật ở `FreeBookApp.init`; `DispatchSourceTimer` main 30 s (leeway 10 s) + mẫu ngay khi `thermalStateDidChangeNotification`; mẫu = mức nhiệt (iOS chỉ có 4 mức, không có °C), % CPU **của app** (Δ`ProcessCPUClock`/Δ tường, 100% = 1 lõi), pin, sạc, Low Power, engine TTS nếu đang phát; bộ đệm vòng `ContiguousArray` cấp phát sẵn 1.440 ô (12 giờ), ghi đè mẫu cũ, **không ghi đĩa**. `ThermalCSVExport` (`Transferable`, `DataRepresentation(.commaSeparatedText)`) dựng CSV trong RAM **đúng lúc chia sẻ** (3 dòng tóm tắt + mỗi mẫu một dòng). `Views/Settings/Diagnostics/ThermalMonitorView` (hiện tại, đọc mỗi 2 s khi mở màn; nút chia sẻ 17pt semibold 36×38) + `ThermalMonitorChart` (Swift Charts: bậc thang mức nhiệt; CPU + pin; tô nền đoạn đang phát TTS; "Đang thu thập…" khi < 2 mẫu).
- **Census fd chi tiết** (plan đã duyệt, gộp commit): `FileDescriptorCensus` thêm dòng `[FD] detail <nhóm> n=… fd=min…max newest(fd,fl,cloexec,off) oldest(…)` cho tối đa 5 nhóm vừa tăng (cùng `off` ⇒ bản `dup` chung một open file description) và `live=[…]` trên dòng đếm đủ; `trackLive` đếm `JSExecutor` (thêm `deinit`), `WebViewLoader`, `VisibleWebViewController` (thêm `deinit`). `AppLogger` đặt `FD_CLOEXEC` cho handle log — phép thử giả thuyết "fd thiếu CLOEXEC bị nhân bản theo nhóm" (log 102: `app_logs.txt`/`collator.dat`/`Dictionary.dat` tăng cùng +N, 23 → 1661 fd trong 33 phút sau lần tìm truyện đa nguồn).
- **Sửa theo review phản biện** (3 hướng × kiểm chứng; 3 phát hiện bị bác): (a) tập "đang nhập từ điển" chuyển sang `TranslationImportState.shared` (giữ tên `importingTypes` qua computed property) — trước kia là `@State` của gốc tab sống suốt phiên, để trên màn con thì mất khi Back/chạm lại tab trong lúc `Task` nhập vẫn chạy ⇒ nhập chồng được; (b) `ThermalCSVExport` cố định `en_US_POSIX` + lịch Gregorian cho cột thời gian/tên file; (c) sửa 2 câu hướng dẫn trỏ vị trí Cài đặt cũ (`NghiTTSSettingsView`, `ReaderDefinitionOverlayView+Rules`); (d) "Mức nhiệt"/"Chế độ nguồn điện thấp" đọc thẳng `ProcessInfo` khi chưa có mẫu thay vì hiện "Bình thường" giả; (e) vòng cập nhật 2 giây của màn nhiệt chạy theo `.task(id: scenePhase)` — ở nền thì dừng.
- `rules.md`: §5.9 trỏ màn log mới + `detail`/`live`/`FD_CLOEXEC`; cây thư mục thêm `Diagnostics/`.
- Chuyển entry `[1.3.490]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + review phản biện; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới; mọi file mới ≤ 320 dòng, một type chính. **Không build tại chỗ** (Windows) — CI. Không đụng `Tests/`.

## [1.3.519] - 2026-10-12

### fix(toc): doc duoc toc_rules.json kieu cu thieu truong replace/isRegex

Người dùng: *"fix ❌ Lỗi decode file toc_rules.json, fallback về defaultTOCRules"* (dòng lỗi lộ ra nhờ 1.3.517 luôn ghi log ❌), kèm file `toc_rules_config_CADD841F.json`. Plan duyệt trong chat.

- **Nguyên nhân**: `TOCRule` ban đầu (2026-07-04) chỉ có `id, name, rule, example, enabled`; refactor 2026-08-13 (`688b57ee`) thêm `replace: String` và `isRegex: Bool` **bắt buộc** (không dùng ở logic mục lục nào) nên decoder tự sinh đòi đủ 7 khoá. `translate/toc_rules.json` ghi từ bản cũ thiếu 2 khoá ⇒ mỗi lần đọc đều decode hỏng, app lẳng lặng dùng `defaultTOCRules` và **bỏ qua rule người dùng đã chỉnh**. Cùng lỗi làm nhập file rule kiểu cũ báo "JSON không hợp lệ" (`validateImportedTOCRules`) và khôi phục bản sao lưu cũ báo lỗi phần quy tắc mục lục. File người dùng gửi decode bình thường — đó là bộ 21 rule mặc định xuất ra sau khi app đã rơi về mặc định.
- **Sửa (`Models/Translation/TOCRule.swift`)**: `init(from:)` + `CodingKeys` tường minh — `id`, `name`, `rule` vẫn bắt buộc; thiếu `enabled` ⇒ `true`, `replace` ⇒ `""`, `isRegex` ⇒ `true` (đúng mặc định của `init`). Ghi file giữ nguyên đủ 7 khoá (encode tự sinh). Một chỗ sửa chữa cả 3 đường: đọc lúc chạy, nhập file, khôi phục sao lưu.
- **Log**: dòng `❌ Lỗi decode file toc_rules.json` in thêm lý do (`TranslateUtils.tocRulesDecodeFailureReason(at:)` trong `TranslateUtils+TOCRuleValidation.swift`, chỉ chạy ở nhánh đã hỏng). Sửa trên dòng có sẵn: `TranslateUtils.swift` giữ 917 dòng (baseline).
- **Hệ quả**: rule tự chỉnh trong file cũ có hiệu lực trở lại thay cho bộ mặc định; file cũ có thể thiếu rule mặc định thêm về sau — muốn bộ mới nhất thì "Khôi phục mặc định" ở màn Quy tắc mục lục.
- Chuyển entry `[1.3.489]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.518] - 2026-10-12

### perf(log): ghi log o luong nen, tu chia file log 2 MB, xuat va xoa tat ca file log

Người dùng: *"có thể sửa tự động chia log file khi quá nhiều không, tôi sợ nhiều quá gây lag app khi log"* → chọn *"chuyển vào luồng nền và chia thành nhiều file, sửa lại xuất cho phép xuất tất cả các file log, sửa xoá tất cả log xoá tất cả file log"*.

- Ghi chú khi phân tích: kích thước file **không** làm việc ghi chậm đi (mỗi dòng là `seekToEnd` + `write` qua handle giữ sẵn); thứ tốn là số dòng/giây ghi đồng bộ trên luồng gọi (kể cả main) và sao chép/xuất file lớn.
- **Ghi trên luồng nền**: `AppLogger.log`/`logAlways` chỉ dựng chuỗi + lấy thời điểm ở luồng gọi rồi `async` sang serial queue `.utility` của `AppLogger`; định dạng giờ, `print` và ghi file làm trên queue. Bỏ `NSLock`; `clear`/`readLogContents` đồng bộ với queue bằng `queue.sync`; `logFileSize` đọc `stat` trực tiếp (bị gọi lúc dựng view). Đổi lại: crash có thể mất vài dòng cuối chưa kịp ghi.
- **Chia file (mới, `Services/Logging/AppLogFiles.swift`)**: `app_logs.txt` quá 2 MB ⇒ đẩy thành `app_logs.1.txt`, các file cũ lùi một bậc tới `app_logs.4.txt`, file cũ nhất bị xoá (tổng ≤ ~10 MB). Xoay vòng chỉ đổi tên/xoá file (không tốn fd); không mở nổi file mới (cạn fd) thì ghi tiếp vào handle cũ — giờ trỏ `app_logs.1.txt` — để không mất dòng. Thay luật "lúc khởi động file > 5 MB thì giữ 1 MB cuối" của 1.3.517.
- **Cài đặt → Nhật ký**: "Xuất tất cả file log" (`ShareLink(items:)` mọi file đang có), "Xóa tất cả nhật ký log" xoá mọi file (file đang ghi cắt về 0 qua handle), "Sao chép nhật ký log (file mới nhất)" chỉ lấy file đang ghi để tránh đưa ~10 MB lên clipboard. `SettingsView.swift` giữ đúng 453 dòng (baseline).
- **Sửa theo review phản biện**: (a) xoay vòng mà không mở nổi file mới (cạn fd) thì đổi tên file đang ghi về lại `app_logs.txt` để handle luôn trỏ file hiện hành — trước đó handle kẹt ở `app_logs.1.txt` và lần xoay sau/"Xóa tất cả" có thể xoá chính file đang ghi; `shiftForRotation` trả `Bool` để chỉ trả tên khi bước đổi tên đã xảy ra; (b) danh sách file cho "Xuất tất cả file log" giữ trong `@State logFileURLs` (thay `logFileExists`), cập nhật khi mở màn Cài đặt và sau khi xoá, để không bỏ sót file mới chia; (c) sửa số dòng `AppLogger.swift` trích trong `CLAUDE.md`/`AGENTS.md`.
- `rules.md` §5.9 + cây thư mục `Logging/`, `CLAUDE.md`/`AGENTS.md` mục Logging cập nhật theo.
- Chuyển entry `[1.3.488]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI. Không đụng `Tests/`.

## [1.3.517] - 2026-10-12

### fix(tts): tam dung khi 5 chuong lien tiep loi, dem file descriptor de tim cho ro, nang gioi han fd, luon ghi log loi

Người dùng: *"nghe truyện lâu sẽ xảy ra lỗi này, đây là chương đã tải, có vẻ lỗi gì đó chặn truy cập file, tìm nguyên nhân lỗi; ngoài ra hãy sửa lại: trước đây nếu chương lỗi sẽ tự sang chương kế tiếp vô hạn. bây giờ hãy sửa lại, nếu sang chương 5 lần đều lỗi thì tạm dừng"*. Plan duyệt trong chat (Phần 1 + Phần 2 + mục 3c; chương rỗng tính vào 5 lần). Sau đó: *"sửa lại để luôn log lỗi dù có bật log hay không giúp tôi"*.

- **Nguyên nhân (đọc code, chưa có log máy thật)**: tiến trình **cạn file descriptor (EMFILE)** sau vài giờ nghe Google TTS. Dấu hiệu: chuỗi `couldn\U2019t … (NSCocoaErrorDomain error 256.)` là chuỗi gốc chưa bản địa hoá của CoreFoundation (chỉ lộ ra khi CF không nạp nổi bảng bản địa hoá); 256 = `NSFileReadUnknownError` (EMFILE ánh xạ vào 256, chặn do khoá máy sẽ ra 257); "Tải lại" không được, ảnh bìa đã tải cũng không hiện, bật log sau khi lỗi cũng không ghi được, chỉ tắt hẳn app mới hết. Đường đi: đọc `.bin` hỏng bị nuốt (`ChapterPersistenceStore.readChapter`, `ChapterContentRepository.loadUnshared`) ⇒ rơi xuống `ExtensionManager.chap` đọc `plugin.json`/`chap.js` cũng hỏng ⇒ lỗi đó lên Reader. Rà 37 commit `c1e51da6..HEAD` và săn rò rỉ trên đường Google TTS (theo luồng + quét theo API) **chưa thấy chỗ rò** ⇒ phải đo trên máy.
- **Đo fd (mới, `Services/Logging/FileDescriptorCensus.swift`)**: đếm fd đang mở theo nhóm (đường dẫn chuẩn hoá `AS/books/<hex>.bin`, `sock/tcp/:443`, `pipe`…) chỉ bằng `fcntl`/`fstat`/`getsockopt`/`getpeername` — không mở fd mới nên chạy được cả khi đã cạn. Ghi lúc khởi động, mỗi lần TTS sang chương, mỗi 100 đoạn audio (chỉ tổng; tăng > 20 thì đếm đủ), khi app vào nền/trở lại, và chụp toàn bộ bảng fd đúng lúc lỗi (`BookBinManager` mở file hỏng, `ImageCacheManager.loadLocalCover` đọc bìa hỏng, TTS bỏ chương vì hết fd) — mỗi phiên một lần.
- **`AppLogger.logAlways`**: ghi bất kể công tắc log (chỉ census dùng, ~1 dòng/chương nên không chạm ngưỡng tự xoá 5 MB). `appendLocked` giờ tạo file rỗng rồi mở handle ngay từ dòng đầu, giữ suốt phiên ⇒ lúc cạn fd vẫn ghi được.
- **Luôn ghi log lỗi**: `AppLogger.log` giờ ghi mọi dòng chứa `❌` dù công tắc log tắt (dòng thường vẫn theo công tắc); đổi lại chuỗi log luôn được dựng để kiểm tra. Gắn `❌` cho 32 dòng log lỗi thật chưa có dấu (catch-block lưu/đọc file, ChapterStore save failed, espeak init, TTS không bắt đầu/không chuẩn bị được chương, NghiTTS synthesis failed, lỗi AI/Gemini Web…); để nguyên các dòng không phải lỗi (huỷ, thử lại, fallback, thống kê, Debug Server ngắt kết nối). Thêm chi tiết lỗi (`FileDescriptorCensus.describe`) vào log nuốt lỗi ở `ChapterPersistenceStore.readChapter` và `ChapterContentRepository.loadUnshared`; thêm log `❌` khi Reader không tải được chương (`ReaderViewModel.runNavigationWorker`). `CLAUDE.md`/`AGENTS.md` mục Logging ghi quy ước `❌`.
- **3c — nâng giới hạn fd**: `FileDescriptorCensus.start()` (gọi cuối `FreeBookApp.init`) nâng `RLIMIT_NOFILE` mềm lên mức cao nhất hệ thống cho phép trong `10240/8192/4096/2048/1024`, ghi `soft=cũ->mới hard=…` vào log. Che bớt triệu chứng trong lúc chờ tìm chỗ rò; census vẫn thấy fd tăng dần.
- **Dừng sau 5 chương lỗi (mới, `TTSManager+ChapterSkipLimit.swift`)**: `skipFailedChapter` thay 3 chỗ tự bỏ chương — tải lỗi, xử lý lỗi (`fallbackAdvanceToNextChapter`) và chương không có nội dung (`applyNextChapter`). Chương lỗi thứ 5 liên tiếp ⇒ `stopCurrentPlayback()` + `pause()` + toast lỗi; nếu do hết fd thì toast thêm "App đang mở quá nhiều file — hãy tắt hẳn app rồi mở lại". Bộ đếm về 0 khi `applyNextChapter` phát được chương (`noteChapterAdvanceSucceeded`), khi `startSpeaking`, khi `pause()`. Không đếm `CancellationError` và nhánh dịch lại do đổi token. Chương lỗi chạm cuối truyện ⇒ toast "không phát được và đã tới cuối truyện" thay cho "Đã phát hết" gây hiểu lầm.
- Nhánh lỗi tải/xử lý thêm guard `!Task.isCancelled` + `ttsProcessingGeneration == expectedGeneration` (nhánh thành công vốn có) để task cũ không đếm nhầm. Log lỗi chương dùng `FileDescriptorCensus.describe` (domain/code từng tầng, không gọi `localizedDescription`).
- Gộp 6 khối "📖 Đã phát hết nội dung bộ truyện" chép lặp thành `advanceOrFinishBook(after:)`; `nextChapterIndex`/`advanceToNextChapter` bỏ `private`. `TTSManager.swift` 3550 → 3510 dòng (baseline 3470 vẫn vượt như trước).
- `rules.md`: bullet giới hạn bỏ qua chương trong mục "Chapter repository memory and cancellation invariants"; ngoại lệ `AppLogger.logAlways` ở §5.9; `FileDescriptorCensus.swift` trong cây thư mục `Logging/`.
- **Sửa theo review phản biện (không build được nên review thay compiler)**: (a) mở màn Cài đặt từng gọi `logFileSize` khi dựng view và đóng mất handle log — lúc đã cạn fd thì mọi dòng log sau đó mất âm thầm; nay `logFileSize`/`readLogContents` không đóng handle, handle mở `forUpdating` để "Sao chép nhật ký log" đọc qua chính nó, `clear()` cắt file về 0 qua handle thay vì xoá; (b) `AppLogger.init` gặp file > 5 MB thì giữ 1 MB cuối thay vì xoá hẳn, để lần mở lại app ngay sau sự cố không xoá mất log của sự cố; (c) census chạy trên serial queue `.utility` (không chặn main/TTS, bỏ lock), đã chụp lúc lỗi rồi thì không quét lại; (d) `describe` giữ câu mô tả lưu sẵn (`NSLocalizedDescriptionKey`, `errorDescription` của lỗi Swift) để log lỗi chương không mất text exception JS như log cũ.
- Chuyển entry `[1.3.487]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ (JSDom, TTSManager), 0 mới. **Không build tại chỗ** (Windows), cần CI/máy Mac. Không đụng `Tests/`.

## [1.3.516] - 2026-10-11

### docs: viet lai README.md theo trang thai hien tai cua app

Người dùng: *"merge code vào nhánh main và viết lại readme.md cho tôi"*.

- Fast-forward `main` lên `refactor/god-objects` (không có merge commit, `main` không có commit riêng).
- `README.md` viết lại: README cũ chỉ nói VBook/VietPhrase/NghiTTS và 3 engine TTS. Bản mới liệt kê đúng tính năng hiện có — 5 engine TTS (NghiTTS, VieNeu, Siri, Google, Extension), trợ lý AI (Gemini Web, OpenAI, Anthropic…), Quick Translation Rules, nhập/xuất nhiều định dạng, sao lưu Local/Google Drive/Telegram, hộp thư chương mới, debug server extension + extension VS Code; cập nhật cấu trúc `Sources/`, cách build, CI và chỉ dẫn đóng góp.
- Chuyển entry `[1.3.486]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- Chỉ đổi tài liệu, không đổi code.

## [1.3.515] - 2026-10-11

### fix(ai): dung AI mot lan la xong, quet ten rieng Gemini Web it luot hon va theo cong tac luu, bo nut X widget

Người dùng: *"lọc tên riêng nhiều chương chưa áp dụng config bật tắt tạm à, ngoài ra hãy giảm số batch để thích hợp với gemini web; bỏ nút x trong widget ai; có lỗi phải bấm nút dừng 2 lần trên dải đến batch mới mất dải batch trên top; hơn nữa dòng ai đang suy nghĩ cũng không mất đi khi bấm dừng"*. Plan duyệt trong chat.

- **Phải bấm dừng 2 lần mới mất dải batch**: bấm dừng thì coordinator xoá dải, nhưng request đang bay ném lỗi huỷ, vòng quét coi là "lỗi lẻ của một nhóm", bỏ qua rồi gọi `onProgress`; báo tiến độ chạy trong một `Task` mới (`Task.isCancelled` của nó luôn false) nên dựng lại dải. Sửa: vòng quét gặp huỷ thì thoát, không báo tiến độ; coordinator gắn `batchRunId` cho mỗi lần chạy và bỏ mọi báo cáo không khớp.
- **"AI đang suy nghĩ" không mất khi dừng**: luồng chat bị huỷ thoát ngay mà tin trợ lý trong `activeSession` vẫn `isStreaming`; màn AI đồng bộ ngược trạng thái đó, cộng một nhịp chữ có thể tới sau khi dừng. Sửa: `AIRuntimeCoordinator.stopActiveTask()` (view gọi thay `cancelActiveTask()`) huỷ rồi hoàn tất mọi tin đang chạy — tin rỗng ghi "Đã dừng." — và lưu phiên; nhịp chữ phải khớp `streamRunId` mới được ghi. Màn AI cũng hoàn tất tin của chính nó ngay khi bấm.
- **Quét tên riêng với Gemini Web**:
  - Gom chương liền nhau tới **~40.000 ký tự/lượt**, không cắt giữa chương (chỉ cắt khi một chương đơn lẻ dài hơn). Đã thử thật từ máy dev: 15k/40k/80k ký tự chữ Hán đều trả `Tên=Nghĩa` trong 5–9 s. Ví dụ 100 chương ~3.000 ký tự: 20 → ~8 lượt. Provider API giữ 5 chương/15.000 ký tự. Văn bản chương được đọc trước rồi mới chia lượt (tổng số lượt biết trước như cũ).
  - Theo công tắc "Lưu chat vào lịch sử Gemini": bật ⇒ cả lần quét là một cuộc chat nối tiếp (`GeminiWebClient.sendConversation`, mở cuộc chat mới sau mỗi 5 lượt để ngữ cảnh không phình; trạng thái chỉ giữ trong RAM — `persist: false` — để không đẩy trạng thái chat thật ra khỏi store); tắt ⇒ mỗi lượt là chat tạm độc lập như trước.
- **Bỏ nút X** trên widget AI thu nhỏ (`AIFloatingWidgetView`).
- `rules.md`: bullet mới về dừng/mã lần chạy trong mục Reader AI; bổ sung kích thước lượt quét vào mục Gemini Web.
- **Kiểm chứng**: đọc code + thử prompt lớn thật; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.514] - 2026-10-11

### feat(ai): Gemini Web noi tiep cuoc chat theo phien, cong tac luu chat vao lich su Gemini

Người dùng: *"mở gemini thấy trong đoạn chat không có chat mới"*, rồi *"làm cả 2 cách thì sao"*. Plan duyệt trong chat.

- **Vì sao trước đây không thấy**: mỗi lượt gửi `f.req[45] = 1` (chat tạm) và metadata rỗng ⇒ không vào lịch sử tài khoản, mỗi lượt là một cuộc chat mới gửi lại toàn bộ ngữ cảnh.
- **Đã thử thật** (chế độ khách): lượt 2 kèm metadata của lượt 1 ⇒ Gemini nhớ nội dung lượt 1, cùng cid — đúng cả khi chat tạm lẫn chat lưu.
- **Nối tiếp hội thoại (luôn bật)**: `GeminiWebClient.sendConversationStreaming` (file `+Conversation.swift`) — mỗi phiên chat của app ứng với một cuộc chat Gemini. Lượt đầu gửi đủ ngữ cảnh; lượt sau chỉ gửi tin mới, khối ngữ cảnh hệ thống đổi (so băm SHA-256 — sang chương khác, đổi chế độ, đổi từ điển…) thì kèm "Cập nhật ngữ cảnh". Mở cuộc chat mới khi đổi model (tránh 1050) hoặc đổi công tắc lưu; lượt nối tiếp bị từ chối trước khi có chữ ⇒ mở lại một lần với đủ ngữ cảnh (không áp cho lỗi tài khoản/hạn mức/timeout).
- **Công tắc "Lưu chat vào lịch sử Gemini"** trong hàng tài khoản Gemini Web (`geminiWebSaveHistory`, mặc định tắt): tắt = chat tạm như cũ; bật = mỗi phiên chat của app là **một** cuộc chat trên gemini.google.com.
- **Giao thức**: `GeminiWebRequestBuilder` nhận metadata 10 ô cho `f.req[2]` và cờ chat tạm; `GeminiWebResponseParser.conversationUpdate` đọc cid/rid (`inner[1]`), rcid (ứng viên `[0]`), ngữ cảnh (`inner[25]`); `GeminiWebConversationState.apply` chỉ ghi đè ô có giá trị (port setter của `gemini-webapi`).
- **Lưu trạng thái**: `GeminiWebConversationStore` (UserDefaults, theo id phiên, tối đa 100 cuộc chat gần nhất). **Lệch plan có chủ ý**: không lưu trong `AIChatSession` vì màn AI và `AIRuntimeCoordinator` cùng ghi phiên khi một lượt kết thúc ⇒ trường mới dễ bị ghi đè mất.
- **Không đổi**: quét tên riêng và "Kiểm tra kết nối" vẫn là chat tạm, không nối tiếp. `rules.md`: thay bullet "stateless" trong mục Gemini Web.
- **Kiểm chứng**: đọc code + thử nối tiếp hội thoại thật từ máy dev; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.513] - 2026-10-11

### perf(reader): tach trang thai highlight TTS khoi ReaderView - nhip highlight chi ve lai cac hang doan van

Người dùng: *"reader vẽ lại như vậy có vẻ khá dư thừa nhỉ, vẫn ở truyện đó thì sao phải vẽ lại liên tục, trong khi chỉ có highlight thay đổi thôi"*. Plan duyệt trong chat.

- **Nguyên nhân**: `ReaderTTSStateReader` có **một** `@Published snapshot` gộp trạng thái thô (đang phát, truyện/chương, widget) với phần mịn (`currentParentParagraphIndex`, `highlightRange`, vệt chuẩn bị); ReaderView `@StateObject` nó ⇒ mỗi câu TTS mới làm **cả thân ReaderView** (~2050 dòng) tính lại, kéo theo overlay, danh sách chương và nội dung mọi màn đang trình bày từ Reader (AI, Cài đặt AI, sheet). `scope(to:)` chỉ chặn highlight của truyện khác. Telemetry máy thật: `updateRPM=105.7`, `repeatUpdateRPM=40.4` khi nghe. Hệ quả đã gặp: sheet đăng nhập Gemini Web bị dựng lại 10 lần/30 s (1.3.512), danh sách chương phải bọc `.equatable()` (1.3.510).
- **Sửa**:
  - `ReaderTTSStateSnapshot` chỉ còn trường thô ⇒ `ReaderTTSStateReader` không publish theo highlight nữa.
  - `ReaderTTSHighlightReader` (file mới) giữ phần mịn, cùng cách gộp highlight của truyện khác thành snapshot trống. ReaderView giữ nó bằng **`@State`** (không `@StateObject` — ReaderView không được quan sát nó).
  - `ReaderTTSHighlightBinder` (file mới) bọc mỗi hàng đoạn văn, quan sát reader mịn và đưa vệt TTS/vệt chuẩn bị vào `ParagraphCardView` (logic chọn vệt y như cũ; thẻ vẫn `.equatable()` nên chỉ thẻ có vệt đổi chạm UIKit).
  - Tự cuộn theo đoạn đang đọc: `.onChange(of: ttsState.snapshot.currentParentParagraphIndex)` → `.background(ReaderTTSParagraphChangeObserver(…))` (file mới, `.onChange` trong view rỗng — giữ ngữ nghĩa chỉ gọi khi đổi).
  - `ReaderView+Controls`, `ReaderView+LoadingView` đọc `ttsHighlight.currentParentParagraphIndex` tức thời (không subscribe).
- ReaderView 2051 → 2045 dòng. `rules.md`: bullet mới về hợp đồng reader thô/mịn.
- **Kiểm chứng**: đọc code + rà soát độc lập 3 lăng kính (observation, tương đương hành vi, biên dịch) có phản biện; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Đo trên máy: so `ReaderEnergy updateRPM` trước/sau khi nghe TTS.

## [1.3.512] - 2026-10-11

### fix(ai): dang nhap Gemini Web trong trinh duyet bypass - WebView khong bi SwiftUI dung lai theo Reader

Người dùng: *"gemini web vẫn lỗi đó, vì sao bạn không dùng bypass browser"* kèm `app_logs (94).txt`. Plan duyệt trong chat.

- **Log phân định (giả thuyết 1.3.511 sai)**: không có dòng nào báo iOS kết thúc tiến trình web; thay vào đó `Tạo WKWebView đăng nhập` xuất hiện **10 lần trong 30 giây** — 3 khi mở, 4 khi quay lại từ Gmail (10:34:26), 3 ngay sau một nhịp TTS (10:34:29); mỗi lần kèm `.task` của một màn đăng nhập mới ⇒ SwiftUI dựng lại cả view, WKWebView mới nạp lại trang đăng nhập từ đầu.
- **Nguyên nhân**: sheet đăng nhập nằm đáy chuỗi `ReaderView → fullScreenCover AI → sheet Cài đặt AI → hàng Form (GeminiWebAccountRow) → sheet`. ReaderView vẽ lại theo từng highlight TTS và khi quay về từ nền (một `@Published snapshot` gộp cả `highlightRange`) nên SwiftUI tính lại nội dung mọi presentation bên dưới và dựng lại sheet gắn trên hàng Form. Quy tắc SwiftUI nội bộ chọn "dựng lại" thay vì "cập nhật" không đọc được từ code app; log cho thấy nó xảy ra.
- **Sửa**: `GeminiWebLoginLauncher` (file mới) mở trang đăng nhập trong **trình duyệt bypass** (`VisibleWebViewLoader` + `VisibleBrowserTabManager`, UIKit, sống suốt app, ngoài cây SwiftUI), `selectTab` để luôn mở toàn màn hình kể cả khi cài đặt "mở thu nhỏ" bật. Nhận biết xong bằng **host** `gemini.google.com` qua KVO `webView.url` (không so chuỗi con — URL đăng nhập chứa `continue=…gemini.google.com…`) ⇒ `refreshAfterLogin`, chờ 0,8 s, đóng tab; người dùng đóng tab trước ⇒ chỉ làm mới trạng thái. Vẫn giải phóng WKWebView ẩn khi bắt đầu đăng nhập. Log `🤖 [GeminiWebLogin]` mỗi điều hướng (host + path).
- `GeminiWebAccountRow` gọi launcher thay cho `.sheet`; xoá `GeminiWebLoginView.swift`, `GeminiWebLoginWebPane.swift` (cùng phần xử lý `webViewWebContentProcessDidTerminate` của 1.3.511 — không phải nguyên nhân). `rules.md`: bullet mới trong mục Gemini Web ("WKWebView mang trạng thái người dùng không được để SwiftUI sở hữu bên dưới Reader").
- Gốc rễ chung (ReaderView vẽ lại theo highlight) được xử lý riêng ở 1.3.513.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.511] - 2026-10-11

### fix(ai): dang nhap Gemini Web - khong tu tai lai khi iOS giai phong trang, log chan doan, giam RAM

Người dùng: *"có lỗi khi đăng nhập gemini web, khi web yêu cầu bấm số xác thực tôi chuyển qua gmail xác thực thì màn hình xác thực của app bị trở về màn hình đăng nhập ban đầu"*. Plan duyệt: `Docs/Plans/2026-10-11-plan-vieneu-search-geminilogin.md` mục 3.

- **Giả thuyết chính (cơ chế có bằng chứng, nhân quả cần log xác nhận)**: khi app ở nền, iOS có thể kết thúc tiến trình WebContent của trang đăng nhập. `GeminiWebLoginWebPane.Coordinator` **không** implement `webViewWebContentProcessDidTerminate` ⇒ WebKit tự tải lại trang khi view hiện lại (mã nguồn WebKit: `NavigationState.mm`, `WebPageProxy::tryReloadAfterProcessTermination`), và trang xác minh của Google mất trạng thái nên quay về bước nhập email. Đã loại trừ theo code: SwiftUI dựng lại pane (sẽ làm sheet đóng hẳn), cửa sổ ẩn của Gemini, xử lý `scenePhase` của app.
- **Không tự tải lại**: implement `webViewWebContentProcessDidTerminate` — ghi log, báo lên `GeminiWebLoginView` để footer hiện "iOS đã giải phóng trang đăng nhập khi app ở nền. Bấm Tải lại để tiếp tục." kèm nút **Tải lại** (`reloadToken` → `updateUIView` gọi `reload()`). Không gọi `reload()` ngay trong callback vì phá lớp chống vòng lặp crash 1 lần/30 s của WebKit.
- **Giảm RAM khi đăng nhập**: sheet mở ⇒ `GeminiWebClient.prepareForLogin()` → `GeminiWebSessionController.releaseWebViewIfIdle()` (file `+Account.swift`; `isIdle` = không fetch đang bay, không nạp trang dở) bỏ WKWebView ẩn — một tiến trình WebContent ít hơn; sau đăng nhập phiên vốn được nạp lại.
- **Mẹo trong footer**: "ở bước bấm số, chọn "Thử cách khác" → mã SMS. iOS gợi ý mã ngay trên bàn phím, không cần rời app."
- **Log chẩn đoán** `🤖 [GeminiWebLogin]`: tạo WKWebView kèm mã instance (hai dòng trong một lần mở sheet ⇒ pane bị dựng lại), mỗi điều hướng / commit / lỗi (chỉ host + path, không query vì chứa token), iOS kết thúc tiến trình, người dùng bấm Tải lại, `scenePhase` khi sheet đang mở.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`GeminiWebSessionController.swift` 393/400). **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Cần log từ máy thật (bật Logging trước) để xác nhận nguyên nhân.

## [1.3.510] - 2026-10-11

### fix(reader): tim chuong theo ten dang hien thi, khong phan biet hoa thuong va dau

Người dùng: *"tìm kiếm không được trong danh sách chương của reader"*, *"gõ số chương cũng không được, gõ đúng viết hoa cũng không được"*, *"tôi tìm xong thì dữ liệu không đổi theo tôi tìm nhưng tắt danh sách chương đi rồi mở lại vì có chữ tìm trong đó danh sách sẽ đổ kết quả tìm"*. Plan duyệt: `Docs/Plans/2026-10-11-plan-vieneu-search-geminilogin.md` mục 2.

- **Bằng chứng**: chạy đúng câu SQL tìm của app trên `chapter_store.sqlite` lấy từ máy người dùng (truyện `bookIdHash=88949c37`, 163/163 chương có `title_trans`): `100` → 2 kết quả, `chương 100` → 1, tên đầy đủ → 1. Truy vấn đúng; lỗi nằm ở tầng vẽ. Git: toàn bộ đường tìm không đổi từ 07–08/2026, thay đổi duy nhất là `c9e7c20a` (2026-10-09) cho `ReaderChapterListView` conform `Equatable` + `.equatable()`.
- **Nguyên nhân chính (thoái lui từ `c9e7c20a`)**: view thật có `@State searchQuery` và đọc store `@Observable` lại mang `==` (bỏ qua state, so store theo identity) dưới `.equatable()`; trên máy, body không chạy lại khi gõ hay khi kết quả về — chỉ chạy khi input `isPresented` đổi (đóng/mở danh sách). Trước commit đó `ReaderView` vẽ lại danh sách liên tục nên che mất chỗ hở. Các `@State` nội bộ khác (đảo thứ tự, đang cập nhật mục lục, đang tải chương lẻ, cache tên dịch) kẹt cùng kiểu.
- **Sửa gốc, giữ tối ưu**: `ReaderChapterListHost` (file mới) là vỏ **không trạng thái** mang `==` + `.equatable()`, body chỉ dựng `ReaderChapterListView`; xoá `ReaderChapterListView+Equatable.swift` nên view thật **không** còn `Equatable` ⇒ `@State`/Observation cập nhật bình thường, nhịp vẽ lại của `ReaderView` (highlight TTS) vẫn bị chặn ở vỏ. `ReaderView` chỉ đổi tên view ở chỗ mount.
- **Lọc trên tên đang hiển thị** (`ChapterTitleSearchMatcher`, file mới): `BackgroundSearchWorker` bỏ SQL `LIKE`, đọc `fetchOrderedTOC` rồi khớp trong Swift trên tên hiển thị (cùng cách chọn với `BackgroundPagingWorker`), tên gốc và `titleTrans`, không phân biệt hoa/thường, dấu, độ rộng; kiểm tra huỷ mỗi 200 chương. Sửa luôn: chương thiếu `title_trans` chỉ tìm được bằng chữ Hán (DB người dùng: 60/204 truyện thiếu một phần hoặc toàn bộ), "đại đế" không ra "Đại Đế" (`LIKE` chỉ gấp hoa/thường ASCII), `%`/`_` thành ký tự đại diện, lệch khi chuyển phồn→giản. Nhánh dự phòng `onlineChapters` dùng cùng bộ khớp. `ChapterStoreDatabase.searchChapters` giữ nguyên (không đổi schema), chỉ không còn được ô tìm gọi.
- **Tìm lại sau reset**: `updateChapters`, `reloadAllPages`, `updateTranslation` (cùng `updateSortOrder`) gọi `rerunSearchIfNeeded()` — trước đây kết quả bị xoá mà ô tìm vẫn giữ chữ.
- **Log** mỗi lượt tìm: `🔎 [ChapterSearch] bookIdHash=… len=… results=… ms=…` (không log từ khoá; `ms` gồm debounce 250 ms).
- **Kiểm chứng**: đọc code + thử SQL trên DB thật; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.509] - 2026-10-11

### feat(vieneu): bo lua chon 1 luong, mo ta cai dat gon va dung tac dung spin

Người dùng: *"Làm gọn bớt phần mô tả của mỗi config trong màn hình cài đặt tts của vieneu"*, *"gọn hơn nữa"*, *"1 luồng không tiết kiệm pin hơn lại còn lag hơn thì bỏ luôn option 1 luồng đi. Luồng chờ bận (spin) giải thích bậy quá, phải giải thích bật/tắt có hiệu quả gì"*. Plan duyệt: `Docs/Plans/2026-10-11-plan-vieneu-search-geminilogin.md` mục 1.

- **Bỏ "1 luồng"**: picker "Số luồng tổng hợp" còn 2/3/4. Kẹp ở `VieNeuSynthesisPolicy.threadCount(from:)` (`max(2, …)`) — đường đọc **duy nhất** của khoá `vieneuThreadCount`, nên giá trị 1 đã lưu (kể cả từ bản sao lưu cũ, vốn ghi thô) tự thành 2 ở UI, nạp engine, kiểm tra nạp lại và tạo giọng; setter `VieNeuTTSService.threadCount` cũng kẹp `max(2, …)`. Căn cứ: đo trên iPhone 1 luồng 0,63 CPU-s/audio-s như 2 luồng nhưng RTF 0,60 so với 0,32, hụt tiếng khi nóng.
- **Spin**: mô tả cũ nói về trạng thái *tắt* trong khi nhãn công tắc là trạng thái *bật*, kèm câu "chỉ để so sánh" khó hiểu. Mới: "Bật: luồng quay vòng chờ việc thay vì ngủ ngay, tốn CPU và nóng máy hơn mà không nhanh hơn. Nên để tắt." (`session.intra_op.allow_spinning`; iPhone 2 luồng: tắt 0,63 CPU-s/audio-s RTF 0,32, bật 0,76 RTF 0,38 — một lần đo, máy đã ấm nên không ghi % vào UI; audio giống hệt từng bit).
- **Mô tả gọn**: tốc độ tổng hợp gộp 2 dòng còn 1 ("Model nói nhanh hơn, máy mát hơn. 1.15x ít lặp chữ nhất, quá 1.25x mất chữ."); số luồng "Nhiều luồng ít chờ hơn nhưng nóng máy hơn." (+ " Tiết kiệm pin đang ghim Cân bằng + 2 luồng."); ngưỡng đệm "Nạp thêm khi đệm còn dưới N giây.".
- **Sửa tài liệu lệch code** (người dùng duyệt): doc `defaultThreadCount` ("Đã đo và giữ 4" trong khi giá trị là 2), `rules.md` "so 4 is kept" và "opt-in Tiết kiệm pin" (mặc định đang BẬT), doc `VieNeuTTSService.powerSaving`.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.508] - 2026-10-10

### feat(ai): Gemini Web - cho phep quet ten rieng nhieu chuong, nghi 2 s giua nhom, dung ro khi het han muc

Người dùng: *"đã chạy tốt, vì sao bạn không cho phép lọc name nhiều chương vậy"* — trước đó đã chọn phạm vi "chỉ chat" theo khuyến nghị (sợ hạn mức/chặn IP); nay giao thức chạy ổn nên mở. Plan duyệt trong chat.

- **Mở quét tên riêng** cho profile Gemini Web: bỏ hai chốt `unsupportedTask` trong `AINameExtractionBatchProcessor` (xoá luôn case khỏi `GeminiWebError`); `extractNamesFromText` rẽ nhánh `GeminiWebClient.sendChat` (prompt hệ thống + văn bản ≤ 15 000 ký tự đi qua `GeminiWebPromptFormatter`, parser `Tên gốc=Nghĩa` giữ nguyên).
- **Nghỉ 2 s giữa các nhóm** khi profile là Gemini Web (`try? Task.sleep`, không ném khi huỷ) — provider API giữ nhịp cũ.
- **Dừng rõ thay vì nuốt lỗi**: vòng quét đổi `try?` thành `do/catch`; `GeminiWebError.usageLimit`/`ipBlocked`/`notSignedIn`/`accountStatus` ⇒ ném `NSError` "Dừng quét sau N/M nhóm — <lý do> Các tên đã quét được vẫn hiện bên dưới." (coordinator giữ `batchExtractedNames` nên phần đã quét vẫn hiện); lỗi lẻ của một nhóm vẫn bỏ qua nhưng nay có log `🤖 [AI]`.
- Nhãn `GeminiWebAccountRow` đổi từ "chỉ chat" sang khuyến nghị quét bằng Flash (Pro có trần ~5/ngày miễn phí, ~100 gói Pro — theo trang hạn mức Gemini Apps của Google, số có thể đổi).
- `AIContextCompactor` vẫn bỏ qua Gemini Web (tiết kiệm hạn mức). `rules.md`: sửa bullet "Phạm vi" trong mục Gemini Web.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.507] - 2026-10-10

### fix(ai): Gemini Web - giu WKWebView an trong window de WebKit khong tam dung tien trinh web giua luc fetch

Người dùng: *"vẫn còn lỗi: Lỗi phản hồi: Gemini Web không phản hồi kịp thời gian chờ"* kèm `app_logs (93).txt`. Plan duyệt trong chat (bổ sung cho `Docs/Plans/2026-10-10-plan-gemini-web-no-response.md`).

- **Log phân định**: `StreamGenerate bắt đầu (…, idle 45 s)` → 45 s sau `timeout (idle 45 s, tổng 45 s, chunk=0)`. Không header, không chunk, không lỗi HTTP — trong khi từ máy dev cùng endpoint với body 38 KB Google trả header sau 1,3 s và xong sau 4 s. ⇒ JavaScript trong WKWebView ẩn **bị đóng băng**, không phải Google chậm.
- **Nguyên nhân**: WKWebView không nằm trong window nào ⇒ WebKit không giữ assertion cho tiến trình WebContent; hết page load là iOS tạm dừng tiến trình dù app foreground, `fetch()` đang bay đứng im. `WebViewLoader` bypass Cloudflare không gặp vì luôn có page load đang chạy và poll bằng `evaluateJavaScript` — nên đợt rà soát trước đã loại trừ nhầm điểm này.
- **Sửa**: `GeminiWebHiddenWindowHost` (file mới) tạo `UIWindow` 1×1 dưới cửa sổ chính (`normal − 1`, không chạm, alpha 0,02) chứa WKWebView ẩn; gắn khi tạo view và trước mỗi `fetch` (gắn lại nếu scene đổi), gỡ khi `releaseWebView()`. App vào background thì WebKit vẫn tạm dừng — đúng ý.
- **Thêm mốc log**: JS gửi `meta` khi `fetch` nhận response ⇒ `… nhận header sau N ms: <mã HTTP> <content-type>`, để lần sau phân biệt "không có header" với "có header, không có body".
- Tách `isSignedIn`/`signOut` sang `GeminiWebSessionController+Account.swift` để file chính dưới 400 dòng. `rules.md`: thêm 1 bullet vào mục "Gemini Web provider invariants".
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Cần người dùng thử lại với Logging bật: kỳ vọng thấy `nhận header sau … ms: 200 application/json` rồi `nhận chunk đầu`.

## [1.3.506] - 2026-10-10

### fix(ai): Gemini Web - phan hoi rong thanh loi, probe token tu didCommit, timeout theo chunk, log tung buoc

Người dùng: *"thêm provider gemini web và đăng nhập nhưng gửi requets ko có response về"*. Plan đã duyệt: `Docs/Plans/2026-10-10-plan-gemini-web-no-response.md`.

- **Đã kiểm chứng trước khi sửa**: từ máy dev (chế độ khách, cùng UA iOS Safari) với đúng payload/header app dựng: `StreamGenerate` trả 200 + text "OK" + `[8][0]==2` (cả đường có header model); `batchexecute otAQ7b` trả 1016 + model `Flash-Lite` ⇒ tên `gemini-flash-lite` đúng. Giao thức không phải thủ phạm. Rà soát độc lập (35 agent, 4 lăng kính, 3 phản biện/phát hiện): không có đường treo vô hạn ở tầng Swift/WebKit; message handler, cookie chia sẻ, CSP, nhánh `isGeminiWeb`, continuation đều loại trừ có bằng chứng.
- **Nguyên nhân 1 — phản hồi rỗng được coi là thành công** (likely): ứng viên có rcid nhưng thiếu `[1][0]` ⇒ `GenerateFrame(text: "")`; `consumeGeneration` chỉ guard "có ứng viên", không đọc cờ `completed`; `AIRuntimeCoordinator` gọi `onComplete("")`; `ReaderAIFullScreenView.messageRow` không vẽ tin trợ lý đã xong mà rỗng ⇒ bubble **biến mất, không lỗi, không toast, không log**. Thư viện tham chiếu coi "EOF mà chưa `[8][0]==2`" là lỗi "silently aborted by Google".
  - Sửa 3 tầng: `GeminiWebError.emptyResponse(completed:)` (retryable khi `completed == false` ⇒ vòng retry 1 lần sẵn có); `consumeGeneration` theo dõi `completed`, đếm frame, ném khi text rỗng; `AIRuntimeCoordinator` ném `AIEmptyResponseError` (file mới `Sources/Services/AI/AIEmptyResponseError.swift`, áp cho mọi provider) khi `accumulated` rỗng ⇒ "Lỗi phản hồi: …"; `messageRow` vẽ "(Không có nội dung)" cho tin đã xong mà rỗng.
- **Nguyên nhân 2 — chuỗi chờ nối tiếp không mốc trung gian** (possible): `prepare()` chờ `didFinish` (sự kiện `load` của SPA nặng) với `.reloadIgnoringLocalCacheData` tới 30 s dù `WIZ_global_data` có ngay khi HTML commit; `GetUserStatus` 30 s; `StreamGenerate` 90 s **tuyệt đối**; không log ở load/probe/finishStream/timeout ⇒ im lặng tới vài phút rồi mới ra timeout.
  - Sửa: probe token từ **`didCommit`** (trần commit 30 s + probe 45 s; chỉ ép tải lại khi `force`); timeout **theo chunk** (idle 45 s chat / 20 s batchexecute, trần tuyệt đối 240 s, watchdog 5 s/lần); trang tự điều hướng hoặc `prepare(force:)` khi còn fetch bay ⇒ fail ngay bằng `.documentChanged` (retryable); log `🤖 [GeminiWeb]` ở commit, probe, bắt đầu/chunk đầu/kết thúc/lỗi/timeout của mỗi fetch, và `🤖 [AI]` ở nhánh xong/lỗi của coordinator (không log nội dung/token).
- **Phụ**: `applyLoadedSession` rơi về `activeProfileId` khi profile ghim trong phiên không còn tồn tại (pill/model khớp request thật sự gửi).
- Tách `GeminiWebSessionController+Scripts.swift` (JS tiêm) và `+Delegates.swift` (WKNavigationDelegate/WKScriptMessageHandler) để file chính dưới 400 dòng. `rules.md`: cập nhật mục "Gemini Web provider invariants" (3 bullet).
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Hành vi thật cần log `[GeminiWeb]` từ máy người dùng (bật Logging trong Cài đặt trước — mặc định tắt mỗi lần mở app).

## [1.3.505] - 2026-10-10

### feat(ai): provider Gemini Web - dang nhap Google trong app, khong can API key

Người dùng: *"Tôi muốn thêm provider gemini web vào chế độ AI ở reader"* — chốt: đăng nhập Google trong app, lấy cookie tự động; phạm vi chỉ chat trong Reader. Plan đã duyệt: `Docs/Plans/2026-10-10-plan-gemini-web-provider.md`.

- **Cách nối**: WKWebView **ẩn** (không gắn window, giống `WebViewLoader`) nạp `gemini.google.com/app`, rồi chạy `fetch()` **trong chính trang đó** bằng `evaluateJavaScript`; body stream về Swift qua `WKScriptMessageHandler` (`GeminiWebSessionController`, 394 dòng). WebKit tự lo cookie xoay `__Secure-1PSIDTS`, Origin/Referer, TLS — không copy cookie sang `URLSession`. Token `SNlM0e`/`cfb2h`/`FdrFJe`/`TuX5cc` đọc từ `window.WIZ_global_data`.
- **Giao thức** (chép theo `gemini-webapi` 2026-10, không có tài liệu chính thức): `StreamGenerate` với `f.req` 81 ô (`[45]=1` temporary chat — không bẩn lịch sử Gemini của tài khoản), header model `x-goog-ext-525001261-jspb` dựng từ model khám phá qua RPC `otAQ7b` (`batchexecute`), frame `rt=c` độ dài theo **UTF-16** (`GeminiWebFrameParser`), field index tập trung ở `GeminiWebResponseParser`. Mã lỗi 1037/1050/1052/1060/1013 và trạng thái tài khoản 1016/1040/1042… thành `GeminiWebError` tiếng Việt.
- **Hội thoại stateless**: `GeminiWebPromptFormatter` ghép system prompt + 6 tin gần nhất thành một prompt có nhãn; không temperature, không tool calling. Frame mang text tích luỹ ⇒ `GeminiWebClient` đổi sang delta theo tiền tố, bản cuối khác thì nối sau dấu "— Gemini sửa lại câu trả lời —"; `AIRuntimeCoordinator` giữ nguyên.
- **Phạm vi**: chat + quick chips + test kết nối + "Load từ API" (khám phá model). `AIContextCompactor` bỏ qua nén; `AINameExtractionBatchProcessor` ném `unsupportedTask` **trước** vòng lặp batch (bên trong `try?` nuốt lỗi từng batch).
- **UI**: mẫu "Google Gemini (Web — đăng nhập)" và segment "Gemini Web" ở `AddProviderProfileSheet` + `AISettingsView`; profile Gemini Web ẩn Base URL/API Key/Temperature, thay bằng `GeminiWebAccountRow` (trạng thái + Đăng nhập Google/Đăng xuất) mở sheet `GeminiWebLoginView` (WKWebView hiển thị, cùng `WKWebsiteDataStore.default()`, tới `gemini.google.com` là tự đóng). Đăng xuất xoá cookie `*.google.com` — trình duyệt bypass cũng mất đăng nhập Google, alert nói rõ.
- **Model/Preset**: `AIProviderPreset.geminiWeb`, `AIProviderProfile.defaultGeminiWeb` (`apiFormat: "geminiWeb"`, `authType: "googleWebSession"`), `isGeminiWeb`.
- **File mới** (9 service ≤ 394 dòng, 3 view): `GeminiWeb{Error,InitSession,Model,RequestBuilder,FrameParser,ResponseParser,PromptFormatter,SessionController,Client}.swift`, `GeminiWeb{LoginWebPane,LoginView,AccountRow}.swift`. `rules.md`: mục "Gemini Web provider invariants (1.3.505)".
- **Rủi ro đã nêu trước khi duyệt**: Google có thể từ chối đăng nhập trong WKWebView (UA Safari như trình duyệt bypass thường qua được; chưa kiểm chứng được trên Windows); giao thức không chính thức, Google đổi là `protocolChanged`; tài khoản miễn phí có hạn mức (1037).
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.504] - 2026-10-10

### fix(ai): widget AI thu nho mo lai dung truyen dang chay, khong theo reader dang hien thi

Người dùng: *"khi vào reader truyện khác bấm vào widget thu nhỏ thì hiển thị chế độ AI không đúng truyện — truyện A đang chạy AI, thu nhỏ, sang truyện B bấm vào widget lại không hiển thị A mà hiển thị B"*.

- **Nguyên nhân**: `AIRuntimeCoordinator.presentFullScreen()` chỉ xét cờ `isReaderActive: Bool`. Reader B đang hiển thị ⇒ cờ bật ⇒ post `reopenReaderAI` ⇒ `ReaderView` của **B** bật `showingAIFullScreen` và dựng `ReaderAIFullScreenView(bookId: B)`; `initializeSessionAsync` thấy `activeSession.bookId (A) != B` nên nạp phiên của B.
- **Sửa**: thay cờ bằng `activeReaderBookId: String?` (Reader `onAppear` gán bookId của mình, `onDisappear` chỉ xoá khi còn đúng là mình — thứ tự appear/disappear giữa hai Reader không làm mất cờ). `presentFullScreen` chỉ đi đường `reopenReaderAI` khi `activeReaderBookId == activeContext.bookId`, kèm `userInfo["bookId"]` để `ReaderView` guard; mọi trường hợp khác (Reader truyện khác, Shelf, Discovery) đi đường UIKit `.overFullScreen` sẵn có với context của truyện đang chạy AI. Rule 1.3.397 giữ nguyên: không có đường `.fullScreen` nào.
- Hành vi mới: ở Reader B bấm widget ⇒ mở AI của **A** đè lên Reader B; đóng ⇒ về Reader B. Nút AI của chính Reader B vẫn mở AI của B như trước.
- `rules.md`: thêm 1 bullet vào mục "Reader AI FullScreen & Background Session Invariants".
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`ReaderView.swift` 2051/2053). **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.503] - 2026-10-09

### revert(vieneu): bo cong tac chong doc lap, ghi chu 1.15x it lap nhat de nguoi dung tu chinh

Người dùng: *"bỏ cái nút chống đọc lặp đi, ghi để người dùng biết 1.15 là ít lặp nhất và họ tự điều chỉnh là được. lần sau sửa phải có plan chờ tôi duyệt nhé"*.

- **Bỏ** cơ chế của 1.3.501: công tắc "Chống đọc lặp" (`VieNeuAntiRepeatToggle.swift` xoá), sàn tốc độ model 1,15 (`VieNeuSynthesisPolicy.modelSpeed`/`playbackCompensation`/`antiRepeatKey`), tốc độ phát đã bù (`TTSManager.localPlaybackRate`, `NghiAudioPlayerQueue.setRateForUpcoming`). Tốc độ đưa vào model lại đúng bằng tốc độ tổng hợp người dùng chọn; `TTSManager.swift` trả 2 dòng về `speed` (giữ 3550 dòng); màn Thử giọng + dòng chẩn đoán về như 1.3.500. Khoá `vieneuAntiRepeat` đã lưu trên máy (nếu có) không còn ai đọc — vô hại.
- **Thay bằng ghi chú** dưới thanh "Tốc độ tổng hợp (VieNeu)": *"Mẹo: 1.15x là mức ít bị đọc lặp chữ nhất (ở 1.00x thỉnh thoảng lặp kiểu "đến đó, đó là"); quá 1.25x bắt đầu mất chữ. Khi tăng tốc độ tổng hợp, hạ tốc độ phát tương ứng để giữ tốc độ nghe thực tế."* — dựa trên số đo của 1.3.501 (200 mẫu/mức: lặp 1,00 ≈ 7, 1,10 = 1, 1,15 = 1, 1,25 = 0), số đo ghi lại trong doc của `VieNeuSynthesisPolicy.synthesisSpeed` và `rules.md`.
- **Giữ** hai bản sửa phụ của 1.3.501 vì chúng sửa lỗi có sẵn của thanh tốc độ tổng hợp: đổi tốc độ ⇒ `resetNextChapterPrefixCache()` (prefix chương kế tổng hợp ở tốc độ cũ không còn lọt vào đầu chương sau) và đoạn hiện tại **chưa vào player** thì huỷ lượt đang bay + tổng hợp lại.
- Quy trình: từ nay mọi thay đổi code trình plan và chờ người dùng duyệt trước khi sửa.
- **Kiểm chứng**: grep `Sources/` không còn `modelSpeed`/`playbackCompensation`/`antiRepeat`/`localPlaybackRate`/`setRateForUpcoming`; `NghiAudioPlayerQueue.swift`, `VieNeuTTSTestView(+Diagnostics).swift` giống hệt 1.3.500; `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`TTSManager.swift` giữ 3550). **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.502] - 2026-10-09

### feat(vieneu): buoc thanh toc do tong hop 0.1 -> 0.05

Người dùng: *"sửa thêm step của thanh điều chỉnh tốc độ tổng hợp từ 0.1 -> 0.05"*.

- Hàng **"Tốc độ tổng hợp (VieNeu)"**: `Stepper` và `Slider` đổi bước 0,1 → **0,05** (dải 1,0–2,0 giữ nguyên) — chỉnh mịn được quanh vùng đã đo (1,10 / 1,15 / 1,25; xem 1.3.501).
- Bước 0,05 cộng dồn số thực ra kiểu `1.1500000000000001` ⇒ giá trị **lưu vào `UserDefaults`** được làm tròn 2 chữ số. Tốc độ đưa vào model, so sánh với sàn chống đọc lặp 1,15 và khoá `TTSSynthesisIdentity` (băm `×100`) vì vậy luôn sạch; nhãn hiển thị vốn đã `%.2f`.
- **Kiểm chứng**: `check_architecture.py` 2 vi phạm nền cũ, 0 mới. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`.

## [1.3.501] - 2026-10-09

### fix(vieneu): chong doc lap - model noi nhanh toi thieu 1.15x, phat cham lai bu dung ti le

Người dùng: *"spin=off thỉnh thoảng bị đọc lắp. ví dụ 'thiên thần' bị đọc thành 'thiên thần thần'… tìm cách fix cho tôi"* (log `app_logs (90).txt`), rồi *"không có cách nào fix à"* (sau khi tôi đề xuất tự chỉnh tốc độ tổng hợp).

- **Nguyên nhân (đo, không đoán)**: VieNeu thỉnh thoảng đọc **lặp một âm tiết** ("đến đó, đó là", "làm được được", "Mất, mất tích") khi model được cấp **dư** thời gian so với số chữ; ngẫu nhiên theo nhiễu đầu vào nhưng dồn vào một số câu. Thực nghiệm PC mô phỏng đúng app (fast/8 bước/cfg 3, 25 câu thật của log 90 × 8 seed = 200 mẫu/mức, Whisper small đếm từ lặp, lọc tay lỗi ASR, xác nhận lại từng file lẻ): lặp thật **1,00 ≈ 7 | 1,10 = 1 | 1,15 = 1 | 1,25 = 0**; độ rõ (WER) như nhau tới 1,25, 1,40 bắt đầu mất chữ. Sway 0 / cfg 2 / nhiễu ×0,8 / nới thời lượng +5 % **không** đỡ (nới còn tệ hơn); 16 bước chỉ giảm một nửa mà gấp đôi CPU; kẹp thời lượng/âm vị chỉ chữa câu cực ngắn. Spin và số luồng cho audio **giống hệt từng bit** ⇒ không liên quan; phoneme đúng (người dùng đã kiểm trước).
- **Sửa — công tắc "Chống đọc lặp" (mặc định bật)** trong Cài đặt VieNeu (`VieNeuAntiRepeatToggle`, dưới thanh Tốc độ tổng hợp): tốc độ đưa vào model = `max(tốc độ tổng hợp, 1,15)` (`VieNeuSynthesisPolicy.modelSpeed`, hàm thuần), và tốc độ phát của player local chia đúng hệ số bù (`TTSManager.localPlaybackRate` = `speed / playbackCompensation`) ⇒ **tốc độ nghe giữ nguyên** (= tốc độ tổng hợp người dùng chọn × tốc độ phát), lỗi lặp giảm ~85 %, lợi phụ ~13 % CPU (ít frame hơn). Mọi đường tổng hợp VieNeu lấy tốc độ qua `localSynthesisSpeed(forTool:)`; `TTSManager.swift` chỉ đổi 2 dòng (`updateRate`/`start(rate:)` dùng `localPlaybackRate`), không tăng dòng. NghiTTS không đổi.
- **Đổi giữa lúc nghe** (công tắc hoặc tốc độ tổng hợp, cùng đường `invalidateVieNeuSynthesisSpeed`): đoạn đang phát giữ nguyên tốc độ cũ, các đoạn sau dựng player với tốc độ mới (`NghiAudioPlayerQueue.setRateForUpcoming`). Review tìm 2 chỗ audio tốc độ cũ còn lọt, đã sửa: prefix chương kế đã tổng hợp (khoá không có tốc độ model) ⇒ `resetNextChapterPrefixCache()` — lỗi này có sẵn từ trước với thanh tốc độ tổng hợp; đoạn hiện tại **chưa vào player** (đang hụt tiếng) ⇒ huỷ lượt đang bay, bỏ audio, `speakCurrent()` tổng hợp lại.
- Màn **Thử giọng** VieNeu dùng cùng tốc độ model + tốc độ phát đã bù (trước đó bỏ qua công tắc ⇒ người dùng sẽ tưởng công tắc vô tác dụng); dòng chẩn đoán thêm "tốc độ model (phát thật)". Log `[TTSRoute] doi toc do tong hop` ghi cả tốc độ model và tốc độ phát đã bù.
- **Giới hạn đã biết** (ghi ở `rules.md`): tốc độ phát VieNeu < 0,575× thì tốc độ phát đã bù bị kẹp ở sàn 0,5× ⇒ nghe nhanh hơn tối đa 15 %. Mẫu nghe trước/sau: `Docs/Reports/tts-samples-2026-10-10-doc-lap/` (gitignored).
- **Kiểm chứng**: `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`TTSManager.swift` giữ 3550 dòng). Review đối kháng 2 lượt: biên dịch 0 lỗi; hành vi 4 lỗi — 3 đã sửa ở trên, 1 ghi là giới hạn. **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Thử trên máy: nghe VieNeu như thường (công tắc mặc định bật) — `[VieNeuPerf] synthSpeed=1.15x`, tốc độ nghe không đổi; tắt công tắc để so.

## [1.3.500] - 2026-10-09

### feat(vieneu): doi spin/so luong ORT co hieu luc ngay o luot tong hop ke tiep, khong can tat app

Người dùng: *"có thể làm spin=on/off tác dụng ngay sau khi bật không, hiện tại phải tắt mở máy lại khá phiền"*.

- **Trước**: số luồng ORT và spin chỉ đặt được lúc dựng session, mà `VieNeuTTSEngine` là singleton không bao giờ unload ⇒ đổi trong Cài đặt chỉ có hiệu lực sau khi **tắt hẳn app** (bẫy đo log 85–87).
- **Nay**: `VieNeuTTSEngine+Reload.swift` (mới) — `runtimeNeedsLoadLocked()` chạy ở đầu `prepareLocked()` (tức **mỗi lượt tổng hợp**, đang giữ `lock`): so `threadCount`/`allowSpinning` của runtime **đang chạy** (lưu trên `VieNeuONNXRuntime` từ 1.3.497) với `VieNeuSynthesisPolicy.effectiveThreadCount`/`allowSpinning` (gồm cả "Tiết kiệm pin" ghim 2 luồng); lệch ⇒ log `Cài đặt đổi (threads a→b, spin x→y) — nạp lại engine`, bỏ runtime cũ rồi nạp lại ngay lượt đó (~3 s). Runtime cũ được giải phóng (session + tensor cache A2b qua `VieNeuORTDestroy`) **trước** khi dựng cái mới ⇒ không nhân đôi bộ nhớ, và không cache nào còn trỏ vào `nullContext` cũ khi nó bị gán lại. Chi phí khi không đổi: 3 lần đọc `UserDefaults` mỗi lượt.
- `VieNeuTTSEngine.swift` chỉ đổi dòng tại chỗ (`runtime` thành `internal` cho `+Reload`, guard của `prepareLocked`, comment về tensor cache); giữ 398 dòng.
- Chú thích UI (công tắc spin, số luồng) đổi thành "có hiệu lực từ lượt tổng hợp kế tiếp (engine tự nạp lại, chờ khoảng 3 giây)"; comment ở `VieNeuONNXRuntime`/`+Adaptive`/`VieNeuTTSService` và `rules.md` (dòng về số luồng ORT) cập nhật theo.
- Bối cảnh: P3 (gộp CFG thành một lượt `Run` batch=2) **giữ lại, chưa làm** (người dùng chốt sau khi hỏi lại): CPU-time gần như không đổi (nhiệt ≈ như cũ) nhưng tổng hợp nhanh hơn ⇒ bớt hụt tiếng khi máy nóng; làm sau khi chốt lỗi đọc lắp, dạng công tắc A/B — trạng thái + lý do ghi ở mục P3 của `Docs/Reports/2026-10-09-vieneu-huong-toi-uu-moi.md`.
- **Kiểm chứng**: `check_architecture.py` 2 vi phạm nền cũ, 0 mới (`VieNeuTTSEngine.swift` giữ 398 dòng). **Không build tại chỗ** (Windows) — CI nhánh `refactor/god-objects`. Thử trên máy: bật log → đổi spin hoặc số luồng trong Cài đặt VieNeu (không tắt app) → log có `Cài đặt đổi (threads …→…, spin …→…) — nạp lại engine` rồi `Nạp xong engine: … threads=… spin=…`, và `[VieNeuPerf] … threads=… spin=…` khớp cài đặt mới.
