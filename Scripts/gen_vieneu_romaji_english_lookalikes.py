#!/usr/bin/env python3
"""Sinh `VieNeuRomajiEnglishLookalikes.swift` — các từ tiếng Anh thông dụng "trông giống tên Nhật".

## Vì sao cần
`VieNeuJapaneseNameReader` (1.3.950) đọc tên kiểu Nhật theo âm tiết ("Sasuke" → xa xu kê) khi từ **viết hoa** cắt được
hết thành âm tiết romaji. Nhưng rất nhiều từ tiếng Anh cũng cắt được như thế ("Game" → ga-me, "Time", "Kate",
"Tomato"…) — đọc theo âm tiết thì sai. File Swift sinh ra là danh sách loại trừ: giao của 10.000 từ tiếng Anh phổ biến
nhất với tập "cắt được thành âm tiết romaji, từ 4 chữ".

## Chống lệch với Swift
Bộ cắt âm tiết ở đây (`normalize` + `parse`) là **bản chép** của `VieNeuRomajiSyllabifier.swift`. Sửa luật ở một bên thì
sửa bên kia rồi chạy lại script; `--selftest` đối chiếu phiên âm với đúng các chuỗi anh Bửu đã nghe và duyệt
(mẫu C / E / F cách A, 2026-11-15).

## Nguồn danh sách từ
`src/lang/en/top_words.rs` của kho sea-g2p (https://github.com/pnnbao97/sea-g2p, Apache-2.0; file đó sinh từ
google-10000-english). Cũng nhận file văn bản mỗi dòng một từ.

Dùng:
    python Scripts/gen_vieneu_romaji_english_lookalikes.py --selftest
    python Scripts/gen_vieneu_romaji_english_lookalikes.py <top_words.rs | words.txt> \
        > Sources/Services/TTS/VieNeu/Names/VieNeuRomajiEnglishLookalikes.swift
"""
import re
import sys

VOWELS = "aiueo"
PLAIN_ONSETS = "kstnhmrgzdbp"
PALATAL_ONSETS = ("ky", "gy", "ny", "hy", "my", "ry", "by", "py")
GEMINATE_CODA = {"k": "k", "t": "t̪", "p": "p", "s": "t̪"}

ONSET_PHONE = {
    "": "", "k": "k", "s": "s", "t": "t̪", "n": "n", "h": "h", "m": "m", "r": "ɹ", "g": "ɣ", "z": "z",
    "d": "ɗ", "b": "b", "p": "p", "w": "w", "y": "j", "j": "z", "f": "f", "sh": "s", "ch": "tʃ", "ts": "s",
    "ky": "k", "gy": "ɣ", "ny": "n", "hy": "h", "my": "m", "ry": "ɹ", "by": "b", "py": "p",
}
VOWEL_PHONE = {"a": "aː", "i": "i", "u": "u", "e": "e", "o": "o"}

# Từ gốc Nhật có trong danh sách tiếng Anh: KHÔNG loại trừ, để chúng được đọc theo âm tiết (anh Bửu đã nghe "Tokyo").
JAPANESE_ORIGIN = {
    "tokyo", "toyota", "suzuki", "subaru", "honda", "nissan", "nikon", "sanyo", "sega", "nintendo", "yamaha",
    "toshiba", "mitsubishi", "hitachi", "fujitsu", "fuji", "tsunami", "karaoke", "manga", "anime", "pokemon",
    "hentai", "kijiji", "bukkake", "momo",
}


def normalize(key: str) -> str:
    """Gộp trường âm về âm ngắn. `key` là chữ thường ASCII (có thể còn dấu nháy sau "n")."""
    word = re.sub(r"oh(?![aiueoy])", "o", key)
    previous = None
    while word != previous:
        previous = word
        word = re.sub(r"ou(?!e)", "o", word)
        for long, short in (("aa", "a"), ("ii", "i"), ("uu", "u"), ("ee", "e"), ("oo", "o"), ("ei", "e")):
            word = word.replace(long, short)
    return word


