import SwiftUI

/// Bảng cấu hình dịch dùng chung: công tắc "Dịch văn bản" + PHẠM VI ÁP DỤNG (Truyện này / Nguồn này / Tất cả) + "Lưu lại".
/// Tách khỏi `ReaderTranslationScopeMenuView` để menu header Khám phá (`DiscoverySourceMenuButton`) mở lại đúng bảng này.
/// Caller tự lo nút neo và `.popover` (`.presentationCompactAdaptation(.popover)` + `.preferredColorScheme(.dark)`);
/// bảng ghi `TranslationConfigStore` rồi gọi `onDone` để caller đóng popover.
struct TranslationScopePopupView: View {
    private typealias TranslationPopupScope = ReaderTranslationScopeMenuView.TranslationPopupScope

    let bookId: String
    let packageId: String
    let sourceName: String
    let isChineseSourceHint: Bool?
    let onDone: () -> Void

    @State private var tempIsEnabled: Bool
    @State private var selectedScope: TranslationPopupScope

    init(
        bookId: String,
        packageId: String,
        sourceName: String,
        isChineseSourceHint: Bool?,
        onDone: @escaping () -> Void
    ) {
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.isChineseSourceHint = isChineseSourceHint
        self.onDone = onDone
        // Nội dung popover bị huỷ khi đóng nên mỗi lần mở đều khởi tạo lại tại đây: công tắc lấy trạng thái đang
        // hiệu lực (như `preparePopupState()` cũ của nút dịch).
        _tempIsEnabled = State(initialValue: TranslationConfigStore.shared.resolveStatus(
            bookId: bookId,
            packageId: packageId,
            isChineseSourceHint: isChineseSourceHint
        ).isEnabled)
        // Khởi tạo ngay theo phạm vi **có thật** của màn gọi: Khám phá truyền `bookId: ""` nên không bao giờ
        // được bắt đầu ở "Truyện này" (mục đó còn không có trong `Menu`). Trước đây mặc định cứng `.book` và chỉ
        // sửa trong `preparePopupState()` lúc bấm nút, nên popover vẽ lần đầu vẫn ghi "Truyện này".
        _selectedScope = State(initialValue: Self.availableScope(bookId: bookId, packageId: packageId))
    }

    /// Phạm vi mặc định theo tham số màn gọi — chỉ chọn cấp **đang tồn tại**.
    static func availableScope(bookId: String, packageId: String) -> ReaderTranslationScopeMenuView.TranslationPopupScope {
        if !bookId.isEmpty { return .book }
        if !packageId.isEmpty { return .source }
        return .global
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

    var body: some View {
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
                                if effectiveScope == .book {
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
                                if effectiveScope == .source {
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
                            if effectiveScope == .global {
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

    /// Phạm vi đang chọn nhưng đã kẹp về cấp có thật: `selectedScope` có thể còn `.book` từ state khởi tạo cũ
    /// hoặc từ lần mở trước, trong khi màn hiện tại không có truyện/nguồn tương ứng.
    private var effectiveScope: TranslationPopupScope {
        switch selectedScope {
        case .book:
            return bookId.isEmpty ? Self.availableScope(bookId: bookId, packageId: packageId) : .book
        case .source:
            return packageId.isEmpty ? Self.availableScope(bookId: bookId, packageId: packageId) : .source
        case .global:
            return .global
        }
    }

    private var scopeDisplayText: String {
        switch effectiveScope {
        case .book:
            return "Truyện này"
        case .source:
            return "Nguồn này (\(displaySourceName))"
        case .global:
            return "Tất cả (Toàn cục)"
        }
    }

    private func saveSettings() {
        // Dùng scope đã kẹp: `bookId` rỗng mà lưu `.book` sẽ ghi override rác với khoá "" vào `UserDefaults`.
        switch effectiveScope {
        case .book:
            TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: tempIsEnabled ? .enabled : .disabled)
        case .source:
            TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: tempIsEnabled ? .enabled : .disabled)
        case .global:
            TranslationConfigStore.shared.globalEnabled = tempIsEnabled
        }
        onDone()
    }
}
