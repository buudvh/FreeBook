# Tàng Công Các

Ứng dụng iOS để đọc truyện chữ, đọc truyện tranh và xem phim, viết bằng SwiftUI + SwiftData.

- **Nguồn nội dung:** web, qua tiện ích JavaScript (theo hợp đồng `extension-api.md` của Darkrai9x) hoặc nguồn sách Legado.
- **Truyện chữ:** dịch convert bằng VietPhrase, đọc thành tiếng bằng nhiều engine TTS (có engine offline chạy ONNX ngay trên máy), có trợ lý AI ngay trong màn đọc.

Thông tin dự án:
- **Tên:** tên hiển thị là **Tàng Công Các**. Tên kỹ thuật (target, scheme, module, bundle id, khoá lưu trữ, đường dẫn dữ liệu) vẫn là `FreeBook`.
- **Nền tảng:** iOS **17.0+** · Swift / SwiftUI / SwiftData · dự án sinh bằng **XcodeGen**.
- **Bản phát hành:** **IPA unsigned** do GitHub Actions đóng gói, cài qua **LiveContainer** (có nguồn cập nhật) hoặc sideload.

---

## Cài đặt và cập nhật

- **Nguồn LiveContainer** (định dạng AltStore): `https://raw.githubusercontent.com/buudvh/FreeBook/source/apps.json`. Thêm một lần trong LiveContainer, các bản sau tự hiện ở đó.
- **Mỗi lượt build xanh trên `main`:**
  - tạo GitHub Release `build-<số build>` kèm IPA, chỉ giữ **5** bản mới nhất;
  - gửi tin Telegram liệt kê đủ các commit của lượt đó.
- **Số phiên bản** lấy theo bản đầu của [`Docs/CodeGraph/CHANGELOG.md`](Docs/CodeGraph/CHANGELOG.md). **Số build** là số lượt chạy CI.
- **Báo bản mới trong app:**
  - App kiểm tra mỗi lần mở, và khi quay lại app sau hơn 30 phút.
  - Có bản mới thì hiện dải báo ở Kệ sách, một hàng ở Cài đặt › Thông Tin và chấm đỏ trên tab Cài đặt.
  - Bấm dòng "Phiên bản ứng dụng" để kiểm tra tay.
  - App không tự cài bản mới được, phải vào LiveContainer để cập nhật.

---

## Tính năng

### Nguồn và thư viện
- **Tiện ích JavaScript:**
  - Cài từ kho trực tuyến, tự kiểm tra cập nhật.
  - Mỗi tiện ích có `search` / `home` / `explore` / `genre` / `detail` / `toc` / `chap`, cho truyện chữ, truyện tranh hoặc video.
  - Có trình soạn script tô màu cú pháp và bộ kiểm tra tiện ích chạy hàng loạt.
  - Cấu hình riêng từng tiện ích: chặn quảng cáo, chế độ máy tính, dịch trang, kiểu thu nhỏ video…
- **Nguồn sách Legado**, có trình duyệt đăng nhập riêng.
- **Khám phá và tìm kiếm** trên nhiều nguồn cùng lúc. Lọc nội dung nhạy cảm (NSFW) theo nguồn hoặc theo từng truyện.
- **Kệ sách, Lịch sử, Bộ sưu tập:**
  - Ghim truyện, sửa thông tin truyện.
  - **Đổi nguồn** có ghi nhật ký: app tắt giữa chừng thì lần mở sau tự hoàn tất hoặc tự hoàn tác.
  - Truyện mất nguồn (tiện ích đã gỡ) được gợi ý chuyển sang tiện ích khác khớp link.
- **Tải offline** chạy nền. Mặc định tải tuần tự từng truyện để không bị trang nguồn chặn (cố ý). Chọn được 2–3 luồng và thời gian nghỉ, nhớ theo từng nguồn.
- **Hộp thư chương mới**: tự kiểm tra truyện đang theo dõi có chương mới.
- **Nhập:**
  - TXT, EPUB, DOCX, FB2, MOBI, PDF, HTML;
  - ZIP/CBZ ảnh thành truyện tranh;
  - MP4/MOV/M4V, hoặc ZIP chứa video, thành **một phim nhiều tập**.
- **Xuất:** TXT, EPUB, FB2, MOBI; truyện tranh ra CBZ/PDF; video đã tải.
- **Sao lưu / khôi phục** thư viện, chương, ảnh bìa, từ điển, tiện ích và cài đặt. Lưu cục bộ, lên **Google Drive** (có tự động sao lưu) hoặc qua **Telegram bot**.
- **Màn Dung lượng:**
  - đo dung lượng từng loại dữ liệu;
  - hiện ngay số đo lần trước, đo lại ngầm;
  - xoá được cache ảnh truyện tranh, file xuất và log.
