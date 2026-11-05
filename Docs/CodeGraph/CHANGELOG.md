# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.728] - 2026-11-05

### feat: màn Dung lượng xem app chiếm bao nhiêu theo loại dữ liệu, xoá cache ảnh, file xuất và log

Người dùng: *"tôi muốn thêm kiểm tra dung lượng đã dùng trên máy có là được không?"*. Chốt theo mockup: xoá mục an toàn (có hỏi xác nhận), chưa cần xem theo từng truyện.

- **Cài đặt › Thư Viện** thêm hàng **Dung lượng** (icon `cylinder.split.1x2` như mockup), đặt trên "Sao lưu & khôi phục dữ liệu". Hàng không hiện số: đo cả cây thư mục mỗi lần mở Cài đặt là tốn.
- **Màn Dung lượng** (`StorageUsageView`, trang đẩy vào, tiêu đề giữa, nút ↻ đo lại):
  - Thẻ đầu: "App đang dùng" + số lớn. Thanh chia theo tỉ lệ: 3 loại lớn nhất màu riêng (teal/tím/cam, không dùng màu nhấn), còn lại xám. Dòng "Máy đã dùng X / Y · Còn trống Z".
  - Danh sách panel (`.bookListPanelRow()`), xếp lớn → nhỏ, bỏ loại 0 byte.
  - Ba loại xoá được có nút chữ đỏ **Xoá** + `confirmationDialog` kèm lời nhắc; xoá xong đo lại và toast "Đã xoá … (số đã giải phóng)".
- **`Services/Storage/`** (mới):
  - `StorageUsageCategory`: 15 loại theo đúng thư mục app ghi: `books/`, `videos/`, `comics/`, `Caches/comic_images/`, `chapters/`, `translate/`, `covers/`, `extensions/` + `extension_store/`, `FreeBook/`, `adblock/`, `backups/`, `library.db*`, `Documents/Exports/`, `app_logs*`, Khác.
  - `StorageUsageScanner`:
    - Đo dung lượng thật trên đĩa (`totalFileAllocatedSize`), đếm cả file ẩn, không theo symlink. `BackupPaths.directorySize` giữ nguyên cho Sao lưu.
    - **Khác** = cả thư mục nhà của app trừ các loại đã liệt kê ⇒ tổng khớp dung lượng thật.
    - Dung lượng máy qua `volumeAvailableCapacityForImportantUsage` / `volumeTotalCapacity`.
  - `StorageUsageSnapshot`: kết quả bất biến.
  - `StorageUsageCleaner`: chỉ gọi đường xoá có sẵn của từng owner.
- **Đường xoá**:
  - `ComicImageLoader.clearDiskCache()` → `ComicImageDiskCache.removeAllAndWait()` (mới, chờ xoá xong; `removeAll()` cũ dùng chung thân).
  - `DownloadManager.clearFinishedExportTasks()` (mới, `@MainActor`): như `clearFinishedTasks()` nhưng **chỉ tác vụ xuất** đã xong/lỗi/huỷ — xoá hàng + file của chúng. Không còn tác vụ xuất nào chạy ⇒ dọn mục mồ côi trong `Exports/`. Đợi xoá file xong, không tự báo toast.
  - `AppLogger.shared.clear()` (có sẵn).
- `CLAUDE.md` / `AGENTS.md`: mục lưu trữ ghi thêm "thêm thư mục dữ liệu mới thì thêm vào `StorageUsageCategory`".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. `DownloadManager+TaskStore.swift` 387/400 dòng.
  - Không build tại chỗ (Windows).
  - Chưa thử trên máy: số liệu so với Cài đặt iOS (app chạy trong LiveContainer nên iOS tính chung vào LiveContainer), xoá ba loại, bản đang xuất không bị xoá.

## [1.3.727] - 2026-11-05

### feat: báo có bản cập nhật mới trong app, dải báo ở Kệ và hàng ở Cài đặt

Người dùng: *"có thể thì thông báo có bản cập nhập mới trong app để user biết"*. Chốt theo mockup bản 4:
- Dải báo không có nút cập nhật; phải bấm vào xem thay đổi.
- Icon cập nhật kiểu mockup (`arrow.down.square`), không dùng chuông, không ghi vào Trung tâm thông báo, không ghi số thay đổi.
- Thêm hàng ở Cài đặt và chấm đỏ tab Cài Đặt.
- Kiểm tra khi mở app và khi quay lại app, giãn cách 6 giờ.
- Giữ nút "Mở LiveContainer" để thử trên máy.

- **`Services/AppUpdate/`** (mới, không `import SwiftUI`):
  - `AppUpdateSourceClient`: đọc `apps.json` ở nhánh `source` (raw GitHub, timeout 15 s, bỏ cache cục bộ). Lấy `apps[0].versions[0]`.
  - `AppUpdateInfo`: `version`, `buildNumber`, `date`, `notes` (mỗi commit một dòng, bỏ tiền tố `- `).
  - `AppUpdateRepository` (`@MainActor @Observable`, nguồn sự thật duy nhất):
    - Có bản mới ⇔ số build của nguồn > `CFBundleVersion` đang chạy. Bản build tay (số build 1) luôn thấy báo.
    - `checkIfNeeded()` giãn cách 6 giờ (`appUpdateLastCheckAt`). Bản đọc được cuối lưu ở `appUpdateLatestJSON`. Lỗi ⇒ log `❌ [AppUpdate]`, giữ kết quả cũ.
    - Ẩn / bỏ qua / đã xem nhớ **theo số build** (`appUpdateDismissedBuild`, `appUpdateSkippedBuild`, `appUpdateSeenBuild`) ⇒ bản mới hơn nữa ra là báo lại.
- **Dải báo Kệ** (`AppUpdateBanner`, dưới dải "mất nguồn", chỉ tab Kệ sách):
  - Dòng "Có bản mới 1.3.NNN · xem thay đổi ›" + ×, cùng kiểu panel `MissingSourceRebindBanner`.
  - Bấm ⇒ sheet. × ⇒ ẩn tới bản sau.
- **Sheet** (`AppUpdateSheet`):
  - Tiêu đề + "bản mới · đang dùng".
  - Danh sách thay đổi.
  - "Cách cập nhật: Mở LiveContainer › Sources › Refresh › Install, chọn thay app cũ để giữ dữ liệu".
  - Nút **Mở LiveContainer** và **Bỏ qua bản này**. Mở sheet ⇒ đánh dấu đã xem.
- **Cài đặt › Thông Tin**: hàng "Có bản mới 1.3.NNN" (chấm đỏ khi chưa xem) mở cùng sheet. Hàng vẫn còn sau khi bấm × ở Kệ, chỉ mất khi bỏ qua hoặc đã lên bản đó.
- **Tab Cài Đặt** (`MainTabBar`): chấm đỏ 8pt khi có bản mới chưa xem. Badge chương mới của tab Kệ giữ nguyên.
- **Kích hoạt** (`MainTabView`): `.task(priority: .utility)` lúc mở app + khi `scenePhase` về `.active`.
- **Vì sao không có nút "Cập nhật ngay"** (đọc mã LiveContainer `TweakLoader/UIKit+GuestHooks.m`):
  - App đang chạy bên trong LiveContainer gọi `livecontainer://install?url=…` ⇒ LiveContainer chỉ báo "Vui lòng mở lại LiveContainer để cài app", không cài.
  - Nút "Mở LiveContainer" dùng `livecontainer://livecontainer-launch?bundle-name=ui` (hộp xác nhận rồi về màn chính LiveContainer). Không mở được ⇒ toast lỗi.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Báo có bản mới trong app".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows).
  - Chưa thử trên máy: dải báo / × / bỏ qua, chấm đỏ, và nút "Mở LiveContainer" có chuyển về màn chính LiveContainer không.

## [1.3.726] - 2026-11-05

### chore: bỏ nút thêm nguồn LiveContainer, tin Telegram gửi link apps.json thay link release

Người dùng: *"không cần nút này, bỏ nút này và nút copy đi giúp tôi, gửi chung link app.json với tele là được, cũng không cần gửi link realase chung tele"*.

- **Cài đặt › Thông Tin**: bỏ hàng "Thêm nguồn cập nhật vào LiveContainer" và nút sao chép link nguồn (thêm ở 1.3.724). Chỉ còn dòng "Phiên bản ứng dụng".
  - Xoá `AppDistributionSource` (`Sources/Common/Utils/`), không còn nơi dùng.
- **Tin Telegram** (`build-ipa.yml`):
  - Bước Publish ghi `SOURCE_URL` (link `apps.json` ở nhánh `source`) thay cho `RELEASE_URL`.
  - Caption gửi IPA kết thúc bằng `📲 Nguồn LiveContainer: <link apps.json>`, **không** còn link release.
  - File quá 50 MB: link tải transfer.sh như trước, kèm dòng nguồn LiveContainer.
  - Dòng thừa đổi thành `… và K commit khác` (bỏ "(xem release)").
- Release `build-*` vẫn tạo như cũ (để `apps.json` có link tải IPA), chỉ không gửi link của nó qua Telegram.
- `CLAUDE.md` / `AGENTS.md`: sửa đoạn "Nguồn cập nhật LiveContainer" và "Tin Telegram + ghi chú release liệt kê mọi commit".
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; YAML hợp lệ; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Commit này đổi `Sources/**` ⇒ kích hoạt build. Lượt đó cũng là lần đầu chạy thật phần liệt kê mọi commit của 1.3.725: tin Telegram phải có 2 commit (1.3.725, 1.3.726) và dòng nguồn LiveContainer.
  - Chưa thử trên máy.

## [1.3.725] - 2026-11-05

### feat: tin Telegram và ghi chú release liệt kê mọi commit của lượt build, gửi lại khi lỗi

Người dùng (qua /grill-me): chia việc cho session con thì *"việc push và build làm cuối cùng sau khi các việc của session con đã xong hết … nội dung commit phải chứa đủ những thứ đã sửa"*. Chốt: giữ commit riêng, session chính push một lần. Thêm: *"nhớ cắt tin nhắn trước khi gửi tele để đảm bảo không bị lỗi tin quá dài nhé. và nhớ check tin nhắn đã được gửi, nếu chưa được thì thử lại 2 lần"*.

- **Trước đây**: CI chỉ đọc `git log -1`. Một lượt push mang nhiều commit thì caption Telegram, ghi chú release và `localizedDescription` của `apps.json` chỉ có commit cuối. `curl … || echo` coi mọi phản hồi là đã gửi, kể cả 400/429.
- **Bước mới `Collect Commit List`** (`build-ipa.yml`):
  - SHA lần build xanh trước trên `main` lấy qua `gh run list` (job thêm `permissions: actions: read`).
  - Danh sách commit lấy qua `gh api repos/…/compare/<cũ>...<mới>` (checkout chỉ có 1 commit). Mỗi commit lấy dòng đầu, cũ → mới, ghi `build/commit_subjects.txt`.
  - Không lấy được ⇒ commit cuối như trước.
- **`Scripts/ci/telegram_commit_summary.py`** (mới): dựng tin `💬 N commit:` + `• <subject>`; một commit giữ dạng `💬 Commit: …`.
  - **Cắt vừa giới hạn trước khi gửi**, đếm theo UTF-16 như Telegram (emoji = 2): caption gửi IPA 1024, tin 4096. Có chừa chỗ cho dòng link. Thừa ⇒ `… và K commit khác (xem release)`.
  - `--format notes` ⇒ danh sách đầy đủ cho ghi chú release, nên LiveContainer cũng thấy đủ.
  - In UTF-8 bất kể bảng mã console.
