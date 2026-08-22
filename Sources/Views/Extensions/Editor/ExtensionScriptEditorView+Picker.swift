import SwiftUI

/// Sheet chọn file script + bộ lọc tìm kiếm, tách khỏi `ExtensionScriptEditorView` để file gốc
/// (đang vượt baseline dòng) chỉ giảm đi.
extension ExtensionScriptEditorView {
    internal var filteredScriptFiles: [ScriptFileInfo] {
        let trimmed = scriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return scriptFiles }
        return scriptFiles.filter { file in
            file.fileName.lowercased().contains(trimmed) || file.displayName.lowercased().contains(trimmed)
        }
    }

    internal var scriptPickerSheetView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm kiếm script (ví dụ: search, libs, json)...", text: $scriptSearchText)
                        .textFieldStyle(.plain)
                    if !scriptSearchText.isEmpty {
                        Button(action: { scriptSearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemFill))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                if filteredScriptFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Không tìm thấy script phù hợp với '\(scriptSearchText)'")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    pickerList
                }
            }
            .navigationTitle("Chọn Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") {
                        showingScriptPickerSheet = false
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var pickerList: some View {
        List {
            ForEach(filteredScriptFiles) { file in
                let isSelected = file.id == selectedScriptId
                let isModified = (isSelected && hasUnsavedChanges) || modifiedFileIds.contains(file.id)

                Button(action: {
                    switchScript(to: file)
                    showingScriptPickerSheet = false
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: file.isPluginJson ? "gearshape.doc.fill" : "curlybraces")
                            .font(.system(size: 16))
                            .foregroundColor(file.isPluginJson ? .orange : (isSelected ? .accentColor : .secondary))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(file.displayName)
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(.primary)

                                if isModified {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                }
                            }

                            if file.fileName != file.displayName {
                                Text(file.fileName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
}
