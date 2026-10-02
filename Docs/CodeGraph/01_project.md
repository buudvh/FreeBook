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
## 1.3.479–1.3.483 — hướng A (bucket tĩnh): đo tham số, chốt lưới, sinh gói phát hành

* **Chuyển hướng sau khi Phase 0 chốt `FAIL`**: plan `Docs/Plans/2026-10-02-plan-vieneu-coreml-bucket-tinh.md` thay phần "sinh gói" bằng **N `.mlpackage` tĩnh** (đóng băng `L`, chia mức `T`) dùng `onnx2coreml` — đường đã chứng minh. `Sources/**/*.swift` **vẫn 639 file**, chưa đụng mã app.
* **`Scripts/coreml_dynamic_experiment.py`** (806 → 939 dòng): `FALLBACK_BUCKETS` 3 mức → **5 mức `t32/t64/t96/t128/t234`**; thêm giai đoạn **D7 `stage_ort_l_sweep`** đo ORT theo `L ∈ {32…256}` ở `T ∈ {64,96,234}`.
* **Vì sao D7 tồn tại**: phép so `rtf` đo trên iPhone (`[VieNeuPerf]`) với thời gian CI dự đoán bị lệch **một chiều** vì CI đo ORT ở `L = 200` đóng băng còn máy chạy `L` thật (trung vị ~91) ⇒ không tách được "máy chậm hơn CI" khỏi "máy làm ít việc hơn". ⚠️ Máy phát triển Windows **không đo được thời gian** (cùng phép đo tại chỗ ra số **không đơn điệu**: `L=91` → 371 ms nhưng `L=128` → 108 ms) ⇒ **mọi số timing phải lấy từ runner CI**.
* **Job `dynamic` trong `.github/workflows/convert-coreml.yml`** (141 → 148 dòng) in thêm bảng quét `L` ở bước `Verdict`. Nhắc lại: `build-ipa.yml` **đã bỏ** `.github/workflows/**` khỏi `paths` nên sửa file workflow **không** còn kéo theo build IPA — đã xác nhận nhiều lượt.
* **Chốt lưới `{64, 96, 234}` = 397 MB** (1,86× theo hệ số 1,28×, hoặc 1,53× theo hệ số đo được 1,05× — xem `ort_l_sweep.json` để chốt). Lý do có `t234`: `VieNeuConfig.maxChunkSeconds = 15,0` chặn `T ≤ 234` **bằng thiết kế** ⇒ đó là trần cấu trúc, không phải suy luận từ log. **`t128` vô dụng** (thêm 127,8 MB mà tỉ lệ không đổi).
* **Phase 2 — `Scripts/coreml_bucket_package.py` (mới, 295 dòng)**: sinh **8 gói** phát hành (`text_encoder` + `duration_predictor` mỗi cái 1 gói vì chỉ phụ thuộc `L`; `vector_estimator` + `codec_decoder` × 3 mức `T ∈ {64,96,234}` ⇒ 2 + 3×2), tổng **397,8 MB**. Kèm **`manifest.json`** (sha256 + size từng file — vì `VieNeuModelClient.download(_:)` hiện **chỉ** kiểm `size > 0` ⇒ không bắt được file cụt) và **`golden/T{n}.npz`** (đầu vào cố định + đầu ra tham chiếu ORT fp32 cho self-test). Job `bucket` mới trong workflow, publish bằng **Trusted Publishers OIDC** (`permissions: id-token: write`, không có secret) — đã chạy thành công.
* ⚠️ **Hai bẫy đã trả giá ở Phase 2, cả hai đều về chỗ ghi file**:
  1. *Lượt đầu*: `convert_graph` ghi gói vào `workdir` trong khi `hf upload` chỉ mang `outdir` ⇒ **publish xanh, repo nhận đúng 3,7 MB manifest+golden, không có gói nào** (xác minh bằng API `tree/main?recursive=true`: 11 mục). Đã sửa: gói ghi vào `outdir/mlpackage/`, cộng **hai lớp bắt** (script đếm `weight.bin` thật sự có mặt; workflow `exit 1` nếu không có).
  2. *Lượt hai*: `.frozen.onnx` / `.opt.onnx` **cũng** nằm trong `mlpackage/` ⇒ bị đẩy lên theo ⇒ repo phình **~400 MB → 1984,5 MB** (mỗi `vector_estimator` có 155 MB trung gian × 2 × 3 mức). App chỉ cần `.mlpackage`. Đã sửa: mọi file trung gian nằm ở `workdir` (ngoài `outdir`).
  3. *Lượt ba*: bước **dọn riêng** chạy `hf auth token` → `HfApi.delete_files` **FAIL** vì dưới Trusted Publishers OIDC **không có credential lưu** ⇒ `hf auth token` trả rỗng ⇒ không xoá được (16 `.onnx` rác 1582,9 MB vẫn còn). Đã sửa: gộp dọn vào chính lệnh `hf upload` (cái đã OIDC thành công) qua **`--delete="mlpackage/*.onnx"`** (glob phẫu thuật, chỉ xoá `.onnx` dưới `mlpackage/`, giữ `README`/manifest/golden); **xoá hẳn** bước Python dọn. ⚠️ **Bài học OIDC**: dưới Trusted Publishers **đừng** dùng `hf auth token` làm token cho Python API — nó rỗng. Mọi thao tác auth phải qua `hf` CLI (tự exchange) hoặc truyền token OIDC trực tiếp.
