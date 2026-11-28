import SwiftUI

/// Sheet "Lọc name local" (Reader › "…", plan 2026-11-27, mockup khung 2–4; bản LAC: mockup LAC khung 1–5): tự dò tên
/// người / địa danh / tổ chức / thuật ngữ trong chữ Hán các chương đã tải, ngay trên máy, không gọi AI, rồi duyệt và lưu
/// vào Name / VP riêng của truyện.
///
/// Ba bước trong **một** sheet, theo `LocalNameFilterSession.phase`:
/// 1. Chọn phạm vi (`+Setup`): như "Lọc name nhiều chương" của AI (`ReaderAIBatchPromptSheet`) bỏ "Tiếp nối"; không đọc /
///    ghi mặc định của sheet AI. Hàng "Lịch sử lọc ›" ở đầu (`+History`, trang `LocalNameFilterHistoryView` — mỗi lần lọc,
///    đã lưu / chưa lưu, mở lại gói tạm), "Loại cần tìm" (`+Categories`,
///    nhớ bằng `@AppStorage`), "Ít nhất N lần" (mặc định 3), "Độ dài name" (thanh kéo hai đầu, nhớ bằng `@AppStorage`) +
///    "Ưu tiên tên Latin" + "Nới đoán tên Latin" (theo truyện, `LocalNameFilterLatinPreferenceStore`), mục "Danh sách" mở
///    bốn màn quản lý (Hậu tố, Tiền tố, Họ, Không phải name) — chung mọi truyện, Hậu tố / Tiền tố / Không phải name có thêm
///    bản riêng của truyện.
///    Không có hàng tải model: chưa có model thì bước 2 tự tải trước.
/// 2. Đang lọc (`LocalNameFilterProgressView`): "Tải model" (lần đầu) rồi "Phân tích chương", name hiện dần; "Dừng" =
///    phân tích nốt phần đã đọc rồi sang bước 3. Lỗi ⇒ "Quay lại" / "Thử lại" (đúng cấu hình cũ).
/// 3. Duyệt: thay cả gốc sheet bằng `ReaderAINameReviewSheet` (danh sách có sẵn, sắp "Nhiều lần nhất", chip lọc loại,
///    badge NE / VP + name đã có bỏ chọn sẵn, ✕ có "Không phải name"); lưu thẳng qua `AIHarnessService.saveExtractedEntries`
///    như màn AI. Nút ‹ ở header ⇒ giữ gói tạm (không toast) rồi về bước 1, sheet không đóng
///    (`LocalNameFilterSession.leaveReview`).
/// Đóng sheet (vuốt xuống) ở bất kỳ bước nào ⇒ huỷ lượt lọc; đang duyệt mà chưa Lưu ⇒ giữ gói tạm + toast. `onDisappear`
/// gắn ở `ZStack` ngoài cùng, sống qua mọi lần đổi bước (gắn vào `Group` thì SwiftUI rải xuống từng nhánh, đổi bước là
/// tưởng đóng sheet). App vào nền lúc đang duyệt ⇒ cũng giữ gói (không toast).
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

    @Environment(\.scenePhase) private var scenePhase
    /// `false` khi sheet đang đóng thật; vẫn `true` lúc chỉ bị màn toàn màn che (xem `closeSheet`).
    @Environment(\.isPresented) private var isPresented
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
    /// "Ưu tiên tên Latin" của truyện này — đọc khi mở / quay về, ghi ngay khi bấm (`LocalNameFilterLatinPreferenceStore`).
    @State var prefersLatinNames: Bool = false
    /// "Nới đoán tên Latin" của truyện này (giá trị đã lưu, kể cả khi "Ưu tiên tên Latin" đang tắt) — như `prefersLatinNames`
    /// (`LocalNameFilterLatinPreferenceStore.loose`).
    @State var loosensLatinGuess: Bool = false
    /// Số mục của bốn danh sách (hậu tố, tiền tố, họ, "Không phải name") — đọc lại mỗi khi quay về từ màn quản lý. Hậu tố /
    /// tiền tố: số Chung + số riêng của truyện này (hàng ghi "1.299 · 3 riêng").
    @State var suffixCount: Int = 0
    @State var prefixCount: Int = 0
    @State var suffixBookCount: Int = 0
    @State var prefixBookCount: Int = 0
    @State var surnameCount: Int = 0
    @State var blockedCount: Int = 0
    /// Số cụm "Không phải name" riêng của truyện này (hàng ghi "214 · 3 riêng").
    @State var blockedBookCount: Int = 0
    /// "Độ dài name" (plan 2026-11-27-phan-loai-name L15): ít nhất / nhiều nhất N chữ, 2…10; nhiều nhất 10 = "10+" (không
    /// giới hạn). Mặc định 2 – 10+ ⇒ kết quả như trước. Giá trị hỏng được kẹp khi đọc (`LocalNameFilterLengthRangeSlider`).
    @AppStorage("localNameFilterMinLength") var minLengthSetting: Int = LocalNameFilterLengthRangeSlider.bounds.lowerBound
    @AppStorage("localNameFilterMaxLength") var maxLengthSetting: Int = LocalNameFilterLengthRangeSlider.bounds.upperBound
    /// "Loại cần tìm" (`+Categories`): `rawValue` các nhóm nối bằng dấu phẩy; rỗng / hỏng = cả bốn nhóm.
    @AppStorage("localNameFilterCategories") var categoriesRaw: String = ""
    /// Lịch sử lọc + gói tạm của truyện cho hàng "Lịch sử lọc" (`+History`); nạp ngoài main mỗi lần trang đầu hiện ra.
    @State var history = LocalNameFilterHistorySnapshot.empty
    /// Đã nạp lịch sử lần đầu (trước đó không ghi "Chưa có").
    @State var historyLoaded = false
    /// Trang Lịch sử lọc đang được đẩy vào stack của sheet.
    @State var showsHistory = false
    /// Màn duyệt đang mở là gói mở từ trang Lịch sử lọc ⇒ bấm ‹ thì về lại trang đó (`+History.reopenHistoryIfNeeded`).
    @State var reopensHistoryAfterReview = false

    var body: some View {
        ZStack {
            if session.phase == .review {
                ReaderAINameReviewSheet(
                    names: session.reviewNames,
                    bookId: bookId,
                    onSave: { items, isName, mode in save(items, isName: isName, mode: mode) },
                    onBlockName: { item, scope in block(item, scope: scope) },
                    onNamesChange: { names in session.updateReviewNames(names) },
                    onBack: { session.leaveReview() },
                    suffixContext: session.reviewSuffixContext
                )
            } else {
                NavigationStack {
                    phaseContent
                        .pageTitle("Lọc name local")
                        .safeAreaInset(edge: .bottom) { bottomBar }
                        .navigationDestination(isPresented: $showsHistory) {
                            LocalNameFilterHistoryView(bookId: bookId) { draft in
                                openDraftFromHistory(draft)
                            }
                        }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { closeSheet() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                session.persistDraftForBackground()
            }
        }
        // Màn duyệt mở từ trang Lịch sử lọc đóng bằng ‹ ⇒ stack dựng lại từ gốc, đẩy lại trang lịch sử.
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .setup {
                reopenHistoryIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .setup, .review:
            setupForm
        case .preparing, .running, .stopping, .failed:
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
            case .failed:
                HStack(spacing: 10) {
                    Button(action: { session.leaveFailure() }) {
                        Text("Quay lại")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { session.retry() }) {
                        Text("Thử lại")
                    }
                    .buttonStyle(.appFilled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Chụp cấu hình từ các danh sách (hậu tố, tiền tố, "Không phải name") + "Loại cần tìm" + "Độ dài name" đúng lúc bấm,
    /// rồi giao cho `session` (lấy chương đã tải theo phạm vi + chạy). Danh sách họ do bộ lọc tự đọc lúc chạy.
    private func startFilter() {
        guard canStart else { return }
        let length = LocalNameFilterLengthRangeSlider.clamped(lower: minLengthSetting, upper: maxLengthSetting)
        let configuration = LocalNameFilter.Configuration(
            minCount: minCount,
            suffixes: LocalNameFilterSuffixStore.shared.allSuffixes(bookId: bookId),
            // "Không phải name" Chung + Riêng của truyện.
            blockedTerms: LocalNameFilterBookBlocklistStore.effectiveTerms(bookId: bookId),
            categories: selectedCategories,
            prefersLatinNames: prefersLatinNames,
            prefixes: LocalNameFilterPrefixStore.shared.allPrefixes(bookId: bookId),
            minLength: length.lowerBound,
            maxLength: length.upperBound >= LocalNameFilterLengthRangeSlider.bounds.upperBound ? nil : length.upperBound,
            // Giá trị hiệu lực: "Nới" chỉ có tác dụng cùng "Ưu tiên tên Latin" (dấu gói tạm tính cùng một cách).
            loosensLatinGuess: prefersLatinNames && loosensLatinGuess
        )
        let numbers = Dictionary((chapters ?? []).map { ($0.index, $0.number) }, uniquingKeysWith: { first, _ in first })
        session.start(LocalNameFilterSession.StartRequest(
            bookId: bookId,
            fromChapterIndex: fromChapterIndexForRun,
            limit: limitValue,
            convertsTraditional: convertsTraditionalToSimplified,
            configuration: configuration,
            chapterNumbers: numbers
        ))
    }

    /// Sheet đóng (vuốt xuống, hoặc màn duyệt tự đóng sau khi bấm Lưu): đang duyệt mà chưa Lưu ⇒ giữ gói tạm; rồi huỷ
    /// lượt lọc nếu còn chạy.
    ///
    /// `onDisappear` còn chạy khi sheet chỉ bị **che** (màn Sửa từ mở tra cứu ngoài bằng `fullScreenCover`) — lúc đó vẫn
    /// ghi gói (ghi đè cùng gói, vô hại) và `cancel()` vô hại ở màn duyệt, nhưng chỉ báo toast khi sheet thật sự đóng
    /// (`isPresented == false`), để không báo sớm rồi báo lại lần hai.
    private func closeSheet() {
        if let kept = session.keepDraftOnClose(), !isPresented {
            ToastManager.shared.show(message: "Đã giữ gói tạm (\(kept) name)", type: .info)
        }
        session.cancel()
    }

    /// Lưu như màn AI (Name riêng / VP riêng, ba cách lưu `DataImportMode` — popup ở `ReaderAINameReviewSheet+Save`) —
    /// `ReaderAINameReviewSheet` đóng sheet ngay sau khi gọi. Lưu xong (kể cả "Chỉ thêm key mới" mà mọi name đã có) ⇒ xoá
    /// gói tạm của màn duyệt này (mở từ gói, hoặc đã ghi khi app vào nền); lưu lỗi ⇒ ghi gói để không mất danh sách.
    private func save(_ items: [AIExtractedName], isName: Bool, mode: DataImportMode) {
        let bid = bookId
        let pending = session.beginSave()
        Task {
            let result = await AIHarnessService.shared.saveExtractedEntries(
                items, bookId: bid, isName: isName, mode: mode
            )
            await MainActor.run {
                let targetName = isName ? "Name riêng" : "VietPhrase riêng"
                if let result {
                    if let pending {
                        LocalNameFilterDraftStore.delete(id: pending.draft.id, bookId: pending.bookId)
                        // Lịch sử lọc: lần lọc của màn duyệt này thành "Đã lưu X / Y" (X = số name thực lưu).
                        LocalNameFilterHistoryStore.markSaved(
                            id: pending.draft.id,
                            savedCount: result.saved,
                            at: Date(),
                            fallback: pending.draft,
                            bookId: pending.bookId
                        )
                    }
                    let toast = ReaderAINameReviewSheet.savedToast(result, targetName: targetName)
                    ToastManager.shared.show(message: toast.message, type: toast.type)
                } else if let pending, !pending.draft.names.isEmpty {
                    LocalNameFilterDraftStore.upsert(pending.draft, bookId: pending.bookId)
                    ToastManager.shared.show(
                        message: "Lưu vào \(targetName) thất bại · đã giữ gói tạm (\(pending.draft.names.count) name)",
                        type: .error
                    )
                } else {
                    ToastManager.shared.show(message: "Lưu vào \(targetName) thất bại", type: .error)
                }
            }
        }
    }

    /// Thùng rác › "Không phải name · riêng truyện / mọi truyện" (mockup N1): màn duyệt bỏ mục khỏi lần này; ở đây thêm vào
    /// danh sách loại bỏ riêng của truyện (`LocalNameFilterBookBlocklistStore`) hoặc dùng chung (`LocalNameFilterBlocklistStore`).
    /// Store từ chối (không phải chữ Hán, quá dài, đầy danh sách…) ⇒ toast lỗi của store, mục vẫn chỉ bị bỏ khỏi lần này.
    private func block(_ item: AIExtractedName, scope: LocalNameFilter.BlockScope) {
        let term = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let error: String?
        switch scope {
        case .book: error = LocalNameFilterBookBlocklistStore.shared.add(term, bookId: bookId)
        case .common: error = LocalNameFilterBlocklistStore.shared.add(term)
        }
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            let note = scope == .book ? "riêng truyện" : "mọi truyện"
            ToastManager.shared.show(message: "Đã thêm \(term) vào “Không phải name” (\(note))", type: .success)
        }
    }
}