def parse(key: str):
    """Cắt thành âm tiết; không cắt được hết ⇒ None. Mỗi âm tiết: dict onset / vowel / coda / geminate / glide."""
    word = normalize(key)
    syllables = []
    index, count = 0, len(word)
    while index < count:
        char = word[index]
        nxt = word[index + 1] if index + 1 < count else ""
        # n mũi cuối âm tiết (ん): không đứng trước nguyên âm / y, hoặc có dấu nháy theo sau.
        if char == "n" and (nxt == "'" or nxt == "" or nxt not in "aiueoy"):
            if not syllables or syllables[-1]["coda"]:
                return None
            syllables[-1]["coda"] = "n"
            index += 2 if nxt == "'" else 1
            continue
        if char == "m" and nxt in ("b", "p"):
            if not syllables or syllables[-1]["coda"]:
                return None
            syllables[-1]["coda"] = "m"
            index += 1
            continue
        # Âm ngắt (っ): phụ âm kép, và "tch".
        geminate = None
        if char in GEMINATE_CODA and nxt == char:
            geminate = char
        elif word.startswith("tch", index):
            geminate = "t"
        if geminate:
            if not syllables or syllables[-1]["coda"]:
                return None
            syllables[-1]["coda"] = GEMINATE_CODA[geminate]
            syllables[-1]["geminate"] = True
            index += 1
            continue
        onset, vowel = split_syllable(word, index)
        if vowel is None:
            return None
        syllables.append({"onset": onset, "vowel": vowel, "coda": "", "geminate": False, "glide": False})
        index += len(onset) + 1
    return merge_glides(syllables) if len(syllables) >= 2 else None


def split_syllable(word: str, index: int):
    two = word[index:index + 2]
    vowel2 = word[index + 2:index + 3]
    if two in PALATAL_ONSETS and vowel2 and vowel2 in "auo":
        return two, vowel2
    if two in ("sh", "ch") and vowel2 and vowel2 in "aiuo":
        return two, vowel2
    if two == "ts" and vowel2 == "u":
        return two, vowel2
    char = word[index]
    vowel1 = word[index + 1:index + 2]
    if char in VOWELS:
        return "", char
    if not vowel1:
        return "", None
    if char in PLAIN_ONSETS and vowel1 in VOWELS:
        return char, vowel1
    if char == "y" and vowel1 in "auo":
        return char, vowel1
    if char == "w" and vowel1 in "aieo":
        return char, vowel1
    if char == "j" and vowel1 in "aiuo":
        return char, vowel1
    if char == "f" and vowel1 == "u":
        return char, vowel1
    return "", None


def merge_glides(syllables):
    """"ai / oi / ui" đọc thành một âm tiết có bán nguyên âm cuối (kai → kˈaːj), trừ khi "i" còn mang đuôi n."""
    merged = []
    for syllable in syllables:
        previous = merged[-1] if merged else None
        if (previous and syllable["onset"] == "" and syllable["vowel"] == "i" and not syllable["coda"]
                and not previous["coda"] and not previous["glide"] and previous["vowel"] in "aou"
                and previous["onset"] not in PALATAL_ONSETS):
            previous["glide"] = True
            continue
        merged.append(syllable)
    return merged if len(merged) >= 2 else None


def render(syllables) -> str:
    parts = []
    for syllable in syllables:
        onset = ONSET_PHONE[syllable["onset"]]
        tail = ""
        if syllable["glide"]:
            tail += "j"
        if syllable["geminate"]:
            tail += "ɜ" + syllable["coda"]
        else:
            tail += syllable["coda"]
        if syllable["onset"] in PALATAL_ONSETS:
            # Âm ghép đọc theo cách A anh Bửu chọn: kya → kia, kyu → kiu, kyo → ki-ô (hai âm tiết).
            if syllable["vowel"] == "a":
                parts.append(onset + "ˈiə" + tail)
            elif syllable["vowel"] == "u":
                parts.append(onset + "ˈiw" + tail)
            else:
                parts.append(onset + "ˈi")
                parts.append("ˈo" + tail)
        else:
            parts.append(onset + "ˈ" + VOWEL_PHONE[syllable["vowel"]] + tail)
    return " ".join(parts)


def phonemes(name: str):
    syllables = parse(name.lower())
    return render(syllables) if syllables else None


