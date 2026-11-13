import Foundation

/// Đầu vào **vòng Euler + CFG** của một chunk Nano — mọi thứ `VieNeuTTSEngine.runChunk` đã tính xong trước bước
/// `vector_estimator` (text_encoder, duration, nhiễu khởi tạo, lưới t), gom lại để một backend khác ORT chạy được.
///
/// Mảng giữ đúng layout của engine: `latent` = `[1, latentChannels, frames]`, `context` = `[1, L, D]` theo
/// `contextShape`, `mask` = `[L]` (1 = token thật), nhánh vô điều kiện (`null*`) như `makeNullBranch`.
struct VieNeuFlowRequest: Sendable {
    let latent: [Float]
    let frames: Int
    let latentChannels: Int
    let grid: [Double]
    let cfg: Float
    let context: [Float]
    let contextShape: [Int64]
    let mask: [UInt8]
    let speaker: [Float]
    let style: [Float]
    let styleRows: Int
    let styleColumns: Int
    let nullContext: [Float]
    let nullContextShape: [Int64]
    let nullMask: [UInt8]
    let nullSpeaker: [Float]
    let nullStyle: [Float]

    /// Số token L của `context` (chiều 1 của `[1, L, D]`).
    var contextLength: Int { contextShape.count >= 2 ? Int(contextShape[1]) : 0 }
    /// Chiều D của `context`.
    var contextDim: Int { contextShape.count >= 3 ? Int(contextShape[2]) : 0 }
}

/// Backend chạy vòng Euler + codec **thay ORT** cho một lượt tổng hợp Nano — Core ML CPU-only
/// (`VieNeuCoreMLFlowBackend`): của màn thử (P1b) hoặc của trình đọc khi bật "Tăng tốc Core ML" (P2c,
/// `VieNeuCoreMLReaderRoute`). Truyền **theo từng lượt gọi**, không gắn vào engine:
/// - hàm `synthesizeWithDuration` đúng chữ ký `LocalTTSEngine` (trình đọc, Nghe thử, nghe thử giọng) lấy backend của
///   trình đọc từ `VieNeuCoreMLReaderRoute` — `nil` khi tắt / chưa sẵn sàng;
/// - hàm có tham số `flowBackend:` (màn thử: "Đọc liên tục", các lượt của Đo tự động) dùng **đúng** giá trị truyền vào,
///   `nil` = ORT — lượt ORT của phép đo A-B-A không bao giờ lẫn Core ML của trình đọc.
///
/// Engine gọi tuần tự trong khoá tổng hợp của nó ⇒ backend không phải tự chịu nhiều luồng gọi cùng lúc.
protocol VieNeuFlowBackend: AnyObject, Sendable {
    /// `false` ⇒ chunk này vượt bucket (T / L) ⇒ engine chạy ORT như cũ rồi báo `noteFallback`.
    func canRun(_ request: VieNeuFlowRequest) -> Bool
    /// Quỹ đạo đủ `grid.count − 1` bước, trả latent cuối `[1, latentChannels, frames]`.
    func trajectory(_ request: VieNeuFlowRequest) throws -> [Float]
    /// `codec_decoder` → PCM float32, đúng `frames × 1536` mẫu.
    func decode(latent: [Float], frames: Int, latentChannels: Int) throws -> [Float]
    /// Chunk vừa chạy ORT vì `canRun` trả `false` — để báo cáo đếm phần lùi về ORT.
    func noteFallback(_ request: VieNeuFlowRequest)
    /// `true` ⇒ backend lỗi ở một chunk thì engine chạy lại chunk đó bằng ORT thay vì báo lỗi cả đoạn (trình đọc, P2c —
    /// không bao giờ mất tiếng). Màn thử để `false`: lỗi là lỗi, để số đo không che lỗi.
    var fallsBackToORTOnError: Bool { get }
    /// Chunk vừa lỗi và đã chạy lại bằng ORT (chỉ gọi khi `fallsBackToORTOnError`).
    func noteFailure(_ error: Error)
}

extension VieNeuFlowBackend {
    var fallsBackToORTOnError: Bool { false }
    func noteFailure(_ error: Error) {}
}
