import SwiftUI
import UniformTypeIdentifiers

/// Màn "Cài đặt dịch thuật" (Cài đặt → Đọc & Nghe). Chuyển **nguyên văn** từ `SettingsView` (1.3.520):
/// section "Dịch Thuật Quick Translate", "Từ điển chung" và trình chọn file nhập từ điển — không đổi hành vi.
struct TranslationSettingsView: View {
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @AppStorage("isTranslationPronounsEnabled") private var isTranslationPronounsEnabled = false
    @AppStorage("isTranslationLuatNhanEnabled") private var isTranslationLuatNhanEnabled = false
    @ObservedObject private var translationManager = TranslationManager.shared

    @State private var showingFileImporter = false
    @State private var importType = "vietphrase"
    /// Tập "đang nhập" phải sống lâu hơn màn này (xem `TranslationImportState`); giữ tên `importingTypes` để
    /// phần code chuyển nguyên văn từ `SettingsView` không phải đổi.
    @ObservedObject private var importState = TranslationImportState.shared
    private var importingTypes: Set<String> {
        get { importState.importingTypes }
        nonmutating set { importState.importingTypes = newValue }
    }

    var body: some View {
        Form {
            Section(header: Text("Dịch Thuật Quick Translate")) {
                Toggle(isOn: $isTranslationEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bật dịch Quick Translate")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Tự động dịch siêu dữ liệu và nội dung truyện chữ tiếng Trung sang tiếng Việt (Hán-Việt/VietPhrase).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isTranslationEnabled) { _, newValue in
                    TranslateUtils.clearCache()
                    TranslationManager.shared.notifyRulesDidUpdate()
                }
                NavigationLink(destination: TOCRulesConfigView()) {
                    Label("Quản lý quy tắc TOC", systemImage: "list.bullet.indent")
                }
                .disabled(!importingTypes.isEmpty)
                NavigationLink(destination: JunkFilterManagementView()) {
                    Label("Quản lý lọc rác", systemImage: "trash.slash")
                }
                .disabled(!importingTypes.isEmpty)
                NavigationLink(destination: TranslationScopeManagementView()) {
                    Label("Cấu hình dịch theo Nguồn & Truyện", systemImage: "slider.horizontal.3")
                }
                .disabled(!importingTypes.isEmpty)
                QuickTranslateRuleSettingsRows(
                    isTranslationEnabled: isTranslationEnabled,
                    isBusy: !importingTypes.isEmpty
                )

                if isTranslationEnabled {
                    Toggle(isOn: $isTranslationPronounsEnabled) {
                        Text("Dịch Đại từ (Pronouns)")
                            .font(.subheadline)
                    }
                    .padding(.leading, 16)
                    .onChange(of: isTranslationPronounsEnabled) { _, _ in
                        TranslateUtils.clearCache()
                        TranslationManager.shared.notifyDictionariesDidUpdate()
                    }

                    Toggle(isOn: $isTranslationLuatNhanEnabled) {
                        Text("Dịch Luật nhân hóa")
                            .font(.subheadline)
                    }
                    .padding(.leading, 16)
                    .onChange(of: isTranslationLuatNhanEnabled) { _, _ in
                        TranslateUtils.clearCache()
                        TranslationManager.shared.notifyDictionariesDidUpdate()
                    }
                }
            }

            if isTranslationEnabled {
                Section(header: Text("Từ điển chung")) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            Button(action: {
                                importType = "vietphrase"
                                showingFileImporter = true
                            }) {
                                DictionaryCard(
                                    title: "VietPhrase.txt",
                                    statusText: getStatusText(for: "vietphrase"),
                                    isSet: translationManager.isVietPhraseLoaded,
                                    isLoading: importingTypes.contains("vietphrase")
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(importingTypes.contains("vietphrase"))

                            Button(action: {
                                importType = "names"
                                showingFileImporter = true
                            }) {
                                DictionaryCard(
                                    title: "Name.txt",
                                    statusText: getStatusText(for: "names"),
                                    isSet: translationManager.isNamesLoaded,
                                    isLoading: importingTypes.contains("names")
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(importingTypes.contains("names"))

                            Button(action: {
                                importType = "phienam"
                                showingFileImporter = true
                            }) {
                                DictionaryCard(
                                    title: "PhienAm.txt",
                                    statusText: getStatusText(for: "phienam"),
                                    isSet: translationManager.isPhienAmLoaded,
                                    isLoading: importingTypes.contains("phienam")
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(importingTypes.contains("phienam"))

                            Button(action: {
                                importType = "pronouns"
                                showingFileImporter = true
                            }) {
                                DictionaryCard(
                                    title: "Pronouns.txt",
                                    statusText: getStatusText(for: "pronouns"),
                                    isSet: translationManager.isPronounsLoaded,
                                    isLoading: importingTypes.contains("pronouns")
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(importingTypes.contains("pronouns"))

                            Button(action: {
                                importType = "luatnhan"
                                showingFileImporter = true
                            }) {
                                DictionaryCard(
                                    title: "LuatNhan.txt",
                                    statusText: getStatusText(for: "luatnhan"),
                                    isSet: translationManager.isLuatNhanLoaded,
                                    isLoading: importingTypes.contains("luatnhan")
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(importingTypes.contains("luatnhan"))
                        }
                        .padding(.vertical, 4)
                    }

                    if translationManager.isDownloading {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(translationManager.downloadMessage)
                                .font(.caption)
                            ProgressView(value: translationManager.downloadProgress)
                        }
                    } else if !translationManager.isDownloaded() {
                        // Đã có dữ liệu VietPhrase thì ẩn hẳn nút này: nút "Làm mới" bên dưới lo
                        // việc nạp lại, còn tải lại từ mạng chỉ có ích khi chưa có dữ liệu.
                        Button(action: {
                            Task {
                                await translationManager.downloadDefaultDictionaries()
                                await MainActor.run {
                                    DictionaryCache.shared.invalidateAll()
                                }
                            }
                        }) {
                            Label("Tải từ điển mặc định", systemImage: "arrow.down.circle")
                        }
                        .disabled(!importingTypes.isEmpty)
                    }

                    Button(action: {
                        importingTypes.insert("refresh")
                        Task {
                            do {
                                try await translationManager.loadAllDictionaries()
                                translationManager.clearBookDictCache()
                                TranslateUtils.clearCache()
                                await MainActor.run {
                                    DictionaryCache.shared.invalidateAll()
                                    importingTypes.remove("refresh")
                                    ToastManager.shared.show(message: "Đã làm mới dữ liệu dịch thành công", type: .success)
                                }
                            } catch {
                                await MainActor.run {
                                    importingTypes.remove("refresh")
                                    ToastManager.shared.show(message: "Lỗi làm mới dữ liệu dịch: \(error.localizedDescription)", type: .error)
                                }
                            }
                        }
                    }) {
                        HStack {
                            Label("Làm mới dữ liệu dịch", systemImage: "arrow.clockwise")
                            if importingTypes.contains("refresh") {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!importingTypes.isEmpty)

                    NavigationLink(destination: SearchEnginesConfigView()) {
                        Label("Cấu hình công cụ tra cứu", systemImage: "magnifyingglass")
                    }
                    .disabled(!importingTypes.isEmpty)
                }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .navigationTitle("Cài đặt dịch thuật")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            DocumentPickerPresenter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false,
                onPick: { urls in
                    guard let selectedUrl = urls.first else { return }
                    let accessing = selectedUrl.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            selectedUrl.stopAccessingSecurityScopedResource()
                        }
                    }

                    let currentType = importType
                    importingTypes.insert(currentType)

                    Task {
                        do {
                            try await translationManager.importDictionary(from: selectedUrl, type: currentType)
                            await MainActor.run {
                                // Invalidate DictionaryCache so it reloads from new .dat
                                if currentType == "vietphrase" {
                                    DictionaryCache.shared.invalidate(type: .vietPhrase)
                                } else if currentType == "names" {
                                    DictionaryCache.shared.invalidate(type: .names)
                                }
                                ToastManager.shared.show(message: "Nhập dữ liệu từ điển thành công!", type: .success)
                            }
                        } catch {
                            AppLogger.shared.log("❌ Lỗi import từ điển: \(error.localizedDescription)")
                            await MainActor.run {
                                ToastManager.shared.show(message: "Lỗi: \(error.localizedDescription)", type: .error)
                            }
                        }
                        _ = await MainActor.run {
                            importingTypes.remove(currentType)
                        }
                    }
                },
                onCancel: nil
            )
        )
    }

    private func getStatusText(for type: String) -> String {
        if importingTypes.contains(type) {
            return "Đang import..."
        }
        if let count = translationManager.getWordCount(for: type) {
            return "\(count) từ"
        }
        return "<Chưa thiết lập>"
    }
}
