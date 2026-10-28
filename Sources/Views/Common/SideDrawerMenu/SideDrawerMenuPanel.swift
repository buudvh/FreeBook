import SwiftUI

/// Nội dung của cover do `SideDrawerMenuModifier` trình bày: lớp phủ tối + ngăn kéo kính mờ bám mép phải.
///
/// - Ngăn kéo cao toàn màn, rộng 78% bề ngang (tối đa 360pt), bo góc trái, viền trái mảnh; nội dung luôn tông tối
///   (`colorScheme = .dark`) để chữ trắng đọc rõ cả khi màn bên dưới là bìa sáng màu.
/// - Đóng: chạm ra ngoài, vuốt sang phải trên ngăn kéo, hoặc chọn một hàng thao tác. Không có nút ✕.
/// - Trượt ra xong mới gọi `onClosed` (kèm action của hàng vừa chọn, nếu có) để modifier gỡ cover.
struct SideDrawerMenuPanel<Content: View>: View {
    let title: String
    /// Gọi đúng một lần khi ngăn kéo đã trượt ra hết; tham số là action của hàng thao tác vừa chọn (`nil` = chỉ đóng).
    let onClosed: ((() -> Void)?) -> Void
    @ViewBuilder let content: () -> Content

    @State private var isShown = false
    @State private var isClosing = false
    @State private var didFinish = false
    @State private var dragOffset: CGFloat = 0

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
        .environment(\.sideDrawerMenuDismiss, SideDrawerMenuDismissAction(handler: close))
        .onAppear {
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
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
                .accessibilityHidden(true)

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

    /// Kính mờ: material + lớp tối 38%. Lớp tối nằm **trên** lớp kính nên quyết định gần hết độ trong — bản đầu 84%
    /// chỉ để lọt ~16% nền mờ, nhìn như nền đặc; 1.3.623 hạ còn 55%, 1.3.626 còn 38% theo người dùng ("thêm trong suốt");
    /// chữ trắng vẫn đọc được nhờ lớp mờ của material. Nền tràn vào vùng an toàn (tai thỏ khi nằm ngang, thanh trạng
    /// thái, home indicator); nới 1pt ra ngoài mép trên/dưới/phải để viền chỉ còn thấy ở cạnh trái.
    private var drawerBackground: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color(white: 0.12).opacity(0.38))
            shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
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

    /// Trượt ngăn kéo ra rồi mới báo `onClosed`. Lần gọi thứ hai trở đi (bấm liên tiếp hai hàng) bị bỏ qua.
    private func close(_ followUp: (() -> Void)?) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeIn(duration: Self.closeDuration)) {
            isShown = false
        } completion: {
            finish(followUp)
        }
        // Dự phòng: completion của animation không được gọi thì vẫn gỡ cover, không để một lớp vô hình chặn chạm.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration + 0.3) {
            finish(followUp)
        }
    }

    private func finish(_ followUp: (() -> Void)?) {
        guard !didFinish else { return }
        didFinish = true
        onClosed(followUp)
    }
}
