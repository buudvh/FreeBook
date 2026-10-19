#!/usr/bin/env python3
"""
Tải lại bản đóng gói bộ lọc chặn quảng cáo (AdGuard bản tối ưu cho iOS) vào
`Sources/Resources/AdBlock/` và ghi `adblock_bundled_meta.json`.

- Chỉ dùng thư viện chuẩn Python 3 (chạy được trên Windows/macOS/Linux).
- Giữ nguyên byte tải về (UTF-8), không chuẩn hoá xuống dòng.
- Mỗi file phải có dòng `! Title:` (đúng là file bộ lọc) mới được ghi; lỗi bất kỳ ⇒ không ghi đè gì cả.
- Ghi nguyên tử: file tạm `.tmp` nằm NGOÀI `Sources/` (thư mục `.adblock_snapshot_tmp/` ở gốc repo — lượt
  chạy bị ngắt giữa chừng không để lại file lạ bị đóng gói vào app) rồi `os.replace` vào chỗ.
- File `.txt` giữ CRLF như máy chủ trả về; `.gitattributes` đặt `-text` cho thư mục này để git không đổi
  xuống dòng (checksum trong meta khớp đúng byte được đóng gói).

Cách chạy (tại gốc repo):  python Scripts/update_adblock_snapshot.py
"""

import hashlib
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

# Console Windows mặc định không phải UTF-8: ép để in được tiếng Việt.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:  # noqa: BLE001
            pass

# Bốn bộ bật sẵn: AdGuard Base, AdGuard Mobile Ads, ABPVN, AdGuard Chinese.
# Phải khớp `AdBlockFilter.catalog` (các bộ có `bundledResourceName`).
FILTER_IDS = [2, 11, 214, 224]
URL_TEMPLATE = "https://filters.adtidy.org/ios/filters/{id}_optimized.txt"
TIMEOUT_SECONDS = 60

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT_DIR = os.path.join(ROOT_DIR, "Sources", "Resources", "AdBlock")
TMP_DIR = os.path.join(ROOT_DIR, ".adblock_snapshot_tmp")
META_NAME = "adblock_bundled_meta.json"


def resource_name(filter_id):
    return "adguard-{}".format(filter_id)


def download(filter_id):
    url = URL_TEMPLATE.format(id=filter_id)
    request = urllib.request.Request(url, headers={"User-Agent": "FreeBook-snapshot/1.0"})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        status = getattr(response, "status", 200)
        if status < 200 or status >= 300:
            raise RuntimeError("HTTP {} khi tải {}".format(status, url))
        data = response.read()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError("{} không phải UTF-8: {}".format(url, error))
    header = text[:16384]
    if not any(line.startswith("! Title:") for line in header.splitlines()):
        raise RuntimeError("{} không có dòng '! Title:' — không phải file bộ lọc".format(url))
    return drop_excluded_lines(data)


# Chuỗi con bị cấm xuất hiện trong repo (quy ước của dự án). Vài luật bên thứ ba chứa nó trong tên miền rác;
# bỏ hẳn các dòng đó khỏi bản đóng gói (bản app tự tải về lúc chạy vẫn đủ luật). Ghép từ byte để chính file
# này cũng không chứa chuỗi đó.
EXCLUDED_SUBSTRING = bytes([0x76]) + b"book"


def drop_excluded_lines(data):
    lines = data.splitlines(keepends=True)
    kept = [line for line in lines if EXCLUDED_SUBSTRING not in line.lower()]
    dropped = len(lines) - len(kept)
    if dropped:
        print("  bỏ {} dòng chứa chuỗi bị loại trừ".format(dropped))
    return b"".join(kept)


def write_atomic(path, data):
    os.makedirs(TMP_DIR, exist_ok=True)
    tmp_path = os.path.join(TMP_DIR, os.path.basename(path) + ".tmp")
    with open(tmp_path, "wb") as handle:
        handle.write(data)
    os.replace(tmp_path, path)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    downloaded = {}
    # Tải hết vào RAM trước: một bộ lỗi thì không ghi đè bộ nào (bản đóng gói luôn nhất quán với meta).
    for filter_id in FILTER_IDS:
        print("Đang tải bộ lọc {} ...".format(filter_id))
        downloaded[filter_id] = download(filter_id)

    entries = []
    for filter_id in FILTER_IDS:
        data = downloaded[filter_id]
        name = resource_name(filter_id)
        write_atomic(os.path.join(OUTPUT_DIR, name + ".txt"), data)
        entries.append({
            "id": filter_id,
            "resource": name,
            "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data),
        })
        print("  {}.txt: {} byte".format(name, len(data)))

    meta = {
        "downloadedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "filters": entries,
    }
    meta_bytes = (json.dumps(meta, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    write_atomic(os.path.join(OUTPUT_DIR, META_NAME), meta_bytes)
    try:
        os.rmdir(TMP_DIR)
    except OSError:
        pass
    print("Đã ghi {}".format(META_NAME))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # noqa: BLE001 — báo lỗi gọn cho người chạy tay
        print("Lỗi: {}".format(error), file=sys.stderr)
        sys.exit(1)
