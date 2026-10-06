---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T14:10:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 9
---

# Hướng dẫn Quy định Lập trình (Coding & Architecture Rules)

Tài liệu này tổng hợp các quy tắc lập trình, quy định bảo trì và kiến thức kỹ thuật chi tiết của dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## 1.3.476 — một luật mới (tham số runtime suy luận bất biến sau khi tạo session)

* **Luật 30 — tham số của một runtime suy luận thường **bất biến sau khi tạo session**, nên muốn quét nó thì phải thiết kế **đường dựng lại**, và phép quét đó là **thủ công**.** Số luồng ORT nằm trong `OrtSessionOptions` lúc `CreateSession`; **không có API nào** đổi số luồng của một `OrtSession` đã tạo. Hệ quả kép: (a) đổi cấu hình = **nhả ngữ cảnh cũ rồi dựng lại** — và phải nhả **trước** khi dựng, vì giữ cả hai cùng lúc ở đây là ~1,8 GB, đủ để bị jetsam; (b) mỗi mức tốn lại ~18 s nạp model, nên giao diện phải có **nút "Áp dụng"** chứ không được tự quét ngầm sau mỗi lần bấm ▶. Cùng luật này áp cho mọi tham số session khác (execution provider, graph optimization level, arena).
* **Hệ quả về phép đo**: khi so nhiều mức cấu hình, phải **ghi lại các biến ngoài tầm kiểm soát** đi kèm số đo — ở đây là `thermalState` và `lowPowerMode`. Nạp 903 MB rồi làm nóng là đủ để máy ấm lên và bị hạ xung, nên một số RTF đo lúc `serious` **không so được** với số đo lúc `nominal`. Không ghi lại thì phép quét kết luận sai.

## 1.3.475 — hai luật mới (đo hiệu năng phải làm nóng; "im lặng" phải tách bằng biên độ đỉnh)

* **Luật 28 — đo hiệu năng một runtime suy luận thì **phải làm nóng trước**; số của lượt đầu không phải số ổn định.** ORT (và hầu hết runtime) cấp phát arena + tối ưu graph ở lần `Run` **đầu tiên** của mỗi session. Đo thẳng lượt đầu rồi kết luận "RTF = 1,07, vượt ngưỡng" là tự lừa mình — và nó lừa theo hướng **bi quan**, tức sẽ dẫn tới quyết định bỏ một engine dùng được. Cách làm: sau khi nạp, đẩy **một lượt thật** qua toàn bộ pipeline rồi vứt kết quả, và **đo riêng** thời gian làm nóng để số đó không lẫn vào số RTF (ở ZeroTTS: `warmupMs`). Bản port JS của upstream có hẳn `warmup()` cho việc này.
* **Luật 29 — "chạy xong mà không có kết quả" phải tách bằng một **đại lượng đo được**, không bằng suy đoán.** Với audio: in **đỉnh biên độ** của PCM. Gần `0` ⇒ tầng **sinh** im lặng (lỗi ở model/codec); biên độ bình thường mà không nghe thấy gì ⇒ lỗi ở tầng **phát** (phiên âm thanh, player). Hai nguyên nhân này có cách sửa hoàn toàn khác nhau, và không có số đo thì chỉ còn cách đoán — lượt 1.3.475 tốn một vòng CI + một vòng máy chỉ vì thiếu đúng một con số. Kèm theo: khi tầng phát không kêu, **kích hoạt phiên âm thanh tường minh** (`AVAudioSession.setCategory` + `setActive(true)`) chứ đừng trông vào việc kích hoạt ngầm của `AVAudioPlayer`, và **kiểm giá trị trả về** của `play()` thay vì bỏ qua nó.

## 1.3.474 — một luật mới (input thì khai kiểu, output thì phải hỏi kiểu)

* **Luật 27 — với tensor ONNX: `input` phải đúng kiểu mình khai, nhưng `output` phải HỎI `GetTensorElementType`.** Hợp đồng upstream ghi `codes (1, K)` là `int64`, và `text_ids`/`new_pos`/`frame_codes` đúng là int64 vì chúng là **input** (graph báo lỗi ngay nếu khai sai). Nhưng **output** int64 *không* được bảo đảm trả về đúng kiểu đó — trên máy thật `local_frame_decode` trả `codes` là **int32**. Copy cứng bằng `memcpy(count * sizeof(int64_t))` gói hai code vào một số 64-bit, và triệu chứng nằm ở **graph sau**: `Gather … indices element out of data bounds, idx=1189705941190` — trông như hỏng bộ nhớ, thật ra là `198 + 277 × 2^32` (hai code hợp lệ). Bản port JS đã biết điều này và có `toBigInt64` "coerce, not cast"; bản C đã bỏ qua cảnh báo đó. **Cách đọc đúng**: `GetTensorTypeAndShape` → `GetTensorElementType` → đổi theo kiểu (`INT64` memcpy; `INT32`/`INT16`/`INT8`/`UINT8` chuyển từng phần tử; kiểu khác thì báo lỗi kèm số hiệu kiểu). Áp dụng cho **mọi** output số nguyên, không chỉ chỗ vừa hỏng.
* **Hệ quả chẩn đoán**: khi một tensor đi vào **graph sau** và graph đó báo lỗi miền giá trị, thủ phạm thường là **graph trước** đọc sai kiểu — không phải graph đang báo lỗi. Thêm kiểm miền ngay tại chỗ sinh ra giá trị (`local_frame_decode` kiểm `[0, codebookSize]` và nêu phần tử thứ mấy) để lỗi nêu đúng thủ phạm.

## 1.3.473 — một luật mới (shape của tensor ONNX phải được kiểm bằng một lượt chạy thật)

* **Luật 26 — shape tensor của graph ONNX chỉ được coi là đã kiểm khi có một lượt chạy thật; đọc hợp đồng rồi viết lại vẫn sai được, và sai ở đây không lộ ra lúc biên dịch.** Ví dụ thật (1.3.473): `frame_codes` của `prefix_step` khai `(B, T, K)` — bản port đã lấy `T`-của-một-frame làm `K` (`{batch, 1, 1}` thay vì `{batch, 1, 16}`) và chỉ lộ ra khi chạy trên máy: `Got invalid dimensions for input: frame_codes … index: 2 Got: 1 Expected: 16`. Hợp đồng đã có sẵn trong `docs/RUNTIME.md` của upstream mà vẫn sai. Hệ quả quy trình: (a) màn thử/engine **phải in nguyên văn** thông báo lỗi của ORT — nó nêu đúng tên tensor, đúng index và đúng số mong đợi; (b) khi **nhiều** tham số cùng khai một chiều (ở đây `K` xuất hiện ở `audio_random_u`, `seen_mask` và `codebooks`), phải thêm guard ngay sau lời gọi trả về chiều đó để thông báo lỗi chỉ đúng thủ phạm thay vì chỉ đúng chỗ nổ.
* **Nhắc lại (đã ghi ở 1.3.472)**: `SWIFT_OBJC_BRIDGING_HEADER` chỉ nhận **một** đường dẫn ⇒ cầu C thứ hai phải qua umbrella header `Sources/Services/TTS/ONNXBridgingHeader.h`.

## 1.3.472 — ba luật mới (fixture khi port; `Section` đủ ba closure; exclusivity khi bọc C API) + một luật build-config

* **Luật 25 — không đọc `.count` của một mảng bên trong `withUnsafeMutableBufferPointer` của chính nó.** Swift báo `error: overlapping accesses to 'x', but modification requires exclusive access` — **lỗi biên dịch**, không phải cảnh báo. Phải hoist ra biến cục bộ **trước** closure: `let count = array.count` rồi dùng `Int32(count)` bên trong. Bẫy này đi kèm việc bọc C API bằng buffer của Swift (mỗi tham số truyền `baseAddress` + `count`), nên repo nay có **hai** cầu C thì nó sẽ còn gặp lại. Lưu ý phân biệt: đọc `.count` của **mảng khác** (nhất là qua `withUnsafeBufferPointer` bất biến) thì **không** vi phạm — chỉ mảng đang bị mượn mutable mới cấm.
* **Luật 24 — `Section` vừa có tiêu đề vừa có footer phải viết `Section { } header: { } footer: { }`.** SwiftUI **không** có initializer `Section(_:content:footer:)`; viết `Section("Giọng đọc") { … } footer: { … }` là lỗi biên dịch `error: missing argument label 'content:' in call` + `cannot convert value of type 'String' to expected argument type '() -> Content'`. Đây là lần thứ **hai** bẫy này xuất hiện trong repo (lần đầu ở khối từ điển), nên nó được ghi thành luật thay vì chỉ nằm trong ghi chú. Các dạng **hợp lệ** đã kiểm: `Section { } header: { } footer: { }`, `Section { } header: { }`, `Section { } footer: { }`, `Section("Tiêu đề") { }` (không footer). Lưu ý phụ: máy phát triển là Windows nên loại lỗi này chỉ lộ ra ở CI — **không** được coi "đọc kỹ rồi" là đã kiểm chứng biên dịch.
* **Luật 23 — port một thuật toán từ bản tham chiếu thì phải kèm fixture đối chiếu chạy được, không chỉ "đọc kỹ rồi viết lại".** `ZeroTTSTokenizer` là bản port của `zerotts/tokenizer.py` + `tokenizer.json`. Loại lỗi ở đây **không** ném exception: lệch một bước tách từ thì model nhận một phân đoạn nó chưa từng thấy khi huấn luyện và chỉ đơn giản là đọc tệ hơn — không có stack trace nào để lần. Vì vậy trước khi viết bản Swift, thuật toán được **viết lại bằng Python** rồi đối chiếu với thư viện `tokenizers` thật trên **6438 ca** (0 sai khác); sau đó 12 ca đại diện được nhúng vào `ZeroTTSTokenizer+Fixture.swift` để màn thử tự kiểm **trên máy** và in kết quả vào khối chẩn đoán. Repo không có tầng test nên đây là hàng rào duy nhất. Áp dụng cho mọi lần port model/thuật toán sau này (kể cả khi bản tham chiếu là Python/JS/Rust).
* **Luật build-config — `SWIFT_OBJC_BRIDGING_HEADER` chỉ nhận MỘT đường dẫn ⇒ thêm cầu C mới phải qua umbrella header.** Repo nay có hai cầu C API cho ONNX Runtime (`VieNeu/VieNeuONNXBridge.h`, `ZeroTTS/ZeroTTSONNXBridge.h`). Không `#include` chéo cầu này vào cầu kia (làm lẫn hai engine trong một file, và biến thay đổi của engine A thành thay đổi của engine B); thêm `Sources/Services/TTS/ONNXBridgingHeader.h` `#import` cả hai và trỏ `project.yml` vào đó. Đường dẫn trong ngoặc kép giải theo thư mục của chính umbrella nên không cần include path. Nhớ: sai đường dẫn bridging header là **mọi** file Swift hỏng biên dịch.
* **Nhắc lại luật đã có, vì lượt này là lần thứ tư vi phạm suýt xảy ra** — "hỏi model, đừng đoán shape". `ZeroTTSORTCreate` trả `ZeroTTSORTShapes` **đọc từ chính graph** (`seen_mask`, `global_hidden`, `packed_kv`) và `ZeroTTSEngine.validate(shapes:against:)` **đối chiếu** với `config.json`, ném lỗi nếu lệch; `ZeroTTSGenerator.validate(crossKvShape:batch:length:)` so shape `cross_kv` thật trước khi vào `prefix_step`. Lịch sử: `Got: 512 Expected: 256` (VieNeu), và trước đó là hai lần cùng loại.

## 1.3.469 — một luật mới (trạng thái tiến trình phải trả về `nil`)

* **Luật 22 — trạng thái "đang chạy" phải được đặt về `nil`, không chỉ hạ cờ boolean.** `@Published` phát lại **giá trị hiện tại** cho mỗi subscriber mới, nên một `batchProgress: (Int, Int)?` còn khác `nil` sau khi tác vụ xong sẽ **sống dậy** ở lần dựng View kế tiếp — mà không còn emission nào để tắt nó. Lỗi thật (1.3.469): thanh "Đang quét tên riêng: Batch n/n" treo vĩnh viễn sau khi quét xong, vì `startBatchExtraction` chỉ hạ `isRunning` mà không xoá `batchProgress`. Quy tắc: mọi trạng thái tuỳ chọn (`Optional`) biểu diễn "đang chạy" phải được gán `nil` ở **mọi** nhánh kết thúc — thành công, lỗi, **và** huỷ.
* **Hệ quả kèm theo**: đừng để View tự suy "đang chạy" từ một giá trị chỉ được xoá ở đường huỷ — `ReaderAIFullScreenView.onReceive($batchProgress)` ánh xạ `isBatchExtracting = (progress != nil)` chính là chỗ đã lộ lỗi.

## 1.3.468 — hai luật mới (prompt đã lưu phải di trú; bộ bóc tách chỉ một định dạng)

* **Luật 20 — đổi prompt mặc định trong code KHÔNG tự áp cho người dùng cũ.** Prompt nằm trong `UserDefaults` (`FreeBook_AI_Configuration_V1`) sau lần lưu cấu hình đầu tiên; sửa hằng số `defaultNameExtractionPrompt` chỉ ảnh hưởng máy **chưa** từng lưu. Muốn đổi cho máy đã dùng thì phải **di trú tường minh** trong `loadConfiguration()` — nhận diện bản cũ bằng marker (`suggestedMeaning` / `extracted_names` / `JSON hợp lệ`) rồi ghi **thẳng** UserDefaults, **không** phát notification: phát notification ngay trong `loadConfiguration()` sẽ tái nhập qua `onReceive` → `reloadSettings()` → `loadConfiguration()`. Cùng khuôn với `BookAIMemoryStore.loadGlobalMemory()`.
* **Luật 21 — bộ bóc tách chỉ nên có MỘT định dạng, và định dạng đó phải khớp prompt mặc định.** Bỏ 4 tầng dự phòng JSON (markdown fence → JSON trực tiếp → `[...]` → `{...}`) là **cố ý**: nhiều định dạng ⇒ prompt và parser có thể lệch nhau mà **không ai biết**, vì kết quả rỗng vẫn "không có lỗi". Đổi định dạng prompt thì phải đổi parser cùng lượt, và ngược lại. Đổi lại: model trả sai dấu phân cách (dấu hai chấm thay vì `=`) sẽ mất kết quả **im lặng** — đây là giá đã biết của luật này.

## 1.3.465 — hai luật mới (tốc độ tổng hợp & khoá cache)

* **Luật 18 — khoá cache phải mang mọi tham số làm đổi audio.** `TTSSynthesisIdentity.computeKey` là khoá của cả nạp trước lẫn cache prefix liên chương. Bất kỳ tham số nào làm audio khác đi (giọng, văn bản, ranh giới, **và tốc độ tổng hợp**) phải nằm trong khoá; thiếu thì audio cũ được trả cho yêu cầu mới — nghe sai mà **không có lỗi nào**. Thêm tham số mới thì truyền tường minh ở mọi caller, đừng tin vào default.
* **Luật 19 — `speed` của engine local là tốc độ tổng hợp, không phải tốc độ phát.** Có **4** điểm gọi local phải cùng một nguồn giá trị: `TTSManager.scheduleNghiRefill`, đường phát on-demand, `TTSNextChapterPrefixSynthesizer`, `TTSChapterPrefetcher` — sửa một chỗ mà quên ba chỗ kia là audio lẫn hai tốc độ. Hai thứ này **nhân** nhau thành tốc độ nghe. Muốn đổi hành vi thì đổi đúng chỗ: tốc độ tổng hợp = tham số truyền vào `synthesize*`; tốc độ phát = `NghiAudioPlayerQueue.updateRate`. Đổi tốc độ tổng hợp lúc đang đọc phải vô hiệu phần đệm đã tổng hợp (`invalidateVieNeuSynthesisSpeed()`), nếu không nghe lẫn hai tốc độ.


## 1.3.464 — hai quy chuẩn rút ra

* **Luật 18 — một hành động có hai nhánh ghi thì phải có đúng một đường ghi chung.** `RephoneticizeTask.apply()` (thay thế toàn bộ) và `applyMerged(_:)` (trộn) cùng đi qua `write(_:)`. Chép thành hai bản thì một bên sẽ quên bước **sao lưu** — mà đây là lượt ghi đè toàn bộ từ điển (NghiTTS ~30k mục), không có đường lùi.
* **Luật 19 — màn so khớp phải tự đọc nguồn sự thật lúc mở, đừng nhận ảnh chụp.** `DictionaryImportConflictView` nhận `currentProvider: @Sendable () async -> [String: String]` thay vì bảng chụp sẵn: bảng "cũ" của ảnh chụp có thể lỗi thời ở thời điểm người dùng bấm Áp dụng ⇒ mục bị **bỏ chọn** lại bị ghi đè bằng một giá trị cũ.

## 1.3.462 — quy chuẩn rút ra (từ điển phiên âm: hai nguồn, phiên âm lại, luồng nhập)

* **Luật 13 — `private @State` trong struct làm `init` memberwise thành `private`.** View / `ViewModifier` nào có `@State private` **và** tham số **không** có giá trị mặc định thì **phải** khai `init` tường minh, nếu không sẽ không gọi được từ file khác (hoặc từ `extension View` — vốn là type khác — trong cùng file). Trong `init`, `@Binding` gán dạng `_x = binding`; `@ObservedObject` gán dạng `_x = ObservedObject(wrappedValue:)`.
* **Luật 14 — số liệu hiện ở màn Thông báo phải nằm ở file meta JSON kèm theo, không suy lại từ file dữ liệu.** Bài học 1.3.448 (`VietPhraseMerged.txt`) lặp lại với plist từ điển: parse file lớn trên main mỗi lần render ⇒ đơ app + nghẽn TTS. Meta phải **nhỏ** (chỉ số đếm + `createdAt` + `version`), ghi atomic, ghi **sau** file dữ liệu, `loadMeta` nil-safe và **không** parse file dữ liệu để bù.
* **Luật 15 — ghi đè toàn bộ một store thì bắt buộc sao lưu trước.** Cả *Thay thế toàn bộ* (nhập file) lẫn *Nhập vào từ điển* (phiên âm lại) đều là ghi đè không có lùi. Kèm theo: `loadResources()` **không** xoá `transliterationCache` (`TextPreprocessor.swift:241-245`) nên đường ghi phải xoá cache cùng lượt — dùng `replaceAllWords`, đừng ghi plist trực tiếp. *(1.3.464: đường **nhập file** đã revert về bản gốc theo yêu cầu người dùng ⇒ **không** còn nhánh "Thay thế toàn bộ" và **không** sao lưu; luật này nay chỉ ràng buộc bước **áp kết quả phiên âm lại**, xem Luật 18.)*
* **Luật 16 — `startAccessingSecurityScopedResource()` phải sống tới khi công việc ngầm đọc file xong.** `defer` trong hàm đồng bộ sẽ nhả quyền trước khi `Task.detached` chạy.
* **Luật 17 — dedupe phải gồm NGUỒN, không chỉ giá trị.** Hai từ điển độc lập có thể cùng cách đọc; gộp theo `text` sẽ nuốt mất chip của nguồn kia. Khoá dedupe đúng là `origin.rawValue + "|" + text`.

## 1.3.456 — ba luật mới

* **Luật 10 — Giọng nhân bản luôn chạy `.high`, bất kể cài đặt người dùng.** `VieNeuSynthesisPolicy.effectiveMode(requested:current:isClonedVoice:)` trả `.high` khi `preset.isCloned`. Vòng Euler là nơi áp dụng toàn bộ điều kiện hoá (x-vector + `style`); 8 bước (`.fast`) làm âm sắc giọng clone **không bám mẫu** dù dữ liệu đưa vào đúng. Đừng "tối ưu" chỗ này.
* **Luật 11 — `@State` khởi tạo từ giá trị đã lưu PHẢI được làm mới ở `.onAppear`.** `@State` chỉ chạy default-expression **một lần** lúc View dựng; nếu nguồn là singleton chưa sẵn sàng thì rơi về mặc định và **không bao giờ** tự sửa (lỗi thật: mở màn Cài đặt TTS luôn hiện "Tiết kiệm pin: bật"). Đọc thẳng `UserDefaults` trong một hàm refresh gọi từ `.onAppear`, đừng đọc qua singleton.
* **Luật 12 — Hằng số mặc định của model phải đối chiếu tệp `config.json` thật và mã nguồn upstream, không tin comment.** Đã lấy `config.json` ở revision đã ghim: `steps_default = 16`, `cfg_default = 3,0`, `ref_max_frames = 140`, `latent_scale = 0,25`, `flow_fps = 15,625`. Cả pipeline nhân bản lẫn vòng tổng hợp của app đã đối chiếu **nguyên văn** với `v3nano.py` của upstream ⇒ **khớp hoàn toàn**; không còn chỗ lệch nào để "tinh chỉnh".


## 1.3.455 — quy chuẩn rút ra (sửa luồng nhân bản giọng)

* **Luật 10 — trạng thái nạp một lần là nguồn của lỗi im lặng.** `VieNeuTTSEngine.catalog` chỉ được nạp trong `prepareLocked` (`guard runtime == nil`), mà engine sống suốt vòng đời app ⇒ mọi thứ suy ra từ catalog (danh sách giọng, `preset(named:)`) **đóng băng** từ lượt nạp đầu. Thêm dữ liệu mới vào catalog thì **bắt buộc** thêm đường làm mới. Tệ hơn: `preset(named:) ?? defaultPreset` **không** ném lỗi ⇒ người dùng nghe sai giọng mà UI vẫn báo thành công.
* **Luật 11 — closure tiến trình qua `Task.detached` phải `@Sendable` và KHÔNG capture `self`.** Nếu nó capture `self` của một SwiftUI View thì đó là cảnh báo Sendable (lỗi ở Swift 6). Cách đúng, đã dùng ở `DictionaryMergeTask` và ở đây: capture một hộp `ObservableObject` `@unchecked Sendable` rồi `Task { @MainActor in … }`.
* **Luật 12 — trần 400 dòng đẩy sang bẫy `private` theo file.** Muốn thêm hàm cho một type ở file đã đúng trần thì phải đặt hàm ở `X+Feature.swift`, và hạ mọi thành viên nó dùng từ `private` xuống `internal`. Sửa access modifier **trên dòng đang có** thì không tăng số dòng — đây là cách duy nhất vừa giữ trần vừa thêm được hành vi.
* **Luật 13 — app cài qua LiveContainer: chọn file bằng `DocumentPickerPresenter`, đừng dùng `.fileImporter`.** `.fileImporter` của SwiftUI mở được picker nhưng **không** trả kết quả ⇒ không file, không lỗi, nút bị khoá im lặng. `DocumentPickerPresenter` (`asCopy: true`) vừa hợp môi trường đó vừa cho URL nằm sẵn trong sandbox.
* **Luật 14 — nút bị khoá phải nói vì sao.** `canSave` suy thẳng từ `saveBlockReason` để nút và dòng giải thích không thể lệch nhau.

## 1.3.453 — quy chuẩn rút ra (nhân bản giọng VieNeu)

