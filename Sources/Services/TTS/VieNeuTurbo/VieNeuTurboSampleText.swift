import Foundation

/// Văn bản mẫu của màn thử VieNeu Turbo — tự viết cho bước đo, không trích từ sách nào.
///
/// - `short`: một đoạn 4 câu có số, giờ, năm, số có dấu chấm nghìn và một từ tiếng Anh — đủ để nghe cả lớp đọc số lẫn
///   chỗ chen tiếng Anh của sea-g2p.
/// - `long`: khoảng 2.600 chữ, nhiều đoạn, câu dài ngắn xen nhau — chế độ "Đọc liên tục" lặp lại văn bản này để đo
///   nhiệt trong nhiều phút.
enum VieNeuTurboSampleText {
    static let short = """
    Sáng nay, thư viện mở cửa lúc 7 giờ 30 và đón hơn 250 bạn đọc trong buổi đầu tiên. \
    Chị thủ thư cho biết năm 2026 sẽ có thêm 1.200 đầu sách mới, phần lớn là truyện dài nhiều tập. \
    Ai muốn mượn sách chỉ cần quét mã trên ứng dụng rồi bấm nút download là xong. \
    Buổi chiều trời mưa nhẹ, nhiệt độ khoảng 24 độ.
    """

    static let long = """
    Làng nằm ở khúc sông cong nhất của vùng hạ lưu, nơi nước chảy chậm đến mức người ta có thể nhìn thấy bóng mây trôi \
    trên mặt sông cả buổi chiều. Mỗi sáng, chuyến đò đầu tiên rời bến lúc năm giờ, chở theo những gánh rau còn ướt sương \
    và mấy bao gạo mới xay.

    Ông lái đò năm nay đã ngoài sáu mươi tuổi. Ông bảo mình đã chèo qua con sông này chừng ba mươi nghìn lượt, nhưng \
    chưa lần nào thấy nó giống hệt lần trước. Có hôm nước đục ngầu vì mưa đầu nguồn, có hôm trong đến mức thấy cả đàn \
    cá con bơi sát mạn đò.

    Chợ phiên họp vào ngày rằm và mùng một. Từ tờ mờ sáng, các sạp hàng đã kín lối đi: nào cá kho niêu, nào bánh đúc \
    nóng, nào những bó lá dong xanh mướt để gói bánh. Tiếng rao lẫn trong tiếng gà gáy, tiếng xe đạp lách cách qua \
    cây cầu gỗ.

    Cô giáo trẻ mới về làng được hai năm. Lớp của cô có hai mươi tư học trò, đứa nhỏ nhất vừa tròn sáu tuổi. Buổi tối, \
    cô mở lớp đọc sách miễn phí ở nhà văn hoá, và lần nào cũng có vài bác nông dân ngồi nghe ké ở hàng ghế cuối.

    Mùa lũ năm ấy đến sớm hơn mọi năm gần một tháng. Nước dâng nhanh trong đêm, tràn qua bờ đê thấp phía tây. Cả làng \
    thức trắng, người khiêng bao cát, người dắt trâu lên gò cao, người chèo thuyền đi đón các cụ già ở xóm ngoài.

    Sáng hôm sau, nước bắt đầu rút. Bùn phủ kín sân đình, mấy luống cải non bị cuốn mất, nhưng không ai bị thương. \
    Người ta gọi nhau dọn dẹp, chia nhau từng nắm gạo khô, từng chiếc chăn còn lành. Đến trưa, khói bếp lại bay lên \
    từ khắp các mái nhà.

    Ở cuối làng có một xưởng mộc nhỏ. Người thợ cả làm nghề đã bốn đời, chuyên đóng đò và sửa bàn ghế cho trường học. \
    Ông nói gỗ cũng có tính nết như người: loại ưa nắng, loại ưa ẩm, loại phải phơi đủ một mùa mới chịu nằm yên.

    Mùa gặt, cả cánh đồng vàng rực đến tận chân núi. Máy gặt chạy từ sáng đến tối, nhưng nhiều nhà vẫn giữ thói quen \
    gặt tay vài thửa ruộng sát bờ tre, để con cháu biết mùi rơm mới và tiếng liềm sột soạt dưới gốc lúa.

    Buổi tối sau mùa gặt, sân kho hợp tác xã sáng đèn. Thanh niên trong làng kéo đàn, hát những bài dân ca cũ, rồi \
    chuyển sang mấy bài hát mới học được trên mạng. Các cụ ngồi uống trà, vừa nghe vừa gật gù, thỉnh thoảng lại sửa \
    giúp một câu hát sai lời.

    Năm ngoái, làng có đường nhựa nối ra quốc lộ. Xe khách chạy mỗi ngày bốn chuyến, chuyến sớm nhất lúc sáu giờ \
    mười lăm. Bọn trẻ đi học trên tỉnh cuối tuần nào cũng về, mang theo sách vở, bánh kẹo, và những câu chuyện về \
    thành phố đông đúc.

    Dẫu vậy, chuyến đò sáng vẫn chưa bao giờ vắng khách. Người ta bảo đi đò chậm hơn đi xe, nhưng ngồi trên đò mới \
    thấy hết khúc sông, mới nghe được tiếng nước vỗ vào mạn gỗ, và mới có dịp hỏi han nhau chuyện mùa màng.

    Chiều xuống, mặt trời lặn sau rặng phi lao. Ông lái đò buộc thuyền vào cọc, xách chiếc ấm nhôm lên bờ, ngồi trên \
    bậc đá quen thuộc. Ông nhìn con sông thêm một lúc rồi mới chậm rãi đi về, như thể sợ nó buồn khi bị bỏ lại một mình.
    """
}
