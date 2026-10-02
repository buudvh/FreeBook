# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.490] - 2026-10-03

### fix: sua coreMLRevision sang revision HF that (het 404 tai Core ML)

Người dùng báo *"lỗi tải manifest.json thất bại 404"* khi bật Core ML.

- **Nguyên nhân**: `VieNeuModelClient.swift:39` ghim `coreMLRevision = "68af081"` — đó là **sha commit của repo GitHub FreeBook** (lượt CI publish Phase 2), **không phải** revision của repo HuggingFace. HF có git sha **riêng** (`5dec42607c10252b7f412db01eba45bd86c6bbe3`) ⇒ `…/resolve/68af081/manifest.json` trả **404**. Repo **public** (`private:false, gated:false`) — 404 là do revision sai, **không** phải quyền.
- **Phạm vi**: `coreMLBase` (`:48-50`) dùng chung revision ⇒ **mọi** file Core ML (8 gói × 3 file + 3 `golden/*.npz`) đều 404, không riêng manifest — Core ML không tải về được.
- **Sửa**: `coreMLRevision = "5dec42607c10252b7f412db01eba45bd86c6bbe3"` (kiểm chứng **200** cho cả file gốc lẫn file lồng trong `.mlpackage`: manifest 10 974 B · golden 727 958 B · weight.bin 77 737 952 B). Cập nhật comment `:23-24`/`:36-38`/`:47` cho khỏi nhầm sha GitHub với revision HF.
- **Bài học**: repo HF có **git sha riêng** — KHÔNG dùng sha commit GitHub làm revision. Muốn pin thì lấy `sha` từ `GET /api/models/<repo>`.
- Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--no-change-needed` 5 doc — sửa cơ học, mô tả vẫn đúng).

---

## [1.3.489] - 2026-10-02

### feat: tich hop Core ML bucket tinh vao engine VieNeu-TTS (Phase 3-5)

Vòng sửa thứ hai sau CI (`37031622247` — **X FAILURE**, `Build and Archive App (Unsigned)` exit 65). Giữ **nguyên subject**, **không amend/force-push**.

- **1 lỗi biên dịch**: `TTSSettingsView+VieNeu.swift:21` — `var vieNeuModelReady: Bool` có câu lệnh `let store = …` rồi biểu thức nhưng **thiếu `return`**. Swift chỉ cho implicit return ở getter **một biểu thức**; có thêm `let` là getter **nhiều câu lệnh** ⇒ phải `return` tường minh. Đã thêm `return`.
- **Bài học**: getter nhiều câu lệnh **bắt buộc** `return`; `let x = …` rồi `x || y` **không** tự trả về.
- Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--no-change-needed` 3 doc — sửa cơ học, mô tả vẫn đúng).

---

## [1.3.488] - 2026-10-02

### feat: tich hop Core ML bucket tinh vao engine VieNeu-TTS (Phase 3-5)

Vòng sửa sau lượt CI đầu (`37030475201` — **X FAILURE**, `Build and Archive App (Unsigned)` exit 65). Giữ **nguyên subject**, **không amend/force-push**.

