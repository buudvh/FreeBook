import Foundation
import os

/// Bản chụp bất biến của `ExtensionLibraryRepository` cho tầng **nền** (DownloadManager, Debug router, Backup,
/// JS bridge…) — đọc đồng bộ qua lock, không cần `await` lên MainActor.
///
/// Repository là chủ duy nhất ghi vào bảng này (sau mỗi mutation); mọi nơi khác chỉ đọc qua các
/// `nonisolated static func` của `ExtensionLibraryRepository`. Tách type riêng vì `static let shared` trên một
/// class `@MainActor` là MainActor-isolated — truy cập từ thread nền sẽ lỗi biên dịch.
final class ExtensionLibrarySnapshotTable: @unchecked Sendable {
    static let shared = ExtensionLibrarySnapshotTable()

    private struct State: Sendable {
        var installed: [Extension] = []
        var installedById: [String: Extension] = [:]
        var catalogById: [String: Extension] = [:]
        var repositories: [ExtensionRepositoryRecord] = []
        /// `localPath` tuyệt đối (đã `standardizedFileURL`) → `packageId` của tiện ích đã cài.
        var packageIdByPath: [String: String] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    /// Chỉ `ExtensionLibraryRepository` gọi, sau mỗi mutation. Dựng bảng ngoài lock rồi thay một lần.
    func update(installed: [Extension], catalog: [Extension], repositories: [ExtensionRepositoryRecord]) {
        var next = State()
        next.installed = installed
        next.repositories = repositories
        for ext in installed {
            if next.installedById[ext.packageId] == nil { next.installedById[ext.packageId] = ext }
            let path = ext.localPath
            if !path.isEmpty { next.packageIdByPath[Self.normalizedPathKey(path)] = ext.packageId }
        }
        for ext in catalog where next.catalogById[ext.packageId] == nil {
            next.catalogById[ext.packageId] = ext
        }
        let table = next
        state.withLock { $0 = table }
    }

    func installedExtension(packageId: String) -> Extension? {
        state.withLock { $0.installedById[packageId] }
    }

    func catalogExtension(packageId: String) -> Extension? {
        state.withLock { $0.catalogById[packageId] }
    }

    func installed() -> [Extension] {
        state.withLock { $0.installed }
    }

    func repositories() -> [ExtensionRepositoryRecord] {
        state.withLock { $0.repositories }
    }

    func packageId(forLocalPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = Self.normalizedPathKey(trimmed)
        return state.withLock { $0.packageIdByPath[key] }
    }

    private static func normalizedPathKey(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