- **`Scripts/ci/telegram_send.sh`** (mới, `tg_call`): coi là đã gửi **chỉ khi** phản hồi có `"ok":true`. Lỗi ⇒ thử lại **2 lần** (nghỉ 5 s, 10 s). Hết lượt ⇒ `::warning::`, không làm đỏ build (để không gửi nhầm tin "Build Thất Bại").
  - Dùng cho cả 3 tin: gửi IPA, file quá 50 MB, build thất bại.
  - Caption/`chat_id` gửi bằng `--form-string` ⇒ subject có `@`, `<`, `;type=` không bị curl hiểu nhầm.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Tin Telegram + ghi chú release liệt kê mọi commit" ở mục CI.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Tại chỗ: API so sánh `4cefa5f7...a7a5aba2` trả đúng 3 subject. Caption 3 commit đúng dạng. 40 commit cắt còn 978/1024 đơn vị UTF-16 kèm "… và 28 commit khác". `tg_call` với curl giả (lỗi 2 lần rồi ok ⇒ gửi ở lần 3; luôn lỗi ⇒ trả 1 sau 3 lần). YAML hợp lệ.
  - Commit này không đổi `Sources/**`/`project.yml` ⇒ không kích hoạt build. Lượt build thật kế tiếp là lần kiểm đầu tiên trên CI.

## [1.3.724] - 2026-11-05

### feat: CI đăng IPA lên GitHub Release và cập nhật nguồn LiveContainer, giữ 5 bản mới nhất

Người dùng: *"có cách tạo nguồn app để livecontainer update không?"*. Duyệt plan: *"Chỉ giữ 5 bản gần nhất là ok, không bỏ GOOGLE_CLOUD_TTS_API_KEY đâu"*.

- **LiveContainer** có tab Sources đọc nguồn kiểu AltStore: thêm bằng URL hoặc link `livecontainer://source?url=…`; `Refresh` rồi `Install` cài bản mới nhất của nguồn.
- **CI** (`build-ipa.yml`), bước mới `Publish GitHub Release + LiveContainer Source`. Chỉ chạy với push lên `main`, không chạy với PR. `continue-on-error` ⇒ lỗi đăng không làm đỏ build, IPA vẫn gửi Telegram.
  - Script `Scripts/ci/publish_altstore_source.py` (mới):
    - Tạo release `build-<số build>` kèm `TangCongCac-<version>-<số build>.ipa`, ghi chú = subject commit. Chạy lại workflow (cùng số build) ⇒ xoá release cũ cùng tag rồi tạo lại.
    - Chỉ giữ **5** release `build-*` mới nhất; release cũ hơn xoá kèm tag (`--cleanup-tag`).
    - Dựng `apps.json` (định dạng nguồn AltStore: `versions` + các trường một bản kiểu cũ) từ 5 release còn lại. Ghi kèm `icon.png` (`icon_60_3x.png`) và `README.md` lên nhánh riêng **`source`** (orphan, không phải `main` ⇒ không kích hoạt build, không đụng lịch sử code).
    - Push bị từ chối (hai lượt build đẩy cùng lúc) ⇒ tải lại nhánh, dựng lại từ danh sách release mới nhất, thử tối đa 3 lần.
  - Job có `permissions: contents: write`.
  - Caption Telegram thêm dòng `🔗 Release: …` khi đăng thành công; file quá 50 MB thì gửi link release thay cho transfer.sh.
- **URL nguồn cố định:** `https://raw.githubusercontent.com/buudvh/FreeBook/source/apps.json`.
- **App:**
  - `AppDistributionSource` mới (`Sources/Common/Utils/`) giữ URL nguồn và dựng link `livecontainer://source?url=…`.
  - Cài đặt › Thông Tin thêm hàng "Thêm nguồn cập nhật vào LiveContainer" (mở LiveContainer; không mở được ⇒ toast lỗi) và nút sao chép link nguồn (`ClipboardCopier`, toast "Đã sao chép link nguồn").
- **Khoá Google Cloud TTS:** repo công khai ⇒ IPA trên Release ai cũng tải được và đọc được `GOOGLE_CLOUD_TTS_API_KEY` trong `Info.plist`. Người dùng chọn giữ khoá trong IPA.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Nguồn cập nhật LiveContainer" ở mục CI.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; cú pháp script Python và YAML hợp lệ; thử đọc danh sách release thật bằng `gh` (chỉ đọc).
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Lượt CI của chính commit này là lượt đầu tiên tạo release và nhánh `source`.
  - Chưa thử trên máy: thêm nguồn trong LiveContainer, cài đè bản mới có giữ dữ liệu không (tài liệu LiveContainer không nói).

## [1.3.723] - 2026-11-05

### feat: version app tự nâng theo số bản CHANGELOG mỗi lần CI build

Người dùng: *"tôi muốn tự nâng ver mỗi khi build thành công"*. Người dùng chọn phương án "Theo CHANGELOG" (không dùng bộ đếm riêng có CI commit ngược).

- **Trước đây**: `project.yml` không khai version ⇒ app mang mặc định của Xcode. Màn Cài đặt › Thông Tin ghi cứng `1.0.0`; caption Telegram không có version.
- **CI** (`build-ipa.yml`):
  - Bước mới `Resolve App Version` lấy số bản đầu `Docs/CodeGraph/CHANGELOG.md` (`## [1.3.NNN]`) làm `APP_VERSION` và `github.run_number` làm `BUILD_NUMBER`. Không đọc được số bản ⇒ cảnh báo + dùng `1.3.0`.
  - `xcodebuild archive` nhận thêm `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
  - Bước đóng gói chốt lại `CFBundleShortVersionString` / `CFBundleVersion` trong `Info.plist` của IPA bằng `plutil` và in ra log.
  - Caption Telegram (thành công, file quá 50 MB, thất bại) có `1.3.NNN (số build)`.
  - CI **không** commit ngược về repo ⇒ không có vòng build lặp, không xung đột với các session commit trên main.
- **`project.yml`**: `CFBundleShortVersionString: "$(MARKETING_VERSION)"`, `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"`. Mặc định cho bản build tay: `MARKETING_VERSION: "1.3.0"`, `CURRENT_PROJECT_VERSION: "1"`.
- **App**:
  - `AppVersionInfo` mới (`Sources/Common/Utils/`) đọc hai khoá trên, dạng hiển thị `1.3.723 (412)`.
  - Màn Cài đặt › Thông Tin hiện version thật thay cho `1.0.0`.
  - `BackupManifest.runningAppVersion` dùng chung `AppVersionInfo.display` (kết quả như cũ).
- **Hệ quả**: commit quên thêm entry CHANGELOG mới thì version không đổi, chỉ số build tăng.
- `CLAUDE.md` / `AGENTS.md`: thêm đoạn "Version app tự nâng theo CHANGELOG" ở mục CI.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows). Lượt CI của chính commit này là lượt kiểm đầu tiên: log bước `Resolve App Version` và dòng `Info.plist version:` phải ra `1.3.723 (<số lượt>)`. Chưa thử trên máy.

## [1.3.722] - 2026-11-05

### fix: Khám phá đổi nguồn thì tab trùng tên tải lại theo nguồn mới

Người dùng: *"Có lỗi khi chuyển ext mở lại tab cũ không được load lại. Ví dụ đang xem tab đồng nhân ext qidian rồi chuyển sang ext stv mở lại tab đồng nhân vẫn hiển thị dữ liệu cũ"*.

- **Nguyên nhân** (`DiscoveryView`):
  - Trang tab trong `TabView` được nhận diện bằng `CategoryResult.id` (= `title + "_" + input`) cộng `.id(catalogConfigStamp)`, không có nguồn.
  - Bộ nạp của tab (`PaginatedNovelLoader`, `@StateObject` của `DiscoveryCategoryTabView`) chỉ tạo một lần, với `localPath`/`configJson` của lần dựng đầu.
  - Đổi nguồn có xoá `homeItems`, nhưng nguồn mới có `explore` thì `loadDiscoveryData` thêm lại tab section **ngay** ⇒ màn chờ không hiện, khung tab không bị dựng lại.
  - Tab của nguồn mới trùng tên + input với tab của nguồn cũ (vd "Đồng nhân" của qidian và STV) ⇒ SwiftUI giữ nguyên trang, kèm bộ nạp vẫn trỏ vào nguồn cũ. Tab section (`ExploreSectionsView`, id cố định) bị y như vậy.
- **Sửa**:
  - Trang tab danh mục và tab section gắn `.id("\(packageId)#\(catalogConfigStamp)")` ⇒ đổi nguồn hay đổi config đều dựng lại với bộ nạp mới.
  - Tab Thể loại gắn `.id(selectedExtensionId)` ⇒ đổi nguồn thì ô tìm thể loại về rỗng.
  - Tải lại khi đổi config giữ nguyên như cũ.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng:**
  - Đọc code + diff; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy: đổi qua lại hai nguồn có tab trùng tên, đổi config của nguồn đang xem.

## [1.3.721] - 2026-11-05

### fix: chip nghĩa theo đúng thứ tự màn quản lý, chỉ còn Name/VP

Người dùng: *"Thanh chip màn hình dịch và nội dung trong màn hình quản lý nghĩa khác nhau (xem hình). Ngoài ra có trường hợp chip không hiển thị badge (như hình 3), xảy ra với chữ ngươi"*. Người dùng chọn: chip chỉ còn Name/VP, Phiên âm giữ ở cuối hàng.

- **Nguyên nhân**:
  - `suggestionChips(from:)` dựng chip theo thứ tự của `dictionaryMatches`: Name → Xưng hô → Luật nhân → VP → Phiên âm.
  - `dictionaryMatches` luôn có Xưng hô / Luật nhân, kể cả khi công tắc dịch của chúng tắt. Pipeline (`lookupRawTranslation`) chỉ dùng hai nguồn này khi bật.
  - Pronouns của người dùng có `县丞=huyện thừa` ⇒ chip đầu là "huyện thừa" của Xưng hô. Nghĩa thứ 3 của VP Chung trùng chữ, gộp vào và nâng chip đó lên badge C ⇒ trông như VP Chung xếp "huyện thừa" đầu. Màn Quản lý nghĩa (chỉ 4 mục Name/VP Riêng/Chung) thì ghi `Huyện Thừa/Huyện thừa/huyện thừa`.
  - Nghĩa chỉ có ở Xưng hô không mượn được badge nên nằm giữa hàng mà không có badge (vd `你们` → "các người", "mọi người").
- **Sửa** (`ReaderView+Suggestions.swift`):
  - Chip chỉ lấy Name R → Name C → VP R → VP C (`ManageDefinitionsDraft.editableSources`, đúng thứ tự mục của màn quản lý), rồi Phiên âm ở cuối.
  - Xếp theo danh sách cố định này, không theo thứ tự của `matches` (màn quản lý nối nguồn mới thêm vào cuối danh sách).
  - Bỏ chip Xưng hô / Luật nhân. Gộp nghĩa trùng và luật badge "Riêng thắng Chung" giữ nguyên.
- Hàm dùng chung nên áp cho cả sheet Dịch của Reader, sheet Sửa từ VP/Name và sheet Tra từ điển của trình duyệt (nhóm VietPhrase ở đó không còn nghĩa Xưng hô / Luật nhân).
- `dictionaryMatches(for:bookId:)` giữ nguyên vì màn quản lý và phần ghi nghĩa dựa vào nó. Chỉ sửa comment mô tả thứ tự cũ ở `ReaderView+Selection`, `SuggestionChip`, `MeaningSuggestionChipRow`, `BrowserDictionaryLookup`.
- "huyền thừa" ở mục Phiên âm của màn quản lý không phải lỗi code: file phiên âm của người dùng ghi `县=huyền`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Đối chiếu file VietPhrase + Pronouns của người dùng với logic dựng chip.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.720] - 2026-11-05

### feat: mở lại theo Lịch sử đọc khi chưa có danh sách gần nhất

