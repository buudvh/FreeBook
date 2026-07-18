import Foundation
import UIKit

public final class ImageCacheManager {
    public static let shared = ImageCacheManager()
    
    private let fileManager = FileManager.default
    
    private var coversDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let directoryURL = documentsDirectory.appendingPathComponent("Covers", isDirectory: true)
        
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return directoryURL
    }
    
    private func getFileName(for bookId: String) -> String {
        // Sanitize bookId to be a safe filename by replacing non-alphanumeric characters with underscores
        let safeName = bookId.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return "\(safeName).jpg"
    }
    
    public func localCoverURL(for bookId: String) -> URL {
        return coversDirectory.appendingPathComponent(getFileName(for: bookId))
    }
    
    public func hasLocalCover(for bookId: String) -> Bool {
        let path = localCoverURL(for: bookId).path
        return fileManager.fileExists(atPath: path)
    }
    
    public func loadLocalCover(for bookId: String) -> UIImage? {
        let path = localCoverURL(for: bookId).path
        guard fileManager.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }
    
    public func downloadAndSaveCover(urlStr: String, bookId: String, completion: @escaping (UIImage?) -> Void = { _ in }) {
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        
        let destinationURL = localCoverURL(for: bookId)
        
        // Nếu đã tồn tại file local thì nạp trực tiếp và trả về, không tải lại
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let image = UIImage(contentsOfFile: destinationURL.path) {
                completion(image)
                return
            }
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Nén ảnh JPEG ở mức chất lượng 80% để tiết kiệm tài nguyên bộ nhớ
            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                do {
                    try jpegData.write(to: destinationURL)
                    AppLogger.shared.log("💾 Đã tải và lưu ảnh bìa offline thành công cho sách: \(bookId)")
                    DispatchQueue.main.async { completion(image) }
                } catch {
                    AppLogger.shared.log("❌ Lỗi ghi tệp ảnh bìa local: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
