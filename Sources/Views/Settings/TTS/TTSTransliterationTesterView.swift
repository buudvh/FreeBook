import SwiftUI

/// Màn **Thử phiên âm**: chỗ duy nhất quan sát được đường đi của một từ qua pipeline tiền xử lý TTS.
///
/// Vì sao cần: app chạy thật qua LiveContainer nên không đính được debugger, và theo `CLAUDE.md` tầng
/// `Tests/` coi như không tồn tại. Đổi bảng âm vị hay ngưỡng phân loại mà không có thước đo thì chỉ là
/// đổi chỗ sai, nên thước đo phải nằm trong app.
///
/// Bốn ô, theo thứ tự cần dùng khi chẩn đoán: giọng espeak có thật không → cả câu → soi một từ → chạy
/// bộ ca kiểm.
struct TTSTransliterationTesterView: View {
    private struct InspectRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private struct GoldenRow: Identifiable {
        let id = UUID()
        let kind: String
        let input: String
        let expected: String
        let actual: String
        let passed: Bool
        let note: String
    }

    @AppStorage(EnglishPhonemeTransliterator.useEspeakKey) private var useEspeakPath = true

    @State private var sentence = "The system station is ready. ラーメン tsunami tomato"
    @State private var sentenceOutput = ""
    @State private var word = "station"
    @State private var inspection: [InspectRow] = []
    @State private var voices: [(name: String, available: Bool)] = []
    @State private var golden: [GoldenRow] = []
    @State private var isBusy = false

    private static let probedVoices = ["vi", "en-us", "en", "en-gb", "ja"]