Tiếp 1.3.718. Danh sách mở gần nhất chỉ bắt đầu ghi từ bản đó, nên lần mở app đầu tiên sau khi cài sẽ không mở gì. Anh Bửu chọn thêm dự phòng.

- `ReaderSessionRestoreStore.takeLaunchCandidates()` trả `[String]?`:
  - `nil` = không mở lại (công tắc tắt, lần mở lại trước chết sớm, đổi nguồn dở);
  - mảng rỗng = chưa có danh sách.
- `ShelfView+LaunchRestore`: danh sách rỗng ⇒ duyệt truyện `isHistory` theo `lastReadDate` giảm dần (thứ tự sẵn của `@Query`), cùng các điều kiện còn trên máy, ở Kệ/Lịch sử, không phải 18+.
  - `isHistory` bật mỗi lần tiến độ được ghi, kể cả truyện trên kệ đã đọc ⇒ không chỉ là truyện ở tab Lịch sử.
  - Mở xong thì màn đọc tự ghi vào danh sách, lần sau dùng danh sách như thường.
- `CLAUDE.md`/`AGENTS.md`: ghi thêm phần dự phòng.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom.swift`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.719] - 2026-11-05

### feat: icon app mới Tàng Công Các kiểu thư pháp thủy mặc

Người dùng: *"tạo lại icon app mới, tàng công các kiểu chữ tiếng việt thư pháp, phong cách tranh thủy mặc, đơn giản"*. Trong 3 phương án phác, người dùng chọn PA2 (đủ ba chữ xếp dọc) với font Kolker Brush.

- **Hình**: nền giấy ngà, ba chữ "Tàng / Công / Các" viết bút lông xếp so le, trăng nhạt, một nhánh tre bên phải, núi xa mờ phía dưới. Ảnh vuông đặc, không trong suốt, không tự bo góc (iOS tự bo).
- **Đánh đổi đã biết**: ở cỡ nhỏ nhất (20–29pt: Cài đặt, thông báo), ba dòng chữ chỉ còn như hoa văn. Người dùng chấp nhận để có đủ tên.
- **Chữ "Tàng"**: tách "T" khỏi "àng" và hạ "àng" xuống 0,13 em, để dấu huyền không bị gạch ngang chữ T che.
- **Ảnh** (`Sources/Assets.xcassets/AppIcon.appiconset/`):
  - Thay cả 12 PNG, giữ tên file và cỡ pixel cũ (40–1024 px), thu nhỏ từ bản 1024 bằng LANCZOS.
  - Giờ là RGB không kênh alpha (bản cũ RGBA), sRGB.
  - `Contents.json` giữ nguyên, không thêm biến thể dark/tinted.
  - Ảnh dựng từ SVG sinh bằng script, chụp bằng Edge headless; script và SVG không đưa vào repo.
- **Font**: Kolker Brush (SIL OFL 1.1), chữ đã render sẵn vào PNG; app không đóng gói file font. Giấy phép ở `Docs/ThirdParty/KolkerBrush-OFL.txt`.
- Không đổi tên hiển thị hay bundle id (thuộc việc đổi tên riêng).
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**:
  - Soát ảnh 1024 và 180 px. So với một bản render bằng font giả để chắc font thật đã nạp.
  - Kiểm từng PNG: `mode == RGB`, không có `transparency`, đúng cỡ.
  - `check_architecture.py`: 1 violation nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.718] - 2026-11-05

### feat: mở lại mục đọc/xem gần nhất không phải 18+ khi mở app

Người dùng đổi phạm vi tính năng của 1.3.716: *"tôi đổi ý, mở lại chương thì mở lại truyện, comic, video không phải nfsw cuối cùng được đọc, xem"*. Trước đây chỉ mở lại khi lúc tắt app đang ở màn đọc; giờ lần nào mở app cũng mở mục gần nhất. Mục gần nhất là 18+ thì bỏ qua, lấy mục kế tiếp.

- **`ReaderSessionRestoreStore`**:
  - Bỏ dấu "đang ở màn đọc". Thay bằng danh sách 20 `bookId` mở gần nhất (`readerSessionRecentBookIds`, mới nhất đứng đầu), ghi ở `BookContentDestination.onAppear` cho cả chữ, truyện tranh, phim.
  - Không dựa `Book.lastReadDate`, vì thêm/bỏ khỏi kệ, chọn chương ở Chi tiết hay tạo bản ghi mới cũng đẩy nó lên.
  - Xoá khoá cũ `readerSessionOpenBookId` lúc khởi động.
- **`ShelfView+LaunchRestore`**: duyệt danh sách và mở mục đầu tiên thoả cả ba điều kiện, theo đúng lối bấm trên Kệ:
  - còn trên máy;
  - nằm ở Kệ, Lịch sử hoặc là truyện nhập file (bản ghi mồ côi của tiện ích tắt lưu lịch sử bị dọn lúc mở app);
  - không phải 18+ (`RepositoryFilterPolicy.isNsfwBook`, cùng luật Kệ dùng để ẩn).
- **Gỡ các phần chỉ phục vụ dấu cũ**: `onDismiss` xoá dấu ở 4 cover màn đọc (Kệ, Tìm trên kệ, Bộ sưu tập, Chi tiết) và chỗ bảo vệ truyện mang dấu trong `HistoryOrphanBookSweeper`. Các file này về lại như trước 1.3.716.
- **Giữ nguyên**: công tắc mặc định bật, chống vòng lặp crash 10 s, bỏ qua khi đổi nguồn dở, phim dừng sẵn, TTS không tự phát.
- **Tự chuyển truyện mất nguồn không đụng truyện đang được mở lại**:
  - Cờ "đang thử" giờ lưu `bookId`. `MissingSourceRebindRunner.isBookOpen` xét thêm `ReaderSessionRestoreStore.isRestoring(bookId:)`.
  - Lý do: dải báo và lượt mở lại cùng chạy ở trang gốc Kệ lúc mở app, còn màn truyện tranh / phim không đặt `ReaderView.activeBookId`.
- **Sao lưu**: `BackupSettingsArchiver` chặn khoá cờ "đang thử" (`readerSessionRestorePending`, trạng thái của một lần chạy). Danh sách mở gần nhất vẫn được sao lưu vì truyện cũng được khôi phục theo.
- Cài đặt: công tắc đổi tên thành "Mở lại truyện đọc gần nhất", sửa giải thích ở nút "?". Cập nhật ghi chú ở `CLAUDE.md`/`AGENTS.md`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom.swift`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.717] - 2026-11-05

### chore: đổi FreeBook thành Tàng Công Các ở tài liệu, chữ hiển thị và comment

Người dùng yêu cầu đổi tên cũ của app (FreeBook) và tên app tiện ích bên thứ ba còn sót trong dự án sang Tàng Công Các. Người dùng chọn: đổi tài liệu + chữ người dùng thấy + comment + nhãn nội bộ; "Tàng Công Các" cho chữ hiển thị/tài liệu, "TangCongCac" cho tên kỹ thuật; tên app tiện ích bên thứ ba thay bằng cách gọi trung tính ("hợp đồng tiện ích", "định dạng gốc"); giữ nguyên lịch sử (entry cũ, archive, `.workbuddy-ai`).

- **Chữ người dùng thấy**: 3 câu xin quyền trong `project.yml` (mạng nội bộ, micro, ảnh); tab + tiêu đề ngăn kéo "Tiện ích Tàng Công Các"; lỗi "… chưa đọc được" ×3; tên dự phòng khi truyện không có tên (Reader ×4, màn khoá TTS) và ngoại lệ viết hoa của `DisplayTextFormatter` (`"TangCongCac"`); file xuất FB2/PDF ghi "Tàng Công Các", MOBI ghi "TangCongCac" (tên Palm chỉ nhận ASCII); chú thích bản backup gửi Telegram; dòng đầu CSV nhiệt và file tắt rule (chỉ file tạo mới); prompt AI mặc định (chỉ máy chưa từng lưu cấu hình AI hoặc bấm khôi phục mặc định — Luật 20, không di trú); mô tả preset "Như engine gốc" thành "Giống bộ dịch gốc trên máy tính"; câu debug server nhắc tên lệnh VS Code; 3 thông báo Telegram của CI; tiêu đề `check_architecture.py` (ASCII để console Windows không lỗi mã hoá).
- **Nhãn nội bộ** (chỉ sống trong RAM, không ghi đĩa): 15 nhãn `DispatchQueue`, tên luồng `LegadoEngine`, 2 background task, môi trường ONNX của VieNeu, tên gesture tắt bàn phím, content world dịch trang, `ExtensionLoadError.errorDomain`, boundary multipart Telegram, thư mục tạm của backup nhiều phần, UA của `update_adblock_snapshot.py` → `TangCongCac…` / `com.tangcongcac…`.
- **Comment**: văn xuôi → "Tàng Công Các"; comment về tiện ích JS → "hợp đồng tiện ích" / "định dạng gốc"; comment chép nguyên salt giải mã và tiền tố khoá `localStorage` cũ viết lại thành tên hằng (`salt`, `storageKeyPrefix`).
- **Tài liệu**: `README.md` (tiêu đề "Tàng Công Các", ghi rõ tên kỹ thuật vẫn là `FreeBook`), `CLAUDE.md` + `AGENTS.md`, `.agents/AGENTS.md`, `rules.md`, `Docs/Specs/legado-source-spec*.md` (scheme đề xuất chưa có code → `tangcongcac://`), 4 file giấy phép `Docs/ThirdParty`, 3 mockup, 2 dòng đầu file này. Skill mẫu tiện ích đổi thư mục thành `.agents/skills/extension_helper/`. Tool VS Code: README, LICENSE và chữ hiển thị (tiêu đề lệnh, category, Output, thanh trạng thái, thông báo) — **giữ** ID lệnh, setting, package, publisher nên cấu hình đã lưu không mất; phải build lại VSIX mới thấy tên mới.
- **Cố ý giữ** (đổi là mất dữ liệu hoặc vỡ tương thích): target/scheme/module/bundle id `FreeBook`, `FreeBookApp`, `FreeBookBridgingHeader.h`, tên `.xcodeproj`/IPA/artifact trong CI; khoá UserDefaults `FreeBook_*`; keychain `com.raikiri1498.FreeBook.*` / `FreeBook.GoogleAccountSnapshots`; thư mục `Application Support/FreeBook/TTS/` (và câu lỗi nhắc nó); tiền tố backup `freebook-` / `freebook-auto-`; thư mục Drive `FreeBookBackups`; salt giải mã và tiền tố khoá cũ của tiện ích JS; giao thức debug `freebook-extdebug.v1`; repo `buudvh/FreeBook`.
- **Kiểm chứng**: grep lại chỉ còn các chỗ cố ý giữ ở trên; `check_architecture.py` như nền (1 violation `JSDom.swift`), 0 mới; mọi thay đổi là thay trong dòng, không thêm dòng code. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.716] - 2026-11-05

### feat: mở lại truyện đang đọc khi mở app, có công tắc trong Cài đặt

Người dùng: *"thêm chức năng mở lại chương đã xem trước khi tắt và thêm config bật tắt chức năng này"*. Người dùng chọn: áp cho chữ + truyện tranh + phim nhưng nguồn 18+ không tự mở lại; chỉ mở lại khi lúc tắt app đang ở màn đọc; TTS mở đúng chỗ, không phát; phim dừng sẵn; công tắc ở Cài đặt › Đọc & Nghe, mặc định bật.

