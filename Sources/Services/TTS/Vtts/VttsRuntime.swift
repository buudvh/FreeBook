import CVTTS
import Foundation

/// Giữ handle C của vtts (`vtts_bridge`, gói `Vendor/vtts`) theo giọng và chạy **mọi** lượt gọi C trên **một** hàng
/// đợi nối tiếp.
///
/// ## Vì sao một hàng đợi cho cả hai giọng
/// Front-end chữ của vtts dùng mảng `static` toàn cục (`v2_sentence` trong `vtts_text.c`) và runtime có setter toàn cục
/// (`vtts_set_fast_scratch`, `vtts_set_out_stage`) ⇒ hai lượt chạy song song — kể cả trên hai handle khác nhau — làm
/// hỏng dữ liệu. Handle chỉ được tra / tạo / nhả **bên trong** hàng đợi: tra trước rồi mới dispatch thì một lượt
/// `releaseAll()` chen vào giữa thành use-after-free. `PiperSynthesisCoordinator` vốn đã cho mỗi lúc một lượt tổng
/// hợp; hàng đợi ở đây chặn thêm các lối không qua coordinator (nạp trước giọng, nhả handle).
///
/// ## Bộ nhớ
/// Model (2,6 MB) + VLEX (1,9 MB) được mmap chỉ đọc (trang sạch theo file — iOS tự nhả khi thiếu RAM, hai giọng dùng
/// chung trang VLEX); mỗi handle thêm ~160 KB heap (workspace front-end). Arena tổng hợp cấp theo lượt rồi trả ngay.
final class VttsRuntime: @unchecked Sendable {
    static let shared = VttsRuntime()

    /// Thư mục con trong bundle — folder resource `Vendor/vtts/assets/vtts` của `project.yml`.
    static let assetSubdirectory = "vtts"
    static let lexiconFileName = "lex_en.bin"

    /// Kết quả một lượt: PCM mono float [-1, 1] (đã nối các chunk front-end, giữa hai chunk 150 ms im lặng), tần số
    /// của model, số chunk front-end, thời gian chạy trong C.
    struct Output {
        let samples: [Float]
        let sampleRate: Int
        let chunkCount: Int
        let runMs: Double
    }

    enum Failure: LocalizedError {
        case missingAssets
        case loadFailed(voice: String, code: Int32, name: String)
        case synthesisFailed(code: Int32, name: String, vttsError: Int32)

