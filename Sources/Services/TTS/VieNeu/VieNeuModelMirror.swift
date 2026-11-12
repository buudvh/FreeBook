import Foundation

/// Nơi app tải model + dữ liệu VieNeu (Nano lẫn Turbo) từ 1.3.888: kho Hugging Face `raikiri1498/VieNeu-TTS`
/// của anh Bửu. Đây là **bản sao nguyên văn** (từng byte) của các nguồn gốc, đúng revision app ghim trước đó:
/// - `common/` — file **dùng chung** cho Nano và Turbo:
///   - `sea_g2p.bin` = `pnnbao97/sea-g2p` @ `e825173f235d08ea19315b2b279fb11153b44cea` (`python/sea_g2p/sea_g2p.bin`)
///   - `speaker_encoder.onnx`, `denoiser.onnx` = có ở cả hai kho model bên dưới, trùng từng byte
/// - `nano/` = `pnnbao-ump/VieNeu-TTS-v3-Nano` @ `aba295eb96a6fa6003ebe417cc1f2802a7adc1dc` (trừ hai file trên), cộng
///   `voices_v3_nano.json` của `pnnbao97/VieNeu-TTS` @ `2e982ff857bbe23fffa0c314e0f60da2497e2f4b`
/// - `turbo/gguf/` = `pnnbao-ump/VieNeu-TTS-v3-Turbo` @ `61b85e3d937fbbacb387714180e8182823512523` (`gguf/`)
///
/// Tất cả là Apache-2.0. README của kho ghi nguồn, giấy phép và sha256 từng file.
///
/// Vì nội dung trùng từng byte, file người dùng đã tải từ nguồn cũ vẫn dùng tiếp, không phải tải lại.
///
/// Ghim **commit** của kho mirror như trước: URL có sha là bất biến. Đổi file trong kho mà chưa đổi `revision` thì
/// app vẫn tải bản cũ.
enum VieNeuModelMirror {
    static let repository = "raikiri1498/VieNeu-TTS"
    /// Commit của `raikiri1498/VieNeu-TTS` có đủ file Nano + Turbo (2026-11-12).
    static let revision = "3486d7dad160cf1b63d957bc5643d447b1e80cfb"

    /// File dùng chung cho Nano và Turbo — kho đặt ở `common/` thay vì thư mục của một model.
    static let commonFileNames: Set<String> = ["sea_g2p.bin", "speaker_encoder.onnx", "denoiser.onnx"]

    /// `path` tương đối trong kho, vd `nano/text_encoder.onnx`, `turbo/gguf/voices/manifest.json`.
    static func url(path: String) -> URL? {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)")
    }

    /// Đường dẫn trong kho của một file mà `VieNeuModelStore` (Nano) tải theo tên: dùng chung ⇒ `common/`, còn lại
    /// `nano/`.
    static func nanoStorePath(_ fileName: String) -> String {
        commonFileNames.contains(fileName) ? "common/\(fileName)" : "nano/\(fileName)"
    }
}