- **`ReaderSessionRestoreStore`** (`Services/Books/ReaderSession/`, mới): giữ khoá công tắc `restoreReaderOnLaunch` (đọc `object(forKey:) as? Bool ?? true` vì `@AppStorage` không ghi mặc định), dấu `bookId` của màn đọc đang mở, cờ "đang thử mở lại" và chốt mỗi tiến trình một lần.
- **Ghi/xoá dấu**:
  - `BookContentDestination.onAppear` ghi dấu ⇒ đủ cả chữ, truyện tranh, phim.
  - Chỉ `onDismiss` của 4 cover màn đọc xoá dấu, khi route đã về `nil`: Kệ, Tìm trên kệ, Bộ sưu tập, Chi tiết. Không dùng `onDisappear` vì Chi tiết đẩy vào hay màn AI phủ lên cũng làm màn đọc biến mất.
  - Trình phát mở lại từ hub/PiP (`VideoPlayerPresenter`) không qua router ⇒ không tính là đang ở màn đọc.
- **Mở lại** (`ShelfView+LaunchRestore`, gọi ở `onAppear` của Kệ):
  - Chờ 0,35 s rồi đặt `readerPresentationRoute` như khi bấm truyện trên Kệ: chương `Book.currentChapterIndex`, vị trí `nil` ⇒ chữ về đoạn đã lưu, truyện tranh về ảnh, phim về giây. TTS đang đọc lúc tắt thì tiến độ thuộc TTS ⇒ mở đúng đoạn TTS, không tự phát.
  - Bỏ qua và xoá dấu khi: công tắc tắt, truyện không còn trên máy, truyện 18+ (`RepositoryFilterPolicy.isNsfwBook`, cùng luật Kệ dùng để ẩn, gồm cả truyện tự đánh dấu), còn nhật ký đổi nguồn dở.
- **Chống vòng lặp crash**: bật cờ ngay trước khi mở lại. Cờ xoá khi màn sống đủ 10 s, khi app rời trạng thái active (`MainTabView`) hoặc khi đóng màn đọc. Mở app mà cờ còn ⇒ bỏ qua lần này, log `❌ [ReaderRestore]`.
- **`HistoryOrphanBookSweeper`** không xoá truyện đang mang dấu: truyện của tiện ích tắt lưu lịch sử có thể bị dọn đúng lúc đang được mở lại.
- **Phim dừng sẵn**: `VideoPlaybackSession+Playback` hỏi `consumePausedVideoStart` khi item sẵn sàng ⇒ tua tới giây đã lưu rồi dừng. Phim nhúng trang web không áp được.
- **Cài đặt › Đọc & Nghe**: thêm công tắc "Mở lại truyện đang đọc"; tiêu đề section thành `SectionHelpHeader` với nút "?" giải thích.
- `CLAUDE.md`/`AGENTS.md`: thêm luật lối mở màn đọc bằng cover phải xoá dấu ở `onDismiss`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom.swift`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.715] - 2026-11-05

### fix: mục lục đổi icon đã tải ngay khi chương tải xong

Người dùng: *"tôi đang đọc truyện và bấm nút tải ở danh sách chương nhưng các chương tải xong ở danh sách chương của reader chưa đổi lại biểu tượng đã tải khi chúng được tải xong"*. Người dùng chọn sửa cả 3 danh sách chương: Reader, comic và tab Mục lục của Chi tiết.

- **Nguyên nhân**:
  - Hàng mục lục Reader đọc `ReaderChapterRowState.isCached`. Cờ này chỉ đổi qua `ReaderChapterListStore.markCached(index:)`, và hàm đó chỉ được gọi từ nút tải lẻ và lúc Reader tự tải chương đang đọc.
  - Nút "Tải truyện" (`TaskOptionsSheet` → `DownloadManager` → `ExportContentProvider`) và TTS đọc trước ghi cờ thẳng vào `ChapterStore` mà không báo ai.
  - Store sống suốt phiên Reader và không nạp lại trang đã có ⇒ đóng/mở lại sheet vẫn sai, phải thoát Reader.
  - Mục lục comic: `downloadedChapterIndexes` chỉ đọc đĩa một lần lúc mở màn.
  - Tab Mục lục của Chi tiết: `chapterSnapshots` chỉ đọc lại khi tab hiện, kéo làm mới hoặc đóng Reader.
- **Kênh mới `ChapterDownloadEventCenter`** (`Services/ChapterText/Events/`): nhiều subscriber, mỗi subscriber một `AsyncStream` lọc theo `bookId`, Task bị huỷ là tự gỡ. Mỗi loại nội dung phát ở **một** chỗ:
  - truyện chữ: actor `ChapterStore`, sau khi ghi DB thành công ở `upsertCachedChapter`, `updateCacheMetadata` (khi `isCached`) và `markChaptersCached`. Phủ tải cả truyện (mọi luồng), xuất có tải, Legado, tải lẻ, Reader/TTS đọc trước, khôi phục backup, đổi nguồn.
  - truyện tranh: `ComicOfflineStore.saveManifest`.
- **Reader** (`ReaderChapterListStore+CacheEvents`): store đăng ký lúc tạo, `deinit` huỷ. `markCached(indices:)` dùng chung cho sự kiện lẫn `markCached(index:)` cũ.
  - Chỉ bật `isCached` của đúng hàng, nên chỉ hàng đó vẽ lại. Không nạp lại trang ⇒ không nháy, không nhảy cuộn.
  - Sửa cả hàng kết quả tìm (trước đây đang tìm mà tải lẻ thì icon không đổi).
  - Nhớ chỉ số trong `freshlyCachedIndices` để hàng dựng sau đó cũng đúng: trang trong `pageCache`, trang đang nạp dở đọc DB trước lúc ghi, kết quả tìm mới. Tập này xoá ở `setupPlaceholderRows()`.
- **Comic** (`ComicReaderViewModel+DownloadEvents`): `.task` của `ComicReaderView` tạo stream, đọc lại đĩa ngoài main, rồi gộp chỉ số được báo. Mở trình xem phóng to làm Task chạy lại nên mỗi lần chạy đều đọc lại đĩa.
- **Chi tiết** (`BookDetailTOCView+DownloadEvents`): giữ tập chỉ số vừa tải; hàng hiện icon khi `chap.isCached || tập.contains(index)`. Không đọc lại cả mục lục mỗi chương.
  - `chapterSnapshots` đọc lại thì bỏ khỏi tập các chương DB đã có; số chương đổi thì xoá hết.
  - Chỉ nghe với truyện chữ: hàng ở đây lấy cờ từ `ChapterStore`, comic báo theo manifest ảnh trên cùng `bookId`.
  - Lưới tập video không đổi (đã có `VideoOfflineLibrary`).
- Không sửa: màn "Chọn chương bắt đầu" và chọn chương quét name chỉ chụp một lần lúc mở để chọn.
- `rules.md`: thêm luật kênh "đã tải" ở mục Danh sách chương Reader; mục 11 của 1.3.334 ghi đúng tên `ReaderChapterListStore.markCached(index:)`.
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom.swift`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.714] - 2026-11-05

### fix: trình duyệt tiện ích giữ tab đang xem khi tiện ích mở tab mới

Người dùng: *"newvisiblebrowser khi mở browser mà tôi có tab đang xem thì giữ tab tôi đang xem chứ đừng sang tab mới mở"*. Trình duyệt đang thu nhỏ thì giữ hành vi cũ (người dùng chọn).

- **`VisibleBrowserTabManager`** (trình duyệt hiện của tiện ích, `Engine.newVisibleBrowser`): thêm `isUserViewingTab` = container đang hiện toàn màn (`isPresented`, không thu nhỏ, không đang tắt) và tab đang chọn còn tồn tại.
- Hai chỗ từng giật tab, giờ đều giữ tab đang xem khi `isUserViewingTab`:
  - `addTab` tab mới: chỉ thêm pill vào cuối dải tab (tiêu đề "Trình duyệt (N tab)", widget đếm tab vẫn cập nhật), `activeTabId` không đổi.
  - `addTab` trùng id — chạy ở **mỗi** `launch()`/`launchAsync()` vì `load`/`loadAsync` gọi `presentUIIfNeeded()`: không `activateTab` nữa. Thiếu chỗ này thì `newVisibleBrowser()` rồi `launch(url)` vẫn kéo sang tab mới, và mỗi lần `launch` sau lại kéo đi.
- **Không đổi**:
  - Trình duyệt chưa có tab ⇒ mở và hiện tab mới như cũ.
  - Đang thu nhỏ ⇒ chuyển sang tab mới, bật lên theo cài đặt "Mở thu nhỏ".
  - Đăng nhập Gemini / Xác minh Google vẫn nhảy sang tab của mình: người dùng bấm nút mới mở, và hai launcher gọi `selectTab` riêng sau `loadAsync`.
