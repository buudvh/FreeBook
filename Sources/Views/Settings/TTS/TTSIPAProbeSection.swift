import AVFoundation
import SwiftUI

/// Thí nghiệm E1: nghe model đọc **chuỗi IPA thô**, và đếm ký hiệu nằm ngoài bộ từ vựng của nó.
///
/// Lý do phải có: `phoneme_id_map` của model Piper đang dùng có **161 ký hiệu và là bộ IPA đầy đủ**,
/// gồm mọi thứ espeak `en-us` sinh ra. Nếu model đọc được IPA tiếng Anh thì cả tầng
/// `IPAToVietnameseMapper` là không cần thiết — và chính vòng "IPA → chữ Việt → text → phiên âm lại"
/// mới là chỗ đang làm sai và mất chữ.
///
/// **Nhưng có mặt trong từ vựng không có nghĩa là đã được train.** Bảng 161 ký hiệu là bảng chuẩn
/// Piper phát cho mọi giọng, không phải bằng chứng dữ liệu tiếng Việt có `θ`, `ð`, `æ`. Cách duy nhất
/// biết là nghe — đó là toàn bộ mục đích của ô nhập này.
///
/// Là `View` riêng chứ không phải extension của `TTSTransliterationTesterView`: state của màn đó là
/// `private` nên extension ở file khác không đọc được, và file đó chỉ còn ít dòng trước trần 400.
struct TTSIPAProbeSection: View {
    private struct Coverage: Identifiable {
        let id = UUID()
        let word: String
        let ipa: String
        let missing: String
    }

    /// Sáu ca của E1. `θ ð æ` là ba âm khó nhất — nếu chúng ra tiếng lạ thì hướng đưa IPA tiếng Anh
    /// vào thẳng model không dùng được, phải quay lại phiên âm sang âm Việt.
    private static let presets: [(label: String, ipa: String)] = [
        ("hello", "həlˈoʊ"),
        ("street", "stɹˈiːt"),
        ("think (θ)", "θˈɪŋk"),
        ("this (ð)", "ðˈɪs"),
        ("cat (æ)", "kˈæt"),
        ("ラーメン", "ɾaːmen"),
        ("Việt đối chứng", "sˈaːw")
    ]

    /// Danh sách phủ rộng âm vị tiếng Anh, để bảng "ngoài từ vựng" nói được điều gì đó chắc chắn.
    private static let coverageWords = [
        "think", "this", "cat", "street", "measure", "church", "judge", "sing",
        "world", "girl", "bird", "about", "book", "food", "father", "caught",
        "voice", "house", "day", "toy", "hue", "nature", "vision", "little"
    ]

    /// Phủ rộng âm vị **tiếng Việt**: đủ 6 thanh, các phụ âm đầu khó (`ng`, `nh`, `tr`, `ch`, `kh`,
    /// `ph`, `th`, `gi`, `d`, `x`, `s`, `r`), và các âm cuối (`-c`, `-t`, `-p`, `-ch`, `-nh`, `-ng`).
    ///
    /// Dùng để dựng **bộ ký hiệu mà model thật sự thấy khi train**: model này là Piper tiếng Việt, nên
    /// tập âm vị nó được huấn luyện chính là tập mà espeak `vi` sinh ra. Ký hiệu chỉ xuất hiện ở
    /// `en-us` mà không bao giờ ở `vi` là **ứng viên chưa được train** — đó là lý do `θ` đọc được mà
    /// `ð`/`æ` thì không, và đây là cách biết trước mà không phải nghe từng ký hiệu một.
    private static let vietnameseProbeWords = [
        "sao", "sáo", "sào", "sảo", "são", "sạo",
        "nghiêng", "nhanh", "trong", "chung", "không", "phong", "thương", "giang",
        "dạy", "xanh", "sương", "rừng", "lười", "quyển", "khuya", "nguyệt",
        "bác", "bát", "bắp", "bích", "bình", "bằng", "tuyệt", "hoàng", "uống", "yêu"
    ]

    @State private var ipaInput = "həlˈoʊ"
    @State private var vietnameseInput = "sao"
    @State private var symbolDiff = ""
    @State private var status = ""
    @State private var inventorySummary = ""
    @State private var coverage: [Coverage] = []
    @State private var player: AVAudioPlayer?
    @State private var isBusy = false
    /// Giữ engine qua nhiều lần bấm: dựng `ORTSession` mới mỗi lần tốn ~1 giây và nạp thêm một bản
    /// model vào RAM cạnh bản đang phát.
    @State private var engine = ONNXPiperEngine()

    var body: some View {
        Section {
            TextField("Chuỗi IPA", text: $ipaInput, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.label) { preset in
                        Button(preset.label) { ipaInput = preset.ipa }
                            .font(.footnote)
                            .buttonStyle(.bordered)
                    }
                }
            }

