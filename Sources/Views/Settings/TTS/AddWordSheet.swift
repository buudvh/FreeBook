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
/// Từ 1.3.462 sheet tra **cả hai** từ điển phiên âm (NghiTTS + VieNeu) chứ không chỉ từ điển của đích, và
/// cho **nhấn giữ chip NGI/VIE để xoá mục** khỏi đúng từ điển đó. Hai từ điển độc lập nên cùng một cách
/// đọc vẫn hiện **hai** chip để người dùng biết mục nằm ở đâu.
///
/// Tách khỏi `TTSDictionaryEditView.swift` cùng lượt: file đó đang **vượt** baseline dòng của
/// `check_architecture.py` và baseline chỉ được phép giảm.
struct AddWordSheet: View {
    /// Chế độ mở sheet — quyết định **cách dựng gợi ý phiên âm**, KHÔNG còn quyết định nút Lưu.
    ///
    /// `chooseAtSave` = mở từ **Reader** (không có từ điển đích sẵn). Hai case còn lại là màn sửa từ điển
    /// của từng engine. Từ 1.3.469 nút Lưu là `Menu` **3 mục** ở **mọi** chế độ, nên `Target` **không**
    /// còn được truyền ra `onAdd` — đích ghi nằm ở `PhoneticDictionaryWriter.Destination`.
    enum Target: Equatable {
        case nghiTTS
        case vieNeu
        case chooseAtSave
    }

    /// Mục đang chờ xác nhận xoá — nhấn giữ chip `NGI`/`VIE` rồi chọn "Xoá".
    ///
    /// Giữ cả `text` (cách đọc) để gỡ **đúng** chip khỏi danh sách sau khi xoá, và `lookupKey` để gọi đúng
    /// API xoá của store (khoá **đã chuẩn hoá**, không phải chuỗi người dùng gõ).
    private struct PendingDeletion: Equatable {
        let origin: TTSPhoneticSuggestion.Origin
        let text: String
        let lookupKey: String
    }

    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var value = ""
    @State private var validationError: String? = nil
    /// Kết quả dựng gợi ý gần nhất. `body` **chỉ** đọc biến này, không tự tính lại.
    @State private var suggestions: [TTSPhoneticSuggestion] = []
    @State private var isBuildingSuggestions = false
    @State private var suggestionLoadTask: Task<Void, Never>? = nil
    @State private var pendingDeletion: PendingDeletion? = nil

    let onAdd: (String, String, PhoneticDictionaryWriter.Destination) -> Void
    let showSuggestions: Bool
    let target: Target

