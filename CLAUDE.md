# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Bắt buộc đọc trước khi sửa code

Repo này có quy trình AI riêng, **ưu tiên cao hơn hướng dẫn mặc định**:

1. `.agents/AGENTS.md` — workflow 8 bước bắt buộc cho mọi AI assistant.
2. `Docs/CodeGraph/00_index.md` — mục lục hệ thống tài liệu sống (15 file).
3. `Docs/CodeGraph/rules.md` — quy chuẩn kỹ thuật + checklist tự kiểm tra.

**Thứ tự thẩm quyền khi xung đột**: `rules.md` > Source Code > `Docs/CodeGraph/*` > tài liệu khác. Nếu không đủ bằng chứng để phân biệt sai lệch là chủ ý hay bug, phải đánh dấu `UNKNOWN` và hỏi người dùng — không tự suy đoán.

Sau khi sửa code phải: cập nhật tài liệu CodeGraph bị ảnh hưởng (chỉ trong vùng `<!-- GENERATED START -->` … `<!-- GENERATED END -->`, tuyệt đối không đụng nội dung ngoài vùng này), cập nhật `manifest.json` + `CHANGELOG.md`, chạy validator, và **kết thúc response bằng một trong hai cụm**: `"CodeGraph updated."` hoặc `"No CodeGraph update required."`

## Commands

Dự án là app iOS, dùng **XcodeGen** — file `.xcodeproj` không được commit mà sinh ra từ `project.yml`.

```bash
# Sinh FreeBook.xcodeproj (chạy lại mỗi khi thêm/xoá/đổi tên file Swift)
xcodegen generate

# Build
xcodebuild build -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Chạy toàn bộ test
xcodebuild test -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Chạy một test class
xcodebuild test ... -only-testing:FreeBookTests/ChapterTextNormalizerTests

# Chạy một test case đơn lẻ
xcodebuild test ... -only-testing:FreeBookTests/ChapterTextNormalizerTests/testNormalizationIsIdempotent
```

Validation tài liệu CodeGraph:

```bash
python Docs/CodeGraph/validate_links.py                  # read-only, phải PASS 100%
python Docs/CodeGraph/validate_links.py --update-hashes  # sau khi sửa source/vùng GENERATED
```

Chạy `--update-hashes` trước, rồi chạy lại chế độ read-only để xác nhận.

**Lưu ý môi trường**: build chỉ chạy được trên macOS. Repo có thể được mở trên Windows — khi đó không build/test tại chỗ được; kiểm chứng qua CI `.github/workflows/build-ipa.yml` hoặc máy Mac, và phải nói rõ điều này thay vì báo "đã test".

Target được cấu hình `CODE_SIGNING_ALLOWED: NO`. Dependencies (SwiftSoup, ZIPFoundation, ONNX Runtime, espeak-ng) khai báo SPM trong `project.yml`.

## Architecture

Phân tầng `Common` / `Models` / `Services` / `Views`. Manager và Service **không được import SwiftUI**.

### Trục dọc quan trọng nhất: normalize → paragraph → TTS chunk → highlight

Đây là nơi tập trung phần lớn độ phức tạp và cũng là nguồn bug hay gặp:

```
ChapterContentRepository            memory → SwiftData → extension fetch
  └─ ChapterTextNormalizer          nguồn DUY NHẤT chuẩn hoá newline, bỏ dòng trống,
                                    gán paragraph ID, tính NSRange UTF-16
       └─ ChapterDocument           tạo MỘT lần, Reader và TTS cùng dùng
            ├─ ReaderParagraphBuilder → [ParagraphItem] (original + translated + translationSpans)
            └─ TTSParagraphBuilder    → [TTSParagraph] (chunk theo dấu câu, giữ nguyên parent line ID)
```

**Bất biến bắt buộc** (chi tiết ở `rules.md`):

