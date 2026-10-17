import Foundation
import JavaScriptCore
import CoreGraphics
import ImageIO

/// Phần native của `Graphics` (VBook extension-api.md, mục "Graphics"): giải mã ảnh, vẽ lên canvas, xuất PNG.
/// Polyfill JS ở `JSGraphicsBootstrapScript`; script ảnh comic (cuutruyen ráp tile) là người dùng chính.
///
/// - Handle là số nguyên trong bảng của **một** bridge; bridge do các block `_nativeGraphics*` giữ, các block do
///   `JSContext` giữ ⇒ handle sống đúng bằng executor. Bridge không giữ `JSContext` nên không tạo vòng tham chiếu.
/// - Toạ độ theo canvas HTML: gốc trên-trái, làm tròn về pixel nguyên. Canvas tối đa 8192×8192 điểm ảnh (tính theo diện tích).
/// - `capture()` giải phóng canvas; `_nativeGraphicsReset()` xoá mọi handle (runner script ảnh gọi quanh mỗi lượt).
final class JSGraphicsBridge: @unchecked Sendable {
    /// Trần bộ nhớ một canvas: 8192×8192 điểm ảnh (~256 MB RGBA). Tính theo **diện tích** chứ không theo từng cạnh:
    /// cuutruyen dựng canvas bằng đúng cỡ ảnh gốc, chặn cạnh 8192 sẽ cắt mất đáy trang webtoon hẹp mà dài.
    static let maxCanvasPixels = 8192 * 8192
    /// Cạnh dài nhất cho phép của bitmap.
    static let maxCanvasSide = 32_768

    private let lock = NSLock()
    private var images: [Int: CGImage] = [:]
    private var canvases: [Int: CGContext] = [:]
    private var nextHandle = 0

    /// Cài các block `_nativeGraphics*` vào `context`. Gọi một lần cho mỗi `JSExecutor`.
    static func install(in context: JSContext) {
        let bridge = JSGraphicsBridge()

        let createImageBlock: @convention(block) (JSValue?) -> [String: Any] = { value in
            let base64 = (value.map { $0.isUndefined || $0.isNull ? "" : ($0.toString() ?? "") }) ?? ""
            return bridge.createImage(base64: base64)
        }
        context.setObject(createImageBlock, forKeyedSubscript: "_nativeGraphicsCreateImage" as NSCopying & NSObjectProtocol)

        let createCanvasBlock: @convention(block) (Double, Double) -> [String: Any] = { width, height in
            bridge.createCanvas(width: width, height: height)
        }
        context.setObject(createCanvasBlock, forKeyedSubscript: "_nativeGraphicsCreateCanvas" as NSCopying & NSObjectProtocol)

        let drawImageBlock: @convention(block) (Int, Int, JSValue?) -> Void = { canvasId, imageId, argsValue in
            bridge.drawImage(canvasId: canvasId, imageId: imageId, arguments: JSGraphicsBridge.numbers(from: argsValue))
        }
        context.setObject(drawImageBlock, forKeyedSubscript: "_nativeGraphicsDrawImage" as NSCopying & NSObjectProtocol)

        let captureBlock: @convention(block) (Int) -> String = { canvasId in
            bridge.capture(canvasId: canvasId)
        }
        context.setObject(captureBlock, forKeyedSubscript: "_nativeGraphicsCapture" as NSCopying & NSObjectProtocol)

        let resetBlock: @convention(block) () -> Void = {
            bridge.reset()
        }
        context.setObject(resetBlock, forKeyedSubscript: "_nativeGraphicsReset" as NSCopying & NSObjectProtocol)
    }

    // MARK: - Ảnh

