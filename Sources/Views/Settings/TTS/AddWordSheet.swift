import SwiftUI

/// Sheet **thêm một mục từ điển phiên âm** (từ gốc → cách đọc tiếng Việt). Mở từ màn từ điển TTS và từ
/// menu bôi đen của Reader.
///
/// Gợi ý phiên âm được dựng **ngoài main thread**. Trước 1.3.336 `suggestions` là computed property đọc
/// ngay trong `body`, mà đường dựng gợi ý gọi `EnglishPhonemeTransliterator` →
/// `EspeakPhonemizer.phonemizeEnglish`: hàm C đồng bộ, giữ **một `NSLock` dùng chung với đường tổng hợp
/// NghiTTS**, và lần gọi đầu còn chạy `espeak_Initialize` (có nhánh dự phòng quét đệ quy bundle). Hệ
/// quả: mở sheet lúc đang nghe TTS là đóng băng UI cho tới khi lượt đọc hiện tại nhả lock, và mỗi lượt
/// vẽ lại lặp đúng việc đó. Nay việc nặng nằm trong `Task.detached`, `body` chỉ đọc `@State`.
///
/// Tách khỏi `TTSDictionaryEditView.swift` cùng lượt: file đó đang **vượt** baseline dòng của
/// `check_architecture.py` và baseline chỉ được phép giảm.
struct AddWordSheet: View {
    /// Đích lưu của sheet.
    ///
    /// `chooseAtSave` = mở từ **Reader**: nút "Lưu" là `Menu` **2 mục** (đúng khuôn
    /// `AddTTSReplacementSheet.swift:108-115`). Hai case còn lại là **đích cố định** — màn sửa từ điển của
    /// từng engine — nên nút Lưu vẫn là `Button` như cũ.
    enum Target: Equatable {
        case nghiTTS
        case vieNeu
        case chooseAtSave
    }

    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var value = ""
    @State private var validationError: String? = nil
    /// Kết quả dựng gợi ý gần nhất. `body` **chỉ** đọc biến này, không tự tính lại.
    @State private var suggestions: [TTSPhoneticSuggestion] = []
    @State private var isBuildingSuggestions = false
    @State private var suggestionLoadTask: Task<Void, Never>? = nil

    let onAdd: (String, String, Target) -> Void
    let showSuggestions: Bool
    let target: Target

    init(
        initialKey: String = "",
        showSuggestions: Bool = false,
        target: Target = .nghiTTS,
        onAdd: @escaping (String, String, Target) -> Void
    ) {
        self.onAdd = onAdd
        self.showSuggestions = showSuggestions
        self.target = target
        _key = State(initialValue: initialKey)
        _value = State(initialValue: "")
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedKey.isEmpty && !value.trimmed.isEmpty && validationError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin từ mới") {
                    TextField("Từ gốc (tiếng Anh/Nhật, e.g. apple)", text: $key)
                        .textInputAutocapitalization(.never)
                        .onChange(of: key) { _, newValue in
                            validateKey(newValue)
                            scheduleSuggestionLoad()
                        }

                    TextField("Phiên âm tiếng Việt (e.g. ép pô)", text: $value)
                }

                if showSuggestions {
                    suggestionSection
                }