            Button(isBusy ? "Đang tổng hợp…" : "Tổng hợp & nghe") { synthesise() }
                .disabled(isBusy || ipaInput.trimmingCharacters(in: .whitespaces).isEmpty)

            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(status.hasPrefix("Lỗi") ? .red : .secondary)
            }
        } header: {
            Text("E1 · Nghe IPA thô")
        } footer: {
            Text("Đưa chuỗi này **thẳng** vào model, bỏ qua toàn bộ tầng phiên âm. Nếu `θˈɪŋk`, `ðˈɪs`, `kˈæt` nghe ra âm tiếng Anh thì bỏ được hẳn bước phiên âm sang chữ Việt. Nếu ra tiếng lạ hoặc im lặng thì các ký hiệu đó có trong từ vựng nhưng chưa được train.")
        }

        Section {
            TextField("Từ tiếng Việt", text: $vietnameseInput)
                .autocorrectionDisabled()
            Button("Lấy IPA (vi) → điền vào ô trên") { fillFromVietnamese() }
                .disabled(isBusy || vietnameseInput.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("E1 · Ca đối chứng")
        } footer: {
            Text("Lấy IPA **thật** mà espeak `vi` sinh ra cho một từ tiếng Việt, rồi tổng hợp lại chính chuỗi đó. Nghe ra đúng từ vừa nhập ⇒ dụng cụ đo đáng tin. Nghe ra từ khác ⇒ lỗi ở dụng cụ, không phải ở model. Đừng dùng chuỗi IPA tự đoán làm đối chứng: `sˈaːw` **không** phải IPA của \"sao\".")
        }

        Section {
            Button("So bộ ký hiệu vi và en-us") { runSymbolDiff() }
                .disabled(isBusy)
            if !symbolDiff.isEmpty {
                Text(symbolDiff)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        } header: {
            Text("E1 · Ký hiệu nào chưa được train")
        } footer: {
            Text("Model này là Piper **tiếng Việt**, nên tập âm vị nó được huấn luyện chính là tập mà espeak `vi` sinh ra. Ký hiệu chỉ có ở `en-us` mà không bao giờ có ở `vi` là **ứng viên chưa được train** — biết trước bằng một lần bấm, thay vì nghe thử từng ký hiệu.")
        }

        Section {
            Button("Đếm ký hiệu ngoài từ vựng của model") { runCoverage() }
                .disabled(isBusy)

            if !inventorySummary.isEmpty {
                Text(inventorySummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(coverage) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.word).font(.system(.footnote, design: .monospaced))
                        Spacer()
                        Text(row.missing.isEmpty ? "đủ" : row.missing)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(row.missing.isEmpty ? .green : .red)
                    }
                    Text(row.ipa)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("E1 · Phủ âm vị")
        } footer: {
            Text("Chạy espeak `en-us` trên 24 từ phủ rộng âm vị tiếng Anh rồi liệt kê scalar nào **không** có trong `phoneme_id_map`. Trước đây mỗi scalar lạ chỉ được ghi một dòng log rồi bỏ im lặng, nên không ai đếm được tổng thiệt hại.")
        }
    }

    // MARK: - Hành động

    private func modelURLs() -> (onnx: URL, config: URL)? {
        guard let store = try? ModelStore() else { return nil }
        let voiceID = TTSManager.shared.selectedVoice.toASCIIID
        let onnx = store.modelURL(for: voiceID, extension: "onnx")
        let config = store.modelURL(for: voiceID, extension: "onnx.json")
        guard FileManager.default.fileExists(atPath: onnx.path),
              FileManager.default.fileExists(atPath: config.path) else { return nil }
        return (onnx, config)
    }

    private func synthesise() {
        guard let urls = modelURLs() else {
            status = "Lỗi: chưa tải model của giọng '\(TTSManager.shared.selectedVoice)'."
            return
        }
        isBusy = true
        let phonemes = ipaInput
        let engine = self.engine
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try engine.synthesizeRawPhonemes(phonemes, modelONNX: urls.onnx, modelConfig: urls.config)
                }.value

                var parts = [
                    "\(String(format: "%.2f", result.pcmDuration))s · \(result.phonemeIDCount) id"
                ]
                if !result.downgraded.isEmpty {
                    parts.append("hạ cấp: " + result.downgraded.map { "\($0.symbol)→\($0.replacement)×\($0.count)" }.joined(separator: ", "))
                }
                if !result.dropped.isEmpty {
                    parts.append("BỎ: " + result.dropped.map { "\($0.symbol)×\($0.count)" }.joined(separator: ", "))
                }

                await MainActor.run {
                    status = parts.joined(separator: " · ")
                    isBusy = false
                    play(result.data)
                }
            } catch {
                await MainActor.run {
                    status = "Lỗi: \(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }

    private func play(_ wav: Data) {
        // Dùng lại chủ sở hữu audio session của app thay vì tự cấu hình lần thứ hai.
        TTSManager.shared.audioSessionController.activate()
        _ = TTSManager.shared.audioSessionController.configureAudioSession()
        do {
            let newPlayer = try AVAudioPlayer(data: wav)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            status = "Lỗi phát: \(error.localizedDescription)"
        }
    }

    /// Lấy IPA thật của espeak `vi` cho một từ tiếng Việt và điền vào ô IPA thô.
    ///
    /// Ca đối chứng **phải** lấy từ chính espeak, không được tự đoán. Chuỗi `sˈaːw` mà tôi từng dùng
    /// làm đối chứng cho "sao" là đoán sai, và nó làm hiểu lầm rằng dụng cụ đo hỏng.
    private func fillFromVietnamese() {
        let word = vietnameseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isBusy = true
        Task {
            let ipa = await Task.detached(priority: .userInitiated) {
                (try? EspeakPhonemizer.phonemize(text: word)) ?? ""
            }.value
            await MainActor.run {
                isBusy = false
                if ipa.isEmpty {
                    status = "Lỗi: espeak không trả IPA cho '\(word)'."
                } else {
                    ipaInput = ipa
                    status = "IPA (vi) của '\(word)': \(ipa)"
                }
            }
        }
    }

    /// Dựng hai bộ ký hiệu (`vi` và `en-us`) rồi lấy phần chỉ có ở `en-us`.
    private func runSymbolDiff() {
        isBusy = true
        Task {
            let report = await Task.detached(priority: .userInitiated) { () -> String in
                func symbols(_ words: [String], english: Bool) -> Set<String> {
                    var result: Set<String> = []
                    for word in words {
                        let ipa = english
                            ? ((try? EspeakPhonemizer.phonemizeEnglish(text: word)) ?? "")
                            : ((try? EspeakPhonemizer.phonemize(text: word)) ?? "")
                        for scalar in ipa.unicodeScalars where !scalar.properties.isWhitespace {
                            result.insert(String(scalar))
                        }
                    }
                    return result
                }

                let vietnamese = symbols(Self.vietnameseProbeWords, english: false)
                let english = symbols(Self.coverageWords, english: true)
                guard !vietnamese.isEmpty, !english.isEmpty else {
                    return "Lỗi: espeak không trả IPA (thiếu giọng vi hoặc en-us?)."
                }

                let onlyEnglish = english.subtracting(vietnamese).sorted()
                let shared = english.intersection(vietnamese).sorted()
                return """
                vi: \(vietnamese.count) ký hiệu · en-us: \(english.count) ký hiệu
                CHỈ có ở en-us (ứng viên CHƯA train): \(onlyEnglish.isEmpty ? "(không có)" : onlyEnglish.joined(separator: " "))
                Có ở cả hai (chắc chắn đã train): \(shared.joined(separator: " "))
                """
            }.value
            await MainActor.run {
                symbolDiff = report
                isBusy = false
            }
        }
    }

    private func runCoverage() {        guard let urls = modelURLs() else {
            inventorySummary = "Chưa tải model của giọng '\(TTSManager.shared.selectedVoice)'."
            return
        }
        isBusy = true
        let configURL = urls.config
        Task {
            // espeak là lời gọi C có khoá; 24 lượt trên main thread là giật UI.
            let outcome = await Task.detached(priority: .userInitiated) { () -> (String, [Coverage]) in
                do {
                    let inventory = try PiperPhonemeInventory(configURL: configURL)
                    var built: [Coverage] = []
                    var totalMissing = 0
                    for word in Self.coverageWords {
                        let ipa = (try? EspeakPhonemizer.phonemizeEnglish(text: word)) ?? ""
                        let missing = inventory.missingScalars(in: ipa)
                        totalMissing += missing.reduce(0) { $0 + $1.count }
                        built.append(Coverage(
                            word: word,
                            ipa: ipa.isEmpty ? "(espeak không trả gì)" : ipa,
                            missing: missing.map { "\($0.symbol)×\($0.count)" }.joined(separator: " ")
                        ))
                    }
                    let tail = totalMissing == 0
                        ? " Không scalar nào ngoài từ vựng."
                        : " \(totalMissing) scalar ngoài từ vựng."
                    return ("Từ vựng model: \(inventory.count) ký hiệu." + tail, built)
                } catch {
                    return ("Lỗi: \(error.localizedDescription)", [])
                }
            }.value
            let summary = outcome.0
            let rows = outcome.1
            await MainActor.run {
                inventorySummary = summary
                coverage = rows
                isBusy = false
            }
        }
    }
}
