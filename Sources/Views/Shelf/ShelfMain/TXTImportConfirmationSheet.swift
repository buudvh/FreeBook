import SwiftUI

/// Sheet xác nhận thông tin trước khi nhập truyện TXT vào CSDL.
/// Hiển thị tên truyện, số chương, tên file và danh sách chương rút gọn để người
/// dùng kiểm tra kết quả parse. Cho phép chọn bảng mã giải mã và quy tắc TOC
/// (mặc định Tự động) rồi "Phân tích lại" để làm mới danh sách chương.
struct TXTImportConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum PickerType: String, Identifiable {
        case decode
        case rules
        var id: String { rawValue }
    }

    let fileName: String

    // Dữ liệu ban đầu (từ lần parse tự động đầu tiên)
    @State private var parsed: ParsedBook
    @State private var autoDecodeID: String?
    @State private var matchedRuleIDs: Set<String>

    // Lựa chọn hiện tại: nil / rỗng = Tự động
    @State private var decodeID: String? = nil
    @State private var selectedRuleIDs: Set<String> = []

    @State private var isReanalyzing = false
    @State private var activePicker: PickerType? = nil

    let onReanalyze: (String?, Set<String>) async -> TXTReanalysisResult?
    let onCancel: () -> Void
    let onConfirm: (ParsedBook) -> Void

    init(
        fileName: String,
        initialParsed: ParsedBook,
        autoDecodeID: String?,
        matchedRuleIDs: Set<String>,
        onReanalyze: @escaping (String?, Set<String>) async -> TXTReanalysisResult?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (ParsedBook) -> Void
    ) {
        self.fileName = fileName
        _parsed = State(initialValue: initialParsed)
        _autoDecodeID = State(initialValue: autoDecodeID)
        _matchedRuleIDs = State(initialValue: matchedRuleIDs)
        self.onReanalyze = onReanalyze
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    private var decodeLabel: String {
        if let decodeID, let option = TextEncodingOption(rawValue: decodeID) {
            return option.displayName
        }
        return "Tự động"
    }

    private var ruleLabel: String {
        if selectedRuleIDs.isEmpty {
            return "Tự động"
        }
        return "\(selectedRuleIDs.count) quy tắc"
    }

    private var previewChapterIndices: [Int] {
        let count = parsed.chapters.count
        guard count > 6 else { return Array(parsed.chapters.indices) }
        return Array(0..<3) + Array((count - 3)..<count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title2)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(parsed.title)
                                    .font(.headline)
                                    .lineLimit(3)

                                Text("\(parsed.chapters.count) chương")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("File: \(fileName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Divider()

                        // Hàng chọn bảng mã + quy tắc TOC + nút phân tích lại
                        VStack(spacing: 10) {
                            Button {
                                activePicker = .decode
                            } label: {
                                HStack {
                                    Label("Bảng mã", systemImage: "textformat")
                                    Spacer()
                                    Text(decodeLabel)
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                activePicker = .rules
                            } label: {
                                HStack {
                                    Label("Quy tắc TOC", systemImage: "list.number")
                                    Spacer()
                                    Text(ruleLabel)
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await reanalyze()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isReanalyzing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                    }
                                    Text(isReanalyzing ? "Đang phân tích lại..." : "Phân tích lại")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isReanalyzing)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Danh sách chương")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            ForEach(previewChapterIndices, id: \.self) { index in
                                if parsed.chapters.count > 6 && index == parsed.chapters.count - 3 {
                                    Text("… \(parsed.chapters.count - 6) chương ở giữa …")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 2)
                                }

                                let chapter = parsed.chapters[index]
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 32, alignment: .trailing)

                                    Text(chapter.title)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(16)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("Hủy")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isReanalyzing)

                    Button(action: {
                        onConfirm(parsed)
                        dismiss()
                    }) {
                        Text("Nhập")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isReanalyzing)
                }
                .padding(16)
            }
            .navigationTitle("Xác nhận nhập truyện")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $activePicker) { picker in
                switch picker {
                case .decode:
                    decodePickerView
                case .rules:
                    rulePickerView
                }
            }
        }
    }

    private func reanalyze() async {
        guard !isReanalyzing else { return }
        isReanalyzing = true
        defer { isReanalyzing = false }

        if let result = await onReanalyze(decodeID, selectedRuleIDs) {
            parsed = result.parsed
            autoDecodeID = result.autoDecodeID
            matchedRuleIDs = result.matchedRuleIDs
        }
    }

    // MARK: - Decode picker

    private var decodePickerView: some View {
        NavigationStack {
            List {
                Section("Tự động") {
                    Button {
                        decodeID = nil
                        activePicker = nil
                    } label: {
                        HStack {
                            Label("Tự động (phát hiện tự động)", systemImage: "wand.and.stars")
                                .foregroundColor(.primary)
                            Spacer()
                            if decodeID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                Section("Bảng mã") {
                    ForEach(TextEncodingOption.allCases) { option in
                        Button {
                            decodeID = option.rawValue
                            activePicker = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .foregroundColor(.primary)
                                    if autoDecodeID == option.rawValue {
                                        Text("Bảng mã đang hoạt động với file")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                Spacer()
                                if autoDecodeID == option.rawValue {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                if decodeID == option.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chọn bảng mã")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - TOC rule picker

    private var rulePickerView: some View {
        NavigationStack {
            List {
                Section("Tự động") {
                    Button {
                        selectedRuleIDs = []
                        activePicker = nil
                    } label: {
                        HStack {
                            Label("Tự động (dùng quy tắc đang bật)", systemImage: "wand.and.stars")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedRuleIDs.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                let allRules = TranslateUtils.getAllTOCRules()
                Section("Quy tắc (tích chọn nhiều)") {
                    ForEach(allRules) { rule in
                        let isSelected = selectedRuleIDs.contains(rule.id)
                        Button {
                            if isSelected {
                                selectedRuleIDs.remove(rule.id)
                            } else {
                                selectedRuleIDs.insert(rule.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isSelected ? .blue : .secondary)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    if let example = rule.example {
                                        Text("Ví dụ: \(example)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if matchedRuleIDs.contains(rule.id) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Áp dụng") {
                        activePicker = nil
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isReanalyzing)
                }
            }
            .navigationTitle("Chọn quy tắc TOC")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