- **Mở lại mục đang đọc / xem dở** khi mở app (tuỳ chọn, bỏ qua nội dung 18+).
- Tự dọn truyện cũ không đọc, theo chính sách cấu hình được.

### Trình đọc truyện chữ
- **Trang đọc** dựng trên `UITextView` (TextKit 1): tuỳ chỉnh font, cỡ chữ, giãn dòng, màu nền. Menu chọn chữ riêng thay menu hệ thống.
- **Tra nghĩa** ngay trên đoạn chọn: Hán-Việt, VietPhrase, nghĩa chi tiết. Sửa từ điển hoặc thêm luật ngay tại chỗ.
- **Công cụ trong chương:** tìm trong chương, xoá dòng rác, sao chép bản gốc.
- **Mục lục** dùng chung một kiểu panel ở Chi tiết, Reader và truyện tranh: có số thứ tự, có tìm kiếm, đảo được thứ tự.
- **Tiến độ đọc** lưu tự động: chờ ngắt rồi mới ghi, ghi ngay khi app vào nền.

### Truyện tranh
- Chạm để bật/tắt thanh điều khiển, chạm đúp để phóng to. Đổi chương bằng nút ở thanh dưới hoặc mục lục.
- Tải ảnh offline, có cache ảnh. Ảnh đi đường riêng, không qua pipeline văn bản.

### Video
- **Màn xem kiểu trình phát dọc:**
  - khung phim 16:9, thể loại dạng nhãn #, tên phim;
  - hàng nút Trên kệ / Tải / Đổi nguồn / Chia sẻ;
  - lưới chọn server, dải tập chia theo nhóm, bình luận;
  - đề xuất kiểu bảng tin. Bấm một phim đề xuất là đổi sang phim đó ngay tại chỗ.
- **Mở phim:** tự phát khi mở (tuỳ chọn). Tắt tiếng khi mở (tuỳ chọn, mặc định chỉ phim 18+). Phim đang tắt tiếng thì TTS vẫn đọc song song.
- **Điều khiển khi xem:**
  - tốc độ, phụ đề, khung hình;
  - chất lượng HLS, nhớ theo từng tiện ích;
  - vuốt để chỉnh độ sáng / âm lượng;
  - nút Toàn màn tự xoay theo khung phim.
- **Thu nhỏ:** **Hình trong hình (PiP)**, phát nền ở hub nổi. Vuốt xuống thì thu nhỏ vào hub hoặc PiP, tuỳ cài đặt.
- **Tải phim offline:** HLS được tải từng đoạn rồi phát lại qua server nội bộ `127.0.0.1`. MP4 phát thẳng từ file.

### Dịch thuật
- **VietPhrase:**
  - từ điển Hán-Việt / VietPhrase / Names;
  - từ điển riêng theo từng truyện;
  - nhập / xuất / chia sẻ từ điển.
- **Luật dịch nhanh:** bộ luật viết lại câu.
  - Có trình soạn, trình thử, chẩn đoán lỗi, độ ưu tiên, bật/tắt theo truyện.
  - Có bộ luật riêng cho tên chương.
  - Token trong luật: `<any>`, `<START>` / `<END>`, ngoặc `<[>` `<]>`…
  - Có trang hướng dẫn viết luật ngay trong app.
- **Khác:** bộ lọc rác nội dung, luật mục lục, phạm vi dịch theo nguồn, chuyển phồn thể sang giản thể theo truyện.

### Đọc thành tiếng (TTS)

| Engine | Mô tả |
|---|---|
| **NghiTTS** | Piper chạy ONNX Runtime + eSpeak NG, hoàn toàn offline |
| **VieNeu** | Model tiếng Việt offline (ONNX), thư viện giọng, **nhân bản giọng** từ bản ghi âm, từ điển tiếng Nhật |
| **Siri** | `AVSpeechSynthesizer` của iOS |
| **Google Cloud TTS** | REST, cần API key lúc build |
| **Tiện ích** | TTS do tiện ích JavaScript tự định nghĩa |

- **Tiền xử lý văn bản:**
  - đọc số tiếng Việt;
  - phiên âm từ tiếng Anh / Nhật;
  - luật regex;
  - từ điển thay thế, dùng chung hoặc theo truyện;
  - phiên âm lại hàng loạt.
