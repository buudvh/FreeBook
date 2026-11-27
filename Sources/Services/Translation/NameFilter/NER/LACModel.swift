import Foundation

/// Cửa vào duy nhất của model LAC cho bộ lọc name local.
///
/// Lần đầu dùng: tải ~19 MB từ kho Hugging Face ghim commit (`LACModelMirror`, `datasets/raikiri1498/vietpharse`, thư mục
/// `lac/`, commit `73bb76d492d03f730b1aee1c6fade62d5eedf08c`) vào `Application Support/translate/LAC/` (`LACModelStore`,
/// `LACModelDownloader`), kiểm sha256; mỗi lần nạp: kiểm sha256, dựng bộ gán nhãn (`LACTagger`), tự kiểm với
/// `lac_golden.json` (`LACSelfCheck`). Đặc tả thuật toán ở `lac/README.md` của kho đó; giấy phép Apache-2.0 ở
/// `Docs/ThirdParty/LAC-LICENSE.txt`.
enum LACModel {
    /// Đảm bảo model có trên máy (thiếu ⇒ tải, báo `progress(0…1)`), nạp + tự kiểm (báo `progress(nil)`), trả bộ gán nhãn.
    /// Gọi lại khi bộ gán nhãn cũ còn sống ⇒ trả lại nó ngay, không báo gì. Ném `LACModelError` / `CancellationError`.
    static func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws -> any LACTagging {
        try await LACModelGate.shared.tagger(progress: progress)
    }

    /// Một lượt tải (nếu cần) + nạp + tự kiểm. Chỉ `LACModelGate` gọi — nó gộp lượt trùng và giữ bộ gán nhãn yếu.
    ///
    /// File hỏng (sha / kích thước / định dạng) ⇒ xoá thư mục + `invalidFiles` (lần sau tải lại); lỗi **đọc** file thoáng
    /// qua ⇒ `readFailed`, giữ file ("Thử lại" đọc lại). Tự kiểm lệch ⇒
    /// `selfCheckFailed`, **giữ** file: sha đã đúng nên lỗi nằm ở code, tải lại không chữa được.
    static func load(progress: @escaping @Sendable (Double?) -> Void) async throws -> LACTagger {
        let store: LACModelStore
        do {
            store = try LACModelStore()
        } catch {
            AppLogger.shared.log("❌ 🧠 [LAC] Không tạo được thư mục model: \(error.localizedDescription)")
            throw LACModelError.invalidFiles("không tạo được thư mục model")
        }

        if store.installedManifest() == nil {
            let started = Date()
            progress(0)
            do {
                try await LACModelDownloader.install(into: store, progress: { progress($0) })
            } catch is CancellationError {
                AppLogger.shared.log("🧠 [LAC] Huỷ tải model sau \(seconds(since: started)) s")
                throw CancellationError()
            } catch {
                AppLogger.shared.log("❌ 🧠 [LAC] Tải model lỗi sau \(seconds(since: started)) s: "
                    + error.localizedDescription)
                throw error
            }
            AppLogger.shared.log("🧠 [LAC] Tải model xong trong \(seconds(since: started)) s")
        }

        progress(nil)
        try Task.checkCancellation()
        guard let manifest = store.installedManifest() else {
            store.removeAll()
            AppLogger.shared.log("❌ 🧠 [LAC] Model thiếu file sau khi tải — đã xoá để tải lại")
            throw LACModelError.invalidFiles("thiếu file sau khi tải")
        }

        let loadStarted = Date()
        let tagger: LACTagger
        do {
            tagger = try LACTagger.load(from: store, manifest: manifest)
        } catch is CancellationError {
            throw CancellationError()
        } catch LACModelError.readFailed(let why) {
            // Lỗi đọc thoáng qua: giữ file (sha đúng thì tải lại cũng vậy), "Thử lại" đọc lại.
            AppLogger.shared.log("❌ 🧠 [LAC] Nạp model lỗi đọc file — giữ model: \(why)")
            throw LACModelError.readFailed(why)
        } catch let error as LACModelError {
            store.removeAll()
            AppLogger.shared.log("❌ 🧠 [LAC] Nạp model lỗi — đã xoá để tải lại: \(error.errorDescription ?? "")")
            throw error
        } catch {
            // Lỗi khác không do kiểm sha / định dạng (vốn ném `LACModelError`) ⇒ coi như lỗi đọc, giữ file.
            AppLogger.shared.log("❌ 🧠 [LAC] Nạp model lỗi — giữ model: \(error.localizedDescription)")
            throw LACModelError.readFailed(error.localizedDescription)
        }
        AppLogger.shared.log("🧠 [LAC] Nạp model \(milliseconds(since: loadStarted)) ms")

        let checkStarted = Date()
        let summary: LACSelfCheck.Summary
        do {
            let golden = try Data(contentsOf: store.url(for: LACModelMirror.goldenName))
            summary = try LACSelfCheck.run(tagger, golden: golden, expectedCount: manifest.golden.count)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LACModelError {
            if case .invalidFiles = error {
                store.removeAll()
                AppLogger.shared.log("❌ 🧠 [LAC] Mẫu đối chiếu hỏng — đã xoá để tải lại: \(error.errorDescription ?? "")")
            }
            throw error
        } catch {
            // `Data(contentsOf:)` lỗi ⇒ lỗi đọc (sha của file mẫu đã đúng lúc nạp), giữ model.
            AppLogger.shared.log("❌ 🧠 [LAC] Không đọc được mẫu đối chiếu — giữ model: \(error.localizedDescription)")
            throw LACModelError.readFailed("không đọc được \(LACModelMirror.goldenName)")
        }
        AppLogger.shared.log("🧠 [LAC] Tự kiểm \(summary.samples) mẫu trong \(milliseconds(since: checkStarted)) ms: "
            + "lệch nhãn \(summary.outputMismatches) câu (cho phép \(LACSelfCheck.maxOutputMismatches)), "
            + "id nhãn thô lệch \(summary.tagIDMismatches) câu")
        return tagger
    }

    private static func seconds(since start: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(start))
    }

    private static func milliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }
}