    init(
        initialKey: String = "",
        showSuggestions: Bool = false,
        target: Target = .nghiTTS,
        onAdd: @escaping (String, String, PhoneticDictionaryWriter.Destination) -> Void
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
            .confirmationDialog(
                "Xoá khỏi từ điển phiên âm?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pending = pendingDeletion {
                    Button("Xoá \"\(pending.lookupKey)\" khỏi \(dictionaryName(pending.origin))", role: .destructive) {
                        deleteEntry(pending)
                    }
                }
                Button("Huỷ", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Mục sẽ bị xoá khỏi từ điển phiên âm và **không** khôi phục được.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 3 mục ở **mọi** chế độ mở sheet: đích cố định của màn gọi chỉ là gợi ý, không phải
                    // ràng buộc — người dùng vẫn có thể lưu sang từ điển của engine kia, hoặc cả hai.
                    Menu("Lưu") {
                        Button("Lưu vào NghiTTS") { save(.nghiTTS) }
                        Button("Lưu vào VieNeu-TTS") { save(.vieNeu) }
                        Button("Lưu tất cả") { save(.both) }
                    }
                    .disabled(!canSave)
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

    @ViewBuilder
    private func suggestionChip(_ suggestion: TTSPhoneticSuggestion) -> some View {
        let chip = Button(action: {
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

        // Nhấn giữ chỉ có tác dụng với chip **có trong từ điển**. Chip JP/EN là kết quả phiên âm tự động,
        // không nằm trong từ điển nào nên không có gì để xoá — gắn menu vào chúng chỉ gây hiểu nhầm.
        if suggestion.origin.isDictionaryEntry {
            chip.contextMenu {
                Button(role: .destructive) {
                    pendingDeletion = PendingDeletion(
                        origin: suggestion.origin,
                        text: suggestion.text,
                        lookupKey: TTSPhoneticSuggestionBuilder.normalizedKey(trimmedKey)
                    )
                } label: {
                    Label("Xoá khỏi \(dictionaryName(suggestion.origin))", systemImage: "trash")
                }
            }
        } else {
            chip
        }
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
            let hits = await Self.libraryHits(for: lookupKey)
            guard !Task.isCancelled else { return }

            // Tách thành hai `String?` rời thay vì truyền cả tuple: closure của `Task.detached` là
            // `@Sendable`, và hai `String?` là kiểu Sendable chắc chắn — không phụ thuộc việc compiler có
            // chấp nhận tuple ở vị trí capture hay không.
            let nghiTTSHit = hits.nghiTTS
            let vieNeuHit = hits.vieNeu

            // Đích VieNeu **không** có nhánh tiếng Anh/IPA ⇒ bỏ hẳn chip EN (và bỏ luôn lượt espeak).
            let includeEnglish = target != .vieNeu
            let built = await Task.detached(priority: .userInitiated) {
                TTSPhoneticSuggestionBuilder.suggestions(
                    for: word,
                    nghiTTSHit: nghiTTSHit,
                    vieNeuHit: vieNeuHit,
                    includeEnglish: includeEnglish
                )
            }.value
            guard !Task.isCancelled else { return }

            suggestions = built
            isBuildingSuggestions = false
        }
    }

    private func save(_ destination: PhoneticDictionaryWriter.Destination) {
        onAdd(key, value, destination)
        dismiss()
    }

    /// Tra **cả hai** từ điển phiên âm, **không** phụ thuộc `target`.
    ///
    /// Từ 1.3.462 chip gợi ý hiện cả `NGI` lẫn `VIE` để người dùng thấy mục đã có ở đâu — hai từ điển độc
    /// lập, cùng một cách đọc vẫn là hai chip (chốt 2026-10-01). Trước đây chỉ tra từ điển của đích nên mở
    /// từ màn NghiTTS thì không bao giờ thấy mục đã có bên VieNeu (và ngược lại).
    private static func libraryHits(for lookupKey: String) async -> (nghiTTS: String?, vieNeu: String?) {
        guard !lookupKey.isEmpty else { return (nil, nil) }
        let nghiTTS = await TextPreprocessor.shared.lookupWord(lookupKey)
        let vieNeu = await VieNeuJapaneseDictionary.shared.lookup(lookupKey)
        return (nghiTTS, vieNeu)
    }

    /// Xoá mục khỏi **đúng** từ điển mà chip trỏ tới, rồi gỡ chip đó khỏi danh sách.
    ///
    /// Gỡ chip **sau khi** xoá thành công: xoá lỗi mà chip đã biến mất thì người dùng tưởng đã xong.
    /// Không dựng lại cả danh sách gợi ý sau khi xoá — phần còn lại không đổi, dựng lại chỉ tốn thêm một
    /// lượt `EspeakPhonemizer` (hàm C giữ `NSLock` dùng chung với đường tổng hợp).
    private func deleteEntry(_ pending: PendingDeletion) {
        pendingDeletion = nil
        Task {
            do {
                switch pending.origin {
                case .nghiTTSLibrary:
                    try await TextPreprocessor.shared.deleteWord(key: pending.lookupKey)
                case .vieNeuLibrary:
                    try await VieNeuJapaneseDictionary.shared.delete(key: pending.lookupKey)
                case .japanese, .englishIPA, .englishRule:
                    return
                }
                suggestions.removeAll { $0.origin == pending.origin && $0.text == pending.text }
                ToastManager.shared.show(
                    message: "Đã xoá \"\(pending.lookupKey)\" khỏi \(dictionaryName(pending.origin))",
                    type: .success
                )
            } catch {
                ToastManager.shared.show(message: "Xoá thất bại: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Tên hiển thị của từ điển theo nguồn chip — dùng cho nhãn menu xoá và toast.
    private func dictionaryName(_ origin: TTSPhoneticSuggestion.Origin) -> String {
        switch origin {
        case .nghiTTSLibrary: return "từ điển NghiTTS"
        case .vieNeuLibrary: return "từ điển VieNeu-TTS"
        case .japanese, .englishIPA, .englishRule: return "từ điển"
        }
    }
}
