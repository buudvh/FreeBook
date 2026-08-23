import SwiftUI

/// Ba picker của `BookImportConfirmationSheet`: bảng mã, quy tắc TOC, cách tách chương.
///
/// Tách khỏi file gốc để nó ở dưới ngưỡng 400 dòng khi thêm picker "Cấu trúc". Vì `private` của Swift
/// là phạm vi **file**, mọi state mà các picker này đọc/ghi (`decodeID`, `selectedRuleIDs`,
/// `selectedStructure`, `activePicker`, `autoDecodeID`, `matchedRuleIDs`, `isReanalyzing`) đều khai
/// `internal` ở file gốc.
extension BookImportConfirmationSheet {
    // MARK: - Decode picker

    internal var decodePickerView: some View {
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

    internal var rulePickerView: some View {
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

    // MARK: - Structure picker

    /// Chọn cách tách chương. `auto` để parser tự chọn theo độ tin cậy; ba giá trị còn lại là ép — hữu
    /// ích khi mục lục nhúng trong file bị rút gọn hoặc lệch so với nội dung thật.
    internal var structurePickerView: some View {
        NavigationStack {
            List {
                Section("Cách tách chương") {
                    ForEach(BookImportService.StructureMode.allCases) { mode in
                        Button {
                            selectedStructure = mode
                            activePicker = nil
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .foregroundColor(.primary)
                                    Text(structureHint(mode))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                if selectedStructure == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("Chỉ EPUB có mục lục và thứ tự file thật; TXT luôn tách bằng quy tắc TOC.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Chọn cấu trúc")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func structureHint(_ mode: BookImportService.StructureMode) -> String {
        switch mode {
        case .auto:
            return "Mục lục nhúng → thứ tự file → quy tắc TOC"
        case .tocIndex:
            return "Dùng mục lục nhúng trong file (NCX/nav của EPUB)"
        case .spine:
            return "Mỗi file nội dung trong sách là một chương"
        case .tocRules:
            return "Tách bằng regex quy tắc TOC như file TXT"
        }
    }
}
