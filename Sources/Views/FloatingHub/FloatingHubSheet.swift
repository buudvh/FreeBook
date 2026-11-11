import SwiftUI

/// **Sheet hub** (anh Bửu duyệt mockup 2026-11-11, thay thẻ menu nổi cạnh nút của 1.3.524): chạm nút hub ⇒ sheet cùng kiểu
/// sheet điều khiển nhanh của nhạc / TTS — nền kính tối theo cài đặt **ngăn kéo** (`DrawerGlassSheetBackground`), bo 16,
/// cao vừa nội dung, vuốt xuống để đóng (không nút chỉ để đóng). Trình bày từ **cửa sổ hub** (`FloatingHubSheetHost`).
///
/// - Trang chính: dòng đầu "Lối tắt nổi" + "N đang chạy"; **bốn dòng cố định** (AI → Thông báo → Video → Kiểm tra nguồn,
///   `FloatingHubItem.Kind.allCases`) dạng ô bo góc, không vạch ngăn. Dòng không dùng được mờ 40%, không biến mất. Dòng
///   Video giữ ⏸ / ✕ ngay trên dòng (sheet không đóng).
/// - Trang con trong sheet: "Tác vụ AI" (`FloatingHubAITaskListView`) và "Kiểm tra nguồn" khi có hai lượt
///   (`FloatingHubSourceCheckListView`), nút ‹ quay lại; danh sách rỗng ⇒ tự về trang chính.
/// - Chạm một dòng mở mục ⇒ container đóng sheet **xong** mới mở (`FloatingHubSheetState.dismiss(then:)`).
///
/// Đọc thẳng `FloatingHubPresentationReader` (chỉ sống khi sheet mở nên vẽ lại theo snapshot là chấp nhận được).
struct FloatingHubSheet: View {
    enum Page {
        case main
        case aiTasks
        /// Hai lượt kiểm tra nguồn cùng thu nhỏ (1.3.697).
        case sourceChecks
    }

    /// Lời gọi về container (`FloatingHubContainerViewController+Actions`).
    struct Actions {
        let onSelect: (FloatingHubItem.Kind) -> Void
        let onTogglePlayback: (FloatingHubItem.Kind) -> Void
        let onStopPlayback: (FloatingHubItem.Kind) -> Void
        let onSelectAITask: (String) -> Void
        let onSelectSourceCheck: (MinimizedSourceCheck.Kind) -> Void
    }

    @ObservedObject var reader: FloatingHubPresentationReader
    @ObservedObject var state: FloatingHubSheetState
    let actions: Actions

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .environment(\.colorScheme, .dark)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(HeightKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - state.contentHeight) > 0.5 else { return }
                state.contentHeight = newHeight
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .appAccentTint()
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
            .presentationBackground { DrawerGlassSheetBackground() }
            .animation(.easeInOut(duration: 0.2), value: shownPage)
    }

    /// Một nấc cao đúng nội dung (`.medium` trong lúc chờ đo lần đầu).
    private var detents: Set<PresentationDetent> {
        state.contentHeight > 0 ? [.height(state.contentHeight)] : [.medium]
    }

    /// Trang đang hiện; danh sách của trang con rỗng (AI vừa xong, lượt kiểm tra vừa đóng) ⇒ trang chính.
    private var shownPage: Page {
        let snapshot = reader.snapshot
        switch state.page {
        case .aiTasks where snapshot.aiTasks.isEmpty, .sourceChecks where snapshot.sourceChecks.isEmpty:
            return .main
        default:
            return state.page
        }
    }

    @ViewBuilder
    private var content: some View {
        let snapshot = reader.snapshot
        switch shownPage {
        case .main:
            VStack(spacing: 8) {
                mainHeader(button: snapshot.button)
                ForEach(FloatingHubItem.Kind.allCases, id: \.self) { kind in
                    FloatingHubMenuRow(
                        item: snapshot.items.first(where: { $0.kind == kind }) ?? FloatingHubItem(kind: kind),
                        onSelect: { selectMainRow(kind) },
                        onTogglePlayback: { actions.onTogglePlayback(kind) },
                        onStop: { actions.onStopPlayback(kind) }
                    )
                }
            }
        case .aiTasks:
            FloatingHubAITaskListView(
                tasks: snapshot.aiTasks,
                onSelect: actions.onSelectAITask,
                onBack: { state.page = .main }
            )
        case .sourceChecks:
            FloatingHubSourceCheckListView(
                entries: snapshot.sourceChecks,
                onSelect: actions.onSelectSourceCheck,
                onBack: { state.page = .main }
            )
        }
    }

    private func mainHeader(button: FloatingHubPresentationReader.ButtonState) -> some View {
        let running = button.runningKinds.filter { !button.quietKinds.contains($0) }.count
        return HStack(alignment: .firstTextBaseline) {
            Text("Lối tắt nổi")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if running > 0 {
                Text("\(running) đang chạy")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
    }

    /// AI ⇒ trang "Tác vụ AI"; Kiểm tra nguồn có hai lượt ⇒ trang chọn lượt; còn lại giao container (đóng sheet rồi mở).
    private func selectMainRow(_ kind: FloatingHubItem.Kind) {
        switch kind {
        case .ai:
            state.page = .aiTasks
        case .sourceCheck where reader.snapshot.sourceChecks.count > 1:
            state.page = .sourceChecks
        default:
            actions.onSelect(kind)
        }
    }

    // MARK: - Lồng (một type chính mỗi file)

    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

extension View {
    /// Một dòng của sheet hub: ô bo góc 12 nền mờ theo màu chữ, không vạch ngăn (kiểu Danh sách của app).
    func hubSheetPanelRow() -> some View {
        padding(.leading, 12)
            .padding(.trailing, 8)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
