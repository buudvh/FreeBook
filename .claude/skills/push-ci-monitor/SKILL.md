---
name: push-ci-monitor
description: "Duyệt plan (coi lệnh này/lời gọi này là sự chấp thuận implementation plan), thực thi sửa code theo plan kèm rà soát checklist kỹ thuật từng bước, kiểm tra kiến trúc và CodeGraph, commit, push và theo dõi tiến độ CI chi tiết bằng lệnh gh run view. Nếu CI thất bại, tự động sửa lỗi và commit lại với đúng commit message cũ cho đến khi CI thành công."
---

# Push & CI Monitor Skill

Skill này đóng vai trò là hành động **Duyệt Plan (Implementation Plan Approval)** và tự động hóa toàn diện chu trình phát triển: thực thi sửa mã nguồn theo plan (kèm rà soát checklist kỹ thuật từng bước), kiểm tra chất lượng (Quality Gate), commit & push, theo dõi tiến độ chi tiết từng bước bằng GitHub CLI (`gh run view`), và tự động sửa lỗi commit lại bằng message cũ nếu CI gặp lỗi.

---

## Ý nghĩa & Khi nào sử dụng skill này?

Sử dụng skill này khi người dùng yêu cầu:
- Gửi lệnh `/push-ci-monitor` hoặc nói "duyệt", "duyệt plan", "duyệt, sửa xong push code và theo dõi CI..." sau khi Agent đã trình bày `implementation_plan.md`.
- **Nguyên tắc cốt lõi**: Từ khóa **"Duyệt"** ở đây là **Duyệt Implementation Plan**. Lệnh này là tín hiệu phê duyệt kế hoạch, yêu cầu Agent chuyển ngay sang chế độ thực thi (Execution Phase) mà không cần hỏi lại.
- Tự động sửa code $\rightarrow$ kiểm tra chất lượng $\rightarrow$ commit, push $\rightarrow$ theo dõi tiến độ CI bằng `gh run view` cho đến khi bản build hoàn tất thành công.

---

## Quy trình 6 bước thực hiện

```mermaid
graph TD
    1[1. Duyệt Plan & Thực thi sửa code theo Checklist] --> 2[2. Quality Gate: Architecture & CodeGraph]
    2 --> 3[3. Git Commit & Push]
    3 --> 4[4. Lấy GH_TOKEN & Run ID qua gh]
    4 --> 5[5. Theo dõi tiến độ chi tiết bằng gh run view]
    5 -->|Thành công| 6A[6A. Báo cáo hoàn tất & Kết thúc]
    5 -->|Thất bại| 6B[6B. Trích xuất log lỗi & Phân tích]
    6B --> 6C[6C. Sửa mã nguồn & Chạy lại Quality Gate]
    6C --> 6D[6D. Commit lại với ĐÚNG message cũ]
    6D -->|Push & Lặp lại| 4
```

---

### Bước 1: Duyệt Plan & Thực thi sửa code

1. **Nhận diện phê duyệt**:
   - Khi nhận lệnh `/push-ci-monitor` hoặc câu lệnh chứa "duyệt", Agent xác nhận kế hoạch trong `implementation_plan.md` đã được người dùng thông qua.
   - Lập tức chuyển sang chế độ thực thi (Execution Phase).

2. **Thực thi sửa code theo từng bước**:
   - Tiến hành chỉnh sửa, bổ sung các file mã nguồn Swift, cấu hình dự án hoặc UI theo đúng các hạng mục đã thỏa thuận trong plan.
   - **Quy tắc theo dõi tiến độ**: Thực hiện tới bước nào thì đánh dấu check `[x]` vào checklist tương ứng (trong implementation plan hoặc thông báo tiến độ) để người dùng dễ dàng theo dõi.
   - Giữ gìn các quy chuẩn lập trình và tính toàn vẹn của mã nguồn hiện hữu.