- **Không áp dụng**: `window.open`/`_blank` (trình duyệt này không có `uiDelegate`, không mở tab từ trong trang); trình duyệt người dùng `BypassWebView` (mỗi lần mở là một store mới, không có tab cũ).
- Chuyển entry cũ nhất sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` 1 violation nền (`JSDom.swift`), **0 mới**. Không build tại chỗ (Windows), chưa thử trên máy. Rủi ro: tab nền không nằm trên màn hình (như trình duyệt ẩn / lúc thu nhỏ) — trang cần bấm captcha thì phải bấm pill của tab đó.

## [1.3.713] - 2026-11-05

### fix: Cài đặt TTS mở ngay từ màn hẹn giờ, tab con về kiểu cũ

Người dùng: *"vào cài đặt tts từ màn hình hẹn giờ bị lâu"*, *"sửa lại hiển thị tab con kiểu như trước"* (chọn mở đè lên Hẹn giờ, badge trong ô cạnh chữ).

- **Nguyên nhân chậm** (đọc code, chưa đo trên máy):
  - Bấm ⚙ ⇒ `dismiss()` sheet Hẹn giờ → chờ cứng 0,3 s → bật `showingSettingsSheet` để widget mở sheet Cài đặt. Sheet ở nấc 0.88 trượt xuống lâu hơn 0,3 s nên Cài đặt phải đợi đóng xong rồi mới trượt lên: hai hoạt cảnh nối đuôi.
  - `TTSSettingsView.onAppear` gọi `AVSpeechSynthesisVoice.speechVoices()` **đồng bộ trên main** (dò kho giọng hệ thống, chậm) ngay lúc sheet đang mở ⇒ chặn hoạt cảnh.
- **Sửa**:
  - `TTSSettingsSheetHost` gắn trong `TTSQuickTimerSheet` thay vì `TTSFloatingWidgetView` ⇒ ⚙ chỉ bật cờ, Cài đặt mở **đè lên** sheet Hẹn giờ (một lần trượt); vuốt đóng Cài đặt là về lại Hẹn giờ. Sheet Hẹn giờ là lối vào duy nhất của cờ này. `resumeAfterSettings` vẫn ở `onDisappear` của `TTSSettingsView` nên không đổi.
  - `TTSSettingsView.loadSystemVoices()`: đọc giọng Siri tiếng Việt bằng `Task.detached`, gán lại trên main, giữ việc chọn giọng mặc định khi engine là Siri mà chưa có giọng. Picker giọng Siri trống một nhịp rồi mới có danh sách. Áp cả khi mở từ tab Cài đặt.
- **Tab con** về ô viên thuốc có icon như trước 1.3.712 (icon + chữ 13pt, bo 10, đang chọn nền màu nhấn 18% + viền 60%). Badge đỏ tổng số chương nằm **trong ô ngay sau chữ**; tên một dòng, chật thì cắt "…", badge `fixedSize` + ưu tiên bố cục nên luôn đủ số. Header, ⚙, đồng hồ trên bìa, số thứ tự, ô tìm nổi giữ nguyên.
- Chưa thử máy (Windows, chỉ CI biên dịch). Nếu Cài đặt vẫn chậm thì nghi tiếp `TTSSettingsView` (Form lớn, `isModelDownloaded` chạm đĩa mỗi giọng NghiTTS trong `body`).

## [1.3.712] - 2026-11-05

### feat: màn hẹn giờ TTS theo header mục lục Reader, thêm số thứ tự và ô tìm chương

Người dùng: *"chưa đánh số thứ tự cho danh sách chương ở màn hình hẹn giờ"*, *"cho header của màn hình hẹn giờ giống màn hình danh sách chương của reader"*, *"số chương ở header bỏ đi, tạo badge số…"*, *"hiển thị hẹn giờ lên ngay chỗ cover trên header, hiển thị giống kiểu chỉ bìa"*, *"danh sách chương ở hẹn giờ đang thiếu ô tìm kiếm"*, *"tab con hiển thị giống tab chi tiết"*, *"nút search hiển thị kiểu giống nút + ở kệ sách"*, *"thời gian hẹn giờ ở cover hiển thị căn lề giữa"* (duyệt mockup bản 6).

- **Sheet Hẹn giờ** (`TTSQuickTimerSheet`, mở từ widget TTS): bỏ `NavigationStack`/toolbar (sheet không đẩy trang). Dải trên cùng 36pt chứa thanh kéo của sheet hệ thống + nút ⚙ dạng chấm tròn 28pt (icon 17pt nửa đậm, vùng chạm 38×38) ở góc phải — header bắt đầu ngay dưới nên tên truyện dùng hết bề ngang. Hàng tên chương đang phát (chữ chạy) giữ riêng dưới header, trên tab con.
- **Header mới** `TTSQuickTimerHeader` (file riêng): cùng số đo header mục lục Reader — bìa `BookCoverView` 86×120 bo 6 (chạm = mở truyện như cũ), tên `.headline` 2 dòng, tác giả `.subheadline` mờ 72%, viên nguồn `.caption2` (icon + tên tiện ích đã cài; tiện ích đã gỡ ⇒ tên nguồn đã lưu). Bỏ thẻ bo viền, bỏ chip "N chương" và hàng trạng thái hẹn giờ. Nút "Hủy" hẹn giờ ở góc dưới phải cột chữ, chỉ khi đang hẹn giờ.
- **Đồng hồ trên bìa**: `CoverCaptionStrip` (dải của kiểu "Chỉ bìa") đè đáy bìa — "m:ss" / "Hết chương" + "Hẹn giờ tắt", **căn giữa**, chữ số rộng đều, phần chuyển thấp (`compactFadeHeight`) vì bìa nhỏ. Chưa hẹn giờ ⇒ bìa trơn. `CoverCaptionStrip` thêm `isCentered` và `usesMonospacedDigits` (mặc định tắt ⇒ Kệ/Khám phá không đổi).
- **Tab con kiểu tab Chi tiết** (`BookDetailView.customTabBar`): chữ `.subheadline`, đang chọn đậm + màu nhấn + gạch chân 3pt, không icon. "Danh sách chương" có badge đỏ **tổng số chương** ngay cạnh chữ (giữ tổng cả khi đang lọc). Tên tab một dòng, chật thì cắt "…"; badge `fixedSize` + ưu tiên bố cục ⇒ luôn đủ số.
- **Danh sách chương** `TTSQuickTimerChapterList` (file riêng):
  - Cột số thứ tự `ChapterOrdinalLabel` theo công tắc "Hiện số thứ tự chương": `chaptersQueue` là mục lục đủ theo thứ tự gốc ⇒ số = `index + 1`, giữ nguyên khi lọc; bề rộng cột tính một lần theo mục lục đủ. `ChapterOrdinalLabel` thêm tham số `font` (mặc định `.body`) để số cùng cỡ 14pt với tên chương ở đây.
  - Chương đang phát chỉ đổi màu nền + chữ đậm; bỏ icon loa đầu hàng và chip "Đang phát".
  - Ô tìm `ChapterTOCSearchField` ("Tìm kiếm N chương") **ẩn mặc định**. Nút kính nổi 52pt góc dưới phải (`floatingAddButton`, cùng kiểu nút "+" ở Kệ) mở ô + bật bàn phím, mở rồi thành ✕ (xoá từ khoá, ẩn ô, cuộn lại chương đang phát). Bàn phím đóng khi ô trống ⇒ ô tự ẩn; cuộn danh sách là đóng bàn phím.
  - Lọc như ô tìm mục lục Reader: `ChapterTitleSearchMatcher` trên tên đang hiển thị (dịch sống y như `TTSManager.displayTitle(for:)`) + tên gốc; chờ 250 ms, chạy ngoài main, phím mới huỷ lượt cũ; mục lục làm mới khi đang lọc ⇒ lọc lại. Không khớp ⇒ "Không có chương nào khớp".
- **Mảnh dùng chung mở rộng (tương thích ngược)**: `FloatingAddButton` / `floatingAddButton(_:systemImage:action:)` thêm `systemImage` (mặc định "plus"); `ChapterTOCSearchField` thêm `focus: FocusState<Bool>.Binding?`.
- Chưa thử máy (Windows, chỉ CI biên dịch). Rủi ro: ô tìm nằm trong cửa sổ nổi của widget TTS (không bao giờ là key window) — tiền lệ là ô API key Google ở sheet cài đặt TTS cùng cửa sổ; nếu gõ không ăn thì nghi ở đây.

## [1.3.711] - 2026-11-04

### feat: danh sách chương hiện số thứ tự, cột số vừa đủ chữ số lớn nhất

Người dùng: *"Thêm số thứ tự hiển thị ở mỗi danh sách chương trong truyện. Nhớ vừa số chữ số cao nhất của thứ tự…"*, *"Cho config hiện/ẩn số thứ tự"*, *"Sửa lại đồng bộ số thứ tự và tên chương hiển thị kiểu flex nhé"*, *"Nhãn ch.N cũ bỏ đi"*.

- **Mảnh dùng chung** (`Sources/Views/Common/ChapterTOCPanel/`):
  - `ChapterOrdinalNumbering`: số = vị trí (từ 1) của chương trong **mục lục đủ** theo thứ tự gốc; dòng tiêu đề nhóm (`isSection`) không có số, không chiếm số ⇒ số lớn nhất = N của "Mục lục (N chương)". Tìm/lọc hay đảo ↓↑ thì mỗi chương giữ số của nó. Mục lục liền mạch không có dòng nhóm (mọi truyện chữ) ⇒ số = chỉ số + 1, không dựng bảng; có dòng nhóm mới dựng bảng chỉ số → số. `digits` = số chữ số của số lớn nhất (2000 → 4, 10000 → 5), tính **một lần mỗi danh sách**.
  - `ChapterOrdinalLabel`: cột số kiểu flex trước tên — đặt cùng tên trong `HStack(alignment: .firstTextBaseline)`, tên dài xuống dòng thì thẳng lề với tên. Bề rộng đo bằng `Text` giữ chỗ ẩn gồm `digits` chữ "0" cùng font (`.body.monospacedDigit()`, cùng cỡ với tên), số căn phải, `Text(verbatim:)` (không chèn dấu nhóm theo vùng). Màu phụ của `ChapterTOCPalette`; hàng đang đọc theo màu tiêu đề, đã đọc mờ thêm. Không `GeometryReader` ⇒ giữ lazy.
- **Các danh sách**:
  - Tab Mục lục của Chi tiết (`BookDetailTOCView` / `BookDetailTOCRow`): bản chụp `chapter_store` dựng số từ `chapterSnapshots` khi mục lục đổi (`@State snapshotNumbering`, không theo từ khoá/chiều); mục lục online dựng từ **toàn bộ** `onlineChapters` ở `BookDetailView.updateFilteredOnlineChapters` (danh sách đã lọc không đếm được dòng nhóm đứng trước) rồi truyền xuống; nhánh `Book.chapters` = index + 1. "Mục lục (N chương)" lấy N từ cùng bộ số ⇒ không còn lệch khi đang tìm ở mục lục online có dòng nhóm.
  - Sheet mục lục Reader (`ReaderChapterListView+List` → `ReaderChapterRowView`): truyện chữ không có dòng nhóm ⇒ số = index logic + 1 cho cả danh sách phân trang lẫn kết quả tìm; cột rộng theo `store.totalCount`. Hàng giữ chỗ (đang tải trang) cũng có cột số để tên không nhảy ngang.
  - Mục lục màn đọc comic (`ComicChapterListSheet`): dựng từ toàn bộ `chapters` (không phải `visibleChapters`).
  - Màn "Chọn chương…" (`ReaderAINameScanChapterPickerView`, sheet tải/xuất + sheet quét tên): **bỏ nhãn "ch.N" cũ**, thay bằng cùng cột số; chương không tên hiện "Chương N"/"Tập N". Sheet tải/xuất gắn `AINameScanChapter.ordinal` lúc dựng danh sách (`DownloadStartChapterCatalog`, dòng nhóm không chiếm số) ⇒ số và tìm theo số khớp mục lục; dòng phụ "ch.N: tên" của mục "Bắt đầu từ" dùng cùng số. Sheet quét tên giữ index + 1.
  - Không đổi: lưới tập video.
- **Công tắc**: Cài đặt › Chung › Giao diện › mục "Danh sách chương" › "Hiện số thứ tự chương" (nút "?" giải thích). `@AppStorage` khoá `chapterListShowsOrdinal` (`ChapterOrdinalNumbering.showsOrdinalKey`), mặc định bật; đọc một lần ở mỗi danh sách, tắt là bỏ hẳn cột, đổi ngay. Backup tự gói (khoá chữ thường đầu, `BackupSettingsArchiver.isExportable`), không cần thêm vào danh sách.
- `CLAUDE.md` / `AGENTS.md`: thêm một câu ở mục "Mục lục & thẻ Chi tiết".
- Chuyển `[1.3.680]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.710] - 2026-11-04

### fix: sửa 5 lỗi engine Legado tìm thấy trong log

Người dùng: *"Duyệt E1–E5"* (từ `app_logs (134).txt`, nối tiếp `[1.3.708]`). Spec `legado-source-spec.md` đã sửa theo (§2.7, §6.2, §6.3, §6.9).

- **E1. `{{@…}}` là rule, không phải JS** (`LegadoRuleAnalyzer+Template.placeholderValue`).
  - Ví dụ 梧桐中文 ×6 `{{@.w_txt li.4@textNodes}}`, 飞卢 ×3, 酷书阁 ×2, 轻菠萝包, SF轻小说. Trước đây lỗi `Invalid character '@'`, mất phần giới thiệu/trường đó.
  - Corpus: 50 chỗ ở 27 nguồn, không chỗ nào là JS.
- **E2. Năm đối tượng chuẩn được trả về bản gốc trước mỗi lần chạy JS**: `java`, `source`, `cookie`, `cache`, `infoMap` (`LegadoJSRuntime+StandardObjects`). Lần chạy lồng lưu và trả lại cả chúng.
  - 晋江百合 / 晋江 (cá nhân) `cookie=cookie.getKey(…)` và 天地中文网 `cookie = cookie.getCookie(…)` gán không khai báo. Trước đây chúng thay `cookie` bằng chuỗi cho mọi script sau, nên lỗi `cookie.getKey is not a function` từ chương thứ hai.
- **E3. `{{js}}` trên trang gốc nhận `result` = chuỗi thân trang**, như phân đoạn JS đứng đầu, không nhận phần tử HTML. Ví dụ 豆瓣读书 ×5 `result.match(/ratingValue…/)` trước đây mất dòng điểm. `src` của `{{js}}` theo quy ước `src` của mục (`[1.3.708]`).
- **E4. `importClass(org.jsoup.Jsoup)` / `JavaImporter` đặt `Jsoup` vào phạm vi**, nhờ bản giả lập Jsoup có tên ngắn. Ví dụ SF轻小说#2 `Jsoup.parse(…)`.
- **E5. Object JSON đưa vào JS có `get(k)`, `containsKey`, `keySet`, `size`**, ẩn, như map của json-smart; chỉ gắn khi không trùng khoá, không lồng xuống object con. Ví dụ 点众阅读 `result.get("statusTips")`.
- Chuyển `[1.3.679]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng:** đọc code; `check_architecture.py` chỉ còn lỗi nền `JSDom.swift`. Không build tại chỗ (Windows), chưa thử trên máy.

## [1.3.709] - 2026-11-04

### revert: bỏ khoảng giá trị min-max của token số trong rule dịch

Người dùng: *"Revert bỏ min max cho token số giúp tôi"*. Gỡ hẳn tính năng `#min-max` của `[1.3.701]` (commit `392dd254`); giữ nguyên `<m>` = `十` đứng đầu mẫu đọc "mười" (`[1.3.703]`) và nút Lưu "Thay rule cũ" / "Lưu thêm rule mới" (`[1.3.705]`).