* **Luật 1 — `groupLatent` là phép hoán vị kênh, không phải concat.** `out[c*g + slot][block] = zpad[c][block*g + slot]` với `g = 6`. Cách viết đúng là gộp nhóm rồi `transpose` rồi duỗi; cách viết **sai** (duỗi thẳng kênh liền kề) vẫn cho shape `(50, 256)` hợp lệ nên **không** có lỗi nào nổi lên — chỉ giọng khác đi. Mọi thay đổi ở đây **phải** chạy lại kiểm chứng numpy.
* **Luật 2 — ba graph clone KHÔNG được vào `requiredNames`.** `VieNeuTTSEngine.swift:151` chặn engine khi `store.missingNames` khác rỗng; thêm graph tuỳ chọn vào đó sẽ khoá luôn engine chính với người dùng chưa tải gói clone.
* **Luật 3 — `.m` / `.h` không bị `check_architecture.py` kiểm.** Cầu C vượt trần 400 dòng một cách hợp lệ, nhưng đổi lại **không** có cổng tự động nào phủ nó: phải tự kiểm bằng `cl.exe` (MSVC BuildTools 18 + Windows SDK có sẵn trên máy Windows). Đừng suy ra "biên dịch được" từ việc script kiến trúc xanh.
* **Luật 4 — đổi kiểu con trỏ trong cầu C là thay đổi phá vỡ âm thầm.** `copyFloatsInto` giữ `int32_t *outCount`; đổi sang `int64_t *` khiến hai caller cũ ghi **8 byte vào ô 4 byte**. Trình biên dịch **có** bắt (`warning C4133`), nhưng chỉ khi thực sự build — mà trên Windows thì không build được.
* **Luật 5 — mọi đường chạm `AVAudioSession` phải trả về `.playback`.** `TTSAudioSessionController.configureAudioSession()` là **nguồn sự thật duy nhất**; không tự `setCategory` lại ở chỗ khác, kể cả trong nhánh lỗi.
* **Luật 6 — màn thư viện giọng dùng `Button` trần + `Label`, không `.borderedProminent`.** `MainTabView` đặt `.tint(.white)` toàn cục ⇒ `.borderedProminent` không tự đảo màu chữ ⇒ nút rỗng (bài học 1.3.447).
* **Luật 7 — `VieNeuCustomVoiceStore.init` không được chạm đĩa.** Nó được gọi trên **đường đọc** (`VieNeuVoiceCatalog.load` ← `VieNeuTTSEngine.prepareLocked`); tạo thư mục trong `init` nghĩa là ghi đĩa mỗi lượt tổng hợp.
* **Luật 8 — không route file của người dùng qua `VieNeuModelStore.url(for:)`.** Kho model là không gian của gói tải về; audio mẫu có vòng đời và quyền truy cập riêng (`CustomVoices/samples/`).
* **Luật 9 — hằng `NS_TYPED_ENUM` của AVFoundation là biến toàn cục kiểu `String`, KHÔNG phải case enum.** `AVAudioConverter.sampleRateConverterAlgorithm` có kiểu `String?`, còn tên `AVSampleRateConverterAlgorithm` **không tồn tại** trong Swift — nên `AVSampleRateConverterAlgorithm.mastering` là lỗi biên dịch `cannot find 'AVSampleRateConverterAlgorithm' in scope`. Viết đúng: `AVSampleRateConverterAlgorithm_Mastering`. Đã cắn một vòng CI (1.3.454). Máy Windows không có SDK để đối chiếu ⇒ **tra Apple docs JSON** (`developer.apple.com/tutorials/data/documentation/…json`, trường `fragments`) trước khi dùng API AVFoundation chưa có tiền lệ trong repo, đừng suy từ tên kiểu.


## 1.3.446 — quy chuẩn rút ra

* **`private` là theo FILE, không theo type** — đã cắn lần thứ ba (1.3.445: `mergeTask`; 1.3.446: `ReplacementStep`/`planLock`/`compile`, `ruleRow`, `alertMessage`, `prepareToEdit`). Khi tách `X+Feature.swift`, phải rà **mọi** thành viên mà file mới dùng và hạ `private` → `internal`, kèm comment nêu lý do.
* **Tham số mới nên có default** khi thêm vào hàm đang có nhiều call site: `applyReplacements(to:bookId: String? = nil)` giữ 8 call site biên dịch được ngay, nhưng **default đó là bẫy** — code cũ biên dịch im lặng mà thiếu tầng riêng. Bù lại bằng cách grep lại **toàn bộ** call site sau khi sửa.
* **File ở sát trần thì mọi tính năng mới đều phải tách file** — 3 file mới trong lượt này tồn tại chỉ vì `TTSReplacementManager.swift` 391/400 và `TTSReplacementManagerView.swift` 390/400. `ReaderView.swift` ở **đúng** baseline ⇒ closure phải nằm ở `ReaderView+RuleTools.swift`; đây là lần `check_architecture.py` bắt được một violation mới (`2060 > 2053`) ngay sau khi thêm closure.
* **Danh sách file riêng truyện phải khai theo kiểu nội dung**: TXT (`key=value`) đi một danh sách, JSON đi danh sách khác — gộp chung là vòng khôi phục ghi đè sai định dạng và phá dữ liệu (`BackupPaths.swift:42-45`).
* **Nguồn sự thật là file trên đĩa**: mọi lối ghi thẳng vào file (khôi phục backup, đổi nguồn) **bắt buộc** gọi `loadRules(bookId:)` sau đó, nếu không cache RAM cũ vẫn thắng và không có gì báo.


## 1.3.444 — quy chuẩn rút ra

* **Trần dòng là ràng buộc thật**: `QuickTranslationRuleEngine.swift` ở **399/400** và **không** có trong `architecture_allowlist.json` ⇒ thêm một `private static func` là tạo violation mới. Helper mới phải đặt ở file `+Extension`.
* **Màn thử phải đi cùng đường với đường thật**: một màn test tự dựng pipeline riêng sẽ đo một thứ khác với thứ người dùng chạy. Ba bước phải trùng: thay thế ký tự (`applyReplacements`), cắt đoạn (`NghiUtteranceSegmenter` + `chunkLength`), và `boundaryKind` của từng đoạn.
* **Đọc đúng khoá của engine**: `TTSManager.shared.chunkLength` thuộc **engine đang chọn**; muốn con số của một engine cụ thể thì đọc khoá `vieneu*`/`nghitts*` tương ứng (đã áp ở `vieNeuChunkLength`).
* **Ghép file nhị phân phải kiểm khuôn trước khi ghép**: `WAVConcatenator` trả `nil` thay vì ghép mù.


## Rules UI Pin & Mặc Định VieNeu (1.3.442)

* **"Tiết kiệm pin" là một overlay, không ghi đè lựa chọn người dùng.** Default = **BẬT**. ON ⇒ `engine.setRequestedMode(.fast)` + `effectiveThreadCount` = 2 (khoá 2 picker); OFF ⇒ `setRequestedMode(nil)` ("Tự động"). Dùng `VieNeuSynthesisPolicy.effectiveThreadCount(from:)`, đừng nhân đôi logic ở UI.
* **Số luồng ORT chỉ có hiệu lực sau khi NẠP LẠI engine** (session dựng một lần) — UI phải ghi rõ điều này.
* **Nhãn mode** (`VieNeuTTSTestView+Sections.swift` `displayName`): **Tự động / Chất lượng cao / Cân bằng** — đổi ở một chỗ, cả màn Cài đặt lẫn màn thử giọng theo.
* **Nhiệt là bài toán SỐ BƯỚC, không phải độ lớn CFG (1.3.449).** `runChunk` hỏi `if tuning.cfg > 0` — điều kiện **nhị phân**, nên `cfg = 3.0 → 1.5` tiết kiệm **0%**; chỉ số bước mới đổi chi phí. Mỗi bước gọi `vector_estimator` **2 lần** khi có CFG: `.high` 32 lượt/đoạn, `.fast` 16. Đừng đề xuất "giảm CFG một phần" — đã kiểm và nó vô ích.
* **SÀN của `steps` là 8 — đừng thử 4/5/6/7 (1.3.450).** Mode 4 bước (`.low`) đã thử và **bỏ hẳn**: sai số tích phân vòng Euler quá lớn, người dùng nghe báo "âm thanh quá kém, không rõ tiếng"; giữ CFG **không bù được**. Chỉ còn `high`/`fast`. Đừng khôi phục `.low` trừ khi có bằng chứng nghe mới.
* **Thêm case vào `Mode` gần như miễn phí ở UI, nhưng có 2 chỗ `switch` buộc sửa.** Hai Picker dùng `ForEach(Mode.allCases)` nên tự có dòng mới; nhưng `tuning(for:)` **và** `nextMode(current:…)` trong policy đều không có `default` ⇒ trình biên dịch bắt lỗi nếu quên. Cộng thêm `displayName` ở tầng View. `VieNeuTTSEngine.swift` **không cần đụng** (đang đúng trần 400/400).
* **Tương thích `UserDefaults` cũ**: `Mode(rawValue:)` trả `nil` cho `"turbo"` và `"low"` ⇒ tự rơi về "tự động", không cần migrate.
* **Pre-schedule machinery đã gỡ hẳn** (1.3.442): đừng thêm lại `play(atTime:)`/`.scheduled` cho đường local.

## Rules Pre-schedule, Pin & Log (1.3.441)

* **Never pre-schedule the next local segment with `AVAudioPlayer.play(atTime:)`.** `duration`/`deviceCurrentTime` are estimates; an early `startTime` overlaps the tail of the current segment → chồng tiếng + "nói lắp" at chunk boundaries (e.g. "chân" | "tướng" → "chân chân tướng"). Hand off via the `audioPlayerDidFinishPlaying` delegate instead. `NghiAudioPlayerQueue` 368 → 324 lines.
* **VieNeu defaults now bias to `fast`** (16 → 8 Euler steps, ~2× less compute ⇒ cooler/less battery, lower quality): engine `mode` starts at `.fast`, `upshiftRTF` 0.30. The opt-in "Tiết kiệm pin" toggle forces `fast` + 2 ORT threads. `threadCount` only takes effect on the **next engine load**.
* **`VieNeuSynthesisPolicy` stays pure** — settings helpers take `UserDefaults` as a parameter (`threadCount(from:)`), never read the global directly.

## Rules Nạp Trước & Generation (1.3.440)

* **A per-schedule generation bump breaks a concurrent pool.** `nghiRefillGeneration` must be bumped ONLY on context change (`cancelNghiRefill`), never inside `scheduleNghiRefill`. The guard `isValidNghiRefillContext` requires **exact** equality, so bumping per schedule invalidates every sibling task in the same `fillNghiRefillUpToCapacity` batch (only the last survives) AND leaks them (the `defer` only cleans when the generation matches), slowly wedging the pool. Introduced with the pool in 1.3.438, fixed in 1.3.440.
* **Symptom to remember:** prefetch pool "works" but the buffer never builds at cold start → gaps at playback start and chapter boundaries. If a `fill...UpToCapacity` batch only ever warms 1 segment, suspect a generation/epoch guard invalidating siblings.

## Rules Số, Đệm Nóng & Tốc Độ (1.3.439)

* **Speed is a playback-only parameter — never let it drive synthesis.** On-device engines synthesise at `speed: 1.0` and apply the user's speed at playback (`nghiAudioPlayerQueue.updateRate`). So `speed.didSet → updatePlaybackParams()` must **not** call `updateNghiPrefetchWindow()` / `cancelNghiWakeTask()`: that re-triggers refill + next-chapter prefetch on every slider tick for nothing. Verified across all four engines — none re-synthesises current audio on a speed change (system = per-utterance; google hardcodes `speed: 1.0`; extension key excludes speed).
* **Warm the first segments at every playback start, not just mid-chapter.** `continueStartSpeaking` is the single entry for both fresh start and chapter handoff — call `warmNghiRefillForPlaybackStart()` there so `N+1..N+3` synthesise in parallel with the current (cold) first segment. Otherwise the first transition(s) underrun and the chapter-title → first-paragraph boundary gaps.
* **A leading-zero rule belongs in `processDigits`, never in `VietnameseNumberSpeller.spell`.** `processDates`/`processTime` call `spell("01")` for day/month; putting the "001 → không không một" rule in `spell` would read `"01/02"` as "không một tháng hai". Keep it on the standalone-number path.
* **`TextPreprocessor.swift` sits exactly on its 1121-line baseline — never grow it.** The 1.3.439 number fix was written net-negative (1120) by collapsing `cleanedR`/`rightSpelled` into one line and using a one-line ternary. Always `wc -l` after editing a baselined file.

## Nạp Trước Đồng Thời Cho VieNeu + Safe-Window 150 ms (1.3.438)

* **Sửa đoạn ngắn VieNeu bị đứt**: `updateNghiPrefetchWindow` trước đây chỉ nạp **1** đoạn rồi `return` (`canScheduleNghiRefill` cấm lượt thứ hai bay cùng lúc). VieNeu tổng hợp đắt (RTF ~0,3 + chi phí cố định theo chunk; `VieNeuSynthesisPolicy.bufferedSecondsTarget = 12`) nên đoạn ngắn không kịp tổng hợp trước khi đoạn đang phát kết thúc. Đổi sang **pool đồng thời** (`nghiRefillTasks: [Int: Task]` + `nghiRefillInFlightIndices: Set<Int>`) và `fillNghiRefillUpToCapacity()`; `nghiRefillCandidate` bước qua index đang bay. NghiTTS giữ 1 luồng.
* **`maxConcurrentNghiRefills`**: 3 cho `vieneu`, 1 cho `nghitts`. Code mới nằm ở `Sources/Services/TTS/TTSManager+NghiPrefetchConcurrency.swift` (ratchet-down).
* **Ngưỡng đệm mặc định VieNeu 8 → 12 s**; optional reserve VieNeu **4** (NghiTTS giữ 2).
* **Safe-window chồng tiếng 50 → 150 ms** (`NghiAudioPlayerQueue`): `AVAudioPlayer.duration` ước lượng ngắn hơn thực tế vài ms ⇒ `startTime` sát đích dễ rơi trước khi đoạn hiện tại kết thúc.

## Đo Lường Mù Là Rủi Ro, Không Phải Chi Tiết Nhỏ (1.3.436)

* **Nếu một đường chạy không có instrumentation, mọi câu hỏi về chất lượng của nó là không trả lời được.** Người dùng hỏi *"vì sao chất lượng kém hơn hẳn màn thử giọng"*, nhưng màn thử giọng hiện mode/chunk/dropped **trên UI** còn đường Reader **không có gì**: engine chỉ log **lúc đổi** chế độ và **một lần cho cả vòng đời** cho phoneme bị bỏ (`droppedScalarWarningShown`). `logSynthesisPerf` ghi mỗi lượt (mode, chunks, dropped, chars, pcm, speech, synth, rtf, boundary). **Viết instrumentation trước khi hỏi người dùng mô tả chất lượng âm thanh lần nữa.**
* **Đừng đoán nguyên nhân của một lỗi phụ thuộc thời điểm.** Triệu chứng *"đoạn này chưa đọc xong thì đoạn khác đã đọc song song"* nằm trong cơ chế `play(atTime:)` + `deviceCurrentTime` của `NghiAudioPlayerQueue` — đọc mã **không** phân định được. Lượt 1.3.436 **cố ý không đổi hành vi**: thêm log `wallRemaining`/`duration`/`currentTime` (đủ để thấy phép tính thời gian có sai không) và một chốt an toàn hẹp, rồi **xin log từ máy thật**. Sửa mò trong mã nhạy thời điểm sẽ tạo lỗi mới khó tìm hơn lỗi cũ.
* **Một tham số có trong chữ ký mà không được dùng là bẫy.** `boundaryKind` khiến `VieNeuTTSService` trông tương thích với `LocalTTSEngine` trong khi **thiếu hẳn** hành vi khoảng lặng đuôi mà Piper có. Khi port một engine sang một protocol chung, phải đối chiếu **từng tham số** xem engine gốc dùng nó thế nào — không chỉ khớp chữ ký cho biên dịch được.
* **`LocalTTSEngine.synthesizeStream` has NO `boundaryKind` parameter — do not reference one there.** `TTSBoundaryKind` is only on `synthesize`/`synthesizeWithDuration`; the protocol deliberately omits it from the streaming entry point (`LocalTTSEngine.swift:43-51`). Threading `boundaryKind` through `VieNeuTTSService` in 1.3.436 almost shipped a compile error by passing the variable inside `synthesizeStream`, where it does not exist. That path is documented as "one chunk for the whole paragraph", so it uses the literal `.paragraphEnd`. **When threading a new parameter through an engine, check the protocol signature for each entry point separately — the same parameter may be absent from one of them.**
* **Trần 400 dòng: đặt log vào file extension, không vào file engine.** `logSynthesisPerf` nằm ở `VieNeuTTSEngine+Adaptive.swift` để `VieNeuTTSEngine.swift` ở **395/400**; thêm trực tiếp vào file engine đã đẩy nó lên 399 với 0 dòng dự phòng.

## VieNeu Boundary Pause & Per-Engine UI State (1.3.436)

* **Every on-device engine must honour `boundaryKind`, or consecutive utterances collide.** `ONNXPiperEngine` appends a trailing pause derived from `boundaryKind` (`pauseDuration(for:)`, used at `:436`). `VieNeuTTSService` accepted `boundaryKind` in its signature **and never used it**, so a Reader that pre-splits a paragraph into utterances produced payloads with **no silence between them** — and each payload had already been edge-trimmed by `trimAndFade` down to a ~40 ms pad. The user heard this as **"mất chữ"** (words swallowed). `VieNeuTTSEngine.pauseSeconds(for boundaryKind:)` now mirrors Piper's mapping **on the same `UserDefaults` keys**, so one setting drives both engines. **Note `joinChunks` only inserts gaps *between* internal chunks — it never pads the last one**, so the trailing pause cannot come from the chunker.
* **Added trailing silence is not speech — add it to the "inserted pause" accumulator.** Otherwise `speechDuration` (the basis for the honest RTF) is inflated and every downstream RTF number is wrong. Same class of bug as the earlier double-counted `vectorMs`.
* **`boundaryKind` belongs in the synthesis cache key.** It changes the audio, so two calls with identical text but different boundaries must not coalesce — `PiperSynthesisCoordinator` coalesces by key, and Piper already puts `boundary=` in its key.
* **A `Picker` bound to a `Binding` that reads a non-`@Observable` service will not update — hold the selection in `@State`.** This is the *second* time this exact bug appeared (`VieNeuTTSTestView` in 1.3.421, `TTSSettingsView.vieNeuReaderSection` in 1.3.436). `VieNeuTTSService.preferredMode`'s setter *does* call `engine.setRequestedMode(...)`, so the engine was always correct — only the UI was stale. **Whenever a control binds to `VieNeuTTSService`/any plain service, stop and use `@State` + `.onChange`.**
* **When the Reader path has no instrumentation, "why is quality worse than the test screen" is unanswerable.** The test screen renders mode/chunk/dropped on screen; the engine only logged mode *changes* and dropped phonemes **once per engine lifetime** (`droppedScalarWarningShown`). `logSynthesisPerf` now emits mode, chunk count, dropped scalars, char count, pcm/speech duration, synthesis ms, RTF and boundary **per synthesis**. **Put the instrumentation in before asking the user to describe audio quality again.**
* **Two layers of chunking is a smell — check `maxChunkCharacters` before pre-splitting.** `VieNeuConfig.maxChunkCharacters` is **140** and the engine packs whole sentences; the Reader *also* pre-splits at `vieneuChunk` (default 200) via `NghiUtteranceSegmenter`. Splitting above the engine's own limit only adds boundaries (and, before the boundary-pause fix, trimmed edges). Suspect double-splitting whenever quality differs between the one-shot test screen and the Reader.

## `prefetchDelayMs` và `chunkLength` — Hai Câu Hỏi Người Dùng Hay Đặt (1.3.435)

* **`prefetchDelayMs` ("Thời gian dãn tiến trình nạp trước") KHÔNG dùng cho engine local.** Nó chỉ được tiêu thụ ở `TTSAudioSynthesisWorker.synthesizeParagraph` (`delayStepMs = max(300, prefetchDelayMs)`, `Task.sleep(offset * delayStepMs)`) — đường của **Google và extension**. `TTSNextChapterPrefixSynthesizer.one` trả sớm cho engine local bằng `localService.synthesize(...)` **không truyền** `prefetchDelayMs`. Stepper này nay **ẩn với engine local** (trước đó nó vẫn hiện cho cả NghiTTS và VieNeu, tức đã chết với NghiTTS từ trước).
* **`chunkLength` ("Độ dài đoạn văn") CÓ dùng cho mọi engine local.** `TTSManager.playbackParagraphs` (`:801-803`) cho cả `nghitts` và `vieneu` đi qua `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)`, và `chunkLength` nằm trong `TTSPreparedNextChapterKey` nên đổi nó là huỷ dữ liệu nạp trước. **Hệ quả bắt buộc**: mọi nơi dựng lại cùng danh sách đoạn văn phải expand **y hệt** — `nextChapterPrefixContext()` đã phải sửa vì lý do này, nếu không chỉ số đoạn văn giữa chương hiện tại và prefix chương kế **lệch nhau**.
* **Nhãn UI phải nói đúng engine.** `chunkLength` của VieNeu từng hiện dưới nhãn *"Độ dài đoạn văn (Extension TTS)"* vì VieNeu rơi vào nhánh `else` của Section 5 (nhánh extension). Khi một engine mới xuất hiện, mọi `Section` phân nhánh theo `tool` đều phải được rà — **một `else` không có nhánh riêng sẽ âm thầm nhận engine mới và gắn nhãn sai cho nó**.

## TTS Local-Engine Playback Invariants (1.3.435)

