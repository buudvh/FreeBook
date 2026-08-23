# FreeBook Extension Debug

VS Code client nội bộ để chạy các hàm global `execute(...)` của VBook extension
trong runtime JavaScriptCore thật của app FreeBook.

## Trạng thái hiện tại

- **Mock Transport** kiểm tra command, profile, snapshot và trace UI; nó luôn hiện rõ
  rằng không chạy JSExecutor iOS.
- **App Transport** đã có protocol WebSocket v1, nhưng chỉ chạy thật khi app iOS triển
  khai FreeBook Debug Server tương ứng.
- Client không thực thi JavaScript bằng Node.js và không chứa VBook runtime thay thế.

## Phát triển và đóng gói

```powershell
npm install
npm run check
npm run package
```

Lệnh cuối tạo file VSIX cục bộ để cài thủ công vào VS Code.

## Cách dùng

### Cài một lần

1. Trong VS Code, mở Extensions (`Ctrl+Shift+X`) → nút `…` → **Install from VSIX…**.
2. Chọn file `freebook-ext-debug-0.1.0.vsix` được tạo trong thư mục này.
3. Reload VS Code nếu VS Code yêu cầu.

### Chạy mỗi ngày

1. Mở thư mục extension VBook, rồi mở một file `.js` của extension.
2. Bấm icon **FreeBook Debug** ở thanh Activity Bar bên trái. Nút nhỏ trên title
   của file `.js` cũng mở đúng sidebar này.
3. Sidebar tự nhận extension; nếu cần, bấm **Chọn…** để chọn thư mục chứa
   `plugin.json`. Chọn script, điền các input đang hiện và chọn **Draft** hoặc
   **Installed**.
4. Khi app chưa có Debug Server, bấm **Use Mock** rồi **Run execute** để kiểm tra
   form, snapshot và protocol. Panel/Trace luôn ghi rõ `Mock — không chạy
   JSExecutor iOS`.
5. Khi app server đã sẵn sàng, bấm **Pair App** và dán pairing URI dạng
   `freebook-debug://pair?endpoint=ws%3A%2F%2F...&token=...`. Sau đó bấm
   **Run execute**; trace xuất hiện ngay dưới form. **Open Trace** chỉ mở log đầy
   đủ của VS Code khi cần.

`Installed` chỉ bật khi app báo extension có package ID trùng khớp. `Draft` luôn
đọc toàn bộ cây extension từ các file đã lưu, chặn khi còn editor bẩn, và stage
cả file root lẫn `src/` trước khi chạy. Extension không tự lưu file cho bạn.

Các command cũ như **Run Current execute** và **Run Saved Profile** vẫn có trong
Command Palette cho trường hợp cần thao tác nhanh, nhưng sidebar là luồng dùng
chính.

## Giới hạn MVP

- Chỉ VS Code desktop local.
- Chỉ workspace đáng tin cậy.
- Source draft lấy nội dung đã lưu; không tự lưu hay upload buffer chưa lưu.
- Token pairing chỉ lưu qua VS Code SecretStorage.
