#!/usr/bin/env python3
"""Dựng lại `phien-am-tieng-nhat.plist` — từ điển phiên âm tiếng Nhật của VieNeu-TTS.

## Vì sao cần script này
File gốc trên HuggingFace (`raikiri1498/nghitts`) là **bản sao gần như nguyên vẹn** của
`non-vietnamese-words.plist` (30.550/30.565 khoá trùng), tức gần như toàn bộ giá trị là cách đọc kiểu
**tiếng Anh**. Dùng nguyên nó làm từ điển tiếng Nhật thì VieNeu đọc sai gần hết.

## Bốn bước, đúng thứ tự (đổi thứ tự là sai kết quả)
1. **Gấp macron ở KHOÁ** (`ā ī ū ē ō` → ASCII). Bắt buộc, không phải tuỳ chọn:
   * lúc đọc, app tra bằng khoá **đã gấp dấu** (`TextPreprocessor.swift:982`) ⇒ khoá còn macron là mục chết;
   * `ForeignScriptClassifier` đòi **toàn ASCII** (`ForeignScriptClassifier.swift:88`) ⇒ không gấp thì **571
     từ Nhật** (`danzō`, `ryū`, `jōnin`, `yōkai`, `kaijū`…) bị loại oan.
2. **Lọc** bằng `ForeignScriptClassifier.isJapaneseRomaji`.
3. **Phiên âm lại** giá trị bằng `JapaneseTransliterator.transliterateRomaji` (đổi `-` → khoảng trắng, đúng
   quy ước lưu của app — `TTSPhoneticSuggestionBuilder.stripSyllableDashes`).
4. **Vá 7 mục** mà `transliterateRomaji` trả về nguyên khoá (không cắt được âm tiết) — xem `HAND_FIXED` /
   `DROPPED`.

## Chống lệch với Swift
Hai bảng quyết định (`romajiToViSyllable`, `longVowelForms`) và whitelist (`JapaneseLoanwordList`) được
**đọc trực tiếp từ file `.swift`**, không chép tay — cùng tinh thần `Scripts/FbankGate` và
`check_group_latent.py`. Sửa bảng trong Swift rồi chạy lại script là ra kết quả mới.

Dùng:
    python Scripts/rebuild_vieneu_japanese_dictionary.py --source <plist gốc> --output <plist đích>
"""

import argparse
import plistlib
import re
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SWIFT_PREPROCESSING = REPO / "Sources/Services/TTS/Preprocessing"
TRANSLITERATOR = SWIFT_PREPROCESSING / "JapaneseTransliterator.swift"
LOANWORD_LIST = SWIFT_PREPROCESSING / "JapaneseLoanwordList.swift"

MACRON = {"\u0101": "a", "\u012b": "i", "\u016b": "u", "\u0113": "e", "\u014d": "o"}

# 4 mục mà `transliterateRomaji` KHÔNG cắt được âm tiết nhưng là từ mượn tiếng Nhật nằm trong whitelist của
# chính app (`JapaneseLoanwordList`) ⇒ bật cờ phiên âm cũng không đọc được, từ điển là cách duy nhất. Người
# dùng chốt cách đọc 2026-10-01.
HAND_FIXED = {
    "chakra": "chát ra",
    "matcha": "mát cha",
    "sempai": "sem pai",
    "tempura": "tem pu ra",
}

# 3 mục còn lại của nhóm lỗi: `cosplay`/`kun` là từ mượn Nhật nhưng người dùng chốt bỏ, `chain` là từ tiếng
# Anh lọt qua hàm chấm điểm.
DROPPED = {"chain", "cosplay", "kun"}


def strip_swift_comments(text: str) -> str:
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("//"))


def load_tables():
    code = strip_swift_comments(TRANSLITERATOR.read_text(encoding="utf-8"))
    block = code.split("romajiToViSyllable: [String: String] = [", 1)[1].split("\n    ]", 1)[0]
    romaji_to_vi = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]*)"', block))
    long_block = code.split("longVowelForms: [(String, String)] = [", 1)[1].split("\n    ]", 1)[0]
    long_vowels = re.findall(r'\("([^"]+)",\s*"([^"]+)"\)', long_block)
    loanwords = strip_swift_comments(LOANWORD_LIST.read_text(encoding="utf-8"))
    whitelist = set(re.findall(r'"([^"]+)"', loanwords.split("static let words: Set<String> = [", 1)[1].split("\n    ]", 1)[0]))
    return romaji_to_vi, long_vowels, whitelist