                if let validationError = validationError {
                    Section {
                        Text(validationError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Thêm từ mới")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Lượt đầu **không** chờ debounce: khoá đã có sẵn từ cụm bôi đen ở Reader.
                scheduleSuggestionLoad(immediately: true)
            }
            .onDisappear {
                suggestionLoadTask?.cancel()
                suggestionLoadTask = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if target == .chooseAtSave {
                        // Menu 2 mục, đúng khuôn `AddTTSReplacementSheet` ("Lưu riêng" / "Lưu chung").
                        Menu("Lưu") {
                            Button("Lưu vào NghiTTS") { save(.nghiTTS) }
                            Button("Lưu vào VieNeu-TTS") { save(.vieNeu) }
                        }
                        .disabled(!canSave)
                    } else {
                        Button("Lưu") { save(target) }
                            .disabled(!canSave)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionSection: some View {
        if isBuildingSuggestions && suggestions.isEmpty {
            Section("Gợi ý phiên âm") {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang dựng gợi ý…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if !suggestions.isEmpty {
            Section("Gợi ý phiên âm") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            suggestionChip(suggestion)
                        }
                    }
                }
            }
        }
    }

    private func suggestionChip(_ suggestion: TTSPhoneticSuggestion) -> some View {
        Button(action: {
            value = suggestion.text
        }) {
            HStack(spacing: 6) {
                Text(suggestion.origin.badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(suggestion.origin.tint.opacity(0.18))
                    .foregroundColor(suggestion.origin.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(suggestion.text)
                    .font(.subheadline)
                    .foregroundColor(suggestion.isPipelineChoice ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    suggestion.isPipelineChoice
                        ? suggestion.origin.tint.opacity(0.5)
                        : Color.gray.opacity(0.3),
                    lineWidth: suggestion.isPipelineChoice ? 1.5 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.text). \(suggestion.origin.explanation)")
    }

    private func validateKey(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" ") {
            validationError = "Từ gốc không được chứa khoảng trắng"
        } else if trimmed.rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil {
            validationError = "Từ gốc không được chứa dấu câu"
        } else {
            validationError = nil
        }
    }

    /// Một task cho một lượt: tra từ điển (actor) rồi dựng gợi ý (espeak, đồng bộ) — **cả hai** đều nằm
    /// ngoài main thread. `Task.detached` chứ không phải `Task`: `Task` thừa hưởng actor của chỗ tạo
    /// (`@MainActor`) nên vẫn chạy espeak trên main thread, đúng thứ đang phải chữa.
    private func scheduleSuggestionLoad(immediately: Bool = false) {
        guard showSuggestions else { return }
        suggestionLoadTask?.cancel()

        // Tra bằng khoá **đã gấp dấu phụ**, giống `transliterateToken` lúc đọc; hạ chữ thường một mình
        // là chưa đủ nên trước đây khoá có dấu không bao giờ khớp.
        let word = trimmedKey
        guard !word.isEmpty else {
            suggestions = []
            isBuildingSuggestions = false
            suggestionLoadTask = nil
            return
        }

        isBuildingSuggestions = true
        suggestionLoadTask = Task { @MainActor in
            if !immediately {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }

            let lookupKey = TTSPhoneticSuggestionBuilder.normalizedKey(word)
            let libraryHit = await Self.libraryHit(for: lookupKey, target: target)
            guard !Task.isCancelled else { return }

            // Đích VieNeu **không** có nhánh tiếng Anh/IPA ⇒ bỏ hẳn chip EN (và bỏ luôn lượt espeak).
            let includeEnglish = target != .vieNeu
            let built = await Task.detached(priority: .userInitiated) {
                TTSPhoneticSuggestionBuilder.suggestions(
                    for: word,
                    libraryHit: libraryHit,
                    includeEnglish: includeEnglish
                )
            }.value
            guard !Task.isCancelled else { return }

            suggestions = built
            isBuildingSuggestions = false
        }
    }

    private func save(_ destination: Target) {
        onAdd(key, value, destination)
        dismiss()
    }

    /// Tra từ điển của **đích**. Đích cố định thì tra đúng từ điển đó; `chooseAtSave` thì tra VieNeu trước
    /// rồi tới NghiTTS — hai từ điển **độc lập** nên một khoá thường chỉ có ở một bên, tra cả hai chỉ để
    /// chip gợi ý hiện được dù người dùng chưa chọn đích.
    private static func libraryHit(for lookupKey: String, target: Target) async -> String? {
        guard !lookupKey.isEmpty else { return nil }
        switch target {
        case .nghiTTS:
            return await TextPreprocessor.shared.lookupWord(lookupKey)
        case .vieNeu:
            return await VieNeuJapaneseDictionary.shared.lookup(lookupKey)
        case .chooseAtSave:
            if let hit = await VieNeuJapaneseDictionary.shared.lookup(lookupKey) { return hit }
            return await TextPreprocessor.shared.lookupWord(lookupKey)
        }
    }
}
