import SwiftUI

/// Màn Sửa từ có **hàng phụ** (`accessoryRows` ở chế độ từ điển — hai hàng "Tiền tố" / "Hậu tố" khi mở từ màn duyệt Lọc
/// name local; mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2, mục C10) mở ở nấc **cao đúng nội dung**
/// — từ tiêu đề tới nút Cập nhật + hàng tra cứu ngoài —, tối đa toàn màn, vẫn kéo lên `.large` được. Luồng AI, từ điển và
/// chế độ danh sách giữ nấc cũ (`.medium`/`.large`, danh sách chỉ `.large`).
///
/// Cách đo (iOS 17: `GeometryReader` + `PreferenceKey`, `onGeometryChange` cần iOS 18):
/// - Sheet mở ở nấc tạm **đã biết giá trị** (`FittedDetent.initialHeight`) ⇒ số đo đầu tiên của vùng cuộn cho ra phần đầu
///   sheet ngoài vùng cuộn (thanh tiêu đề, và lề dưới nếu nấc có tính) = nấc tạm − vùng cuộn, **một lần rồi giữ**. Không
///   phải luật "nấc `.height` có tính lề dưới hay không", cũng không lấy hai số đo ở hai callback khác nhau (cặp lệch nhịp
///   lúc bàn phím trượt lên sẽ thổi phồng phần đầu). Lúc mở, luồng có hàng phụ không tự focus ô nào nên chưa có bàn phím.
/// - Nấc vừa khít = phần đầu + chiều cao tự nhiên của nội dung trong `ScrollView` (không đổi theo bàn phím). Lần khớp đầu
///   lên hay xuống đều được; sau đó **chỉ nâng** (nội dung dài thêm khi chip / token / hàng phụ về muộn), không hạ — gõ
///   chữ, bàn phím hiện hay ẩn không làm sheet giật.
/// - Nấc đang chọn luôn nằm trong bộ nấc: nấc vừa khít đổi thì chỉ dời lựa chọn khi nó đang ở nấc vừa khít cũ; người dùng
///   đã kéo lên `.large` thì để yên.
extension DictEntryEditSheet {
    /// `true` ⇒ mở nấc vừa khít (chế độ từ điển có hàng phụ). `accessoryRows` là `let` ⇒ nhánh cố định suốt đời sheet.
    var usesFittedDetent: Bool { listMode == nil && accessoryRows != nil }

    func fittedViewportHeightDidChange(_ height: CGFloat) {
        guard usesFittedDetent else { return }
        fitting.recordViewport(height)
    }

    func fittedContentHeightDidChange(_ height: CGFloat) {
        guard usesFittedDetent else { return }
        fitting.recordContent(height)
    }

    /// Trạng thái nấc vừa khít (một `@State` của sheet).
    struct FittedDetent {
        /// Nấc tạm lúc mở, trước khi đo (≈ nửa màn, nhỏ hơn nấc toàn màn của mọi iPhone dọc).
        static let initialHeight: CGFloat = 420
        /// Phần đầu đo được ngoài khoảng này ⇒ dùng số mặc định. Sàn 44 = ít nhất một thanh điều hướng: nấc tạm bị hệ thống
        /// kẹp (máy nằm ngang…) hay khung vùng cuộn tính cả chỗ thanh tiêu đề sẽ cho số ~0 / ~34 (lề dưới), dùng là nội
        /// dung bị thanh tiêu đề che.
        static let headerRange: ClosedRange<CGFloat> = 44...140
        static let fallbackHeader: CGFloat = 56

        /// Nấc vừa khít đang dùng (nấc tạm cho tới lần khớp đầu).
        private(set) var height: CGFloat = FittedDetent.initialHeight
        var selection: PresentationDetent = .height(FittedDetent.initialHeight)
        /// Phần đầu sheet ngoài vùng cuộn — tính một lần từ số đo vùng cuộn đầu tiên.
        private var header: CGFloat?
        /// Số đo vùng cuộn đầu tiên (chỉ để ghi log lần khớp đầu).
        private var openViewport: CGFloat = 0
        private var contentHeight: CGFloat = 0
        private var hasFitted = false

        var detents: Set<PresentationDetent> { [.height(height), .large] }

        mutating func recordViewport(_ viewport: CGFloat) {
            guard header == nil, viewport > 0 else { return }
            openViewport = viewport
            let measured = height - viewport
            header = Self.headerRange.contains(measured) ? measured : Self.fallbackHeader
            refit()
        }

        mutating func recordContent(_ content: CGFloat) {
            guard content > 0 else { return }
            contentHeight = content
            refit()
        }

        private mutating func refit() {
            guard let header, contentHeight > 0 else { return }
            let target = (header + contentHeight).rounded(.up)
            // Lần đầu khớp đúng (lên hoặc xuống từ nấc tạm); sau đó chỉ nâng, lệch dưới 1pt bỏ qua.
            let shouldApply = hasFitted ? target > height + 1 : abs(target - height) > 0.5
            if !hasFitted {
                // Một dòng mỗi lần mở — để lượt thử đầu trên máy xác nhận cách đo (phần đầu đo được hay số mặc định).
                let headerSource = Self.initialHeight - openViewport == header ? "đo" : "mặc định"
                let message: String = "📐 [DictEdit] Nấc vừa khít lần đầu: nấc tạm \(Int(Self.initialHeight))"
                    + " · vùng cuộn \(Int(openViewport)) · phần đầu \(Int(header)) (\(headerSource))"
                    + " · nội dung \(Int(contentHeight)) ⇒ \(Int(target))"
                AppLogger.shared.log(message)
            }
            hasFitted = true
            guard shouldApply else { return }
            let followsFitted = selection == .height(height)
            height = target
            if followsFitted { selection = .height(target) }
        }
    }

    /// Chiều cao tự nhiên của nội dung trong `ScrollView`.
    struct FittedContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Chiều cao vùng cuộn (khung của `ScrollView`). Key riêng: con của `ScrollView` cũng phát `FittedContentHeightKey`
    /// lên tới đó, dùng chung một key thì `onPreferenceChange` của vùng cuộn nhận lẫn số của nội dung.
    struct FittedViewportHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

extension View {
    /// Đo chiều cao của view này (`GeometryReader` nền + `PreferenceKey`) — dùng cho nấc vừa khít của màn Sửa từ.
    func dictEntryEditMeasuredHeight<Key: PreferenceKey>(
        _ key: Key.Type,
        perform action: @escaping (CGFloat) -> Void
    ) -> some View where Key.Value == CGFloat {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: proxy.size.height)
            }
        )
        .onPreferenceChange(key) { value in action(value) }
    }

    /// Bộ nấc của màn Sửa từ: có hàng phụ ⇒ nấc vừa khít + `.large` (`DictEntryEditSheet.FittedDetent`); còn lại giữ như
    /// cũ — danh sách chỉ `.large` (ô chữ gốc tự focus, nấc nửa màn để bàn phím che nút "Thêm" và các hàng phụ), từ điển
    /// `.medium` + `.large`.
    @ViewBuilder
    func dictEntryEditDetents(
        fits: Bool,
        isListMode: Bool,
        fitting: Binding<DictEntryEditSheet.FittedDetent>
    ) -> some View {
        if fits {
            presentationDetents(fitting.wrappedValue.detents, selection: fitting.selection)
        } else {
            presentationDetents(isListMode ? [.large] : Set<PresentationDetent>([.medium, .large]))
        }
    }
}
