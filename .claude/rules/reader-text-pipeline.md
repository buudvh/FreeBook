---
paths:
  - "Sources/Views/Reader/**"
  - "Sources/Services/ChapterText/**"
  - "Sources/Services/TTS/**"
  - "Sources/Services/ReadingProgress/**"
  - "Sources/Services/Translation/Utils/**"
---

# Trục normalize → paragraph → chunk → highlight & Reader bridge UIKit

> Tách từ `AGENTS.md` (1.3.959). Claude Code tự nạp file này khi đọc / sửa file khớp `paths`; agent khác phải tự đọc trước khi sửa phân hệ này.

### Trục dọc quan trọng nhất: normalize → paragraph → chunk → highlight

Đây là nơi tập trung phần lớn độ phức tạp và cũng là nguồn bug hay gặp:

```
ChapterContentRepository            memory (12 entry/12 MiB) → SwiftData → extension fetch
  └─ ChapterTextNormalizer          nguồn DUY NHẤT chuẩn hoá newline, bỏ dòng trống,
     normalize / normalizeProcessedContent   gán line ID, tính NSRange UTF-16
       └─ NormalizedChapterText { content, lines: [ChapterTextLine] }
            └─ ChapterDocument      tạo MỘT lần, Reader và TTS cùng dùng
                 ├─ Reader: ReaderViewModel+Translation → [ParagraphItem]
                 │           (original + translated + translationSpans; title id = -1)
                 └─ TTS:    TTSBackgroundProcessor → TTSParagraphBuilder → [TTSParagraph]
                             (chunk theo dấu câu, giữ parent line ID)
```

`normalize()` chạy `JunkFilterManager.shared.filterRawContent` trước; `normalizeProcessedContent()` thì **không** lọc rác lần hai — dùng cho chuỗi đã qua xử lý/dịch.

**Bất biến bắt buộc**:

- Chỉ `ChapterTextNormalizer` được chuẩn hoá text chương. Reader/TTS builder tiêu thụ dòng đã normalize, **không tự tách lại hay đánh số lại**.
- **`ChapterTextLine.id` là chỉ số dòng thô, tính cả dòng trống** (`id: originalLineIndex`, `ChapterTextNormalizer.swift:40`), trong khi `content` chỉ join dòng không rỗng. Nên paragraph ID **thưa và không phải array index** — `"Một\n\nHai"` cho ids `[0, 2]`. Luôn tra theo `id`, đừng bao giờ dùng làm offset. `ParagraphItem.id` và `TTSParagraph.paragraphIndex` thừa hưởng đúng tính chất này.
- Hệ quả: `ChapterTextLine.utf16Range` tính trên chuỗi **trước khi lọc dòng trống** (`location += length + 1` chạy qua mọi component), nên nó **không** index được vào `NormalizedChapterText.content` khi chương có dòng trống. Đừng dùng nó để cắt `content`.
- Mọi offset trao đổi với UIKit là `NSRange` ngữ nghĩa **UTF-16**, không phải `String.Index`.
- TTS chunk có thể cắt một dòng nhưng phải giữ `ChapterTextLine.id` của dòng cha (`TTSParagraph.paragraphIndex`). Chunk tiêu đề chương dùng `paragraphIndex = -1` (khớp `ParagraphItem.id = -1`).
- Khi TTS đang phát, **TTS sở hữu tiến độ đọc**; `ReadingProgressStore` loại bỏ snapshot `.reader` khi sách đã bị `.tts` claim.

**Hệ toạ độ highlight — đọc kỹ, tài liệu cũ nói ngược:**

`TTSParagraph.range` là offset UTF-16 **trên chuỗi đang được hiển thị** (`TTSLineEntry.translatedText` — tức bản dịch khi bật VietPhrase, bản gốc khi tắt), và **tương đối với dòng cha**, không phải tuyệt đối theo chương. `TTSParagraph.sourceRange` mới là range ánh xạ về text gốc.

Lý do: `TTSBackgroundProcessor.processChapter` dịch **từng dòng trước**, rồi `reconstructContentPreservingLineIDs` → `normalizeProcessedContent`, nên `normalizedContent` của TTS và `ParagraphItem` của Reader nằm cùng một hệ toạ độ. Vì vậy `ReaderView` truyền `ttsState.snapshot.highlightRange` **thẳng** xuống `ParagraphCardView` → `ReaderTextView` không ánh xạ gì (guard theo `playingBookId`, `playingChapterIndex`, `currentParentParagraphIndex`). Hàm `ReaderSelectionMapper.mapHighlight` đã bị **xoá** ở 1.3.81 — đừng gọi lại nó.

`ReaderSelectionMapper` giờ chỉ còn chiều ngược cho *selection* của người dùng: `mapSelection(_:in:isTranslationEnabled:bookId:)` map từ chuỗi dịch về text gốc để tra từ điển, ưu tiên `translationSpans`, fallback heuristic câu/token khi span rỗng hoặc không phủ hết.

### Reader là bridge UIKit, đừng "đơn giản hoá" nó

`ReaderTextView` (`UIViewRepresentable` → `AutoSizingTextView : ReaderUITextView : UITextView`) có ba quyết định cố ý dễ bị coi là code cũ:

- Khởi tạo `AutoSizingTextView(usingTextLayoutManager: false)` (`ReaderTextView.swift:81`) — bắt buộc dùng TextKit 1, vì code cần `layoutManager.characterIndex(for:in:fractionOfDistanceBetweenInsertionPoints:)` (:209) để đổi điểm chạm thành offset ký tự. Bật TextKit 2 là mất API này.
- `ReaderUITextView.addInteraction` **chặn** `UITextInteraction(.nonEditable)` và `UIEditMenuInteraction` (:372-386) để dập menu Speak/Look Up/Share của hệ thống, nhường chỗ cho `FloatingSelectionMenu`.
- `updateUIView` (:108-230) diff tay text/font/theme/highlight; khi chỉ đổi highlight thì chỉ sửa attribute background trên `textStorage` thay vì gán lại text. Thay bằng gán thẳng là giật và mất selection.