- **Gỡ**: xoá `QuickTranslationRuleValueRange`, `QuickTranslationRuleParser+ValueRange`, `QuickTranslationRuleTokenValueRangeEditor`; bỏ `valueRange` khỏi `QuickTranslationRuleElement` và `TokenSpec`, nhánh kiểm giá trị trong `walkNumeral`, mã lỗi `INVALID_VALUE_RANGE`, `#` trong đuôi gợi ý bàn phím, thanh chỉnh giá trị dưới thanh độ dài (kèm `.id(tokenPosition)`), các ý về `#` trong `QuickTranslationRuleGuide` + câu trợ giúp ô Mẫu, câu về `#min-max` trong đoạn token của `CLAUDE.md`/`AGENTS.md`. Parser, matcher, chip chỉnh trở lại đúng như trước 1.3.701.
- **Rule đã viết có `#`** (cú pháp giờ không còn):
  - `<n#1-200>`, `<d#0-99>`, `<n#5>` (không ghi độ dài) ⇒ `UNKNOWN_TOKEN_NAME` (lỗi nặng). Rule không chạy, **không hiện** ở danh sách rule và sheet lỗi (hai nơi này chỉ hiện rule biên dịch được + cảnh báo), và **bị bỏ khỏi file** ở lần ghi kế tiếp của bộ đó (thêm / sửa / xoá / nhập rule đi qua `validRecords`). Không bị coi là chữ cố định.
  - `<n:1-4#1-200>` (độ dài rồi `#`) ⇒ **không báo lỗi**: phần độ dài `1-4#1-200` tách theo `-` rồi bỏ mảnh không phải số ⇒ thành độ dài `1-200`, không giới hạn giá trị. `<n:1-4#5>` ⇒ độ dài đúng 1; `<n:3#5>` ⇒ lỗi "Khoảng độ dài không hợp lệ" (lỗi nặng, như trên). Đây là cách đọc độ dài lỏng có từ trước 1.3.701.
- Chuyển `[1.3.678]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff (patch đảo của `392dd254` áp sạch trừ `QuickTranslationRuleEditorSheet+Editing.swift`, gỡ tay hai chỗ); grep `valueRange`/`ValueRange`/`invalidValueRange` trong `Sources/` không còn; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.708] - 2026-11-04

### fix: sửa 15 lỗi engine Legado từ báo cáo kiểm tra nguồn 19:57

Người dùng: *"Làm theo javis đề xuất và hãy xem log sau đây"* (plan có bằng chứng từ hai báo cáo 18:12 và 19:57 cùng `app_logs (134).txt`). Mọi bằng chứng đối chiếu trang hoặc API thật, cộng corpus 6 file nguồn. Spec `legado-source-spec.md` đã sửa theo (§1.2.1, §2.2–§2.3, §2.6, §2.12, §3.9/U8, §3.10, §4.6, §4.7, §6.1–§6.4).

- **Rule và URL**
  - **Đuôi `##R##P##` cũng là trích khớp đầu, như `###`** (`LegadoRuleScanner.splitRegexTail`).
    - Ví dụ: 黑岩#玄奇 / 黑岩网站 `a@href##\d+$##…/content/$0##` trước đây ra URL dính `…/book/140966/https://…` (404).
    - Corpus: 27 rule ở 20 nguồn chỉ hợp lý khi trích khớp đầu. `##R##` (hai phần) vẫn là "xoá mọi đoạn".
  - **`@js:` có đuôi `##`** ⇒ chạy phần trước `##` làm JS rồi áp đuôi regex lên kết quả. Chỉ tách khi cả đoạn không phân tích được mà phần trước thì được (`LegadoJSRegexTail`: kiểm cú pháp bằng `JSCheckScriptSyntax`, không chạy).
    - `@js:##…` (JS rỗng) giữ `result`; khối `<js>##…</js>` là đuôi regex.
    - Ví dụ 晋江[网页], 穿越小说, 笔迷读, VIP中文, 企鹅阅读, 七猫, 恩京.
    - Corpus: 86 đoạn ở 65 nguồn, 20 đoạn JS rỗng, 26 khối `<js>##`.
  - **Body là chuỗi JSON mà nguồn không đặt Content-Type** ⇒ gửi `application/json`, như `java.post` (U8 đã chốt).
    - 乐读 ×3, 少年梦, 西瓜 ×4, 趣悦 ×2: gửi form thì 4 API từ chối hoặc trả rỗng.
  - **Khối option `,{…}` không đọc được thì bỏ** (§1.2.1), không dán vào URL nữa. 独步 ×2 trước đây bị trang báo "没有找到…{body…}".
  - **XPath `//X…` trên mục X khớp cả chính mục** (`self::X… | .//X…`). Ví dụ 耽美小说 `bookList //h2` + `name //h2/a//text()`. Vị từ chỉ số giữ nguyên nghĩa.
  - **`src` của JS trong rule trường của mục là mã của mục**: HTML gọn hoặc JSON. 冷冷文学 cùng 9 nguồn dùng chung chapterUrl chạy regex một dòng trên `src`.
- **Cầu JS**
  - **`java.getElement`** với jsoup/CSS/XPath trả cả danh sách như `getElements`; JSONPath xác định vẫn trả một giá trị.
    - 凡人小说 ×2 trước đây dùng `d.length`/`d.select` mà ra 0 chương; trang thật có 1891 chương.
    - Danh sách có thêm `hasAttr`, `hasClass`, `hasText`, `val`.
  - **`res.headers(tên)`** trả danh sách mọi giá trị (`[i]`, `toString()` kiểu `[a, b]`). `Set-Cookie` tách theo từng cookie.
    - 天籁小说 `headers("Set-Cookie")[0]` trước đây ra `undefined`, nên URL tìm kiếm dựng ra rỗng.
  - **Danh sách JSON rỗng thành chuỗi `"[]"`**, nối tiếp 1.3.700. 爱发电 ×3 (tác giả có 0 album) trước đây ra 0 chương.
  - **`base64Decode` bỏ ký tự ngoài bảng chữ base64.** 完本小说网: base64 chứa `\/`, sau khi giải AES ra nội dung chương.
  - **Lỗi cú pháp mà Rhino chấp nhận thì sửa rồi chạy lại** (`LegadoJSRhinoSyntax`, `runFixingRhinoSyntax`). Áp cho rule JS và jsLib; bản sửa là bản được cài.
    - **Ký tự Cf** (U+200B…) ngoài literal thì bỏ (ES3 §7.1). Ví dụ 移动阅读 ×2.
    - **`let X` trùng tham số** thì đổi thành `var X`. Ví dụ jsLib 书旗 `GetUrl`, 长佩 `AESencrypt`, trước đây mất cả thư viện.
- **Mạng và bộ kiểm tra nguồn**
  - **UA mặc định đổi sang Chrome máy tính** (§3.10).
    - Với UA Android di động, 26 nguồn bị chuyển sang bản mobile không khớp rule: 黑岩 ×10, 若初 ×6, 若夏 ×4, 塔读 ×5, 红袖.
    - Thử 40 nguồn đang qua với UA máy tính: không nguồn nào đổi kết quả.
    - `java.getWebViewUA()` giữ UA WebView Android.
  - **Trang HTTP 404 của các bước chính vẫn chạy rule** (§4.6, `LegadoSourceRuntime+HTTPErrorPage`). Áp cho tìm, khám phá, thông tin sách, mục lục, nội dung, comic.
    - Bước ra rỗng hoặc rule ném lỗi trên trang 404 ⇒ ném lại lỗi HTTP gốc như trước.
    - Mã ≥ 400 khác (403/429/503 thử thách Cloudflare, captcha) vẫn lỗi ngay. Nhờ vậy trang chặn không thành nội dung chương, và nút "Mở link lỗi" vẫn hiện.
    - Ví dụ 阅友 ×4: chapterUrl là id trần nên trả 404, nhưng rule nội dung tự gửi POST.
    - Thay đổi hành vi: trang 404 mà rule nội dung vẫn ra chữ thì chữ đó được lưu làm nội dung chương.
  - **Bộ kiểm tra nguồn chọn chương thử bỏ qua hàng quyển** (không URL, URL trùng trang mục lục hoặc trùng hàng khác). Mục kiểm `++url` dùng làm tocUrl.
    - 中文万维 / 中文书城 ×7 trước đây bị báo lỗi nội dung giả.
- **Chưa sửa**
  - `{{baseUrl}}` sau chuyển hướng (起点 ×2 `//catalog/`): bằng chứng chưa đủ, ghi UNKNOWN ở §4.7.
- **Kiểm chứng**
  - Đọc code; logic JS thử trên Node/V8 với văn bản bootstrap thật; `check_architecture.py` chỉ còn lỗi nền `JSDom.swift`.
  - Không build tại chỗ (Windows), chưa thử trên máy.
  - Báo cáo 19:57 chạy bản có 1.3.700. Các nguồn 1.3.700 đã sửa đang tắt nên cần bật lại và chạy riêng.

## [1.3.707] - 2026-11-04

### fix: ô tìm của bảng chọn nguồn Khám phá đứng yên khi cuộn

Người dùng: *"Hãy sửa cho hàng search luôn hiển thị ở vị trí đó dù scroll xuống dưới trên màn chọn tiện ích khám phá"*.

- **Ngăn kéo menu có tuỳ chọn `contentScrolls`** (`sideDrawerMenu(..., contentScrolls:)`, mặc định `true`, đi qua `SideDrawerMenuModifier` → `SideDrawerMenuWindowManager` → `SideDrawerMenuWindowRoot` → `SideDrawerMenuPanel`).
  - `false` thì panel không bọc nội dung trong `ScrollView`. Nội dung chiếm phần còn lại của ngăn kéo và tự cuộn.
  - Mọi ngăn kéo khác giữ nguyên.
- **Bảng chọn nguồn Khám phá** (`DiscoverySourcePickerModifier`, `ExtensionSelectorView`) mở với `contentScrolls: false`.
  - Ô tìm và nút chọn loại đứng yên ở đầu; chỉ danh sách nguồn (hoặc dòng "Không có nguồn nào khớp") cuộn bên dưới.
  - Ô tìm vẫn ở trong cùng view nên từ khoá vẫn là `@State` của bảng: gõ là lọc ngay, như trước.