        var errorDescription: String? {
            switch self {
            case .missingAssets:
                return "Bản build thiếu tài sản vtts (thư mục vtts/ trong ứng dụng)."
            case let .loadFailed(voice, code, name):
                return "Không nạp được giọng vtts \(voice) (lỗi \(code) \(name))."
            case let .synthesisFailed(code, name, vttsError):
                return "vtts tổng hợp lỗi \(code) \(name) (mã vtts \(vttsError))."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.raikiri1498.FreeBook.vtts.runtime", qos: .userInitiated)
    /// Chỉ đọc / ghi trên `queue`.
    private var handles: [VttsVoice: OpaquePointer] = [:]

    private init() {}

    static func modelURL(for voice: VttsVoice) -> URL? {
        Bundle.main.url(forResource: voice.modelFileName, withExtension: nil, subdirectory: assetSubdirectory)
    }

    static var lexiconURL: URL? {
        Bundle.main.url(forResource: lexiconFileName, withExtension: nil, subdirectory: assetSubdirectory)
    }

    /// Đủ tài sản trong bundle (2 model + VLEX). Chỉ kiểm file, không đụng hàng đợi ⇒ gọi được từ main. Bundle không đổi
    /// lúc chạy nên tính một lần.
    static let isAvailable: Bool = {
        guard lexiconURL != nil else { return false }
        return VttsVoice.allCases.allSatisfy { modelURL(for: $0) != nil }
    }()

    // MARK: - API

    /// Nạp handle của giọng nếu chưa có. Trả ms nạp; `nil` khi đã nạp sẵn.
    @discardableResult
    func prepare(voice: VttsVoice) async throws -> Double? {
        try await onQueue { try self.loadHandle(voice).loadMs }
    }

    /// Tổng hợp một đoạn. Task bị huỷ ⇒ C dừng trước chunk front-end kế tiếp và hàm ném `CancellationError`.
    func synthesize(text: String, voice: VttsVoice, lengthScale: Float) async throws -> Output {
        let cancel = CancelToken()
        return try await withTaskCancellationHandler {
            try await onQueue {
                try self.runSynthesis(text: text, voice: voice, lengthScale: lengthScale, cancel: cancel)
            }
        } onCancel: {
            cancel.request()
        }
    }

    /// Nhả mọi handle. Không chặn (gọi được từ main): việc nhả xếp sau lượt đang chạy trên hàng đợi.
    func releaseAll() {
        queue.async { [self] in
            guard !handles.isEmpty else { return }
            let names = handles.keys.map(\.rawValue).sorted().joined(separator: ", ")
            for handle in handles.values {
                vtts_bridge_destroy(handle)
            }
            handles.removeAll()
            AppLogger.shared.log("🗣️ [Vtts] Đã nhả runtime (\(names))")
        }
    }

    // MARK: - Trên hàng đợi

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result(catching: work))
            }
        }
    }

    private func loadHandle(_ voice: VttsVoice) throws -> (handle: OpaquePointer, loadMs: Double?) {
        if let existing = handles[voice] { return (existing, nil) }
        guard let modelURL = Self.modelURL(for: voice), let lexiconURL = Self.lexiconURL else {
            AppLogger.shared.log("❌ [Vtts] Thiếu tài sản trong bundle (\(Self.assetSubdirectory)/\(voice.modelFileName) hoặc \(Self.lexiconFileName))")
            throw Failure.missingAssets
        }
        let started = ProcessInfo.processInfo.systemUptime
        var code: Int32 = 0
        guard let handle = vtts_bridge_create(modelURL.path, lexiconURL.path, &code) else {
            let name = Self.errorName(code)
            AppLogger.shared.log("❌ [Vtts] Nạp giọng \(voice.rawValue) lỗi \(code) \(name) (\(voice.modelFileName))")
            throw Failure.loadFailed(voice: voice.rawValue, code: code, name: name)
        }
        handles[voice] = handle
        let loadMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let tokenSet = String(cString: vtts_bridge_token_set_name(handle))
        AppLogger.shared.log(
            "🗣️ [Vtts] Nạp giọng \(voice.rawValue): bộ token \(tokenSet), \(vtts_bridge_sample_rate(handle)) Hz, "
                + String(format: "%.0f ms", loadMs) + " — \(ProcessMemoryProbe.snapshot().summary)"
        )
        return (handle, loadMs)
    }

    private func runSynthesis(text: String, voice: VttsVoice, lengthScale: Float, cancel: CancelToken) throws -> Output {
        let handle = try loadHandle(voice).handle
        let started = ProcessInfo.processInfo.systemUptime
        var pcm: UnsafeMutablePointer<Float>?
        var count = 0
        let code = text.withCString { cText in
            vtts_bridge_synthesize_cancellable(handle, cText, lengthScale, cancel.pointer, &pcm, &count)
        }
        defer { vtts_bridge_free_pcm(pcm) }
        let runMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        if code == VTTS_BRIDGE_ERR_CANCELLED { throw CancellationError() }
        guard code == VTTS_BRIDGE_OK else {
            let name = Self.errorName(code)
            let vttsError = vtts_bridge_last_vtts_error(handle)
            AppLogger.shared.log(
                "❌ [Vtts] Tổng hợp lỗi \(code) \(name) (mã vtts \(vttsError)), giọng \(voice.rawValue), \(text.count) ký tự"
            )
            throw Failure.synthesisFailed(code: code, name: name, vttsError: vttsError)
        }
        var samples: [Float] = []
        if let pcm, count > 0 {
            samples = Array(UnsafeBufferPointer(start: pcm, count: count))
        }
        return Output(
            samples: samples,
            sampleRate: Int(vtts_bridge_sample_rate(handle)),
            chunkCount: Int(vtts_bridge_last_chunk_count(handle)),
            runMs: runMs
        )
    }

    private static func errorName(_ code: Int32) -> String {
        String(cString: vtts_bridge_error_name(code))
    }

    /// Thẻ huỷ C của **một** lượt. `request()` gọi được từ luồng bất kỳ (ghi nguyên tử bên C); C đọc thẻ trước mỗi chunk.
    private final class CancelToken: @unchecked Sendable {
        let pointer: OpaquePointer?

        init() {
            pointer = vtts_bridge_cancel_create()
        }

        func request() {
            vtts_bridge_cancel_request(pointer)
        }

        deinit {
            vtts_bridge_cancel_destroy(pointer)
        }
    }
}
