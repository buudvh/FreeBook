import SwiftUI

/// Menu điều khiển cấu hình dịch thuật 3 mức: Truyện này > Nguồn này > Toàn cục.
/// Hiển thị Popover nhỏ gọn gồm Toggle Bật/Tắt + Dropdown chọn phạm vi + Nút Lưu lại.
public struct ReaderTranslationScopeMenuView: View {
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

    @State private var status: TranslationConfigStore.ResolvedStatus
    @State private var showingPopup = false
    @State private var tempIsEnabled: Bool = false
    @State private var selectedScope: TranslationPopupScope = .book

    public init(
        bookId: String,
        packageId: String = "",
        sourceName: String = "",
        textColor: Color? = nil,
        showBackground: Bool = true,
        isChineseSourceHint: Bool? = nil,
        iconSize: CGFloat = 19,
        frameWidth: CGFloat? = nil,
        frameHeight: CGFloat? = nil
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

    private var displaySourceName: String {
        if !sourceName.isEmpty {
            return sourceName
        }
        if packageId.isEmpty || packageId == "local" {
            return "Sách tự nhập (Local)"
        }
        return packageId
    }

    public var body: some View {
        Button(action: {
            preparePopupState()
            showingPopup = true
        }) {
            if showBackground {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: status.isEnabled ? "character.bubble.fill" : "character.bubble")
                        .font(.system(size: iconSize, weight: .semibold))
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
            } else {
                Image(systemName: status.isEnabled ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(status.isEnabled ? .white : (textColor?.opacity(0.45) ?? .secondary.opacity(0.6)))
                    .overlay(alignment: .topTrailing) {
                        if status.bookOverride != .inherited {
                            dotIndicator
                                .offset(x: iconSize <= 14 ? 3 : 4, y: iconSize <= 14 ? -2 : -3)
                        }
                    }
                    .frame(width: resolvedWidth, height: resolvedHeight)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.isEnabled ? "Đang bật dịch" : "Đang tắt dịch")
        .popover(isPresented: $showingPopup, arrowEdge: .top) {
            popupContent
                .presentationCompactAdaptation(.popover)
                .preferredColorScheme(.dark)
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

    private var popupContent: some View {
        VStack(spacing: 12) {
            // Hàng 1: Cần gạt Bật / Tắt dịch
            HStack(spacing: 10) {
                Image(systemName: tempIsEnabled ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)

                Text("Dịch văn bản")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Toggle("", isOn: $tempIsEnabled)
                    .labelsHidden()
                    .tint(.white)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Hàng 2: Dropdown chọn phạm vi áp dụng
            VStack(alignment: .leading, spacing: 6) {
                Text("PHẠM VI ÁP DỤNG")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Menu {
                    if !bookId.isEmpty {
                        Button {
                            selectedScope = .book
                        } label: {
                            HStack {
                                Text("Truyện này")
                                if selectedScope == .book {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    if !packageId.isEmpty {
                        Button {
                            selectedScope = .source
                        } label: {
                            HStack {
                                Text("Nguồn này (\(displaySourceName))")
                                if selectedScope == .source {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Button {
                        selectedScope = .global
                    } label: {
                        HStack {
                            Text("Tất cả (Toàn cục)")
                            if selectedScope == .global {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(scopeDisplayText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Hàng 3: Nút Lưu lại (Tone màu trắng/tối giản)
            Button(action: saveSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Lưu lại")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(minWidth: 260, maxWidth: 280)
    }

    private var scopeDisplayText: String {
        switch selectedScope {
        case .book:
            return "Truyện này"
        case .source:
            return "Nguồn này (\(displaySourceName))"
        case .global:
            return "Tất cả (Toàn cục)"
        }
    }

    private func preparePopupState() {
        refreshStatus()
        tempIsEnabled = status.isEnabled
        if !bookId.isEmpty {
            selectedScope = .book
        } else if !packageId.isEmpty {
            selectedScope = .source
        } else {
            selectedScope = .global
        }
    }

    private func saveSettings() {
        switch selectedScope {
        case .book:
            TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: tempIsEnabled ? .enabled : .disabled)
        case .source:
            TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: tempIsEnabled ? .enabled : .disabled)
        case .global:
            TranslationConfigStore.shared.globalEnabled = tempIsEnabled
        }
        refreshStatus()
        showingPopup = false
    }

    private func refreshStatus() {
        status = TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint)
    }
}
