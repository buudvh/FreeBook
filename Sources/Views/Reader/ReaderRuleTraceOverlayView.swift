import SwiftUI

/// Màn **Check rule** của Reader: soi cả đoạn văn, hiện mọi rule khớp (thắng / tranh chấp / đã tắt),
/// cho sửa/bật-tắt-xoá ngay và thêm rule mới từ cụm đang chọn.
///
/// Bố cục mượn màn Dịch (`ReaderDefinitionOverlayView`) để tay người dùng không phải học lại:
/// 1. thanh **chữ gốc** của đoạn, có 4 chevron nới/thu cụm;
/// 2. thanh **nghĩa** mà rule đang chọn sinh ra;
/// 3. dải **nghĩa từng token** của rule đó;
/// 4. dải **chip rule**, đầu dải là nút `+`.
///
/// Bấm một ký tự ở thanh 1 **không** chọn một ký tự lẻ mà snap vào **cụm áp dụng** của rule phủ ký tự
/// đó — đúng yêu cầu "bấm vào mỗi thành phần chọn cụm áp dụng rule dịch".
struct ReaderRuleTraceOverlayView: View {
    /// Ba việc có thể làm với một rule từ popup ấn giữ.
    enum RuleAction: Equatable {
        case setDisabled(Bool, QuickTranslationRuleScope)
        case edit
        case delete
    }

    let paragraphIndex: Int
    let bookId: String
    let originalSentence: String
    @Binding var selectedWordOffset: Int
    @Binding var selectedWordLength: Int
    let traces: [QuickTranslationRuleTrace]
    @Binding var focusedTraceID: String?
    /// Công tắc tổng của tính năng rule — tắt thì phải nói ra, không hiện dải trắng.
    let isRuleFeatureEnabled: Bool
    let hasAnyRuleSet: Bool
    let onAddRule: () -> Void
    let onRuleAction: (QuickTranslationRuleTrace, RuleAction) -> Void
    let onShowGuide: () -> Void
    let onClose: () -> Void

    @ObservedObject private var disableStore = QuickTranslationRuleDisableStore.shared
    @State private var actionTarget: QuickTranslationRuleTrace? = nil
    @State private var showingActions = false

    private var accent: Color { Color(red: 0.30, green: 0.82, blue: 0.55) }

    private var focusedTrace: QuickTranslationRuleTrace? {
        if let focusedTraceID, let match = traces.first(where: { $0.id == focusedTraceID }) {
            return match
        }
        return traces.first
    }

    var body: some View {
        VStack(spacing: 12) {
            dragIndicatorView
            headerView
            originalSentenceRowView
            meaningRowView
            captureRowView
            chipStripView
            if let notice = noticeText {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .confirmationDialog(
            actionTarget.map { "Rule dòng \($0.sourceLine) · \($0.scope.longLabel)" } ?? "Rule",
            isPresented: $showingActions,
            titleVisibility: .visible,
            presenting: actionTarget
        ) { trace in
            actionButtons(for: trace)
        } message: { trace in
            Text("\(trace.pattern)\n→ \(trace.replacement)")
        }
    }

    private var noticeText: String? {
        if !hasAnyRuleSet {
            return "Máy chưa có bộ rule nào. Tải hoặc nhập ở Cài đặt → Quản lý rule dịch."
        }
        if !isRuleFeatureEnabled {
            return "Công tắc rule dịch đang TẮT trong Cài đặt — bên dưới chỉ là mô phỏng, chưa áp dụng."
        }
        if traces.isEmpty {
            return "Không rule nào chạm đoạn này."
        }
        return nil
    }

    private var dragIndicatorView: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check rule")
                    .font(.headline)
                Text(paragraphIndex < 0 ? "Tiêu đề chương" : "Đoạn #\(paragraphIndex)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onShowGuide) {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundColor(accent)
            }
            .accessibilityLabel("Hướng dẫn dùng màn check rule")

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .accessibilityLabel("Đóng")
        }
    }

    // MARK: - ① Thanh chữ gốc