- **Khi đọc:** highlight đoạn đang đọc trong trang đọc, tự chuyển chương, tải trước chương kế. Điều khiển được từ màn hình khoá và tai nghe. Có widget TTS nổi và hẹn giờ.
- Quản lý / tải model TTS ngay trong app.

### Trợ lý AI
- **Chat về chương đang đọc:** gợi ý nhanh, nhiều phiên chat, bộ nhớ AI theo truyện, tự nén ngữ cảnh.
- **Quét tên riêng** qua nhiều chương, duyệt lại rồi đưa vào từ điển Names.
- **Nhà cung cấp:**
  - Google Gemini: qua API, hoặc **Gemini Web** đăng nhập tài khoản, không cần key;
  - Chế độ AI của Google;
  - OpenAI, Anthropic Claude, OpenRouter, DeepSeek, Groq, Ollama;
  - endpoint tuỳ chỉnh tương thích OpenAI.
- AI chạy theo từng truyện, kết quả chưa xem được giữ lại trên hub nổi.

### Trình duyệt
- **Nhiều tab:** dùng để vượt Cloudflare và đăng nhập trang nguồn. Thu nhỏ thành widget nổi được.
- **Chặn quảng cáo** bằng bộ lọc AdGuard (`WKContentRuleList`), tự cập nhật bộ lọc.
- **Chỉnh riêng theo tên miền:** chế độ máy tính, chặn quảng cáo, dịch trang.
- **Dịch trang** bằng VietPhrase, có menu nhấn giữ riêng.

### Giao diện
- Màu nhấn tuỳ chọn, thanh tab tự vẽ, menu ba chấm dạng ngăn kéo kính mờ.
- **Hub nổi** gom các tiến trình đang chạy: TTS, tải, AI, video, kiểm tra nguồn.

### Dành cho người viết tiện ích
- **Debug server** trong app + extension VS Code ở [`Tools/VSCode/FreeBookExtDebug`](Tools/VSCode/FreeBookExtDebug): chạy và gỡ lỗi script tiện ích trên máy thật.
- Mẫu `plugin.json` và từng script: [`.agents/skills/extension_helper/SKILL.md`](.agents/skills/extension_helper/SKILL.md).
- **API JS có sẵn:**
  - `Html`, `Engine`, `fetch` (lỗi thì tự thử lại qua browser ẩn), `Crypto`;
  - `localStorage`, `Qt`;
  - `load('x.js')`, kèm `crypto.js` (CryptoJS) dựng sẵn.

---

## Build

Chỉ build được trên **macOS** với Xcode (CI dùng `macos-15`). `FreeBook.xcodeproj` **không** được commit, luôn sinh từ `project.yml`.

```bash
brew install xcodegen
xcodegen generate          # chạy lại mỗi khi thêm / xoá / đổi tên file Swift
xcodebuild build -project FreeBook.xcodeproj -scheme FreeBook \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

- **Dependencies** khai SPM trong `project.yml`, Xcode tự tải:
  - **SwiftSoup**, **ZIPFoundation**, **ONNX Runtime**, **espeak-ng-spm** (+ `libsqlite3`);
  - **SafariConverterLib** 4.3.1, giấy phép GPL-3.0. Thư viện này có build plugin nên dòng lệnh cần `-skipPackagePluginValidation`.
- Target đặt `CODE_SIGNING_ALLOWED: NO`.
- **Phiên bản:** bản build tay mang mặc định `1.3.0 (1)` của `project.yml`. Chỉ CI mới đặt số phiên bản thật.
- **API key Google TTS:** `GOOGLE_CLOUD_TTS_API_KEY` đi từ build setting vào `Info.plist`. Build local không có key thì engine Google TTS không chạy, chuyện bình thường.

### CI

[`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml) chạy khi push `Sources/**` hoặc `project.yml` lên `main`, theo các bước:

1. Lấy số phiên bản từ CHANGELOG, số build từ số lượt chạy.
2. `xcodegen generate` → `xcodebuild archive` unsigned → đóng gói IPA kèm `espeak-ng-data`.
3. Đăng GitHub Release và ghi `apps.json` lên nhánh `source`. Không sửa tay nhánh này.
4. Gửi IPA lên Telegram kèm danh sách commit. Tin được cắt cho vừa giới hạn và gửi lại khi lỗi.

CI **chỉ chứng minh biên dịch được**, không chạy test hay kiểm tra kiến trúc.

---

## Cấu trúc mã nguồn

