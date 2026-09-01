import SwiftUI

public struct FilterSheet: View {
    @Environment(\.dismiss) internal var dismiss
    public let allAuthors: [String]
    public let allLocales: [String]
    public let allTypes: [String]

    @Binding public var filterType: String
    @Binding public var filterLocale: String
    @Binding public var filterAuthor: String

    public init(
        allAuthors: [String],
        allLocales: [String],
        allTypes: [String],
        filterType: Binding<String>,
        filterLocale: Binding<String>,
        filterAuthor: Binding<String>
    ) {
        self.allAuthors = allAuthors
        self.allLocales = allLocales
        self.allTypes = allTypes
        self._filterType = filterType
        self._filterLocale = filterLocale
        self._filterAuthor = filterAuthor
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Loại tiện ích")) {
                    Picker("Loại", selection: $filterType) {
                        Text("Tất cả").tag("all")
                        ForEach(allTypes, id: \.self) { type in
                            Text(translateType(type)).tag(type)
                        }
                    }
                }

                Section(header: Text("Ngôn ngữ")) {
                    Picker("Ngôn ngữ", selection: $filterLocale) {
                        Text("Tất cả").tag("all")
                        ForEach(allLocales, id: \.self) { locale in
                            Text(translateLocale(locale)).tag(locale)
                        }
                    }
                }

                Section(header: Text("Tác giả")) {
                    Picker("Tác giả", selection: $filterAuthor) {
                        Text("Tất cả").tag("all")
                        ForEach(allAuthors, id: \.self) { author in
                            Text(author).tag(author)
                        }
                    }
                }
            }
            .navigationTitle("Bộ lọc tiện ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đặt lại") {
                        filterType = "all"
                        filterLocale = "all"
                        filterAuthor = "all"
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    internal func translateType(_ type: String) -> String {
        switch type {
        case ExtensionType.novel: return "Truyện chữ (Novel)"
        case ExtensionType.chineseNovel: return "Truyện Trung Quốc (Chinese)"
        case ExtensionType.tts: return "Giọng đọc (TTS)"
        case ExtensionType.legado: return "Nguồn Legado (JSON)"
        default: return type.capitalized
        }
    }

    internal func translateLocale(_ locale: String) -> String {
        switch locale {
        case "vi_VN": return "Tiếng Việt"
        case "zh_CN": return "Tiếng Trung"
        case "en_US": return "Tiếng Anh"
        default: return locale
        }
    }
}
