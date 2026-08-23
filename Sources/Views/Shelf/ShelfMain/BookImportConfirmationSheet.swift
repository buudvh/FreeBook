import SwiftUI

/// Sheet xác nhận thông tin trước khi nhập truyện từ file vào CSDL
/// (TXT / HTML / EPUB / MOBI–AZW3 / PRC / DOCX / FB2 / PDF).
/// Hiển thị tên truyện, số chương **sau cùng**, tên file, cách tách chương đã dùng, báo cáo chương quá
/// dài đã bị `ChapterLengthLimiter` tách, cảnh báo mất mát nội dung (nếu có) và danh sách chương rút
/// gọn để người dùng kiểm tra kết quả parse. Cho phép chọn bảng mã, quy tắc TOC và cách tách chương
/// (mặc định Tự động) rồi "Phân tích lại" để làm mới danh sách chương.
///
/// Khi parser trả `warningNote` (PDF hỗn hợp: một phần trang là ảnh scan) thì nút "Nhập" bị chặn cho
/// tới khi người dùng tự tick chấp nhận — đúng yêu cầu "xác nhận trước khi nhập phần còn lại".
///
/// Ba picker nằm ở `Extensions/BookImportConfirmationSheet+Pickers.swift`; vì `private` của Swift là
/// phạm vi **file** nên các `@State` dưới đây phải là `internal`.
struct BookImportConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    internal enum PickerType: String, Identifiable {
        case decode
        case rules
        case structure
        var id: String { rawValue }
    }

    let fileName: String
    let format: BookImportFormat

    // Dữ liệu ban đầu (từ lần parse tự động đầu tiên)
    @State internal var parsed: ParsedBook
    @State internal var autoDecodeID: String?
    @State internal var matchedRuleIDs: Set<String>

    // Lựa chọn hiện tại: nil / rỗng = Tự động
    @State internal var decodeID: String? = nil
    @State internal var selectedRuleIDs: Set<String> = []
    @State internal var selectedStructure: BookImportService.StructureMode = .auto

    @State internal var isReanalyzing = false
    @State internal var activePicker: PickerType? = nil
    /// Người dùng đã tự chấp nhận `parsed.warningNote` (PDF hỗn hợp thiếu lớp văn bản ở một số trang).
    @State internal var acknowledgedWarning = false

    let onReanalyze: (String?, Set<String>, BookImportService.StructureMode) async -> BookImportService.Result?
    let onCancel: () -> Void
    let onConfirm: (ParsedBook) -> Void

    init(
        fileName: String,
        format: BookImportFormat,
        initialParsed: ParsedBook,
        autoDecodeID: String?,
        matchedRuleIDs: Set<String>,
        onReanalyze: @escaping (String?, Set<String>, BookImportService.StructureMode) async -> BookImportService.Result?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (ParsedBook) -> Void
    ) {
        self.fileName = fileName
        self.format = format
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

    /// EPUB/DOCX/FB2 tự khai bảng mã trong file (XML luôn UTF-8 trên thực tế) và PDF do PDFKit tự
    /// giải mã, nên hàng "Bảng mã" là lựa chọn vô nghĩa, ẩn đi.
    private var showsDecodeRow: Bool {
        switch format {
        case .epub, .docx, .fb2, .pdf: return false
        case .txt, .html, .mobi: return true
        }
    }

    /// Nhập được hay chưa: cảnh báo mất mát nội dung (PDF hỗn hợp) phải được người dùng chấp nhận trước.
    private var canConfirm: Bool {
        guard let warning = parsed.warningNote, !warning.isEmpty else { return true }
        return acknowledgedWarning
    }

    /// Báo cáo của bước hậu xử lý chung: chương dài bất thường đã bị tách thành nhiều phần.
    private var splitReport: String? {
        return ChapterLengthLimiter.report(for: parsed.chapters)
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

                                Text("\(format.displayName) • \(parsed.chapters.count) chương")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("File: \(fileName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)

                            if let note = parsed.structureNote, !note.isEmpty {
                                Text("Cách tách: \(note)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            if let splitReport {
                                Text(splitReport)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .lineLimit(2)
                            }
                        }

                        if let warning = parsed.warningNote, !warning.isEmpty {
                            warningSection(warning)
                        }

                        Divider()

                        optionRows

                        Divider()

                        chapterListView
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
                    .disabled(isReanalyzing || !canConfirm)
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
                case .structure:
                    structurePickerView
                }
            }
        }
    }

    // Hàng chọn bảng mã + quy tắc TOC + cách tách chương + nút phân tích lại
    private var optionRows: some View {
        VStack(spacing: 10) {
            if showsDecodeRow {
                Button {
                    activePicker = .decode
                } label: {
                    pickerRowLabel(
                        title: "Bảng mã",
                        systemImage: "textformat",
                        value: decodeLabel
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                activePicker = .rules
            } label: {
                pickerRowLabel(
                    title: "Quy tắc TOC",
                    systemImage: "list.number",
                    value: ruleLabel
                )
            }
            .buttonStyle(.plain)

            Button {
                activePicker = .structure
            } label: {
                pickerRowLabel(
                    title: "Cấu trúc",
                    systemImage: "list.bullet.indent",
                    value: selectedStructure.displayName
                )
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
    }

    /// Cảnh báo mất mát nội dung + ô người dùng tự chấp nhận. Chỉ hiện khi parser có `warningNote`
    /// (hiện là PDF hỗn hợp), nên các format khác không thấy gì thêm.
    private func warningSection(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("Tôi hiểu, chỉ nhập phần có văn bản", isOn: $acknowledgedWarning)
                .font(.caption)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    private func pickerRowLabel(title: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var chapterListView: some View {
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
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 56, alignment: .trailing)

                    Text(chapter.title)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func reanalyze() async {
        guard !isReanalyzing else { return }
        isReanalyzing = true
        defer { isReanalyzing = false }

        if let result = await onReanalyze(decodeID, selectedRuleIDs, selectedStructure) {
            parsed = result.parsed
            autoDecodeID = result.autoDecodeID
            matchedRuleIDs = result.matchedRuleIDs
        }
    }
}
