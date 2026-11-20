import SwiftUI

/// **Tạm thời** (1.3.1026) — trang mẫu của màn tự thử nhịp dọc header: dựng đúng một kiểu nội dung (Form, Form có tiêu
/// đề nhóm, Form / List trơn dưới ô tìm, List trơn, panel ScrollView, header tự dựng) với một cách chỉnh khoảng trên,
/// header giống trang thật (`.backPageTitle` + cụm 🔍 | … canh phải như 1.3.1023). Số đo gửi về `HeaderSpacingLabRecorder`.
struct HeaderSpacingLabPage: View {
    let variant: HeaderSpacingLabVariant
    let recorder: HeaderSpacingLabRecorder

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if variant.kind == .customBack {
            customHeaderPage
        } else {
            standardPage
        }
    }

    // MARK: - Trang có thanh hệ thống

    private var standardPage: some View {
        content
            .modifier(LabSearch(enabled: variant.hasSearch, query: $query))
            .backPageTitle("Mẫu \(variant.kind.rawValue)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: HeaderButtonMetrics.pairSpacing) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                            .frame(width: HeaderButtonMetrics.pairIconWidth, height: HeaderMetrics.iconFrameHeight)
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                            .frame(width: HeaderButtonMetrics.pairIconWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                            .labMeasure("toolbarRight", recorder)
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .background(alignment: .topLeading) {
                HeaderSpacingLabProbe(dumpsBar: variant.kind == .plain && variant.fix == .none) { recorder.receive($0) }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch variant.kind {
        case .form, .formHeader, .formSearch:
            applyFix(formContent)
        case .plain, .plainSearch:
            applyFix(plainContent)
        case .panels, .customBack:
            panelContent
        }
    }

    private var formContent: some View {
        Form {
            if variant.kind == .formHeader {
                Section {
                    formRows
                } header: {
                    Text("Nhóm đầu").labMeasure("groupText", recorder)
                }
            } else {
                Section { formRows }
            }
            Section("Nhóm hai") {
                Text("Hàng nhóm hai")
                Text("Hàng nhóm hai")
            }
        }
    }

    @ViewBuilder
    private var formRows: some View {
        Text("Hàng đầu").labMeasure("firstRowText", recorder)
        LabeledContent("Hàng hai", value: "Giá trị")
        LabeledContent("Hàng ba", value: "Giá trị")
    }

    private var plainContent: some View {
        List {
            ForEach(0..<14, id: \.self) { index in
                Text("Hàng \(index + 1)")
                    .labMeasure(index == 0 ? "firstRowText" : "row\(index)", recorder)
            }
        }
        .listStyle(.plain)
    }

    private var panelContent: some View {
        ScrollView {
            LazyVStack(spacing: BookListPanelModifier.stackSpacing) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 92)
                        .labMeasure(index == 0 ? "firstPanel" : "panel\(index)", recorder)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, variant.fix == .panelPad16 ? 16 : 4)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func applyFix<Content: View>(_ view: Content) -> some View {
        switch variant.fix {
        case .none, .panelPad16:
            view
        case .margin0:
            view.contentMargins(.top, 0, for: .scrollContent)
        case .margin16:
            view.contentMargins(.top, 16, for: .scrollContent)
        case .minHeader0:
            view.environment(\.defaultMinListHeaderHeight, 0)
        case .compact:
            view.listSectionSpacing(.compact)
        case .margin16MinHeader0:
            view.contentMargins(.top, 16, for: .scrollContent).environment(\.defaultMinListHeaderHeight, 0)
        }
    }

    // MARK: - Header tự dựng

    /// Thanh hệ thống ẩn, hàng nút tự dựng như Reader / truyện tranh: `HeaderBackButton` + "…" canh phải, lề chung.
    private var customHeaderPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HeaderBackButton { recorder.current = nil }
                    .labMeasure("customBack", recorder)
                Text("Header tự dựng")
                    .font(.system(size: HeaderMetrics.rowTitleFontSize, weight: .bold))
                    .padding(.leading, -HeaderBackButton.titleOverlap)
                Spacer(minLength: 0)
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                    .labMeasure("customRight", recorder)
            }
            .padding(.horizontal, HeaderMetrics.horizontalMargin)
            .frame(height: HeaderMetrics.rowHeight)
            panelContent
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(alignment: .topLeading) {
            HeaderSpacingLabProbe(dumpsBar: false) { recorder.receive($0) }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Ô tìm luôn hiện như trang danh sách thật (`.navigationBarDrawer(displayMode: .always)`), chỉ khi biến thể cần.
    private struct LabSearch: ViewModifier {
        let enabled: Bool
        @Binding var query: String

        @ViewBuilder
        func body(content: Content) -> some View {
            if enabled {
                content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm")
            } else {
                content
            }
        }
    }
}
