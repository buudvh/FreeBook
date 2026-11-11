import SwiftUI
import UIKit

/// Trình xem phóng to một ảnh comic, trình bày bằng `fullScreenCover` từ `ComicReaderView`.
///
/// - `UIScrollView` zoom 1–4×; ảnh vừa bề ngang màn (ảnh webtoon dài thì cuộn dọc được), ngắn hơn màn thì căn giữa.
/// - Chạm đúp: đang zoom thì thu về 1×, chưa zoom thì phóng 2,5× quanh điểm chạm. Nút đóng góc trên phải.
/// - Ảnh nhận vào là bản đã downsample theo bề ngang màn (không giữ ảnh gốc trên RAM), nên zoom sâu sẽ hơi mờ.
/// - Dịch ảnh (1.3.834): truyện đang bật dịch (`translation` khác `nil`) ⇒ `ComicZoomTranslationLayer` phủ lên ảnh, **bên trong**
///   view được zoom (`contentView` chứa ảnh + lớp dịch) nên khối phóng theo ảnh. Khối lấy từ `ComicPageTextRepository` (ảnh vừa
///   hiện trên trang ⇒ trúng RAM, không nhận chữ lại) rồi dịch như trên trang.
struct ComicZoomViewer: UIViewRepresentable {
    /// Một lần mở phóng to: ảnh đang vẽ trên trang + yêu cầu ảnh của trang đó. `ComicReaderView` trình bày bằng
    /// `fullScreenCover(item:)` (1.3.835) để cover nhận đúng ảnh ngay lần đầu.
    struct Target: Identifiable {
        let id = UUID()
        let image: UIImage
        let request: ComicImageRequest
    }

    let image: UIImage
    /// Yêu cầu ảnh của trang đang phóng to — khoá của kết quả nhận chữ.
    let request: ComicImageRequest?
    /// `nil` = truyện đang tắt dịch.
    let translation: ComicImageTranslationContext?
    /// Chạm một khối dịch: chữ Trung gốc của khối ⇒ màn Dịch (1.3.837, `ComicZoomScreen` trình bày).
    let onOpenDefinition: (String) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ZoomContainerView {
        let view = ZoomContainerView()
        view.scrollView.delegate = context.coordinator
        context.coordinator.container = view
        view.closeHandler = onClose
        view.translationLayer.onTapBlock = { onOpenDefinition($0.block.text) }
        view.setImage(image)
        context.coordinator.loadTranslation(into: view, image: image, request: request, translation: translation)
        return view
    }

    func updateUIView(_ uiView: ZoomContainerView, context: Context) {
        uiView.closeHandler = onClose
        uiView.translationLayer.onTapBlock = { onOpenDefinition($0.block.text) }
        if uiView.imageView.image !== image {
            uiView.setImage(image)
            context.coordinator.loadTranslation(into: uiView, image: image, request: request, translation: translation)
        } else if context.coordinator.loadedTranslation != translation {
            // Từ điển / rule vừa đổi (vd lưu name ở màn Dịch) ⇒ dịch lại, giữ khối cũ tới khi có bản mới.
            context.coordinator.loadTranslation(
                into: uiView,
                image: image,
                request: request,
                translation: translation,
                clearsCurrent: false
            )
        }
    }

    static func dismantleUIView(_ uiView: ZoomContainerView, coordinator: Coordinator) {
        coordinator.translationTask?.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var container: ZoomContainerView?
        var translationTask: Task<Void, Never>?
        /// Ngữ cảnh dịch của lượt nạp gần nhất — đổi (`revision` mới) thì `updateUIView` dịch lại.
        private(set) var loadedTranslation: ComicImageTranslationContext?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            container?.contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            container?.centerImage()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            container?.translationLayer.setZoomScale(scale)
        }