    private var originalSentenceRowView: some View {
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                chevronButton("chevron.left") { expand(byLeft: true) }
                chevronButton("chevron.right") { shrink(fromLeft: true) }
            }
            .foregroundColor(accent)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let nsSentence = originalSentence as NSString
                        ForEach(0..<nsSentence.length, id: \.self) { index in
                            characterView(
                                nsSentence.substring(with: NSRange(location: index, length: 1)),
                                at: index
                            )
                        }
                    }
                }
                .onChange(of: selectedWordOffset) { _, _ in
                    withAnimation {
                        proxy.scrollTo("rule-orig-\(selectedWordOffset)", anchor: .center)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("rule-orig-\(selectedWordOffset)", anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                chevronButton("chevron.left") { shrink(fromLeft: false) }
                chevronButton("chevron.right") { expand(byLeft: false) }
            }
            .foregroundColor(accent)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    /// Ký tự thuộc cụm của rule đang chọn thì đậm + gạch chân; ký tự thuộc **token** trong cụm đó còn
    /// có nền nhạt để phân biệt phần literal với phần token.
    private func characterView(_ char: String, at index: Int) -> some View {
        let inSelection = index >= selectedWordOffset && index < selectedWordOffset + selectedWordLength
        let inCapture = isInsideCapture(index)
        return Text(char)
            .font(.body)
            .bold(inSelection)
            .underline(inSelection)
            .foregroundColor(inSelection ? accent : .primary)
            .padding(.horizontal, 1)
            .background(inCapture ? accent.opacity(0.18) : Color.clear)
            .cornerRadius(3)
            .id("rule-orig-\(index)")
            .onTapGesture { snapToRule(coveringCharacterAt: index) }
    }

    private func chevronButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(Circle())
        }
    }

    // MARK: - ② Thanh nghĩa rule · ③ Nghĩa từng token

    private var meaningRowView: some View {
        HStack(alignment: .top, spacing: 8) {
            if let trace = focusedTrace {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trace.rendered.isEmpty ? "(rule này không sinh chữ nào ở đây)" : trace.rendered)
                        .font(.body)
                        .foregroundColor(trace.status.isDisabled ? .secondary : .primary)
                        .textSelection(.enabled)

                    Text(trace.status.isDisabled
                         ? "\(ReaderRuleChipStyle.label(for: trace.status)) — chưa áp dụng"
                         : ReaderRuleChipStyle.label(for: trace.status))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Chọn một rule ở dải bên dưới để xem nghĩa nó sinh ra.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var captureRowView: some View {
        let captures = focusedTrace?.captures.filter { !$0.sourceText.isEmpty } ?? []
        if !captures.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(captures, id: \.index) { capture in
                        Button {
                            if let range = capture.sourceRange, range.length > 0 {
                                selectedWordOffset = range.location
                                selectedWordLength = range.length
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(capture.sourceText)
                                    .font(.system(size: 12, design: .monospaced))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                                Text(capture.renderedText.isEmpty ? "∅" : capture.renderedText)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.12))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - ④ Dải chip rule

    private var chipStripView: some View {
        HStack(spacing: 8) {
            Button(action: onAddRule) {
                Image(systemName: "plus")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
                    .padding(9)
                    .background(accent.opacity(0.14))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Thêm rule mới từ cụm đang chọn")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(traces) { trace in
                        ReaderRuleTraceChip(
                            trace: trace,
                            isSelected: trace.id == focusedTrace?.id,
                            onTap: { focus(trace) },
                            onLongPress: {
                                actionTarget = trace
                                showingActions = true
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Popup ấn giữ. Lựa chọn hiện ra **theo phạm vi của chính rule đó**, đúng bảng ngữ nghĩa file tắt:
    ///
    /// - Rule của **bộ riêng** chỉ chịu file tắt riêng ⇒ chỉ có "Tắt/Bật cho truyện này". Đưa thêm
    ///   "tắt ở bộ chung" vào đây là hứa một việc không có hiệu lực.
    /// - Rule của **bộ chung** chịu cả hai ⇒ có đủ hai lựa chọn: tắt riêng cho truyện đang đọc, hoặc
    ///   tắt cho mọi truyện.
    @ViewBuilder
    private func actionButtons(for trace: QuickTranslationRuleTrace) -> some View {
        let bookScope = QuickTranslationRuleScope.book(bookId)
        let disabledForBook = disableStore.isDisabled(pattern: trace.pattern, in: bookScope)

        Button("Sửa rule") {
            onRuleAction(trace, .edit)
        }

        if !bookId.isEmpty {
            Button(disabledForBook ? "Bật cho truyện này" : "Tắt cho truyện này") {
                onRuleAction(trace, .setDisabled(!disabledForBook, bookScope))
            }
        }

        if trace.scope.isGlobal {
            let disabledGlobally = disableStore.isDisabled(pattern: trace.pattern, in: .global)
            Button(disabledGlobally ? "Bật cho mọi truyện" : "Tắt cho mọi truyện") {
                onRuleAction(trace, .setDisabled(!disabledGlobally, .global))
            }
        }

        Button("Xoá rule khỏi \(trace.scope.longLabel.lowercased())", role: .destructive) {
            onRuleAction(trace, .delete)
        }

        Button("Hủy", role: .cancel) {}
    }

    // MARK: - Chọn cụm

    /// Bấm một ký tự ⇒ snap vào **cụm áp dụng** của rule phủ ký tự đó, ưu tiên rule đang thắng; không
    /// rule nào phủ thì chọn đúng một ký tự như các panel khác.
    private func snapToRule(coveringCharacterAt index: Int) {
        let covering = traces.filter {
            $0.sourceRange.length > 0
                && index >= $0.sourceRange.location
                && index < NSMaxRange($0.sourceRange)
        }
        if let winner = covering.first(where: { $0.status == .applied }) ?? covering.first {
            focus(winner)
            return
        }
        selectedWordOffset = index
        selectedWordLength = 1
    }

    private func focus(_ trace: QuickTranslationRuleTrace) {
        focusedTraceID = trace.id
        guard trace.sourceRange.length > 0 else { return }
        selectedWordOffset = trace.sourceRange.location
        selectedWordLength = trace.sourceRange.length
    }

    private func isInsideCapture(_ index: Int) -> Bool {
        guard let trace = focusedTrace else { return false }
        for capture in trace.captures {
            guard let range = capture.sourceRange, range.length > 0 else { continue }
            if index >= range.location && index < NSMaxRange(range) { return true }
        }
        return false
    }

    private func expand(byLeft: Bool) {
        if byLeft {
            guard selectedWordOffset > 0 else { return }
            selectedWordOffset -= 1
            selectedWordLength += 1
        } else {
            guard selectedWordOffset + selectedWordLength < (originalSentence as NSString).length else { return }
            selectedWordLength += 1
        }
    }

    private func shrink(fromLeft: Bool) {
        guard selectedWordLength > 1 else { return }
        if fromLeft {
            selectedWordOffset += 1
        }
        selectedWordLength -= 1
    }
}
