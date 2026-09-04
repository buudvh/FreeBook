import SwiftUI

/// Ba hàng dưới của panel Dịch: cụm định dạng + hai bộ chọn (Loại / Phạm vi), nút Cập nhật, và dải
/// công cụ tra cứu ngoài.
///
/// Tách khỏi `ReaderDefinitionOverlayView.swift` ở 1.3.334 để file đó **về dưới** baseline 468 dòng,
/// tạo chỗ cho hai hàng mới của Check rule. Không đổi một dòng logic nào khi di chuyển; các thành viên
/// phải là `internal` vì `private` trong Swift là phạm vi **file**.
extension ReaderDefinitionOverlayView {

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
                // Loại (NE vs VP)
                HStack(spacing: 0) {
                    dictSegmentButton(title: "NE", isSelected: saveAsNameType == true, isPinned: pinnedSaveAsNameType == true) {
                        saveAsNameType = true
                    } onPin: {
                        onPinNameType(true)
                    }

                    Divider()
                        .frame(height: 14)

                    dictSegmentButton(title: "VP", isSelected: saveAsNameType == false, isPinned: pinnedSaveAsNameType == false) {
                        saveAsNameType = false
                    } onPin: {
                        onPinNameType(false)
                    }
                }
                .padding(2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)

                // Phạm vi (R vs C)
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
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    internal func dictSegmentButton(
        title: String,
        isSelected: Bool,
        isPinned: Bool,
        onTap: @escaping () -> Void,
        onPin: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(selectedTheme == .dark ? Color(red: 1.0, green: 0.8, blue: 0.3) : Color.orange)
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? selectedTheme.textColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.secondary.opacity(0.25) : Color.clear)
            .cornerRadius(6)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onPin()
            }
        )
    }

    internal var updateButtonView: some View {
        Button(action: onSaveDefinition) {
            HStack {
                Spacer()
                Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
