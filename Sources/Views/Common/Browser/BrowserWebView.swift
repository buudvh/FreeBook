import UIKit
import WebKit

/// `WKWebView` của trình duyệt người dùng (`BypassBrowserTabStore.makeTab`). Lớp con để gắn menu bôi đen (`buildMenu`)
/// và menu ảnh ngoài link (`UIEditMenuInteraction` qua `BrowserImageMenuPresenter`).
///
/// Dữ liệu do script menu nhấn giữ báo về (`BrowserContextMenuScript` → `BypassBrowserTabStore+ContextMenu`):
/// - `lastSelection`: vùng chọn gần nhất để `buildMenu` đọc **đồng bộ** (`BrowserPageTranslator.selectionInfo(in:)` là
///   `async`). Chỉ là bản xem trước (cắt 2 000 ký tự, `sourceText` = chữ đang hiện): hành động lấy lại vùng chọn đầy
///   đủ + bản gốc lúc bấm.
/// - `lastSelectionHasHan`: bản gốc của vùng chọn có chữ Hán (hoặc trang đang dịch) ⇒ hiện Dịch QT / Tra từ điển /
///   Sao chép bản dịch.
/// - bản ghi `touchstart` trên ảnh: nhóm "Ảnh" của menu nhấn giữ link bọc ảnh.
///
/// Hành động chuyển về store qua `uiDelegate` (store là `WKUIDelegate` của mọi tab).
final class BrowserWebView: WKWebView {
    /// Thao tác của menu bôi đen.
    enum SelectionAction {
        case translate
        case lookup
        case copyTranslation
        case searchWeb
        case openLink(URL)
    }

    /// Thao tác của nhóm "Ảnh" (menu link bọc ảnh và menu ảnh ngoài link).
    enum ImageAction {
        case save
        case copy
        case openInNewTab
    }

    /// Bản ghi `touchstart` trên ảnh quá thời hạn này thì không còn tính là ảnh của lần nhấn giữ link hiện tại.
    private static let imageTouchLifetime: TimeInterval = 1.5
    /// Điểm chạm native dùng để đặt menu ảnh; cũ hơn thì quy đổi từ toạ độ trang do script gửi.
    private static let touchPointLifetime: TimeInterval = 3

    /// Mục hệ thống bị bỏ khỏi menu bôi đen (Tra cứu, Dịch, Chia sẻ, Nói, Học); Sao chép giữ nguyên.
    private static let removedSystemMenus: [UIMenu.Identifier] = [.lookup, .learn, .share, .speech]
    /// Phòng hờ khi WebKit tự thêm mục ngoài các menu trên: selector **riêng** của WebKit/UIKit (chỉ so tên, không gọi).
    /// Chưa kiểm trên máy — xem báo cáo.
    private static let hiddenSystemActions: Set<String> = [
        "_lookup:", "_define:", "_translate:", "_share:",
        "_accessibilitySpeak:", "_accessibilitySpeakLanguageSelection:", "_accessibilityPauseSpeaking:"
    ]

    /// Vùng chọn gần nhất do script báo về; `nil` = không có vùng chọn.
    var lastSelection: BrowserSelectionInfo?
    /// Bản gốc vùng chọn có chữ Hán (hoặc trang đang dịch QT).
    private(set) var lastSelectionHasHan = false

    private var lastImageTouch: (imageURL: URL, linkURL: URL?, date: Date)?
    private var lastTouchPoint: (point: CGPoint, date: Date)?
    private lazy var imageMenu = BrowserImageMenuPresenter(webView: self)

    // MARK: - Khởi tạo