        /// Khối chữ của ảnh (RAM nếu trang vừa nhận) → dịch → lớp dịch. Tắt dịch / thiếu yêu cầu ảnh ⇒ không có lớp dịch.
        func loadTranslation(
            into view: ZoomContainerView,
            image: UIImage,
            request: ComicImageRequest?,
            translation: ComicImageTranslationContext?,
            clearsCurrent: Bool = true
        ) {
            translationTask?.cancel()
            loadedTranslation = translation
            if clearsCurrent || translation == nil {
                view.translationLayer.setItems([])
            }
            guard let request, let translation, let cgImage = image.cgImage else { return }
            translationTask = Task { @MainActor [weak view] in
                guard let blocks = try? await ComicPageTextRepository.shared.blocks(for: request, image: cgImage),
                      !Task.isCancelled,
                      let items = await ComicPageTextTranslator.translate(
                          blocks,
                          bookId: translation.bookId,
                          convertsTraditional: translation.convertsTraditional
                      ),
                      !Task.isCancelled else { return }
                view?.translationLayer.setItems(items)
            }
        }
    }

    final class ZoomContainerView: UIView {
        let scrollView = UIScrollView()
        /// View được zoom: chứa ảnh và lớp dịch, cùng khung — khối dịch phóng / cuộn theo ảnh.
        let contentView = UIView()
        let imageView = UIImageView()
        let translationLayer = ComicZoomTranslationLayer()
        var closeHandler: (() -> Void)?

        private let closeButton = UIButton(type: .system)
        /// Kích thước khung đã dựng ảnh lần gần nhất — `layoutSubviews` chỉ dựng lại khi khung đổi (xoay màn).
        private var laidOutSize: CGSize = .zero

        private static let maximumZoomScale: CGFloat = 4
        private static let doubleTapZoomScale: CGFloat = 2.5
        private static let closeButtonSize: CGFloat = 38

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black

            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = Self.maximumZoomScale
            scrollView.bouncesZoom = true
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.decelerationRate = .fast
            addSubview(scrollView)

            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            scrollView.addSubview(contentView)
            contentView.addSubview(imageView)
            contentView.addSubview(translationLayer)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)
            translationLayer.attach(doubleTap: doubleTap)

            configureCloseButton()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setImage(_ image: UIImage) {
            imageView.image = image
            laidOutSize = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = bounds
            if bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 {
                laidOutSize = bounds.size
                // Đặt frame khi đang có transform zoom là không xác định — luôn về 1× trước.
                scrollView.zoomScale = scrollView.minimumZoomScale
                contentView.frame = fittedImageFrame()
                imageView.frame = contentView.bounds
                translationLayer.frame = contentView.bounds
                translationLayer.setZoomScale(scrollView.zoomScale)
                scrollView.contentSize = contentView.frame.size
                centerImage()
                // Đổi inset không tự dời offset — đặt offset theo inset để ảnh ngắn hiện giữa màn ngay từ đầu.
                scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
            }
            closeButton.frame = CGRect(
                x: bounds.width - safeAreaInsets.right - 16 - Self.closeButtonSize,
                y: safeAreaInsets.top + 8,
                width: Self.closeButtonSize,
                height: Self.closeButtonSize
            )
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        /// Ảnh khi zoom 1×: vừa bề ngang khung, chiều cao theo tỉ lệ ảnh.
        private func fittedImageFrame() -> CGRect {
            guard let size = imageView.image?.size, size.width > 0, size.height > 0 else {
                return CGRect(origin: .zero, size: bounds.size)
            }
            let width = bounds.width
            return CGRect(x: 0, y: 0, width: width, height: width * size.height / size.width)
        }

        /// Ảnh nhỏ hơn khung (theo chiều nào) thì đệm inset để nằm giữa chiều đó.
        func centerImage() {
            let content = contentView.frame.size
            let horizontal = max(0, (scrollView.bounds.width - content.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - content.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            // `zoom(to:)` nhận rect trong hệ toạ độ của view zoom (`contentView`, chưa nhân transform).
            let point = gesture.location(in: contentView)
            let scale = min(Self.doubleTapZoomScale, scrollView.maximumZoomScale)
            let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            scrollView.zoom(to: rect, animated: true)
        }

        private func configureCloseButton() {
            let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbol), for: .normal)
            closeButton.tintColor = .white
            closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            closeButton.layer.cornerRadius = Self.closeButtonSize / 2
            closeButton.accessibilityLabel = "Đóng"
            closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
            addSubview(closeButton)
        }

        @objc private func handleClose() {
            closeHandler?()
        }
    }
}
