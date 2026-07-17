import Foundation
import UIKit
import CoreText
import Combine

/// UICollectionView-backed CoreText continuous reader.
final class CoreTextCollectionScrollViewController: UIViewController {
    
    // MARK: - Properties
    private let collectionView: UICollectionView
    
    // Cache nội bộ để lưu trữ NSAttributedString và Pages đã phân trang cho từng chương
    private var attributedStrings: [Int: NSAttributedString] = [:]
    private var paginatedPages: [Int: [CoreTextPage]] = [:]
    private var chapterStates: [Int: ChapterState] = [:]
    
    // Insets và thông số định dạng hiển thị
    private var horizontalInset: CGFloat = 20.0
    private var verticalInset: CGFloat = 20.0
    private var readerFont: UIFont = .systemFont(ofSize: 18)
    private var themeTextColor: UIColor = .black
    private var themeBackgroundColor: UIColor = .white
    private var themeHighlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.3)
    private var lineSpacing: CGFloat = 6.0
    private var paragraphSpacing: CGFloat = 16.0
    
    private var totalChaptersCount: Int = 0
    private var currentChapterIndex: Int = 0
    private var currentParagraphIndex: Int = 0
    
    // Trạng thái highlight cho TTS
    private var activeHighlightRange: NSRange?
    private var activeHighlightChapter: Int?
    
    private var isJumpingToPosition = false
    private var hasAppliedInitialScroll = false
    private var initialChapter: Int = 0
    private var initialParagraph: Int = 0
    
    // Callbacks báo về SwiftUI
    var onProgressCommit: ((_ chapter: Int, _ paragraph: Int) -> Void)?
    var onTap: (() -> Void)?
    var onChapterContentRequired: ((Int) -> Void)?
    
    private var cancellables: Set<AnyCancellable> = []
    
    enum ChapterState {
        case notLoaded
        case loading
        case loaded
        case failed(String)
    }
    
    // MARK: - Initializer
    init(
        totalChapters: Int,
        initialChapter: Int,
        initialParagraph: Int,
        horizontalInset: CGFloat,
        verticalInset: CGFloat,
        backgroundColor: UIColor
    ) {
        self.totalChaptersCount = totalChapters
        self.initialChapter = initialChapter
        self.initialParagraph = initialParagraph
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        self.themeBackgroundColor = backgroundColor
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = themeBackgroundColor
        
        setupCollectionView()
        setupEditMenu()
        setupTTSNotificationObserver()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Khi layout xong lần đầu, thực hiện cuộn tới vị trí đọc cũ
        if !hasAppliedInitialScroll && totalChaptersCount > 0 {
            hasAppliedInitialScroll = true
            scrollToSavedPosition(chapter: initialChapter, paragraph: initialParagraph)
        }
    }
    
    private func setupCollectionView() {
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.isOpaque = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(CoreTextPageCell.self, forCellWithReuseIdentifier: CoreTextPageCell.reuseIdentifier)
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Thêm Gesture Tap để bật/tắt HUD controls giống SwiftUI
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.delegate = self
        collectionView.addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleTap() {
        onTap?()
    }
    
    // MARK: - Public APIs (Dùng để đồng bộ từ SwiftUI)
    
    func updateTheme(
        font: UIFont,
        textColor: UIColor,
        backgroundColor: UIColor,
        highlightColor: UIColor,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) {
        let needRepaginate = self.readerFont != font || 
                             self.horizontalInset != horizontalInset || 
                             self.verticalInset != verticalInset ||
                             self.lineSpacing != lineSpacing ||
                             self.paragraphSpacing != paragraphSpacing
        
        self.readerFont = font
        self.themeTextColor = textColor
        self.themeBackgroundColor = backgroundColor
        self.themeHighlightColor = highlightColor
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        
        view.backgroundColor = backgroundColor
        
        if needRepaginate {
            // Khi cấu hình font/size thay đổi, cần xóa cache phân trang và phân lại toàn bộ
            let currentChap = currentChapterIndex
            let currentPara = currentParagraphIndex
            
            let tempStrings = attributedStrings
            attributedStrings.removeAll()
            paginatedPages.removeAll()
            
            // Re-parse lại các chương cũ bằng font mới
            for (idx, attrStr) in tempStrings {
                // Ta chỉ re-paginate, còn attributedString sẽ được sinh lại khi updateChapterCache
                // Để đơn giản, ta tạm thời xóa hết, SwiftUI updateUIViewController sẽ tự động push data mới xuống.
            }
            
            collectionView.reloadData()
            
            // Cuộn neo lại vị trí trước khi đổi font
            DispatchQueue.main.async {
                self.scrollToSavedPosition(chapter: currentChap, paragraph: currentPara)
            }
        } else {
            // Nếu chỉ đổi màu nền/màu chữ, chỉ cần reload các cell đang hiển thị
            collectionView.reloadData()
        }
    }
    
    func updateChapterData(
        chapterIndex: Int,
        state: ChapterState,
        htmlContent: String? = nil
    ) {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return }
        
        let oldState = chapterStates[chapterIndex]
        chapterStates[chapterIndex] = state
        
        switch state {
        case .loaded:
            if let html = htmlContent, !html.isEmpty {
                // Bóc tách HTML div metadata thành NSAttributedString kèm Custom Attributes
                let attrStr = CoreTextHTMLParser.shared.parse(
                    html: html,
                    font: readerFont,
                    textColor: themeTextColor,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing
                )
                attributedStrings[chapterIndex] = attrStr
                
                // Thực hiện phân trang
                let bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: view.bounds.width - (horizontalInset * 2),
                    height: view.bounds.height - (verticalInset * 2)
                )
                let pages = CoreTextPaginator.shared.paginate(
                    attributedString: attrStr,
                    bounds: bounds,
                    chapterIndex: chapterIndex
                )
                paginatedPages[chapterIndex] = pages
                
                collectionView.reloadSections(IndexSet(integer: chapterIndex))
                
                // Nếu đây là chương khởi tạo đầu tiên, cuộn lại lần nữa để neo đúng vị trí chính xác sau khi phân trang xong
                if chapterIndex == initialChapter && isJumpingToPosition {
                    isJumpingToPosition = false
                    scrollToSavedPosition(chapter: initialChapter, paragraph: initialParagraph)
                }
            }
        case .loading, .failed:
            attributedStrings.removeValue(forKey: chapterIndex)
            paginatedPages.removeValue(forKey: chapterIndex)
            collectionView.reloadSections(IndexSet(integer: chapterIndex))
        case .notLoaded:
            attributedStrings.removeValue(forKey: chapterIndex)
            paginatedPages.removeValue(forKey: chapterIndex)
            collectionView.reloadSections(IndexSet(integer: chapterIndex))
        }
    }
    
    /// Nhảy trực tiếp tới một Chương và Đoạn văn cụ thể (TOC / Khôi phục lịch sử)
    func scrollToSavedPosition(chapter: Int, paragraph: Int) {
        guard chapter >= 0 && chapter < totalChaptersCount else { return }
        
        self.currentChapterIndex = chapter
        self.currentParagraphIndex = paragraph
        
        // 1. Kiểm tra xem chương đã được tải và phân trang chưa
        guard let pages = paginatedPages[chapter], !pages.isEmpty,
              let attrStr = attributedStrings[chapter] else {
            // Nếu chưa có dữ liệu, chuyển sang trạng thái chờ và yêu cầu tải chương
            isJumpingToPosition = true
            onChapterContentRequired?(chapter)
            return
        }
        
        // 2. Tìm trang (PageIndex) chứa đoạn văn (ParagraphIndex) tương ứng
        var targetPageIndex = 0
        let targetParaId = "para-\(chapter)-\(paragraph)"
        
        for (pageIdx, page) in pages.enumerated() {
            var found = false
            attrStr.enumerateAttribute(.paragraphId, in: page.range, options: []) { value, range, stop in
                if let paraId = value as? String, paraId == targetParaId {
                    found = true
                    stop.pointee = true
                }
            }
            if found {
                targetPageIndex = pageIdx
                break
            }
        }
        
        // 3. Cuộn UICollectionView đến đúng cell (Section = chapter, Item = pageIndex)
        let indexPath = IndexPath(item: targetPageIndex, section: chapter)
        collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
    }
}