def fold_macrons(word: str) -> str:
    value = word.lower()
    for source, target in MACRON.items():
        value = value.replace(source, target)
    return value


def strip_diacritics(word: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", word) if not unicodedata.combining(c))


def build_classifier(romaji_to_vi, whitelist):
    syllables = {"n"}
    for onset in ["", "k", "s", "t", "n", "h", "m", "y", "r", "w", "g", "z", "d", "b", "p"]:
        for vowel in "aiueo":
            syllables.add(onset + vowel)
    for palatal in ["ky", "sh", "ch", "ny", "hy", "my", "ry", "gy", "j", "by", "py"]:
        for vowel in "auo":
            syllables.add(palatal + vowel)
    for extra in ["shi", "chi", "tsu", "fu", "ji", "she", "che", "je", "ti", "di", "tu", "du",
                  "aa", "ii", "uu", "ee", "oo"]:
        syllables.add(extra)

    english_suffixes = ["ing", "ed", "tion", "sion", "ly", "ness", "ment", "able", "ible",
                        "ful", "less", "est", "ism", "ist", "ous", "ive"]
    english_clusters = ["th", "ph", "wh", "ck", "gh", "sc", "sp", "st", "sk", "sl", "sm", "sn",
                        "sw", "tr", "dr", "pr", "br", "cr", "gr", "fr", "bl", "cl", "fl", "gl",
                        "pl", "nt", "nd", "mp", "ng", "rt", "rd", "rn", "rm", "rl", "lt", "ld",
                        "lm", "lf", "ct", "pt", "xt", "ea", "oa", "ie", "au", "aw", "ow", "oy", "ay", "ey"]
    romaji_vowel_sequences = ["ou", "uu", "aa", "ii", "ee", "oo", "ai", "ei", "oi"]
    markers = ["tsu", "ryu", "ryo", "kyo", "kyu", "shu", "sho", "cha", "chu", "cho", "gyo"]
    threshold = 4

    def normalize(word):
        value = strip_diacritics(fold_macrons(word))
        return value

    def segment(word):
        parts, index = [], 0
        while index < len(word):
            matched = False
            for length in (3, 2, 1):
                if index + length > len(word):
                    continue
                candidate = word[index:index + length]
                if candidate not in syllables:
                    continue
                if candidate == "n" and length == 1 and index + 1 < len(word) and word[index + 1] in "aiueoy":
                    continue
                parts.append(candidate)
                index += length
                matched = True
                break
            if not matched:
                return None
        return parts

    def is_japanese(word):
        normalized = normalize(word)
        if normalized in whitelist:
            return True
        if len(normalized) < 2 or not (normalized.isascii() and normalized.isalpha()):
            return False
        if any(c in "lqvx" for c in normalized):
            return False
        simplified, sokuon, index = [], 0, 0
        while index < len(normalized):
            if index < len(normalized) - 1 and normalized[index] == normalized[index + 1] and normalized[index] not in "aiueo":
                sokuon += 1
                simplified.append(normalized[index])
                index += 2
            else:
                simplified.append(normalized[index])
                index += 1
        simplified = "".join(simplified)
        parts = segment(simplified)
        if not parts or len(parts) < 2:
            return False
        score = 0
        for suffix in english_suffixes:
            if normalized.endswith(suffix):
                score -= 3
                break
        score -= 2 * sum(1 for cluster in english_clusters if cluster in normalized)
        for marker in markers:
            if marker in simplified:
                score += 2
        score += 2 * sum(1 for sequence in romaji_vowel_sequences if sequence in simplified)
        if sokuon > 0:
            score += 2
        if simplified[-1] in "aiueo":
            score += 1
        if "n" in parts and len(parts) >= 3:
            score += 1
        return score >= threshold

    return is_japanese


def build_transliterator(romaji_to_vi, long_vowels):
    valid = set(romaji_to_vi)
    sokuon_coda = {"k": "c", "s": "t", "t": "t", "p": "p", "g": "c", "b": "p", "d": "t", "z": "t",
                   "n": "n", "m": "m"}

    def collapse(word):
        previous = None
        while word != previous:
            previous = word
            for source, target in long_vowels:
                word = word.replace(source, target)
        return word

    def normalize(word):
        value = strip_diacritics(fold_macrons(word))
        return collapse(value)

    def segment(word):
        parts, index = [], 0
        while index < len(word):
            matched = False
            for length in (3, 2, 1):
                if index + length > len(word):
                    continue
                candidate = word[index:index + length]
                if candidate not in valid:
                    continue
                if candidate == "n" and length == 1 and index + 1 < len(word) and word[index + 1] in "aiueony":
                    continue
                parts.append(candidate)
                index += length
                matched = True
                break
            if not matched:
                return None
        return parts

    def can_take_glide_i(syllable):
        return bool(syllable) and syllable[-1] in "a\u0103\u00e2e\u00ea" "o\u00f4\u01a1u\u01b0"

    def transliterate(word):
        normalized = normalize(word)
        sokuon, simplified, index = [], [], 0
        while index < len(normalized):
            if index < len(normalized) - 1 and normalized[index] == normalized[index + 1] and normalized[index] not in "aeiou":
                sokuon.append((len(simplified), normalized[index]))
                simplified.append(normalized[index])
                index += 2
            else:
                simplified.append(normalized[index])
                index += 1
        simplified = "".join(simplified)
        syllables = segment(simplified)
        if syllables is None:
            return word
        vi_syllables = [romaji_to_vi.get(s, s) for s in syllables]
        merged, merged_index = [], [0] * len(vi_syllables)
        for position, syllable in enumerate(vi_syllables):
            if syllable == "n" and position > 0 and merged:
                merged[-1] += "n"
            elif syllable == "i" and position > 0 and merged and can_take_glide_i(merged[-1]):
                merged[-1] += "i"
            else:
                merged.append(syllable)
            merged_index[position] = len(merged) - 1
        if sokuon:
            cursor, boundaries = 0, []
            for syllable in syllables:
                boundaries.append((cursor, cursor + len(syllable)))
                cursor += len(syllable)
            for sokuon_position, sokuon_char in sokuon:
                for syllable_index, (start, end) in enumerate(boundaries):
                    if start <= sokuon_position < end:
                        target = merged_index[syllable_index]
                        if 0 < target < len(merged):
                            merged[target - 1] += sokuon_coda.get(sokuon_char, sokuon_char)
                        break
        result = "-".join(merged)
        return word if result == "" else result

    return transliterate


def main():
    parser = argparse.ArgumentParser(description="Dựng lại từ điển phiên âm tiếng Nhật cho VieNeu-TTS.")
    parser.add_argument("--source", required=True, help="File .plist gốc (bản trên HuggingFace).")
    parser.add_argument("--output", required=True, help="File .plist đích.")
    args = parser.parse_args()

    romaji_to_vi, long_vowels, whitelist = load_tables()
    is_japanese = build_classifier(romaji_to_vi, whitelist)
    transliterate = build_transliterator(romaji_to_vi, long_vowels)

    raw = plistlib.load(open(args.source, "rb"))
    print(f"Khoá gốc: {len(raw)}")

    folded = {}
    for key in raw:
        folded[fold_macrons(key)] = key
    print(f"Sau khi gấp macron ở khoá: {len(folded)} (khoá trùng là bản ASCII/macron của cùng một từ)")

    japanese = sorted(k for k in folded if is_japanese(k))
    print(f"Qua bộ lọc tiếng Nhật: {len(japanese)}")

    result, replaced, hand_fixed, dropped, failed = {}, [], [], [], []
    for key in japanese:
        if key in DROPPED:
            dropped.append(key)
            continue
        if key in HAND_FIXED:
            result[key] = HAND_FIXED[key]
            hand_fixed.append(key)
            continue
        value = transliterate(key)
        if value == key:
            failed.append(key)
            result[key] = raw[folded[key]]
            continue
        result[key] = value.replace("-", " ")
        replaced.append(key)

    print(f"Phiên âm lại: {len(replaced)}")
    print(f"Đặt tay: {len(hand_fixed)} → {', '.join(hand_fixed)}")
    print(f"Đã xoá: {len(dropped)} → {', '.join(dropped)}")
    if failed:
        print(f"⚠️ Còn {len(failed)} mục KHÔNG phiên âm được, giữ giá trị cũ: {', '.join(failed)}")
    print(f"TỔNG KẾT: {len(result)} mục")

    non_ascii = [k for k in result if not k.isascii()]
    if non_ascii:
        print(f"⚠️ Khoá còn ngoài ASCII (không nên có): {non_ascii}")

    plistlib.dump(result, open(args.output, "wb"))
    print(f"Đã ghi: {args.output}")


if __name__ == "__main__":
    main()