    var body: some View {
        Form {
            engineSection
            TTSIPAProbeSection()
            sentenceSection
            wordSection
            goldenSection
        }
        .navigationTitle("Thử phiên âm")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Giọng espeak

    @ViewBuilder
    private var engineSection: some View {
        Section {
            Toggle("Dùng IPA của espeak cho tiếng Anh", isOn: $useEspeakPath)

            Button("Kiểm tra giọng espeak") {
                let probed = EspeakPhonemizer.probeVoices(Self.probedVoices)
                voices = Self.probedVoices.map { (name: $0, available: probed[$0] ?? false) }
            }

            ForEach(voices, id: \.name) { voice in
                HStack {
                    Text(voice.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Image(systemName: voice.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(voice.available ? .green : .red)
                }
            }
        } header: {
            Text("Engine")
        } footer: {
            Text("Tắt công tắc trên là quay về bộ luật chính tả cũ, dùng để so A/B ngay trên máy. Nếu `en-us` báo đỏ thì bộ dữ liệu espeak trong bản build này thiếu giọng Anh và mọi từ tiếng Anh đang chạy bằng luật dự phòng.")
        }
    }

    // MARK: - Cả câu

    @ViewBuilder
    private var sentenceSection: some View {
        Section {
            TextEditor(text: $sentence)
                .frame(minHeight: 70)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()

            Button("Chạy cả pipeline") {
                runSentence()
            }
            .disabled(isBusy)

            if !sentenceOutput.isEmpty {
                Text(sentenceOutput)
                    .font(.footnote)
                    .foregroundColor(.accentColor)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Cả câu (đúng những gì TTS nhận được)")
        }
    }

    // MARK: - Soi một từ

    @ViewBuilder
    private var wordSection: some View {
        Section {
            TextField("station", text: $word)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Soi từ này") {
                inspectWord()
            }
            .disabled(isBusy)

            ForEach(inspection) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(row.value.isEmpty ? "(rỗng)" : row.value)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Một từ")
        } footer: {
            Text("Thứ tự pipeline thật: từ điển thắng trước, rồi tới bộ phân loại Nhật/Anh, rồi mới tới bộ phiên âm tương ứng.")
        }
    }

    // MARK: - Bộ ca kiểm

    @ViewBuilder
    private var goldenSection: some View {
        Section {
            Button("Chạy bộ ca kiểm (\(TransliterationGoldenSet.all.count) ca)") {
                runGolden()
            }
            .disabled(isBusy)

            if !golden.isEmpty {
                let passed = golden.filter(\.passed).count
                Text("Đúng \(passed)/\(golden.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(passed == golden.count ? .green : .orange)

                ForEach(golden) { row in
                    goldenRowView(row)
                }
            }
        } header: {
            Text("Bộ ca kiểm")
        } footer: {
            Text("Kỳ vọng ở đây là **định hướng**, không phải chuẩn chính tả: dùng để thấy một thay đổi làm tốt lên hay xấu đi trên cùng một tập. Ca nào đổi kỳ vọng thì đổi cùng commit kèm lý do.")
        }
    }

    private func goldenRowView(_ row: GoldenRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: row.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(row.passed ? .green : .red)
                Text(row.kind)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(row.input)
                    .font(.system(.footnote, design: .monospaced))
            }
            Text("mong đợi: \(row.expected)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("thực tế: \(row.actual.isEmpty ? "(rỗng)" : row.actual)")
                .font(.system(size: 10))
                .foregroundColor(row.passed ? .secondary : .red)
            if !row.note.isEmpty {
                Text(row.note)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Chạy

    private func runSentence() {
        isBusy = true
        let text = sentence
        Task {
            let output = await TextPreprocessor.shared.preprocess(text)
            await MainActor.run {
                sentenceOutput = output
                isBusy = false
            }
        }
    }

    private func inspectWord() {
        isBusy = true
        let raw = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Task {
            let dictHit = await TextPreprocessor.shared.lookupWord(raw)
            let verdict = ForeignScriptClassifier.classify(raw)
            let outcome = EnglishPhonemeTransliterator.detailed(raw)
            let kana = JapaneseTransliterator.convertToRomaji(raw)
            let japanese = JapaneseTransliterator.transliterateRomaji(raw)
            let ruleOnly = EnglishTransliterator.transliterateWord(raw)
            let pipeline = await TextPreprocessor.shared.preprocess(raw)

            let rows: [InspectRow] = [
                InspectRow(label: "Từ điển phiên âm", value: dictHit ?? "(không có)"),
                InspectRow(label: "Phân loại", value: "\(verdict.isJapanese ? "Nhật" : "Anh") · điểm \(verdict.score)"),
                InspectRow(label: "Lý do phân loại", value: verdict.reasons.joined(separator: " · ")),
                InspectRow(label: "Kana → romaji", value: kana == raw ? "(không phải kana)" : kana),
                InspectRow(label: "Đường Nhật", value: japanese),
                InspectRow(label: "IPA (espeak en-us)", value: outcome.ipa),
                InspectRow(label: "Đường Anh (\(outcome.source.rawValue))", value: outcome.text),
                InspectRow(label: "Bộ luật chính tả (dự phòng)", value: ruleOnly),
                InspectRow(label: "Kết quả cả pipeline", value: pipeline)
            ]

            await MainActor.run {
                inspection = rows
                isBusy = false
            }
        }
    }

    private func runGolden() {
        isBusy = true
        Task {
            var rows: [GoldenRow] = []
            for testCase in TransliterationGoldenSet.all {
                let actual = await actualResult(for: testCase)
                let passed: Bool
                switch testCase.kind {
                case .vietnamese:
                    passed = actual.contains(testCase.expected)
                default:
                    passed = actual == testCase.expected
                }
                rows.append(GoldenRow(
                    kind: testCase.kind.rawValue,
                    input: testCase.input,
                    expected: testCase.expected,
                    actual: actual,
                    passed: passed,
                    note: testCase.note
                ))
            }
            await MainActor.run {
                golden = rows
                isBusy = false
            }
        }
    }

    private func actualResult(for testCase: TransliterationGoldenSet.Case) async -> String {
        switch testCase.kind {
        case .classifier:
            return ForeignScriptClassifier.isJapaneseRomaji(testCase.input) ? "Nhật" : "Anh"
        case .japanese:
            let romaji = JapaneseTransliterator.convertToRomaji(testCase.input)
            return JapaneseTransliterator.transliterateRomaji(romaji)
        case .english:
            return EnglishPhonemeTransliterator.transliterate(testCase.input)
        case .vietnamese:
            return await TextPreprocessor.shared.preprocess(testCase.input)
        }
    }
}