3. **Checklist Kỹ thuật Bắt buộc khi Sửa Code (Coding Rules Checklist)**:
   Trước và trong quá trình viết code, Agent bắt buộc phải đối chiếu và tuân thủ các quy tắc sau:

   - **Phạm vi & Tính toàn vẹn (Scope Preservation)**:
     - [ ] Chỉ sửa đổi các file và logic nằm trong `implementation_plan.md` đã duyệt.
     - [ ] Nếu phát hiện lỗi phát sinh ngoài phạm vi hoặc cần refactor thêm: **Dừng lại, thông báo cho người dùng và cập nhật plan** (tuân thủ Rule 5), không tự ý mở rộng phạm vi.

   - **Kiến trúc & Cấu trúc File (Architecture & File Limits)**:
     - [ ] Đặt file đúng tầng: `Sources/App`, `Sources/Common`, `Sources/Models`, `Sources/Services`, `Sources/Views`. Chiều phụ thuộc: Views $\rightarrow$ ViewModel/Coordinator $\rightarrow$ Services/Repositories $\rightarrow$ Models.
     - [ ] File mới tối đa **$\le 400$ dòng vật lý**.
     - [ ] File legacy chỉ được phép giảm hoặc giữ nguyên số dòng (ratchet down), không tăng vượt baseline. Tách file extension theo mẫu `X+Feature.swift` khi cần mở rộng.
     - [ ] Đúng **1 primary type** (class/struct/enum/actor) ở top-level mỗi file.
     - [ ] Không tạo lại thư mục hoặc target `Tests/` (tầng test đã bị xóa).

   - **SwiftData & Tương tác Dữ liệu (SwiftData Invariants)**:
     - [ ] `Sources/Views/**` TUYỆT ĐỐI KHÔNG gọi `modelContext.insert/delete/save` hay gán trực tiếp thuộc tính `@Model`. Mọi mutation phải đi qua Coordinator (`BookTransactionCoordinator`, `ExtensionTransactionCoordinator`) với Command DTO bất biến.
     - [ ] Không viết predicate lọc chuỗi trong `@Query` (tránh lỗi bộ dịch SQLite iOS 17) — truy vấn toàn bộ và lọc trên RAM bằng computed property.
     - [ ] Background tasks phải khởi tạo `ModelContext` riêng từ `ModelContainer`, không dùng chung context của `@MainActor`.
     - [ ] `ChapterStoreConfiguration.enableSwiftDataTOCWrite = false`: mục lục chương lưu ở raw SQLite `chapters/chapter_store.sqlite` (`ChapterStore`), không nằm ở bảng SwiftData `Chapter`.

   - **Tách biệt Service & UI (Service / UI Decoupling)**:
     - [ ] `Sources/Services/**` TUYỆT ĐỐI KHÔNG `import SwiftUI` (ngoại lệ duy nhất: file kết thúc bằng `*WebViewLoader.swift`).
     - [ ] `Sources/Services/**` TUYỆT ĐỐI KHÔNG gọi `ToastManager.shared`. Phải phát event qua AsyncStream (`TTSPresentationEventCenter`, `DownloadPresentationEventCenter`) hoặc trả về `Result`.

   - **Chuẩn hoá Văn bản & Toạ độ (TextKit, Reader, TTS Invariants)**:
     - [ ] Chỉ dùng `ChapterTextNormalizer` (`normalize` / `normalizeProcessedContent`) để chuẩn hoá text chương. Reader và TTS không tự tách/đánh số lại dòng.
     - [ ] `ChapterTextLine.id` tính cả dòng trống $\rightarrow$ ID dòng là thưa (sparse), không phải index mảng, luôn tra cứu theo ID.
     - [ ] Mọi toạ độ / offset trao đổi với UIKit/TextKit là UTF-16 `NSRange`, không dùng `String.Index` hay `Character`.
     - [ ] `ReaderTextView` bắt buộc giữ TextKit 1 (`usingTextLayoutManager: false`).
     - [ ] Highlight coordinate: `TTSParagraph.range` là offset UTF-16 trên chuỗi đang hiển thị (đã dịch nếu bật VietPhrase), tương đối với dòng cha. Không dùng mapper bọc highlight.

   - **Concurrency, Threading & Bộ nhớ (Concurrency & Memory Rules)**:
     - [ ] Không chặn Main Thread bằng `DispatchSemaphore` khi đợi `WKWebView` (dùng `withCheckedContinuation`).
     - [ ] Không gọi `espeak` / `EspeakPhonemizer` từ SwiftUI `body`, computed property hoặc `@MainActor` (dùng `Task.detached` + `@State`).
     - [ ] Mọi kiểu dữ liệu crossing `Task.detached` boundary phải conform `Sendable`.
     - [ ] Không khởi tạo `NSRegularExpression` trong vòng lặp hay hàm chạy per-token / per-line (dùng `static let`).
     - [ ] Dọn dẹp cache PCM `preloadedData`/`preloadedDurations` đúng cửa sổ trượt từng engine; callback ngầm dùng `[weak self]`.
     - [ ] Không dùng shared `JSExecutor` cho các tác vụ bóc tách (mỗi tác vụ tạo mới và giải phóng, ngoại trừ `ExtTTSRuntime`).

   - **Logging & An toàn Runtime**:
     - [ ] Mọi log phải dùng `AppLogger.shared.log(...)`, KHÔNG gọi `print(...)` trực tiếp. Không log token/secret/payload chương.
     - [ ] `CancellationError` không được ghi nhận là lỗi tổng hợp âm thanh hay failure state.