// MARK: - UICollectionViewDataSource & UICollectionViewDelegateFlowLayout
extension CoreTextCollectionScrollViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return totalChaptersCount
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let state = chapterStates[section] ?? .notLoaded
        
        switch state {
        case .loaded:
            let pages = paginatedPages[section] ?? []
            return pages.isEmpty ? 1 : pages.count
        case .loading, .failed, .notLoaded:
            return 1 // Trả về 1 cell để hiển thị trạng thái loading/error/placeholder
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CoreTextPageCell.reuseIdentifier, for: indexPath) as! CoreTextPageCell
        
        let chapterIdx = indexPath.section
        let pageIdx = indexPath.item
        let state = chapterStates[chapterIdx] ?? .notLoaded
        
        switch state {
        case .loaded:
            if let pages = paginatedPages[chapterIdx], !pages.isEmpty,
               let attrStr = attributedStrings[chapterIdx] {
                let page = pages[pageIdx]
                
                // Kiểm tra xem trang này có chứa đoạn văn đang được phát TTS không
                var highlightRangeInPage: NSRange? = nil
                if let activeRange = activeHighlightRange,
                   let activeChap = activeHighlightChapter,
                   activeChap == chapterIdx {
                    // Nếu highlightRange giao thoa với page.range
                    let maxStart = max(page.range.location, activeRange.location)
                    let minEnd = min(page.range.location + page.range.length, activeRange.location + activeRange.length)
                    if maxStart < minEnd {
                        highlightRangeInPage = activeRange
                    }
                }
                
                let insets = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
                cell.configure(
                    attributedString: attrStr,
                    pageRange: page.range,
                    highlightRange: highlightRangeInPage,
                    insets: insets,
                    highlightColor: themeHighlightColor,
                    themeTextColor: themeTextColor
                )
            } else {
                cell.showLoading(themeTextColor: themeTextColor)
            }
        case .loading:
            cell.showLoading(themeTextColor: themeTextColor)
        case .failed(let msg):
            cell.showError(message: msg, themeTextColor: themeTextColor)
            cell.onReloadTap = { [weak self] in
                self?.onChapterContentRequired?(chapterIdx)
            }
        case .notLoaded:
            cell.showLoading(themeTextColor: themeTextColor)
            // Kích hoạt tải tự động khi view placeholder đi vào màn hình
            onChapterContentRequired?(chapterIdx)
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size // Mỗi cell chiếm trọn vẹn kích thước ScrollView
    }
}