```
Sources/
├── App/        FreeBookApp.swift — ModelContainer, cổng nạp từ điển, migration khởi động
├── Common/     tiện ích dùng chung, ImageCacheManager, ToastManager, AppVersionInfo
├── Models/     4 @Model SwiftData (Book, BookCollection, Chapter, DownloadTaskModel), bản ghi tiện ích (JSON),
│               nguồn Legado, DTO, từ điển
├── Services/
│   ├── AI/              client các nhà cung cấp, Gemini Web, quét tên riêng, lịch sử chat
│   ├── AppUpdate/       đọc nguồn apps.json, báo bản mới
│   ├── Backup/          sao lưu cục bộ, Google Drive, Telegram
│   ├── Books/           transaction coordinator cho sách, gắn lại nguồn
│   ├── Browser/         chặn quảng cáo AdGuard, dịch trang, menu nhấn giữ, chính sách nội dung web
│   ├── ChapterText/     ChapterContentRepository, ChapterTextNormalizer, ChapterStore (sqlite)
│   ├── Comic/ Video/    tải ảnh / phim offline, phiên phát video, PiP, màn xem
│   ├── Download/        DownloadManager, BookDownloadWorker, BookStorageManager, đổi nguồn
│   ├── Export/ Import/  các định dạng xuất / nhập
│   ├── Extensions/      JSExecutor + bootstrap API JS, kho tiện ích, debug server
│   ├── LegadoSource/    engine nguồn Legado
│   ├── Storage/         màn Dung lượng
│   ├── TTS/             TTSManager + NghiTTS, VieNeu, Siri, Google, Ext, Preprocessing
│   ├── Translation/     VietPhrase, luật dịch nhanh
│   └── …                Cleanup, Diagnostics, Images, Logging, NewChapters, ReadingProgress
└── Views/      SwiftUI theo màn hình: Shelf, BookDetail, Reader (+AI), ComicReader, VideoPlayer,
                Discovery, Search, Download, Dictionary, Extensions, Settings, FloatingHub,
                TTSWidget, ContentRouting, Common
```

**Dữ liệu app** nằm dưới `Application Support`:

| Đường dẫn | Nội dung |
|---|---|
| `library.db` | SwiftData |
| `chapters/chapter_store.sqlite` | mục lục chương |
| `books/*.bin` | nội dung chương |
| `covers/` | ảnh bìa |
| `extensions/` | script và icon của tiện ích |
| `extension_store/` | tiện ích đã cài, kho, `localStorage` |
| `comics/` | ảnh truyện tranh tải offline |
| `videos/` | phim tải offline |
| `adblock/` | bộ lọc chặn quảng cáo |
| `translate/` | từ điển và luật dịch |
| `FreeBook/TTS/` | dữ liệu TTS |
| `app_logs.txt` (+ file xoay vòng) | log |

Hai thư mục nằm ngoài `Application Support`:
- `Documents/Exports/`: file xuất.
- `Caches/comic_images/`: cache ảnh truyện tranh, hệ điều hành được phép xoá.

**Luồng xử lý trung tâm** của truyện chữ: **normalize → paragraph → chunk → highlight**. `ChapterTextNormalizer` là nguồn duy nhất chuẩn hoá text chương, Reader và TTS dùng chung một `ChapterDocument`. Ảnh truyện tranh và phim không đi qua luồng này.

---

## Đóng góp

Đọc trước khi sửa code:

1. [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md): tổng quan kiến trúc, bất biến và các bẫy đã biết.
2. [`.agents/AGENTS.md`](.agents/AGENTS.md): quy trình làm việc bắt buộc.
3. [`Docs/CodeGraph/rules.md`](Docs/CodeGraph/rules.md): quy chuẩn kỹ thuật, thẩm quyền cao nhất.
4. [`Docs/CodeGraph/CHANGELOG.md`](Docs/CodeGraph/CHANGELOG.md): lịch sử thay đổi `[1.3.NNN]`. Tiêu đề entry trùng subject commit, và bản đầu tiên là số phiên bản của lượt build kế.

Công cụ kiểm tra chạy được trên mọi nền tảng:

```bash
python Scripts/check_architecture.py   # luật kích thước file, 1 type chính/file, tách View–SwiftData, Service không import SwiftUI
codegraph explore "<câu hỏi hoặc tên symbol>"
```

Quy ước chính:
- File Swift mới ≤ 400 dòng, mỗi file một type chính.
- View không ghi SwiftData trực tiếp mà qua `*TransactionCoordinator`.
- Log chỉ qua `AppLogger.shared.log(...)`.
- Comment và chuỗi giao diện viết tiếng Việt.
