import Foundation

/// Polyfill JS cho `Graphics` (extension-api.md, mục "Graphics") — gọi xuống các block `_nativeGraphics*`
/// do `JSGraphicsBridge.install(in:)` cài. Nạp sau bridge trong `JSExecutor`.
///
/// ```js
/// let canvas = Graphics.createCanvas(800, 600);
/// let image = Graphics.createImage(base64String);  // ảnh lỗi ⇒ undefined (hành vi iOS của app gốc)
/// canvas.drawImage(image, dx, dy);                  // 3 / 5 (6 coi như 5) / 9 tham số như canvas HTML
/// let png = canvas.capture();                       // PNG base64; canvas bị giải phóng
/// ```
enum JSGraphicsBootstrapScript {
    /// Chuỗi JS, `evaluateScript` ngay sau `JSGraphicsBridge.install(in:)`.
    static let source = """
    var Graphics = {
        createImage: function(base64) {
            var input = (base64 === null || base64 === undefined) ? "" : String(base64);
            var info = _nativeGraphicsCreateImage(input);
            if (!info || !info.id) {
                return undefined;
            }
            return { __fbGraphicsImageId: info.id, width: info.width, height: info.height };
        },
        createCanvas: function(width, height) {
            var info = _nativeGraphicsCreateCanvas(Number(width), Number(height));
            var canvasId = (info && info.id) ? info.id : 0;
            return {
                width: info ? info.width : 0,
                height: info ? info.height : 0,
                drawImage: function(image) {
                    if (!canvasId || !image || !image.__fbGraphicsImageId) {
                        return;
                    }
                    var numbers = [];
                    for (var i = 1; i < arguments.length; i++) {
                        numbers.push(Number(arguments[i]));
                    }
                    _nativeGraphicsDrawImage(canvasId, image.__fbGraphicsImageId, numbers);
                },
                capture: function() {
                    if (!canvasId) {
                        return "";
                    }
                    var output = _nativeGraphicsCapture(canvasId);
                    canvasId = 0;
                    return output || "";
                }
            };
        }
    };
    """
}
