import SwiftUI

/// Sheet "Lọc name local" (Reader › "…", plan 2026-11-27, mockup khung 2–4): tự dò tên người / địa danh / tông môn trong
/// chữ Hán các chương đã tải, ngay trên máy, không gọi AI, rồi duyệt và lưu vào Name / VP riêng của truyện.
///
/// Ba bước trong **một** sheet, theo `LocalNameFilterSession.phase`:
/// 1. Chọn phạm vi (`+Setup`): như "Lọc name nhiều chương" của AI (`ReaderAIBatchPromptSheet`) bỏ "Tiếp nối"; không đọc /
///    ghi mặc định của sheet AI. "Ít nhất N lần" (mặc định 3), mục "Danh sách" mở hai màn quản lý dùng chung mọi truyện.
/// 2. Đang lọc (`LocalNameFilterProgressView`): name hiện dần; "Dừng" = phân tích nốt phần đã đọc rồi sang bước 3.
/// 3. Duyệt: thay cả gốc sheet bằng `ReaderAINameReviewSheet` (danh sách có sẵn, sắp "Nhiều lần nhất", ✕ có "Không phải
///    name"); lưu thẳng qua `AIHarnessService.saveExtractedEntries` như màn AI.
/// Đóng sheet (vuốt xuống) ở bất kỳ bước nào ⇒ huỷ lượt lọc — `onDisappear` gắn ở `ZStack` ngoài cùng, sống qua mọi lần
/// đổi bước (gắn vào `Group` thì SwiftUI rải xuống từng nhánh, đổi bước là tưởng đóng sheet).
struct LocalNameFilterSheet: View {
    /// Kiểu chọn chương bắt đầu (bỏ "Tiếp nối" của sheet AI: lọc local không lưu tiến độ).
    enum ScanStart: Hashable {
        case current, first, custom
    }

    static let minCountChoices = [2, 3, 5, 10]

    let bookId: String
    /// Chương đang đọc (0-based theo mục lục).
    let chapterIndex: Int
    /// Reader bật dịch ⇒ tên chương ở phạm vi lọc là bản dịch, như danh sách chương Reader.
    let translatesChapterTitles: Bool
    /// Cờ phồn → giản của Reader — chữ đưa vào bộ lọc là chữ Reader đang hiện.
    let convertsTraditionalToSimplified: Bool

    @State var session = LocalNameFilterSession()
    /// Kiểu người dùng đã bấm; `nil` = theo `defaultStart` (chỉ chốt được sau khi nạp xong danh sách chương).
    @State var pickedStart: ScanStart? = nil
    /// Chương tự chọn ở "Chọn chương…" — không nhớ giữa các lần mở sheet.
    @State var customChapterIndex: Int? = nil
    /// "Số lượng chương" — mỗi lần mở về Tất cả như sheet AI.
    @State var limitOption: ChapterLimitOption = .all
    @State var customLimit: Int = 100
    /// Chương đã tải theo thứ tự mục lục, nạp một lần khi mở sheet; `nil` = đang nạp.
    @State var chapters: [AINameScanChapter]? = nil
    /// "Ít nhất N lần" — mặc định 3, không nhớ giữa các lần mở.
    @State var minCount: Int = 3
    /// Số đuôi đang bật / số cụm "Không phải name" — đọc lại mỗi khi quay về từ màn quản lý.
    @State var suffixCount: Int = 0
    @State var blockedCount: Int = 0

    var body: some View {
        ZStack {
            if session.phase == .review {
                ReaderAINameReviewSheet(
                    names: session.reviewNames,
                    bookId: bookId,
                    onSave: { items, isName, isMerge in save(items, isName: isName, isMerge: isMerge) },
                    onBlockName: { item in block(item) }
                )
            } else {
                NavigationStack {
                    phaseContent
                        .pageTitle("Lọc name local")
                        .safeAreaInset(edge: .bottom) { bottomBar }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { session.cancel() }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .setup, .review:
            setupForm
        case .preparing, .running, .stopping:
            LocalNameFilterProgressView(session: session)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            switch session.phase {
            case .setup, .review:
                Button(action: startFilter) {
                    Text("Bắt đầu lọc")
                }
                .buttonStyle(.appFilled)
                .disabled(!canStart)
            case .preparing, .running:
                Button(action: { session.stop() }) {
                    Text("Dừng")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            case .stopping:
                Button(action: {}) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang phân tích nốt…")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Chụp cấu hình từ hai danh sách đúng lúc bấm, rồi giao cho `session` (lấy chương đã tải theo phạm vi + chạy).
    private func startFilter() {
        guard canStart else { return }
        let configuration = LocalNameFilter.Configuration(
            minCount: minCount,
            suffixes: LocalNameFilterSuffixStore.shared.enabledSuffixes(),
            blockedTerms: LocalNameFilterBlocklistStore.shared.terms()
        )
        session.start(
            bookId: bookId,
            fromChapterIndex: fromChapterIndexForRun,
            limit: limitValue,
            convertsTraditional: convertsTraditionalToSimplified,
            configuration: configuration
        )
    }

    /// Lưu như màn AI (Name riêng / VP riêng, Gộp / Thay thế) — `ReaderAINameReviewSheet` đóng sheet ngay sau khi gọi.
    private func save(_ items: [AIExtractedName], isName: Bool, isMerge: Bool) {
        let bid = bookId
        Task {
            let savedCount = await AIHarnessService.shared.saveExtractedEntries(
                items, bookId: bid, isName: isName, isMerge: isMerge
            )
            await MainActor.run {
                let targetName = isName ? "Name riêng" : "VietPhrase riêng"
                if savedCount > 0 {
                    ToastManager.shared.show(message: "Đã lưu \(savedCount) mục vào \(targetName) của truyện", type: .success)
                } else {
                    ToastManager.shared.show(message: "Lưu vào \(targetName) thất bại", type: .error)
                }
            }
        }
    }

    /// ✕ › "Không phải name": màn duyệt bỏ mục khỏi lần này; ở đây thêm vào danh sách loại bỏ dùng chung. Store từ chối
    /// (không phải chữ Hán, quá dài, đầy danh sách…) ⇒ toast lỗi của store, mục vẫn chỉ bị bỏ khỏi lần này.
    private func block(_ item: AIExtractedName) {
        let term = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        if let error = LocalNameFilterBlocklistStore.shared.add(term) {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: "Đã thêm \(term) vào “Không phải name”", type: .success)
        }
    }
}
