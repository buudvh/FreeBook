import SwiftUI

/// Menu điều khiển cấu hình dịch thuật 3 mức: Truyện này > Nguồn này > Toàn cục.
/// Nút + chấm chỉ báo ở đây; Popover nhỏ gọn (Toggle Bật/Tắt + Dropdown chọn phạm vi + Bộ dịch + Ngôn ngữ + Nút Lưu
/// lại) là `TranslationScopePopupView`, dùng chung với menu header Khám phá.
///
/// Hai chấm: chấm xanh/đỏ góc trên phải = truyện có cấu hình bật/tắt riêng; chấm cam "!" góc dưới phải = chương đang
/// hiện (`chapterIndex`, chỉ Reader truyền) bị tiện ích dịch lỗi, đang dùng QT thay thế (`TranslationFallbackStatusStore`,
/// `@Observable` nên tự vẽ lại khi Reader ghi báo).
public struct ReaderTranslationScopeMenuView: View {
    /// Phạm vi của bảng dịch; `TranslationScopePopupView` dùng, giữ chỗ cũ vì là API public của nút.
    public enum TranslationPopupScope: String, CaseIterable, Identifiable {
        case book = "Truyện này"
        case source = "Nguồn này"
        case global = "Tất cả"

        public var id: String { rawValue }
    }

    public let bookId: String
    public let packageId: String
    public let sourceName: String
    public let textColor: Color?
    public let showBackground: Bool
    public let isChineseSourceHint: Bool?
    public let iconSize: CGFloat
    public let frameWidth: CGFloat?
    public let frameHeight: CGFloat?
    /// Chương đang hiện của Reader — để hiện chấm cam + hàng báo "QT thay thế"; `nil` ⇒ không báo.
    public let chapterIndex: Int?
    /// `false` ⇒ popup không có BỘ DỊCH / NGÔN NGỮ (màn truyện tranh: bộ dịch tiện ích không có tác dụng ở đó).
    public let showsEngineSection: Bool

    @State private var status: TranslationConfigStore.ResolvedStatus
    @State private var showingPopup = false

    public init(
        bookId: String,
        packageId: String = "",
        sourceName: String = "",
        textColor: Color? = nil,
        showBackground: Bool = true,
        isChineseSourceHint: Bool? = nil,
        iconSize: CGFloat = 19,
        frameWidth: CGFloat? = nil,
        frameHeight: CGFloat? = nil,
        chapterIndex: Int? = nil,
        showsEngineSection: Bool = true
    ) {
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.textColor = textColor
        self.showBackground = showBackground
        self.isChineseSourceHint = isChineseSourceHint
        self.iconSize = iconSize
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.chapterIndex = chapterIndex
        self.showsEngineSection = showsEngineSection
        _status = State(initialValue: TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint))
    }

    private var resolvedWidth: CGFloat {
        if let frameWidth = frameWidth { return frameWidth }
        if !showBackground && iconSize <= 14 { return 32 }
        return 44
    }

    private var resolvedHeight: CGFloat {
        if let frameHeight = frameHeight { return frameHeight }
        if !showBackground && iconSize <= 14 { return 32 }
        return showBackground ? 52 : 36
    }

    private var dotIndicator: some View {
        Circle()
            .fill(status.bookOverride == .enabled ? Color.green : Color.red)
            .frame(
                width: showBackground ? 7 : (iconSize <= 14 ? 4.5 : 6),
                height: showBackground ? 7 : (iconSize <= 14 ? 4.5 : 6)
            )
    }

    /// Báo "QT thay thế" của chương đang hiện; đọc store `@Observable` trong lượt vẽ ⇒ Reader ghi là nút vẽ lại.
    @MainActor
    private var hasFallbackStatus: Bool {
        guard let chapterIndex, !bookId.isEmpty else { return false }
        return TranslationFallbackStatusStore.shared.status(bookId: bookId, chapterIndex: chapterIndex) != nil
    }

    /// Chấm cam có dấu "!" ở góc dưới phải nút.
    private var fallbackBadge: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 13, height: 13)
            .overlay(
                Text("!")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
            )
            .accessibilityHidden(true)
    }

    @MainActor
    private var accessibilityText: String {
        let state = status.isEnabled ? "Đang bật dịch" : "Đang tắt dịch"
        return hasFallbackStatus ? state + ", chương này đang dùng QT thay thế" : state
    }

    public var body: some View {
        Button(action: {
            refreshStatus()
            showingPopup = true
        }) {
            if showBackground {
                ZStack(alignment: .topTrailing) {
                    // Icon ngoài không có bản "fill": bật/tắt chỉ khác màu.
                    AppGlyph.translate.image(size: iconSize)
                        .foregroundColor(status.isEnabled ? .white : (textColor?.opacity(0.45) ?? .secondary.opacity(0.6)))
                        .frame(width: resolvedWidth, height: resolvedHeight)
                        .background(
                            textColor?.opacity(0.08) ?? Color(UIColor.systemGray6),
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                    // Dấu chấm nhỏ chỉ thị truyện này đang có cấu hình riêng biệt
                    if status.bookOverride != .inherited {
                        dotIndicator
                            .padding(.top, 8)
                            .padding(.trailing, 4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if hasFallbackStatus {
                        fallbackBadge
                            .padding(.bottom, 6)
                            .padding(.trailing, 2)
                    }
                }
            } else {
                AppGlyph.translate.image(size: iconSize)
                    .foregroundColor(status.isEnabled ? .white : (textColor?.opacity(0.45) ?? .secondary.opacity(0.6)))
                    .overlay(alignment: .topTrailing) {
                        if status.bookOverride != .inherited {
                            dotIndicator
                                .offset(x: iconSize <= 14 ? 3 : 4, y: iconSize <= 14 ? -2 : -3)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if hasFallbackStatus {
                            fallbackBadge
                                .offset(x: 6, y: 5)
                        }
                    }
                    .frame(width: resolvedWidth, height: resolvedHeight)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .popover(isPresented: $showingPopup, arrowEdge: .top) {
            // Trạng thái bảng (công tắc, phạm vi) khởi tạo trong `TranslationScopePopupView` mỗi lần mở.
            TranslationScopePopupView(
                bookId: bookId,
                packageId: packageId,
                sourceName: sourceName,
                isChineseSourceHint: isChineseSourceHint,
                chapterIndex: chapterIndex,
                showsEngineSection: showsEngineSection,
                onDone: {
                    refreshStatus()
                    showingPopup = false
                }
            )
            .presentationCompactAdaptation(.popover)
            .appGlassPopover()
        }
        .onAppear {
            refreshStatus()
        }
        .onChange(of: packageId) { _, _ in
            refreshStatus()
        }
        .onChange(of: bookId) { _, _ in
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationConfigStore.didChangeNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        status = TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint)
    }
}