    /// App đặt màu nhấn **trắng** toàn cục (`.tint(.white)`) ⇒ vùng bôi đen + tay nắm của trang thừa hưởng màu trắng, trên
    /// trang nền trắng không thấy gì. Gán màu xanh hệ thống **tường minh** (giống Safari) để không thừa hưởng nữa.
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        tintColor = .systemBlue
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tintColor = .systemBlue
    }

    // MARK: - Script → native (store gọi)

    func updateSelection(text: String, linkURL: URL?, sourceHasHan: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastSelection = nil
            lastSelectionHasHan = false
            return
        }
        lastSelection = BrowserSelectionInfo(text: text, sourceText: text, linkURL: linkURL)
        lastSelectionHasHan = sourceHasHan
    }

    func recordImageTouch(imageURL: URL, linkURL: URL?) {
        lastImageTouch = (imageURL, linkURL, Date())
    }

    /// Ảnh của lần nhấn giữ link `linkURL`: bản ghi chạm còn mới và ảnh nằm trong **chính** link đó.
    func imageURL(forLinkMenu linkURL: URL) -> URL? {
        guard let touch = lastImageTouch,
              Date().timeIntervalSince(touch.date) <= Self.imageTouchLifetime,
              let touchLink = touch.linkURL,
              Self.linkKey(touchLink) == Self.linkKey(linkURL) else { return nil }
        return touch.imageURL
    }

    /// So link của JS (`a.href`) với link WebKit trao: bỏ fragment và so dạng đã chuẩn hoá mã hoá, tránh trượt vì lệch
    /// `%20`/ký tự Unicode giữa hai bên.
    private static func linkKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let text = components?.string ?? url.absoluteString
        return text.removingPercentEncoding ?? text
    }

    /// Nhấn giữ ảnh ngoài link: bật menu ảnh ngay chỗ chạm.
    func presentImageMenu(imageURL: URL, pagePoint: CGPoint) {
        let point: CGPoint
        if let touch = lastTouchPoint, Date().timeIntervalSince(touch.date) <= Self.touchPointLifetime {
            point = touch.point
        } else {
            point = viewPoint(forPagePoint: pagePoint)
        }
        imageMenu.present(imageURL: imageURL, at: point)
    }

    // MARK: - Chuyển hành động về store

    func perform(_ action: SelectionAction) {
        (uiDelegate as? BypassBrowserTabStore)?.performSelectionAction(action, in: self)
    }

    /// `UIAction` có thân chạy trên main bất kể SDK khai `UIActionHandler` có gắn `@MainActor` hay không.
    static func menuAction(
        _ title: String,
        image: UIImage? = nil,
        perform: @escaping @MainActor () -> Void
    ) -> UIAction {
        UIAction(title: title, image: image) { _ in
            MainActor.assumeIsolated { perform() }
        }
    }

    // MARK: - UIResponder

    /// Ghi điểm chạm native (đúng toạ độ view) để đặt menu ảnh; không đổi kết quả hit-test.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view != nil, event?.type == .touches {
            lastTouchPoint = (point, Date())
        }
        return view
    }

    /// Menu bôi đen: bỏ Tra cứu/Dịch/Chia sẻ/Nói/Học của hệ thống, giữ Sao chép, chèn nhóm của trình duyệt ngay sau
    /// nhóm sửa chuẩn. Gọi `super` trước vì WebKit thêm mục của nó trong đó. Chỉ đụng menu ngữ cảnh (`.context`), không
    /// đụng thanh menu chính (iPad).
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        for identifier in Self.removedSystemMenus where builder.menu(for: identifier) != nil {
            builder.remove(menu: identifier)
        }
        guard let selection = lastSelection else { return }
        let menu = UIMenu(title: "", options: .displayInline, children: selectionMenuItems(for: selection))
        if builder.menu(for: .standardEdit) != nil {
            builder.insertSibling(menu, afterMenu: .standardEdit)
        } else {
            builder.insertChild(menu, atEndOfMenu: .root)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if Self.hiddenSystemActions.contains(NSStringFromSelector(action)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: - Nội bộ

    /// Thứ tự theo mockup: Dịch QT, Tra từ điển, Sao chép bản dịch (chỉ khi bản gốc có chữ Hán), Tìm trên web, Mở tab
    /// mới (chỉ khi vùng chọn nằm trong link).
    private func selectionMenuItems(for selection: BrowserSelectionInfo) -> [UIMenuElement] {
        var items: [UIMenuElement] = []
        if lastSelectionHasHan {
            items.append(Self.menuAction("Dịch QT") { [weak self] in self?.perform(.translate) })
            items.append(Self.menuAction("Tra từ điển") { [weak self] in self?.perform(.lookup) })
            items.append(Self.menuAction("Sao chép bản dịch") { [weak self] in self?.perform(.copyTranslation) })
        }
        items.append(Self.menuAction("Tìm trên web") { [weak self] in self?.perform(.searchWeb) })
        if let link = selection.linkURL, BypassBrowserTabStore.isWebURL(link) {
            items.append(Self.menuAction("Mở tab mới") { [weak self] in self?.perform(.openLink(link)) })
        }
        return items
    }

    /// Toạ độ tài liệu (CSS px) → toạ độ view: nội dung của scroll view được phóng theo `zoomScale` từ gốc (0, 0).
    private func viewPoint(forPagePoint pagePoint: CGPoint) -> CGPoint {
        let scale = scrollView.zoomScale
        let contentPoint = CGPoint(x: pagePoint.x * scale, y: pagePoint.y * scale)
        let converted = scrollView.convert(contentPoint, to: self)
        return CGPoint(
            x: min(max(converted.x, 0), bounds.width),
            y: min(max(converted.y, 0), bounds.height)
        )
    }
}