- Chỉ `ChapterTextNormalizer` được phép chuẩn hoá text chương. Reader/TTS builder tiêu thụ dòng đã normalize, **không tự tách lại hay đánh số lại**.
- Mọi offset trao đổi với UIKit là `NSRange` theo ngữ nghĩa **UTF-16**, không phải Swift `String.Index`.
- TTS chunk có thể cắt một dòng nhưng phải giữ `ChapterTextLine.id` của dòng cha.
- Khi TTS đang phát, **TTS sở hữu tiến độ đọc**; snapshot của Reader bị bỏ qua.

**Cạm bẫy hệ toạ độ**: `TTSParagraph.range` tính trên **text GỐC**, còn Reader lại hiển thị **bản dịch** khi bật VietPhrase. Range gốc không thể áp thẳng lên text đã dịch — phải ánh xạ qua `ParagraphItem.translationSpans` (`ReaderSelectionMapper`). Span chính xác được ưu tiên; heuristic câu/token chỉ dùng làm fallback khi span thiếu hoặc không hợp lệ.

### TTS

`TTSManager` điều phối 3 engine, chọn theo biến `tool`:

| `tool` | Engine | Vị trí |
|---|---|---|
| `nghitts` | Piper offline chạy ONNX Runtime | `Services/TTS/NghiTTS/` |
| `system` | AVSpeechSynthesizer native | `Services/TTS/Siri/` |
| `google` | Google Cloud TTS REST | `Services/TTS/Google/` |
| *(khác)* | Extension JavaScript tự định nghĩa | `Services/TTS/Ext/` |

Text đi qua `Preprocessing/` (đọc số tiếng Việt, chuyển tự Anh/Nhật, luật regex, từ điển thay thế) trước khi tổng hợp. Kết quả sau thay thế phải khác rỗng mới được đưa vào engine.

Cache buffer PCM (`preloadedWavs`) chỉ giữ cửa sổ trượt `[N, N+1]` — không dọn sẽ OOM. Callback audio ngầm phải dùng `[weak self]`.

### Dịch thuật VietPhrase

`TranslateUtils` là nơi tra từ điển và dựng `TranslatedTextResult { text, spans }`. `buildTranslationSpans` dò từng token dịch trong chuỗi kết quả; nếu **một** token không tìm thấy thì trả `[]` — code tiêu thụ span phải xử lý được trường hợp mảng rỗng này.

### Extension JavaScript (VBook)

Entrypoint mọi file JS (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) là hàm `execute(...)`, gọi qua `runAsync`. Script nằm ở gốc extension hoặc trong `src/`. Global inject vào `JSContext`: `Html`, `console`, `fetch`, `Response`, `Engine`. Mỗi tác vụ bóc tách tạo `JSExecutor` mới rồi giải phóng — không dùng executor dùng chung.

## Ràng buộc runtime cần nhớ

- **Logging**: dùng `AppLogger.shared.log(...)` ghi ra `app_logs.txt` trong `Documents`. Không dùng `print`/Xcode Console — app chạy thật qua LiveContainer trên máy iOS vật lý, không đính được debugger.
- **SwiftData**: không viết predicate lọc chuỗi trong `@Query` (bộ dịch SQLite iOS 17 lỗi) — query hết rồi lọc trên RAM bằng computed property. Tác vụ nền phải tạo `ModelContext` riêng từ `ModelContainer`.
- **Không chặn Main Thread** bằng `DispatchSemaphore` khi chờ `WKWebView` (bypass Cloudflare) — deadlock vĩnh viễn. Dùng `withCheckedContinuation`.
- **Tiến độ đọc**: chỉ lưu DB khi dịch chuyển ≥ 3 đoạn, debounce 3 giây; đồng thời lưu ngay khi `scenePhase == .background`.
- **Xoá sách**: `BookStorageManager` là điều phối viên duy nhất — commit DB xong mới xoá file nền; thao tác file phải qua `validatePathSafety(for:)`.

## Tests

XCTest trong `Tests/`, `@testable import FreeBook`. Test tập trung vào tầng logic thuần (normalizer, builder, translate utils, accounting) chứ không phải UI. Khi sửa trục normalize/paragraph/highlight, thêm test vào `Tests/ChapterTextNormalizerTests.swift` — file này đã có sẵn pattern assert range UTF-16 bằng cách so `NSString.substring(with:)` với `chunk.text`.
