#!/usr/bin/env python3
"""Dựng nội dung tin Telegram (và ghi chú release) liệt kê mọi commit của một lượt build.

`build-ipa.yml` gom danh sách subject commit kể từ lần build xanh trước vào một file (bước `Collect Commit List`,
mỗi dòng một subject, cũ → mới). Một lượt push có thể mang nhiều commit (session chính push gộp sau khi các
session con commit xong), nên tin build phải nói đủ — không chỉ commit cuối.

- `--format telegram`: header, rồi `💬 Commit: <subject>` (một commit) hoặc `💬 N commit:` + `• <subject>` từng dòng;
  cắt cho vừa `--limit` ký tự (caption sendDocument 1024, sendMessage 4096), chừa chỗ cho `--footer`; còn thừa ⇒
  `… và K commit khác`.
- `--format notes`: danh sách gạch đầu dòng `- <subject>` đầy đủ, dùng làm ghi chú release / `apps.json`.

Subject trùng nhau chỉ giữ lần đầu (1.3.729): commit sửa lỗi CI dùng lại đúng message của commit hỏng, nên một
lượt build có thể mang hai commit cùng subject.
"""

import argparse
import sys


def read_subjects(path):
    try:
        with open(path, encoding="utf-8") as fh:
            lines = [line.strip() for line in fh if line.strip()]
    except OSError:
        return []
    # Giữ thứ tự cũ → mới, bỏ dòng trùng (so nguyên văn).
    return list(dict.fromkeys(lines))


def u16len(text):
    """Telegram đếm giới hạn theo đơn vị UTF-16 (emoji = 2)."""
    return len(text.encode("utf-16-le")) // 2


def trim_u16(text, limit):
    while text and u16len(text) > limit:
        text = text[:-1]
    return text


def telegram_text(header, subjects, footer, limit):
    footer_part = f"\n{footer}" if footer else ""
    if len(subjects) <= 1:
        body = f"💬 Commit: {subjects[0]}" if subjects else ""
        text = f"{header}\n\n{body}" if body else header
        return trim_u16(trim_u16(text, max(0, limit - u16len(footer_part))) + footer_part, limit)

    lines = [f"{header}\n\n💬 {len(subjects)} commit:"]
    for index, subject in enumerate(subjects):
        remaining = len(subjects) - index
        candidate = f"• {subject}"
        # Chừa chỗ cho dòng "còn K commit" (nếu dòng này không phải dòng cuối) và footer.
        tail = "" if remaining == 1 else f"\n… và {remaining - 1} commit khác"
        projected = u16len("\n".join(lines + [candidate])) + u16len(tail) + u16len(footer_part)
        if projected > limit:
            lines.append(f"… và {remaining} commit khác")
            break
        lines.append(candidate)
    return trim_u16("\n".join(lines) + footer_part, limit)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", required=True, help="file danh sách subject, mỗi dòng một commit")
    parser.add_argument("--format", choices=["telegram", "notes"], default="telegram")
    parser.add_argument("--header", default="")
    parser.add_argument("--footer", default="")
    parser.add_argument("--limit", type=int, default=1024)
    args = parser.parse_args()

    subjects = read_subjects(args.list)
    if args.format == "notes":
        text = "\n".join(f"- {subject}" for subject in subjects)
    else:
        text = telegram_text(args.header, subjects, args.footer, args.limit)
    # Luôn UTF-8, không theo bảng mã của console (Windows mặc định cp1252 không in được emoji).
    sys.stdout.buffer.write(text.encode("utf-8"))


if __name__ == "__main__":
    main()