// MARK: - UIScrollViewDelegate (Theo dõi cuộn & Prefetch 70%)
extension CoreTextCollectionScrollViewController: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.height > 0 else { return }
        
        // 1. Xác định Cell ở giữa màn hình hiện tại (Trang hiển thị chính)
        let visibleCenterPoint = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        guard let indexPath = collectionView.indexPathForItem(at: visibleCenterPoint) else { return }
        
        let chapterIdx = indexPath.section
        let pageIdx = indexPath.item
        
        // 2. Nếu chuyển trang hoặc chương, tiến hành tính toán cập nhật tiến trình
        if chapterIdx != currentChapterIndex || pageIdx != currentChapterIndex {
            updateReadingProgress(chapterIndex: chapterIdx, pageIndex: pageIdx)
        }
        
        // 3. THUẬT TOÁN TẢI TRƯỚC SỚM 70% KIỂU YUEDU-READER
        if let pages = paginatedPages[chapterIdx], !pages.isEmpty {
            let totalPages = pages.count
            // Nếu người dùng lướt qua mốc 70% số trang của chương hiện hành
            if pageIdx >= (totalPages * 7) / 10 {
                let nextChapter = chapterIdx + 1
                if nextChapter < totalChaptersCount && chapterStates[nextChapter] == nil {
                    // Kích hoạt tải trước chương kế tiếp
                    chapterStates[nextChapter] = .loading
                    onChapterContentRequired?(nextChapter)
                }
            }
        }
    }
    
    private func updateReadingProgress(chapterIndex: Int, pageIndex: Int) {
        self.currentChapterIndex = chapterIndex
        
        guard let pages = paginatedPages[chapterIndex], pageIndex < pages.count,
              let attrStr = attributedStrings[chapterIndex] else { return }
        
        let page = pages[pageIndex]
        
        // Tra cứu thuộc tính .paragraphId tại ký tự đầu tiên hiển thị trên trang để tìm paragraphIndex
        var foundParagraphIndex = 0
        attrStr.enumerateAttribute(.paragraphId, in: page.range, options: []) { value, range, stop in
            if let paraId = value as? String {
                let components = paraId.components(separatedBy: "-")
                if components.count >= 3 {
                    foundParagraphIndex = Int(components[2]) ?? 0
                    stop.pointee = true
                }
            }
        }
        
        self.currentParagraphIndex = foundParagraphIndex
        
        // Báo cáo về SwiftUI để cập nhật HUD và lưu lịch sử đọc
        onProgressCommit?(chapterIndex, foundParagraphIndex)
    }
}

// MARK: - Edit Menu (Bôi đen dịch & TTS)
extension CoreTextCollectionScrollViewController: UIEditMenuInteractionDelegate {
    
