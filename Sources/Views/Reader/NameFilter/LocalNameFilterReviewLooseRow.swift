import SwiftUI

/// Hàng **"Nới đoán tên Latin"** ở màn Sửa từ của màn duyệt Lọc name local (2026-11-28, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N6): tên + `?` + công tắc, ngay dưới hàng "Phân loại". Chỉ hiện khi
/// truyện bật "Ưu tiên tên Latin" và name ghép lại được (nơi dựng — `LocalNameFilterReviewAffixRows` — quyết định).
///
/// Áp **chỉ cho name đang sửa** (anh Bửu chọn): bật ⇒ màn duyệt ghép lại nghĩa name này theo cách nới (lõi chỉ cần ½ số chữ
/// là chữ phiên âm; nhãn "đoán" nếu máy đoán), tắt ⇒ về như cách thường. Giá trị mở đầu = ghi đè của name, chưa có ⇒ công
/// tắc của truyện. Trạng thái giữ ở `@State` (ngữ cảnh màn duyệt không phát thay đổi); mỗi lần gạt ⇒ `onChange`.
struct LocalNameFilterReviewLooseRow: View {
    let onChange: (Bool) -> Void

    @State private var isOn: Bool

    private static let helpParagraphs: [String] = [
        "Chỉ áp cho **name đang sửa**: phần lõi của tên kiểu Latin (sau khi bỏ tiền tố / hậu tố) chưa có trong từ điển thì máy đoán khi **một nửa** số chữ là chữ phiên âm, thay vì mọi chữ.",
        "Bật ⇒ ghép lại nghĩa name này theo cách nới (nhãn **đoán** nếu máy đoán); tắt ⇒ về như cũ. Nghĩa đã tự sửa cũng đổi theo — bấm Cập nhật để sửa lại. Gói tạm nhớ lựa chọn.",
        "Công tắc chung cho cả lượt lọc nằm ở sheet Lọc name local, dưới **Ưu tiên tên Latin**."
    ]

    init(isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        _isOn = State(initialValue: isOn)
    }

    var body: some View {
        HStack(spacing: 2) {
            Text("Nới đoán tên Latin")
                .font(.subheadline)
                .foregroundColor(.secondary)
            SectionHelpButton(
                accessibilityLabel: "Giải thích Nới đoán tên Latin",
                paragraphs: Self.helpParagraphs.map { LocalizedStringKey($0) }
            )
            Spacer(minLength: 8)
            Toggle("Nới đoán tên Latin", isOn: Binding(
                get: { isOn },
                set: { value in
                    guard value != isOn else { return }
                    isOn = value
                    onChange(value)
                }
            ))
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