* **A playback identity check that ends in `self.tool == "nghitts"` silently discards synthesized audio.** `playNghiTTS` synthesizes through `service.synthesizeWithDuration(...)` and *then* calls `guard isIdentityValid() else { return }`. Because `isIdentityValid()` ended in `self.tool == "nghitts"`, a second local engine paid the full synthesis cost and then **threw the result away** — no log, no error, no toast. The only evidence was the *absence* of the `[TTSRoute] playAudioData` line while `[NghiEnergy] Underrun` proved the function had been entered. **Symptom to remember: "engine produces no audio and no error, but synthesis time is spent" = an identity/context guard, not a synthesis failure.**
* **`isContextValid` compares `tool == context.engine`, so every `makePlaybackContext(..., engine:)` must pass `tool`, never a literal.** Two sites hardcoded `engine: "nghitts"`; with a second local engine the comparison was always false and every handoff was cancelled. Grep `engine: "` — the convention everywhere else is `engine: key.tool` / `engine: tool`.
* **`prefetchDelayMs` is remote-only — do not offer it for on-device engines.** `TTSNextChapterPrefixSynthesizer.one` returns early for local engines with a direct `localService.synthesize(...)` that never receives `prefetchDelayMs`; only the Google and extension paths go through `TTSAudioSynthesisWorker`'s `Task.sleep(offset * delayStepMs)`. The settings Stepper is now hidden for local engines. (It was already dead for NghiTTS before this change.)
* **`chunkLength` *is* used by every local engine — it is not Piper-only.** `TTSManager.playbackParagraphs` sends both `nghitts` and `vieneu` through `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)`. Any code path that builds the *same* paragraph list must expand identically, or indices diverge: `nextChapterPrefixContext()` had to be changed for exactly this reason.
* **The "negated three-way engine predicate" bug has now appeared in three shapes.** `tool != "system" && tool != "nghitts" && tool != "google"` appeared in 6 places (1.3.433), as `if tool == "system" || tool == "nghitts" || tool == "google"` in `TTSManager+TranslationIdentity.swift:8` (1.3.435), and as the `else` branch of `loadParamsForCurrentTool()` / the `if/else` chain in `TTSManager.init`. Each one silently routes a new engine into the *extension* branch. **When adding an engine, grep for every list of engine names, not just the predicate you already know about.**
* **`TTSManager.init` loads params before `super.init()` (`:953`), so it cannot call instance methods.** The param chain there is also missing the `vieneu` branch. The fix is one line in `initialize(container:)` calling `applyVieNeuParamsIfNeeded()` — reuse the single source of truth instead of copying the key list a third time.
* **Never hardcode the engine name in a synthesis cache key.** `TTSSynthesisIdentity.computeKey(engine:)` was given `"nghitts"` at two sites, so a second local engine produced **identical** keys for the same chapter/paragraph/voice, and `PiperSynthesisCoordinator` coalesces in-flight requests by that key. Always pass `tool`.
* **A `static func` on a `@MainActor` class is itself actor-isolated — mark pure helpers `nonisolated`.** `TTSManager` is `@MainActor`, so `isLocalEngine`/`isExtensionTool` inherited that isolation and every call from a `nonisolated` context (e.g. `TTSNextChapterPrefixSynthesizer`, a plain `enum` documented as running off the main actor) failed CI with *"expression is 'async' but is not marked with 'await'"* at `TTSNextChapterPrefixSynthesizer.swift:23`. These predicates only compare a `String`, so they are now `nonisolated static func`. **Rule: a pure static helper on a `@MainActor` type must be explicitly `nonisolated`; otherwise every non-MainActor call site needs `await`, and forgetting one is a compile error that only shows up in CI.**
* **`--accept` on `validate_links.py` takes one doc per invocation.** Loop over the files; a second `--accept` for an already-accepted doc reports "vùng GENERATED không đổi".

## TTS Engine Routing Invariants (1.3.434)

* **`isLocalEngine` and `isExtensionTool` answer two different questions — never merge them.** `TTSManager.isExtensionTool(_:)` = *"is this a user-supplied extension package?"* (`tool != "system" && tool != "nghitts" && tool != "google" && tool != "vieneu"`). `TTSManager.isLocalEngine(_:)` = *"does this engine run on-device and share NghiTTS's playback path?"* (`tool == "nghitts" || tool == "vieneu"`). A new built-in engine must be added to **both** lists, and the symptom of forgetting `isLocalEngine` is **silence** while the symptom of forgetting `isExtensionTool` is **extension-flavoured UI**. Ask *"Piper specifically?"* with a literal `== "nghitts"` — the confirmed Piper-only case is the `nghittsPrefetchDelay` **key** in the `prefetchDelayMs` `didSet` (writing VieNeu's fixed 500 ms there would clobber the user's NghiTTS setting). Note that `NghiUtteranceSegmenter` is **not** Piper-only: `TTSManager.playbackParagraphs` (`:801-803`) deliberately sends `vieneu` through `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength: chunkLength)` too, so VieNeu **does** need `chunkLength` loaded.
* **An on-device engine must be routed to `playNghiAudioData`, or it plays through the wrong player.** `playAudioData` picks `playNghiAudioData` for `isLocalEngine(tool)` and the shared `AVAudioPlayer` otherwise. `updatePlaybackParams()` only ever sets rate on `nghiAudioPlayerQueue` for those engines, so an on-device engine sent down the `AVAudioPlayer` branch gets **no rate and no audio** — no error is raised. This was the actual cause of *"chọn VieNeu không tạo ra được âm thanh"*.
* **`pitch` is a no-op for every on-device engine.** `NghiAudioPlayerQueue` exposes `updateRate(_:)` only (clamped 0.5…2.0); `AVAudioUnitTimePitch` is configured solely by `setupAudioEngine()` → `TTSAudioEngineController.configureEngine(speed:pitch:)`, which serves the `AVAudioEngine` path. So `nghittsPitch`/`vieneuPitch` are stored and loaded but never audible. Do not advertise a working pitch control for these engines until pitch is actually added to the queue.
* **The final `else` of `loadParamsForCurrentTool()` is the extension branch, and it overwrites anything a helper loaded.** It calls `applyVieNeuParamsIfNeeded()` on its first line and then immediately reassigns `self.speed`/`self.pitch`/`self.selectedVoice` from `extRate_<tool>`/`extPitch_<tool>`/`extVoice_<tool>`. Any engine routed there gets its own loader silently discarded. **A new engine needs its own `else if` branch**, and the check is *"does the old `else` still swallow my engine?"* — not *"did I add my branch?"*.
* **Never write a value under one `UserDefaults` key and read it under another.** `selectedVoice.didSet` wrote `extVoice_vieneu` while `applyVieNeuParamsIfNeeded()` read `vieneuVoice`, so the chosen voice was forgotten on every engine switch. Whenever a per-engine key is introduced, grep **both** directions for it.
* **Per-engine `UserDefaults` keys are separate on purpose — do not "unify" them.** VieNeu needs a deeper buffer than Piper (`VieNeuSynthesisPolicy.bufferedSecondsTarget` = 12 s vs 8 s) and has a different RTF, so one shared threshold is wrong for both. `nghitts*` and `vieneu*` stay apart (`vieneuVoice`, `vieneuRate`, `vieneuPitch`, `vieneuChunk`, `vieneuPrefetchCount`, `vieneuSafeCachedTimeThreshold`, `vieneuPreferredMode`); only the *pause* durations (`paragraphPauseDuration` etc.) are deliberately shared because those are content, not performance. **But a separate key is not the same as a working setting** — see the next invariant.
* **`TTSManager.swift` is pinned at 4029 lines against a 3470 baseline — extend it with `didSet` helpers in an extension, not inline.** Three `if/else` chains inside the `speed`/`pitch`/`selectedVoice` `didSet`s were collapsed into `persistSpeed(_:)`/`persistPitch(_:)`/`persistVoice(_:)` in `TTSManager+VieNeu.swift`, so a new engine now costs **one `case` line** in the extension instead of ~2 lines in the legacy file. The same trick let 1.3.434 add a whole engine plus five keys at **net 0 lines**. Extensions cannot add stored properties, so a new *setting* still needs its declaration in the legacy file (or a `Binding` built in the extension, as `vieNeuModeBinding` does).
* **The NghiTTS refill / wake-window machinery is still gated on `tool == "nghitts"` in ~15 places, so a second local engine gets no paragraph-level refill.** The gates live in `updateNghiPrefetchWindow` (`:2652`), `prepareNextNghiAudioIfPossible` (`:3252`), `calculateNghiCachedTime` (`:2596`), `handleNghiAudioFinished` (`:3362`), `startPrefetchTask(for:)` (`:2991`) and `handleNghiScheduledHandoff` (`:3194`). Two consequences: (1) `calculateNghiCachedTime()` returns **0.0** for anything but `nghitts`, so a per-engine "safe cached time" threshold is **never read** — the consumers (`TTSManager+NextChapterPrefix.swift:73`, `TTSManager.swift:2674`, `:2714`) all read `nghittsSafeCachedTimeThreshold` from inside gated code; (2) `currentPrefetchCount`'s only consumer is `updatePrefetchWindow()` (`:2488`), the **remote** path. **A per-engine threshold/prefetch setting therefore persists correctly but has no runtime effect until these gates are widened — do not advertise it as working.** Widening them is the next increment and must be done deliberately: these gates operate on `nghiAudioPlayerQueue`, which the second local engine *does* use, so they look like Piper-era leftovers rather than intentional Piper-only behaviour — but that has to be verified at runtime, not assumed.
* **`TTSSettingsView.swift` has a 519-line baseline and only 2 lines of headroom left (517).** The per-engine "quản lý riêng của trình đọc" block lives in `TTSSettingsView+VieNeu.swift`; when headroom runs out, fold `Image`+`Text` pairs into `Label` or move the section out — do not raise the baseline.
## `sea_g2p.bin` Format Invariants (1.3.421)