    private func setupEditMenu() {
        let interaction = UIEditMenuInteraction(delegate: self)
        collectionView.addInteraction(interaction)
        
        // Lắng nghe long press để bôi đen chọn chữ
        // Trong Lightweight CoreText View, để đơn giản hóa, ta sử dụng tính năng bôi đen của hệ thống hoặc
        // hỗ trợ một menu nổi thông qua long press cử chỉ (ở đây mô tả khung gối đầu để bạn tùy biến).
    }
    
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let translateAction = UIAction(title: "Dịch đoạn") { [weak self] _ in
            self?.handleTranslateSelection()
        }
        
        let speakAction = UIAction(title: "Nghe tại đây") { [weak self] _ in
            self?.handleSpeakFromSelection()
        }
        
        return UIMenu(children: [translateAction, speakAction] + suggestedActions)
    }
    
    private func handleTranslateSelection() {
        // Tra cứu text được chọn dựa trên NSRange bôi đen của CoreText
        // Gọi Popover dịch song ngữ của FreeBook
    }
    
    private func handleSpeakFromSelection() {
        // Phân tích paragraphId tại điểm bôi đen
        // Gửi thông báo đến TTSManager bắt đầu phát từ (chapter, paragraph) đó
        NotificationCenter.default.post(
            name: NSNotification.Name("ttsRequestPlayFromPosition"),
            object: nil,
            userInfo: [
                "chapterIndex": currentChapterIndex,
                "paragraphIndex": currentParagraphIndex
            ]
        )
    }
}

// MARK: - TTS Notification Observer
extension CoreTextCollectionScrollViewController {
    
    private func setupTTSNotificationObserver() {
        // Lắng nghe sự kiện TTS chuyển từ mới phát
        NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidUpdateParagraphPosition"))
            .sink { [weak self] notification in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let bookId = userInfo["bookId"] as? String,
                      let chapterIdx = userInfo["chapterIndex"] as? Int,
                      let paragraphIdx = userInfo["paragraphIndex"] as? Int else { return }
                
                self.syncHighlightForTTS(chapterIndex: chapterIdx, paragraphIndex: paragraphIdx)
            }
            .store(in: &cancellables)
    }
    
    /// Đồng bộ highlight màu nền chữ khi TTS đang đọc
    private func syncHighlightForTTS(chapterIndex: Int, paragraphIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount,
              let attrStr = attributedStrings[chapterIndex],
              let pages = paginatedPages[chapterIndex] else { return }
        
        let targetParaId = "para-\(chapterIndex)-\(paragraphIndex)"
        var targetRange: NSRange?
        
        // 1. Tìm NSRange của đoạn văn trong NSAttributedString
        attrStr.enumerateAttribute(.paragraphId, in: NSRange(location: 0, length: attrStr.length), options: []) { value, range, stop in
            if let paraId = value as? String, paraId == targetParaId {
                targetRange = range
                stop.pointee = true
            }
        }
        
        guard let rangeToHighlight = targetRange else { return }
        
        self.activeHighlightChapter = chapterIndex
        self.activeHighlightRange = rangeToHighlight
        
        // 2. Tìm trang chứa đoạn văn này để cuộn màn hình đồng bộ (auto-scroll follow)
        var targetPageIndex: Int?
        for (pageIdx, page) in pages.enumerated() {
            if page.range.location <= rangeToHighlight.location && 
               (page.range.location + page.range.length) > rangeToHighlight.location {
                targetPageIndex = pageIdx
                break
            }
        }
        
        // 3. Cập nhật và vẽ lại cell tương ứng
        if let pageIdx = targetPageIndex {
            let indexPath = IndexPath(item: pageIdx, section: chapterIndex)
            
            // Cuộn theo giọng đọc TTS (nếu không ở đúng trang hiện tại)
            if chapterIndex != currentChapterIndex || pageIdx != currentPageIndex {
                collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
            }
            
            // Reload cell đang hiển thị để cập nhật highlightColor vẽ đè lên context
            collectionView.reloadItems(at: [indexPath])
        }
    }
    
    private var currentPageIndex: Int {
        let visibleCenterPoint = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        return collectionView.indexPathForItem(at: visibleCenterPoint)?.item ?? 0
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CoreTextCollectionScrollViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Chỉ nhận sự kiện tap khi người dùng không chạm vào các nút điều khiển lỗi/reload
        if touch.view is UIButton {
            return false
        }
        return true
    }
}
