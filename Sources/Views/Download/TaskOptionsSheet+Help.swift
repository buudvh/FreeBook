import SwiftUI

/// Nút "?" ở tiêu đề từng mục của `TaskOptionsSheet` (1.3.624). Các đoạn giải thích trước đây là footer luôn hiện, giờ
/// nằm trong popover của `SectionHelpButton` (qua `SectionHelpHeader`) — cùng kiểu sheet thêm rule dịch.
extension TaskOptionsSheet {
    func helpHeader(_ title: String, paragraphs: [LocalizedStringKey]) -> some View {
        SectionHelpHeader(title, paragraphs: paragraphs)
    }

    var startHelpParagraphs: [LocalizedStringKey] {
        if isVideoExport {
            return [
                "**Tập đang xem**: xuất từ tập đang xem lúc tác vụ bắt đầu chạy. **Tập đầu tiên**: xuất từ đầu danh sách tập.",
                "**Chọn tập…** mở toàn bộ danh sách tập, tìm được theo số hoặc tên tập.",
                "Từ tập bắt đầu, tác vụ xét tới hết **Số lượng tập**; tập chưa tải trong khoảng đó bị bỏ qua."
            ]
        }
        if isVideo {
            return [
                "**Tập đang xem**: tải từ tập đang xem lúc tác vụ bắt đầu chạy. **Tập đầu tiên**: tải từ đầu danh sách tập.",
                "**Chọn tập…** mở toàn bộ danh sách tập, tìm được theo số hoặc tên tập.",
                "Từ tập bắt đầu, tác vụ tải tới hết **Số lượng tập**."
            ]
        }
        return [
            "**Chương đang đọc**: tải từ vị trí đọc lúc tác vụ bắt đầu chạy. **Chương đầu tiên**: tải từ đầu mục lục.",
            "**Chọn chương…** mở toàn bộ mục lục (tên đã dịch nếu truyện bật dịch), tìm được theo số hoặc tên chương.",
            "Từ chương bắt đầu, tác vụ tải tới hết **Số lượng chương**."
        ]
    }

    var taskOptionsHelpParagraphs: [LocalizedStringKey] {
        if isComicExport {
            return [
                "Chỉ các chương **đã tải ảnh offline** được đưa vào file; chương chưa tải bị bỏ qua, không tải thêm.",
                "**CBZ** giữ nguyên ảnh gốc, mỗi chương một thư mục. **PDF** mỗi ảnh một trang.",
                "Tắt **Hiển thị trong Kệ sách** để truyện nằm trong Lịch sử đọc."
            ]
        }
        if isVideoExport {
            return [
                "Chỉ các tập **đã tải về máy** được xuất; tập chưa tải bị bỏ qua, không tải thêm.",
                "Video tải dạng file (MP4/MOV) được chép nguyên bản. Video dạng HLS được nối các đoạn thành một file **TS** hoặc **MP4** (không chuyển định dạng); nguồn tách riêng luồng tiếng thì có thêm một file tiếng. Phụ đề chép kèm.",
                "Một tập ra một file; nhiều tập (hoặc tập có file tiếng / phụ đề) gom vào một thư mục, chia sẻ một lần khi xuất xong.",
                "Tắt **Hiển thị trong Kệ sách** để phim nằm trong Lịch sử."
            ]
        }
        if isExport {
            return [
                "Bật **Dịch nội dung**: các chương được dịch tự động bằng Quick Translator trước khi ghi vào file.",
                "Bật **Chỉ xuất chương đã tải**: quá trình xuất chạy offline và chỉ lấy các chương đã có cache — bản xuất sẽ thiếu những chương chưa tải.",
                "Tắt **Hiển thị trong Kệ sách** để truyện nằm trong Lịch sử đọc."
            ]
        }
        if isVideo {
            return [
                "Tải lần lượt từng tập, chỉ chạy khi app đang mở: ra nền thì tạm dừng, mở lại tự tải tiếp.",
                "Nguồn có nhiều mức thì lấy mức cao nhất không vượt **Chất lượng**. Tập chỉ xem được dạng nhúng trang hoặc có DRM sẽ bị bỏ qua.",
                "Tắt **Hiển thị trong Kệ sách** để phim nằm trong Lịch sử."
            ]
        }
        return [
            "Tải truyện offline chỉ tải nội dung gốc chưa dịch để lưu trữ và tối ưu tốc độ đọc.",
            "Tắt **Hiển thị trong Kệ sách** để truyện nằm trong Lịch sử đọc."
        ]
    }

    var speedHelpParagraphs: [LocalizedStringKey] {
        var paragraphs: [LocalizedStringKey] = [
            "**Nghỉ giữa các lần tải**: mỗi luồng chờ chừng ấy giây sau một chương phải tải từ mạng; chương đã có trong máy không phải chờ. Mặc định **Không**."
        ]
        if supportsLanes {
            paragraphs.append("**Số luồng**: tải cùng lúc nhiều chương của truyện này — nhanh hơn nhưng dễ bị trang nguồn chặn. Mặc định **1** (tuần tự).")
            paragraphs.append("App chạy tối đa 2 tác vụ một lúc: hai truyện cùng nguồn, mỗi truyện 3 luồng là 6 lượt tải cùng lúc vào một trang.")
        }
        paragraphs.append("Cấu hình nhớ riêng cho từng nguồn; truyện khác cùng nguồn dùng lại.")
        return paragraphs
    }
}
