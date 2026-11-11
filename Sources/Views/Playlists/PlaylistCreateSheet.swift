import SwiftUI

/// Sheet "Playlist mới" của nút "+" nổi ở tab Playlist: nhập tên + chọn loại (Nhạc / Video; mặc định theo chip đang chọn).
/// "Tạo" ở header; không có nút chỉ để đóng — vuốt xuống, đã gõ tên thì hỏi bỏ (`confirmDiscardOnSwipe`).
struct PlaylistCreateSheet: View {
    /// Chạy sau khi tạo xong (tab chuyển chip sang loại vừa tạo).
    let onCreated: (Playlist) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: PlaylistKind
    @FocusState private var isNameFocused: Bool

    init(initialKind: PlaylistKind, onCreated: @escaping (Playlist) -> Void = { _ in }) {
        self.onCreated = onCreated
        _kind = State(initialValue: initialKind)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section("Tên") {
                    TextField("Tên playlist", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(create)
                }
                Section("Loại") {
                    Picker("Loại", selection: $kind) {
                        ForEach(PlaylistKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }.glassSheetRows() }
            .pageTitle("Playlist mới")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tạo", action: create)
                        .headerTextButton()
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .confirmDiscardOnSwipe(isDirty: !trimmedName.isEmpty)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        switch PlaylistCoordinator.shared.create(name: name, kind: kind) {
        case .success(let playlist):
            ToastManager.shared.show(message: "Đã tạo playlist \(playlist.name)", type: .success)
            onCreated(playlist)
            dismiss()
        case .failure(let error):
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }
}