EXPECTED = {
    # Mẫu C
    "Sasuke": "sˈaː sˈu kˈe", "Naruto": "nˈaː ɹˈu t̪ˈo", "Kakashi": "kˈaː kˈaː sˈi", "Konoha": "kˈo nˈo hˈaː",
    "Kazuto": "kˈaː zˈu t̪ˈo", "Asuna": "ˈaː sˈu nˈaː", "Takemichi": "t̪ˈaː kˈe mˈi tʃˈi", "Akame": "ˈaː kˈaː mˈe",
    "Inosuke": "ˈi nˈo sˈu kˈe", "Uchiha": "ˈu tʃˈi hˈaː", "Itachi": "ˈi t̪ˈaː tʃˈi", "Tanjiro": "t̪ˈaːn zˈi ɹˈo",
    "Nezuko": "nˈe zˈu kˈo", "Zenitsu": "zˈe nˈi sˈu",
    # Mẫu E
    "Yuki": "jˈu kˈi", "Kirigaya": "kˈi ɹˈi ɣˈaː jˈaː", "Hattori": "hˈaːɜt̪ t̪ˈo ɹˈi", "Ikki": "ˈiɜk kˈi",
    "Hokkaido": "hˈoɜk kˈaːj ɗˈo", "Yusuke": "jˈu sˈu kˈe", "Inoue": "ˈi nˈo ˈu ˈe", "Sempai": "sˈem pˈaːj",
    "Satou": "sˈaː t̪ˈo", "Gojo": "ɣˈo zˈo", "Satoru": "sˈaː t̪ˈo ɹˈu",
    # Mẫu F cách A
    "Otsutsuki": "ˈo sˈu sˈu kˈi", "Kyoko": "kˈi ˈo kˈo", "Ryuji": "ɹˈiw zˈi", "Tokyo": "t̪ˈo kˈi ˈo",
    # Biến thể chính tả
    "Ohno": "ˈo nˈo", "Satoh": "sˈaː t̪ˈo", "Kyouko": "kˈi ˈo kˈo", "Sensei": "sˈen sˈe", "Jun'ichi": "zˈun ˈi tʃˈi",
    "Shin'ya": "sˈin jˈaː", "Senpai": "sˈen pˈaːj", "Ryuu": None, "Kun": None,
}
REJECTED = ["Harry", "Hermione", "Dumbledore", "Klein", "Luffy", "Levi", "Xiaomi", "Linfeng", "Wanglin", "Smith"]


def selftest() -> int:
    failures = 0
    for name, expected in EXPECTED.items():
        got = phonemes(name)
        if got != expected:
            failures += 1
            print(f"SAI  {name}: {got!r} ≠ {expected!r}")
    for name in REJECTED:
        if phonemes(name) is not None:
            failures += 1
            print(f"SAI  {name}: lẽ ra không cắt được, lại ra {phonemes(name)!r}")
    print("selftest:", "ĐẠT" if failures == 0 else f"{failures} lỗi", f"({len(EXPECTED) + len(REJECTED)} ca)")
    return failures


def load_words(path: str):
    text = open(path, encoding="utf-8").read()
    if path.endswith(".rs"):
        return sorted(set(re.findall(r'"([a-z]+)"', text)))
    return sorted({line.strip().lower() for line in text.splitlines() if line.strip().isalpha()})


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--selftest":
        sys.exit(1 if selftest() else 0)
    words = [w for w in load_words(sys.argv[1]) if len(w) >= 4 and w not in JAPANESE_ORIGIN and parse(w)]
    lines = []
    row = "       "
    for word in words:
        piece = f' "{word}",'
        if len(row) + len(piece) > 118:
            lines.append(row.rstrip())
            row = "       "
        row += piece
    lines.append(row.rstrip())
    print("import Foundation")
    print()
    print("/// Từ tiếng Anh thông dụng **cắt được hết thành âm tiết romaji** (game, time, kate, tomato…) — `VieNeuJapaneseNameReader`")
    print("/// loại chúng ra để không đọc nhầm theo âm tiết kiểu Nhật.")
    print("///")
    print("/// **File sinh tự động** bằng `Scripts/gen_vieneu_romaji_english_lookalikes.py` từ 10.000 từ tiếng Anh phổ biến nhất")
    print("/// (`top_words.rs` của sea-g2p, Apache-2.0, gốc google-10000-english). Đừng sửa tay: sửa luật cắt âm tiết trong")
    print("/// `VieNeuRomajiSyllabifier` thì sửa bản chép trong script rồi sinh lại.")
    print("enum VieNeuRomajiEnglishLookalikes {")
    print(f"    /// {len(words)} từ, chữ thường.")
    print("    static let words: Set<String> = [")
    print("\n".join(lines))
    print("    ]")
    print("}")


if __name__ == "__main__":
    main()
