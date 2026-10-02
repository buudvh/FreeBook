import Foundation

/// Chọn bucket Core ML theo số frame `T` của một chunk.
///
/// Lưới bucket đã chốt ở Phase 1: `T ∈ {64, 96, 234}` (xem `Scripts/coreml_bucket_package.py:
/// BUCKET_FRAMES`). Với `VieNeuConfig.maxChunkSeconds = 15,0` thì `T ≤ round(15 × 15,625) = 234`,
/// nên bucket lớn nhất **không thể tràn** — không cần guard chia đoạn.
///
/// Hàm này dùng ở Phase 4 để chọn gói `vector_estimator-T{n}` / `codec_decoder-T{n}` tương ứng,
/// **không** đổi `splitIntoChunks` (tách văn bản vẫn theo `maxChunkCharacters`).
enum VieNeuBucketSelector {
    /// Các mức frame của lưới bucket — phải khớp `Scripts/coreml_bucket_package.py:BUCKET_FRAMES`
    /// và `VieNeuModelStore.coreMLPackageNames`.
    static let bucketFrames: [Int] = [64, 96, 234]

    /// Hậu tố gói Core ML cho một số frame: `-T64` / `-T96` / `-T234`.
    ///
    /// Chọn mức **nhỏ nhất** `≥ frames`; nếu vượt mức lớn nhất (không nên xảy ra vì `maxChunkSeconds`)
    /// thì dùng mức lớn nhất.
    static func packageSuffix(for frames: Int) -> String {
        let bucket = bucketFrames.first { $0 >= frames } ?? bucketFrames.last ?? 234
        return "-T\(bucket)"
    }

    /// Chỉ số bucket (vào `bucketFrames`) cho một số frame — tiện cho debug/log.
    static func bucketIndex(for frames: Int) -> Int {
        let bucket = bucketFrames.first { $0 >= frames } ?? bucketFrames.last ?? 234
        return bucketFrames.firstIndex(of: bucket) ?? bucketFrames.count - 1
    }
}
