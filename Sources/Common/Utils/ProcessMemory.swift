import Darwin
import Foundation

/// Đọc mức bộ nhớ mà **tiến trình** đang thực sự chiếm.
///
/// Tách riêng khỏi từng engine vì **hai màn thử phải gọi cùng một hàm** thì số mới so được với nhau:
/// tiêu chí go/no-go của màn thử Kokoro là "RAM đỉnh thấp hơn VieNeu", mà trước lượt này **VieNeu chưa
/// từng được đo RAM** — không có `phys_footprint` ở đâu trong phân hệ VieNeu.
///
/// `phys_footprint` là con số iOS dùng để quyết định jetsam. Cố ý **không** dùng `os_proc_available_memory()`:
/// hàm đó trả phần **còn lại**, còn thứ cần báo cáo là phần **đã dùng**.
enum ProcessMemory {
    /// `phys_footprint` tính bằng byte.
    ///
    /// Trả `0` khi `task_info` thất bại — không có số còn hơn có số sai, và `0` cũng là giá trị mà bên gọi
    /// dùng để in `—` thay vì một con số bịa.
    static func residentBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.phys_footprint)
    }

    /// Chuỗi hiển thị dạng `1,24 GB`, hoặc `—` khi không đọc được.
    static func formatted() -> String {
        let bytes = residentBytes()
        guard bytes > 0 else { return "—" }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    /// Tên trạng thái nhiệt lúc đo.
    ///
    /// iOS hạ xung khi máy nóng, nên một số đo lúc `serious` là số của **máy đã bị hãm**. Không ghi lại thì
    /// hai lượt đo cách nhau vài phút không so được — mà nạp model vài trăm MB là đủ để máy ấm lên.
    static func thermalStateName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// `true` khi hệ thống đang bật chế độ tiết kiệm pin — nó hạ xung và làm số đo xấu đi.
    static var isLowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
