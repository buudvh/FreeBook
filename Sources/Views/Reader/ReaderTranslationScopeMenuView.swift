import SwiftUI

/// Menu xổ xuống điều khiển cấu hình dịch thuật 3 mức: Truyện này > Nguồn này > Toàn cục.
public struct ReaderTranslationScopeMenuView: View {
    public let bookId: String
    public let packageId: String
    public let sourceName: String
    public let textColor: Color?
    public let showBackground: Bool

    @State private var status: TranslationConfigStore.ResolvedStatus

    public init(
        bookId: String,
        packageId: String = "",
        sourceName: String = "",
        textColor: Color? = nil,
        showBackground: Bool = true
    ) {
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.textColor = textColor
        self.showBackground = showBackground
        _status = State(initialValue: TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId))
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
        Menu {
            // Phần 1: Tóm tắt trạng thái hiện tại
            Section {
                Label(
                    status.isEnabled ? "Đang BẬT dịch (\(status.origin.rawValue))" : "Đang TẮT dịch (\(status.origin.rawValue))",
                    systemImage: status.isEnabled ? "character.bubble.fill" : "character.bubble"
                )
            }

            // Phần 2: Cấu hình cho Truyện này
            Section("Truyện này") {
                Button {
                    TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .inherited)
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Theo nguồn (Mặc định)")
                        if status.bookOverride == .inherited {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .enabled)
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Luôn Bật cho truyện này")
                        if status.bookOverride == .enabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .disabled)
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Luôn Tắt cho truyện này")
                        if status.bookOverride == .disabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            // Phần 3: Cấu hình cho Nguồn này
            Section("Nguồn: \(displaySourceName)") {
                Button {
                    TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: .inherited)
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Theo toàn cục (Mặc định)")
                        if status.sourceOverride == .inherited {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: .enabled)
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Luôn Bật cho nguồn này")
                        if status.sourceOverride == .enabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: .disabled)
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Luôn Tắt cho nguồn này")
                        if status.sourceOverride == .disabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            // Phần 4: Cấu hình Toàn cục
            Section("Toàn cục (Tất cả truyện)") {
                Button {
                    TranslationConfigStore.shared.globalEnabled = true
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Bật mặc định toàn cục")
                        if status.globalEnabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    TranslationConfigStore.shared.globalEnabled = false
                    refreshStatus()
                } label: {
                    HStack {
                        Text("Tắt mặc định toàn cục")
                        if !status.globalEnabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: status.isEnabled ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(status.isEnabled ? .blue : (textColor?.opacity(0.85) ?? .secondary))
                    .frame(width: 44, height: 52)
                    .background(
                        showBackground ? (textColor?.opacity(0.07) ?? Color(UIColor.systemGray6)) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )

                // Dấu chấm nhỏ chỉ thị truyện này đang có cấu hình riêng biệt
                if status.bookOverride != .inherited {
                    Circle()
                        .fill(status.bookOverride == .enabled ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                        .padding(.top, 8)
                        .padding(.trailing, 6)
                }
            }
        }
        .onAppear {
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationConfigStore.didChangeNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        status = TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId)
    }
}
