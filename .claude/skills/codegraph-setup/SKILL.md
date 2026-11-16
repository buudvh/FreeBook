---
name: codegraph-setup
description: "Thiết lập codegraph cho repo FreeBook trên máy mới / checkout mới / sau idle dài hoặc git pull nhiều: cài binary, codegraph init, wire agent (Claude, Codex, Antigravity, WorkBuddy), sync lại. Dùng khi codegraph báo chưa có index .codegraph/ hoặc khi người dùng hỏi cách cài codegraph."
---

# Thiết lập trên máy mới / checkout mới

> Tách từ `AGENTS.md` (1.3.959).

Khi clone repo này về máy khác (hoặc để lâu ngày rồi `git pull` nhiều thay đổi), codegraph cần khởi tạo thủ công một lần — công cụ **không tự build index** (lệnh `codegraph explore` sẽ báo *"no .codegraph/ index exists ... run 'codegraph init'"* và bảo agent không tự chạy init):

1. Cài codegraph (binary + PATH): chạy `install.ps1` từ GitHub release, hoặc `codegraph upgrade` nếu đã có.
2. Tại root repo: `codegraph init` — build `.codegraph/` từ `codegraph.json` (bắt buộc; agent **không** tự chạy).
3. Wire các agent hỗ trợ: `codegraph install --yes --target=claude,codex,antigravity`.
4. WorkBuddy (không nằm trong danh sách `install`): tự tạo `~/.workbuddy-ai/mcp.json`:
   ```json
   {
     "mcpServers": {
       "codegraph": {
         "command": "codegraph",
         "args": ["serve", "--mcp"],
         "env": { "CODEGRAPH_TELEMETRY": "0", "CODEGRAPH_WATCH_DEBOUNCE_MS": "2000" }
       }
     }
   }
   ```
   rồi Connectors → mục **"Custom connectors"** góc trên bên phải → bấm **Trust**.
5. Đồng bộ lại sau idle dài / git pull / đổi nhánh: `codegraph sync` (hoặc `codegraph index` để rebuild toàn bộ) — **agent tự chạy**, không cần hỏi. File watcher tự động đồng bộ khi session đang chạy, nhưng **không** bắt kịp thay đổi lúc máy tắt.