* **The string blob starts at byte 48 (v2), not 32.** `write_bin_v2` writes `SEAP` + `u32 version` + 3 counts + 3 positions + `u32 sectionCount` + `u32 sectionsPos` + 8 reserved = **48 bytes** before the NUL-terminated string blob. The ported `SeaG2P.swift` hardcoded `32 + offset` (the v1 header size), so every string it read was the *tail of the previous string plus the head of the next* — the G2P returned garbage phonemes while shapes, tensors and audio length all looked correct, which is why the symptom was "the audio isn't Vietnamese" rather than an error. `stringBase` is now read from the version field (v2 → 48, v1 → 32). Verified against the real 62.829.820-byte file: base 48 resolves `xin → sˈin`, `chào → tʃˈaː2w`, `việt → vˈiɛ6t̪`; base 32 resolves **nothing**.
* **Binary search over the tables must compare in UTF-8 byte order.** `write_bin_v2` sorts with `sorted(..., key=lambda kv: kv[0].encode("utf-8"))`, i.e. byte order. Swift's `String.<` uses Unicode canonical ordering, which is not guaranteed to agree, so a lookup can miss a key that *is* present. `SeaG2P.utf8Less` uses `lhs.utf8.lexicographicallyPrecedes(rhs.utf8)` (no allocation).
* **Never split a word across chunks.** The first `splitIntoChunks` cut at exactly `limit` characters, so a word straddling the boundary was phonemized as two fragments: `trở` → `t` + `rở`, `Potter` → `Po` + `tter`. Fragments are not dictionary words, so they fell into `charFallback` and were read as **Vietnamese letter names** — heard as "thê giở" and "pô ti tờ". The splitter now packs whole words (`split(separator: " ")`) and only hard-cuts a single word longer than the limit. **Symptom to remember: a few isolated words mispronounced in an otherwise correct sentence = chunk boundary, not a dictionary miss.** `Output.chunkCount` is reported in the test screen so this is visible next time.
* **The vocab is per Unicode scalar, and `SeaG2P` emits combining marks as separate scalars.** `việt` → `vˈiɛ6t̪` contains U+032A as its own scalar; encoding must iterate `unicodeScalars`, never Swift `Character`s.
* **Measured result for VieNeu on device — the Euler loop is 98% of synthesis time.** `Timing` reported `vector 7.60 s | khác 0.14 s` for 28.01 s of audio. Two consequences worth remembering: (1) per-chunk fixed cost (text_encoder + duration_predictor + codec_decoder) is negligible, so **reducing the chunk count buys nothing**; (2) raising `threadCount` 2 to 4 did help — `RTF thật` 0.37 to **0.29** — so 4 is kept. The remaining levers are only steps (8 is the documented floor) and CFG (turning it off was heard as unusable). **This engine is close to its practical floor.**
* **The reference does NOT level-match chunks — this is a deliberate extension.** `join_audio_chunks` keeps each chunk's audio untouched and only pads zeros; there is no `normalize`/`peak`/`rms`/`gain` helper anywhere in `core_utils.py`. So a level step between chunks is **inherent to the reference**, not a porting bug — but the user hears it as *"chỗ đến năm giảm âm lượng đột ngột"* at a chunk boundary inside a long number run. `joinChunks` now pulls every chunk toward the **median** chunk RMS, clamped to **[0.6 … 1.6]** (±4 dB). The clamp is the point: it flattens only the arbitrary variation from generating chunks independently, and leaves meaningful dynamics (whispers, emphasis) alone. Recorded here as an extension so nobody later "fixes" it back to match the reference.
* **`VieNeuTTSEngine+Audio.swift` hit 432 lines and had to be split by concern.** The natural seam is *text* vs *samples*: chunking (sentence packing, guards, `Chunk`/`Gap`, gap classification) moved to `VieNeuTTSEngine+Chunking.swift`; DSP (`timeGrid`, noise, `joinChunks`, `trimAndFade`, `edgeSilence`) stayed in `+Audio`. Both under 400 again.
* **Number-introducer words also block a cut.** The reference blocks a cut only *between two number words*, so `tháng | sáu` slips through — and the user heard exactly that ("chỗ đọc số ngắt nghỉ chưa hay"). `numberIntroducers` (tháng ngày giờ phút giây tuổi khoảng độ số trang chương phần quyển tập mục điều quãng hồi chặng) blocks a cut right after them when the next word is a number. Verified: old guard gives `…từ khoảng tháng | nghìn chín trăm…`, new guard gives `…từ khoảng | nghìn chín trăm…`. This **extends** the reference, but the reference itself notes that over-blocking beats splitting a year, so it follows its intent rather than diverging.
* **Measure before optimizing, and make the measurement unable to double-count.** When the user reports "synthesis too slow", the first move is a **breakdown**, not a change. `VieNeuTTSEngine.Timing` accumulates `vectorMs` (the Euler loop) and `otherMs` (everything else in a chunk). The first version of that instrumentation used two `defer` blocks — the outer one measured the whole chunk *including* the loop, so the vector time was counted **twice**. Correct form: time the loop explicitly, then `otherMs += max(0, chunkMs - vectorMs)`. A wrong measurement is worse than no measurement because it sends the next change in the wrong direction.
* **Diagnostics that only show the first unit are useless.** The phoneme sample printed chunk 0 only, so the user could not see which of 6 chunks was mispronounced — exactly the thing they needed. It now prints **one line per chunk** (`[0] …`, `[1] …`).
* **Nested types can live in an extension file, and should when the main file gets tight.** `VieNeuTTSEngine` hit **399/400** lines after adding instrumentation; moving `Chunk`/`Gap` to `+Audio.swift` and `Timing` to `+Adaptive.swift` brought it to 370. Prefer moving the *types* (they are self-contained) over moving methods that touch private state.
* **Never split a number across chunks, and never cut inside a connector pair.** The reference carries three tables for exactly this: `_NUMBER_WORDS` (không một mốt hai ba bốn tư năm lăm sáu bảy tám chín mười mươi trăm nghìn ngàn triệu tỷ tỉ linh lẻ phẩy chấm), `_CONN_WORDS` (và nhưng hoặc song rồi nên vì nếu khi để do bởi) and `_CONN_PAIRS` (sau khi, trước khi, cho nên, bởi vì, tuy nhiên, …). `_balanced_cut` accepts a cut only if it is not inside a pair and not between two number words; the final fallback walks back out of a pair. Without them the reader splits "…hai nghìn | không trăm ba mươi mốt" and the user hears **"ngắt nghỉ bất thường khi đang đọc số"**. Verified: 262-char text → 3 pieces 85/90/85, 0 number splits, 0 pair splits, concatenation identical.
* **`_split_long_part` divides EVENLY, it is not greedy.** `k = ceil(rest / max_chars)` pieces, each targeting `rest / k`; the docstring records why greedy was abandoned — it left a 304-char part as 251 + 53 and the "near the ceiling" cut landed on bad spots. `min_left = max_chars // 3` gates connector-word cuts (a natural cut must still leave a real clause).
* **RTF must be reported against speech, not against audio-with-pauses.** Inserted inter-chunk silence costs no inference but inflates `pcmDuration`, so `synthesisMs / pcmDuration` is **falsely low** — and the more chunks, the more falsely low. `Output.speechDuration` (audio minus inserted pauses) is reported alongside, and the test screen shows both.
* **Chunk by SENTENCE, never by word or character — port `pack_sentences_into_chunks`.** The reference is `normalize_to_chunks_v3_with_gaps` → `pack_sentences_into_chunks(sentences, max_chars)`: split paragraphs on `\n`, split sentences with `RE_SENTENCE_FINDALL = r'[^.!?]+[.!?]*|[.!?]+'`, then greedily pack **whole sentences**. Only a single sentence longer than the ceiling may be split, and then **first at minor punctuation** (`RE_MINOR_PUNCT = r'(?<=[,;:\-–—])\s+'`) and only after that by words. A word-based chunker (the 1.3.424 attempt) fixed split *words* but still cut **mid-sentence**, so the join landed as an unnatural pause — the reported "cắt chunk giữa đường". Verified on the user's 450-char paragraph: 5 chunks, every cut on a comma or sentence end, concatenation byte-identical to the source.
* **Gaps are classified by the chunk's final punctuation, and each class has its own silence.** `_classify_gap` returns `"sentence"` when the chunk ends in `.!?` and `"minor"` otherwise (`,;:` or a forced cut); `"para"` is assigned by the caller for a `\n` boundary. Reference silences are `V3_GAP_SILENCE = {"para": 0.70, "sentence": 0.50, "minor": 0.30}`; FreeBook maps them to the existing `UserDefaults` keys instead (`paragraphPauseDuration` 0.5 / `sentencePauseDuration` 0.3 / `phrasePauseDuration` 0.15) so one setting drives both engines.
* **`_fits` has a tail slack, and dropping it creates orphan fragments.** A sentence is accepted if it fits, **or** if it is shorter than `min(CHUNK_TAIL_SLACK, max_chars/8)` and the total stays within `max_chars + slack`. Without that rule a fragment like `"phương."` ends up alone and gets glued onto the next sentence.
* **Inter-chunk pauses must follow the punctuation, and the chunker must break on it.** The first version inserted a flat 0.12 s between chunks and did not treat `,` as a boundary at all, so commas lived *inside* a chunk while silence was only inserted *between* chunks — every comma break was lost. `pauseSeconds(afterChunk:)` now reads the same `UserDefaults` keys the NghiTTS path uses (`sentencePauseDuration` / `phrasePauseDuration`), and `chunkBoundaryCharacters` includes `,` `，` `、`.
* **`sea_g2p.bin` has no digits at all — numbers and dates must be spelled out before phonemizing.** `8`, `1999`, `74`, `3`, `2002` all fail lookup, so they fall into the per-character fallback; the model's vocab only has `1 2 4 5 6 7`, so `0 3 8 9` are dropped. The user's `8/1999` and `3/11/2002` lost exactly **10** characters (7 digits + 3 slashes) — the reported `phoneme bỏ: 10`. VieNeu therefore runs `TextPreprocessor.normalizingForVieNeu`, which is `processVietnameseText` (numbers, dates, year ranges, time, units, roman numerals, NFC, dash/quote normalization) **without** the espeak transliteration that `preprocess(_:)` would add — espeak IPA is a different alphabet and would be dropped silently. This is a **reversal of plan §2** ("no preprocessing"), driven by reality.
* **`isExtensionTool` is one predicate in six places — adding a built-in engine means fixing all six.** `tool != "system" && tool != "nghitts" && tool != "google"` appeared **4× in `TTSSettingsView`** and **2× in `TTSManager`**. Adding `vieneu` without touching all six made VieNeu fall into the **extension** branch: the settings screen rendered the extension voice list (empty ⇒ *"Không có giọng đọc nào"*) and printed *"Extension TTS không hỗ trợ chỉnh cao độ"*. It is now a single `TTSManager.isExtensionTool(_:)`. **Symptom to remember: a new built-in engine showing extension-flavoured UI = this predicate.**
* **A built-in engine needs its own voice branch in `TTSSettingsView`.** The voice section ends with an `else` that is the *extension* case; a new engine silently lands there. VieNeu's branch is `vieNeuVoicePicker` in `TTSSettingsView+VieNeu.swift` — and it deliberately does **not** filter by `isModelDownloaded` (its 11 voices share one `voices_v3_nano.json`, not per-voice files).
* **The prefetch chain is 6 files deep, not 3 — count call sites before promising a signature change.** The 2b plan listed `TTSChapterPrefetcher`, `TTSNextChapterPrefixSynthesizer` and `TTSManager`. Reality also had `TTSNextChapterPrefixCache.swift` (declaration **and** pass-through), `TTSNextChapterPrefixCache+GoogleBatch.swift` (two `nil` call sites) and `TTSManager+NextChapterPrefix.swift`. Renaming a parameter label without those compiles nowhere. **Grep the whole `Sources/` tree for the old name after the rename, not just the files the plan named.**
* **`TTSSettingsView.swift` has a 519-line baseline — adding to it creates a new violation.** The 2b wiring pushed it to **540**; the fix was moving the additions to `TTSSettingsView+VieNeu.swift` (and widening `@State availableVoices` from `private` to `internal`). Same pattern as `VieNeuTTSTestView+Sections`.
* **The app already implements "synthesis at 1.0, speed at playback".** Both NghiTTS synthesis call sites pass `speed: 1.0` (`TTSManager.swift:2889`, `:3652`) and `updatePlaybackParams()` (`:1122`) applies the user's speed at playback (`nghiAudioPlayerQueue.updateRate`). So `makeDefaultSynthesisKey` never sees a non-1.0 speed, and no cache-key surgery is needed for VieNeu.
* **Never add a line to `TextPreprocessor.swift` — it sits exactly on its 1121-line baseline.** Widening `PreprocessorRuntimeConfig` and `processVietnameseText` from `private` to `internal` was done **in place** (same line count) and the new entry point lives in `TextPreprocessor+Numbers.swift`. Adding a 2-line doc comment there already pushed it to 1123 and produced a new `LINE_LIMIT_EXCEEDED`; it was reverted. **Check `wc -l` after every edit to a baselined file.**
* **Dictionary values may contain `-`, and that is correct.** `sách → sˈe-ɜc`, `giành → zˈe-2ɲ`, `anh → ˈe-ɲ` come straight from `sea_g2p.bin`; `-` is vocab id 6, so it encodes fine. Do **not** "fix" these — they are upstream data, and the model was trained with them.
* **Normalize punctuation to the model's vocab before phonemizing.** `config.json` has `,` `-` `.` `!` `?` `:` `;` but **no** `–` (U+2013), `—` (U+2014) or `“ ” « »`; `encode` drops unknown scalars **silently** (only counted). The user saw exactly `phoneme bỏ: 1` from one en dash. `normalizingPunctuation` maps dashes to `,` (they mean a break, and the model reads a comma) and strips decorative quotes — but deliberately leaves `'` / `’` alone because the tokenizer uses them to join words.
* **RTF is a ratio — compare it on identical text.** `RTF = synthesisMs / audioSeconds`, so anything that shortens the audio (per-chunk `trim_and_fade`, a shorter source text) raises RTF without the engine being slower. A reported 0.26 → 0.30 came from a different 285-vs-290-char text and 11% shorter audio while absolute synthesis time moved only 4%. The report now also prints the realtime multiplier (`1/RTF`) so the number reads directly.
* **SwiftUI cannot see changes in a plain (non-`@Observable`) service — bind UI state to `@State`.** The mode picker originally bound its selection to a computed `Binding` reading `VieNeuTTSService.preferredMode`, and the "Đang chạy" label read `service.currentMode`. Neither is observable, so the label only refreshed when some *other* state changed — the reported symptom was "chọn xong không thấy đổi, bấm Phát mới đổi". Fix: hold the selection in `@State`, push it to the service in `.onChange`, and render the label from the state first.
* **Speed belongs to the playback layer, never to synthesis.** The engine's `speed` divides `exp(log_s)` (`secs = min(exp(log_s)/speed, 15)`), i.e. it makes the model **generate** shorter or longer audio — pushing it away from the pace it was trained on, and forcing a full re-synthesis on every speed change. `VieNeuTTSTestView` therefore always synthesizes at **1.0×** and applies the user's speed with `AVAudioPlayer.rate` (`enableRate = true` must be set **before** `rate`). Consequence to remember when wiring the Reader: the measured RTF always corresponds to 1.0×, and changing speed must not trigger a new synthesis.
* **No `cfg = 0` mode.** Removing CFG does halve the compute, but the model card warns it "hurts intelligibility" and listening confirmed **choppy, unclear** output. The option was removed rather than kept as a trap; a stale `"turbo"` value in `UserDefaults` degrades to "auto" because `Mode(rawValue:)` returns `nil`.
* **Diagnostics must surface dropped phonemes in the UI, not only in the log.** `AppLogger` only writes when the user enables it, so a G2P that returns characters outside the model's vocab fails silently. `VieNeuTTSEngine.Output.droppedScalars` now flows to the test screen's copyable report.

## VieNeu-TTS ONNX Bridge Invariants (1.3.419, bổ sung 1.3.420)

* **Never derive a tensor shape from `config.json` — read it from the model.** The first version built `ctx` as `[1, L, dim]` with `dim = 512` and `duration_predictor` answered `Got: 512 Expected: 256`: the real last dimension of `ctx` is `style_dim` (256), and `dim` serves a different part of the architecture. `VieNeuORTRunTextEncoder` now returns the shape it actually produced (`copyFloats` fills `outShape`/`outRank` from `GetDimensions`) and both downstream calls must consume exactly that. `VieNeuConfig.dim` was **removed** rather than left unused. Same failure mode as the hardcoded output names — the engine's rule is *ask the model, never guess*.


* **Never trust the ZIP local header's `compressed`/`uncompressed` size when reading `.npz`.** `np.savez` writes `0xFFFFFFFF` (ZIP64 sentinel) there and keeps the real size in the extra field / central directory. Reading it produced `4.294.967.295` and a bogus "vượt biên file" failure. `VieNeuNPZReader` therefore parses the **NPY** header instead (`\x93NUMPY` magic → `shape` + `descr`) and computes the byte count itself (`elementCount × elementSize`), which also makes the cursor land exactly past each entry — the condition for never matching a stray `PK\x03\x04` inside float payload.
* **Never hardcode ONNX output tensor names.** The Python reference uses positional outputs (`run(None, {...})[0]`), so it cannot confirm names, while `OrtApi::Run` **requires** names. `VieNeuONNXBridge.m` asks the session itself (`SessionGetOutputName`) right after `CreateSession` and stores the result. Input names *are* confirmed by the reference (it passes them by name) and may stay hardcoded.
* **`VieNeuTTSEngine.prepareLocked()` must build every component into locals and assign them all at once.** Assigning `runtime` first means a later failure (`config`/`catalog`/`phonemizer`) leaves a half-initialised engine: `isPrepared` lies, every subsequent attempt skips loading, and the real error is masked by a downstream guard. This is exactly how a `.npz` parse failure surfaced as "Graph runtime…".
* **`ORT_API2_STATUS` does not prepend `const OrtApi*`.** Call through `api->Fn(...)`. `ORT_CLASS_RELEASE` functions return **`void`**, not `OrtStatus*` — never pass them to a status-checking helper.
* **`CreateTensorWithDataAsOrtValue` does not copy.** The input `NSMutableData` (or C buffer) must outlive the `Run` call; `VieNeuONNXBridge.m` normally creates, uses and releases every tensor inside a single function to guarantee it. **One controlled exception (1.3.450)**: the 4 loop-invariant CFG null tensors (`nullContext`/`nullMask`/`nullSpeaker`/`nullStyle`) are cached in `struct VieNeuORT` and reused across every Euler step. This is safe **only** because `VieNeuTTSEngine` has no `unload` — the source buffers are assigned once in `prepareLocked` and live for the whole engine lifetime. Any new cache of this kind requires the same proof; `VieNeuORTDestroy` must free the cache.
* **`ctx_mask` is `tensor(bool)` and cannot be produced by the Objective-C wrapper.** `ORTTensorElementDataType` has no `Bool` case in any usable ORT release (verified on 1.16.0, 1.20.0, 1.24.2 and the SPM package's `main`); only ORT core `main` has it. The C API is the only route, and it must be reached through a **C bridge** (`VieNeuONNXBridge.h/.m` + `SWIFT_OBJC_BRIDGING_HEADER`) because `import onnxruntime` does not resolve for the app target.
* **`SeaG2P` needs the vocab as Unicode scalars, not Swift `Character`s.** Four combining marks (`̪ ̩ ̃ ʲ`) are separate vocab entries; iterating `Character`s merges `t` + `̪` into one and silently drops the phoneme.

## Reader AI FullScreen & Background Session Invariants (1.3.397)

* **ReaderView must present AI via native SwiftUI `.fullScreenCover`, never UIKit `.fullScreen`.** Presenting a UIKit modal with `.fullScreen` unmounts the reader's view hierarchy from the Window, breaking `isChapterSubtreeRenderable` handshake and causing infinite skeleton loading upon dismissal. SwiftUI `.fullScreenCover` preserves the view hierarchy, keeping text and reading position 100% intact.
* **External AI presentations outside ReaderView must use `.overFullScreen`.** When reopening AI from Shelf or Discovery, `AIRuntimeCoordinator.presentFullScreen` must use `modalPresentationStyle = .overFullScreen` so the underlying ViewController is not detached.
* **Immediate disk persistence for all AI actions and chat messages.** In `ReaderAIFullScreenView+Actions.swift`, calling `AIChatHistoryStore.shared.saveSession` must occur immediately when appending user and assistant messages (typing, quick chips, name extractions, batch scans). Never defer saving until stream completion.
* **AIRuntimeCoordinator owns the live `activeSession`.** When the AI view is closed during streaming or batch execution, `AIRuntimeCoordinator.shared` must maintain and update the active session in memory, ensuring reopening from the widget restores the entire conversation state seamlessly.

## Reader AI Agent Harness invariants (1.3.385)

* **Raw chapter content is the single source of truth for AI analysis.** Extraction of character names, locations, and glossary terms must use the raw Chinese chapter text via `AIBookDataInspector.loadRawChapterContent`, never the translated text. This prevents translation distortion from polluting the dictionary.
* **Three harness modes dictate data mutation authority.** In `.ask` mode, all book data mutations (adding names, adding junk filter rules) must be queued into an action plan requiring user confirmation before execution. In `.plan` mode, multi-step actions require explicit approval. In `.bypass` mode, actions execute automatically.
* **Custom Name dictionary writes must use `isName: true` and specify `bookId`.** Direct mutations of book names must call `TranslationManager.shared.saveCustomEntry(key, meaning, isName: true, bookId: bookId)` to benefit from Name protection in `QuickTranslationRuleMatcher`.
* **AI Chat history is partitioned by book.** Chat sessions are stored as JSON files under `Application Support/ai_chats/<sha256(bookId)>.json`, keeping context isolated between different books.

## Reader definition overlay rule chip loading invariants (1.3.381)

* **Rule traces are scoped to the paragraph, not the token selection.** `openDefinitionPanel()` and `showingDefinitionSheet` trigger `refreshRuleTraces()` so chips are populated on open. `refreshDefinitionRules()` validates paragraph identity (`originalSentence == text`), not `currentDefinitionSnapshot()`. Expanding or shrinking token selection does not reload rule traces.
* **Rule updates only reload for global rules and the active book.** `QuickTranslationRuleBookStore.notifyChange(bookId:)` posts `.quickTranslationRulesDidUpdate`. Both `ReaderView` and `TTSManager` filter incoming rule notifications: reload only when `targetBookId == nil` (global) or matches the current book (`bookId` for reading, `playingBookId` for listening).

## Chapter cache ceiling and translation-only reload invariants (1.3.375)

* **A stale translation token is not a reason to reload chapter content.** `loadChapterContentFromExtension` must return early (`.memory`) when `forceRefresh == false` **and** the reader cache already holds `state == .loaded` with non-empty `originalContent`. The only remaining work in that case is re-translating from the cached raw text, which `runNavigationWorker` already does. Explicit refresh paths (`forceRefresh: true` — "Cập nhật mục lục", `reloadDisplayedChapter`) must keep fetching.
* **The chapter cache has a ceiling, and it is enforced on navigation.** `ChapterCache.queueReleaseAllNonVisible` is called from `ReaderView.applyNavigationCommit` with a ±3 window. Do not widen it back to "never evict": `handleMemoryWarning` keeps only the displayed chapter, so unbounded growth merely defers eviction to a moment the reader cannot predict. Any `queueRelease` task that removes entries must run on the main actor — `cache` is `@Observable`.
* **A memo smaller than one chapter is not a memo.** `QuickTranslationRuleEngine`'s rewrite memo must hold more entries than a chapter has paragraphs: the pipeline calls `rewrite` twice per string (once to translate, once to build spans), so a 64-entry memo thrashes inside a single chapter build.

## Translation snapshot, mutation and refresh invariants (1.3.354)

* **One synchronous translation pass uses one `TranslationReadContext`.** Dictionary tries, tombstones, per-book dictionaries, rule snapshots, disabled rules, token/priority configuration and generation must not be re-read independently midway through a pass.
* **Published dictionaries are immutable.** Loader objects may mutate while loading, but only `FrozenTrieDictionary` values cross into `TranslationDictionaryState`. All lookup offsets and match lengths are UTF-16.
* **Accepted VP/Names runtime writes are serial and non-cancellable.** Route custom global/per-book CRUD, import and tombstone restore through `TranslationDictionaryWriter`; persist first, then publish/invalidate, then notify. Presentation cancellation may cancel CPU lookup, never an accepted save.
* **Translation caches require both budgets and stale-insert protection.** Every memo has entry/cost limits; invalidation advances an epoch so an in-flight old computation cannot insert afterward. Every tokenization input must remain in its key/generation.
* **Reader refresh is latest-wins and presentation-aware.** Coalesce dictionary/rule notifications for 500 ms, invalidate non-current chapter tokens, and never apply rebuilt paragraph content while a selection/definition/rule overlay owns that paragraph. Pending apply must re-check chapter, revision, translation token and settings.
* **TTS next-chapter identity includes `translationToken`.** Dictionary/rule updates affecting the playing book invalidate prepared current data, next DTO/audio, prefix audio and claimed synthesis. A stale DTO must reprocess the same chapter; it must not recursively advance using the stale cache.

## Extension origin and editor-run invariants (1.3.351)

* **`Extension.installOrigin` is the durable source of install provenance.** Views may display it but must not assign it directly; writes go through `UpsertExtensionCommand.installOrigin` or `ExtensionTransactionCoordinator.setInstallOrigin`. Repository installs must set `repository`, import zip must set `importZip`, and debug server installs/overwrites must set `debugServer`.
* **The debug badge is presentation-only.** It is derived from `Extension.showsDebugBadge`; do not add a second persisted badge flag or a separate cache. The fallback heuristic exists only for rows created before `installOrigin` shipped.
* **Script Editor Run must reuse the debug pipeline.** Detect executable scripts with `ExtensionDebugScriptScanner.containsExecute(in:)`, save dirty files before running, seed `ExtensionDebugConsoleView`, and let `ExtensionDebugRunner` own `JSExecutor`, trace, redaction, run IDs, and cancellation. Do not add a second editor-only JS execution path.
* **A widget jump to the current TTS highlight is an explicit re-enable signal for Reader auto-scroll.** `ReaderView` may set `isAutoScrollDisabled = false` when handling `navigateReaderToPlayingChapter`; TTS widget and Shelf must not learn about that state.

## Hot-path invariants on the translation pipeline (1.3.339)

* **Never compile an `NSRegularExpression` inside a function that runs per line or per token.** Literal patterns belong in `static let`. `postProcessText` violated this for four patterns while being called once per token during span building; that alone accounted for ~24,000 ICU pattern compiles per chapter rebuild.
* **`TokenizeMemo` correctness depends on one thing only: every input that can change tokenization must be in the key.** Today that is `TranslateUtils.translationGenerationToken(for:)` (global / per-book / settings generations + `QuickTranslationRuleStore.cacheTag`), `bookId`, the pronoun and luật-nhân flags, and `md5(text)`. If you add a new data source to the tokenizer, either bump one of those generations or add it to the key — otherwise the memo serves stale tokens silently, with no error anywhere.
* **Do not call `tokenize` while holding `TranslateUtils.cacheLock`.** The memo path reads `translationGenerationToken`, which takes that same non-recursive `NSLock`. All existing lock scopes wrap exactly one dictionary read or write; keep it that way.
* **`TextDictionary` length bookkeeping is UTF-16, not `Character`.** Both lookup functions operate on `[UInt16]`, so key lengths must be counted with `key.utf16.count`. Only try lengths that actually exist as keys — iterating from the longest key in the whole file down to 1 makes one long user-added entry slow down every lookup position forever.
* **`translationTokens` is a function of the paragraph, not of the selection.** Anything recomputed when only `selectedWordOffset`/`selectedWordLength` change must be cheap and per-word. Whole-paragraph work in that path is a defect.
* **`updateCachedTranslatedContent` must read its `scope`.** A change scoped to a different book must not rebuild the open chapter. Note the notification usually carries `userInfo["bookId"] == nil`, so filtering at the View layer is not enough — the view model is the only place that knows `self.bookId`.
* **`QuickTranslationRuleDiagnostics.diagnose` may run off the main actor** — same call graph as `performChapterTranslationOffMainActor`, and `QuickTranslationRuleTrace` is `Sendable`. Keep it debounced: it is re-run after every rule action, and it deliberately scans with `includesDisabled: true`, i.e. more rules than the real translate path.
* **A token that no `{i}` references is valid, not an error.** It still matches and consumes input; that is how `第<n><L> = Chương {0}` swallows `章`. `UNUSED_CAPTURE` must stay a warning — making it `hard` drops whole valid rule lines silently.
* **No lazy container inside a `List`/`Form` row.** Use `ScrollView` + `LazyVGrid` at top level, or `FlowLayout` (a non-lazy custom `Layout`) inside a row. This is the 1.3.269 crash, not a style preference.

## Rule-priority configuration: invariants (1.3.338)

* **`QuickTranslationRuleEngine.select` remains the only implementation of match priority.** It now reads the middle four criteria from a `QuickTranslationRulePriorityConfiguration.Configuration`; do not reimplement the ordering anywhere else, and do not add a second comparator for the diagnostics screen — it must call the same `select` with the same configuration snapshot.
* **`start` first, `sourceLine` last are structural, not preferences.** The selection loop is a single linear pass keyed on `start`; a different primary key breaks the `cursor` semantics. `sourceLine` must stay below `scopeRank` because line numbers restart at 1 in each rule set, so two rules from different scopes can tie on it.
* **Only reorder or flip total keys.** Any permutation of the four movable criteria is a valid strict weak ordering. Do **not** add a pairwise-conditional rule ("compare length first only when both rules are numeral-only") — that breaks transitivity and makes `sorted(by:)` undefined. Express such a policy as a single total key instead.
* **Configuration must be snapshotted before sorting.** The comparator runs O(n log n) times per line of text; reading `UserDefaults` or a JSON file inside it is a defect, not a style issue.
* **Any new runtime configuration that affects rewrite output must enter the memo key.** `priority.signature` sits next to `tokenConfiguration.signature` in `QuickTranslationRuleEngine.rewrite`. Adding a config without its signature means the cache keeps serving results computed under the old config.
* **Per-book configuration inherits; it never copies.** An absent field in `translate/books/<bookId>/QuickTranslateEngineConfig.json` means "follow the global setting". Per-book token state is three-valued for the same reason. A store that snapshots the global value into the book file the first time its screen opens is a defect.
* **Per-book config files are read per line of text**, so the owning store must cache in memory behind a lock, and a corrupt or unreadable file must degrade to the global configuration — never to "this book cannot be translated".
* **Persist from `onChange`, not from a `Binding` setter,** when the write path touches `@MainActor` APIs such as `ToastManager`: the setter is an escaping closure and does not reliably inherit the body's isolation.

## Punctuation normalisation position, espeak off the main thread, caret plumbing: invariants (1.3.336)

1. **Chinese→Latin punctuation normalisation runs AFTER dictionary lookup and BEFORE `postProcessText`.** `TranslationPunctuationMapper.apply` sits between `translatedWords.joined(separator: " ")` and `postProcessText`. Moving it earlier (the pre-1.3.336 shape) silently breaks **every** dictionary entry whose key contains one of `。．，、；：！？…～—　` — `弹指、遮天` can never match, because the trie sees `弹指, 遮天`. Moving it later loses sentence capitalisation and space trimming, since `postProcessText` only recognises `.!?:：`.
2. **There is exactly one punctuation table.** It lives in `TranslationPunctuationMapper`; `TranslateUtils.punctuationMapping` is gone. Do not reintroduce a second table, and do not "pre-normalise" a chapter before `tokenize`.
3. **`performTranslation` and `getTranslationTokens` must tokenise the same string.** Both now tokenise the post-rule source. If one of them normalises first, spans, `snapToToken` and the Dịch panel drift from the text actually rendered — and the drift is invisible until a user reports that an entry "does nothing".
4. **Span candidates go through the same mapper**: `translatedCandidate(for:)` = `postProcessText(TranslationPunctuationMapper.apply(token.translatedText))`. Comparing an unmapped candidate against mapped output silently drops spans.
5. **Never call espeak (or any `EspeakPhonemizer` entry point) from a SwiftUI `body`, a computed property read by `body`, or anywhere on the MainActor.** `phonemize` and `phonemizeEnglish` share one static `NSLock` with NghiTTS synthesis, and the first call may run `espeak_Initialize` plus a recursive bundle scan. Build such results in `Task.detached` and store them in `@State`. Note `Task { }` alone is not enough — it inherits the enclosing actor.
6. **Any value crossing a `Task.detached` boundary must be `Sendable` explicitly if it is `public`** — public structs/enums get no implicit conformance. `TTSPhoneticSuggestion` and its `Origin` carry it for exactly this reason.
7. **A debounced load task owns its own cancellation**: cancel the previous task before starting a new one, cancel in `onDisappear`, and re-check `Task.isCancelled` after every suspension point before writing `@State`. Cancellation does not stop a synchronous C call already running — it only discards the result.
8. **Both fields of the rule editor use `QuickTranslationRulePatternField`.** Insertion helpers (`insertIntoPattern`, `insertIntoReplacement`) must insert at the caret or replace the selection — never append to the end. Caret indices count **characters**; UTF-16 conversion happens only inside that field. Persist both carets in `QuickTranslationRuleDraftStore.Draft`, otherwise a sheet rebuild mid-typing throws the caret to the end.
9. **Rows that need both tap and long-press must not be wrapped in a `Button`.** Use `contentShape(Rectangle())` + `onTapGesture` + `onLongPressGesture`; a `Button` also fires its action when the finger lifts after a long press.
10. **Collection mutations stay in `BookCollectionCoordinator`.** New entry points (toolbar menu, context menu) may only call it and handle the returned `Result`; deleting from inside a collection must `dismiss()` on success rather than leaving the user in a dead screen.
11. **Chapter titles are translated at the point of display, not at the point of storage.** `NewChapterRecord.latestChapterTitle` keeps the source string; views guard with `isTranslationEnabled && TranslateUtils.containsChinese` before calling `translateChapterTitle`.

## `ReaderView` body layering: invariants (1.3.335)

1. **`ReaderView`'s body is a chain of one-modifier-group properties, and it must stay that way.** Order, outermost first: `body` → `readerLifecycleView` → `readerDataObservationView` → `readerPresentationView` → `readerPresentationNavigationLayer` → `readerObserverLayer` → `readerSheetLayer` → `readerOverlayStack`. Never merge two layers back into one expression: a single 330-line `GeometryReader`/`ZStack`/modifier expression is what produced `error: the compiler is unable to type-check this expression in reasonable time` and a red build.
2. **New view content goes into the layer that owns its role**, not into whichever layer is nearest: overlays into the `ZStack` of `readerOverlayStack` (as a one-line call to a `@ViewBuilder` member), presentation into `readerSheetLayer` or `readerPresentationNavigationLayer`, reactions into `readerObserverLayer`, lifecycle into `readerLifecycleView`. If a layer grows past roughly 100 lines, split it rather than letting the type-checker budget decide.
3. **Anything inline in that `ZStack` longer than a couple of lines becomes a `@ViewBuilder` member taking `in geometry: GeometryProxy`.** `floatingSelectionMenuOverlay(in:)` and `junkDeleteOverlay(in:)` are the pattern; keep passing the proxy explicitly instead of capturing an outer one, because the junk-delete panel reads `geometry.safeAreaInsets.bottom`.
4. **Splitting layers must preserve modifier order exactly.** The composed tree is only identical if each extracted property re-applies its group in the original sequence (`toolbar` → 4 `sheet` → `onChange`×10 + `onReceive` → 2 `sheet` + 2 `fullScreenCover` → `background`). Reordering while splitting changes safe-area and presentation context and produces **no** compiler error.
5. **Members that only `ReaderView.swift` uses stay `private` in that file.** These layers touch `@State` that is still `private` (28 of 86 declarations), so they cannot move into a `ReaderView+*.swift` file — Swift `private` is file-scoped. Only promote a member to `internal` when it genuinely has to be called from another file.

## Batched next-chapter prefix, per-chapter download, rule tracing inside the Dịch panel: invariants (1.3.334)

1. **The next-chapter prefix cache is the second batching site, and it keeps its own key space.** `TTSNextChapterPrefixCache+GoogleBatch` builds `batchKey = "gbatch|" + synthesisKeys.joined(separator: "|")` from the per-chunk `synthesisKey`s. Never reuse a single chunk's key for a batch, and never let a batch write into the per-chunk key space — a voice/rate/replacement change on any chunk must produce a different batch key.
2. **Batch only when it buys something: `guard batchIndices.count >= 2`.** A one-chunk "batch" adds a failure mode (all-or-nothing) for no request saving. Fall through to `TTSNextChapterPrefixSynthesizer.one` instead.
3. **Empty text never gets a slot.** Apply `TTSReplacementManager.shared.applyReplacements` then trim, and drop empties **before** assembling `batchIndices`/`texts`; those indices go down the single-request path. `googleBatch` must also enforce `audios.count == texts.count` and `throw` otherwise. This is the same index-drift invariant as 1.3.332 rule 3, now at a second site.
4. **Assign results by `batchIndices[i]`, never by `offset + i`.** `offset = batchIndices[0]` exists for key construction only; the index set can be sparse because empties were removed.
5. **One token per batch, stamped on every index it serves.** `nextTaskToken &+= 1` once, then record that token for all indices. Cancelling any index must invalidate the whole batch — a half-accepted batch is how audio lands on the wrong paragraph.
6. **`CancellationError` returns; it is not a synthesis failure.** Do not log it as an error, do not mark state, and do not trigger `recoverBatchFailure`. Any other error falls back to per-chunk synthesis for exactly the failed indices.
7. **Retry still lives in exactly one layer.** `RemoteTTSSynthesisCoordinator` owns the 2 attempts; `TTSManager` and the prefix cache must not wrap another retry loop around a batch. (Same rule as 1.3.332 rule 5 and 1.3.330 rule 6 — three sites now, one owner each.)
8. **`TTSNextChapterPrefixSynthesizer` stays stateless.** Two `static func`s that produce audio; the cache remains the only owner of `preloadedData`/`preloadedDurations`. If a synthesiser starts caching, there are two owners of the sliding window and no way to reason about eviction.
9. **A View may not assign `@Model` properties or call `modelContext.save()` — including indirectly.** `ReaderView.initializeReaderIfNeeded` and `BookDetailView.task(id:)` must call `BookTransactionCoordinator.refreshTitleTranslations(bookId:in:)` and handle its `Result`. `BookTitleTranslationMigrator.refreshTranslations(for:)` only assigns and returns `didChange`; calling it outside the coordinator dirties the context with nobody to commit. This closed the last two `VIEW_SWIFTDATA_MUTATION` violations (gate 12 → 8).
10. **A coordinator command must not open an empty transaction.** `refreshTitleTranslations` returns `.success(false)` and skips `save()` when nothing changed — opening a book is a hot path.
11. **The per-chapter download button primes the existing cache; it is not a download subsystem.** Call `ChapterContentRepository.load(forceRefresh: false)` + `ChapterStore.markCached(index:)`; do not create a `DownloadTaskModel`, do not enter the `BookDownloadWorker` queue. It deliberately bypasses `ReaderViewModel.loadChapterContentFromExtension` because that path also translates and builds `[ParagraphItem]` — if that path gains a step, this one will not inherit it, and that is the accepted trade-off.
12. **The download `Task` is not cancellable, on purpose.** Clean up only the UI flag (`defer { downloadingChapterIndices.remove(index) }`); the write must run to completion per the "content past the final cancel checkpoint must not be cancelled" rule. Expect toasts to appear after the chapter list closes.
13. **Rule tracing lives in the Dịch panel and diagnoses the whole paragraph.** `focusedRuleRange` is `trace.sourceRange` — it must **not** be snapped to the user's selection; snapping loses the context the rule actually matched. The read-only rule-meaning box stays separate from the editable translation-meaning box, otherwise the two meanings fight over one field.
14. **The panel-close side effects belong in `.onChange(of: showingDefinitionSheet)`, not in `closeDefinitionPanel()`.** Swipe-to-dismiss and tap-outside only lower the `isPresented` binding, so logic placed in the close function silently skips two of the three exit paths.
15. **Never reintroduce `ReaderRuleTraceOverlayView` / `ReaderRuleTraceGuideSheet` or a `?` guide button.** Both files were deleted at 1.3.334; the Dịch panel plus its three distinct notice strings ("Máy chưa có bộ rule nào…", "Công tắc rule dịch đang TẮT…", "Không rule nào chạm đoạn này.") replace them. Collapsing those three strings into one sends users hunting for a bug that is not there.

## Batched Google TTS prefetch: invariants (1.3.332)

1. **Only the prefetch window is batched; the paragraph the user is waiting for is not.** `updatePrefetchWindow` covers `N+1…N+k`; the current paragraph keeps its own single-part request because one round trip alone (~370 ms) beats waiting for a bigger one.
2. **A batch is still one coordinator job.** Route every remote synthesis through `RemoteTTSSynthesisCoordinator`; do not call `GoogleTTSService` directly from a prefetch path. Multiple mp3 blobs travel as one `Data` via `TTSBatchAudioPayload` — that framing exists specifically so the coordinator does not have to become generic.
3. **Never send an empty part, and always verify the count.** The API silently drops blank parts, which shifts every later index onto the wrong audio. `makeGoogleBatch` filters, `synthesizeBatch` rejects, and the returned count must equal the sent count or the call must throw.
4. **Batch text must be produced the same way as single-paragraph text** (`TTSReplacementManager.applyReplacements` then trim). Two code paths that build the text differently will synthesise two different audios for the same paragraph depending on which one ran.
5. **Retry stays inside `GoogleTTSService`** (`withRetry`, 2 attempts). `TTSManager` must not wrap another retry loop around a batch; a failed batch falls back to per-paragraph requests instead.
6. **Register a batch task under every index it serves, and cancel by task identity, not by index.** The window slides one paragraph at a time, so index-based cancellation kills a batch that is still needed for the remaining indices.
7. **Only Google batches.** Ext TTS calls `execute(text, voice)` in JavaScript — one paragraph per call. Do not invent a batching protocol for extensions.
8. **Scope changes on a rule are copy-then-delete, in that order.** `QuickTranslationRuleTransfer.copy` stays a copy (it is shared with the dictionary's Chuyển button); the delete lives at the call site. Writing the destination first means a mid-way failure leaves the rule intact rather than losing user-authored data, and the "exists in both places" outcome must be reported, not hidden.
9. **Shelf tab indices go through `ShelfTab`, never bare integers.** The order is Downloads → Bộ Sưu Tập → Kệ Sách → Lịch Sử; `SearchView` posts `rawValue` and `ShelfView` rejects values that do not map to a case.

## Ext TTS script cache, icon cache, repo refresh: invariants (1.3.330)

1. **`ExtTTSScriptCache` is the only reader of `tts.js` and the only place that merges TTS config.** Do not re-add a direct `String(contentsOf:)` in `ttsGenerate` or a second SHA256 in `getTTSRuntimeFingerprint`: those two paths reading disk independently is how a `synthesisKey` from one revision could end up caching audio produced by another.
2. **Cache validity is `(configJson, plugin.json modDate, script modDate)` — all three.** `plugin.json` decides the script *filename*, so watching only the script lets a renamed entry point serve the old file forever.
3. **`resetTTSRuntime()` invalidates the cache before resetting the runtime.** Reversing the order leaves a window where the next synthesis rebuilds the executor from a stale payload.
4. **`ExtTTSRuntime.Identity` compares the fingerprint, never the script text.** Comparing `scriptContent` is an O(len(script)) string compare on every paragraph, and the fingerprint already covers script + config + path.
5. **Ext TTS owns no files.** It returns `Data` only. Do not reintroduce temp-file staging: the deleted PCM path wrote one file per paragraph and needed a lock plus an explicit cleanup list to undo it. If a PCM path is ever needed again, decode in memory and apply normalisation **once**.
6. **Retry stays in exactly one layer** — `ExtTTSService.synthesizeData` (2 attempts). The cache must `throw` straight through, and `TTSManager` must not wrap another retry loop.
7. **Automatic repository refresh goes through `RepositoryRefreshPolicy`; manual refresh does not.** A refresh is one registry request per repo *plus* one `plugin.json` request per not-installed extension, so an ungated `.onAppear` sweep is ~95 requests for a 100-extension repo. `markRefreshed()` may only be called when at least one repo actually updated — otherwise one offline visit silences the next 6 hours.
8. **`ExtensionIconImageCache` keys on `(path, modDate)` and caches misses too.** Most extensions ship no `icon.png`; without negative caching every redraw stats and fails again. Never key on path alone — reinstalling an extension must show the new icon.
9. **Prefer `ExtensionIconView` over `AsyncImage` for extension icons.** It reads the local `icon.png` first, so installed extensions never hit the network and still render offline. Keep the type-specific fallback (`waveform` for TTS) for rows that have neither a local path nor an icon URL.
10. **Compute a filtered/sorted list once per view update.** `filteredExtensions` runs four `filter` passes plus a `sorted` using `localizedCompare`; calling it separately from a counter, an `isEmpty` check and a `List` multiplies the most expensive part of the redraw by three.

## Book collections: invariants (1.3.328)

These are **binding** for any change touching `BookCollection`, `Book.isPinned`, the Shelf tabs, or the long-press sheet:

1. **A book in a collection is always on the shelf.** Every path that adds membership must set `isOnShelf` (`BookCollectionCoordinator.promoteToShelf`), and every path that clears `isOnShelf` must empty `Book.collections` and clear `isPinned` (`BookTransactionCoordinator.removeFromShelf`, `setOnShelf(false)`, `addBookToShelf(isOnShelf: false)`). The invariant is enforced in the coordinators so no call site has to remember it.
2. **Removing from a collection never removes from the shelf, and deleting a collection never deletes books.** `deleteRule: .nullify` on both ends of the N-N relationship is load-bearing — `.cascade` here means deleting real books. `deleteCollection` also clears `books` by hand before `context.delete` because this is the easiest thing in the feature to get wrong.
3. **The type is `BookCollection`, never `Collection`.** A module-level `Collection` shadows `Swift.Collection` and silently changes what every later generic constraint means.
4. **New SwiftData properties stay additive with defaults.** There is no `VersionedSchema`/`SchemaMigrationPlan`, and `ModelContainer` init failure is `fatalError`, so a non-additive schema change ships an app that cannot launch.
5. **Collection membership and pin state are written only through coordinators.** Views read with `@Query` and handle the returned `Result`; `check_architecture.py` already watches `.isPinned =` for `SCOPED_VIEWS`, and it matches those views **by path substring**, so any new file with `ShelfView` in its path inherits the ban.
6. **Shelf tab indices are a cross-screen contract.** `ShelfView` tabs are Downloads 0, Kệ Sách 1, Bộ Sưu Tập 2, Lịch Sử 3, and `SearchView` posts that integer as `userInfo["shelfTab"]` on `sourceChangedNavigateToShelf`. Both the notification name and the value are bare literals: change one end and navigation silently lands on the wrong tab.
7. **Do not wrap a shelf row in a `Button` and add a long-press on top.** Releasing after the long press still fires the button, which opens the Reader behind the sheet. Use `onTapGesture` + `onLongPressGesture`.
8. **Pin-first ordering is two `filter` passes, not one `sorted`.** `sorted(by:)` is not stable in Swift, so comparing two keys in one pass reshuffles books inside each group; `pinned + unpinned` preserves the `lastReadDate` order the `@Query` already established.
9. **Backup gains entries, never a `BackupScope` case.** Collections and `isPinned` ride along with the mandatory `.books` scope via `library/collections.json`. New non-optional keys in `BackupPayload` records must be `Optional` (or get a hand-written `init(from:)`): Swift's synthesized decoder ignores property defaults, so a plain new key breaks every older archive. Restore is a **merge** — collections matched by case-insensitive name, members attached only when the book exists locally.

## Supersedes: transliteration verification no longer lives in the app (1.3.328)

* **The 1.3.290 bullet "Verification for this subsystem lives in the app … `TTSTransliterationTesterView` + `TransliterationGoldenSet`" and the 1.3.290 instruction to "re-run `TransliterationGoldenSet` from the Thử phiên âm screen" no longer apply.** Both the screen and the golden set were deleted on request; `EspeakPhonemizer.probeVoices` and `VietnameseTokenGate.explain` went with them.
* **Never override a user setting to serve a quality argument.** `VieNeuSynthesisPolicy.effectiveMode` used to force `.high` for every synthesis using a cloned voice (1.3.456), on the reasoning that 8 Euler steps make the cloned timbre drift. The reasoning was right and the **scope** was wrong: "high quality" belongs to the *clone step* (which runs the three clone graphs and has no `steps` at all), not to story playback. The user set "Tiết kiệm pin" and still got 16 steps, with the settings screen showing "Cân bằng" and nothing revealing the mismatch — the audible result was `underrun` and a hot device. If a context genuinely needs a different quality, pass an **explicit parameter** from the caller that owns that context; never infer it from the data (which voice, which book, which file). (1.3.461)
* **What remains is listening.** The only in-app check for a phoneme table or threshold change is "Thử giọng đọc" (`NghiTTSSettingsHubView`, formerly `NghiTTSTextToolView`) — type text, hear it. There is no automated gate: `check_architecture.py` only counts lines and `validate_links.py` only compares hashes. State plainly in the changelog when a transliteration change was not listened to.
* **The rest of the 1.3.290/1.3.291 transliteration invariants stand unchanged** (never return empty, never delete sounds to satisfy phonotactics, restore the espeak voice to `vi`, all espeak access through `EspeakPhonemizer`, don't grow a word blacklist, group regex alternations, collapse long vowels before segmentation, `/j/` splits onset/coda). Where those bullets cite the golden set as the record of a listening decision, treat the bullet itself as the record.
* **Japanese `u` renders as `u`, not `ư` (1.3.328).** `ku su tsu tu nu hu fu mu ru gu zu du bu pu` and bare `u` all use Vietnamese `u`. `ư` is /ɨ/ — unrounded — and espeak-vi speaks it as a different vowel ("Naruto" → *na-rư-tô*). Value collisions this creates (`tsu`/`tu` → `chu`, `zu` → `du`) are harmless: only dictionary **keys** must be unique.

## Quy chuẩn cho đường cài mới của debug server (1.3.325)

Bốn luật này bắt buộc với mọi thay đổi chạm nhánh `draft.install`:

* **File trước, bản ghi sau — không đảo.** Copy vào `extensions/<packageId>/` xong mới ghi hàng `Extension`. Hàng SwiftData trỏ vào thư mục không tồn tại là lỗi im lặng ở mọi màn đang `@Query`; thư mục mồ côi thì `ExtensionInstallAudit` thấy được và lần cài sau tự sao lưu rồi thay.
* **`packageId` là danh tính do *app* suy từ `plugin.json`, không phải giá trị client gửi.** Client gửi id chỉ để làm khoá vùng staging. Ba đường cài (repo sync, import zip, cài từ debug) phải cho **cùng một** id với cùng một cái tên — sửa luật ở một chỗ thì phải sửa cả `ExtensionSyncCommandBuilder.packageId(forName:)`, `ExtensionManager.installFromLocalZip` và `ExtensionDraftMetadata.slug(forName:)`, nếu không thư viện sẽ có hai hàng cho một extension.
* **Ghi SwiftData chỉ ở router, chỉ qua `ExtensionTransactionCoordinator`, và chỉ bằng `ModelContext` dựng mới từ container.** `ExtensionDraftInstaller` phải giữ nguyên vai "chỉ đụng file" — nó là actor nền và không được giữ `ModelContext`.
* **Mọi nhánh ghi vào dữ liệu người dùng đều phải qua `ExtensionDebugInstallGate`, và `Kind` phải nói đúng việc sắp làm.** Thêm một nhánh ghi mới mà tái dùng `Kind` cũ là làm người bấm hiểu sai thứ họ đồng ý; đường cài mới bắt buộc kèm tên đọc từ `plugin.json` vì `packageId` một mình không đủ để quyết định.

## Quy chuan cho debug server (1.3.303)

Nam luat nay bat buoc voi moi thay doi cham `Debug/Server/` hoac `Debug/Staging/`:

1. **Khong bao gio bo qua cua xac nhan tren thiet bi.** Token dung chi cho phep *xin* pair; `isPaired` chi `true` sau `approvePending()`. `draft.install`/`draft.rollback` phai di qua `ExtensionDebugInstallGate`. Them mot lenh nao ghi de du lieu nguoi dung thi lenh do cung phai di qua cong nay.
2. **Khong nhan path tu client.** Lenh chi duoc mang `packageId`, `entrypoint`, input va `relativePath` **da khai trong manifest**. Cam them field nao nhan `URL`, path tuyet doi, hay source JavaScript raw vao `run.start`.
3. **Moi duong tat may phai `InstallGate.cancelPending()`.** Do la cho duy nhat trong app co continuation treo vo han; thieu mot duong la `Task` cua router treo ca phien.
4. **`ExtensionDraftStagingStore` la cho duy nhat tao/xoa file trong `extension-drafts/`.** Khong ai khac duoc ghi vao do, va no khong duoc ghi ra ngoai do.
5. **`src/protocol.ts` la mirror cua `ExtensionDebugProtocol.swift` + `ExtensionDebugEvent.swift`.** Sua mot ben phai sua ben kia cung luot. App la tham quyen cuoi cung ve manifest, entrypoint va contract; client chi validate hinh dang de bao loi som.

Doi `Envelope`, them `CommandType` hay `ErrorCode` la doi contract v1 => nang `ExtensionDebugProtocol.version` va `ExtensionDebugEvent.contractVersion`, khong them im lang.

## Quy chuẩn cho trace debug extension (1.3.302)

Bốn luật này là **bắt buộc** với mọi thay đổi chạm phân hệ debug extension:

1. **`ExtensionDebugEventSink.emit` không được blocking.** Nó bị gọi từ thread đang chạy JavaScript (trong `@convention(block)` của JavaScriptCore) và từ callback `URLSession`. Cấm `await`, cấm I/O, cấm giữ khoá qua một lời gọi khác. Đó là lý do sink là `final class` + `NSLock` chứ không phải `actor` — mọi việc nặng thuộc `ExtensionDebugEventHub`.
2. **Redact ở phía tạo event, không ở phía gửi.** `ExtensionDebugEvent` được coi là đã sạch từ lúc khởi tạo. Không thêm hàm nào vào `ExtensionDebugRedactor` để nhận header, cookie, request/response body, nội dung chương, `configJson` hay localStorage — việc **không có hàm** là chốt an toàn, không phải thiếu sót.
3. **Trace không được phụ thuộc `AppLogger`.** Không đọc `isLoggingEnabled`, không tail `app_logs.txt`. `AppLogger.init` tự tắt log mỗi lần khởi chạy nên log file không dùng được làm giao thức debug; đó là lý do phân hệ này tồn tại.
4. **`ExtensionDebugEntrypoint.jsArguments` là bản sao của contract `execute(...)` ở `ExtensionManager`.** Sửa một bên phải sửa bên kia cùng lượt. Hai chỗ dễ sai đã có sẵn: `search` truyền `page` dưới dạng `String`, và `toc` chỉ resolve URL khi extension **không** khai script `page`.

Thêm `case` vào `ExtensionDebugEvent.Category` là đổi contract v1 ⇒ nâng `ExtensionDebugEvent.contractVersion`, không thêm im lặng.

## TTS transliteration: no-drop invariants (1.3.291)

* **No transliterator may return an empty string.** If a word cannot be rendered, return the original token verbatim. The only downstream guard is chunk-level (`PiperTTSService.isUnspeakable`), so an empty token is silently missing audio, which users hear as dropped words.
* **Never satisfy Vietnamese phonotactics by deleting sounds.** Clusters Vietnamese cannot spell must become additional filler syllables (`+ "ơ"`), not be truncated. `IPAToVietnameseMapper.assemble` returns `[String]` for exactly this reason.
* **Japanese long vowels render short, on purpose.** `ー`, `ou`, `ei` collapse to the short vowel because Vietnamese has no vowel length and doubling makes Piper insert a syllable break. This is a listening decision recorded in the golden set — do not "correct" it back to Hepburn without listening.
* **The ambiguous-syllable gate requires foreign neighbours on both sides.** One-sided context transliterated Vietnamese words; prefer a missed transliteration over mangled Vietnamese.
* **Bulk dictionary actions have one owner.** `TTSDictionaryBulkActionsModifier` performs the delete itself and only reports completion; views must not re-implement "delete all".

## TTS transliteration invariants (1.3.290)

* **espeak voice must always be restored to `vi`.** Any entry point that calls `espeak_SetVoiceByName` with another language must restore `vi` in a `defer` **inside the same `NSLock` critical section** before returning. Piper synthesis assumes Vietnamese phonemes; a leaked voice change corrupts every later utterance and the symptom surfaces long after the cause.
* **All espeak access goes through `EspeakPhonemizer`.** Do not call `libespeak_ng` from anywhere else: the initialization flag, the lock and the voice invariant live in that one type. New needs get a new entry point there, not a second engine owner.
* **Do not "fix" transliteration by growing the word blacklist.** Recognizing Japanese romaji versus English is a scoring problem in `ForeignScriptClassifier`; the set of English words that happen to segment into valid romaji syllables is unbounded, so an exclusion list can only ever chase the last report. Adjust signals or `japaneseThreshold`, and re-run `TransliterationGoldenSet` from the Thử phiên âm screen.
* **Transliterator output must be legal Vietnamese orthography.** The result is fed back into espeak (`vi`) for Piper, so onset/coda combinations that Vietnamese does not allow are silently mispronounced. `IPAToVietnameseMapper.legalOnset`/`legalCoda`/`normalize` are the only place that guarantee this; new phoneme entries must pass through them rather than emitting raw strings.
* **Rule cascade order in `EnglishTransliterator` is load-bearing.** `sRules` → `rRules` → `tRules` run on the *same progressively rewritten* string, so a rule that collapses a digraph (`ck`, `sh`) must not run before the suffix rules that need that digraph. Any new rule must state which stage it belongs to and why.
* **Regex alternation must be grouped.** `"\bcr|pr|gr"` anchors only the first branch; always write `"\b(?:cr|pr|gr)"`. This class of bug silently rewrote mid-word clusters for a long time.
* **Never overwrite `non-vietnamese-words.plist` wholesale.** It holds both the downloaded base dictionary and user-added pronunciations. Downloads must merge with local entries winning.
* **Japanese long-vowel collapsing happens before syllable segmentation, never as table entries.** `greedySegment` matches longest-first *at each cursor position*, so a `"ou"`/`"uu"` key in `romajiToViSyllable` can never win against the `"to"` that starts one character earlier — "arigatou" segmented to `to` + `u` and spoke a spurious `ư` syllable for a full release while the table looked correct. Collapse in `JapaneseTransliterator.collapseLongVowels` (called from `normalizeRomaji`) and keep the reading table free of long-vowel keys. `ai`/`oi`/`ui`/`au` must stay out of `longVowelForms`: those are real diphthongs and collapsing them drops a sound.
* **A nucleus and a coda that are individually legal can still form an illegal rime.** `IPAToVietnameseMapper` looks the two up in separate tables, so nothing stops it emitting `ơng`, `âyp`, or a stop-final syllable with no tone mark — none of which exist in Vietnamese, and all of which reached espeak-vi for a full release. Three rules hold the line and each one carries the others: diphthongs (`ây ai oi ao ia ua iu`) take **no** coda, a coda in `p t c ch` **forces** the acute tone, and `/əl/`/`/ən/` are fixed rimes. `acute` only handles a single-character nucleus — that is safe *only because* the diphthong rule runs first, so relaxing the diphthong rule silently stops adding tone marks. Any new vowel or coda entry must be checked against the rime it can produce, not just against its own table.
* **`/j/` maps to `d` at the onset and `i` at the coda, and the two must not be unified.** At the onset Vietnamese has no letter for /j/, and writing `i` makes espeak-vi read a diphthong (`ia` → /iə/) so the word gains a syllable; at the coda `i` *is* the offglide of `ai`, `ây`. Same split applies to `ya/yu/yo` in `JapaneseTransliterator`. Accept that `d` reads /z/ in the default `vi` voice: a wrong consonant is a smaller error than a wrong syllable count.
* **Verification for this subsystem lives in the app**, not in `Tests/`: `TTSTransliterationTesterView` + `TransliterationGoldenSet`. Changing a phoneme table or a threshold without re-running the golden set is not a verified change. Cases the team has decided not to fix yet stay in the set marked `ĐỎ` with the reason, rather than being deleted or quietly retargeted.

## TTS preparing highlight color invariant (1.3.278)

* Preparing highlight and active TTS highlight must use the same configured Reader highlight colors: `theme.highlightUIColor` for background and `theme.highlightTextUIColor` for foreground when available. Do not add a separate alpha, fallback color, or hard-coded preparing color.
* `highlightIsPreparing` remains useful only as render/diff state and must not imply a distinct visual palette or progress ownership.

## TTS widget reveal-from-Reader invariants (1.3.277)

* Hành động nghe khởi phát từ Reader phải yêu cầu widget TTS mở rộng ban đầu qua tầng View (`TTSFloatingWidgetWindowManager.requestRevealOnNextShow()`), không qua `TTSManager`. `Services/TTS` không được phụ thuộc `Views/TTSWidget` hoặc biết `WidgetMode`.
* `FloatingWidgetViewModel` vẫn mặc định `.peeking`; không đổi default mode toàn app chỉ để phục vụ Reader. Reveal ban đầu là cờ một lượt ở window manager và phải được consume khi container sẵn sàng.
* Reveal từ Reader dùng lại `FloatingWidgetViewModel.reveal()` và auto-hide hiện có. Muốn ghim widget mở lâu hơn phải là yêu cầu riêng, không lẫn vào request "mở rộng ban đầu".

## TTS preparing highlight invariants (1.3.276)

* `TTSPlaybackSnapshot.preparingParentParagraphIndex` và `preparingHighlightRange` là **presentation-only state** cho đoạn sắp nghe trước khi audio thật bắt đầu. Không dùng chúng để lưu tiến độ đọc, update Now Playing, claim `ReadingProgressStore`, mở rộng prefetch window hay đánh dấu synthesis thành công.
* Active highlight vẫn chỉ được publish qua `commitAudibleParagraphState(index:)` khi audio đã bắt đầu/scheduled đúng đoạn. Không publish `highlightRange` active sớm trong `speakCurrent()`; guard dedupe của snapshot có thể làm lượt commit audible bị bỏ qua và mất side effect.
* Reader phải ưu tiên highlight theo thứ tự active TTS → preparing TTS → search. Preparing highlight chỉ hợp lệ khi `playingBookId`, `playingChapterIndex` và `preparingParentParagraphIndex` khớp đoạn đang render; Reader sách khác phải nhận `nil` qua projection reader.
* Preparing range dùng cùng hệ toạ độ UTF-16 tương đối với dòng cha như `TTSParagraph.range`. Không map lại qua `ReaderSelectionMapper` và không tạo hệ toạ độ thứ ba.

## Một nguồn duy nhất cho file riêng truyện; tắt rule bằng file theo phạm vi (1.3.274)

* **Danh sách file riêng truyện chỉ được khai ở một nơi**: `Sources/Services/Translation/Extensions/TranslationManager+BookScopedFiles.swift` (`bookScopedDictionaryTextFiles`, `bookScopedDictionaryBinaryFiles`, `bookScopedRuleFiles`, `bookScopedMigrationFiles`). `BackupPaths` và luồng đổi nguồn của `SearchView` phải đọc hằng từ đó. Thêm tên file riêng truyện mới mà khai ở nơi khác (hoặc thêm danh sách `["VietPhrase.txt", …]` thứ ba) là tái tạo đúng loại bug im lặng "file không vào backup và không đi theo truyện khi đổi nguồn" mà 1.3.274 vừa dọn.
* **Bật/tắt rule dịch tuyệt đối không được sửa file rule.** Rule đang tắt vẫn nằm trong `snapshot.rules` (bật lại được, giữ `sourceLine`); chỉ có **mẫu** của nó nằm trong file tắt (`translate/QuickTranslateRulesDisabled.txt` chung / `translate/books/<bookId>/QuickTranslateRulesDisabled.txt` riêng). Khoá của file tắt là **mẫu** (phần trước dấu `=`), không phải `sourceLine` — số dòng đổi sau mỗi lần thêm/xoá. `QuickTranslationRuleDisableFile` là hàm thuần trên `String` (không chạm `FileManager`); chỉ `QuickTranslationRuleDisableStore` được ghi file tắt, và hết mẫu thì **xoá file** thay vì để file rỗng.
* **Ngữ nghĩa tắt theo phạm vi** (`QuickTranslationRuleDisableStore.Snapshot.isDisabled(pattern:scopeRank:)`): rule của bộ riêng chỉ chịu file tắt riêng; rule của bộ chung chịu file tắt chung (mọi truyện) **hoặc** file tắt riêng của truyện đang đọc. Tắt ở bộ chung = tắt cho mọi truyện; muốn dùng lại ở đúng một truyện thì thêm mẫu vào bộ rule riêng của truyện đó.
* **`scopeRank` là tiêu chí ưu tiên thứ 5 của `QuickTranslationRuleEngine.select`** (sau độ dài match, trước `sourceLine`; rule bộ riêng = 0 thắng bộ chung = 1). Mọi nơi cần trả lời "rule nào thắng" (màn Check rule qua `QuickTranslationRuleDiagnostics`, ô Thử nhanh qua `preview`) phải dùng lại đúng `collectFound` + `select` của engine — không cài lại thứ tự ưu tiên ở chỗ thứ hai — và không được để màn soi ghi trạng thái (`notesComplexRules: false`) hay bỏ qua file tắt; nếu không nó nói khác kết quả dịch thật.
* **Mọi invalidation khi đổi dữ liệu rule** (bật/tắt/thêm/sửa/xoá/chuyển, token policy, priority policy, phạm vi nào cũng vậy) gói vào đúng một `TranslationManager.notifyRulesDidUpdate(bookId:)` sau khi `TranslateUtils.clearCache()` hoặc `TranslateUtils.invalidateCache(bookId:)` đã bump generation liên quan. Không thêm `disableRevision`/`revision` vào cache key. Ghi file thất bại ⇒ không bump, không notify, trả lỗi lên View để toggle quay về trạng thái cũ. Đổi từ điển mới được dùng `notifyDictionariesDidUpdate(bookId:scope:)`.
* **Định danh nghiệp vụ của Quick Translation rule là `pattern` (vế trái dấu `=`), không phải `sourceLine`** — số dòng đổi sau mỗi lần thêm/xoá. File rule được canonical first-wins nên `pattern` là duy nhất trong snapshot; `QuickTranslationRuleTrace.id` xác định theo scope/pattern/location, không phải `UUID()` mới mỗi lượt. Thêm/sửa/xoá chung và riêng đều đi qua `QuickTranslationRuleRecordStore`.

## Tắt bàn phím là hành vi toàn app, có đúng một chủ (1.3.266)

* **Không thêm `.onTapGesture { hideKeyboard() }` (hay `background` bắt tap) cho từng màn để tắt bàn phím.** Hành vi "bấm ra ngoài ô nhập thì bàn phím tắt" do `KeyboardDismissGesture` (`Sources/Common/Utils/`) phủ ở tầng `UIWindow` cho mọi màn. Thêm ở màn lẻ là tạo điểm điều khiển thứ hai cho cùng một hành vi, và thường kèm tác dụng phụ ăn mất touch của nút bên dưới.
* **Vẫn được tắt bàn phím tường minh** khi đó là *lệnh* của người dùng — nút "Xong", đóng overlay, submit form: dùng `View.hideKeyboard()` (`Common/Extensions/View+Keyboard.swift`). Ranh giới: recognizer nền xử lý tap vào vùng trống; lệnh tường minh xử lý phần còn lại.
* **Nếu phải sửa `KeyboardDismissGesture`, giữ ba thiết lập sau** — mỗi cái chặn một lỗi cụ thể: `cancelsTouchesInView = false` (không thì nút/hàng `List` mất touch), `shouldRecognizeSimultaneouslyWith → true` (không thì pan của scroll view và tap chọn hàng bị chặn), và `shouldReceive touch` bỏ qua ô **đang nhập được** (không thì bấm vào chính ô đang gõ lại tắt bàn phím). Thêm loại ô nhập mới thì sửa trong `isEditableTextInput` bằng `as?` + cờ `isEnabled`/`isEditable`, **không** so tên class.
* **Chỉ cài lên `UIWindow` ở level `.normal`.** Cài lên window của toast/TTS widget/widget trình duyệt (quanh level `.alert`, hit-test passthrough) là vô ích và gây nhiễu; bàn phím nằm ở window hệ thống riêng nên vốn không đi qua đây.
* **Recognizer chỉ được tồn tại trong quãng bàn phím đang hiện (1.3.323).** `keyboardWillShowNotification` cài, `keyboardWillHideNotification` gỡ — **không** được "cài một lần rồi để đó cho gọn". `handleTap` gọi `endEditing(true)`, và lệnh đó buộc **first responder bất kỳ** trong window resign, kể cả `UITextView` chỉ đọc của Reader hay `WKContentView` của web view đang giữ vùng bôi đen ⇒ mất vùng chọn ở đúng nhịp thả tay, hay gặp nhất với vùng bôi **ngắn** (tap chỉ fail khi ngón di chuyển quá ngưỡng, không phải khi giữ lâu). Bộ lọc `shouldReceive` không thay được hàng rào này: nó không phân biệt được "tap vào chữ" với "vừa bôi đen xong rồi thả tay". `uninstall()` phải quét **mọi** window, không lọc `windowLevel`/`isHidden` như lúc cài, nếu không window đã ẩn sẽ giữ lại recognizer mồ côi.

## Next-chapter prefix audio invariants (1.3.234)

* Cửa sổ prefetch đoạn văn **vẫn bị chặn ở biên chương**: `updatePrefetchWindow` và `updateNghiPrefetchWindow` không bao giờ tạo index vượt `paragraphs.count` của chương đang phát. Phần thiếu ở cuối chương được lấp bằng **chunk đầu của chương kế** do `TTSNextChapterPrefixCache` sở hữu, chứ không bằng cách mở rộng không gian index của `preloadedData`.
* `TTSNextChapterPrefixCache` chỉ giữ chunk index `>= 1`. Chunk 0 của chương kế vẫn thuộc `TTSChapterPrefetcher` (nó có đường claim in-flight riêng khi chuyển chương). Prefix chỉ được yêu cầu khi state của prefetcher đã là `.synthesizingAudio` hoặc `.audioReady`, nhờ đó chunk 0 luôn vào hàng đợi trước ở cùng hoặc cao hơn mức ưu tiên.
* **Trần bộ nhớ không đổi** — prefix chỉ *tái phân bổ* các slot đang trống, và mỗi engine dùng đúng đơn vị đo của chính nó:
  - **Google/Ext — theo `preload_size`/`googlePrefetchCount`**: `capacity = max(0, count - inChapterTargetCount - 1)` với `count = max(1, min(10, currentPrefetchCount))`. Vì `inChapterTargetCount + 1 (chunk 0) + capacity == count`, **độ sâu buffer phía trước luôn bằng đúng `count` chunk kể cả khi đi qua biên chương**, và tổng payload vẫn `<= count + 1` như lúc ở giữa chương.
  - **NghiTTS — theo watermark cached-time**: prefix là phần kéo dài của **cùng một** `cachedTime`. `calculateNghiCachedTime()` cộng thêm chuỗi chunk prefix **liên tục ngay sau chunk 0** của chương kế, nên chuỗi phát liên tục được đo **vượt qua biên chương**. Khi chương hiện tại đã hết ứng viên (`selectNghiOptionalRefillCandidate == nil`) mà `cachedTime < nghittsSafeCachedTimeThreshold`, prefix được nạp tiếp cho đủ ngưỡng; đạt ngưỡng thì dừng nạp và **giữ** chunk đã có (không thu hồi). Số chunk bị chặn bởi phần còn trống của `NghiSynthesisPolicy.maxTotalAudioPayloads` (5), tính bằng `preloadedData.count + (hasPreparedNext ? 1 : 0) + (reservesNghiAudioSlot ? 1 : 0)` — phép đếm này cố ý **thiên về bảo thủ** (có thể đếm trùng một payload) để không bao giờ vượt trần.
  - Khi chương hiện tại vẫn còn ứng viên, prefix bị thu hồi về 0 (`capacity: 0`) — chương đang phát luôn được ưu tiên trước.
* Prefix đi qua đúng coordinator của engine ở **mức ưu tiên thấp nhất** (`.optionalReserve` cho Nghi, `.nextChapter` cho remote) và **không** có vòng retry riêng ở tầng manager.
* **Mọi cấu hình chunk/pacing của cửa sổ đoạn văn đều được áp cho prefix**:
  - *Số ký tự mỗi phân đoạn*: đã nằm trong `key.chunkLength` (với extension là `max_length` từ JSON config). Remote tiêu thụ DTO đã chunk hoá bởi `TTSBackgroundProcessor.processChapter(chunkLength: key.chunkLength)`; Nghi chunk lại bằng `NghiUtteranceSegmenter.expand(_:maximumLength: key.chunkLength)`.
  - *Khoảng giãn giữa các request remote*: `TTSAudioSynthesisWorker.synthesizeParagraph(offset: index, prefetchDelayMs: prefetchDelayMs)` — cùng cơ chế `sleep(offset × max(300, prefetchDelayMs))` như prefetch trong chương (`googlePrefetchCount`/`prefetchDelayMs` của Google, `extPrefetchDelay_<tool>` của extension). NghiTTS không có cấu hình này nên không áp; nó được điều tiết bằng watermark + `PiperSynthesisCoordinator`.
  - Ngoại lệ có chủ ý: **chunk 0** chương kế (do `TTSChapterPrefetcher.startAudioSynthesis` sở hữu) vẫn dùng `offset: 0, prefetchDelayMs: 0` vì đó là slot bắt buộc cần có sớm nhất; chỉ các chunk prefix đầu cơ mới bị giãn.
* **Highlight của prefix hoạt động y hệt chunk thường, và không thể lệch.** Highlight do `commitAudibleParagraphState` phát ra từ `paragraphs[index].range`/`paragraphs[index].paragraphIndex` của chương **đã áp dụng**, hoàn toàn độc lập với nguồn gốc của byte audio; đường phát chunk từ cache vẫn gọi `commitAudibleParagraphState` (remote: `playAudioData` sau `player.play()`; Nghi: `NghiAudioPlayerQueue.onTransition`/`onScheduleHandoff` với `item.paragraphIndex`). Điều kiện duy nhất là audio ở `index` phải là audio của đúng `paragraphs[index]`, và nó được cưỡng chế **hai lớp**: (1) `consume(matching:)` yêu cầu `TTSPreparedNextChapterKey` trùng tuyệt đối; (2) `mergeNextChapterPrefixAudio` còn so `PreparedChunk.finalText` với `applyReplacements(paragraphs[index].text)` đã trim — lệch thì bỏ chunk đó (log `textMismatch`) và chương mới tổng hợp lại như bình thường. Nhờ lớp (2), mọi trường hợp DTO bị dựng lại (fallback load, force-refresh nội dung) đều an toàn dù key không đổi.
* Mọi chunk gắn với đúng một `TTSPreparedNextChapterKey`. `consume(matching:)` chỉ trả dữ liệu khi key trùng tuyệt đối; key được dựng lại tại `applyNextChapter` từ `TTSChapterInfo` của chương vừa áp dụng, nên đổi giọng/pitch/chunkLength/cờ dịch/từ điển giữa lúc nạp trước và lúc chuyển chương luôn làm dữ liệu cũ bị loại thay vì phát sai cấu hình.
* Chunk hoá của prefix dùng `key.chunkLength` (không dùng giá trị hiện hành của manager) để index luôn nhất quán với chính key mà nó được lưu dưới.
* **Chống lặp và chống ghi trễ, dùng lại đúng cơ chế của cửa sổ đoạn văn**:
  - Mỗi task prefix mang một token theo index; `finishSynthesis` chỉ ghi khi khớp cả `generation`, `activeKey` **và** token — tương ứng `removePrefetchTask(for:taskGen:)` của prefetch trong chương, tránh task cũ đã bị `trim` hủy xóa mất entry của task mới.
  - Lỗi được phân loại bằng **chính** `TTSManager.evaluateRefillError(_:currentAttempts:maxAttempts: 2)` (single source với refill NghiTTS): non-retryable hoặc hết 2 attempt thì index bị block tới khi `reset()`; audio rỗng bị block ngay từ attempt đầu; `CancellationError` không tính attempt và không log.
  - Prefix **không** có retry task/backoff riêng: attempt kế tiếp chỉ xảy ra ở lần đánh giá cửa sổ tiếp theo.
* Pause hủy tổng hợp prefix đang bay nhưng **giữ** chunk đã xong và trạng thái lỗi (`cancelPendingWork`); stop, đổi `tool` và đổi `selectedVoice` giải phóng toàn bộ qua `clearAllTTSCaches` → `resetNextChapterPrefixCache`.

## Normative Architecture Rules (Refactor v4.1/v4.2/v5.0)

* **Physical File Line Limit**: New Swift files created during refactoring must stay <= 400 physical lines. Legacy files exceeding 400 lines are tracked in `Scripts/architecture_allowlist.json` and must ratchet downward.
* **One Primary Type Per File**: Each Swift file must declare exactly one primary type (class, struct, enum, or actor).
* **SwiftData Write Coordinators**: SwiftUI Views must not perform direct `modelContext` write mutations (`insert`, `delete`, `save`). All write transactions are owned by domain transaction coordinators (`ExtensionTransactionCoordinator`, `BookTransactionCoordinator`) accepting immutable Command DTOs/IDs.
* **Services Layer Boundaries**: `Sources/Services/` must not import `SwiftUI` and must not invoke `ToastManager.shared` directly. The `SERVICE_SWIFTUI_IMPORT` check exempts only files whose name ends with `WebViewLoader.swift` (currently `WebViewLoader.swift` and `VisibleWebViewLoader.swift`); as of this revision no Services file imports SwiftUI at all, so the exemption is a standing allowance rather than an active carve-out.
* **Presentation Event Center**: UI presentation events (toasts) emitted by background services use thread-safe `AsyncStream` event centers (`TTSPresentationEventCenter`, `DownloadPresentationEventCenter`) with `AppLaunchRootView` as the sole UI presentation subscriber.
* **VBook JS Runtime Boundaries**: Extraction operations use short-lived `JSExecutor` instances; only `ExtTTSRuntime` may persist a long-lived runtime. All extension calls must preserve `execute(...)`, `runAsync`, global API injections (`Html`, `Engine`, `Response`, `fetch`), and root vs `src/` script path resolution.
* **Logging and Observability**: Log via `AppLogger.shared` with structured tags; do not use raw `print`. Never log secrets, full chapter payloads, or sensitive user data.
* **Security**: Enforce `validatePathSafety(for:)` on all physical file operations. Validate external URLs and input data at extension boundaries. Never expose API keys.
* **Test Layer Removed (1.3.235, user-directed)**: tầng test không còn tồn tại — `Tests/` và target `FreeBookTests` đã bị xoá khỏi repo và `project.yml`. Không tạo lại thư mục `Tests/` hay target test khi người dùng chưa yêu cầu rõ ràng. Xác minh tính đúng dựa trên đọc code, build trên macOS và hai script tĩnh (`validate_links.py`, `check_architecture.py`); không được viện dẫn test làm bằng chứng.
* **UI Views & Event Handlers**: SwiftUI Views must perform zero direct file I/O or SwiftData mutations. `@Query` reads are permitted for reactive presentation only; user actions must dispatch command DTOs to Coordinators.
* **Code Placement Naming Matrix**:
  - `View`: SwiftUI visual interface element under `Sources/Views/`
  - `ViewModel`: `@MainActor` state model binding View to Services/Coordinators
  - `Coordinator`: Domain transaction or flow manager handling multi-step processes or persistence
  - `Repository`: Single source of truth data access layer for domain entities
  - `Store`: Specialized low-level persistence engine (e.g., `ChapterStore`, `ReadingProgressStore`)
  - `Service`: Core business logic or platform interface under `Sources/Services/`
  - `Engine`: Low-level execution engine (e.g., `JSExecutor`, `ONNXPiperEngine`)
  - `Adapter`: Platform or framework bridge layer
  - `Worker`: Background unit of work actor/task (e.g., `BackgroundPagingWorker`)
  - `DTO` / `Command`: Immutable value types representing transactions or payloads
  - `Snapshot`: Immutable thread-safe copy of entity state for cross-isolation transport
  - `Mapper` / `Formatter`: Pure functional converter between models or text formatting

* **Add-Code Checklist**:
  1. Primary directory placement: `Sources/App`, `Sources/Common`, `Sources/Models`, `Sources/Services`, `Sources/Views`.
  2. Dependencies: Views -> ViewModel/Coordinator -> Services/Repositories -> Models. Views MUST NOT import SwiftData or perform direct `modelContext` write mutations.
  3. Physical Line Limit: Max 400 lines for new files; legacy allowlisted files must ratchet down.
  4. Exactly 1 primary type per file.
  5. Services must not import SwiftUI (exemption matches file names ending `WebViewLoader.swift`) or invoke ToastManager.shared.
  6. Không tạo lại `Tests/` hay target test (tầng test đã bị xoá ở 1.3.235).
  7. CodeGraph docs must be updated factually and validated with `validate_links.py`.

## Thermal State Invariants (Phase 0.1)

* `ProcessInfo.ThermalState` is diagnostic/logging-only for NghiTTS and does not cancel or suppress audio refill or next-chapter prefetch.

## NghiTTS safeCachedTimeSeconds prefetch and contiguous scheduler invariants (1.3.116)

* `nghittsSafeCachedTimeSeconds` is a user-configurable, persistent NghiTTS duration setting (`UserDefaults` key `"nghittsSafeCachedTimeSeconds"`, default 8.0s, allowed 4.0...20.0s, UI step 1.0s). Old installations without the key fallback to 8.0s without error.
* `cachedTime` counts only the contiguous playable audio chain at the current playback rate: current player remaining time + prepared $N+1$ + sequential preloaded $N+2...$, stopping at the first missing gap. Chapter $K+1/0$ is counted only when every remaining chunk in chapter $K$ is ready and $K+1/0$ audio is ready.
* Immediate successor $N+1$ and chapter $K+1/0$ are mandatory slots. When `cachedTime < nghittsSafeCachedTimeSeconds`, optional reserve chunks ($N+2, N+3$) are synthesized sequentially up to at most 2 optional reserve items. Max 5 logical audio payloads total (current + $N+1$ + 2 optional + $K+1/0$).
* When `cachedTime >= nghittsSafeCachedTimeSeconds`, refill stops and one cancellable deadline sleep task (`nghiWakeTask`) is scheduled to wake when `cachedTime` is predicted to cross the threshold. No polling loops.
* `PiperSynthesisCoordinator` uses a 4-level priority queue (`demand = 4` > `immediateSuccessor = 3` > `nextChapterMandatory = 2` > `optionalReserve = 1`). Exact synthesis keys coalesce duplicate requests, promote pending priority, and claim in-flight ONNX inference on demand.
* Pause cancels queued speculative requests (`cancelPendingRequests()`) while allowing an active ONNX inference to complete and cache. While paused, audio does not autoplay or chain further speculative refill.
* Thermal state (`ProcessInfo.ThermalState`) is diagnostic/logging-only for NghiTTS and does not cancel or suppress audio refill or next-chapter prefetch.
* Changing `nghittsSafeCachedTimeSeconds` during active playback reschedules `nghiWakeTask` and re-evaluates refill immediately without clearing valid preloaded audio or interrupting playback. Opening/closing Settings when ONLY `nghittsSafeCachedTimeSeconds` changed does not stop/restart playback, rebuild paragraphs, or clear preloaded audio.

## Chapter repository memory and cancellation invariants (1.3.114)

* `ChapterContentRepository` is the sole shared chapter-content cache and must bound normalized documents by both recency and estimated memory cost: at most 12 entries and 12 MiB. A single document larger than the cost budget bypasses shared RAM caching but is still returned to its caller and may remain persistent on disk.
* A memory warning clears only reusable repository RAM snapshots. Documents already retained by Reader/TTS, in-flight subscriber state, and persistent chapter content remain valid.
* One in-flight chapter operation may serve multiple Reader/TTS subscribers. Canceling a subscriber must resume only that waiter with `CancellationError`; the underlying operation is canceled only after its final waiter leaves. Force refresh supersedes the prior operation and cancels all of its waiters.
* Cancellation from the final waiter must propagate through persistent lookup and extension execution. Once fetched content has passed the final cancellation checkpoint and entered shared memory, its background persistence write must not be canceled by Reader dismissal.
* `TTSManager` must own fallback auto-advance work. Stop, engine/session replacement, or a newer chapter advance cancels the prior task; canceled/superseded work must not stop playback as an ordinary load failure or commit stale chapter state. If repository force-refresh supersedes only the shared load while playback itself remains active, auto-advance may reattach once to the replacement operation.

## TTS presentation energy invariants (1.3.112)

* The floating TTS cover must remain static during sustained playback; a continuously scheduled `TimelineView` or display-rate decorative animation is forbidden. Expanded/peeking mode changes must reuse the parent-owned decoded image and must not start a new cover load.
* App root, Shelf, Reader, and floating widget must not observe the entire `TTSManager` when they render only a subset of its state. Projection readers publish deduplicated snapshots, and Reader highlight state must collapse to inactive when the playing `bookId` does not match its scoped book.
* Lock Screen book title, chapter title, translation result, and artwork are static metadata keyed by book/chapter/cover/translation generation. Only one static metadata task may be active; paragraph transitions update only timeline, progress, speed, and playback state.
* NghiTTS model preparation is lazy: app initialization may warm the model only when `tool == "nghitts"`; selecting another engine cancels pending warm-up.

## TTS highlight coordinate invariants (1.3.81, supersedes 1.3.80)

* `TTSParagraph.range` is expressed in UTF-16 offsets of the **displayed** string (`TTSLineEntry.translatedText` — the translated line when VietPhrase is on, the original line when it is off) and is **relative to its parent line**, not absolute within the chapter. `TTSParagraph.sourceRange` is the range mapped back onto the original text.
* Reader and TTS share one coordinate space by construction: `TTSBackgroundProcessor.processChapter` translates **line by line first**, then rebuilds through `reconstructContentPreservingLineIDs` → `ChapterTextNormalizer.normalizeProcessedContent`, so the TTS `normalizedContent` and Reader's `ParagraphItem` list describe the same string.
* Therefore `ReaderView` passes `ttsState.snapshot.highlightRange` **directly** to `ParagraphCardView` → `ReaderTextView` with no remapping. Correctness is enforced by identity guards (`playingBookId`, `playingChapterIndex`, `currentParentParagraphIndex`), not by coordinate translation.
* `ReaderSelectionMapper.mapHighlight`, `mappedRangeUsingOriginalSpans`, and `proportionalHighlightFallback` were removed in 1.3.81 because the pipeline no longer produces a coordinate mismatch. **Do not reintroduce them and do not wrap the highlight range in any mapper.**
* `ReaderSelectionMapper` retains only the reverse direction for user selection: `mapSelection(_:in:isTranslationEnabled:bookId:)` maps a selection on the displayed string back onto the original text for dictionary lookup. Stored `translationSpans` take precedence; the sentence/token heuristic is fallback-only when spans are empty or do not cover the selection.
* Range validity checks guard against crashes only; they must never be relied on as correctness of alignment.

## Reader/TTS normalized-text invariants (1.3.15)

* `ChapterTextNormalizer` is the only component allowed to canonicalize chapter newlines, remove blank lines, assign paragraph IDs, and calculate UTF-16 ranges.
* `ChapterTextLine.id` is the **raw line index and counts blank lines**, so paragraph IDs are sparse and are never array offsets: `"Một\n\nHai"` yields ids `[0, 2]`. `ParagraphItem.id` and `TTSParagraph.paragraphIndex` inherit that property; always look up by `id`. The chapter-title chunk uses `-1` on both sides.
* `ChapterTextLine.utf16Range` is computed over the string **before** blank lines are dropped, so it must not be used to slice `NormalizedChapterText.content`.
* `ChapterDocument` is created once by `ChapterContentRepository`; Reader and TTS builders must consume its normalized lines without re-splitting or re-numbering.
* TTS chunks may split a line but must retain the parent `ChapterTextLine.id`; replacement output must be non-empty before extension synthesis.
* TTS owns progress while playing. Reader snapshots are ignored during TTS ownership and all checkpoints flush through `ReadingProgressStore` off the MainActor.
* TOC navigation carries an immutable `ReaderRoute.chapterIndex`; filtering and sorting must never convert an original chapter index into a filtered-row offset.
* `ChapterContentRepository` is the only chapter-content loader: memory -> SwiftData -> extension. Non-empty normalized content read via `BookBinManager` based on `Chapter.offset`, `Chapter.length`, and `Chapter.isCached` is authoritative. The production `Chapter` model does not store the text content directly in the database.
* **Sandbox File Security**: All operations on physical files (like cover images or chapter `.bin` files) must perform security validation (`validatePathSafety(for:)`) to ensure files are located inside the application support directory, preventing path traversal attacks.
* **Atomic Database-First Deletion**: When deleting a book, the database model modifications must be committed (via `ModelContext.save()`) successfully before starting the background cleaning task of physical files on a detached background thread.
* **UserDefaults-Backed Deletion Retry**: Failed physical file deletions must be queued in a background retry queue saved in `UserDefaults` (`failed_file_deletions_queue`) and drained on app launch (`drainRetryQueue()`), with a maximum limit of 3 retries per file to prevent resource leaks.
* Reader and TTS may share chapter documents/in-flight loads, but playback/navigation sessions remain isolated by `bookId`, chapter identity, and TTS `sessionID`; a Reader for another book must never prepare or seek the active TTS session.
* Fetched chapter content enters shared memory before background persistence. Reader dismissal must flush, not cancel, pending chapter writes.

## Reader paragraph invariants (1.3.14)

* Split original chapter content before translation. Each original line, including an empty or trailing line, must produce exactly one translated line and one `ParagraphItem` with the same stable index.
* All selection and translation offsets exchanged with UIKit must use UTF-16 `NSRange` semantics.
* The definition editor must resolve `chapterIndex + paragraph id` and use `ParagraphItem.original` as its only source text; translated text may only be used to map the selected range.
* Exact stored spans take precedence. The historical sentence/token heuristic is fallback-only when span coverage is missing or invalid.

## 1. Thứ tự Ưu tiên Thẩm quyền (Priority of Authority / Source of Truth Hierarchy)

Thứ tự ưu tiên thẩm quyền của tài liệu và mã nguồn khi xảy ra xung đột thông tin được định nghĩa theo cấp bậc sau:
1.  **`Docs/CodeGraph/rules.md`** (Normative Specification / The current approved technical specification. Unless explicitly changed by the user or project maintainers, AI must treat it as the authoritative technical standard).
2.  **`Source Code`** (Actual Implementation / Triển khai thực tế - những gì code đang thực thi).
3.  **`Docs/CodeGraph/*`** (Descriptive Documentation / Tài liệu mô tả - những gì tài liệu mô tả về mã nguồn).
4.  **Các tài liệu khác** (Other documentation).

> [!NOTE]
> **This authority order is only used to resolve conflicts between artifacts. It does not define the normal development workflow.**
> *(Thứ tự ưu tiên thẩm quyền này chỉ được sử dụng khi xảy ra xung đột giữa các tài liệu hoặc mã nguồn. Nó không định nghĩa hay thay thế quy trình phát triển thông thường).*

*   **Bản chất**: `rules.md` là tài liệu quy phạm (những gì dự án cần tuân thủ), trong khi `Docs/CodeGraph/*` là tài liệu mô tả (những gì mã nguồn đang thực thi hiện tại).
*   **Quy trình xử lý sai lệch (Deviation Handling)**: AI phải thực hiện quy trình sau khi phát hiện sự sai lệch:
    *   **Xác minh**: Kiểm tra xem sai lệch là **chủ ý thiết kế mới** (intentional change) hay là **lỗi lập trình** (stale/bug).
    *   **Lỗi / Sai lệch**: Tiến hành sửa đổi `Source Code` để tuân thủ quy chuẩn trong `rules.md`.
    *   **Quy tắc cũ / Thay đổi kiến trúc**: Cập nhật `rules.md` trước (chỉ khi bản thân quy chuẩn kỹ thuật của dự án thay đổi) để ghi nhận quy tắc mới $\rightarrow$ Đồng bộ `Source Code` (nếu cần) $\rightarrow$ Cập nhật `Docs/CodeGraph/*` tương ứng để phản ánh trạng thái thực tế mới.
    *   **Yêu cầu trực tiếp từ người dùng (User-directed change)**: Nếu người dùng hoặc maintainer yêu cầu thay đổi tính năng, kiến trúc hoặc quy tắc (chỉ áp dụng khi yêu cầu của người dùng có sửa code):
        1. Thực hiện thay đổi theo yêu cầu trên **Source Code**.
        2. Đánh giá xem thay đổi đó có làm thay đổi quy chuẩn của dự án (**`rules.md`**) hay không.
        3. Nếu có, cập nhật **`rules.md`**.
        4. Cuối cùng cập nhật **`Docs/CodeGraph/*`** để phản ánh trạng thái mới.
    *   **Trường hợp không rõ (UNKNOWN)**: Nếu AI không đủ bằng chứng để xác định liệu sai lệch là chủ ý hay lỗi, **bắt buộc phải đánh dấu UNKNOWN** và yêu cầu người dùng xác nhận thay vì tự suy đoán.
    *   **Không tự ý sửa**: Tuyệt đối không tự ý sửa `Source Code` chỉ để khớp với `rules.md` khi chưa xác minh `rules.md` vẫn là quy tắc hiện hành.

*   **Lưu ý**: Đa số các tính năng thông thường (ordinary features) không cần sửa `rules.md`.

*   **Ví dụ minh họa (Examples)**:
    *   *Code khác CodeGraph* $\rightarrow$ Cập nhật CodeGraph.
    *   *Code khác rules.md vì rules.md cũ* $\rightarrow$ 1. Cập nhật rules.md; 2. Đồng bộ Source Code (nếu cần); 3. Cập nhật Docs/CodeGraph/* để phản ánh trạng thái mới.
    *   *Code khác rules.md do bug* $\rightarrow$ Sửa Source Code để tuân thủ rules.md.
    *   *Người dùng yêu cầu thay đổi tính năng/kiến trúc* $\rightarrow$ 1. Sửa Source Code; 2. Đánh giá và cập nhật rules.md (nếu đổi quy chuẩn); 3. Cập nhật Docs/CodeGraph/*.

---

## 2. Quy tắc Bảo trì CodeGraph (Maintenance Rules)

*   **Không tạo lại toàn bộ (No Full Regeneration)**: Chỉ phân tích và chỉnh sửa các tài liệu bị ảnh hưởng trực tiếp bởi thay đổi code. Giữ nguyên các tài liệu khác.
*   **Bảo vệ ghi chú của con người (Preserve Human Edits)**:
    *   Mọi nội dung tự động sinh bởi AI nằm trong khối comment bắt đầu bằng `GENERATED_START` và kết thúc bằng `GENERATED_END` (không chứa khoảng trắng để tránh xung đột parser).
    *   AI chỉ được phép chỉnh sửa nội dung bên trong vùng này.
    *   **Tuyệt đối không** ghi đè, xóa hoặc sửa đổi bất kỳ nội dung nào nằm ngoài vùng này.
*   **Đồng bộ khi Rename / Delete / Move file**:
    *   If a Swift file is renamed, moved, or deleted, the AI must update all relative path references in `Docs/CodeGraph/` and remove orphan references.

---

## 3. Quy tắc Kích hoạt Cập nhật (Trigger Rules)

CodeGraph bắt buộc phải được đồng bộ hóa lập tức khi có bất kỳ thay đổi nào sau đây:
*   Thêm file mới, xóa file hoặc di chuyển/đổi tên file Swift.
*   Thay đổi Public API của các Manager, Service, hoặc ViewModel.
*   Thay đổi định nghĩa Protocol.
*   Thay đổi mối quan hệ phụ thuộc (Dependency) giữa các thành phần.
*   Thay đổi Máy trạng thái (State Machine) điều khiển TTS, Tải xuống, hoặc Đọc truyện.
*   Thay đổi quan hệ sở hữu đối tượng (Ownership Graph).
*   Thay đổi luồng điều hướng màn hình (Navigation).
*   Thay đổi cấu trúc mô hình SwiftData (`@Model`).
*   Thay đổi cấu hình Audio Pipeline (`AVAudioEngine`, `AVAudioSession`) hoặc TTS Pipeline.

---

## 4. Kiến thức Dự án & Cấu trúc Thư mục (Project Knowledge)

### 4.1. Cấu trúc thư mục mã nguồn
Dự án FreeBook được tổ chức theo cấu trúc phân tầng nghiêm ngặt:
*   **Common (`Sources/Common`)**: Chứa các thành phần dùng chung cho toàn dự án.
    *   `Extensions/`: Các phần mở rộng (Extensions/Helpers) dùng chung (`String+HTML.swift`, `View+Keyboard.swift`, `String+Crypto.swift`...).
    *   `Services/`: Các Service/Manager dùng chung cho toàn bộ ứng dụng (`ImageCacheManager.swift`, `ToastManager.swift`...).
*   **Models (`Sources/Models`)**:
    *   `Database/`: All SwiftData persistable model classes (`Book`, `Chapter`, `Extension`, `Repository`, `DownloadTaskModel` — the `ModelContainer` schema in `FreeBookApp.swift` registers all five).
    *   `Dictionaries/`: All translation lookup data structure classes (`DoubleArrayTrie`, `TextDictionary`, `SearchEngine`).
*   **Views (`Sources/Views`)**: Tổ chức thành các thư mục con theo module chức năng độc lập:
    *   `Shelf/ShelfMain/`: Chỉ chứa kệ sách chính (`ShelfView.swift`).
    *   `Discovery/`: Tab Khám phá (`DiscoveryView.swift`).
    *   `BookDetail/`: Chi tiết sách (`BookDetailView.swift`).
    *   `Search/`: Tìm kiếm truyện (`SearchView.swift`).
    *   `Reader/`: Trình đọc truyện (`ReaderView.swift` và các view phụ trợ).
    *   `TTSWidget/`: Floating widget điều khiển giọng đọc trên trình đọc.
    *   `Dictionary/`: Tra cứu từ điển (`DictionaryHubView.swift`, `DictionaryListView.swift`...).
    *   `Download/`: Quản lý tiến trình tải sách (`DownloadTrackerView.swift`, `TaskOptionsSheet.swift`).
    *   `Extensions/`: Quản lý extension, chia làm các thư mục con `Config/`, `Store/`, `Manager/`.
    *   `Settings/`: Cấu hình hệ thống, chia làm các thư mục con `Main/`, `Search/`, `TTS/`.
    *   `Common/`: Các view phụ trợ dùng chung (`BypassWebView.swift`, `DocumentPicker.swift`, `BookCoverView.swift`...).
*   **Services (`Sources/Services`)**: Tổ chức thành các thư mục con theo mảng dịch vụ chức năng:
    *   `TTS/`: Dịch vụ phát âm TTS.
        *   Thư mục gốc `TTS/`: Các bộ điều khiển và định nghĩa dùng chung (`TTSManager.swift`, `EspeakPhonemizer.swift`, `WAVEncoder`...) và thư mục `Preprocessing/`.
        *   `NghiTTS/`: Chứa client NghiTTS và lõi Piper offline (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `ModelStore.swift`).
        *   `Siri/`: Chứa dịch vụ phát âm native Siri (`SiriTTSService.swift`).
        *   `Ext/`: Chứa dịch vụ phát âm qua Extension JS (`ExtTTSService.swift`).
    *   `Extensions/`: Engine chạy extension javascript.
        *   `Engine/`: Core thực thi JS (`JSExecutor.swift`, `JSDom.swift`, `JSCrypto.swift`).
        *   `Manager/`: `ExtensionManager.swift`.
    *   `Translation/`: Dịch thuật tự động.
        *   `Manager/`: `TranslationManager.swift`.
        *   `Utils/`: `TranslateUtils.swift`, `DictionaryCache.swift`.
    *   `Download/`: `DownloadManager.swift`, `BookDownloadWorker.swift`, `DownloadTaskOutcomeCalculator.swift`.
    *   `Logging/`: `AppLogger.swift`.

### 4.2. JavaScript Core Runtime & VBook Extensions Integration
*   **Script Entrypoint**: Tên hàm bắt đầu thực thi bên trong toàn bộ các tệp JavaScript (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) phải là `execute(...)`, được gọi bất đồng bộ qua `runAsync` trong `ExtensionManager.swift`.
*   **Script File Path Resolution**: Các tệp JS script có thể đặt ở thư mục gốc của extension hoặc trong thư mục `src/`. `ExtensionManager` sẽ quét cả hai vị trí này.
*   **Injected Global JS Objects**: Các đối tượng global được inject vào `JSContext`:
    *   `Html`: Parser cầu nối DOM (`Html.parse(...)`, `element.attributes()`, `elements.isEmpty()`, `elements.map()`).
    *   `console`, `Console`, `print`, `Log`: Chuyển hướng `log` ra console in logs (`AppLogger`).
    *   `fetch`: API tải mạng đồng bộ/bất đồng bộ kèm `response.statusText`, `url`, `headers`, `header()`, `blob()`, `request`.
    *   `Response`: `Response.success(data)` và `Response.error(message)`.
    *   `Engine`: Headless browser giả lập (`Engine.newBrowser()`, `newVisibleBrowser()`).
    *   `Qt`: Quick Translator bridge (`Qt.translate(text, to, extras)`) và các tiện ích mã hóa.
    *   `localStorage`, `cacheStorage`, `localConfig`, `localCookie`: Hệ thống lưu trữ và cấu hình tiện ích mở rộng.
    *   `UserAgent`, `Crypto`, `Script`, `Http`: Các bộ công cụ giả lập môi trường VBook Android & WebKit.

---

## 5. Các Quy định Lập trình chi tiết (Coding Rules)

### 5.1. SwiftData Rules
*   **Tên**: Không sử dụng bộ lọc chuỗi trên Predicate trong `@Query`
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Tránh viết các câu lệnh truy vấn lọc chuỗi trực tiếp trong Predicate của SwiftUI `@Query`. Thay vào đó, hãy query toàn bộ danh sách và thực hiện lọc trên RAM bằng computed property.
*   **Lý do**: Bộ dịch truy vấn SQLite của SwiftData trên iOS 17 gặp lỗi dịch câu lệnh chuỗi gây ra kết quả không chính xác hoặc lỗi biên dịch.
*   **Ví dụ đúng**:
    ```swift
    @Query private var allExtensions: [Extension]
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    @Query(filter: #Predicate<Extension> { !$0.localPath.isEmpty && $0.isEnabled })
    private var activeExtensions: [Extension]
    ```

### 5.2. Architecture Rules
*   **Tên**: Không import SwiftUI vào các lớp nghiệp vụ Manager / Service
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Tầng Manager và Service tuyệt đối không được import framework `SwiftUI` hay giữ tham chiếu đến giao diện (View).
*   **Lý do**: Đảm bảo tính độc lập của logic nghiệp vụ, phục vụ unit testing dễ dàng và ngăn chặn rò rỉ bộ nhớ.
*   **Ví dụ đúng**:
    ```swift
    // Trong Sources/Services/Translation/Manager/TranslationManager.swift
    import Foundation
    public final class TranslationManager: ObservableObject { ... }
    ```
*   **Ví dụ sai**:
    ```swift
    import SwiftUI
    public final class TranslationManager: ObservableObject {
        var statusLabelView: Text? // Vi phạm kiến trúc
    }
    ```

### 5.3. Concurrency Rules
*   **Tên**: Sử dụng ModelContext riêng biệt cho tác vụ chạy nền (Background Tasks)
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Mọi thao tác ghi hoặc cập nhật thực thể SwiftData trong các tác vụ nền phải tạo một `ModelContext` mới từ `ModelContainer` dùng chung và không dùng chung context với MainActor.
*   **Lý do**: Tránh lỗi tranh chấp dữ liệu và lỗi crash truy cập sai luồng của SwiftData.
*   **Ví dụ đúng**:
    ```swift
    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        let allBooks = (try? bgContext.fetch(FetchDescriptor<Book>())) ?? []
        try? bgContext.save()
    }
    ```
*   **Ví dụ sai**:
    ```swift
    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let allBooks = (try? viewModel.modelContext.fetch(FetchDescriptor<Book>())) ?? []
        try? viewModel.modelContext.save()
    }
    ```

### 5.4. SwiftUI Rules
*   **Tên**: Lưu bookmark tiến độ đọc truyện khẩn cấp khi chuyển nền
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: View chính của trình đọc phải lắng nghe sự kiện thay đổi trạng thái của app (`scenePhase == .background`) để lưu bookmark vị trí đọc hiện tại ngay lập tức.
*   **Lý do**: Hệ điều hành iOS có thể chấm dứt ứng dụng chạy ngầm bất cứ lúc nào để giải phóng RAM, gây mất bookmark của người đọc nếu không lưu kịp thời.
*   **Ví dụ đúng**:
    ```swift
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .background {
            viewModel?.saveProgressImmediately()
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    .onDisappear {
        viewModel?.saveProgressImmediately()
    }
    ```
*   **Tên**: Chuẩn hoá kích thước Header, Toolbar Icon và khoảng cách nút bấm
*   **Loại quy tắc**: **Normative Rule**
*   **Mô tả**:
    *   **Kích thước Icon Header chuẩn**: Mọi icon trên Header, NavigationBar, Toolbar của toàn bộ các màn hình bắt buộc dùng font `.system(size: 17, weight: .semibold)` (tương đương chuẩn Apple SF Pro Header Action). Nghiêm cấm dùng icon tùy tiện (`.title3` 20pt, 13pt, 14pt hoặc default regular).
    *   **Khung chạm (Hitbox) & Khoảng cách (Spacing)**:
        *   Custom Header Bar / Toolbar: Khoảng cách giữa các nút liền kề tối thiểu **`6pt`**; khung chạm (hitbox) tối thiểu **`36 x 36pt`** (khuyến nghị **`36 x 38pt`**).
        *   Nút tròn (Circle button): Kích thước chuẩn **`38 x 38pt`** (icon 17pt semibold).
        *   Nút dạng viên thuốc (Pill/Capsule button) cùng hàng: Chiều cao chuẩn **`38pt`** (`frame(height: 38)`, `cornerRadius: 19`).
        *   Nút Quay lại (Back button): Khung bấm mở rộng tối thiểu **`38 x 44pt`** để chạm dễ dàng.
        *   Menu phụ / mục lục chương lồng bên trong: Kích thước icon chuẩn **`14pt semibold`**, frame tối thiểu **`32 x 32pt`**, spacing tối thiểu **`4pt`**.
*   **Lý do**: Đảm bảo trải nghiệm thị giác đồng nhất, cân đối thẩm mỹ trên toàn app và ngăn chặn tình trạng nút bấm quá sát nhau hoặc icon lệch kích thước khi bổ sung màn hình mới.
*   **Ví dụ đúng**:
    ```swift
    // Navigation Toolbar icon chuẩn
    ToolbarItem(placement: .primaryAction) {
        Button(action: showOptions) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
        }
    }

    // Custom Header HStack
    HStack(spacing: 6) {
        Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 38)
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    // Icon quá nhỏ, quá lớn hoặc thiếu semibold
    Image(systemName: "ellipsis.circle")
    Image(systemName: "gearshape")
        .font(.title3) // 20pt, quá to
    HStack(spacing: 2) { ... } // Dính sát, khó bấm
    ```

### 5.5. Audio Rules
*   **Tên**: Tránh chặn Main Thread bằng Semaphore khi tải WebView ngầm
*   **Loại quy tắc**: **Recommended Rule**
*   **Mô tả**: Không sử dụng `DispatchSemaphore` chờ đồng bộ trên Main Thread khi chạy `WKWebView` để bypass Cloudflare hoặc nạp web động.
*   **Lý do**: Gây hiện tượng Deadlock vĩnh viễn vì WKWebView yêu cầu chạy trên Main Thread nhưng Main Thread lại bị Semaphore khóa cứng.
*   **Ví dụ đúng**:
    ```swift
    func loadWebView(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            loader.load(url: url) { html in
                continuation.resume(returning: html)
            }
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        loader.load(url: url) { html in
            semaphore.signal()
        }
    }
    _ = semaphore.wait(timeout: .now() + 5.0) // Gây Deadlock vĩnh viễn trên Main Thread
    ```

### 5.6. TTS Rules
*   **Tên**: Dọn dẹp cửa sổ trượt prefetch audio của đoạn văn
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Bộ đệm audio đoạn văn là `preloadedData` (dữ liệu WAV/MP3) đi kèm `preloadedDurations`; mọi index nằm ngoài cửa sổ trượt hiện hành phải bị loại bỏ. Cửa sổ khác nhau theo engine:
    *   Google/Ext (`updatePrefetchWindow`): giữ `[N, N + count]` với `count = max(1, min(10, currentPrefetchCount))` — `currentPrefetchCount` lấy từ `googlePrefetchCount` (2-10) hoặc `preload_size` của extension.
    *   NghiTTS (`updateNghiPrefetchWindow`): giữ đoạn hiện tại `N`, đoạn kế `N + 1` (slot bắt buộc), tối đa `NghiSynthesisPolicy.maxOptionalReserveItems` (2) optional reserve từ `N + 2`, cộng audio chương kế do `TTSChapterPrefetcher` giữ riêng.
*   **Lý do**: Buffer âm thanh thô tiêu tốn rất nhiều bộ nhớ RAM, nếu không dọn dẹp sẽ gây crash app vì cạn bộ nhớ (OOM).
*   **Ví dụ đúng**:
    ```swift
    let cacheKeepIndices = Set(Array(N...(N + count)))
    for idx in preloadedData.keys where !cacheKeepIndices.contains(idx) {
        preloadedData.removeValue(forKey: idx)
        preloadedDurations.removeValue(forKey: idx)
    }
    ```
*   **Ví dụ sai**:
    ```swift
    preloadedData[index] = data // Không bao giờ giải phóng
    ```

### 5.7. Extension Rules
*   **Tên**: Phân tách vòng đời JSExecutor bóc tách, Ext TTS và Tải truyện (Download)
*   **Loại quy tắc**: **Normative Rule**
*   **Mô tả**:
    * Các tác vụ bóc tách nội dung ngắn hạn (`search`, `detail`, `toc`, `home`, `genre`) tiếp tục tạo `JSExecutor` ngắn hạn và giải phóng sau mỗi lần chạy.
    * Ext TTS được phép dùng một `ExtTTSRuntime` actor giữ `JSExecutor` lâu dài cho extension/config đang hoạt động vì TTS gọi cùng script theo từng chunk.
    * Tác vụ tải/xuất truyện của `DownloadManager` sử dụng duy nhất một `BookDownloadWorker` actor cho mỗi sách để giữ `JSExecutor` chạy tuần tự cho toàn bộ các chương của tác vụ đó, hỗ trợ ngắt hủy request tức thì và giải phóng khi hoàn tất.
*   **Lý do**: Bóc tách đơn lẻ cần cô lập trạng thái; Ext TTS và Download cần tránh tạo và bootstrap lại `JSContext` hàng trăm lần liên tục cho cùng một sách.
*   **Ví dụ đúng**:
    ```swift
    public func chap(url: String) async throws -> String {
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        return try await executor.runAsync(...)
    }

    actor ExtTTSRuntime {
        private var executor: JSExecutor? // Dùng tuần tự cho TTS hiện tại
    }

    actor BookDownloadWorker {
        private var executor: JSExecutor? // Dùng tuần tự cho tác vụ tải/xuất sách hiện tại
    }
    ```
*   **Ví dụ sai**:
    ```swift
    public final class ExtensionManager {
        private let sharedExecutor = JSExecutor() // Dùng chung không kiểm soát cho mọi loại script
    }
    ```

### 5.7.1. Remote TTS Scheduling Rules
* `prefetchDepth` là số chunk muốn giữ trong cache, không phải số request được chạy đồng thời.
* Mọi tổng hợp Google/Ext, kể cả đọc đoạn được chọn và audio chương kế tiếp, phải đi qua `RemoteTTSSynthesisCoordinator` với tối đa một operation đang hoạt động.
* Thứ tự ưu tiên bắt buộc là `current > prefetch > nextChapter`; request cùng key phải được gộp để không tổng hợp trùng.
* Remote TTS prefetch tuần tự 1 worker và không bị điều tiết hay hủy bởi `thermalState`. Extension TTS tự động áp dụng `preload_size` và `max_length` từ JSON config (ẩn trên UI); Google TTS hiển thị `googlePrefetchCount` (2-10 đoạn), Stepper `chunkLength` (50-500 ký tự) và `prefetchDelayMs` (tối thiểu 300ms).
* Mô hình 2 Worker chuyên trách độc lập cho Trình nghe TTS: Worker 1 (`TTSChapterTextWorker`) kích hoạt nạp trước DTO chữ chương $K+1$ khi $N \ge \text{count}/2$ hoặc $\text{remainingParents} \le 3$; Worker 2 (`TTSAudioSynthesisWorker`) tổng hợp âm thanh MP3/PCM vào bộ đệm RAM.
* Đối với Google/Ext, retry chỉ được sở hữu bởi service, tối đa hai attempt tổng cộng cho mỗi synthesis; `TTSManager` không được bọc thêm vòng retry cho Remote TTS.

### 5.7.2. NghiTTS Energy Rules
* NghiTTS synthesis phải tiếp tục đi qua `PiperSynthesisCoordinator` với tối đa một inference đang chạy.
* ORT/XNNPACK mặc định chỉ dùng một worker; không tăng thread count theo số core vì nghe lâu là sustained workload.
* `NghiSynthesisPolicy` là nguồn duy nhất cho watermark cached-time (`defaultSafeCachedTimeThreshold = 8.0`, dải `safeCachedTimeThresholdRange = 4.0...20.0`) và `maxOptionalReserveItems = 2`; không lặp các hằng số này trong manager/prefetcher. Policy này **không** chứa cooldown hay thermal eligibility — đừng thêm vào.
* Thermal state là diagnostic-only cho toàn bộ TTS (Nghi và Remote): nó chỉ cập nhật `TTSManager.currentThermalState` cho telemetry và làm nhãn trong energy log. Không được dùng `.serious`/`.critical` để hủy, điều tiết hay thu hẹp refill, prefetch, hoặc audio chương kế.
* Refill N+1 đang chạy phải được playback demand tái sử dụng; không được hủy rồi tổng hợp trùng cùng đoạn.
* Audio chương kế của NghiTTS do `TTSChapterPrefetcher` sở hữu và chỉ được promote khi chuỗi chunk còn lại của chương hiện tại đã đủ; nó không phải một slot refill của cửa sổ đoạn văn.
* Kết quả sau `TextPreprocessor` không còn ký tự có thể đọc phải được `PiperTTSService` chuyển thành WAV/PCM khoảng lặng hợp lệ. Luồng streaming phải phát đúng một terminal chunk và không chuyển chuỗi rỗng vào ONNX/eSpeak.
* NghiTTS refill được phép retry tại `TTSManager` vì đây là chính sách cửa sổ prefetch, không phải retry nội bộ engine: tối đa hai attempt tổng cộng cho mỗi session/chapter/paragraph (`evaluateRefillError(maxAttempts: 2)`), retry backoff 1 giây, lỗi model/engine/request không retry bị block ngay.
* Trong thời gian chờ backoff, scheduler không được tạo refill thay thế (`canScheduleNghiRefill` chặn khi còn `nghiRefillRetryTask`). Retry task phải xác thực session/chapter/generation, xóa reference của chính nó trước khi gọi lại prefetch, và bị hủy/reset khi stop, đổi session hoặc chuyển chương.
* `CancellationError` không được ghi failure state, log như synthesis failure hoặc lên lịch retry. Index đã block chỉ bị bỏ qua ở prefetch; foreground/on-demand synthesis vẫn giữ quyền thử lại.

### 5.8. Memory Rules
*   **Tên**: Tránh giữ strong reference `self` trong callback âm thanh ngầm
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Dùng `[weak self]` ở các callback schedule buffer hoặc các block xử lý luồng âm thanh ngầm.
*   **Lý do**: Tránh tạo ra strong reference cycle giữ chặt `TTSManager` hoặc View Model trong bộ nhớ RAM, gây rò rỉ bộ nhớ.
*   **Ví dụ đúng**:
    ```swift
    player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
        DispatchQueue.main.async {
            guard let self = self, self.isPlaying else { return }
            self.nextParagraph()
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    player.scheduleBuffer(buffer, at: nil, options: []) {
        self.nextParagraph()
    }
    ```

### 5.9. Logging Rules
*   **Tên**: Ghi log ngoại lệ chi tiết của JS Engine ra tệp logs
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Toàn bộ thông tin crash, exception của JS phải được lưu vào file `app_logs.txt` trong thư mục `applicationSupportDirectory` (không phải `Documents`). `AppLogger.init` set `isLoggingEnabled = false` mỗi lần khởi chạy và tự xóa file khi vượt 5 MB, nên phải bật lại trong Settings mới thấy log mới.
*   **Lý do**: Nhà phát triển ứng dụng cài app qua LiveContainer test trực tiếp trên iOS vật lý, không thể debug qua Xcode Console.
*   **Ví dụ đúng**:
    ```swift
    context.exceptionHandler = { context, exception in
        let desc = exception?.toString() ?? ""
        AppLogger.shared.log("❌ JSContext Exception: \(desc)")
    }
    ```
*   **Ví dụ sai**:
    ```swift
    context.exceptionHandler = { context, exception in
        print("❌ JSContext Exception: \(exception)")
    }
    ```

### 5.10. Performance Rules
*   **Tên**: Giới hạn lưu tiến độ đọc (Debounce DB Save)
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Chỉ thực hiện lưu DB tiến độ khi người dùng dịch chuyển ít nhất 3 đoạn văn trở lên và áp dụng trì hoãn lưu 3 giây (`Task.sleep`).
*   **Lý do**: Giảm tần suất ghi đĩa I/O của SwiftData liên tục khi người đọc cuộn trang nhanh, tránh làm đơ/lag UI.
*   **Ví dụ đúng**:
    ```swift
    if abs(newProgress.paragraphIndex - last.paragraphIndex) >= 3 {
        dbSaveTask?.cancel()
        dbSaveTask = Task {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            repository.saveProgress(newProgress)
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    repository.saveProgress(newProgress)
    ```

### 5.11. Testing Rules
*   **Tên**: Kiểm tra chéo toàn bộ liên kết tài liệu phân tích (Cross Validation)
*   **Loại quy tắc**: **Recommended Rule**
*   **Mô tả**: Đảm bảo số lượng file quét trùng khớp với thư mục, không có markdown link bị hỏng, và tất cả UNKNOWN đều ghi rõ nguyên nhân.
*   **Lý do**: Tối ưu hóa bộ tài liệu phân tích để AI assistant có thể hiểu sâu sắc mà không bị đi vào các liên kết chết.
*   **Ví dụ đúng**: Chạy script quét link kiểm tra trước khi hoàn thiện tài liệu.
*   **Ví dụ sai**: Bỏ qua bước kiểm tra liên kết sau khi viết markdown.

### 5.12. Coding Rules
*   **Tên**: Save path plugin gốc vào `downloadUrl` khi đồng bộ repo
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Lưu trực tiếp thuộc tính `path` từ `plugin.json` của repo vào `downloadUrl` của model `Extension`.
*   **Lý do**: Đảm bảo link tải zip của plugin chính xác và thống nhất.
*   **Ví dụ đúng**:
    ```swift
    extension.downloadUrl = item.path
    ```
*   **Ví dụ sai**:
    ```swift
    extension.downloadUrl = "https://raw.githubusercontent.com/.../plugin.zip"
    ```

---

## 6. Quy định mở rộng về Chất lượng Code (AI Expanded Policies)

### 6.1. Quy tắc Biên dịch & An toàn Concurrency (Compile & Concurrency Rules)
- **Compile Rule**: Mọi thay đổi mã nguồn phải cố gắng giữ khả năng biên dịch thành công của dự án. Tránh tuyệt đối các lỗi về thiếu ký hiệu (missing symbols), vi phạm Actor isolation (`@MainActor`), xử lý sai luồng SwiftData (phải dùng background context riêng) và vòng lặp tham chiếu mạnh (retain cycles/strong reference).
- **UNKNOWN Rule**: Khi xây dựng các đồ thị phân tích (Call Graph, State Machine, Ownership Graph, Dependency, Event Graph), nếu phương pháp phân tích tĩnh (static analysis) không thể chứng minh hoặc xác thực một mối quan hệ/đường gọi cụ thể (ví dụ: callback, dynamic dispatch, dynamic event), bắt buộc phải đánh dấu mối quan hệ đó là `UNKNOWN` hoặc `PARTIAL` kèm theo lý do cụ thể, tuyệt đối không được tự ý suy đoán dựa trên kinh nghiệm.

### 6.2. Quy trình Validation & CodeGraph Refresh Policy
- **Validation Failure Policy**: Chạy `python Docs/CodeGraph/validate_links.py`. Nếu kịch bản phát hiện bất kỳ lỗi nào (như tệp manifest không khớp, liên kết chết, sai định dạng front matter hoặc GENERATED comment), AI bắt buộc phải sửa lỗi và chạy lại; không được báo cáo hoàn thành khi validation chưa PASS 100%.
- **Doc Routing Policy (manifest `schemaVersion: 2`)**: Mỗi doc khai `sourcePatterns` (glob tương đối gốc repo) là phạm vi mã nguồn nó chịu trách nhiệm mô tả, cộng `staleOn`:
  * `staleOn: "structure"` — doc chỉ bị stale khi *tập* file khớp pattern thay đổi (thêm/xoá/đổi tên). Dùng cho doc mô tả bản đồ file và số liệu tổng: `00_index.md`, `02_file_graph.md`, `09_dependency_rules.md`, `14_complexity_report.md`.
  * `staleOn: "content"` — doc bị stale khi tập file thay đổi *hoặc* nội dung file trong phạm vi thay đổi. Dùng cho doc mô tả hành vi: `01_project.md`, `03`–`08`, `10`–`13`, `rules.md`.
  * **Coverage Rule (hai điều kiện, validator FAIL kèm tên file nếu vi phạm)**: (1) mọi file `Sources/**/*.swift` phải khớp `sourcePatterns` của ít nhất một doc; (2) mọi file phải được ít nhất một doc `staleOn: "content"` phủ — nếu một file chỉ nằm trong doc `structure` thì sửa nội dung nó sẽ không làm doc nào stale, đúng lỗ hổng khiến "đổi logic mà tài liệu không đổi". `11_subsystems.md` phủ toàn bộ `Sources/Services/**` + `Sources/Views/**` để giữ điều kiện (2); thêm thư mục mã nguồn mới thì phải mở rộng pattern của doc phụ trách.
  * Sửa `sourcePatterns` là thay đổi hợp đồng routing: chạy `--bootstrap` để tính lại toàn bộ hash, và chỉ dùng cờ này cho đúng mục đích đó.
- **Manifest Hash Policy**: `structureHash` là SHA-256 của *tập đường dẫn* khớp `sourcePatterns` (đổi khi thêm/xoá/đổi tên file); `sourceHash` là SHA-256 của đường dẫn + nội dung đã chuẩn hoá LF (đổi khi sửa logic); `generatedHash` là SHA-256 của nội dung giữa cặp marker GENERATED đã chuẩn hoá LF. Ba hash này chỉ được ghi lại qua validator, không sửa tay.
- **Doc Review Policy**: Sau thay đổi source, chạy `--explain` (thêm `--since REF` để so với một commit) để biết doc nào bị stale và vì sao, rồi ghi nhận từng doc:
  * `--accept DOC…` — doc đã được sửa. Validator **từ chối** nếu vùng GENERATED của doc đó không đổi, nên không thể "bless" hàng loạt mà không thực sự viết lại tài liệu.
  * `--no-change-needed DOC…` — đã đọc doc, kết luận nội dung vẫn đúng với code mới. Lựa chọn này được ghi vào `reviewMode`/`reviewedAt`/`reviewedCommit` để có audit trail; đây là cách hợp lệ duy nhất để bỏ qua một doc bị stale.
  * `--update-hashes` — accept mọi doc có vùng GENERATED đã đổi, sau đó **FAIL** nếu còn doc stale (liệt kê doc còn lại). Nó không còn là lệnh xoá sạch tín hiệu stale như trước.
  * `DOC` nhận `08`, `08_lifecycle.md` hoặc đường dẫn đầy đủ.
- **Full CodeGraph Refresh Policy**: Khi phát sinh các thay đổi mang tính cấu trúc lớn, tái cấu trúc thư mục dự án hoặc chỉnh sửa đồng loạt trên khoảng 20 file mã nguồn Swift trở lên, AI phải đề xuất hoặc thực hiện làm mới toàn bộ hệ thống CodeGraph (Full CodeGraph Refresh) để đảm bảo tính đồng bộ hoàn toàn.

### 6.3. Thiết kế Kiến trúc & Tối ưu hóa Hiệu năng (Performance & Memory Rules)
- **Architecture Decision Rule**: Ưu tiên tối đa việc tái sử dụng các lớp Manager, Service và ViewModel sẵn có trong dự án (ví dụ: `TTSManager`, `ExtensionManager`, `DownloadManager`, `TranslationManager`). Tránh tạo ra duplicate logic hoặc tự ý xây dựng lại các kiến trúc thiết kế mới song song nếu không có yêu cầu cụ thể từ người dùng.
- **Logging Rule**: Mọi log runtime trong mã nguồn Swift hoặc engine JS phải sử dụng tiện ích `AppLogger` để ghi trực tiếp vào tệp logs `app_logs.txt` trong thư mục `applicationSupportDirectory` của thiết bị. Không sử dụng hoặc phụ thuộc vào Xcode Console (do môi trường chạy thực tế là LiveContainer trên iOS vật lý không thể đính Xcode). `AppLogger.log` tự gọi `print` bên trong — luật "không `print`" là không gọi trực tiếp ở nơi khác.
- **Performance & Memory Rules**:
  * Tránh khởi tạo lại thực thể `AVAudioEngine` nhiều lần không cần thiết.
  * NGHI-TTS playback must run strictly via `AVAudioPlayer` double-buffering queue (`NghiAudioPlayerQueue`). `AVAudioEngine` node streaming path must not be used.
  * Technical split chunks (`TTSBoundaryKind.technicalChunk`) must not append `paragraphPauseDuration` (0.5s) silence; paragraph silence applies only to `.paragraphEnd` or `.chapterEnd`.
  * Scheduled handoff transitions must call `commitParagraphState` without re-invoking `speakCurrent()` to prevent double-play bugs.
  * Tránh truy vấn (fetch) SwiftData dư thừa; ưu tiên sử dụng RAM cache (`ChapterCache`, `bookDicts`).
  * Đảm bảo hủy các `Task` chạy ngầm ngắt quãng (`Task.sleep`, prefetch tasks), gỡ bỏ `NotificationCenter` observers khi View hoặc ViewModel deinit để triệt tiêu nguy cơ rò rỉ bộ nhớ (retain cycle).

---

## 7. Checklist Tự kiểm tra trước khi Hoàn thành (AI Review Checklist)

Trước khi kết thúc lượt và thông báo hoàn thành, AI bắt buộc phải tự đánh giá mã nguồn và tài liệu theo checklist sau:
- [ ] **Compile**: Mã nguồn sửa đổi biên dịch thành công, không vi phạm Actor isolation, không lỗi threading SwiftData?
- [ ] **Architecture**: Tái sử dụng components cũ tối đa, tránh tạo logic trùng lặp, giữ vững Clean Architecture?
- [ ] **Extension**: Giữ nguyên tính tương thích ngược, không đổi API của tiện ích mở rộng nếu không được yêu cầu?
- [ ] **TTS & Audio**: Dọn dẹp `preloadedData`/`preloadedDurations` đúng cửa sổ trượt của từng engine (Google/Ext `[N, N + count]`, NghiTTS `N` + `N+1` + tối đa 2 optional reserve), tránh retain cycle?
- [ ] **UI & Header Standard**: Toàn bộ icon Header/Toolbar tuân thủ chuẩn font `.system(size: 17, weight: .semibold)`, hitbox tối thiểu 36x36pt (khuyến nghị 36x38pt), spacing tối thiểu 6pt?
- [ ] **Validation**: Chạy `validate_links.py --explain`, xử lý mọi doc bị stale bằng `--accept` (đã sửa) hoặc `--no-change-needed` (đã xem, vẫn đúng), rồi chạy read-only PASS 100%; cập nhật `manifest.json` và `CHANGELOG.md` thành công?
<!-- GENERATED END -->
