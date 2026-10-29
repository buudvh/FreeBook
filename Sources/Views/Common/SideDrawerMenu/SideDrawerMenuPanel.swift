import SwiftUI

/// Nội dung cửa sổ ngăn kéo (`SideDrawerMenuWindowRoot`): lớp phủ tối + ngăn kéo bán trong suốt bám mép phải.
///
/// - Ngăn kéo cao toàn màn, rộng 78% bề ngang (tối đa 360pt), bo góc trái, viền trái mảnh; nội dung luôn tông tối
///   (`colorScheme = .dark`) để chữ trắng đọc rõ cả khi màn bên dưới là bìa sáng màu.
/// - Đóng: chạm ra ngoài, vuốt sang phải trên ngăn kéo, hoặc chọn một hàng thao tác. Không có nút ✕.
/// - Bắt đầu trượt ra ⇒ gọi ngay `onCloseBegan` (kèm action của hàng vừa chọn, nếu có) để cửa sổ thôi nhận chạm và
///   action chạy luôn; trượt ra xong ⇒ `onClosed` để cửa sổ ẩn đi.
struct SideDrawerMenuPanel<Content: View>: View {
    let title: String
    /// Panel vừa lên màn (bắt đầu trượt vào) — chỉ để đo thời gian.
    let onAppeared: () -> Void
    /// Gọi đúng một lần khi ngăn kéo bắt đầu trượt ra; tham số là action của hàng thao tác vừa chọn (`nil` = chỉ đóng).
    let onCloseBegan: ((() -> Void)?) -> Void
    /// Gọi đúng một lần khi ngăn kéo đã trượt ra hết.
    let onClosed: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isShown = false
    @State private var isClosing = false
    @State private var didFinish = false
    @State private var dragOffset: CGFloat = 0
    /// Tăng khi hàng công tắc / hàng chọn vừa đổi giá trị ⇒ `body` chạy lại, đọc lại state mới nhất của màn.
    @State private var contentRevision = 0

    /// Nhanh hơn bản đầu (0,26 / 0,2 s) theo yêu cầu người dùng (1.3.623).
    private static var openAnimation: Animation { .easeOut(duration: 0.18) }
    private static var closeDuration: Double { 0.14 }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = min(proxy.size.width * 0.78, 360)
            // Nền ngăn kéo tràn qua vùng an toàn bên phải (tai thỏ khi nằm ngang) ⇒ đẩy thêm đoạn đó khi ẩn.
            let hiddenOffset = drawerWidth + proxy.safeAreaInsets.trailing + 24
            ZStack(alignment: .trailing) {
                dimmingLayer
                drawer(width: drawerWidth)
                    .offset(x: isShown ? dragOffset : hiddenOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(!isClosing)
        .environment(
            \.sideDrawerMenuDismiss,
            SideDrawerMenuDismissAction(handler: close, revision: contentRevision, refresher: refreshContent)
        )
        .onAppear {
            onAppeared()
            withAnimation(Self.openAnimation) {
                isShown = true
            }
        }
    }

    // MARK: - Lớp phủ

    private var dimmingLayer: some View {
        Color.black
            .opacity(isShown ? 0.3 : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { close(nil) }
            .accessibilityElement()
            .accessibilityLabel("Đóng menu")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { close(nil) }
    }

    // MARK: - Ngăn kéo

    private func drawer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tiêu đề cùng chuẩn tiêu đề trang (22pt đậm, một dòng); không còn vạch ngăn bên dưới.
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { drawerBackground }
        .environment(\.colorScheme, .dark)
        .simultaneousGesture(swipeToClose(drawerWidth: width))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close(nil) }
    }

    /// Nền kính theo Cài đặt › Giao diện (`SideDrawerGlassBackground`, mặc định "kính đục vừa" của 1.3.633). Nền tràn
    /// vào vùng an toàn (tai thỏ khi nằm ngang, thanh trạng thái, home indicator); nới 1pt ra ngoài mép trên/dưới/phải
    /// để viền chỉ còn thấy ở cạnh trái.
    private var drawerBackground: some View {
        SideDrawerGlassBackground()
            .padding(.vertical, -1)
            .padding(.trailing, -1)
            .ignoresSafeArea()
    }

    // MARK: - Đóng

    /// Chỉ ăn cú vuốt **ngang** sang phải để không tranh với cuộn dọc của danh sách mục.
    private func swipeToClose(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                guard !isClosing else { return }
                let dx = value.translation.width
                if dx > 0, abs(dx) > abs(value.translation.height) {
                    dragOffset = dx
                } else if dragOffset != 0 {
                    dragOffset = 0
                }
            }
            .onEnded { value in
                guard !isClosing else { return }
                let travelled = dragOffset
                let predicted = value.predictedEndTranslation.width
                if travelled > 0, travelled > drawerWidth * 0.3 || predicted > drawerWidth * 0.6 {
                    close(nil)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// Bắt đầu trượt ra và báo `onCloseBegan` **ngay** (action của hàng chạy luôn, không chờ trượt xong); trượt xong mới
    /// báo `onClosed`. Lần gọi thứ hai trở đi (bấm liên tiếp hai hàng) bị bỏ qua.
    private func close(_ followUp: (() -> Void)?) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeIn(duration: Self.closeDuration)) {
            isShown = false
        } completion: {
            finish()
        }
        // Dự phòng: completion của animation không được gọi thì vẫn ẩn cửa sổ, không để một lớp vô hình chặn chạm.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration + 0.3) {
            finish()
        }
        onCloseBegan(followUp)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onClosed()
    }

    /// Hàng công tắc / hàng chọn vừa đổi giá trị: vẽ lại để đọc state mới (màn có thể không vẽ lại nếu `body` của nó
    /// không đọc giá trị đó, nên không đợi lượt đẩy từ màn).
    private func refreshContent() {
        contentRevision &+= 1
    }
}
