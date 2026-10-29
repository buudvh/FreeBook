import SwiftUI

/// Header section "tiêu đề + nút ?" dùng chung: đặt trong `header:` của `Section`, đoạn giải thích (trước là footer)
/// nằm trong popover của `SectionHelpButton`. Nhãn trợ năng của nút là "Giải thích <tiêu đề>".
///
/// Section khai bằng `Section("Tiêu đề") { … }` không có tham số header — phải đổi sang
/// `Section { … } header: { SectionHelpHeader(…) }`.
struct SectionHelpHeader: View {
    let title: String
    let texts: [Text]

    init(_ title: String, paragraphs: [LocalizedStringKey]) {
        self.title = title
        self.texts = paragraphs.map { Text($0) }
    }

    init(_ title: String, texts: [Text]) {
        self.title = title
        self.texts = texts
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            SectionHelpButton(accessibilityLabel: "Giải thích \(title)", texts: texts)
        }
    }
}
