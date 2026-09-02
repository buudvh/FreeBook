import SwiftUI

/// Hub ba từ điển **tham chiếu**: phiên âm, đại từ, luật nhân.
///
/// Tách khỏi `DictionaryHubView` vì ba bộ này không có bản riêng theo truyện và không đi qua đường CRUD
/// một-từ của VietPhrase/Names — xem `ReferenceDictionaryReader`. Nếu nhồi chúng vào `DictType` thì 17
/// điểm `switch` trong module (trong đó có token của rule dịch nhanh) phải xử lý hai case vô nghĩa.
struct ReferenceDictionaryHubView: View {
    @ObservedObject private var translationManager = TranslationManager.shared

    var body: some View {
        List {
            Section {
                ForEach(ReferenceDictionaryReader.Kind.allCases) { kind in
                    NavigationLink(destination: ReferenceDictionaryListView(kind: kind)) {
                        HStack(spacing: 12) {
                            Image(systemName: kind.icon)
                                .foregroundStyle(.teal)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(subtitle(for: kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Ba bộ này là dữ liệu tham chiếu dùng chung, không có bản riêng theo truyện. Sửa nội dung của chúng cần thay file trong thư mục dịch — danh sách ở đây để tra và kiểm tra.")
            }
        }
        .navigationTitle("Từ điển tham chiếu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subtitle(for kind: ReferenceDictionaryReader.Kind) -> String {
        let count = kind.loadedCount
        guard count > 0 else { return "Chưa nạp" }
        return "\(count) mục đã nạp"
    }
}