* **Cả hai là cùng một loại lỗi với "phép kiểm rỗng nghĩa" ở Phase 0: CI xanh mà không làm điều mình tưởng.** Phép kiểm của một bước publish phải là **"nội dung thật sự ở đích có đúng không"**, không phải "lệnh có thoát 0 không".
* Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**. Không có Swift toolchain trên Windows ⇒ không khẳng định đã kiểm chứng biên dịch.

## 1.3.472–1.3.475 — Phase 0: thăm dò `.mlpackage` **shape động** cho CoreML (cổng của plan engine Core ML)

* Thêm `Scripts/coreml_shape_surgery.py` (376 dòng) — thay op `Range` (không có lowering trong Core ML) bằng `Slice(arange(0, MAX), starts, ends, axes=[0], steps=[delta])`. Khác bản né trước đó ở chỗ **không đóng băng shape**: `limit` vẫn là tensor suy từ `Shape` nên chiều động giữ nguyên. `investigate()` truy vết từng `Range` về `Shape(...)` để biết nó phụ thuộc chiều nào; **raise** khi không truy vết được, vì `MAX` quá nhỏ làm `Slice` **cắt cụt im lặng**. `normalize_clip()` cấp `max = +inf` tường minh cho `Clip` bỏ trống input thứ ba (không có nó thì `onnx2torch` chết ngay).
* Thêm `Scripts/coreml_dynamic_experiment.py` (806 dòng) — **5 đường** convert, mỗi đường trả lời **một** câu hỏi (`o2c_original` · `o2c_surgery` · `torch_original` · `torch_surgery` · `torch_enum_T`); đo parity/độ trễ/thời gian biên dịch ở 3 shape cho `ALL` và `CPU_ONLY`; **chứng minh phẫu thuật không đổi số** (D2b); đo `trace_shapes` để chứng minh `torch.jit.trace` nướng shape; sinh `golden.npz`; luôn thu số liệu bucket dự phòng.
* **`.github/workflows/convert-coreml.yml` thêm job `dynamic`** (70 → 141 dòng) — job `convert` cũ **giữ nguyên** làm mốc so sánh. Job mới cài thêm `torch` + `onnx2torch`; workdir `coreml-dynamic` (không bắt đầu bằng dấu chấm, vì `upload-artifact` bỏ qua thư mục ẩn); cố ý **không** upload `.mlpackage` (≈1,2 GB cho 4 graph × 5 đường, trong khi Phase 1 chạy lại conversion chỉ ~7 s/graph). *(Job `dynamic` **đã gỡ ở 1.3.486** — Phase 0 = FAIL nên chạy lại mỗi push chỉ tốn CI, không thêm thông tin.)*
* **Trigger `push` của workflow giờ gồm cả 2 script mới** — sửa script là tự chạy lại.
* ⚠️ **`build-ipa.yml` đã bỏ `.github/workflows/**` khỏi `paths` (2026-10-02)** — trước đó sửa bất kỳ file workflow nào cũng kéo theo một lượt build IPA đầy đủ (xem mục 1.3.471). Từ nay sửa `convert-coreml.yml` **chỉ** chạy job CoreML. Lưu ý: `01_project.md` khai `.github/workflows/*.yml` trong `sourcePatterns`, nên **mọi** thay đổi file workflow vẫn làm doc này stale — đó là chủ ý, không phải hệ quả của `build-ipa.yml`.
* **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file; `project.yml` và `Sources/App/FreeBookApp.swift` không đổi.
* **Publish lên HuggingFace** chốt bằng **Trusted Publishers (OIDC)** thay cho token tĩnh: claim `repository equals buudvh/FreeBook` + `workflow_ref starts with buudvh/FreeBook/.github/workflows/convert-coreml.yml@`. Không thêm secret nào vào GitHub repo. Lưu ý: claim khớp **chính xác**, nên **đổi tên file workflow là hỏng publish** cho tới khi sửa lại claim trên HuggingFace.
* **Sự kiện kỹ thuật đã đo** (dùng cho các lượt sau, đừng thí nghiệm lại): chỉ **2/4 graph có `Range`** — `text_encoder` 1 node (phụ thuộc `L`), `vector_estimator` 6 node (5 node phụ thuộc **`T`**, 1 node phụ thuộc `ctx[1]` = `L`). Phẫu thuật **bit-exact** (`max|Δ| = 0`) ở cả 6 điểm thử, kể cả `L=300`/`T=234` chưa từng dùng khi phẫu thuật. `onnx2coreml` **đòi shape tĩnh** (đo, không chỉ đọc tài liệu) và **không có lowering cho `Range`**. `onnx2torch` **chết với `Clip` bỏ trống `max`** (`node_converters/clip.py:60` gọi `get_const_value('')`) — vá bằng `normalize_clip`. `onnx2torch` **nướng shape** qua `torch.Size` ở `node_converters/reshape.py:23` ⇒ `torch.jit.trace` **không** giữ được chiều động.
* ⚠️ **Bài học về phép kiểm rỗng nghĩa**: lượt CI #2 báo `text_encoder` trace "chạy lại OK ở cả 3 shape", nhưng đó là vì `make_feeds` không cắt/đệm `ids` về đúng `length` ⇒ cả 3 "shape" thực ra **giống hệt nhau**. Phép kiểm xanh mà không đo gì là loại lỗi nguy hiểm nhất trong loại script này — đã thêm `_fit_ids()`. Cùng chủ đề: `verdict` giờ **chỉ** tính đường shape động (`torch_*`), không tính `o2c_*` (chúng chỉ sống khi shape đã đóng băng).
* **⭐ KẾT LUẬN PHASE 0 = `FAIL`.** Bốn `.mlpackage` **có** được sinh ra, tổng **142,0 MB** (khớp ước tính ~141,6 MB của plan ⇒ phần dung lượng của plan đúng), nhưng `trace_ok` = **1/3** cho `text_encoder`/`vector_estimator`/`codec_decoder` (chỉ `duration_predictor` 3/3, mà nó chiếm ~0 % thời gian) ⇒ **không có gói shape động nào dùng được**. Vì vậy `verdict` bắt buộc phải kiểm `trace_shapes` toàn `ok`, chứ "convert được" **không đủ**: `ct.convert` vẫn dựng ra gói có `RangeDim` từ graph đã bị nướng shape — gói đó compile được nhưng cho kết quả **sai/im lặng** ở shape khác.
* **Số liệu phương án bucket dự phòng** (nếu sau này cần): 3 mức × 2 graph = **384,0 MB**; tại bucket `t234`: `vector_estimator` **2,87×**, `codec_decoder` **1,23×**. Theo quyết định #6 của plan, lượt này **dừng** chứ **không** tự chuyển sang bucket.
* Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**. Không có Swift toolchain trên Windows ⇒ không khẳng định đã kiểm chứng biên dịch.

