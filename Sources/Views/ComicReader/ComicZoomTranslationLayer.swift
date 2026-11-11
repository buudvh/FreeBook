import UIKit

/// Lớp dịch của trình xem phóng to (`ComicZoomViewer`, 1.3.834) — bản UIKit của `ComicTranslationOverlay`, cùng đo đạc
/// (`ComicTranslationLayout`), nên khối nằm đúng chỗ và cùng cỡ chữ với trên trang.
///
/// - Nằm **trong** view được zoom, cùng khung với ảnh ở 1× ⇒ khối dịch phóng / thu / cuộn theo ảnh.
/// - Chữ là `UILabel`, cỡ chữ đo một lần ở 1× (thu nhỏ dần tới khi vừa khung, như `minimumScaleFactor` của bản SwiftUI).
///   Zoom xong (`setZoomScale`) đặt `contentScaleFactor` của chữ = scale màn × mức zoom để vẽ lại sắc nét; trong lúc đang
///   chụm hai ngón thì hơi mờ — cách làm thường của `UIScrollView`.
/// - Chạm một khối ⇒ `onTapBlock` (màn Dịch, 1.3.837); nhấn giữ ⇒ ẩn bản dịch, lộ chữ gốc (viền nét đứt màu nhấn), nhấn giữ
///   lại ⇒ dịch — như bản SwiftUI trên trang. Cử chỉ chạm chờ chạm đúp phóng to thất bại. Vùng trống không nhận chạm (kéo /
///   zoom đi thẳng xuống `UIScrollView`).
final class ComicZoomTranslationLayer: UIView {
    /// Một khối dịch: nền + chữ, hoặc chỉ viền nét đứt khi đang lộ chữ gốc.
    private final class BlockView: UIView {
        let item: ComicPageTextTranslator.Item
        let label = UILabel()
        private let border = CAShapeLayer()

        init(item: ComicPageTextTranslator.Item) {
            self.item = item
            super.init(frame: .zero)
            layer.cornerRadius = ComicTranslationLayout.cornerRadius
            layer.cornerCurve = .continuous
            label.text = item.translated
            label.numberOfLines = 0
            label.textAlignment = .center
            label.lineBreakMode = .byWordWrapping
            addSubview(label)
            border.fillColor = UIColor.clear.cgColor
            border.lineWidth = 1.5
            border.lineDashPattern = [4, 3]
            layer.addSublayer(border)
            isAccessibilityElement = true
            accessibilityTraits = .button
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func apply(revealed: Bool) {
            let isDark = item.block.isDarkBackground
            backgroundColor = revealed
                ? .clear
                : (isDark
                    ? UIColor.black.withAlphaComponent(ComicTranslationLayout.darkBackgroundOpacity)
                    : UIColor.white.withAlphaComponent(ComicTranslationLayout.lightBackgroundOpacity))
            label.textColor = isDark ? .white : .black
            label.isHidden = revealed
            border.isHidden = !revealed
            accessibilityLabel = revealed ? item.block.text : item.translated
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds.insetBy(
                dx: ComicTranslationLayout.horizontalPadding,
                dy: ComicTranslationLayout.verticalPadding
            )
            border.frame = bounds
            border.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 6).cgPath
            border.strokeColor = tintColor.withAlphaComponent(0.85).cgColor
        }

        override func tintColorDidChange() {
            super.tintColorDidChange()
            border.strokeColor = tintColor.withAlphaComponent(0.85).cgColor
        }
    }

    /// Chạm một khối (sau khi chạm đúp đã thất bại).
    var onTapBlock: ((ComicPageTextTranslator.Item) -> Void)?

    private var items: [ComicPageTextTranslator.Item] = []
    private var revealed: Set<Int> = []
    private var blockViews: [BlockView] = []
    private weak var doubleTapGesture: UIGestureRecognizer?
    private var zoomScale: CGFloat = 1
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Cử chỉ chạm đúp phóng to của trình xem — chạm khối phải chờ nó thất bại.
    func attach(doubleTap: UIGestureRecognizer) {
        doubleTapGesture = doubleTap
    }

    func setItems(_ items: [ComicPageTextTranslator.Item]) {
        self.items = items
        revealed.removeAll()
        blockViews.forEach { $0.removeFromSuperview() }
        blockViews = items.map { item in
            let view = BlockView(item: item)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            if let doubleTapGesture {
                tap.require(toFail: doubleTapGesture)
            }
            view.addGestureRecognizer(tap)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            hold.minimumPressDuration = 0.4
            view.addGestureRecognizer(hold)
            addSubview(view)
            return view
        }
        laidOutSize = .zero
        setNeedsLayout()
    }

    /// Mức zoom vừa dừng: vẽ lại chữ theo độ phân giải mới.
    func setZoomScale(_ scale: CGFloat) {
        zoomScale = max(1, scale)
        // Chưa vào cửa sổ thì `displayScale` có thể là 0 — lấy tạm 2, lần zoom / bố cục kế đặt lại.
        let screenScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        let renderScale = screenScale * zoomScale
        for view in blockViews where view.label.contentScaleFactor != renderScale {
            view.label.contentScaleFactor = renderScale
            view.label.setNeedsDisplay()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        for view in blockViews {
            let frame = ComicTranslationLayout.displayFrame(for: view.item.block, in: bounds.size)
            view.frame = frame
            let textSize = CGSize(
                width: max(1, frame.width - 2 * ComicTranslationLayout.horizontalPadding),
                height: max(1, frame.height - 2 * ComicTranslationLayout.verticalPadding)
            )
            view.label.font = Self.fittedFont(
                for: view.item.translated,
                in: textSize,
                startingAt: ComicTranslationLayout.fontSize(for: view.item.block, imageHeight: bounds.height)
            )
            view.apply(revealed: revealed.contains(view.item.id))
        }
        setZoomScale(zoomScale)
    }

    /// Chỉ khối nhận chạm; chạm vào vùng trống rơi xuống ảnh / `UIScrollView`.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view as? BlockView else { return }
        onTapBlock?(view.item)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view as? BlockView else { return }
        let id = view.item.id
        if revealed.contains(id) {
            revealed.remove(id)
        } else {
            revealed.insert(id)
        }
        view.apply(revealed: revealed.contains(id))
    }

    /// Cỡ chữ lớn nhất (bước 0,5 pt, từ cỡ khởi điểm xuống `minimumScaleFactor` lần) mà chữ xuống dòng vẫn lọt chiều cao khung.
    private static func fittedFont(for text: String, in size: CGSize, startingAt start: CGFloat) -> UIFont {
        let minimum = start * ComicTranslationLayout.minimumScaleFactor
        var points = start
        while points > minimum {
            let font = UIFont.systemFont(ofSize: points, weight: .medium)
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            if ceil(bounding.height) <= size.height {
                return font
            }
            points -= 0.5
        }
        return UIFont.systemFont(ofSize: minimum, weight: .medium)
    }
}