    /// `{id, width, height}`; `id == 0` khi base64 không phải ảnh (wrapper JS trả `undefined`, đúng hành vi iOS của VBook).
    private func createImage(base64: String) -> [String: Any] {
        // Chấp nhận cả URI `data:…;base64,…` cho dễ tính, dù hợp đồng chỉ nói base64 trần.
        var payload = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.lowercased().hasPrefix("data:"), let comma = payload.firstIndex(of: ",") {
            payload = String(payload[payload.index(after: comma)...])
        }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters), !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return ["id": 0, "width": 0, "height": 0]
        }
        lock.lock()
        nextHandle += 1
        let handle = nextHandle
        images[handle] = image
        lock.unlock()
        return ["id": handle, "width": image.width, "height": image.height]
    }

    // MARK: - Canvas

    private func createCanvas(width: Double, height: Double) -> [String: Any] {
        guard width.isFinite, height.isFinite else { return ["id": 0, "width": 0, "height": 0] }
        // Kẹp trên `Double` trước khi đổi sang `Int` (số JS quá lớn làm `Int(_:)` trap).
        let pixelWidth = Int(min(max(width.rounded(), 1), Double(Self.maxCanvasSide)))
        var pixelHeight = Int(min(max(height.rounded(), 1), Double(Self.maxCanvasSide)))
        if pixelWidth * pixelHeight > Self.maxCanvasPixels {
            pixelHeight = max(1, Self.maxCanvasPixels / pixelWidth)
        }
        guard let canvas = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            AppLogger.shared.log("❌ [Graphics] Không tạo được canvas \(pixelWidth)x\(pixelHeight)")
            return ["id": 0, "width": 0, "height": 0]
        }
        canvas.interpolationQuality = .high

        lock.lock()
        nextHandle += 1
        let handle = nextHandle
        canvases[handle] = canvas
        lock.unlock()
        return ["id": handle, "width": pixelWidth, "height": pixelHeight]
    }

    /// `arguments` là các số sau `img`: 2 → (dx, dy) cỡ gốc; 4 hoặc 5 → (dx, dy, dw, dh) (số thứ 5 bỏ qua);
    /// 8 → (sx, sy, sw, sh, dx, dy, dw, dh). Số lượng khác: không vẽ gì (đúng extension-api.md).
    private func drawImage(canvasId: Int, imageId: Int, arguments: [Double]) {
        lock.lock()
        let canvas = canvases[canvasId]
        let image = images[imageId]
        lock.unlock()
        guard let canvas, let image else { return }
        guard arguments.allSatisfy({ $0.isFinite }) else { return }

        let values = arguments.map { CGFloat($0.rounded()) }
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var sourceRect = imageBounds
        let destinationRect: CGRect
        switch values.count {
        case 2:
            destinationRect = CGRect(x: values[0], y: values[1], width: imageBounds.width, height: imageBounds.height)
        case 4, 5:
            destinationRect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        case 8:
            sourceRect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            destinationRect = CGRect(x: values[4], y: values[5], width: values[6], height: values[7])
        default:
            return
        }

        // Canvas HTML chuẩn hoá hình chữ nhật âm, rồi cắt phần nguồn nằm ngoài ảnh và co đích theo cùng tỉ lệ.
        let source = sourceRect.standardized
        let destination = destinationRect.standardized
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else { return }
        let clipped = source.intersection(imageBounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return }

        let scaleX = destination.width / source.width
        let scaleY = destination.height / source.height
        let target = CGRect(
            x: destination.minX + (clipped.minX - source.minX) * scaleX,
            y: destination.minY + (clipped.minY - source.minY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        )

        // `CGImage.cropping(to:)` dùng toạ độ ảnh gốc trên-trái — khớp thẳng với `sx, sy`.
        guard let piece = clipped == imageBounds ? image : image.cropping(to: clipped) else { return }

        // Bitmap context của CoreGraphics có gốc dưới-trái và vẽ ảnh đúng chiều: chỉ cần lật trục y của khung đích.
        let flipped = CGRect(
            x: target.minX,
            y: CGFloat(canvas.height) - target.minY - target.height,
            width: target.width,
            height: target.height
        )
        canvas.draw(piece, in: flipped)
    }

    /// PNG base64 của canvas rồi giải phóng canvas đó. Chuỗi rỗng khi handle không còn hoặc mã hoá lỗi.
    private func capture(canvasId: Int) -> String {
        lock.lock()
        let canvas = canvases.removeValue(forKey: canvasId)
        lock.unlock()
        guard let canvas, let image = canvas.makeImage() else { return "" }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else {
            return ""
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            AppLogger.shared.log("❌ [Graphics] Không mã hoá được PNG từ canvas")
            return ""
        }
        return (output as Data).base64EncodedString()
    }

    private func reset() {
        lock.lock()
        images.removeAll()
        canvases.removeAll()
        lock.unlock()
    }

    /// Mảng số JS → `[Double]`. Phần tử không phải số thành NaN để `drawImage` bỏ lượt vẽ.
    private static func numbers(from value: JSValue?) -> [Double] {
        guard let value, value.isArray,
              let lengthValue = value.forProperty("length") else { return [] }
        let count = Int(lengthValue.toInt32())
        guard count > 0, count <= 16 else { return count == 0 ? [] : [Double.nan] }
        return (0..<count).map { index in
            guard let element = value.atIndex(index), element.isNumber else { return Double.nan }
            return element.toDouble()
        }
    }
}