## 1.3.471 — workflow thí nghiệm CoreML (một lần, không đụng CI IPA)

* Thêm `.github/workflows/convert-coreml.yml` — **workflow riêng**, chỉ chạy khi `workflow_dispatch` hoặc khi chính file đó đổi. Runner `macos-15` (Apple Silicon ⇒ **có ANE**), Python 3.12 vì `onnx2coreml` yêu cầu `>=3.11,<3.14`.
* Thêm `Scripts/coreml_convert_experiment.py` — tải model ghim revision, `analyze` 4 graph, chốt shape tĩnh rồi convert `vector_estimator` (2 bucket) + `codec_decoder` (1 bucket), và **so số + đo tốc độ Core ML fp16 vs ORT fp32 trên cùng một máy**; mọi giai đoạn bọc `try/except` để lỗi ở đâu cũng là kết quả thu được.
* **Không** sửa `Sources/`, **không** sửa `build-ipa.yml`. Lưu ý (đúng ở thời điểm 1.3.471, **đã hết hiệu lực từ 2026-10-02**): `build-ipa.yml` khi đó có `paths: '.github/workflows/**'` nên push file workflow này **cũng** kích hoạt một lượt build IPA. Hai dòng đó đã được gỡ; xem mục 1.3.472–1.3.475.
* Trigger `push` gồm **cả** `Scripts/coreml_convert_experiment.py` (sửa script là tự chạy lại); `workflow_dispatch` để chạy tay. Thư mục làm việc **không** được bắt đầu bằng dấu chấm (`upload-artifact` bỏ qua thư mục ẩn ⇒ mất `.mlpackage`).
* **Kết quả lượt chạy `36990902528`** (chi tiết ở `Docs/Reports/research-2026-10-02-vieneu-xnnpack-va-turbo.md` §7): convert được `vector_estimator` **78,1 MB** + `codec_decoder` **49,7 MB** (op chặn `Range` giải bằng `ORT_ENABLE_BASIC` constant folding — **không** dùng `ORT_ENABLE_ALL`); fp16 SNR **49,0 dB**; Core ML nhanh hơn ORT CPU **~2×** (`vector_estimator` 120,6 → 56,8 ms; ước lượng 1 chunk 2180 → 1103 ms) **kể cả `CPU_ONLY`** ⇒ lợi ích đến từ runtime CPU + fp16 của Core ML, không phải ANE.