- **Kiểm chứng:**
  - Đọc code; `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**.
  - Không build tại chỗ (Windows), chưa thử trên máy: cuộn danh sách dài, vuốt đóng ngăn kéo, gõ tìm khi bàn phím đang mở.

## [1.3.706] - 2026-11-04

### feat: màn sửa VP/Name theo bố cục màn dịch, nghĩa rule cuộn ngang được

Người dùng:
- *"Cho màn edit của vp/name trong danh sách giống màn dịch của reader nhưng đừng có suggest rule và nghĩa rule"*;
- *"Thêm nút mở rộng thu hẹp, nếu lưu vế trái sẽ lưu phần đang chọn"*;
- *"hàng gốc phải giống dịch. Nút mở rộng thu hẹp trên 1 hàng"*;
- *"Ô nhập hiển thị được tối đa 2 hàng như dịch. Sửa phần nghĩa rule màn dịch nếu dài quá sẽ cho scroll ngang"*;
- chọn *"Giữ từ cũ"*.

- **Màn sửa từ của danh sách VP/Name** (`DictEntryEditSheet`, `+Rows`, `DictEntryEditLookup`): chế độ `.edit` của `DictEntrySheet` chuyển sang màn mới; chế độ thêm (dán nhiều dòng `key=value`) giữ nguyên. Dựng lại theo `ReaderDefinitionOverlayView`, màu theo hệ thống thay cho chữ trắng trên nền tối. Từ trên xuống:
  - **Header:** `.pageTitle("Sửa từ")`, nhãn chỉ đọc loại từ điển và phạm vi ("VP · Chung", "Name · Riêng truyện"). Nút bút chì gõ lại từ gốc, giữ cảnh báo ghi đè. Không còn nút "Lưu" trên header.
  - **Hàng từ gốc:** giống Reader — cao 40, hai cặp nút tròn 28pt mở rộng/thu hẹp hai đầu trên cùng một hàng. Chữ đang chọn đậm và gạch chân, chữ còn lại mờ; chạm một chữ thì chọn chữ đó. Vùng chọn ban đầu là cả từ, mở rộng tới hai đầu từ gốc, thu hẹp còn ít nhất 1 chữ.
  - **Hàng token dịch:** dùng `TranslateUtils.getTranslationTokens`; chạm token thì chọn đúng phạm vi của token.
  - **Ô nghĩa:** 2 dòng như Reader. Đổi vùng chọn thì ô hiện nghĩa của cụm: nghĩa đang lưu nếu cụm đã có trong danh sách, không thì bản dịch (`translateTerm`). Chữ người dùng đang gõ không bị kết quả tra về muộn ghi đè.
  - **Dải gợi ý nghĩa:** chip của Reader, tính lại theo vùng chọn. Có nút dán. Nút ⚙ quản lý nghĩa chỉ hiện khi có truyện.
  - **Chữ hoa/thường** và **tra nhanh** (công cụ tìm của Reader, mở `BypassWebView`, ⚙ cấu hình công cụ).
  - Không có phần rule (nghĩa rule, chip rule, thêm rule) và không có bộ chọn NE/VP, R/C.
- **Lưu bằng nút "Cập nhật"** (`.appFilled`) ở dưới:
  - Chọn cả từ: cập nhật nghĩa như cũ.
  - Từ gõ lại bằng bút chì: đổi tên như cũ.
  - **Chọn một phần: giữ nguyên từ cũ, thêm cụm đang chọn thành từ mới**, kèm dòng báo trước khi lưu và cảnh báo khi cụm đã có trong danh sách.
  - Vuốt đóng khi có thay đổi thì hỏi xác nhận.
- **Màn dịch của Reader:** chữ "Nghĩa rule" và dòng thông báo rule nằm trong khung cuộn ngang, nên chữ dài kéo xem hết được. Vẫn chọn để chép được; hàng giữ cao 50.
- **Kiểm chứng:**
  - Đọc code đối chiếu API có sẵn: `getTranslationTokens`, `translateTerm`, `ReaderView.dictionaryMatches`/`suggestionChips`, `SearchEngine.loadEngines`, `ReaderLookupRoute`.
  - `check_architecture.py` chỉ còn 1 lỗi nền (`JSDom.swift`), **0 mới**. `DictionaryListView` 661/690 dòng.
  - Không build tại chỗ (Windows), chưa thử trên máy.
  - Rủi ro: sửa nghĩa trong ⚙ rồi bấm "Cập nhật" sẽ ghi đè bằng chữ trong ô; gõ lại từ gốc rồi chọn một phần thì thêm cụm thay vì đổi tên.

## [1.3.705] - 2026-11-04

### feat: sửa rule dịch đổi mẫu thì chọn thay rule cũ hoặc lưu thêm rule mới

Người dùng: *"Nút lưu của sửa rule thêm option thay the rule cũ cùng lưu và giữ rule cũ. Hiển thị option kiểu như nút lưu thêm rule"*; duyệt plan + mockup.

- **Trước đây** sửa mà đổi mẫu thì luôn **thêm** rule mới, rule cũ giữ nguyên (`updateRule` bỏ qua `oldPattern`, chỉ `upsert` mẫu mới); muốn bỏ rule cũ phải xoá ở danh sách.
- **Màn sửa rule** (`QuickTranslationRuleEditorSheet`): đổi mẫu ⇒ chạm Lưu mở `Menu` hai mục như nút Lưu của màn thêm: "Thay rule cũ" (phụ đề "Sửa đúng dòng N, mẫu cũ mất") / "Lưu thêm rule mới" ("Giữ nguyên rule cũ" — hành vi cũ). Mẫu không đổi ⇒ Lưu vẫn là nút thường, đè bản dịch tại chỗ: file khoá theo mẫu nên không giữ được hai dòng cùng mẫu. Bản lưu luôn vào bộ của rule đang sửa (chung / tên chương / riêng truyện). Câu trợ giúp ô Mẫu viết lại.
- **Thay chỗ**: `QuickTranslationRuleRecordStore.replacing(oldPattern:pattern:replacement:in:)` (mới) đặt rule mới đúng vị trí dòng cũ (giữ thứ tự khi hoà ưu tiên); mẫu mới trùng một dòng khác trong bộ ⇒ dòng kia bị bỏ để bản đang sửa thắng (như lưu mẫu đã có thì đè); không còn dòng cũ ⇒ thêm như `upsert`. `updateRule` của cả ba kho (`QuickTranslationRuleStore+Editing`, `QuickTranslationRuleChapterStore`, `QuickTranslationRuleBookStore`) dùng hàm này; "Lưu thêm rule mới" đi `QuickTranslationRuleTransfer.copy` như thêm rule.
- `onSubmit` của sheet nhận thêm `replacing` (mẫu bị thay chỗ, `nil` = thêm / giữ rule cũ) nên danh sách rule và Reader không còn tự suy `oldPattern` từ `mode`. Cờ tắt của mẫu cũ không chuyển sang mẫu mới (như xoá rule hiện nay). Chuyển `[1.3.674]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.704] - 2026-11-04

### feat: khoá nút kiểm tra nguồn khi đang có lượt kiểm tra chạy nền

Người dùng: *"Đang có tiến trình kiểm tra rồi thì disable nút kiểm tra đi nhé"*. Trước đây bấm vẫn mở màn rồi mới báo "Đang có một lượt kiểm tra khác…".

- **`SourceCheckBusyReader`** (mới, `Views/Extensions/SourceCheck/`): đọc `MinimizedSourceCheckCoordinator.isBusy(kind)` = bộ chạy có lượt **đang chạy ở nền** (đã thu nhỏ). Màn kiểm tra còn mở thì đã che mọi lối vào, và không đổi trạng thái `NavigationLink` đang đẩy chính màn đó. Reader tự observe coordinator nên dùng được trong ngăn kéo ⋯ (cửa sổ nổi riêng).
- **Bốn lối vào** khoá theo đúng bộ chạy, mờ đi và có chữ lý do: ⋯ tab Nguồn Legado "Kiểm tra nguồn (theo nhóm đang lọc)" và ⋯ tab Tất cả tiện ích "Kiểm tra tiện ích đang hiện" (chữ phụ "Đang chạy"); "Kiểm tra nguồn này" ở Chi tiết nguồn Legado (chữ "Đang có lượt kiểm tra"); nút tròn "Kiểm tra" ở thẻ đầu Cấu hình tiện ích (nhãn đổi thành "Đang chạy"). Lượt Legado không khoá lối vào tiện ích JS và ngược lại (hai bộ chạy riêng, chạy song song được).
- Lượt chạy từ Debug server không qua màn kiểm tra nên không khoá; bấm vẫn ra màn báo bận như cũ. `rules.md` luật hub (f) thêm ý này. Chuyển `[1.3.673]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.703] - 2026-11-04

### fix: token <m> đứng đầu rule đọc 十 là mười

Người dùng: *"Nếu token <m> giá trị 10 đứng đầu rule ví dụ mười mấy thì dịch là mười thay vì mươi"*; xác nhận `<m>几 = {0} mấy` trên `十几` đang ra "mươi mấy", muốn "mười mấy", tiêu chí *"đứng đầu rule và là 10 thôi, 20 30 vẫn là mươi"*; duyệt plan.

- **Nguyên nhân**: `QuickTranslationMagnitudeFormatter` tra bảng cố định `十`/`一十` → `mươi` (chữ đơn vị để ghép sau số đếm: `几<m>` ⇒ `mấy mươi`), không biết `<m>` đứng ở đâu trong mẫu.
- **Sửa**: compiler đánh dấu `<m>` là phần tử đầu tiên của mẫu (`QuickTranslationRuleCompiler+LeadingMagnitude`, mới; cờ `QuickTranslationRuleElement.leadsPattern`). Neo `<START>`/`<END>` bỏ qua vì không chiếm ký tự; mẫu mở đầu bằng nhóm thì xét phần tử đầu từng nhánh; chữ cố định hay ngoặc đứng trước thì không tính là đứng đầu. `<m>` được đánh dấu mà khớp `十`/`一十` ⇒ `mười` (`renderMagnitude(_:leadsPattern:)`); `二十` vẫn `hai mươi`, `十万` vẫn `chục vạn`, `几<m>年` vẫn `mấy mươi năm`.
- Giới hạn theo đúng tiêu chí vị trí: câu `几十几` gặp rule `<m>几` vẫn khớp từ `十` (`几` không thuộc lớp ký tự của `<m>` nên không bị chặn biên) ⇒ ra "mấy mười mấy". Tên chương đã lưu bản dịch trong mục lục chỉ đổi sau "Dịch lại tên chương".
- Hướng dẫn (`QuickTranslationRuleGuide`, mục Token số và nhãn) thêm một ý. Chuyển `[1.3.672]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.702] - 2026-11-04

### fix: thu nhỏ màn kiểm tra nguồn không còn mất dòng trên hub

Người dùng (bản 1.3.698 trên máy): *"Đã thu nhỏ, kiểm tra đang chạy nhưng không hiện hub mà hiện icon thông báo"*. Lượt không bấm chia sẻ; mở lại Kiểm tra nguồn không có nút "Mở lượt đang chạy" ⇒ bản ghi chưa bao giờ được đánh dấu thu nhỏ (phần hub đúng).

- **Nguyên nhân**: nút ⌄ chỉ đóng màn rồi trông vào `onDisappear` để báo thu nhỏ; màn Legado không có lối dự phòng chắc chắn khi sheet đóng mà `onDisappear` không tới (`ScreenLease` chỉ chạy nếu SwiftUI giải phóng màn). Chưa xác nhận được trên máy lối nào rơi.
- **Nút ⌄** gọi `MinimizedSourceCheckCoordinator.screenDidClose(_, screenId: nil)` **trước** khi đóng màn, không qua `onDisappear`.
- **`onDismiss` của mọi sheet có thể chứa màn kiểm tra**: sheet Kiểm tra nguồn và Chi tiết nguồn Legado (`RepositoryManagerView+LegadoMenu`, `DiscoverySourcePickerModifier`), ba chỗ mở Cấu hình tiện ích (`RepositoryManagerView`, `DiscoverySourcePickerModifier`, `TTSSettingsView`); sheet mở lại từ hub dùng `SheetDismissRelay` (`presentationController.delegate`, gán sau khi trình bày).
- `onDisappear` của hai màn bỏ điều kiện cờ chia sẻ (bảng chia sẻ không làm màn biến mất, cờ kẹt thì chặn mất việc thu nhỏ). `update` bỏ qua lượt đã thu nhỏ (màn đóng mà task chưa dừng không cướp mốc "xong" ⇒ mất toast). Log `🧪 [SourceCheck]` ở `track` và các nhánh `screenDidClose` bỏ qua (cần bật log trong Cài đặt). `rules.md` luật hub (f) ghi các lối báo đóng. Chuyển `[1.3.671]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.701] - 2026-11-04

### feat: token số trong rule dịch có khoảng giá trị #min-max

Người dùng: *"thêm min max cho các token số trong rule dịch"*; chọn **giá trị số** (không phải độ dài, vốn đã có `<n:1-4>`), áp cho `<n>` `<d>` `<y>` `<h>` `<hn>`, cú pháp `<n#1-200>`; duyệt plan + mockup.

