# FreeBook (Tàng Công Các)

Ứng dụng đọc truyện chữ cho iOS, viết bằng SwiftUI + SwiftData. Lấy truyện từ nguồn web qua extension JavaScript (tương thích VBook), dịch convert bằng VietPhrase, đọc thành tiếng bằng nhiều engine TTS (có engine offline chạy ONNX ngay trên máy) và có trợ lý AI ngay trong màn đọc.

- Tên hiển thị: **Tàng Công Các** · Bundle target: `FreeBook`
- iOS **17.0+** · Swift / SwiftUI / SwiftData · dự án sinh bằng **XcodeGen**
- Bản build chính thức là **IPA unsigned** do GitHub Actions đóng gói, cài qua sideload / LiveContainer.

---

## Tính năng

### Nguồn truyện & thư viện
- **Extension JavaScript (VBook)**: cài từ kho (repository) trực tuyến, tự đồng bộ cập nhật; mỗi extension có `search` / `home` / `genre` / `detail` / `toc` / `chap`. Có trình soạn script có tô màu cú pháp và cấu hình riêng từng extension.
- **Trình duyệt bypass** nhiều tab để vượt Cloudflare / đăng nhập trang nguồn, có widget nổi để mở lại.
- **Khám phá & tìm kiếm** trên nhiều nguồn cùng lúc, cấu hình bộ máy tìm kiếm.
- **Kệ sách** có bộ sưu tập, sửa thông tin truyện, đổi nguồn truyện.
- **Tải truyện offline** chạy nền (tuần tự từng truyện — cố ý, để không bị trang nguồn chặn), theo dõi trong màn tải.
- **Hộp thư chương mới**: tự kiểm tra truyện đang theo dõi có chương mới.
- **Nhập** TXT, EPUB, DOCX, FB2, MOBI, PDF, HTML · **Xuất** TXT, EPUB, FB2, MOBI.
- **Sao lưu / khôi phục** thư viện, chương, ảnh bìa, từ điển, extension và cài đặt — lưu cục bộ, **Google Drive** (có tự động sao lưu) hoặc **Telegram bot**.
- Tự dọn truyện cũ không đọc theo chính sách cấu hình được.

### Trình đọc
- Trang đọc dựng trên `UITextView` (TextKit 1): tuỳ chỉnh font, cỡ chữ, giãn dòng, màu nền; menu chọn chữ riêng thay menu hệ thống.
- Tra nghĩa ngay trên đoạn chọn: Hán-Việt, VietPhrase, nghĩa chi tiết; sửa từ điển / thêm luật ngay tại chỗ.
- Tìm trong chương, danh sách chương, xoá dòng rác, sao chép bản gốc.
- Lưu tiến độ đọc tự động (debounce, flush khi app vào nền).

### Dịch thuật
- **VietPhrase** với từ điển Hán-Việt / VietPhrase / Names, từ điển riêng theo từng truyện, nhập / xuất / chia sẻ từ điển.
- **Quick Translation Rules**: bộ luật viết lại câu có trình soạn, trình thử, chẩn đoán lỗi, độ ưu tiên và bật/tắt theo truyện.
- Bộ lọc rác nội dung, luật mục lục, phạm vi dịch theo nguồn.

### Đọc thành tiếng (TTS)

| Engine | Mô tả |
|---|---|
| **NghiTTS** | Piper chạy ONNX Runtime + eSpeak NG, hoàn toàn offline |
| **VieNeu** | Model tiếng Việt offline (ONNX), thư viện giọng, **nhân bản giọng** từ bản ghi âm, từ điển tiếng Nhật |
| **Siri** | `AVSpeechSynthesizer` của iOS |
| **Google Cloud TTS** | REST, cần API key lúc build |
| **Extension** | TTS do extension JavaScript tự định nghĩa |

- Tiền xử lý văn bản: đọc số tiếng Việt, phiên âm từ tiếng Anh/Nhật, luật regex, từ điển thay thế (chung và theo truyện), phiên âm lại hàng loạt.
- Highlight đoạn đang đọc trong trang đọc, tự chuyển chương, prefetch chương kế, điều khiển từ màn hình khoá / tai nghe, widget TTS nổi.
- Quản lý / tải model TTS trong app.

### Trợ lý AI
- Chat về chương đang đọc, gợi ý nhanh, nhiều phiên chat, bộ nhớ AI theo truyện, tự nén ngữ cảnh.
- **Quét tên riêng** nhiều chương rồi duyệt để đưa vào từ điển Names.
- Nhà cung cấp: Google Gemini (API hoặc **Gemini Web** đăng nhập tài khoản, không cần key), OpenAI, Anthropic Claude, OpenRouter, DeepSeek, Groq, Ollama và endpoint tuỳ chỉnh tương thích OpenAI.
- Widget AI nổi, có thể thu nhỏ khi đang đọc.

