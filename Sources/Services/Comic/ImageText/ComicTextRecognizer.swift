import CoreGraphics
import Foundation
import Vision

/// Nhận chữ Trung trên một ảnh truyện tranh bằng Vision, chạy hoàn toàn trên máy (dịch ảnh, 1.3.826).
///
/// - Ảnh dải webtoon rất cao bị cắt thành **lát** cao ≤ `tileHeightRatio` × bề ngang, chồng nhau `tileOverlapRatio`, để chữ
///   nhỏ không bị bỏ sót khi Vision thu ảnh về cỡ xử lý. Mỗi lát có một vùng "lõi" (ranh giới ở giữa phần chồng); dòng chỉ
///   được giữ ở lát mà tâm dòng rơi vào lõi ⇒ dòng nằm ở phần chồng không bị đếm hai lần.
/// - Mỗi lúc **một** ảnh (hàng chờ như slot request của `ComicImageLoader`): Neural Engine/GPU dùng chung với TTS và giải mã
///   ảnh. Hàng cuộn khỏi màn ⇒ task bị huỷ ⇒ rời hàng chờ, hoặc `cancel()` request Vision đang chạy.
/// - Các hằng `tile*`, `minimumTextHeight`, `minimumConfidence` là **giá trị khởi điểm chưa thử trên máy** — chỉnh xong thì tăng
///   `ComicTextPage.currentSchemaVersion` để bỏ kết quả cũ.
actor ComicTextRecognizer {
    static let shared = ComicTextRecognizer()

    /// Một dòng Vision trả về: khung chuẩn hoá theo **cả ảnh**, gốc trên-trái.
    struct Line: Sendable {
        let rect: CGRect
        let text: String
        let confidence: Float
    }

    static let tileHeightRatio: CGFloat = 1.5
    static let tileOverlapRatio: CGFloat = 0.12
    /// Chiều cao chữ tối thiểu, tương đối với chiều cao **lát**. Đặt tường minh, không dựa giá trị mặc định của Vision.
    static let minimumTextHeight: Float = 0.012
    static let minimumConfidence: Float = 0.3
    static let recognitionLanguages = ["zh-Hans", "zh-Hant"]

    private static let workQueue = DispatchQueue(label: "com.tangcongcac.comic-text-recognizer", qos: .userInitiated)

    /// Bọc request để `onCancel` (closure `@Sendable`) gọi được `cancel()`.
    private final class RequestBox: @unchecked Sendable {
        let request: VNRecognizeTextRequest

        init(_ request: VNRecognizeTextRequest) {
            self.request = request
        }
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    /// Một lát: hàng điểm ảnh `top ..< top + height`; dòng có tâm (theo điểm ảnh của cả ảnh) trong `coreStart ..< coreEnd`.
    private struct Tile {
        let top: Int
        let height: Int
        let coreStart: CGFloat
        let coreEnd: CGFloat
    }

    private var isBusy = false
    private var waiters: [Waiter] = []
    private var hasLoggedLanguages = false

    // MARK: - API

    /// Các dòng chữ trên `image`, theo thứ tự lát (trên xuống). Ném `CancellationError` khi task bị huỷ.
    func recognizeLines(in image: CGImage) async throws -> [Line] {
        try await acquireSlot()
        do {
            try Task.checkCancellation()
            logSupportedLanguagesOnce()
            let lines = try await recognize(image)
            releaseSlot()
            return lines
        } catch {
            releaseSlot()
            throw error
        }
    }

    // MARK: - Nhận chữ

    private nonisolated func recognize(_ image: CGImage) async throws -> [Line] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }
        // Lát rộng bằng cả ảnh ⇒ x / bề ngang chuẩn hoá của Vision dùng thẳng được; chỉ trục dọc phải quy đổi.
        let fullHeight = CGFloat(height)

        var lines: [Line] = []
        for tile in Self.tiles(width: width, height: height) {
            try Task.checkCancellation()
            guard let crop = image.cropping(to: CGRect(x: 0, y: tile.top, width: width, height: tile.height)) else { continue }
            let observations: [VNRecognizedTextObservation]
            do {
                observations = try await perform(on: crop)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
            let tileHeight = CGFloat(crop.height)
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= Self.minimumConfidence else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // Vision: chuẩn hoá theo lát, gốc dưới-trái ⇒ điểm ảnh của cả ảnh, gốc trên-trái.
                let box = observation.boundingBox
                let pixelY = CGFloat(tile.top) + (1 - box.maxY) * tileHeight
                let pixelHeight = box.height * tileHeight
                let centerY = pixelY + pixelHeight / 2
                guard centerY >= tile.coreStart, centerY < tile.coreEnd else { continue }
                lines.append(Line(
                    rect: CGRect(
                        x: box.minX,
                        y: pixelY / fullHeight,
                        width: box.width,
                        height: pixelHeight / fullHeight
                    ),
                    text: text,
                    confidence: candidate.confidence
                ))
            }
        }
        return lines
    }

    /// Chạy một `VNRecognizeTextRequest` trên `workQueue` (Vision chặn luồng gọi tới khi xong).
    private nonisolated func perform(on image: CGImage) async throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Self.recognitionLanguages
        request.usesLanguageCorrection = true
        request.minimumTextHeight = Self.minimumTextHeight
        let box = RequestBox(request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[VNRecognizedTextObservation], Error>) in
                Self.workQueue.async {
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    do {
                        try handler.perform([box.request])
                        continuation.resume(returning: box.request.results ?? [])
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            box.request.cancel()
        }
    }

    /// Ảnh thấp hơn một lát ⇒ một lát. Lát cuối luôn chạm đáy ảnh (bước cuối có thể ngắn hơn); ranh giới lõi giữa hai lát kề
    /// nhau là điểm giữa phần chồng của chúng, nên các lõi nối liền nhau phủ đủ cả ảnh.
    private static func tiles(width: Int, height: Int) -> [Tile] {
        let tileHeight = min(height, max(1, Int((CGFloat(width) * tileHeightRatio).rounded())))
        guard tileHeight < height else {
            return [Tile(top: 0, height: height, coreStart: 0, coreEnd: CGFloat(height) + 1)]
        }
        let overlap = max(1, Int((CGFloat(tileHeight) * tileOverlapRatio).rounded()))
        let step = max(1, tileHeight - overlap)
        var tops: [Int] = []
        var top = 0
        while top + tileHeight < height {
            tops.append(top)
            top += step
        }
        tops.append(height - tileHeight)

        var result: [Tile] = []
        result.reserveCapacity(tops.count)
        for (index, top) in tops.enumerated() {
            let start: CGFloat = index == 0
                ? 0
                : (CGFloat(tops[index - 1] + tileHeight) + CGFloat(top)) / 2
            let end: CGFloat = index == tops.count - 1
                ? CGFloat(height) + 1
                : (CGFloat(top + tileHeight) + CGFloat(tops[index + 1])) / 2
            result.append(Tile(top: top, height: tileHeight, coreStart: start, coreEnd: end))
        }
        return result
    }

    /// Ghi một lần mỗi tiến trình: máy có đủ ngôn ngữ nhận chữ không (danh sách thật trên máy — chưa kiểm được lúc viết).
    private func logSupportedLanguagesOnce() {
        guard !hasLoggedLanguages else { return }
        hasLoggedLanguages = true
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        let supported = (try? probe.supportedRecognitionLanguages()) ?? []
        let missing = Self.recognitionLanguages.filter { !supported.contains($0) }
        if missing.isEmpty {
            AppLogger.shared.log("🈶 [ComicOCR] Vision có \(Self.recognitionLanguages.joined(separator: ", "))")
        } else {
            AppLogger.shared.log("❌ [ComicOCR] Vision trên máy này thiếu \(missing.joined(separator: ", ")); có: \(supported.joined(separator: ", "))")
        }
    }

    // MARK: - Mỗi lúc một ảnh

    private func acquireSlot() async throws {
        try Task.checkCancellation()
        if !isBusy {
            isBusy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Trao lượt thẳng cho người chờ đầu hàng (giữ `isBusy`) hoặc trả lượt.
    private func releaseSlot() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