- **Cú pháp**: `#min-max` viết sau tên và sau độ dài: `<n#1-200>`, `<n:1-4#1-200>`, `<d#0-99>`, `#5` = đúng 5, `#100-` = từ 100 trở lên. Kiểu `QuickTranslationRuleValueRange` (mới, `Engine/`) giữ tách `#`, đọc, kẹp, dựng lại cú pháp và kiểm giá trị — parser (`QuickTranslationRuleParser+ValueRange`, mới), `tokenSpecNames` và `TokenSpec` cùng gọi nên hiểu `#` như nhau. `#…` tách **trước** `:`: tách `:` trước thì `<n:1-4#1-200>` bị đọc lặng lẽ thành độ dài `1-200`.
- **Giá trị lấy từ kết quả render**, không parse lại chữ Hán: `<n>` `<y>` `<h>` `<d>` ra chữ số ⇒ `Int` (`二零二五` = 2025, `007` = 7); `<n>` liệt kê (`十三四` → `13, 14`) ⇒ mọi số phải trong khoảng; `<hn>` (render Hán-Việt) ⇒ giá trị bằng `renderNumeral` của chuỗi nguồn; tràn `Int` / đọc không được ⇒ không khớp. Matcher (`walkNumeral`) bỏ độ dài ứng viên có giá trị ngoài khoảng rồi thử độ dài ngắn hơn, như ứng viên `<m>` sai dạng; token có biên chặn hai đầu (`第<n#1-200>章`) chỉ xét cả dãy số ⇒ `第三百章` không khớp hẳn.
- **Lỗi mới `INVALID_VALUE_RANGE` (lỗi nặng)**: `#` trống, không phải số, `#-9` (thiếu số đầu; không chặn dưới thì viết `#0-…`), khoảng ngược `#5-3` (khác độ dài vốn tự kẹp), sai thứ tự `#1-9:1-3`, hoặc `#` gắn cho `<a>` `<m>` `<L>` `<any>`, token từ điển, neo dòng, ngoặc.
- **Chip chỉnh** (`QuickTranslationRuleTokenValueRangeEditor`, mới): dưới thanh độ dài của token số có công tắc "Giới hạn giá trị" (bật ⇒ 1–100, tắt ⇒ bỏ `#`) và hai hàng `[−] ô số [+]`; ô Đến trống = không chặn trên. Ô số chỉ ghi vào mẫu khi rời ô hoặc bấm −/+, kẹp qua `clamped()` (chung với `TokenSpec.clamp()`); thanh chỉnh gắn `.id(tokenPosition)` để chữ gõ dở không dính sang token khác. `TokenSpec` giữ `valueRange` nên chỉnh độ dài không làm mất `#`; `#` viết sai ⇒ không mở thanh (không xoá phần đang gõ). Gợi ý bàn phím coi `#` là đuôi token (con trỏ trước `#…` không bị hiểu là gõ dở).
- **Rule cũ không đổi**: không thêm loại token nên chữ ký cache (`Configuration.signature`) giữ nguyên; token không ghi `#` có `valueRange == nil`, matcher không đi qua nhánh mới. Ưu tiên giữa rule không đổi: `<n>章` và `<n#1-9>章` hoà mọi tiêu chí thì dòng viết trước thắng như cũ.
- Hướng dẫn (`QuickTranslationRuleGuide`: mục Token số và nhãn + Lỗi hay gặp), câu trợ giúp ô Mẫu, đoạn token ở `CLAUDE.md`/`AGENTS.md` cập nhật. Chuyển `[1.3.670]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.700] - 2026-11-04

### fix: sửa 5 lỗi engine Legado từ báo cáo kiểm tra nguồn

Người dùng gửi hai báo cáo "Kiểm tra nguồn" (31 nguồn / 735 nguồn dừng ở 76) và duyệt plan sửa các lỗi do app. Bằng chứng lấy từ trang/API thật và corpus nguồn; phần lớn lỗi còn lại là do web hoặc nguồn cũ.

- **`java.getString/getElements` trong JS sau một phân đoạn rule chạy trên trang/mục của rule** (`LegadoRuleAnalyzer.evaluate`: `frameContent` = nội dung gốc, không còn là kết quả trung gian; `result` giữ nguyên). ㊣ UC小说 #一程1101: `$.data.chapterList[0].volumeList<js>java.put('freeUrlPre',java.getString('$.data.freeContUrlPrefix'))…` trước đây ra tiền tố rỗng, URL chương ghép vào API mục lục nên nội dung rỗng. 77 rule cùng kiểu trong corpus (书旗, 阿巴, 人人小说, 起点, 晋江…).
- **JSONPath ngầm `.x` thành `$..x`** (quét sâu, như thư viện JsonPath thêm `$.` trước đường dẫn không bắt đầu bằng `$`/`@`); `..x` và `[…]` chỉ thêm `$`. QQ阅读 ×3 `.bookList[*]`/`.books[*]` trên API trả `{"data":{"bookList":[…]}}` trước đây ra 0 mục.
- **Danh sách giá trị JSON đổi thành chuỗi ra văn bản JSON** như `JSONArray` của json-smart (`LegadoJSBootstrap.core`: `dec` gắn cờ ẩn khi mọi mục là `$json`, `toString()` dùng `JSON.stringify`). 网易云 `data.books[*]` rồi `JSON.parse(result)` trước đây lỗi `Unexpected identifier "object"`; 爱发电 `String(result).replace(/\[/,…)`, 番茄 cũng cần. Danh sách phần tử HTML và danh sách chuỗi giữ như 1.3.694; danh sách rỗng vẫn ra `""`.
- **XPath dựng trên cây SwiftSoup thay vì thân thô** (`rootXPathDocument`, nhánh chuỗi HTML của `xpathItems`): libxml2 2.9 không tự đóng `<dd>` khi gặp `<dd>` kế, nên mục lục R 玩文学 (`<dd><a>…` thiếu `</dd>`) thành lồng nhau, chương i lấy link/tên của chương i…N ⇒ HTTP 414 ở bước nội dung. Tuần tự hoá không pretty-print, escape `.xhtml` để SwiftSoup không chép lại nguyên văn thân gốc; cài đặt in của document trả lại ngay. Rule `/table/tbody/tr` (13 rule corpus) cũng khớp như cây jsoup.
- **Trường URL nhiều giá trị lấy dòng không rỗng đầu** (`LegadoURLResolver.absoluteFieldURL`, sau khi tách khối option): 一曲书屋 `bookUrl: a@href` trên `<p>` có link sách + link tác giả trước đây ra `…/book/132394/\n/author/…` ⇒ HTTP 400. `nextTocUrl`/`nextContentUrl` vẫn là danh sách.
- **Không sửa (không phải lỗi app)**: 企鹅浏览 (bản cài có `bookUrl` hỏng), 天地中文 (web trả danh sách rỗng; kết luận "app" của báo cáo là sai), ⭐ 猫眼看书③ (mọi host API lỗi), 黑岩 ×2 (UA di động mặc định ⇒ web chuyển bản `w.heiyan.com` không có `<span>`; giữ UA theo spec §3.10).
- Spec `legado-source-spec.md` cập nhật §2.2 bước 5, §2.11.1, §2.12, §2.15 bước 1, §6.3 (`toString`), bảng `java.getString`. Chuyển `[1.3.669]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; chạy `core` bootstrap bằng node với `__lgNative` giả (danh sách JSON/chuỗi/trộn/rỗng, `for…in`, export); lần tay JSONPath trên JSON QQ thật; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.

## [1.3.698] - 2026-11-04

### feat: thu nhỏ màn kiểm tra nguồn và kiểm tra tiện ích vào hub nổi

Người dùng: *"cho phép thu nhỏ khi kiểm tra nguồn, làm cho cả kiểm tra js luôn"*, rồi *"vuốt xuống sheet đừng tắt mà thu nhỏ nhé"*. Lối mở lại là dòng thứ 4 cố định của hub (người dùng chọn).

- **Rời màn không còn dừng lượt**: màn Kiểm tra nguồn Legado (`LegadoSourceCheckView`) và Kiểm tra tiện ích (`ExtensionCheckView`) có nút ⌄ sát nút chia sẻ (chỉ hiện khi đang chạy). Bấm ⌄, vuốt xuống sheet hay quay lại khi lượt còn chạy ⇒ lượt **thu nhỏ** và chạy tiếp ở bộ chạy; chỉ nút Dừng mới dừng. `stopSourceCheck` (`onDismiss` của sheet kiểm tra tiện ích hàng loạt) đổi từ huỷ lượt sang thu nhỏ.
- **`MinimizedSourceCheckCoordinator`** (mới, `Views/Extensions/SourceCheck/`): mỗi bộ chạy giữ tối đa một bản ghi (lượt Legado và lượt tiện ích JS chạy song song được). Màn bắt đầu hoặc gắn vào lượt ⇒ `track`; vòng thăm dò của màn ⇒ `update`. Màn đóng (`onDisappear`, hoặc `ScreenLease` là `@StateObject` giải phóng cùng màn, để bắt cả lúc sheet bị vuốt khi đang đẩy màn con) ⇒ lượt còn chạy thì thu nhỏ và tự thăm dò mỗi giây, lượt đã xong thì bỏ. Xong hoặc dừng khi đang thu nhỏ ⇒ toast (vào cả Trung tâm thông báo).
- **Mở lại**: `reopen` trình bày màn bằng UIKit từ màn trên cùng của cửa sổ mức thường (sheet có thanh kéo; thử lại khi màn trên cùng đang mở/đóng dở). Màn chạy ở chế độ `attachRunId`: đọc ngay kết quả hiện có, không chạy lượt mới; bộ chạy đã sang lượt khác ⇒ báo rõ và bỏ bản ghi. Màn báo bận có thêm nút "Mở lượt đang chạy" khi lượt kia đang thu nhỏ; "Dừng lượt đang chạy" ở đó cũng thôi theo dõi như nút Dừng.
- **Hub nổi**: dòng thứ 4 cố định `Kind.sourceCheck` "Kiểm tra nguồn" (`checkmark.seal`), xám khi không có lượt. Đang chạy ⇒ là tiến trình của nút (nháy), dòng phụ "12/31 · 3 lỗi"; xong mà chưa xem ⇒ nằm trong `quietKinds` (không nháy), "Xong · 25 đạt · 6 lỗi — bấm để xem". Tiến độ chỉ nằm ở chữ của dòng, không vào `ButtonState`. Hai lượt cùng thu nhỏ ⇒ trang con `FloatingHubSourceCheckListView`. Chạm hub khi đây là tiến trình duy nhất ⇒ mở thẳng màn.
- Tách phần trùng giữa hai màn: `SourceCheckHeaderButtons`, `SourceCheckTile`, `SourceCheckActionButton`, `SourceCheckStartErrorView`, `ExtensionCheckFilterChip` (giữ `ExtensionCheckView` dưới 400 dòng). `rules.md` thêm luật hub (f) cho dòng Kiểm tra nguồn và vòng đời lượt thu nhỏ. Chuyển `[1.3.668]`, `[1.3.667]` sang `CHANGELOG.archive.md`.
- **Kiểm chứng**: đọc code + diff; `check_architecture.py` chỉ còn lỗi có sẵn của `JSDom.swift`. Máy Windows nên chưa build, chưa thử trên máy — chờ CI biên dịch.
