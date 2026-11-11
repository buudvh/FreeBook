import Darwin
import Foundation
import os

/// Bộ nhớ của tiến trình — để log khi chạy model lớn (VieNeu Turbo qua audio.cpp) và biết còn cách giới hạn bao xa.
///
/// - `phys_footprint` (TASK_VM_INFO) là con số iOS dùng để quyết giết app vì hết bộ nhớ (jetsam) — không phải RSS.
/// - `os_proc_available_memory()` (iOS 13+) là phần còn lại trước khi chạm giới hạn của **app này**; trả 0 khi hệ thống
///   không cho biết. Chạy trong LiveContainer thì vẫn là giới hạn của tiến trình đang chạy.
enum ProcessMemoryProbe {
    struct Snapshot: Sendable {
        let footprintMB: Double
        let availableMB: Double

        /// "RAM 612 MB · trống 1.204 MB" — gọn để chèn vào dòng log / dòng số đo.
        var summary: String {
            String(format: "RAM %.0f MB · trống %.0f MB", footprintMB, availableMB)
        }
    }

    static func snapshot() -> Snapshot {
        Snapshot(
            footprintMB: footprintBytes() / 1_048_576,
            availableMB: Double(os_proc_available_memory()) / 1_048_576
        )
    }

    private static func footprintBytes() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) : 0
    }
}
