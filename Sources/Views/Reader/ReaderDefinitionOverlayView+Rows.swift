import SwiftUI

/// Ba hàng dưới của panel Dịch: cụm định dạng + hai bộ chọn (Loại / Phạm vi), nút Cập nhật, và dải
/// công cụ tra cứu ngoài.
///
/// Tách khỏi `ReaderDefinitionOverlayView.swift` ở 1.3.334 để file đó **về dưới** baseline 468 dòng,
/// tạo chỗ cho hai hàng mới của Check rule. Không đổi một dòng logic nào khi di chuyển; các thành viên
/// phải là `internal` vì `private` trong Swift là phạm vi **file**.
extension ReaderDefinitionOverlayView {

    /// Bề ngang **cố định** của nút NE / VP / PN / R / C (mockup Pronoun khung 1 anh Bửu chọn: "nút loại còn khoảng
    /// 30 pt"). Cố định chứ không `minWidth` + `maxWidth: .infinity`: hai cụm cùng co giãn vô hạn thì HStack có thể chia
    /// đôi cho cụm aa…AA trước ⇒ cụm nút loại thiếu ~11 pt ở panel 329 pt (máy 375 pt) và hàng tràn; còn trần hữu hạn
    /// thì HStack trong chia cho cụm R | C trước ⇒ R / C rộng hơn NE / VP / PN. Cụm nút này cứng ⇒ đặt trước, cụm aa…AA
    /// nhận phần còn lại (~27 pt / nút ở 329 pt, giãn trên máy rộng).
    private static let segmentButtonWidth: CGFloat = 30

    internal var combinedFormattingAndPickersView: some View {
        HStack(spacing: 8) {
            // Cụm 1: Định dạng chữ (aa, Aa¹, Aa², Aa, AA)
            HStack(spacing: 2) {
                ForEach(["aa", "Aa¹", "Aa²", "Aa", "AA"], id: \.self) { format in
                    Button(action: {
                        customMeaning = onFormatMeaning(customMeaning, format)
                    }) {
                        Text(format)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 20)

            // Cụm 2: Phân loại & Phạm vi Từ điển
            HStack(spacing: 6) {
                // Loại (NE / VP / PN). PN (Pronouns) không ghim được — ghim mặc định chỉ NE hoặc VP.
                HStack(spacing: 0) {
                    dictSegmentButton(title: "NE", isSelected: saveTarget == .name, isPinned: pinnedSaveAsNameType == true) {
                        saveTarget = .name
                    } onPin: {
                        onPinNameType(true)
                    }

                    Divider()
                        .frame(height: 14)

                    dictSegmentButton(title: "VP", isSelected: saveTarget == .vietPhrase, isPinned: pinnedSaveAsNameType == false) {
                        saveTarget = .vietPhrase
                    } onPin: {
                        onPinNameType(false)
                    }

                    Divider()
                        .frame(height: 14)

                    dictSegmentButton(title: "PN", isSelected: saveTarget == .pronoun, isPinned: false) {
                        saveTarget = .pronoun
                    }
                    .accessibilityLabel("Pronoun")
                }
                .padding(2)
                // Nền bo góc thay cho `.cornerRadius` (cắt cả nhóm): ghim của nút nhô ra ngoài nhóm, không được bị cắt.
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                // Phạm vi (R vs C). PN chỉ có bản chung ⇒ cả cụm mờ, không bấm / không ghim được; `saveToBookSpecific`
                // giữ nguyên để chọn lại NE / VP thì R / C về như cũ.
                HStack(spacing: 0) {
                    dictSegmentButton(title: "R", isSelected: saveToBookSpecific == true, isPinned: pinnedSaveToBookSpecific == true) {
                        saveToBookSpecific = true
                    } onPin: {
                        onPinScope(true)
                    }

                    Divider()
                        .frame(height: 14)

                    dictSegmentButton(title: "C", isSelected: saveToBookSpecific == false, isPinned: pinnedSaveToBookSpecific == false) {
                        saveToBookSpecific = false
                    } onPin: {
                        onPinScope(false)
                    }
                }
                .padding(2)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .opacity(saveTarget.hasBookScope ? 1 : 0.35)
                .disabled(!saveTarget.hasBookScope)
                .allowsHitTesting(saveTarget.hasBookScope) // chặn cả cử chỉ nhấn giữ ghim, không chỉ nút
            }
        }
    }

    /// `onPin == nil` ⇒ nút không ghim được (PN): tắt riêng cử chỉ nhấn giữ — `including: .subviews` giữ cú chạm của
    /// `Button` (`.none` sẽ tắt luôn cả nút).
    @ViewBuilder
    internal func dictSegmentButton(
        title: String,
        isSelected: Bool,
        isPinned: Bool,
        onTap: @escaping () -> Void,
        onPin: (() -> Void)? = nil
    ) -> some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? selectedTheme.textColor : .secondary)
                .frame(width: Self.segmentButtonWidth)
                .padding(.vertical, 6)
                .background(isSelected ? Color.secondary.opacity(0.25) : Color.clear)
                .cornerRadius(6)
        }
        // Trạng thái ghim đọc qua giá trị của nút (badge ẩn khỏi trợ năng — không thành phần tử rời).
        .accessibilityValue(isPinned ? "Đang ghim mặc định" : "")
        // Ghim kiểu bìa Kệ ở góc trên phải, nhô ra ngoài nút; chữ luôn ở giữa. Nút thứ hai của cặp vẽ sau ⇒ nâng
        // `zIndex` để nền "đang chọn" của nó không phủ lên ghim của nút đầu.
        .overlay(alignment: .topTrailing) {
            if isPinned {
                CoverPinBadge(diameter: 15, angle: 20, accessibilityText: "Đang ghim mặc định")
                    .offset(x: 5, y: -7)
                    .accessibilityHidden(true)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard let onPin else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onPin()
            },
            including: onPin == nil ? .subviews : .all
        )
        .zIndex(isPinned ? 1 : 0)
    }

    internal var updateButtonView: some View {
        Button(action: onSaveDefinition) {
            HStack {
                Spacer()
                Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.16))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
        .disabled(isSaving || customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity((isSaving || customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
    }

    internal var quickLookupLinksView: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(searchEngines) { engine in
                        Button(action: {
                            onPerformQuickLookup(engine)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text(engine.name)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }
            }

            Button(action: onOpenSearchEngineConfig) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(8)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            .accessibilityLabel("Cấu hình công cụ tra cứu")
            .accessibilityHint("Nhấn hai lần để quản lý danh sách công cụ tìm kiếm")
        }
    }
}