## `project.yml` thêm `NSMicrophoneUsageDescription` + cổng CI `fbank-gate` (1.3.451 / 1.3.453)

* **Quyền micro là điều kiện sống còn, không phải "cho chắc"**: thiếu `NSMicrophoneUsageDescription` trong `Info.plist` thì iOS **kill app** ngay khi phiên âm thanh chạm tới input — không phải trả `false` rồi thôi. Chuỗi thêm vào `info.properties`:
  `"FreeBook dùng micro để thu 3–8 giây giọng nói làm mẫu, từ đó tạo giọng đọc riêng cho phần đọc truyện. Bản thu chỉ nằm trên máy bạn."`
* **Workflow thứ hai**: [`.github/workflows/fbank-gate.yml`](../../.github/workflows/fbank-gate.yml) — cổng số cho `VieNeuFbank.swift`. Khác `build-ipa.yml` ở chỗ nó **chạy thật** Swift (`swiftc -O VieNeuFbank.swift Scripts/FbankGate/main.swift`) rồi so với một bản numpy độc lập; `runs-on: macos-15`. Kích hoạt bằng `push` theo `paths` (`Scripts/FbankGate/**`, `VieNeuFbank.swift`, chính nó) nên là cổng **chống hồi quy**, không chỉ chạy tay.
* **Vì sao cần cổng riêng**: máy phát triển là Windows **không có Swift toolchain**, nên tại chỗ chỉ chạy được bản dịch Python của cùng thuật toán. Đây là chỗ **duy nhất** mã Swift thật được thi hành trong CI ngoài `build-ipa.yml`.
* `sources: - path: Sources` không đổi; `Scripts/` **không** thuộc target app nên `FbankGate` không vào bản build.
* `Sources/App/FreeBookApp.swift` **không đổi**.

## `project.yml` có thêm `SWIFT_OBJC_BRIDGING_HEADER` cho cầu nối C của VieNeu-TTS (1.3.417)

* **Thay đổi build-config đầu tiên của phân hệ VieNeu**: `settings.base.SWIFT_OBJC_BRIDGING_HEADER: Sources/Services/TTS/VieNeu/VieNeuONNXBridge.h`. Đây là bridging header **đầu tiên** của target — trước đó `Sources/` không có file `.h`/`.m`/`.mm` nào.
* **Vì sao bắt buộc**: engine VieNeu phải tạo tensor **bool** (`ctx_mask` của `duration_predictor`/`vector_estimator` khai `elem_type = 9 = BOOL`; node duy nhất dùng nó là `Not`, mà `Not` của ONNX chỉ nhận bool), mà lớp ObjC của ONNX Runtime không có case `Bool`. C API có, nhưng `import onnxruntime` **không** hoạt động từ target app: product SPM `onnxruntime` chỉ trỏ tới target ObjC `OnnxRuntimeBindings`, còn binary target C là dependency nội bộ và umbrella header không `#import` header C API. Nên phần C API nằm ở `VieNeuONNXBridge.m` và Swift thấy nó qua bridging header.
* **Rủi ro đã biết**: sai đường dẫn bridging header là **mọi** file Swift hỏng biên dịch, không riêng phân hệ VieNeu. Đường dẫn tính từ gốc project (`Sources/...`), đúng như `sources: - path: Sources`.
* `sources: - path: Sources` vẫn khai theo thư mục nên `VieNeuONNXBridge.h/.m` tự vào target; chỉ cần `xcodegen generate` như thường lệ.

## Luật "View không ghi SwiftData" đã sạch nợ ở hai View lớn cuối (1.3.334)

