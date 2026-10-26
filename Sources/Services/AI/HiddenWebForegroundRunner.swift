import Foundation

/// Chạy một lượt quét tên riêng qua WKWebView ẩn **tạm dừng khi app ở nền**, gửi lại khi app mở lại (1.3.602; dùng
/// chung cho Gemini Web và Chế độ AI của Google từ 1.3.609 — chuyển nguyên văn từ `GeminiWebClient+NameScan`, hành vi
/// Gemini Web không đổi).
///
/// Log máy thật 21–26/10: ~30 lượt quét lỗi `StreamGenerate lỗi sau ~150 000 ms, chunk=0` — **tất cả** lúc app ở nền
/// (TTS giữ app sống nhưng iOS tạm dừng tiến trình web của WKWebView ẩn, `fetch()` trong trang đứng im), mỗi lượt phí
/// trọn idle timeout 150 s. Ở đây:
/// - trước khi gửi: chờ app ở trước (`GeminiWebForegroundGate`); vừa chờ xong thì nghỉ 2 s cho trang kịp thức dậy;
/// - app vào nền khi lượt đang chạy: huỷ lượt (huỷ luôn việc đang chạy trong trang) — chờ app mở lại rồi gửi lại **đúng
///   lượt đó**;
/// - lượt ném lỗi mà app đã vào nền trong lúc chạy (vd. "Load failed" ngay sau khi mở lại) cũng tính là bị gián đoạn;
/// - tối đa 3 lần gửi lại mỗi lượt, quá thì ném lỗi của lần cuối (hoặc `exhaustedError`);
/// - lỗi làm dừng cả lần quét (`shouldStop`: hạn mức/tài khoản/captcha…) thì không bao giờ gửi lại dù app đã vào nền.
///
/// Bị gián đoạn **không bao giờ** nổi lên thành `CancellationError`: `AINameExtractionBatchProcessor.runTurns` coi lỗi
/// đó là người dùng bấm Dừng và dừng cả lần quét. Chỉ khi task ngoài bị huỷ thật mới ném `CancellationError`.
enum HiddenWebForegroundRunner {
    private static let maxBackgroundResends = 3
    /// App vừa mở lại thì nghỉ chút rồi mới gửi: tiến trình web và mạng cần thời gian thức dậy (log thật: fetch cũ báo
    /// "Load failed" 3 s sau khi mở lại app).
    private static let resumeSettleDelay: UInt64 = 2_000_000_000

    /// `logTag` dạng `"[GeminiWeb]"` — giữ nguyên chuỗi log cũ của từng provider.
    static func run<Value: Sendable>(
        logTag: String,
        shouldStop: @escaping @Sendable (Error) -> Bool,
        exhaustedError: Error,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let gate = GeminiWebForegroundGate.shared
        await gate.installIfNeeded()
        var resends = 0
        while true {
            let wasInBackground = gate.isInBackground
            if wasInBackground {
                AppLogger.shared.log("🤖 \(logTag) Quét tên riêng: app ở nền — tạm dừng lượt, chờ mở lại app")
            }
            // Người dùng bấm Dừng lúc đang chờ ⇒ `CancellationError` (huỷ thật) — để nổi lên.
            let epoch = try await gate.waitUntilForeground()
            if wasInBackground || resends > 0 {
                try await Task.sleep(nanoseconds: resumeSettleDelay)
                // Lại vào nền trong lúc nghỉ: chưa gửi gì ⇒ chờ tiếp, không tính là một lần gửi lại.
                if gate.hasEnteredBackground(since: epoch) { continue }
                let what = resends > 0 ? "lại lượt bị gián đoạn (lần \(resends)/\(maxBackgroundResends))" : "lượt"
                AppLogger.shared.log("🤖 \(logTag) Quét tên riêng: app đã mở lại — gửi \(what)")
            }

            let attempt = await race(operation, againstBackgroundSince: epoch, gate: gate)
            // Task ngoài bị huỷ = người dùng bấm Dừng — huỷ thật, bất kể nhánh nào xong trước.
            try Task.checkCancellation()
            let lastError: Error?
            switch attempt {
            case .finished(let value):
                return value
            case .failed(let error) where !gate.hasEnteredBackground(since: epoch):
                throw error
            case .failed(let error) where shouldStop(error):
                // Hết hạn mức / chặn IP / mất đăng nhập / captcha: gửi lại chỉ làm bị chặn nặng hơn, dù app đã vào nền
                // trong lúc chạy — để vòng lượt dừng cả lần quét như mọi lần gặp lỗi này.
                throw error
            case .failed(let error):
                lastError = error
                AppLogger.shared.log("🤖 \(logTag) Quét tên riêng: lượt lỗi (\(error.localizedDescription)) mà app đã vào nền trong lúc chạy — coi là bị gián đoạn, gửi lại khi app mở lại")
            case .backgrounded:
                lastError = nil
                AppLogger.shared.log("🤖 \(logTag) Quét tên riêng: app vào nền khi lượt đang chạy — huỷ lượt (cả fetch trong trang), gửi lại khi app mở lại")
            }
            resends += 1
            guard resends <= maxBackgroundResends else {
                AppLogger.shared.log("❌ 🤖 \(logTag) Quét tên riêng: lượt bị app vào nền cắt quá \(maxBackgroundResends) lần — bỏ lượt này \(gate.appStateLabel)")
                if let lastError, !(lastError is CancellationError) { throw lastError }
                throw exhaustedError
            }
        }
    }

    /// Chạy `operation` song song với nhánh chờ app vào nền; nhánh nào xong trước thì huỷ nhánh kia. App vào nền trước
    /// ⇒ `.backgrounded` và **bỏ** kết quả của `operation` (bị huỷ thì `sendConversation`/`sendChat` của Gemini Web trả
    /// về phần chữ dở như thành công, vì stream bị huỷ kết thúc êm chứ không ném).
    private static func race<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value,
        againstBackgroundSince epoch: Int,
        gate: GeminiWebForegroundGate
    ) async -> Attempt<Value> {
        await withTaskGroup(of: Attempt<Value>?.self, returning: Attempt<Value>.self) { group in
            group.addTask {
                do {
                    let value = try await operation()
                    return .finished(value)
                } catch {
                    return .failed(error)
                }
            }
            group.addTask {
                do {
                    try await gate.waitForBackground(after: epoch)
                    return .backgrounded
                } catch {
                    return nil // Bị huỷ: lượt xong trước, hoặc người dùng bấm Dừng.
                }
            }
            // Nhánh gửi luôn trả về một kết quả khác `nil` nên vòng này luôn gán `outcome`.
            var outcome: Attempt<Value>?
            for await case let result? in group {
                outcome = result
                break
            }
            group.cancelAll()
            return outcome ?? .backgrounded
        }
    }

    /// Kết quả một lần gửi trong `race`.
    private enum Attempt<Value: Sendable>: Sendable {
        case finished(Value)
        case failed(Error)
        case backgrounded
    }
}
