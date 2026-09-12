import SwiftUI

/// Cấu hình lượt kiểm tra chương mới tự động.
///
/// Mọi giá trị đọc/ghi trực tiếp qua `@AppStorage` với **đúng các khoá** của
/// [`NewChapterCheckPolicy`](../../../Services/NewChapters/NewChapterCheckPolicy.swift) — policy vẫn là
/// nơi duy nhất kẹp biên và quyết định "có được kiểm tra lúc này không".
struct NewChapterSettingsView: View {
    @AppStorage(NewChapterCheckPolicy.enabledKey) private var isEnabled = true
    @AppStorage(NewChapterCheckPolicy.modeKey) private var modeRaw = NewChapterCheckPolicy.Mode.cooldown.rawValue
    @AppStorage(NewChapterCheckPolicy.cooldownHoursKey) private var cooldownHours = 6
    @AppStorage(NewChapterCheckPolicy.dailyHourKey) private var dailyHour = 8

    @ObservedObject private var newChapters = NewChapterInboxManager.shared

    private var mode: NewChapterCheckPolicy.Mode {
        NewChapterCheckPolicy.Mode(rawValue: modeRaw) ?? .cooldown
    }

    var body: some View {
        Form {
            Section {
                Toggle("Tự động kiểm tra chương mới", isOn: $isEnabled)
            } footer: {
                Text("Lượt kiểm tra chạy sau khi Kệ sách đã hiện, chỉ tải mục lục và không tải nội dung chương. Tắt mục này thì vẫn kiểm tra được bằng tay từ menu Kệ sách.")
            }

            if isEnabled {
                Section(header: Text("Thời điểm kiểm tra")) {
                    Picker("Chế độ", selection: $modeRaw) {
                        ForEach(NewChapterCheckPolicy.Mode.allCases, id: \.rawValue) { item in
                            Text(item.displayName).tag(item.rawValue)
                        }
                    }

                    switch mode {
                    case .cooldown:
                        Stepper(value: $cooldownHours, in: 1...48) {
                            Text("Cách nhau \(cooldownHours) giờ")
                        }
                    case .daily:
                        Picker("Sau giờ", selection: $dailyHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Trạng thái")) {
                LabeledContent("Truyện có chương mới", value: "\(newChapters.totalNewBooks)")
                LabeledContent(
                    "Lần kiểm tra gần nhất",
                    value: NewChapterCheckPolicy.lastBatchAt.map { formatted($0) } ?? "Chưa kiểm tra"
                )
                if newChapters.isChecking {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang kiểm tra \(newChapters.checkProgress)")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Text("Mỗi lượt tự động kiểm tra tối đa \(NewChapterCheckPolicy.maxBooksPerBatch) truyện, ưu tiên truyện đọc gần đây nhất. Truyện có mục lục phân trang quá \(NewChapterCheckPolicy.maxTOCPagesPerCheck) trang chỉ được lấy trang cuối, nên badge hiện dấu chấm thay vì số chương.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Kiểm tra chương mới")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }
}
