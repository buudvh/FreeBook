import Foundation

/// Nơi app tải model LAC (bộ nhận diện tên của "Lọc name local"): kho Hugging Face `datasets/raikiri1498/vietpharse`
/// của anh Bửu, thư mục `lac/` — bản đổi định dạng của LAC 2.1.2 (Baidu, Apache-2.0), sinh bằng
/// `Tools/lac-export/export_lac.py`. README của kho ghi nguồn, giấy phép, sha256 từng file và đặc tả thuật toán.
///
/// Ghim **commit** như `VieNeuModelMirror`: URL có sha là bất biến. Chỉ sha của `lac_manifest.json` ghim trong code;
/// manifest ghim tiếp kích thước + sha256 của mọi file còn lại. Đổi file trong kho ⇒ đổi `revision`, `manifestSHA256`,
/// `manifestByteCount` cùng lúc (máy đã cài bản cũ thấy manifest lệch ⇒ tải lại).
enum LACModelMirror {
    static let repository = "raikiri1498/vietpharse"
    /// Commit của kho có đủ thư mục `lac/` (2026-11-27).
    static let revision = "73bb76d492d03f730b1aee1c6fade62d5eedf08c"
    static let directory = "lac"

    static let manifestName = "lac_manifest.json"
    /// sha256 + kích thước `lac/lac_manifest.json` @ `revision` (bảng file trong README của kho).
    static let manifestSHA256 = "420a38e129c8257169a794fad25204b97158001932c2cf34fa7c297f15d5f693"
    static let manifestByteCount: Int64 = 3_773

    static let weightsName = "lac_weights.bin"
    static let wordDictionaryName = "word.dic"
    static let tagDictionaryName = "tag.dic"
    static let replaceDictionaryName = "q2b.dic"
    static let segmentDictionaryName = "small_seg.dic"
    static let goldenName = "lac_golden.json"

    /// File app cần ngoài manifest (~19 MB), theo thứ tự tải. Không tải `README.md` / `LICENSE` (giấy phép nằm trong
    /// repo app ở `Docs/ThirdParty/LAC-LICENSE.txt`).
    static let dataFileNames = [
        weightsName, wordDictionaryName, tagDictionaryName, replaceDictionaryName, segmentDictionaryName, goldenName
    ]

    static func url(for name: String) -> URL? {
        URL(string: "https://huggingface.co/datasets/\(repository)/resolve/\(revision)/\(directory)/\(name)")
    }
}