* **Mục 2 của bản tổng kết v4.1/v5.0 bên dưới giờ mới đúng hoàn toàn.** Nó tuyên bố "SwiftUI Views không được gán thuộc tính `@Model`", nhưng tới trước 1.3.334 vẫn còn đúng hai chỗ vi phạm thật: `ReaderView.initializeReaderIfNeeded` và `BookDetailView.task(id:)` gọi `BookTitleTranslationMigrator.refreshTranslations(for:)` — hàm này gán `titleTrans`/`authorTrans` rồi View tự `try? modelContext.save()`. Cả hai nay đi qua `BookTransactionCoordinator.refreshTitleTranslations(bookId:in:)` và xử lý `Result`. Migrator chỉ còn gán và trả `Bool` didChange; **không** còn `save()` bên trong nó.
* **Command mới không mang DTO** — khác với `AddBookToShelfCommand`/`UpsertExtensionCommand`. `refreshTitleTranslations` nhận `bookId: String` vì payload thật (bảng từ điển VietPhrase) là state toàn cục của `TranslationManager`, không phải giá trị caller cung cấp; đóng nó vào struct chỉ tạo DTO một trường vô nghĩa. Khuôn còn lại vẫn giữ: `in context: ModelContext`, trả `Result`, `try context.save()` là dòng cuối.
* **`check_architecture.py` 12 → 8 violation.** Bốn chỗ hết: hai `VIEW_SWIFTDATA_MUTATION` trên và hai món nợ dòng (`ReaderChapterListView` 468 → 295, `ReaderDefinitionOverlayView` 489 → 372, cả hai nhờ tách file `+List`/`+Download`/`+Rules`/`+Rows`). Baseline trong `architecture_allowlist.json` **không** bị siết theo — chấp nhận ~200 dòng dư hơn là khoá cứng con số vừa đạt được.
* **Gate được sửa chính xác hơn, không nới**: regex gán `@Model` ở `check_architecture.py:144` thêm lookbehind `(?<!\bself)`. `DiscoveryView` bị báo oan cho `self.currentChapterIndex = …` — đó là `@State` của chính struct View, không phải `@Model`. Mọi `<biến khác>.currentChapterIndex = …` vẫn bị bắt.
* **Không mở cơ chế nào, không thêm dependency, không đổi schema** ở lượt này: 8 file mới, 2 file xoá, `Sources/**/*.swift` 477 → 483. `project.yml` khai `sources: - path: Sources` theo thư mục nên file mới **không** cần sửa manifest.

## Phân hệ Bộ sưu tập sách — `@Model` thứ 6 (1.3.328)

* **Lần đầu schema SwiftData lớn thêm kể từ khi repo có 5 `@Model`.** `BookCollection` (`Sources/Models/Database/BookCollection.swift`) quan hệ **N-N** với `Book`; `FreeBookApp.init()` vẫn là **chỗ duy nhất** khai schema. Không có `VersionedSchema`/`SchemaMigrationPlan`, nên mọi field mới phải additive + có mặc định (`Book.isPinned = false`, `Book.collections = []`) — lightweight migration là toàn bộ hàng rào ở đây, và `ModelContainer` init thất bại là `fatalError`.
* **Không mở cơ chế mới nào**: chiều phụ thuộc vẫn View → coordinator → Models. `BookCollectionCoordinator` (`@MainActor`) là chủ transaction duy nhất của bộ sưu tập, cùng khuôn `in context: ModelContext` → `Result` như `BookTransactionCoordinator`/`ExtensionTransactionCoordinator`. Tầng Views chỉ `@Query` để đọc.
* **Tên type là `BookCollection`, không phải `Collection`** — `Collection` ở phạm vi module sẽ che `Swift.Collection` và làm mọi generic constraint viết sau này hiểu sai type. Đây là quyết định có chủ ý, không phải đặt tên dài cho vui.
* **Sao lưu mở rộng theo đúng lối cũ**: `library/collections.json` + `BookRecord.isPinned` đi kèm nhóm `.books`, **không** thêm case `BackupScope` (rawValue vào `manifest.scopes` sẽ làm bản app cũ decode lỗi — luật đã ghi hai lần trong `BackupPaths.swift`).
* **Một vi phạm kiến trúc cũ được trả nợ trong cùng lượt**: `ShelfView.removeFromHistory` từng gán `book.isHistory` rồi `try? modelContext.save()` ngay trong View; nay đi qua `BookTransactionCoordinator.setHistory`. `check_architecture.py` từ 14 → **13** violation.

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