---

### Bước 2: Quality Gate sau khi sửa code

Trước khi commit bất kỳ thay đổi nào, bắt buộc phải vượt qua toàn bộ các cổng kiểm tra tĩnh:

1. **Kiểm tra kiến trúc (`check_architecture.py`)**:
   ```bash
   python Scripts/check_architecture.py
   ```
   - Đảm bảo **0** vi phạm mới do các thay đổi gây ra.
   - Các file mới phải $\le 400$ dòng và chỉ có 1 primary type ở top-level.
   - Các file legacy chỉ được phép giữ nguyên hoặc giảm số dòng dưới baseline.
   - Tuyệt đối không vi phạm View SwiftData Mutation hay Service SwiftUI Import.

2. **Kiểm tra CodeGraph tài liệu (`validate_links.py`)**:
   ```bash
   python Docs/CodeGraph/validate_links.py --explain
   ```
   - Xác định danh sách các doc bị stale (ảnh hưởng bởi các file Swift đã đổi).
   - Cập nhật nội dung các doc bị ảnh hưởng trong vùng `<!-- GENERATED START --> ... <!-- GENERATED END -->`.
   - Ghi nhận từng doc đã sửa bằng:
     ```bash
     python Docs/CodeGraph/validate_links.py --accept <doc_id...>
     ```
   - Đối với các doc vẫn giữ nguyên tính đúng đắn, ghi nhận bằng:
     ```bash
     python Docs/CodeGraph/validate_links.py --no-change-needed <doc_id...>
     ```

3. **Cập nhật `CHANGELOG.md`**:
   - Thêm entry phiên bản mới `[1.3.NNN] - YYYY-MM-DD` (tăng `NNN` lên 1 đơn vị so với bản gần nhất).
   - Tiêu đề entry phải **trùng khớp với subject của git commit**.
   - Nếu `CHANGELOG.md` vượt quá ~30 entry, đẩy các entry cũ nhất sang `CHANGELOG.archive.md` để giữ file chính gọn.

4. **Xác thực đọc-chỉ (Read-only)**:
   ```bash
   python Docs/CodeGraph/validate_links.py
   ```
   - Bắt buộc phải **PASS 100%** (không có link chết, không có file mồ côi, không còn doc nào stale).

---

### Bước 3: Commit & Push lên Git

1. **Lưu trữ commit message vào biến/context**:
   Xác định rõ commit message chuẩn theo quy ước (ví dụ: `feat: ...`, `fix: ...`).
   Ghi nhớ thông điệp này (`COMMIT_MSG`) để tái sử dụng nếu cần sửa lỗi.

2. **Stage và Commit**:
   ```bash
   git add -A && git commit -m "$COMMIT_MSG"
   ```

3. **Push lên nhánh tương ứng**:
   ```bash
   git push origin <branch_name>
   ```

---

### Bước 4: Lấy quyền xác thực & Tra cứu CI Run qua `gh`

Kiểm tra trước bằng `gh auth status` — **nếu đã xanh thì bỏ qua toàn bộ mục này** (máy này đã đăng nhập sẵn, không cần `GH_TOKEN`). Nếu chưa cấu hình `gh auth login`, tự động trích xuất token xác thực từ Git Credential Manager mà không làm phiền người dùng:

- **Trên Windows PowerShell**:
  ```powershell
  $token = ("protocol=https`nhost=github.com`n" | git credential fill | Select-String "password=").Line.Replace("password=", "").Trim()
  $env:GH_TOKEN = $token
  gh run list --limit 3
  ```

- **Trên macOS / Linux (bash/zsh)**:
  ```bash
  export GH_TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill | grep '^password=' | cut -d= -f2)
  gh run list --limit 3
  ```

Xác định **Run ID** mới nhất được kích hoạt bởi commit vừa push (trạng thái ban đầu thường là `queued` hoặc `in_progress`).

