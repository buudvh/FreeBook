# Gửi Telegram có kiểm kết quả — `source` từ các bước gửi tin của `.github/workflows/build-ipa.yml`.
#
# `tg_call <method> <tham số curl…>`: gọi `https://api.telegram.org/bot$TELEGRAM_TOKEN/<method>`, coi là đã gửi
# **chỉ khi** phản hồi có `"ok":true` (curl exit 0 vẫn có thể là 400 "message caption is too long" hay 429). Lỗi thì
# thử lại 2 lần (tổng 3 lần), nghỉ 5 s rồi 10 s. Hết lượt vẫn lỗi ⇒ cảnh báo trên CI, trả 1 — bước gọi tự quyết có
# làm hỏng lượt build hay không. Nội dung tin phải cắt vừa giới hạn **trước** khi gọi (`telegram_commit_summary.py`):
# thử lại không chữa được tin quá dài.

tg_call() {
  local method="$1"
  shift
  local attempt response
  for attempt in 1 2 3; do
    response=$(curl -sS --connect-timeout 30 --max-time 300 "$@" \
      "https://api.telegram.org/bot${TELEGRAM_TOKEN}/${method}" 2>&1) || true
    if printf '%s' "$response" | grep -q '"ok":true'; then
      echo "Telegram ${method}: đã gửi (lần ${attempt})."
      return 0
    fi
    echo "::warning::Telegram ${method} lần ${attempt} chưa gửi được: $(printf '%s' "$response" | head -c 300)"
    if [ "$attempt" -lt 3 ]; then
      sleep $((attempt * 5))
    fi
  done
  echo "::warning::Telegram ${method}: không gửi được sau 3 lần."
  return 1
}
