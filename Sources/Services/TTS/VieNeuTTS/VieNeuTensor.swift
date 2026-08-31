import Foundation
import OnnxRuntimeBindings

/// Cặp `(NSMutableData, ORTValue)` giữ chung tuổi thọ.
///
/// `ORTValue(tensorData:elementType:shape:)` **bọc con trỏ** của `NSMutableData` chứ không giữ
/// tham chiếu tới nó. Nếu buffer bị giải phóng trước khi `run` xong thì ONNX Runtime đọc vào bộ
/// nhớ đã thu hồi — biểu hiện là crash ngẫu nhiên hoặc, tệ hơn, âm thanh sai mà không có lỗi nào.
/// Bọc cả hai vào một giá trị là cách để trình biên dịch giữ buffer sống đúng bằng vòng đời tensor.
struct VieNeuTensor {
    /// Giữ tham chiếu — không được xoá dù trông như không dùng.
    let buffer: NSMutableData
    let value: ORTValue

    private init(buffer: NSMutableData, elementType: ORTTensorElementDataType, shape: [NSNumber]) throws {
        self.buffer = buffer
        self.value = try ORTValue(tensorData: buffer, elementType: elementType, shape: shape)
    }

    static func float(_ values: [Float], shape: [NSNumber]) throws -> VieNeuTensor {
        let data = values.withUnsafeBufferPointer { pointer -> NSMutableData in
            guard let base = pointer.baseAddress else { return NSMutableData() }
            return NSMutableData(bytes: base, length: pointer.count * MemoryLayout<Float>.size)
        }
        return try VieNeuTensor(buffer: data, elementType: .float, shape: shape)
    }

    static func int64(_ values: [Int64], shape: [NSNumber]) throws -> VieNeuTensor {
        let data = values.withUnsafeBufferPointer { pointer -> NSMutableData in
            guard let base = pointer.baseAddress else { return NSMutableData() }
            return NSMutableData(bytes: base, length: pointer.count * MemoryLayout<Int64>.size)
        }
        return try VieNeuTensor(buffer: data, elementType: .int64, shape: shape)
    }

    static func int32(_ values: [Int32], shape: [NSNumber]) throws -> VieNeuTensor {
        let data = values.withUnsafeBufferPointer { pointer -> NSMutableData in
            guard let base = pointer.baseAddress else { return NSMutableData() }
            return NSMutableData(bytes: base, length: pointer.count * MemoryLayout<Int32>.size)
        }
        return try VieNeuTensor(buffer: data, elementType: .int32, shape: shape)
    }

    /// Tensor `float` rỗng — dùng cho KV cache ban đầu của acoustic decoder, shape
    /// `[1, heads, 0, headDim]`. Chiều 0 là hợp lệ trong ONNX và là cách graph biết "chưa có cache".
    static func emptyFloat(shape: [NSNumber]) throws -> VieNeuTensor {
        try VieNeuTensor(buffer: NSMutableData(), elementType: .float, shape: shape)
    }

    /// Đọc output `float` của ORT thành `[Float]`.
    ///
    /// `tensorData()` **copy** — đó là lý do hàm này chỉ được dùng cho hidden state (768 float),
    /// không bao giờ cho KV cache. KV cache phải truyền thẳng `ORTValue` output sang input bước sau;
    /// ở `T = 300` một lượt copy cả cache là ~12 MB, 12.5 lần mỗi giây.
    static func floatArray(from value: ORTValue, expectedCount: Int) throws -> [Float] {
        let data = try value.tensorData() as Data
        let expectedBytes = expectedCount * MemoryLayout<Float>.size
        guard data.count >= expectedBytes else {
            throw TTSError.internalError(
                "Output tensor có \(data.count) byte, cần ít nhất \(expectedBytes)"
            )
        }
        var output = [Float](repeating: 0, count: expectedCount)
        _ = output.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination, from: 0..<expectedBytes)
        }
        return output
    }
}