- **8 lỗi biên dịch** (chỉ CI bắt được — Windows không có Swift toolchain): `VieNeuCoreMLRuntime.swift:165` `MLMultiArray` không có `floatValue(at:)` ⇒ `array[0].floatValue` · `VieNeuModelClient.swift:104,105` dùng `voicesURL`/`g2pURL` (static) như thành viên instance ⇒ `Self.voicesURL`/`Self.g2pURL` · `VieNeuModelClient.swift:276` `hasher.update(…)` thiếu nhãn `data:` ⇒ `hasher.update(data: Data(buffer[..<read]))` · `VieNeuModelManagerView+Sections.swift:102` gọi `store.coreMLCompiledURL(for:)` nhưng đó là **thuộc tính** `URL` ⇒ `store.compiledURL(for:)` · `…+Sections.swift:129-131` `isDownloading`/`downloadProgress`/`downloadMessage` là `@State private` ⇒ extension **khác file** không đọc được ⇒ bỏ `private`.
- **Bài học**: `private` của Swift giới hạn **theo file** ⇒ `@State private` ở View mà extension nằm file khác là **lỗi access**; muốn dùng chéo file phải hạ xuống `internal`.
- Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--no-change-needed` 5 doc — sửa cơ học, mô tả vẫn đúng).

---

## [1.3.487] - 2026-10-02

### feat: tich hop Core ML bucket tinh vao engine VieNeu-TTS (Phase 3-5)

Phases 3–5 của plan `Docs/Plans/2026-10-02-plan-vieneu-coreml-phases-3-5.md` — nối 8 gói Core ML bucket tĩnh (đã publish sạch ở Phase 1–2, `raikiri1498/VieNeu-TTS-v3-Nano-CoreML`, 397,8 MB) vào app. Phase 0 (shape động) đã chốt **FAIL** ở `1.3.472–1.3.475` nên đây là đường duy nhất còn lại.

- **Thêm 11 file Swift** (`Sources/**/*.swift` **639 → 650**); `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--accept` **12** doc).
- **Phase 3 — tầng dữ liệu**: `VieNeuModelStore` thêm `coreMLURL`/`coreMLPackageNames`/`coreMLReady`/`coreMLTotalBytes` (**đệ quy** — `byteCount(of:)` dùng `fileSizeKey` không đệ quy nên không dùng được cho `.mlpackage`)/`deleteCoreML`, `url(for:)` thành **3 nhánh**; `VieNeuModelClient` thêm `coreMLSources`/`prefetchCoreML` + `expectedSha`/`expectedBytes` (bắt file cụt **và** sai sha — trước chỉ kiểm `size > 0`). `VieNeuCoreMLCompiler` (`MLModel.compileModel` → `.mlmodelc`, idempotent) · `VieNeuBucketSelector` (`frames` → bucket `{64,96,234}`).
- **Phase 4 — tầng engine**: protocol `VieNeuInferenceBackend` (khớp **7** thành viên `VieNeuONNXRuntime`) ⇒ `VieNeuCoreMLRuntime` (nạp N `MLModel`; **`ids`/`ctx_mask`→Int32**, `time` scalar; nạp/nhả theo bucket) và `VieNeuONNXRuntime` cùng thỏa; `VieNeuBackendFactory` trả `BackendChoice { primary, fallback: VieNeuONNXRuntime? }`; `VieNeuBackendSelfTest` + `VieNeuGoldenNPZ` (golden SNR ≥ 30 dB; đo 45–49,5 dB). `VieNeuTTSEngine`: `runtime` → `backend` + `fallbackRuntime`; `runChunk` bọc `try/catch` ⇒ **rớt riêng đoạn đó về ORT** (Q2). `makeNullBranch` chuyển ra `+Backend.swift` (file chính 400 → **357**, R6).
- **Phase 5 — nối dây + UI**: khoá `vieneuCoreML*` ở `VieNeuSynthesisPolicy` (mặc định **TẮT**); `VieNeuTTSService.useCoreML`/`enableCoreML()` (tách ra `+CoreML.swift`, file chính giữ **398**); `TTSManager.invalidateVieNeuBackend()`; màn mới `VieNeuModelManagerView` (+`+Sections`) chứa toggle + 8 gói + tự test; `VieNeuTTSTestView` bỏ phần model; Section 3 Cài đặt TTS thành **link** `Model VieNeu`. Gate `isReady` → `isReady || coreMLReady` ở **mọi** chỗ (R2).
- **Ba quyết định sản phẩm** (grill 2026-10-02): Core ML **tắt mặc định** · **rớt từng đoạn về ORT** · UI gom **màn riêng**.
- ⚠️ **Chưa đo trên máy thật** — hệ số ~1,4× là **suy luận** (R1/U1); điều kiện hoàn thành là ≥ 1,3× trên iPhone. **Không có Swift toolchain trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch.
- **Không đụng** `VieNeuONNXBridge.m/.h`, thuật toán tổng hợp (`steps`/`sway`/`cfg`/chunking), `@Model`/SwiftData.

---

## [1.3.486] - 2026-10-02

### feat: sinh 7 goi CoreML bucket tinh va publish len HuggingFace bang OIDC

Vòng sửa thứ ba của Phase 2 — **dọn rác trên repo HF vẫn chưa xong**. (Tiền lệ: [1.3.484] gói không được publish · [1.3.485] publish kèm ~1,6 GB rác.)

- **Lỗi ở lượt [1.3.485]**: bước "Dọn file trung gian trên HF" chạy `export HF_TOKEN=$(hf auth token)` rồi `HfApi.delete_files`. Dưới **Trusted Publishers OIDC không có credential lưu** ⇒ `hf auth token` trả **rỗng** ⇒ `HfApi(token="")` không xoá được (thiếu quyền) ⇒ bước **FAIL**, repo vẫn giữ **16 file `.onnx` trung gian (1582,9 MB)**. Đã xác minh bằng tree API lúc đó: 84 mục = 40 mlpackage/weight (8 gói đúng) + 16 `.onnx` rác + `manifest.json` + 3 `golden/*.npz`.
- **Sửa**: gộp việc dọn vào chính lệnh `hf upload` (cái đã chạy OIDC thành công ở bước publish) qua cờ **`--delete="mlpackage/*.onnx"`** — glob phẫu thuật, **chỉ xoá `.onnx` dưới `mlpackage/`**, GIỮ `README.md` / `manifest.json` / `golden`. Xoá hẳn bước Python dọn riêng (vốn lỗi vì không có token tĩnh). `hf upload` tự làm OIDC exchange nên không cần secret.
- **Gỡ job `dynamic` (Phase 0) khỏi workflow**: Phase 0 đã KẾT LUẬN FAIL (xem `Docs/Reports/research-2026-10-02-vieneu-coreml-shape-dong.md`) ⇒ chạy lại mỗi push chỉ tốn ~40 phút CI và kéo dài thời gian xác minh. Workflow giờ chỉ còn `convert` (baseline) + `bucket` (Phase 2). Cập nhật luôn header comment.
- **Bài học OIDC**: dưới Trusted Publishers, **không dùng `hf auth token`** để lấy token cho Python API — nó rỗng. Mọi thao tác cần auth (upload, xoá, list) phải qua `hf` CLI (tự exchange) hoặc truyền token OIDC trực tiếp. Đã ghi vào `01_project.md`.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Lượt này chỉ sửa `.github/workflows/convert-coreml.yml` + tài liệu.

---

## [1.3.485] - 2026-10-02

### feat: sinh 7 goi CoreML bucket tinh va publish len HuggingFace bang OIDC

Vòng sửa thứ hai của Phase 2. Lượt trước publish được gói, nhưng **đẩy theo cả file trung gian**.

- **Lỗi**: `.frozen.onnx` / `.opt.onnx` nằm cùng thư mục với `.mlpackage` ⇒ `hf upload` mang tất cả lên ⇒ repo HF phình **~400 MB → 1984,5 MB** (84 mục; mỗi `vector_estimator` có 155 MB trung gian × 2 × 3 mức = ~930 MB; `codec_decoder` ~596 MB). App chỉ cần `.mlpackage`. Đã xác minh bằng `GET /api/models/raikiri1498/VieNeu-TTS-v3-Nano-CoreML/tree/main?recursive=true`.
- **Sửa**: mọi file trung gian ghi ra `workdir` (**ngoài** `outdir`), chỉ `.mlpackage` nằm trong `outdir/mlpackage/`.
- **Thêm bước CI dọn phần đã lỡ có trên repo**: `hf auth token` (đổi OIDC) → `HfApi.delete_files` xoá mọi `mlpackage/*.onnx`. Không cần token tĩnh.
- ⚠️ **Bài học chung cho cả hai bẫy của Phase 2** (lượt đầu: gói không được publish; lượt hai: publish kèm ~1,6 GB rác): **phép kiểm của một bước publish phải là "nội dung thật sự ở đích có đúng không", không phải "lệnh có thoát 0 không"**. Cùng một loại lỗi với "phép kiểm rỗng nghĩa" ở Phase 0 — CI xanh mà không làm điều mình tưởng. Đã ghi vào `01_project.md`.
- **Điều đã chạy đúng từ lượt trước** (giữ nguyên): 8/8 gói convert bằng `onnx2coreml` (ứng viên `basic-folded`) · tổng **397,8 MB** (`vector_estimator` 78,1/78,1/78,5 · `codec_decoder` 49,7 ×3 · `text_encoder` 13,5 · `duration_predictor` 0,4) ⇒ **khớp mục tiêu 397 MB** · 3 golden (T64 728 KB · T96 961 KB · T234 1 968 KB) · Trusted Publishers OIDC chạy được, **không có secret nào**.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--accept 01_project.md`).
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.484] - 2026-10-02

### feat: sinh 7 goi CoreML bucket tinh va publish len HuggingFace bang OIDC

Vòng sửa sau lượt CI đầu của Phase 2 (`37016482886`). ⚠️ **Lượt đó xanh nhưng publish ra nội dung trống rỗng.**

- **Lỗi**: `convert_graph` ghi gói vào `workdir` (`coreml-bucket-work`), trong khi `hf upload` chỉ mang `outdir` (`coreml-bucket`) ⇒ repo HF nhận được **đúng 3,7 MB** (`manifest.json` + `summary.json` + 3 `golden/*.npz`) và **không có gói nào**. CI **vẫn xanh** — đúng loại lỗi "xanh mà không làm gì", cùng họ với phép kiểm rỗng nghĩa ở Phase 0. Đã xác minh bằng `GET /api/models/raikiri1498/VieNeu-TTS-v3-Nano-CoreML/tree/main?recursive=true` ⇒ 11 mục, 3,7 MB.
- **Sửa**: gói ghi vào **`outdir/mlpackage/`**. Thêm **hai lớp bắt** để không lặp lại: (a) script đếm số file `weight.bin`/`.mlmodel` **thật sự có mặt** trong `outdir` rồi mới cho `verdict = PASS`; (b) workflow `exit 1` nếu `find coreml-bucket -name 'weight.bin'` ra 0.
- **Sửa số lượng**: tôi đếm sai ở bản trước — `2 + 3 × 2 = **8 gói**`, không phải 7. Tổng dung lượng đo được **397,8 MB** (`vector_estimator` 78,1/78,1/78,5 · `codec_decoder` 49,7 ×3 · `text_encoder` 13,5 · `duration_predictor` 0,4) ⇒ **khớp mục tiêu 397 MB** của plan.
- **Điều đã chạy đúng ở lượt đầu** (giữ nguyên): 8/8 gói convert được bằng đường `onnx2coreml` (`freeze_shapes` → `optimize_with_ort` **BASIC** → `fold_range`, thử nhiều ứng viên; tất cả convert bằng ứng viên `basic-folded`). 3 golden sinh đủ: `T64` 728 KB · `T96` 961 KB · `T234` 1 968 KB.
- **Publish bằng Trusted Publishers (OIDC)** chạy thành công ở lượt đầu — `permissions: id-token: write` + `HF_OIDC_RESOURCE`, **không có secret nào**. Lượt này chỉ sửa chỗ ghi file để gói đi cùng.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--accept 01_project.md`).
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.483] - 2026-10-02

### feat: sinh 7 goi CoreML bucket tinh va publish len HuggingFace bang OIDC

Phase 2 của plan `Docs/Plans/2026-10-02-plan-vieneu-coreml-bucket-tinh.md`. **Không đụng `Sources/`.**

- **`Scripts/coreml_bucket_package.py` (mới, 274 dòng)**: sinh **7 gói** theo lưới đã chốt ở Phase 1 — `text_encoder` + `duration_predictor` mỗi cái **1 gói** (chiều động duy nhất của chúng là `L`, đã đóng băng ở 200); `vector_estimator` + `codec_decoder` **× 3 mức `T ∈ {64, 96, 234}`**. Dùng đúng đường `onnx2coreml` đã chứng minh: `freeze_shapes` → `optimize_with_ort` (**BASIC**, không ALL) → `fold_range`, thử **nhiều ứng viên** để một bản tối ưu hỏng không làm mất bản gốc. **`T = 128` không sinh** — Phase 1 đo được: thêm 127,8 MB mà tỉ lệ **không đổi**.
- **`manifest.json`**: sha256 + size từng file. Cần vì `VieNeuModelClient.download(_:)` hiện **chỉ** kiểm `size > 0` ⇒ **không bắt được file cụt**. App sẽ kiểm `expectedBytes` ở Phase 3.
- **`golden/T{n}.npz` + `.json`** cho từng mức: đầu vào cố định (`ids`/`style`/`spk`/`latent`/`time`) + đầu ra tham chiếu ORT fp32 (`ctx`/`log_s`/`velocity`/`pcm`). Chạm đủ 4 graph đã chuyển, tất định, bắt đúng 3 kiểu hỏng đã gặp: **im lặng · NaN · nhiễu**. Không kiểm được: bộ phonemizer (`sea_g2p.bin`, không đổi) và chất lượng tiếng Việt — phải nghe trên máy.
- **Publish bằng Trusted Publishers (OIDC)**: job `bucket` có `permissions: id-token: write` + `contents: read`, `HF_OIDC_RESOURCE=raikiri1498/VieNeu-TTS-v3-Nano-CoreML`, `hf upload …`. **Không có secret nào.** Publish **chỉ khi sinh đủ 7 gói** — bộ thiếu gói còn tệ hơn không phát hành, vì app sẽ tải về rồi mới phát hiện thiếu.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--accept 01_project.md`).
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.482] - 2026-10-02

### docs: R1 da giai quyet - gia tri huong A ha xuong ~1,5x

Chỉ tài liệu — lượt này **không** đổi mã, chốt R1 sau lượt quét `L` (`37014485074`). Không lượt CI nào chạy.

- **Quét `L` cho kết quả quyết định**: `vector_estimator` và `codec_decoder` **gần như KHÔNG phụ thuộc `L`** (`T=96`: `L=32` → 111,3 ms · `L=91` → 123,6 · `L=128` → 121,4 · `L=200` → 101,8 · `L=256` → 109,1 — không xu hướng, chỉ nhiễu ±15 %). Chỉ `text_encoder` tăng theo `L` (9,1 → 113,2 ms) nhưng chiếm **~1,4 %** thời gian.
- ⇒ **Nhiễu `L` không đáng kể** ⇒ hệ số máy-thật/CI đo được (**1,05×**) **đứng vững**, và **giả định 1,28× bị bác bỏ bằng đo**. Hợp lý: runner CI chỉ có **3 core** nên 4 luồng không nhanh hơn 2 luồng trên iPhone (6 core) là bao.
- ⭐ **Giá trị hướng A hạ xuống ~1,5×** cho lưới `{64,96,234}` (397 MB) — **không phải 1,86×** như báo cáo trước đó (1,86× dựa trên giả định 1,28× nay đã bị bác bỏ).
- ⚠️ **Nhiễu giữa các lượt chạy ~±20 %**: cùng một cấu hình, hai giai đoạn trong **cùng một lượt** đã lệch 20 % (`bucket_fallback` T96 `vector_estimator` 123,6 ms vs `ort_l_sweep` T96/L200 101,8 ms) ⇒ **đừng tin chữ số thứ hai** của bất kỳ số timing nào từ runner.
- ⚠️ **ANE trên runner là giả lập** (`Apple M1 (Virtual)`) ⇒ ANE thật của iPhone **có thể tốt hơn** ⇒ 1,5× là ước lượng **thiên thấp**, không phải trần.
- **Cách chốt con số**: so `rtf` trước/sau khi bật Core ML, với **mốc nền đo hôm nay = `rtf` trung vị 0,420** (p10 0,380 · p90 0,480) — phép so sạch nhất, không cần giả định.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.

---

## [1.3.481] - 2026-10-02

### chore: them quet L cho ORT (D7) de go nhieu khi so rtf may that voi so CI

Bước 1 của hướng A. **Không đụng `Sources/`.**

- **Vì sao cần**: phép so `rtf` đo trên iPhone (`[VieNeuPerf]`) với thời gian CI dự đoán bị lệch **một chiều** — CI đo ORT ở `L = 200` **đóng băng** (vì bucket đóng băng shape), còn máy chạy `L` **thật** (trung vị ~91 đo từ `[VieNeuChunk]`). Máy làm **ít việc hơn** nên đáng lẽ phải nhanh hơn; đo ra máy *chậm* hơn thì **không tách được** "máy chậm hơn CI" khỏi "máy làm ít việc hơn".
- **Số đã đo trước đó**: `rtf` máy thật trung vị **0,420** (p10 0,380 · p90 0,480); tỉ lệ máy/CI = **1,05×** (p25 0,96× · p75 1,11×) — **không phải 1,28×** như tài liệu gợi ý. Nhưng vì nhiễu `L` nên chưa chốt được; hướng A nằm trong khoảng **1,53× … 1,86×**.
- **Thêm `stage_ort_l_sweep` (D7)** vào `Scripts/coreml_dynamic_experiment.py` (806 → 939 dòng): đo ORT theo `L ∈ {32, 64, 91, 128, 160, 200, 256}` ở `T ∈ {64, 96, 234}` cho `vector_estimator` · `text_encoder` · `codec_decoder`, ghi `ort_l_sweep.json`. `91` là trung vị `L` thật; `200` là mốc CI đang dùng cho bucket ⇒ hiệu hai mốc chính là **hệ số bù** cần tìm.
- ⚠️ **Bài học: máy phát triển Windows KHÔNG đo được thời gian.** Thử đúng phép đo này tại chỗ ra số **không đơn điệu** (`L=91` → 371 ms nhưng `L=128` → 108 ms, `L=160` → 238 ms) — sandbox + tải nền. **Mọi số timing phải lấy từ runner CI**; đừng lặp lại việc đo timing trên Windows.
- **`.github/workflows/convert-coreml.yml`** (141 → 148 dòng): bước `Verdict` in thêm bảng quét `L`.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%** (`--accept 01_project.md`).
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.480] - 2026-10-02

### docs: chot luoi bucket 64/96/234 (397 MB, 1,86x) cho huong A

Chỉ tài liệu — lượt này **không** đổi mã, chốt tham số cuối của hướng A sau lượt đo `37010522273`. Không lượt CI nào chạy.

- **Số đo 5 mức bucket** (`L=200`, `ComputeUnit.ALL`, `vector_estimator` / `codec_decoder`): `t32` **1,82×** / 1,48× · `t64` **2,12×** / 1,22× · `t96` **2,12×** / 0,91× · `t128` 2,07× / 1,16× · `t234` 2,22× / 1,00×.
- **Tỉ lệ bình quân có trọng số** trên phân bố `T` thật (608 lượt), so ORT **2 luồng**:
  `96` = 142 MB / 1,55× · `64/96` = 270 MB / 1,86× · **`64/96/234` = 397 MB / 1,86×** · `32/64/96` = 397 MB / 1,93× · `32/64/96/234` = 525 MB / 1,93×.
- ⭐ **Chốt lưới `{64, 96, 234}` — 397 MB, 1,86×, CPU_ONLY 1,78×.** Cùng dung lượng như phương án `{32,64,96}` nhưng **an toàn tuyệt đối** vì `t234` là **trần cấu trúc** (`maxChunkSeconds = 15,0` ⇒ `T ≤ 234` bằng thiết kế) ⇒ **không cần** guard chia đoạn, **không đụng** logic chunking. So với phương án 525 MB thì **tiết kiệm 128 MB** chỉ đổi lấy 0,07× (4 %). **`t128` vô dụng**: thêm 127,8 MB mà tỉ lệ **không đổi**.
- **Loại bỏ guard `limit`**: muốn chắc chắn `T ≤ 96` thì `limit ≈ 53` ký tự (vì `speech/char` max = 0,115) ⇒ **+59 % số chunk** — câu bị vụn.
- ⚠️ **Dao động giữa các lượt chạy**: cùng bucket `t64`, lượt trước đo `vector_estimator` **1,47×**, lượt này **2,12×**. Runner `Apple M1 (Virtual)` 3 core dùng chung ⇒ chênh dưới ~20 % không đọc là thật. Vì vậy **R1 (đo trên iPhone thật)** vẫn là việc bắt buộc trước khi tin con số nào.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.

---

## [1.3.479] - 2026-10-02

### chore: Phase 1 huong A - do them bucket t32/t96/t128 cho luoi CoreML

Phase 1 của plan `Docs/Plans/2026-10-02-plan-vieneu-coreml-bucket-tinh.md` (hướng A — bucket tĩnh). **Không đụng `Sources/`.**

- **Trả lời được hai câu hỏi của Phase 1 ngay trên Windows, không tốn lượt CI nào** — bằng cách khai thác log có sẵn `Docs/Reports/2026-09-30-log-vieneu-25phut.txt`:
  - **`L` (số phoneme id)**: lọc ký tự của `[VieNeuChunk] phonemes=«…»` theo `config.json → vocab` (81 mục), 609 chunk ⇒ **p50 91 · p90 129 · p99 143 · max 150**. `L_max = 160` phủ **100 %** ⇒ **giữ `L = 200`**, lo ngại "`L=200` sát trần" ở bản plan đầu là **sai**; bỏ được một vòng đo lại bucket ở `L=256`.
  - **Guard `T > 96` không khả thi**: quét `limit` cho thấy `limit=90` ⇒ **+16 %** số chunk mà vẫn còn 1 chunk vượt; muốn **chắc chắn** không vượt thì `limit ≈ 53` (vì `speech/char` max = 0,115) ⇒ **+59 %** số chunk — câu bị vụn vì quá nhiều ranh giới. ⇒ **Loại bỏ guard**.
- **⭐ Sự kiện làm đổi quyết định của plan**: `VieNeuConfig.maxChunkSeconds = 15,0` (`VieNeuConfig.swift:61`) chặn `T ≤ round(15 × 15,625) = 234` **bằng thiết kế** (`VieNeuTTSEngine.swift:336-337`) ⇒ **chỉ bucket `t234` mới bảo đảm không bao giờ tràn**. Lưới `{32,64,96}` dù có guard vẫn có thể tràn (90 ký tự × 0,115 = 10,35 s → `T = 162`). ⇒ Con số **397 MB** của bản plan đầu **không đạt được** nếu không thêm một trong hai thứ; plan đã cập nhật thành hai thiết kế **D1** (`{32,64,96,234}`, **525 MB**, không đụng logic chia đoạn) và **D2** (`{32,64,96}`, **397 MB**, cần đường xử lý tràn). Đề xuất **D1**. **Chờ người dùng chốt.**
- **Đo thêm bucket**: `FALLBACK_BUCKETS` từ 3 mức (`t64/t128/t234`) → **5 mức `t32/t64/t96/t128/t234`** — `t32` và `t96` **chưa từng có số**, mà lưới đề xuất cần cả hai; `t128` để so. `L` vẫn 200 (đã chứng minh đủ).
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.478] - 2026-10-02

### docs: ghi so do cuoi cua Phase 0 CoreML (FAIL) vao CHANGELOG

Chỉ tài liệu — lượt này **không** đổi mã, chỉ chốt lại bằng chứng cuối của Phase 0 vào nhật ký. Không lượt CI nào chạy (không đụng `Sources/**`, `project.yml`, `Scripts/*.py` hay file workflow).

- **Xác nhận độc lập thứ hai cho `FAIL`** (lượt CI #6, `36999867586`): sau khi sửa bẫy dtype của `ids`, `golden` chạy được tới tận runtime và Core ML trả về nguyên văn `NSLocalizedDescription = "Error in dynamically resizing for sequence length (error: -7)."` ⇒ Core ML **từ chối đổi chiều dài chuỗi** dù gói đã khai `RangeDim`. Một bằng chứng từ phép thử `trace_shapes`, một từ runtime thật — hai đường đo độc lập, cùng kết luận.
- **Và ngay ở shape chạy được, gói torch vẫn chậm hơn gói tĩnh** (`L=160, T=96`): `text_encoder` **0,70×** (chậm hơn) · `vector_estimator` **1,68×** (baseline tĩnh: **2,12×**) · `codec_decoder` **0,53×** (chậm gấp ~2; baseline tĩnh: **1,28×**). Ước lượng một chunk: ORT 2977 ms → Core ML 2075 ms = **1,44×**, so với **1,98×** của đường tĩnh.
- ⇒ Đường torch hỏng vì **hai** lý do độc lập: (1) **không shape động**; (2) **chất lượng gói kém hơn**. Điều này làm hướng "viết lại converter `Reshape` của `onnx2torch`" **khó hơn** so với lúc viết plan: sửa được shape động vẫn còn phải sửa cả chất lượng gói.
- **Báo cáo đầy đủ**: `Docs/Reports/research-2026-10-02-vieneu-coreml-shape-dong.md` (gitignored).
- **Trạng thái**: Phase 0 đã đóng với `FAIL`; theo quyết định #6 của plan, **dừng và chờ quyết định** giữa ba hướng (bucket 384–512 MB · viết lại converter onnx2torch · bỏ Core ML).

---

## [1.3.477] - 2026-10-02

### fix: sua golden stage CoreML dung bien the dtype (ids int32)

Vòng dọn cuối của Phase 0 (đã chốt `FAIL` ở 1.3.475). `golden` vẫn chưa sinh được, nhưng vì lý do khác.

- **Lượt CI #5 (`36999267717`) xác nhận thêm hai điều**: `verdict = FAIL` (lần thứ hai, độc lập) và **D2b `surgery_parity` toàn bộ `max_abs_delta = 0`** ⇒ phẫu thuật `Range` **bit-exact** trên runner macOS, không chỉ trên máy Windows. Nhưng `golden` báo `RuntimeError: value type not convertible`.
- **Nguyên nhân**: Core ML khai `ids` là **INT32** còn ONNX khai **int64** ⇒ cùng họ với bẫy `ctx_mask` (ONNX bool, Core ML FLOAT32) đã gặp ở lượt baseline. Thông báo `value type not convertible` **không nói input nào**, nên cách duy nhất là thử biến thể.
- **Sửa**: đổi `predict_with_mask_variants` → `predict_with_dtype_variants`, mở rộng để thử cả `ids-int32` (và tổ hợp `ids-int32+mask-int32`), rồi dùng nó cho **cả 4** graph trong `stage_golden` — trước đó chỉ `duration_predictor`/`vector_estimator` dùng, còn `text_encoder`/`codec_decoder` gọi `predict` trần nên không được bảo vệ.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.476] - 2026-10-02

### chore: sua golden stage CoreML + bo .github/workflows/** khoi paths cua build-ipa

Vòng dọn sau khi Phase 0 đã chốt `FAIL` (1.3.475). Hai việc độc lập, gộp một lượt.

- **Sửa `stage_golden`** — hỏng do chính bản vá `_fit_ids` ở 1.3.474: `stage_golden` gọi `make_feeds(model_dir, workdir, 0, 0)` chỉ để lấy `config`, mà `_fit_ids` cắt `ids` về `length = 0` ⇒ `text_encoder` chết với `Invalid input shape: {0}` ⇒ golden không sinh được ở lượt CI #4. Nay lấy `config = load_config(model_dir)` trực tiếp và `length = real_ids(config).shape[1]`. Đây là bài học nhỏ nhưng đúng loại lỗi đã gặp: **một hàm tiện ích đổi ngữ nghĩa (`length` giờ có tác dụng) làm hỏng một caller cũ dùng `length` như tham số giả**.
- **`.github/workflows/build-ipa.yml`: bỏ `.github/workflows/**` khỏi `paths`** (cả `push` lẫn `pull_request`) — người dùng chốt. Trước đó, sửa **bất kỳ** file workflow nào (kể cả `convert-coreml.yml` không liên quan gì tới build IPA) cũng kéo theo một lượt build IPA đầy đủ: đo được ở 1.3.472 (push `96052673`) và 1.3.474 (push `278122f5`) — cả hai đều sinh `Build Unsigned IPA`. Từ nay sửa `convert-coreml.yml` chỉ chạy job CoreML.
- **`01_project.md` cập nhật theo**: hai chỗ ghi *"`build-ipa.yml` có `paths: '.github/workflows/**'` nên push file này cũng kích hoạt build IPA"* nay đã hết hiệu lực, sửa thành ghi chú lịch sử có mốc ngày. Ghi rõ thêm: `01_project.md` vẫn khai `.github/workflows/*.yml` trong `sourcePatterns`, nên thay đổi file workflow **vẫn** làm doc này stale — đó là chủ ý của validator, không phải hệ quả của `build-ipa.yml`.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.475] - 2026-10-02

### chore: them Phase 0 tham do shape dong cho mlpackage CoreML (khong dung Sources/)

Vòng sửa thứ ba, và là vòng **chốt kết luận**. Lượt CI #3 (`36998092891`) báo `verdict: PASS` — nhưng **sai**, vì tiêu chí của script còn lỏng.

- **Siết `verdict`**: "convert được" **không đủ**. `ct.convert` vẫn dựng ra `.mlpackage` có `RangeDim` từ một graph đã bị `torch.jit.trace` nướng shape — gói đó **compile được** nhưng cho kết quả **sai/im lặng** ở shape khác, đúng loại lỗi tệ nhất trong engine này. Nay điều kiện bắt buộc là graph **đã trace** phải chạy lại đúng ở **cả 3** shape (`trace_shapes` toàn `ok`), cộng thêm `verdict_reason` và `package_bytes` vào `summary.json`.
- **⭐ KẾT LUẬN PHASE 0: `FAIL`.** Bốn `.mlpackage` **có** được sinh ra, tổng **142,0 MB** — khớp gần đúng ước tính ~141,6 MB của plan ⇒ **phần dung lượng của plan đúng**. Nhưng `trace_ok` = **1/3** cho `text_encoder`, `vector_estimator`, `codec_decoder` (chỉ `duration_predictor` được 3/3, và nó chiếm ~0 % thời gian): graph đã trace **chỉ đúng ở đúng shape đã trace**, nên **không có gói shape động nào dùng được**.
- **Nguyên nhân gốc (đã truy tới dòng)**: `onnx2torch/node_converters/reshape.py:23` dùng `torch.reshape(input_tensor, torch.Size(shape))`. `torch.Size` **không trace được** nên torch.jit tính ngay lúc trace rồi **nướng shape thành hằng**. Vá một dòng **không cứu được**: `torch.reshape(x, tensor_shape)` → `TypeError: argument 'shape' must be tuple of ints, not Tensor`; `shape.tolist()` vẫn hỏng vì còn op khác cũng bị nướng. Đường torch chỉ sống nếu **viết lại converter `Reshape` của `onnx2torch`** — một dự án riêng, không phải một bước trong plan này.
- **Hai chặn độc lập của `onnx2coreml`, đo chứ không đọc tài liệu**: (a) `Range` không có lowering (1 node ở `text_encoder`, 6 node ở `vector_estimator`); (b) `input has a dynamic or unknown dimension; fixed input shapes are required in this version`.
- **Số liệu phương án bucket dự phòng (đã đo ở lượt CI #1, vẫn đúng)**: 3 mức × 2 graph = **384,0 MB**; tại bucket `t234`: `vector_estimator` **2,87×** (383,3 → 133,6 ms, SNR 45,4 dB), `codec_decoder` **1,23×** (916,1 → 746,3 ms, SNR 49,3 dB).
- **Theo đúng quyết định #6 của plan, dừng ở đây**: báo cáo số đo, **không** tự chuyển sang bucket. Chi tiết ở `Docs/Reports/research-2026-10-02-vieneu-coreml-shape-dong.md`.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.474] - 2026-10-02

### chore: them Phase 0 tham do shape dong cho mlpackage CoreML (khong dung Sources/)

Vòng sửa thứ hai. Lượt CI #2 (`36997384879`) **xanh** và cho ra bảng chẩn đoán đầy đủ — nhưng trong đó có **hai lỗi nữa của script**, và một trong hai làm phép kiểm trung tâm **rỗng nghĩa**.

- **`dynamic_spec` sai số chiều**: `x` của `vector_estimator`/`codec_decoder` là `[1, latent_channels, T]` — **3 chiều**, `T` ở chiều thứ ba. Bản cũ trả về **một** `RangeDim` trần làm *cả* shape ⇒ `ValueError: Shape should be list or tuple, got type RangeDim` cho cả hai graph. Nay `T` nằm trong danh sách: `ct.Shape([1, channels, RangeDim])`. Cũng bỏ lớp bọc `ct.Shape` thừa quanh `EnumeratedShapes`.
- **`make_feeds` làm phép kiểm `text_encoder` rỗng nghĩa**: `ids` dùng `real_ids(config)` nguyên trạng (~140 phần tử) **bất kể** `length`, nên `text_encoder` nhận **cùng một** shape ở cả 3 "shape" đại diện ⇒ `trace_shapes` "đạt" mà **không chứng minh gì**. Thêm `_fit_ids()` cắt/đệm về đúng `length`. Đây là loại lỗi nguy hiểm nhất — xanh vì phép kiểm không đo gì.
- **Siết tiêu chí kết luận**: `verdict` giờ **chỉ tính đường shape động** (`torch_surgery`/`torch_enum_T`). `o2c_original`/`o2c_surgery` chạy được cũng **không** tính, vì chúng chỉ sống khi shape đã đóng băng — mà shape động chính là thứ plan cần. Thêm `trace_ok` (số shape chạy lại được / 3) vào `summary.json` và vào bước `Verdict` của workflow.
- **Xác nhận lại kết luận của 1.3.473, lần này bằng phép đo trung thực**: `torch.jit.trace` **nướng shape** vào graph. Đo cục bộ (torch **2.14.1**, đúng bản CI dùng) trên graph đã phẫu thuật + đã vá `Clip`: trace ở `(L=160,T=96)` xong chạy lại ở `(64,32)`, `(200,234)`, `(300,96)` đều `RuntimeError` — với cả `text_encoder` lẫn `vector_estimator`. Gốc: `onnx2torch/node_converters/reshape.py:23` dùng `torch.reshape(input_tensor, torch.Size(shape))`, mà `torch.Size` **không trace được** nên torch.jit tính ngay lúc trace rồi nướng kết quả thành hằng.
  ⚠️ Lượt CI #2 báo `text_encoder [torch_surgery]: OK` **kèm** `trace@small/typical/max: chạy lại OK` — đó là **ảo giác của phép kiểm rỗng nghĩa**, không phải bằng chứng trace giữ được chiều động. Ghi lại để lần sau không đọc nhầm nó thành "đã chạy được".
- **Bảng chẩn đoán lượt CI #2 (giữ nguyên, vẫn đúng)**: `o2c_original` — `text_encoder`/`vector_estimator` chặn bởi `Range` (1 và 6 node), `duration_predictor`/`codec_decoder` chặn bởi `input has a dynamic or unknown dimension` ⇒ `onnx2coreml` **đòi shape tĩnh**, đo chứ không chỉ đọc tài liệu. `o2c_surgery` — gỡ `Range` rồi vẫn chặn vì chiều động. `torch_original` — `text_encoder`/`vector_estimator` chặn bởi `Clip` bỏ trống `max`. `duration_predictor` — đường torch chạy được và **giữ được chiều động** (đầu ra là scalar nên không có op phụ thuộc shape).
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.473] - 2026-10-02

### chore: them Phase 0 tham do shape dong cho mlpackage CoreML (khong dung Sources/)

Vòng sửa sau lượt CI đầu. Job `dynamic` **xanh nhưng `verdict = FAIL`**, và bảng kết quả có 3/4 đường hỏng vì **bug của chính script** ⇒ không dùng để ra quyết định được. Vòng này sửa bug và **đổi thiết kế bảng đường** để lần chạy sau cho ra **bảng chẩn đoán** thay vì danh sách "hỏng/hỏng/hỏng".

- **Sửa bug truyền nhầm thư mục**: `route_torch` gọi `make_feeds(os.path.dirname(source), os.path.dirname(source), …)` ⇒ tìm `voices_v3_nano.json`/`config.json` trong thư mục model thay vì workdir ⇒ `FileNotFoundError` cho **mọi** graph, nên `torch_surgery`/`torch_enum_T` **chưa từng thực sự chạy**. Nay truyền `context = {config, model_dir, workdir}`.
- **Sửa `bench_graph` cho gói đã đóng băng**: hàm luôn đo bằng 3 shape đại diện, mà model tĩnh chỉ chạy ở **đúng** shape đã chốt ⇒ bucket `t64`/`t128` báo `mọi cách ép kiểu đều lỗi` (trông như Core ML hỏng, thật ra là đo sai shape). Nay nhận tham số `shapes`; bucket đo bằng chính shape của nó.
- **`normalize_clip` (mới, trong `coreml_shape_surgery.py`)**: cấp `max = +inf` tường minh cho `Clip` đang bỏ trống input thứ ba. Ba node `Clip` của bộ model đều ở dạng `[data, min, '']`, mà `onnx2torch/node_converters/clip.py:60` gọi `get_const_value('')` → `KeyError` → `NotImplementedError` ⇒ `text_encoder`/`vector_estimator` chết **trước cả** bước Core ML. Tương đương ngữ nghĩa (`min(x, +inf)` = `x`). Đã kiểm cục bộ: vá xong `onnx2torch.convert` **nhận cả 4 graph**.
- **Đổi 4 đường cũ thành 5 đường, mỗi đường trả lời một câu hỏi**: `o2c_original` (op nào chặn `onnx2coreml`) · `o2c_surgery` (gỡ op rồi còn chặn vì gì) · `torch_original` (op nào chặn `onnx2torch`) · `torch_surgery` (trace có giữ chiều động) · `torch_enum_T`.
- **Thêm `trace_shapes`**: chạy lại graph **đã trace** ở 3 shape khác. Đây là phép kiểm quyết định — `torch.jit.trace` **nướng shape** vào graph.
- **Lặp tại chỗ bằng `torch` + `onnx2torch`** (không cần `coremltools`, nên làm được trên Windows): `torch.jit.trace` ở `(L=160,T=96)` xong chạy lại ở `(64,32)`/`(200,234)` đều `RuntimeError` (trừ `duration_predictor`). Gốc: `onnx2torch/node_converters/reshape.py:23` dùng `torch.reshape(input, torch.Size(shape))` — `torch.Size` **không trace được** nên torch.jit tính ngay lúc trace rồi nướng thành hằng. Vá một dòng **không cứu được**: `torch.reshape(x, tensor_shape)` → `TypeError: argument 'shape' must be tuple of ints, not Tensor`; `shape.tolist()` vẫn hỏng vì còn op khác cũng bị nướng.
- **Số liệu bucket dự phòng lượt trước (giữ nguyên, vẫn đúng)**: 3 mức × 2 graph = **384,0 MB**; tại bucket `t234`: `vector_estimator` **2,87×** (383,3 → 133,6 ms, SNR 45,4 dB), `codec_decoder` **1,23×** (916,1 → 746,3 ms, SNR 49,3 dB).
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** ⇒ không khẳng định đã kiểm chứng biên dịch; lượt này không đổi mã Swift.

---

## [1.3.472] - 2026-10-02

### chore: them Phase 0 tham do shape dong cho mlpackage CoreML (khong dung Sources/)

Cổng của plan `Docs/Plans/2026-10-02-plan-vieneu-coreml-engine-trong-app.md`: **chỉ khi Phase 0 đạt mới làm engine Core ML trong app**; không đạt thì dừng và báo cáo số đo, không tự chuyển sang phương án bucket.

- **Vì sao phải là shape động**: trọng số chiếm gần hết gói, **không** phải activation — `vector_estimator` fp16 nặng **78,1 MB ở `L=160,T=96`** và **78,5 MB ở `L=200,T=234`**. Nghĩa là bucket hoá tốn **127,8 MB cho MỖI mức** (4 mức = 512 MB, gấp rưỡi 347 MB hiện tại). Một gói shape động phủ mọi câu: tổng ~141,6 MB.
- **`Scripts/coreml_shape_surgery.py` (mới, 333 dòng)** — `investigate()` truy vết từng node `Range` ngược lên `Shape(...)` để trả lời nó **phụ thuộc chiều nào** (`x`/`ctx`/`ctx_mask`, dim nào) kèm hệ số nhân/cộng và `MAX` cần bao nhiêu; không truy được thì ghi `UNKNOWN`, **không đoán**. `apply()` thay `Range(start, limit, delta)` bằng `Slice(arange(0, MAX), starts=[start], ends=[limit], axes=[0], steps=[delta])` — tương đương ngữ nghĩa nhưng **giữ nguyên chiều động** vì `limit` vẫn là tensor suy từ `Shape`. **Raise** nếu có `Range` không truy vết được: `MAX` quá nhỏ làm `Slice` **cắt cụt im lặng** (không exception) — đúng loại lỗi tệ nhất trong engine này.
- **`Scripts/coreml_dynamic_experiment.py` (mới, 743 dòng, 7 giai đoạn D0–D6 + D2b)** — thử **4 đường** cho **cả 4 graph**: `o2c_dynamic` (kiểm chứng lại tài liệu *"Fixed input shapes"* của `onnx2coreml` bằng đo chứ không bằng niềm tin) · `torch_dynamic` (`onnx2torch` → `ct.convert` + `RangeDim` cho `L` và `T`) · `torch_surgery` (trên graph đã phẫu thuật) · `torch_enum_T` (`EnumeratedShapes` cho `T` = 32/64/96/160/234 + `RangeDim` cho `L`, vì ANE thường cần shape tĩnh). Mỗi đường bọc `try/except`, ghi **nguyên văn** thông báo lỗi — "lỗi ở đâu, vì sao" cũng là kết quả.
- **D2b — chứng minh phẫu thuật KHÔNG đổi số**: ORT chạy graph gốc vs graph đã phẫu thuật ở 3 shape. Kỳ vọng **bit-exact**; khác `0` nghĩa là phẫu thuật sai chứ không phải sai số dấu chấm động. Phép kiểm này **tách hẳn** "phẫu thuật `Range` sai" khỏi "convert sai" — không có nó thì hai loại lỗi trông giống hệt nhau và ta sẽ đi sửa nhầm chỗ.
- **Đã kiểm chứng cục bộ trên Windows trước khi tốn lượt CI** (`onnx 1.23.1` + `onnxruntime 1.30.0` trong venv cách ly): chỉ **2/4 graph có `Range`** — `text_encoder` 1 node (`/text/Range`, phụ thuộc `L`) và `vector_estimator` 6 node (5 node phụ thuộc **`T`**, 1 node phụ thuộc `ctx[1]` = `L`); `duration_predictor` và `codec_decoder` **không có node nào**. Cả 7 node truy vết được và phẫu thuật sạch, `max|Δ| = 0.000e+00` ở **cả 6 điểm thử** — kể cả shape chưa từng dùng khi phẫu thuật (`L=300`, `T=234`) ⇒ phép thay thế giữ đúng tính shape động.
- **Đo ở 3 shape** (`L=64/T=32` · `L=160/T=96` · `L=200/T=234`): parity SNR so với ORT fp32 · độ trễ · **thời gian `MLModel(...)` biên dịch** (chi phí một lần mà người dùng phải chờ trên máy thật) — cho cả `ComputeUnit.ALL` và `CPU_ONLY`.
- **`golden.npz` thay cho WAV** (đổi so với bản plan đầu): để có WAV phải dựng lại **cả** vòng Euler **và** bộ phonemizer trong Python, mà hai thứ đó **không hề đổi** ở lượt này. Golden = đầu vào cố định (`ids` thật từ `app_logs (60).txt` + preset giọng thật + `latent` theo seed + `t=0,5`) cộng đầu ra tham chiếu của **cả 4 graph** ⇒ chạm đủ 4 graph đã chuyển, tất định, và bắt đúng 3 kiểu hỏng đã gặp (im lặng · NaN · nhiễu), ~0,8 MB. Không kiểm được: bộ phonemizer (`sea_g2p.bin`, không đổi) và chất lượng tiếng Việt (phải nghe trên máy thật).
- **`bucket_fallback.json`** — dù shape động đạt hay không, script **vẫn** đo phương án bucket (3 mức `T` × 2 graph nặng): dung lượng thật từng mức + độ trễ từng mức. Không có nó thì nếu Phase 0 thất bại, quyết định tiếp theo sẽ phải dựa trên cảm giác.
- **Job `dynamic` mới trong `.github/workflows/convert-coreml.yml`** (141 dòng), cố ý **không** đụng job `convert` baseline — job cũ giữ nguyên làm mốc so sánh. Cài thêm `torch` + `onnx2torch` (~200 MB). **Cố ý không upload `.mlpackage`**: 4 graph × 4 đường ≈ 1,2 GB, mà Phase 1 sẽ chạy lại conversion (~7 s/graph) nên gói cũ chỉ là rác; artifact chỉ giữ JSON báo cáo + `golden.npz`.
- **Publish lên HuggingFace chốt bằng Trusted Publishers (OIDC)** — **không** token tĩnh, **không** secret. Claim khớp **chính xác** (không regex): `repository equals buudvh/FreeBook` + `workflow_ref starts with buudvh/FreeBook/.github/workflows/convert-coreml.yml@`. Token sinh ra chỉ ghi được **một** repo và sống **60 phút**.
- **Không đụng `Sources/`** — `Sources/**/*.swift` vẫn 639 file. Cổng: `check_architecture.py` **5 violation nền, 0 mới**; `validate_links.py` **PASS 100%**.
- **Chưa build được trên Windows** (không có Swift toolchain) ⇒ không có khẳng định "đã kiểm chứng biên dịch"; lượt này cũng không đổi mã Swift nên không cần.

---

## [1.3.471] - 2026-10-02

### chore: them workflow thi nghiem convert ONNX sang mlpackage (CoreML) tren runner macOS

Thí nghiệm **một lần**, không đụng `Sources/`. Mục tiêu: trả lời 3 câu cho nhánh CoreML bằng số đo trên runner macOS (Apple Silicon, **có ANE**).

- **`onnx2coreml` convert được không** — `analyze` cả 4 graph, ghi op thiếu vào `reports/analysis.json`.
- **fp16 thật có giữ được số không** — so đầu ra Core ML (fp16) với ORT **fp32** trên cùng input thật (phoneme chép từ log + preset giọng thật) ⇒ SNR, thay cho proxy 25,6 dB đã đo trên PC.
- **Core ML có nhanh hơn ORT CPU không** — đo `ms/lượt` của `vector_estimator` trên **cùng một máy**, với `ComputeUnit` = ALL / CPU_AND_NE / CPU_ONLY.
- Shape phải **cố định** (giới hạn của `onnx2coreml`) ⇒ `freeze_shapes` chốt `dim_value` + xoá `value_info` + `infer_shapes`; 2 bucket: `L=160,T=96` (điển hình) và `L=200,T=234` (trần 15 s).
- **Đã kiểm chứng cục bộ phần không cần coremltools**: `freeze_shapes` cho model nạp được trong ORT với shape tĩnh đúng thiết kế và `Run` trả `[1,144,96]`.
- Tiêu chí chốt trước: convert được **và** SNR ≥ 20 dB **và** Core ML nhanh hơn ORT ≥ 1,3× ⇒ mới bàn tới việc viết engine mới trong app. Trượt cổng nào thì ghi vào báo cáo nghiên cứu và **dừng nhánh CoreML**.

---

## [1.3.470] - 2026-10-02

### revert: dua toan bo phan VieNeu ve dung moc truoc khi them CoreML EP

Người dùng: *"sao bạn không revert code mà về trước khi thêm coreml"* → sau khi hỏi lại: *"bây giờ còn dùng cầu nối log làm gì không"*.

- **Revert toàn bộ `Sources/` về `ee3d24f` (1.3.465)**: kiểm chứng bằng `git diff ee3d24f --stat -- Sources/` **rỗng** ⇒ không còn dòng nào của đợt thí nghiệm backend (1.3.466 → 1.3.469).
- **Vì sao revert hết chứ không chỉ gỡ EP**: (1) **cầu nối log ORT** chỉ có ích khi bật verbose cho thí nghiệm — ở mức WARNING ORT **im lặng** trên 4 graph này (không in gì trong nhiều lượt nạp model trên PC), lỗi thật thì C API đã trả về qua `RuntimeError` ⇒ nó là **code chết**; (2) **đường nạp lại engine** chỉ có người dùng nhờ một thay đổi hành vi (ô "Số luồng" áp dụng ngay) mà người dùng **chưa yêu cầu**; (3) giữ lại làm codebase khác mốc đã ship **+214 dòng** mà không đổi lại lợi ích.
- **Xoá 2 file**: `VieNeuTTSEngine+Reload.swift` (44) · `VieNeuTTSService+Reload.swift` (36). Validator: **641 → 639** file Swift.
- **Trở lại như cũ**: 7 thành viên engine + `engine` của service về `private`; `VieNeuONNXRuntime.init(modelStore:threadCount:)`; `createBaseContext` dùng `CreateEnv`; tên hàm `invalidateVieNeuSynthesisSpeed()`; ô "Số luồng" + caption trở về hành vi cũ.
- **Kết luận kỹ thuật vẫn giữ** (không bị revert, đã ghi trong `Docs/Reports/`): int8 · fp16 · CoreML EP · XNNPACK EP · nén thời lượng — **tất cả đều không dùng được** cho `VieNeu-TTS v3 Nano` + ORT 1.24.2. `rules.md` **Luật 23** giữ lại (đừng thử lại CoreML EP); Luật 20/21/22 mất hiệu lực vì code đã gỡ.

---

## [1.3.469] - 2026-10-02

### fix: loai bo CoreML EP va noi duong nap lai engine vao o So luong tong hop

Tiếp sau 3 lượt đo CoreML EP trên máy thật (1.3.466 → 1.3.468): **cả ba cấu hình đều hỏng**.

- **Bằng chứng quyết định** (log `app_logs (63).txt`): với `MLComputeUnits=CPUOnly` — đường CoreML chạy trên CPU, **không mất độ chính xác** — audio **vẫn nhiễu**. ⇒ Thủ phạm là **semantics của CoreML EP** với graph này (nghi `ctx_mask` bool + phân mảnh với chiều động), **không phải fp16/ANE**. Kể cả trường hợp tốt nhất (2 partition) `rtf` vẫn 0,67–0,87 so với **0,26–0,44** của ORT CPU ⇒ chậm gấp ~2×.
- **Đã xoá**: đăng ký CoreML EP (`appendCoreMLProvider`, `VieNeuORTRunOptions`, `VieNeuORTCreateWithRunOptions`), công tắc trong Cài đặt + `@State vieNeuCoreMLEnabled`, `coreMLActive`, `prepareCoreMLCacheDirectory`, khoá `vieneuCoreMLEP`.
- **Giữ lại hạ tầng có giá trị**: log ORT → `AppLogger` (nay **luôn** bật ở mức WARNING, `CreateEnvWithCustomLogger` thay `CreateEnv`) và **đường nạp lại engine tại chỗ**.
- **Đường nạp lại nay có người dùng thật**: ô **"Số luồng tổng hợp"** áp dụng **ngay** (nạp lại engine ~2 s + dòng trạng thái) thay vì bắt *"mở lại app hoặc đổi engine"* như trước — số luồng chỉ có hiệu lực lúc tạo session ORT.
- `reloadEngine(useCoreML:)` → **`reloadEngine(reason:)`**.
- **Luật 23** (`rules.md`): đừng thử lại CoreML EP cho model Nano, kèm bài học chung khi thử một EP mới cho đường phát (công tắc tắt được + tiêu chí đo chốt trước + log của backend vào được `AppLogger`).
- **Trần dòng lùi mạnh**: `VieNeuONNXRuntime.swift` 400 → **341** · `VieNeuONNXBridge.m` 1257 → **1187** · `VieNeuONNXBridge.h` 219 → **196** · `VieNeuSynthesisPolicy.swift` 199 → **187** · `TTSSettingsView+VieNeu.swift` 398 → **361**; còn **2** file chạm trần 400 (`VieNeuTTSEngine.swift`, `VieNeuTTSService.swift`).

---

## [1.3.468] - 2026-10-02

### fix: CoreML EP ep shape tinh van ra tieng nhieu - chuyen MLComputeUnits sang CPUOnly de chan doan

Người dùng: *"phát ra toàn tiếng nhiễu, không có tiếng việt"* (log `app_logs (62).txt`).

- **1.3.467 sửa được "im tiếng" nhưng lộ lỗi nặng hơn**: với `RequireStaticInputShapes=1`, CoreML EP còn **14 partition** và `[VieNeuPerf] coreML=on` có đầy đủ (`pcm` 7,32 / 6,95 / 8,61 s…) nhưng audio là **nhiễu hoàn toàn, không có tiếng Việt** ⇒ **giá trị tính ra sai**, không phải lỗi tầng phát. Kèm theo `rtf` **0,64–0,93** so với **0,26–0,44** của CPU thường ⇒ chậm gấp ~2×, 3 `Underrun`.
- **Đổi `MLComputeUnits` → `CPUOnly`** (bước **chẩn đoán**): CoreML trên CPU là đường **không mất độ chính xác** (fp32) ⇒ nếu audio **đúng** thì thủ phạm là **fp16/ANE**; nếu **vẫn nhiễu** thì lỗi ở **semantics/phân mảnh của EP**. Không phải để dùng thật — CoreML trên CPU chắc chắn chậm hơn ORT CPU.
- **Cache**: hậu tố đổi thành `CoreMLCache-staticShapes-cpuOnly`; **cả hai** thế hệ cache cũ (`CoreMLCache`, `CoreMLCache-staticShapes`) bị dọn một lần theo danh sách tên (Luật 22).
- **Trần dòng**: `VieNeuONNXRuntime.swift` giữ **đúng 400** (đã vượt 402 khi thêm chú thích và phải nén lại — lần sau **tách file trước**) · `VieNeuONNXBridge.m` 1252 → **1257**.

---

## [1.3.467] - 2026-10-02

### fix: CoreML EP chia vector_estimator thanh 33 partition lam im tieng - ep shape tinh

Người dùng: *"hoàn toàn không phát ra tiếng"* sau khi bật công tắc CoreML/ANE (log `app_logs (61).txt`).

- **Nguyên nhân (đúng rủi ro đã ghi ở plan 1.3.466 §7)**: với `RequireStaticInputShapes=0`, CoreML EP chia `vector_estimator` thành **33+ partition**, mỗi partition là một `.mlmodel` được **biên dịch riêng** (`CoreMLCache/<hash>/3_dynamic_mlprogram` … `33_dynamic_mlprogram`) và **sinh thêm partition ở mỗi lượt chạy**. Trong 25 giây đọc **không có một dòng `[VieNeuPerf]` nào** — chưa lượt tổng hợp nào hoàn tất, chỉ có `[NghiEnergy] Underrun chapter=116 index=174/177` ⇒ im tiếng.
- **Sửa**: `RequireStaticInputShapes=1` (EP chỉ nhận node có shape tĩnh). `L` và `T` của model này đổi mỗi đoạn nên EP sẽ nhận **rất ít** node — kỳ vọng lợi ích ~0, nhưng **hết bão biên dịch**. Đây là bước kiểm chứng trước khi quyết định bỏ hẳn EP.
- **Tách cache theo cấu hình EP**: khoá cache của CoreML EP **chỉ** là hash model, **không** gồm tuỳ chọn EP ⇒ đổi tuỳ chọn mà giữ thư mục cũ là partition của cấu hình cũ bị tái dùng. Thư mục nay là `CoreMLCache-staticShapes`; thư mục `CoreMLCache` của 1.3.466 (chứa 33+ partition của cấu hình hỏng) được **dọn một lần**.
- **Luật 22** (`rules.md`): cache của execution provider phải tách theo cấu hình EP.
- Công tắc vẫn **mặc định TẮT**; khôi phục nếu vẫn im tiếng: gạt công tắc về TẮT (engine tự nạp lại bằng CPU).
- **Trần dòng**: `VieNeuONNXRuntime.swift` 390 → **400** (chạm trần — lần sau phải tách file trước) · `VieNeuONNXBridge.m` 1245 → **1252**.

---

## [1.3.466] - 2026-10-02

### feat: them cong tac thi nghiem CoreML/ANE cho VieNeu-TTS de giam tai CPU

Nối tiếp nghiên cứu nhóm C (`Docs/Reports/research-2026-10-02-vieneu-nhom-C.md`): lượng tử hoá int8 đã bị **loại bằng số đo** (chậm 2,7× và audio SNR 2,2 dB), còn CoreML EP thì **đã nằm sẵn** trong thư viện ORT mà app đang link.

- **Công tắc "Dùng CoreML/ANE (thử nghiệm)"** trong *Quản lý riêng của trình đọc*, **mặc định TẮT**. Bật ⇒ đăng ký CoreML EP cho `vector_estimator` (**83,1 %** thời gian chunk) và `codec_decoder` (**15,5 %**) với `ModelFormat=MLProgram`, `MLComputeUnits=CPUAndNeuralEngine`, `ModelCacheDirectory` (bắt buộc — không cache thì Core ML biên dịch lại mỗi lần mở session) và `ProfileComputePlan=1`.
- **Dùng API key/value** `SessionOptionsAppendExecutionProvider` (có từ ORT 1.12) chứ không dùng `..._CoreML(options, flags)`: API cũ **không** đặt được cache dir lẫn profile.
- **Đường nạp lại engine tại chỗ** (2 file mới `VieNeuTTSEngine+Reload`, `VieNeuTTSService+Reload`): `prepareLocked` chỉ chạy một lần trong vòng đời engine nên đổi EP mà không nhả thì cấu hình mới không bao giờ có hiệu lực. `unload()` nhả theo thứ tự bắt buộc — `runtime = nil` **trước** khi xoá ba mảng `null*` (tensor cache của nhánh vô điều kiện trỏ vào buffer của chúng), và chỉ an toàn nhờ `lock` của engine.
- **Log ORT vào `AppLogger`**: `CreateEnvWithCustomLogger` + callback con trỏ hàm C (không dùng block ⇒ không phụ thuộc ARC). Bật EP ⇒ **buộc** mức VERBOSE, vì `ProfileComputePlan` ghi ở mức INFO — để WARNING là mất luôn bảng phân bổ ANE/GPU/CPU.
- **Nguồn sự thật là trạng thái thật**: `coreMLActive` (EP có đăng ký được không) chứ không phải cờ `UserDefaults`. EP lỗi ⇒ tự nạp lại bằng CPU + toast + gạt công tắc về TẮT, không để UI nói dối.
- `invalidateVieNeuSynthesisSpeed()` **đổi tên** thành `invalidateVieNeuPrefetch(reason:)` để dùng chung cho cả hai nguyên nhân (đổi tốc độ tổng hợp / nạp lại engine).
- **Trần dòng**: `VieNeuTTSEngine.swift` giữ **đúng 400** (chỉ đổi `private`→`internal` và nối thêm tham số vào dòng có sẵn) · `VieNeuTTSService.swift` 398 → **400** (lần sau phải tách file trước) · `TTSSettingsView.swift` 458 → **462**.
- **Chưa kết luận**: tiêu chí đã chốt trước khi đo — *ăn* nếu `rtf` giảm ≥ 20 % và audio không lệch tai nghe; lượt đo đầu tiên bị loại vì còn thời gian Core ML biên dịch.

---

## [1.3.465] - 2026-10-02

### feat: them thanh Toc do tong hop cho VieNeu-TTS de giam tai CPU va giam nhiet

Người dùng: *"Tôi muốn tối ưu thêm VieuNeu-TTS để giảm nhiệt, giảm lag"* (ràng buộc cứng: **không ảnh hưởng độ mượt khi nghe**).

- **Gốc rễ tìm được: không engine local nào dùng tốc độ gốc của model.** `TTSManager.swift:2903`/`:3596` và `TTSNextChapterPrefixSynthesizer` đều truyền `speed: 1.0`; tốc độ chỉ áp bằng `AVAudioPlayer.rate` (`NghiAudioPlayerQueue.swift:186`, `enableRate = true` ⇒ varispeed, **đổi cả cao độ**). Trong khi VieNeu có sẵn `secs = exp(log_s)/speed` (`VieNeuTTSEngine.swift:336`) và Piper có `lengthScale = 1/speed`.
- **Vì sao đây là đòn bẩy duy nhất thoả ràng buộc**: lượng tính toán tỷ lệ thuận với thời lượng audio sinh ra, nên tổng hợp ở 1,8× rồi phát 1,0× cho cùng tốc độ nghe mà tốn ít hơn ~45 % tính toán (duty cycle 79 % → ~44 %). Hạ luồng ORT / hạ QoS / tự động theo nhiệt đều là **làm chậm** tổng hợp ⇒ sinh đứt đoạn.
- **Thanh mới "Tốc độ tổng hợp (VieNeu)"** (1,0–2,0, bước 0,1, mặc định 1,0 = hành vi cũ) đặt cạnh thanh Tốc độ trong section *Cấu hình giọng nói*; hiện luôn **tốc độ nghe thực tế** (= tích hai thanh) và đổi màu khi > 2,0×. Màn "Nghe thử" dùng chung cài đặt.
- **Khoá cache**: `TTSSynthesisIdentity.computeKey` nhận thêm `synthesisSpeed` — thiếu thì audio tốc độ cũ được trả cho yêu cầu tốc độ mới.
- **Đổi lúc đang đọc**: phát nốt đoạn hiện tại (`invalidateVieNeuSynthesisSpeed()` huỷ nạp trước, lọc `preloadedData`, `clearPreparedNext()`), áp từ đoạn kế ⇒ không khựng.
- **Trần dòng**: `TTSSettingsView.swift` kẹt **519/519** ⇒ Section 4 chuyển nguyên sang file mới `TTSSettingsView+Voice.swift` (**90**), file chính **519 → 458**. `TTSManager.swift` giữ **3970** (gộp hai dòng tham số để bù).

---

## [1.3.464] - 2026-10-01

### feat: dat hop thoai Tron/Thay the vao nut nhap vao tu dien sau phien am lai, revert duong nhap tu file va ve lai UI danh sach tron

Người dùng: *"ý tôi là sau khi bấm vào nhấp vào từ điển sau khi phiên âm lại từ điển xong thì hiển thị trộn và thay thế, bạn làm cho chức năng nhập từ file làm gì, ngoài ra UI quá xấu. mocup lại UI phần danh sách trộn"* + *"Đường nhập từ file revert lại ver cũ đi"*.

- **Sửa hiểu nhầm của 1.3.462/463.** Hộp thoại *Trộn / Thay thế toàn bộ* từng gắn vào **đường nhập từ điển từ file**; ý người dùng là nó thuộc **bước áp kết quả phiên âm lại** — tức nút **"Nhập vào từ điển"** ở card màn Thông báo và ở banner màn từ điển.
- **Nút áp dùng chung.** File mới `RephoneticizeApplyButton.swift` (**122**): vẽ nút "Nhập vào từ điển" + `confirmationDialog` hai nhánh; *Thay thế toàn bộ* gọi `RephoneticizeTask.apply()` (hành vi cũ, có `.bak-rephoneticize`), *Trộn* mở `DictionaryImportConflictView`. Một nút cho cả hai chỗ để không bên nào quên bước sao lưu.
- **`RephoneticizeTask.applyMerged(_:)`** — đường áp kiểu trộn. `apply()` và nó cùng đi qua một helper `write(_:)` ⇒ hai đường không thể lệch ở bước sao lưu hay bước dọn file kết quả + meta. `RephoneticizeService.normalizedKey(_:target:)` và `currentWords(for:)` hạ `private` → `internal`.
- **Màn danh sách trộn vẽ lại (hướng C).** Mỗi dòng hai tầng — `khoá` đậm, rồi `cách đọc hiện tại → cách đọc mới` trên **cùng một dòng**; **chạm cả dòng** để chọn/bỏ (bỏ `Toggle`); chip `N trùng · M thêm mới · K giữ nguyên`; ô tìm kiếm + `Chọn hết` / `Bỏ chọn hết`. Màn **tự đọc** từ điển đang dùng trong `Task.detached` (không nhận ảnh chụp từ caller) để mục bị bỏ chọn không bị ghi đè bằng giá trị cũ.
- **Revert 100% đường nhập từ file** về code trước 1.3.462: VieNeu **trộn** (bản nhập thắng), NghiTTS **ghi đè toàn bộ** (ghi plist trực tiếp + `loadResources()`, **không** backup, có lại `parseCSV` riêng). **Xoá** `DictionaryImportFlowModifier.swift`; giữ `DictionaryImportParser` + `DictionaryImportDiff` vì màn trộn dùng.

---

## [1.3.463] - 2026-10-01

### fix: hop thoai Tron/Thay the toan bo khong hien, chi hien card da phien am lai va banner tien do o man tu dien

Người dùng: *"vì sao nhập từ điển không có 2 option Trộn / Thay thế toàn bộ; bạn đang hiểu nhầm gì không đấy"* + *"ở thông báo từ điển nào phiên âm lại mới hiển thị ra, từ điển không phiên âm hiển thị làm gì"*.

- **Hộp thoại *Trộn / Thay thế toàn bộ* không hiện — lỗi presentation.** 1.3.462 mở hộp thoại bằng `.onChange(of: fileURL)`, tức bật cờ **ngay trong `onPick`**; mà `onPick` của `DocumentPicker` chạy trong **completion của lượt dismiss** sheet chọn file ⇒ presentation bắt đầu giữa lượt dismiss modal bị UIKit/SwiftUI **nuốt im lặng**. Tệ hơn: `fileURL` vẫn còn giá trị nên `.onChange` không thấy đổi ⇒ chọn lại **đúng file đó** cũng không kích hoạt lại. Nay cờ `isModeDialogPresented` do **View gọi sở hữu** và bật trong `onDismiss` của sheet chọn file — hook này chỉ chạy **sau khi** animation đóng xong.
- **Chỉ hiện card của từ điển đã phiên âm lại.** `rephoneticizeRow()` vẽ **cả hai** card vô điều kiện ⇒ từ điển chưa chạy vẫn hiện một dòng "Chưa phiên âm lại" vô nghĩa. Nay mỗi card chỉ vẽ khi `task.isVisible`.
- **Chặn nhầm file hợp lệ ở màn NghiTTS.** Kiểm tra kích thước `resourceValues(forKeys: [.fileSizeKey])` thêm ở 1.3.462 nhưng đọc **ngoài** security scope ⇒ file từ provider (iCloud/Files) ném lỗi, `fileSize` ra 0, chặn nhầm file hợp lệ. Nay bọc trong `startAccessingSecurityScopedResource()` / `stopAccessing`.
- **Banner tiến độ ngay trên màn từ điển.** User: *"hiển thị cả tiến độ phiên âm lại ở màn hình từ điển phiên âm nữa, tương tự màn hình thông báo"*. Thêm `RephoneticizeProgressBanner` — `ViewModifier` gắn qua `.safeAreaInset(edge: .top)`: tiêu đề + `statusText`, `ProgressView(value:)` khi đang chạy, và khi có kết quả thì nút **Nhập vào từ điển** / **Bỏ qua** (nút **Xuất file** để ở màn Thông báo cho banner khỏi che danh sách). Là modifier chứ không viết thẳng vì `VieNeuJapaneseDictionaryView.swift` đang **397/400**; mỗi màn chỉ thêm **một dòng**.
- **File mới**: `Views/Settings/TTS/RephoneticizeProgressBanner.swift` (**127**) · `Views/Settings/TTS/VieNeuJapaneseDictionaryView+Status.swift` (**36** — tách `statusSection` + `JapaneseFlags` khỏi file chính khi nó chỉ còn **1** dòng biên so với trần 400).
- **File sửa**: `DictionaryImportFlowModifier.swift` 144 → **158** (bỏ `.onChange`, `@State showingModeDialog` → `@Binding isModeDialogPresented`), `TTSDictionaryEditView.swift` 518 → **532**, `VieNeuJapaneseDictionaryView.swift` 389 → **374** sau khi tách, `NotificationInboxView+Rephoneticize.swift` 219 → **226**.
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100% (16 doc, 636 file Swift)**. Không build được trên Windows.
- **Tài liệu CodeGraph**: `11_subsystems.md` thêm mục 1.3.463 — **accept**.

---

## [1.3.462] - 2026-10-01

### feat: chip NGI/VIE, xoa tu bang nhan giu, tsu thanh su, phien am lai tu dien va man chon trung khi nhap

Thực thi plan `Docs/Plans/2026-10-01-plan-chip-ngi-vie-va-phien-am-lai-tu-dien.md` (phiên grill-me, 17 câu hỏi đã chốt).

- **Chip gợi ý có hai nguồn.** `TTSPhoneticSuggestion.Origin` tách `.library` (badge `TĐ`) thành `.nghiTTSLibrary` (`NGI`) + `.vieNeuLibrary` (`VIE`); `AddWordSheet` tra **cả hai** store mỗi lượt. Dedupe đổi khoá từ `text` sang `origin.rawValue + "|" + text` ⇒ hai từ điển cùng cách đọc vẫn hiện **hai** chip (trước đây chip của nguồn kia bị nuốt). Cả hai chip từ điển đều `isPipelineChoice = true`.
- **Nhấn giữ chip `NGI`/`VIE` để xoá mục** khỏi đúng từ điển (`contextMenu` + `confirmationDialog` → `TextPreprocessor.deleteWord` / `VieNeuJapaneseDictionary.delete`). Chip `JP`/`EN` không có menu. Chip gỡ **sau khi** xoá thành công.
- **`tsu` (つ) đọc "su" thay vì "chu"**: `JapaneseTransliterator.romajiToViSyllable` sửa một dòng. Bảng dùng **chung** cho NghiTTS, VieNeu và chip JP ⇒ cả hai engine đổi theo; `tu` vẫn ra `"chu"`.
- **Nút "Phiên âm lại từ điển"** ở cả hai màn từ điển → `RephoneticizeService.run` chạy trong `Task.detached(priority: .utility)`: chuẩn hoá khoá (gấp dấu phụ — vá luôn **mục chết** của NghiTTS), gộp mục trùng khoá, mục engine không phiên âm được thì **giữ giá trị cũ**. NghiTTS đi đúng thứ tự `transliterateToken` (Nhật trước, Anh sau); VieNeu chỉ có nhánh Nhật. Kết quả ghi ra `phien-am-lai-nghi.plist` / `phien-am-lai-vieneu.plist` — **không** ghi thẳng vào từ điển.
- **Hai card ở màn Thông báo**, mỗi từ điển một card. Số liệu nằm ở **file meta JSON** kèm theo (`RephoneticizeService.Meta`, mirror `DictionaryMergeService.Meta`); `init` chỉ đọc meta vài trăm byte, `body` **không** chạm đĩa — đúng cách chữa của 1.3.448 để mở màn Thông báo sau khi khởi động lại không bị đơ.
- **"Nhập vào từ điển"** sao lưu `.bak-rephoneticize` rồi `replaceAllWords` / `replaceAll`.
- **Luồng nhập file gom vào `DictionaryImportFlowModifier`**: hỏi *Trộn* / *Thay thế toàn bộ*. Chọn *Trộn* mở `DictionaryImportConflictView` — màn mở **ngay** với skeleton, parse + `diff` chạy trong `Task.detached`, mặc định **tích hết**, có ô tìm kiếm + Chọn hết/Bỏ chọn hết; **Huỷ = không ghi gì**. `DictionaryImportParser` dùng chung plist/json/csv/txt.
- **Bất đối xứng đã sửa**: nhập của NghiTTS trước đây **ghi đè toàn bộ** (`TTSDictionaryEditView.swift:459-460`, không backup) còn VieNeu **trộn**; nay cả hai có đủ hai nhánh và nhánh ghi đè có sao lưu. `loadResources()` không xoá `transliterationCache` ⇒ nay đường ghi dùng `replaceAllWords` để xoá cache cùng lượt.
- **Bẫy đã vấp**: `private @State` trong struct làm `init` memberwise thành `private` ⇒ ba chỗ (`DictionaryImportConflictView`, `DictionaryImportFlowModifier`, `RephoneticizeCard`) phải khai `init` tường minh, nếu không CI đỏ ở file gọi.
- **File mới (7)**: `RephoneticizeService` **309** · `RephoneticizeTask` **236** · `DictionaryImportConflictView` **234** · `NotificationInboxView+Rephoneticize` **219** · `DictionaryImportFlowModifier` **144** · `DictionaryImportParser` **128** · `DictionaryImportDiff` **94**.
- **File sửa**: `TTSDictionaryEditView.swift` 559 → **518** (giảm), `AddWordSheet.swift` 253 → **344**, `VieNeuJapaneseDictionaryView.swift` 358 → **389**, `NotificationInboxView.swift` 368 → **393**, `TTSPhoneticSuggestion.swift` 61 → **82**, `TTSPhoneticSuggestionBuilder.swift` 81 → **91**, `JapaneseTransliterator.swift` 347 → **350**, `TextPreprocessor+Bulk.swift` 30 → **47**.
- **Ràng buộc đã đo**: `check_architecture.py` giữ nguyên **5** violation nền và **0** vi phạm mới; `validate_links.py` **PASS 100% (16 doc, 636 file Swift)**. Không build được trên Windows.
- **Tài liệu CodeGraph**: cả **10** doc stale đều được cập nhật mục 1.3.462 (`00_index`, `02_file_graph`, `03_type_graph`, `04_call_graph`, `09_dependency_rules`, `10_risk_report`, `11_subsystems`, `13_resource_lifecycle`, `14_complexity_report`, `rules.md` thêm **luật 13–17**).
- **Chưa chốt**: có nên **chặn** "Phiên âm lại" khi TTS đang đọc (nhánh tiếng Anh dùng chung `NSLock` của espeak với đường tổng hợp ⇒ có thể giật audio).

---

## [1.3.461] - 2026-10-01

### fix: bo ep che do cao theo loai giong, doc truyen theo dung cai dat TTS

Người dùng: *"tôi bật fast mà sao lại log high nhỉ"* → *"chỉ high khi đang thực hiện clone giọng, khi đọc tts thì theo đúng cài đặt tts, cài đặt tts là tiết kiệm thì phải tiết kiệm"*.

- **Sửa lỗi phạm vi của 1.3.456.** Lượt đó thêm `isClonedVoice` vào `VieNeuSynthesisPolicy.effectiveMode` và **ép `.high` (16 bước) cho MỌI lượt tổng hợp bằng giọng nhân bản**, kể cả đường đọc truyện. Đó là **hiểu sai yêu cầu gốc**: "chất lượng cao" thuộc **bước clone giọng** (chọn audio gốc + bấm Lưu) — mà bước đó chạy **3 graph clone** (`speaker_encoder`/`codec_encoder`/`reference_encoder`), **không** chạy vòng Euler ⇒ **không có `steps`** để đặt. Nay `effectiveMode(requested:current:)` = `requested ?? current`: **chỉ theo cài đặt**, cho cả giọng preset lẫn giọng clone.
- **Triệu chứng thật, đo từ log người dùng gửi** (`app_logs (58).txt`): "Tiết kiệm pin" BẬT + giọng clone ⇒ `mode=high`, `rtf` 0,75–1,08, `busyPct` **97,2 %**, **`underrun` 4**, `thermal=serious` ⇒ **audio giật, máy nóng**. Màn Cài đặt vẫn hiện "Cân bằng" (vì "Tiết kiệm pin" khoá ô chọn) và **không có gì tiết lộ sự lệch** ⇒ người dùng tưởng lỗi ở chỗ khác.
- **Cách chẩn đoán** (đáng nhớ): log `[VieNeuPerf] mode=` in **đúng** `activeMode` (`VieNeuTTSEngine.swift:282`). "Tiết kiệm pin" BẬT ⇒ `requestedMode = .fast` (`VieNeuTTSService.swift:105` setter, `:133` trong `prepare`) ⇒ nếu giọng là **preset** thì `activeMode` **phải** là `.fast`; log ghi `high` ⇒ nhánh duy nhất còn lại là `isClonedVoice == true` ⇒ giọng đang chọn ở Reader **là giọng nhân bản** (danh sách giọng xếp giọng user **lên đầu** nên rất dễ được chọn sẵn).
- **Loại trừ được nghi vấn sai**: tính năng **từ điển tiếng Nhật (1.3.459) KHÔNG liên quan** — trong log, `Danzo`/`Sharingan`/`Shisui` đi tới engine nguyên vẹn (không có trong từ điển và `ForeignScriptClassifier` không nhận là tiếng Nhật), và lớp tiền xử lý còn chạy ở **tầng service trước khi gọi engine** nên không nằm trong `vectorMs`/`otherMs`.
- **Hệ quả có chủ ý**: đọc truyện bằng giọng clone khi "Tiết kiệm pin" BẬT nay chạy **8 bước** ⇒ RTF ~0,45, hết `underrun`, máy mát hơn; đổi lại **âm sắc khi đọc bám mẫu kém hơn** 16 bước. Muốn 16 bước khi đọc thì **tắt "Tiết kiệm pin" + đặt "Chất lượng cao"** — hai công tắc đã có sẵn, không thêm gì.
- **`Preset.isCloned` nay không còn caller** — giữ lại (vị từ miền "giọng này do user tạo" mà UI sẽ cần khi muốn đánh dấu giọng nhân bản trong danh sách), doc đã sửa để **không** còn nói nó đổi chế độ chất lượng.
- **File sửa**: `VieNeuSynthesisPolicy.swift` (doc viết lại + bỏ tham số `isClonedVoice`), `VieNeuTTSEngine.swift:216` (1 dòng, giữ **400/400**), `VieNeuVoiceCatalog.swift` (doc `isCloned`).
- **Ràng buộc đã đo**: `check_architecture.py` **5 violation nền / 0 mới**; `validate_links.py` **PASS 100% (16 doc, 629 file Swift)**.
- **Tài liệu CodeGraph**: `11_subsystems.md` thêm mục 1.3.461 + `rules.md` thêm luật **"đừng ghi đè cài đặt người dùng vì lý do chất lượng"** — **accept**; `04_call_graph`, `10_risk_report`, `13_resource_lifecycle` **no-change-needed**.