---

### Bước 5: Theo dõi tiến độ chi tiết bằng `gh run view` (Non-blocking)

> [!IMPORTANT]
> **Không bao giờ chạy polling loop liên tục** làm lãng phí tài nguyên và làm nghẽn context. Cách **đã kiểm chứng trên WorkBuddy**: chạy `gh run watch <run_id> --exit-status --interval 30` với `run_in_background=true`, rồi `TaskOutput` `block=true` — lệnh tự thoát khi run kết thúc và trả về exit code. (Công cụ `schedule` / `DurationSeconds` là của Antigravity, **không** tồn tại trên WorkBuddy.)

1. **Lệnh theo dõi tiến độ chi tiết**:
   Sử dụng lệnh `gh run view` để kiểm tra trực tiếp tiến trình từng step trong workflow:
   ```powershell
   gh run view <run_id>
   # Hoặc xem chi tiết theo job ID:
   gh run view --job=<job_id>
   ```
   Lệnh này hiển thị rõ ràng cây trạng thái của từng bước:
   - `✓ Set up job`
   - `✓ Checkout Repository`
   - `✓ Cache Homebrew & Install XcodeGen`
   - `✓ Generate Xcode Project`
   - `✓ Resolve and patch Package dependencies`
   - `* Build and Archive App (Unsigned)`
   - `* Package IPA`
   - `* Upload IPA Artifact`
   - `* Send IPA to Telegram`

2. **Cách chờ đã kiểm chứng (WorkBuddy)**:
   - Một lệnh duy nhất, chạy nền: `gh run watch <run_id> --exit-status --interval 30` (`run_in_background=true`).
   - Chờ kết quả: `TaskOutput` với `block=true` + `timeout` dài (run này mất **~7–9 phút** trên macOS runner) ⇒ lệnh trả về ngay khi CI xong.
   - Muốn xem cây step giữa chừng: `gh run view <run_id>` (đọc nhanh, không chặn).

---

### Bước 6: Xử lý Kết quả (Pass / Fail & Auto-remediation)

#### Trường hợp 1: CI THÀNH CÔNG (`✓ SUCCESS`)
1. Báo cáo hoàn tất cho người dùng kèm theo:
   - Run ID và link GitHub Actions run.
   - Tóm tắt các giai đoạn đã hoàn tất thành công từ output của `gh run view`.
2. Tạo hoặc cập nhật file báo cáo `walkthrough.md`.
3. Kết thúc câu phản hồi bằng: `"CodeGraph updated."` (hoặc `"No CodeGraph update required."`).

#### Trường hợp 2: CI THẤT BẠI (`X FAILURE`)
1. **Trích xuất thông tin lỗi**:
   - Chạy lệnh xem log thất bại:
     ```powershell
     gh run view --log-failed --job=<job_id>
     ```
   - Nếu log bị cắt ngắn hoặc nằm trong phần diagnostics, dump log ra file tạm và lọc các dòng lỗi:
     ```powershell
     gh run view --log --job=<job_id> > ci_log.txt
     Select-String -Path ci_log.txt -Pattern "error:" -Context 3,3
     ```

2. **Phân tích nguyên nhân & Sửa mã nguồn**:
   - Phân tích nguyên nhân cụ thể gây lỗi compile / archive trên macOS runner.
   - Tiến hành chỉnh sửa chính xác các vị trí gây lỗi trong source code.
   - Xóa file log tạm sau khi trích xuất xong (`Remove-Item ci_log.txt -Force`).

3. **Kiểm tra lại chất lượng**:
   - Chạy `check_architecture.py` đảm bảo không vi phạm kiến trúc.
   - Chạy `validate_links.py --explain` và cập nhật CodeGraph/manifest nếu có file thay đổi.
   - Đảm bảo `validate_links.py` PASS 100%.

4. **Commit lại với ĐÚNG commit message cũ**:
   > [!WARNING]
   > Theo quy định, khi sửa lỗi sau CI fail, phải commit lại bằng **đúng commit message cũ ban đầu** (`$COMMIT_MSG`), không đổi nội dung message commit:
   ```bash
   git add -A && git commit -m "$COMMIT_MSG"
   git push origin <branch_name>
   ```

5. **Tiếp tục theo dõi**:
   - Lấy Run ID mới và quay trở lại **Bước 4** và **Bước 5** (tiếp tục dùng `gh run view`) cho đến khi CI báo `✓ SUCCESS`.