### Dành cho người viết extension
- **Debug server** trong app + extension VS Code ở [`Tools/VSCode/FreeBookExtDebug`](Tools/VSCode/FreeBookExtDebug) để chạy và gỡ lỗi script extension trên máy thật.
- Mẫu `plugin.json` và từng script: [`.agents/skills/vbook_helper/SKILL.md`](.agents/skills/vbook_helper/SKILL.md).

---

## Build

Chỉ build được trên **macOS** với Xcode (CI dùng `macos-15`). `FreeBook.xcodeproj` **không** được commit — luôn sinh từ `project.yml`.

```bash
brew install xcodegen
xcodegen generate          # chạy lại mỗi khi thêm / xoá / đổi tên file Swift
xcodebuild build -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

- Dependencies khai SPM trong `project.yml`, Xcode tự tải: **SwiftSoup**, **ZIPFoundation**, **ONNX Runtime**, **espeak-ng-spm** (+ `libsqlite3`).
- Target đặt `CODE_SIGNING_ALLOWED: NO`.
- `GOOGLE_CLOUD_TTS_API_KEY` lấy từ build setting → `Info.plist`. Build local không có key thì engine Google TTS không hoạt động — bình thường.

### CI

[`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml) chạy khi push `Sources/**` hoặc `project.yml` lên `main` (và vài nhánh phát triển): `xcodegen generate` → `xcodebuild archive` unsigned → đóng gói IPA kèm `espeak-ng-data` → gửi Telegram. CI **chỉ chứng minh biên dịch được**, không chạy test hay kiểm tra kiến trúc.

---

## Cấu trúc mã nguồn

```
Sources/
├── App/        FreeBookApp.swift — ModelContainer, cổng nạp từ điển, migration khởi động
├── Common/     tiện ích dùng chung, ImageCacheManager, ToastManager
├── Models/     @Model SwiftData (Repository, Extension, Book, Chapter, DownloadTaskModel), DTO, từ điển
├── Services/
│   ├── AI/            client OpenAI/Anthropic, Gemini Web, quét tên riêng, lịch sử chat
│   ├── Backup/        sao lưu cục bộ, Google Drive, Telegram
│   ├── Books/         transaction coordinator cho sách
│   ├── ChapterText/   ChapterContentRepository, ChapterTextNormalizer, ChapterStore (sqlite)
│   ├── Download/      DownloadManager, BookDownloadWorker, BookStorageManager
│   ├── Export/ Import/   các định dạng xuất / nhập
│   ├── Extensions/    JSExecutor + bootstrap API JS, quản lý kho, debug server
│   ├── NewChapters/   kiểm tra chương mới
│   ├── ReadingProgress/
│   ├── TTS/           TTSManager + NghiTTS, VieNeu, Siri, Google, Ext, Preprocessing
│   └── Translation/   VietPhrase, Quick Translation Rules
└── Views/      SwiftUI theo màn hình: Shelf, BookDetail, Reader (+AI), Discovery, Search,
                Download, Dictionary, Extensions, Settings, TTSWidget, Common
```

Dữ liệu app nằm dưới `Application Support`: `library.db` (SwiftData), `chapters/chapter_store.sqlite` (mục lục), `books/*.bin` (nội dung chương), `covers/`, `extensions/`, `translate/`, `FreeBook/TTS/`, `app_logs.txt`. File xuất nằm ở `Documents/Exports/`.

Luồng xử lý trung tâm: **normalize → paragraph → chunk → highlight** — `ChapterTextNormalizer` là nguồn duy nhất chuẩn hoá text chương, Reader và TTS dùng chung một `ChapterDocument`.

---

## Đóng góp

Đọc trước khi sửa code:

1. [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) — tổng quan kiến trúc, bất biến và các bẫy đã biết.
2. [`.agents/AGENTS.md`](.agents/AGENTS.md) — quy trình làm việc bắt buộc.
3. [`Docs/CodeGraph/rules.md`](Docs/CodeGraph/rules.md) — quy chuẩn kỹ thuật (thẩm quyền cao nhất).
4. [`Docs/CodeGraph/CHANGELOG.md`](Docs/CodeGraph/CHANGELOG.md) — lịch sử thay đổi `[1.3.NNN]`; tiêu đề entry trùng subject commit.

Công cụ kiểm tra chạy được trên mọi nền tảng:

```bash
python Scripts/check_architecture.py   # luật kích thước file, 1 type chính/file, tách View–SwiftData, Service không import SwiftUI
codegraph explore "<câu hỏi hoặc tên symbol>"
```

Quy ước chính: file Swift mới ≤ 400 dòng, mỗi file một type chính; View không ghi SwiftData trực tiếp mà qua `*TransactionCoordinator`; log chỉ qua `AppLogger.shared.log(...)`; comment và chuỗi giao diện viết tiếng Việt.
