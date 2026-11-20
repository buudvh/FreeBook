"""Versioned, spelling-based token inventory shared by teacher, student and C runtime.

Token ids are the index in TOKENS. Changing the order or contents requires a
new PHONEME_SET_VERSION.

Prefixes: O: onset, G: on-glide, N: nucleus, C: coda, T1..T6 tones in the order
ngang, huyền, sắc, hỏi, ngã, nặng. The set is dialect-neutral: spellings that
merge in Hanoi speech (tr/ch, s/x, r/d/gi) stay distinct tokens.
"""

PHONEME_SET_VERSION = "1"

PAD, BOS, EOS, SPACE = "<pad>", "<bos>", "<eos>", " "
PUNCTUATION = (",", ".", "?", "!", ";", ":")

ONSETS = ("b", "k", "ch", "d", "đ", "g", "gi", "h", "kh", "l", "m", "n", "ng", "nh",
          "p", "ph", "r", "s", "t", "th", "tr", "v", "x")
NUCLEI = ("a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "iê", "uô", "ươ", "oo")
CODAS = ("c", "ch", "m", "n", "ng", "nh", "p", "t", "j", "w")
TONE_COUNT = 6

TOKENS: tuple[str, ...] = (
    (PAD, BOS, EOS, SPACE)
    + PUNCTUATION
    + tuple(f"O:{o}" for o in ONSETS)
    + ("G:w",)
    + tuple(f"N:{n}" for n in NUCLEI)
    + tuple(f"C:{c}" for c in CODAS)
    + tuple(f"T{i}" for i in range(1, TONE_COUNT + 1))
)
VOCAB_SIZE = len(TOKENS)

_TOKEN_TO_ID = {tok: i for i, tok in enumerate(TOKENS)}


def token_to_id(tok: str) -> int:
    return _TOKEN_TO_ID[tok]


def id_to_token(i: int) -> str:
    return TOKENS[i]


# ---------------- version 2: Vietnamese + English (ids 0..64 unchanged) ----------------
# English uses the 39 ARPAbet phonemes (CMUdict); a stress token S0/S1/S2 follows each vowel,
# the way a tone token follows each Vietnamese syllable.

PHONEME_SET_VERSION_V2 = "2"
ARPABET = ("AA", "AE", "AH", "AO", "AW", "AY", "B", "CH", "D", "DH", "EH", "ER", "EY", "F", "G",
           "HH", "IH", "IY", "JH", "K", "L", "M", "N", "NG", "OW", "OY", "P", "R", "S", "SH", "T",
           "TH", "UH", "UW", "V", "W", "Y", "Z", "ZH")
ARPABET_VOWELS = frozenset(("AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY",
                            "OW", "OY", "UH", "UW"))
STRESS = ("S0", "S1", "S2")

TOKENS_V2: tuple[str, ...] = TOKENS + tuple(f"EN:{p}" for p in ARPABET) + STRESS
VOCAB_SIZE_V2 = len(TOKENS_V2)

_TOKEN_TO_ID_V2 = {tok: i for i, tok in enumerate(TOKENS_V2)}


def token_to_id_v2(tok: str) -> int:
    return _TOKEN_TO_ID_V2[tok]


# ---------------- token set "zh-en": Mandarin + English (ids 0..106 = v2 unchanged) ----------------
# A model uses only the ids of its pair; the Vietnamese rows (8..64) stay unused by zh-en models
# so that the English rows (65..106) can be warm-started from a vi-en teacher. Mandarin syllables
# are [ZI:initial] ZF:final ZTtone; finals are written in full (iou, uei, uen; v for u-umlaut),
# "ii" is the apical vowel after zh/ch/sh/r and "i0" after z/c/s. Tone 5 is the neutral tone.

TOKEN_SET_V2 = "vi-en"
TOKEN_SET_ZHEN = "zh-en"

ZH_INITIALS = ("b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
               "zh", "ch", "sh", "r", "z", "c", "s")
ZH_FINALS = ("a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "er",
             "i", "ia", "ie", "iao", "iou", "ian", "in", "iang", "ing", "iong",
             "u", "ua", "uo", "uai", "uei", "uan", "uen", "uang", "ueng",
             "v", "ve", "van", "vn", "ii", "i0")
ZH_TONE_COUNT = 5

TOKENS_ZHEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"ZI:{i}" for i in ZH_INITIALS)
    + tuple(f"ZF:{f}" for f in ZH_FINALS)
    + tuple(f"ZT{i}" for i in range(1, ZH_TONE_COUNT + 1))
)
VOCAB_SIZE_ZHEN = len(TOKENS_ZHEN)

TOKEN_SETS: dict[str, tuple[str, ...]] = {TOKEN_SET_V2: TOKENS_V2, TOKEN_SET_ZHEN: TOKENS_ZHEN}

_TOKEN_TO_ID_ZHEN = {tok: i for i, tok in enumerate(TOKENS_ZHEN)}


def token_to_id_zhen(tok: str) -> int:
    return _TOKEN_TO_ID_ZHEN[tok]


# ---------------- token set "ko-en": Korean + English (ids 0..106 = v2 unchanged) ----------------
# Phoneme-level tokens after the standard pronunciation rules (src/vtts/frontend/ko/): a syllable
# is [KO:I:onset] KO:V:vowel [KO:C:coda]. The silent onset ㅇ has no token; vowels include the
# glides (ya, wa, ui, ...); codas are the 7 coda sounds. Names are romanized (Revised Romanization
# letters; ㄹ is "r" as an onset and "l" as a coda). Korean has no lexical tone.

TOKEN_SET_KOEN = "ko-en"

KO_ONSETS = ("g", "kk", "k", "d", "tt", "t", "b", "pp", "p", "s", "ss", "j", "jj", "ch", "h",
             "n", "m", "r")
KO_VOWELS = ("a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u",
             "wo", "we", "wi", "yu", "eu", "ui", "i")
KO_CODAS = ("k", "n", "t", "l", "m", "p", "ng")

TOKENS_KOEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"KO:I:{o}" for o in KO_ONSETS)
    + tuple(f"KO:V:{v}" for v in KO_VOWELS)
    + tuple(f"KO:C:{c}" for c in KO_CODAS)
)
VOCAB_SIZE_KOEN = len(TOKENS_KOEN)

TOKEN_SETS[TOKEN_SET_KOEN] = TOKENS_KOEN

_TOKEN_TO_ID_KOEN = {tok: i for i, tok in enumerate(TOKENS_KOEN)}


def token_to_id_koen(tok: str) -> int:
    return _TOKEN_TO_ID_KOEN[tok]


# ---------------- token set "ja-en": Japanese + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes in the style of Open JTalk (src/vtts/frontend/ja/): a mora is [JA:consonant] JA:vowel,
# or JA:N (moraic nasal ん) or JA:cl (geminate っ). Palatalized consonants are one token (ky, sh,
# ch, j, ...); ts f v ty dy serve loanword kana (ツァ ファ ヴァ テュ デュ). A long vowel is the vowel repeated (トー -> t o o), not a
# separate token. Devoiced vowels and pitch accent are not marked in version 1.

TOKEN_SET_JAEN = "ja-en"

JA_VOWELS = ("a", "i", "u", "e", "o")
JA_CONSONANTS = ("k", "g", "s", "z", "t", "d", "n", "h", "b", "p", "m", "y", "r", "w",
                 "ky", "gy", "sh", "j", "ch", "ny", "hy", "by", "py", "my", "ry",
                 "ts", "f", "v", "ty", "dy")
JA_SPECIAL = ("N", "cl")

TOKENS_JAEN: tuple[str, ...] = (
    TOKENS_V2 + tuple(f"JA:{p}" for p in JA_VOWELS + JA_CONSONANTS + JA_SPECIAL)
)
VOCAB_SIZE_JAEN = len(TOKENS_JAEN)

TOKEN_SETS[TOKEN_SET_JAEN] = TOKENS_JAEN

_TOKEN_TO_ID_JAEN = {tok: i for i, tok in enumerate(TOKENS_JAEN)}


def token_to_id_jaen(tok: str) -> int:
    return _TOKEN_TO_ID_JAEN[tok]


# ---------------- token set "es-en": Spanish + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/es/: vowels, the same vowels stressed
# (a1 = stressed a), the glides of diphthongs (j as in "tiene", w as in "bueno") and consonants.
# Dialect-neutral like the Vietnamese set: spellings that merge in some dialects stay distinct
# (th = c/z as in "cielo", "zapato" vs s; ll vs y). b/v are one phoneme; allophones (b d g
# spirantized, n assimilated) are left to the model.

TOKEN_SET_ESEN = "es-en"

ES_VOWELS = ("a", "e", "i", "o", "u")
ES_GLIDES = ("j", "w")
ES_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "th", "s", "x", "ch", "y", "ll", "m", "n",
                 "ny", "l", "r", "rr")

TOKENS_ESEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"ES:{v}" for v in ES_VOWELS)
    + tuple(f"ES:{v}1" for v in ES_VOWELS)
    + tuple(f"ES:{c}" for c in ES_GLIDES + ES_CONSONANTS)
)
VOCAB_SIZE_ESEN = len(TOKENS_ESEN)

TOKEN_SETS[TOKEN_SET_ESEN] = TOKENS_ESEN


# ---------------- token set "id-en": Indonesian + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/id/: six vowels (e = the e of "enak",
# @ = the schwa of "besar"), the stressed vowels (the schwa is never stressed) and consonants
# (? = glottal stop: final k, apostrophe; sy, kh for loanwords; v is read f).

TOKEN_SET_IDEN = "id-en"

ID_VOWELS = ("a", "i", "u", "e", "@", "o")
ID_STRESSED = ("a", "i", "u", "e", "o")
ID_CONSONANTS = ("p", "b", "t", "d", "k", "g", "?", "c", "j", "f", "s", "z", "sy", "kh", "h", "m",
                 "n", "ny", "ng", "l", "r", "w", "y")

TOKENS_IDEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"ID:{v}" for v in ID_VOWELS)
    + tuple(f"ID:{v}1" for v in ID_STRESSED)
    + tuple(f"ID:{c}" for c in ID_CONSONANTS)
)
VOCAB_SIZE_IDEN = len(TOKENS_IDEN)

TOKEN_SETS[TOKEN_SET_IDEN] = TOKENS_IDEN


# ---------------- token set "pt-en": Brazilian Portuguese + English (ids 0..106 = v2 unchanged) ----
# Phonemes from the spelling rules of src/vtts/frontend/pt/: oral vowels, nasal vowels (an en in
# on un), the stressed vowels with open E/O (é, ó), the glides j/w of diphthongs and nasal
# diphthongs (pai, mão, bem) and consonants (sh zh nh lh; r = the tap of "caro", rr = the strong r
# of "carro", "rio" and of a syllable-final r). Final unstressed e/o are written i/u (leite, carro);
# t/d before i and syllable-final l are left to the voice (palatalized, vocalized in Brazil).

TOKEN_SET_PTEN = "pt-en"

PT_VOWELS = ("a", "e", "i", "o", "u")
PT_STRESSED = ("a", "e", "E", "i", "o", "O", "u")
PT_NASALS = ("an", "en", "in", "on", "un")
PT_CONSONANTS = ("j", "w", "p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "sh", "zh", "m", "n",
                 "nh", "l", "lh", "r", "rr")

TOKENS_PTEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"PT:{v}" for v in PT_VOWELS)
    + tuple(f"PT:{v}1" for v in PT_STRESSED)
    + tuple(f"PT:{v}" for v in PT_NASALS)
    + tuple(f"PT:{v}1" for v in PT_NASALS)
    + tuple(f"PT:{c}" for c in PT_CONSONANTS)
)
VOCAB_SIZE_PTEN = len(TOKENS_PTEN)

TOKEN_SETS[TOKEN_SET_PTEN] = TOKENS_PTEN


# ---------------- token set "hi-en": Hindi + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the Devanagari rules of src/vtts/frontend/hi/ (schwa deletion applied). Vowels: a
# (the schwa of अ), aa i ii u uu e, ai (ऐ, also ॅ), o, au (औ, also ऑ); "~" nasalizes the vowel
# before it (chandrabindu, anusvara before a non-stop or after a long vowel). Consonants in ITRANS
# style: c ch = च छ, T Th D Dh N = retroflex ट ठ ड ढ ण, R Rh = the flaps ड़ ढ़, ng ny = ङ ञ, sh = श
# and ष (merged), q x G z f = the nukta consonants क़ ख़ ग़ ज़ फ़. ऋ is read r i; no stress.

TOKEN_SET_HIEN = "hi-en"

HI_VOWELS = ("a", "aa", "i", "ii", "u", "uu", "e", "ai", "o", "au")
HI_NASAL = "~"
HI_CONSONANTS = ("k", "kh", "g", "gh", "ng", "c", "ch", "j", "jh", "ny",
                 "T", "Th", "D", "Dh", "N", "t", "th", "d", "dh", "n",
                 "p", "ph", "b", "bh", "m", "y", "r", "l", "v", "sh", "s", "h",
                 "R", "Rh", "q", "x", "G", "z", "f")

TOKENS_HIEN: tuple[str, ...] = (
    TOKENS_V2 + tuple(f"HI:{p}" for p in HI_VOWELS + (HI_NASAL,) + HI_CONSONANTS)
)
VOCAB_SIZE_HIEN = len(TOKENS_HIEN)

TOKEN_SETS[TOKEN_SET_HIEN] = TOKENS_HIEN


# ---------------- token set "th-en": Thai + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/th/: a syllable is TH:I:initial
# [TH:I:second consonant of a cluster] TH:V:vowel [TH:F:final] TH:Ttone. Initials are the 21
# initial sounds (? = the glottal stop of อ); vowels are the nine monophthongs short and long
# (ue = ɯ, ae = ɛ, or = ɔ, oe = ɤ; doubled letters = long) and the diphthongs ia, uea, ua; finals
# are the six final sounds k p t m n ng and the glides w j. Tones T1..T5: mid, low, falling, high,
# rising (สามัญ เอก โท ตรี จัตวา).

TOKEN_SET_THEN = "th-en"

TH_INITIALS = ("p", "ph", "b", "t", "th", "d", "k", "kh", "c", "ch", "?", "m", "n", "ng", "f",
               "s", "h", "j", "r", "l", "w")
TH_VOWELS = ("a", "aa", "i", "ii", "ue", "uue", "u", "uu", "e", "ee", "ae", "aae", "o", "oo",
             "or", "oor", "oe", "ooe", "ia", "uea", "ua")
TH_FINALS = ("k", "p", "t", "m", "n", "ng", "w", "j")
TH_TONE_COUNT = 5

TOKENS_THEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"TH:I:{c}" for c in TH_INITIALS)
    + tuple(f"TH:V:{v}" for v in TH_VOWELS)
    + tuple(f"TH:F:{c}" for c in TH_FINALS)
    + tuple(f"TH:T{i}" for i in range(1, TH_TONE_COUNT + 1))
)
VOCAB_SIZE_THEN = len(TOKENS_THEN)

TOKEN_SETS[TOKEN_SET_THEN] = TOKENS_THEN


# ---------------- token set "fr-en": French + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes of standard (metropolitan) French from the spelling rules of src/vtts/frontend/fr/,
# after silent letters, liaison, elision and e-muet deletion. Oral vowels: i e E a O o u y,
# eu = ø (feu), oe = œ (peur), @ = the schwa (petit); a/ɑ are one vowel. Nasal vowels: an (ɑ̃
# enfant), on (ɔ̃ bon), in (ɛ̃ vin), un (œ̃ brun). Glides: j (pied), w (oui), H = ɥ (huit).
# Consonants: sh = ʃ, zh = ʒ, gn = ɲ (montagne), ng = ŋ (loanwords: parking), r = the uvular r.
# French has no lexical stress (the phrase-final syllable is stressed): no stress tokens.

TOKEN_SET_FREN = "fr-en"

FR_VOWELS = ("i", "e", "E", "a", "O", "o", "u", "y", "eu", "oe", "@")
FR_NASALS = ("an", "on", "in", "un")
FR_GLIDES = ("j", "w", "H")
FR_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "sh", "zh", "m", "n", "gn",
                 "ng", "l", "r")

TOKENS_FREN: tuple[str, ...] = (
    TOKENS_V2 + tuple(f"FR:{p}" for p in FR_VOWELS + FR_NASALS + FR_GLIDES + FR_CONSONANTS)
)
VOCAB_SIZE_FREN = len(TOKENS_FREN)

TOKEN_SETS[TOKEN_SET_FREN] = TOKENS_FREN


# ---------------- token set "de-en": German + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes (German SAMPA names) from the rules of src/vtts/frontend/de/: 18 full vowels, short lax
# (a E I O U Y 9) and long tense (a: e: E: i: o: u: y: 2:) and the diphthongs aI aU OY, each also
# stressed (a1 = stressed a, a:1 = stressed a:); the schwa @ and the vocalized r 6 (der, Uhr,
# Lehrer) are never stressed. An unstressed tense vowel (the o of Politik) is the long token.
# Consonants: C = ich-Laut, x = ach-Laut, S = sch, Z = the j of Garage, N = ng, R = consonantal r,
# ? = glottal stop (vowel at the start of a word or morpheme); affricates are two tokens (t s,
# p f, t S). Final devoicing is applied (Tag -> t a:1 k).

TOKEN_SET_DEEN = "de-en"

DE_VOWELS = ("a", "a:", "E", "e:", "E:", "I", "i:", "O", "o:", "U", "u:", "Y", "y:", "9", "2:",
             "aI", "aU", "OY")
DE_REDUCED = ("@", "6")
DE_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "S", "Z", "C", "x", "h", "j",
                 "m", "n", "N", "l", "R", "?")

TOKENS_DEEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"DE:{v}" for v in DE_VOWELS)
    + tuple(f"DE:{v}1" for v in DE_VOWELS)
    + tuple(f"DE:{v}" for v in DE_REDUCED + DE_CONSONANTS)
)
VOCAB_SIZE_DEEN = len(TOKENS_DEEN)

TOKEN_SETS[TOKEN_SET_DEEN] = TOKENS_DEEN


# ---------------- token set "it-en": Italian + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/it/: five vowels, the stressed vowels with
# open E/O (è, ò: "bène", "buòno") and closed e/o, the glides j/w (piano, buono) and consonants
# (ch dj = c/g before e/i, sh = sc, ny = gn, ly = gli, ts dz = z, z = voiced s of "casa"). A long
# (geminate) consonant is the consonant twice (fatto -> f a1 t t o), as are ny ly sh ts dz between
# vowels.

TOKEN_SET_ITEN = "it-en"

IT_VOWELS = ("a", "e", "i", "o", "u")
IT_STRESSED = ("a", "e", "E", "i", "o", "O", "u")
IT_CONSONANTS = ("j", "w", "p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "ts", "dz", "ch",
                 "dj", "sh", "m", "n", "ny", "l", "ly", "r")

TOKENS_ITEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"IT:{v}" for v in IT_VOWELS)
    + tuple(f"IT:{v}1" for v in IT_STRESSED)
    + tuple(f"IT:{c}" for c in IT_CONSONANTS)
)
VOCAB_SIZE_ITEN = len(TOKENS_ITEN)

TOKEN_SETS[TOKEN_SET_ITEN] = TOKENS_ITEN


# ---------------- token set "tr-en": Turkish + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/tr/: eight vowels (I = ı, oe = ö,
# ue = ü), the same vowels stressed, "long" after a lengthened vowel (dağ, hâlâ, öğretmen) and
# consonants (c = c of "cam", ch = ç, sh = ş, zh = j, y = y; ky gy = the palatal k g before â û of
# loanwords: kâr, rüzgâr). A doubled consonant is the consonant twice (anne -> a n n e1).

TOKEN_SET_TREN = "tr-en"

TR_VOWELS = ("a", "e", "I", "i", "o", "oe", "u", "ue")
TR_CONSONANTS = ("long", "b", "c", "ch", "d", "f", "g", "gy", "h", "zh", "k", "ky", "l", "m", "n",
                 "p", "r", "s", "sh", "t", "v", "y", "z")

TOKENS_TREN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"TR:{v}" for v in TR_VOWELS)
    + tuple(f"TR:{v}1" for v in TR_VOWELS)
    + tuple(f"TR:{c}" for c in TR_CONSONANTS)
)
VOCAB_SIZE_TREN = len(TOKENS_TREN)

TOKEN_SETS[TOKEN_SET_TREN] = TOKENS_TREN


# ---------------- token set "ru-en": Russian + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the rules of src/vtts/frontend/ru/: stressed vowels a1 e1 i1 o1 u1 y1 (y = ы);
# unstressed vowels after vowel reduction: a (first syllable before the stress and the absolute
# start of a word, after a hard consonant), @ (other unstressed a/o, final unstressed я/а), i
# (unstressed е/я/а after a soft consonant: ikanye), u, y. Consonants: the hard/soft pairs
# (p p' ... x x', "'" = palatalized) and the unpaired sh zh ts (always hard), ch shch j (always
# soft). Voicing assimilation and final devoicing are applied; geminates are written once.

TOKEN_SET_RUEN = "ru-en"

RU_VOWELS = ("a", "i", "u", "y", "@")
RU_STRESSED = ("a", "e", "i", "o", "u", "y")
RU_PAIRED = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "m", "n", "l", "r", "x")
RU_UNPAIRED = ("sh", "zh", "ts", "ch", "shch", "j")

TOKENS_RUEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"RU:{v}" for v in RU_VOWELS)
    + tuple(f"RU:{v}1" for v in RU_STRESSED)
    + tuple(f"RU:{c}" for c in RU_PAIRED)
    + tuple(f"RU:{c}'" for c in RU_PAIRED)
    + tuple(f"RU:{c}" for c in RU_UNPAIRED)
)
VOCAB_SIZE_RUEN = len(TOKENS_RUEN)

TOKEN_SETS[TOKEN_SET_RUEN] = TOKENS_RUEN


# ---------------- token set "pl-en": Polish + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/pl/: vowels a e i o u y and the nasal vowels
# on (ą) en (ę), each also stressed (a1 ... en1; the stress is on the second-to-last syllable);
# consonants with sh zh ch dzh (sz ż/rz cz dż), the soft s' z' c' dz' n' (ś ź ć dź ń), x (ch h),
# w (ł), v (w), ts dz (c dz). ki gi before a vowel are k j / g j (kiedy). Nasal vowels before stops
# are written as vowel + nasal consonant; voicing assimilation and final devoicing are applied.

TOKEN_SET_PLEN = "pl-en"

PL_VOWELS = ("a", "e", "i", "o", "u", "y", "on", "en")
PL_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "sh", "zh", "s'",
                 "z'", "x", "ts", "dz", "ch", "dzh", "c'", "dz'", "m", "n", "n'", "l", "w", "r", "j")

TOKENS_PLEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"PL:{v}" for v in PL_VOWELS)
    + tuple(f"PL:{v}1" for v in PL_VOWELS)
    + tuple(f"PL:{c}" for c in PL_CONSONANTS)
)
VOCAB_SIZE_PLEN = len(TOKENS_PLEN)

TOKEN_SETS[TOKEN_SET_PLEN] = TOKENS_PLEN
# ---------------- token set "ar-en": Arabic + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes of Modern Standard Arabic from src/vtts/frontend/ar/ (vowels restored, pausal form): 28
# consonants (? = hamza, H = ح, x = خ, 3 = ع, gh = غ, th dh = ث ذ, sh = ش, S D T Z = the emphatics
# ص ض ط ظ) and the loanword consonants g v; short and long vowels a i u aa ii uu and the same
# vowels stressed (a1 = stressed a). A geminate (shadda) is the consonant twice.

TOKEN_SET_AREN = "ar-en"

AR_CONSONANTS = ("?", "b", "t", "th", "j", "H", "x", "d", "dh", "r", "z", "s", "sh", "S", "D",
                 "T", "Z", "3", "gh", "f", "q", "k", "l", "m", "n", "h", "w", "y", "g", "v")
AR_VOWELS = ("a", "i", "u", "aa", "ii", "uu")

TOKENS_AREN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"AR:{c}" for c in AR_CONSONANTS)
    + tuple(f"AR:{v}" for v in AR_VOWELS)
    + tuple(f"AR:{v}1" for v in AR_VOWELS)
)
VOCAB_SIZE_AREN = len(TOKENS_AREN)

TOKEN_SETS[TOKEN_SET_AREN] = TOKENS_AREN
# ---------------- token set "fi-en": Finnish + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/fi/: the eight vowels (ae = ä, oe = ö), the
# same vowels stressed (the first vowel of a word and of each part of a number word), the length
# mark ":" after a long vowel or consonant (written double: saari s a1 : r i, kukka k u1 k : a;
# ng is the long velar nasal "ng :"), and consonants with the loan sounds b d g f sh zh.
# Diphthongs are two vowel tokens.

TOKEN_SET_FIEN = "fi-en"

FI_VOWELS = ("a", "e", "i", "o", "u", "y", "ae", "oe")
FI_LENGTH = ":"
FI_CONSONANTS = ("p", "t", "k", "b", "d", "g", "f", "s", "sh", "zh", "h", "v", "j", "l", "r", "m",
                 "n", "ng")

TOKENS_FIEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"FI:{v}" for v in FI_VOWELS)
    + tuple(f"FI:{v}1" for v in FI_VOWELS)
    + (f"FI:{FI_LENGTH}",)
    + tuple(f"FI:{c}" for c in FI_CONSONANTS)
)
VOCAB_SIZE_FIEN = len(TOKENS_FIEN)

TOKEN_SETS[TOKEN_SET_FIEN] = TOKENS_FIEN


# ---------------- token set "el-en": Greek + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/el/: five vowels, the same vowels stressed
# (the tonos), consonants with the fricatives th dh gh (θ δ γ) and x (χ), the affricates ts dz, the
# velar nasal ng (γγ, γκ, γχ inside a word) and the glide j (an unstressed i before a vowel:
# παιδιά p e dh j a1). Palatal allophones of k g x gh before e/i are left to the voice.

TOKEN_SET_ELEN = "el-en"

EL_VOWELS = ("a", "e", "i", "o", "u")
EL_CONSONANTS = ("p", "t", "k", "b", "d", "g", "f", "v", "th", "dh", "gh", "s", "z", "x", "ts", "dz",
                 "m", "n", "ng", "l", "r", "j")

TOKENS_ELEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"EL:{v}" for v in EL_VOWELS)
    + tuple(f"EL:{v}1" for v in EL_VOWELS)
    + tuple(f"EL:{c}" for c in EL_CONSONANTS)
)
VOCAB_SIZE_ELEN = len(TOKENS_ELEN)

TOKEN_SETS[TOKEN_SET_ELEN] = TOKENS_ELEN
# ---------------- token set "ms-en": Malay + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/ms/ (shared with Indonesian): the six
# Indonesian vowels (e = the e taling of "elok", @ = the e pepet of "besar"), the stressed vowels
# (the schwa is never stressed) and the Indonesian consonants plus v (universiti), gh (ghaib) and
# dh, th (Ramadhan, Mahathir: Arabic loanwords and names) of Malay spelling. Final a is a
# (standard reading, not the schwa).

TOKEN_SET_MSEN = "ms-en"

MS_VOWELS = ("a", "i", "u", "e", "@", "o")
MS_STRESSED = ("a", "i", "u", "e", "o")
MS_CONSONANTS = ("p", "b", "t", "d", "k", "g", "?", "c", "j", "f", "v", "s", "z", "sy", "kh", "gh",
                 "dh", "th", "h", "m", "n", "ny", "ng", "l", "r", "w", "y")

TOKENS_MSEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"MS:{v}" for v in MS_VOWELS)
    + tuple(f"MS:{v}1" for v in MS_STRESSED)
    + tuple(f"MS:{c}" for c in MS_CONSONANTS)
)
VOCAB_SIZE_MSEN = len(TOKENS_MSEN)

TOKEN_SETS[TOKEN_SET_MSEN] = TOKENS_MSEN


# ---------------- token set "tl-en": Tagalog + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/tl/: five vowels (e/i and o/u as written),
# the same vowels stressed, the native consonants with the glottal stop ? (between vowels, after a
# hyphen, word-final in malumi/maragsa words) and ng, and the loanword consonants f v z j ch sh.

TOKEN_SET_TLEN = "tl-en"

TL_VOWELS = ("a", "e", "i", "o", "u")
TL_CONSONANTS = ("p", "b", "t", "d", "k", "g", "?", "m", "n", "ng", "s", "h", "l", "r", "w", "y",
                 "f", "v", "z", "j", "ch", "sh")

TOKENS_TLEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"TL:{v}" for v in TL_VOWELS)
    + tuple(f"TL:{v}1" for v in TL_VOWELS)
    + tuple(f"TL:{c}" for c in TL_CONSONANTS)
)
VOCAB_SIZE_TLEN = len(TOKENS_TLEN)

TOKEN_SETS[TOKEN_SET_TLEN] = TOKENS_TLEN


# ---------------- token set "sw-en": Swahili + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/sw/: five vowels, the same vowels stressed
# (penultimate stress), the consonants with the digraphs ch sh ny th dh gh kh and ng (the velar
# nasal of ng'ombe), and the prenasalized stops mb nd nj ngg (ngg = the ng of ngoma). Syllabic m/n
# (mtu, nchi) are the plain nasal tokens.

TOKEN_SET_SWEN = "sw-en"

SW_VOWELS = ("a", "e", "i", "o", "u")
SW_CONSONANTS = ("p", "b", "t", "d", "k", "g", "ch", "j", "f", "v", "s", "z", "sh", "h", "m", "n",
                 "ny", "ng", "l", "r", "w", "y", "th", "dh", "gh", "kh", "mb", "nd", "nj", "ngg")

TOKENS_SWEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"SW:{v}" for v in SW_VOWELS)
    + tuple(f"SW:{v}1" for v in SW_VOWELS)
    + tuple(f"SW:{c}" for c in SW_CONSONANTS)
)
VOCAB_SIZE_SWEN = len(TOKENS_SWEN)

TOKEN_SETS[TOKEN_SET_SWEN] = TOKENS_SWEN


# ---------------- token set "nl-en": Dutch + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/nl/ (SAMPA-like names): short vowels A E I
# O Y, long vowels a: e: o: 2: and i (ie) u (oe) y (uu), diphthongs Ei (ei/ij) 9y (ui) Au (au/ou),
# each also stressed with "1" (a:1 = stressed a:); the schwa @ is never stressed. Consonants: x = g
# and ch (the northern merger of the velar fricatives), N = ng, S = sj, Z = the g of garage, w = the
# labiodental w, g only in loanwords. Final devoicing is applied (hond -> h O1 n t).

TOKEN_SET_NLEN = "nl-en"

NL_VOWELS = ("A", "E", "I", "O", "Y", "a:", "e:", "i", "o:", "u", "y", "2:", "Ei", "9y", "Au")
NL_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "z", "x", "h", "S", "Z", "m", "n",
                 "N", "l", "r", "w", "j")

TOKENS_NLEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"NL:{v}" for v in NL_VOWELS)
    + tuple(f"NL:{v}1" for v in NL_VOWELS)
    + ("NL:@",)
    + tuple(f"NL:{c}" for c in NL_CONSONANTS)
)
VOCAB_SIZE_NLEN = len(TOKENS_NLEN)

TOKEN_SETS[TOKEN_SET_NLEN] = TOKENS_NLEN


# ---------------- token set "sv-en": Swedish + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/sv/ and scand_g2p.py (Central Standard
# Swedish, SAMPA-like names). Long vowels i: y: e: E: {: 2: 9: }: u: o: A: (}: = the long u, u: = the
# long o, o: = the long å, {: and 9: = ä and ö before r); short vowels I Y e E { 9 8 U O a (8 = the
# short u); the schwa @. A tone token follows the stressed vowel: '1 (accent 1) or '2 (accent 2); ","
# marks a secondary stress. Consonants: S = sj-ljud, C = tj-ljud, N = ng, and the retroflex t` d` n` s`
# l` from r + t d n s l.

TOKEN_SET_SVEN = "sv-en"

SV_VOWELS = ("i:", "y:", "e:", "E:", "{:", "2:", "9:", "}:", "u:", "o:", "A:",
             "I", "Y", "e", "E", "{", "9", "8", "U", "O", "a", "@")
SV_PROSODY = ("'1", "'2", ",")
SV_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "S", "C", "h", "m", "n", "N", "l", "r",
                 "j", "t`", "d`", "n`", "s`", "l`")

TOKENS_SVEN: tuple[str, ...] = (
    TOKENS_V2 + tuple(f"SV:{p}" for p in SV_VOWELS + SV_PROSODY + SV_CONSONANTS)
)
VOCAB_SIZE_SVEN = len(TOKENS_SVEN)

TOKEN_SETS[TOKEN_SET_SVEN] = TOKENS_SVEN


# ---------------- token set "no-en": Norwegian + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/no/ and scand_g2p.py (Bokmål with Urban East
# Norwegian pronunciation, SAMPA-like names). Long vowels i: y: e: {: 2: }: u: o: A: ({: = æ, }: = the
# long u, u: = the long o, o: = the long å); short vowels I Y E { 9 } U O A; the diphthongs {I (ei),
# 9Y (øy), {} (au), Ai (ai); the schwa @. A tone token follows the stressed vowel: '1 (tonem 1) or '2
# (tonem 2); "," marks a secondary stress. Consonants: S = sj-lyd, C = kj-lyd, N = ng, and the
# retroflex t` d` n` s` l` from r + t d n s l.

TOKEN_SET_NOEN = "no-en"

NO_VOWELS = ("i:", "y:", "e:", "{:", "2:", "}:", "u:", "o:", "A:",
             "I", "Y", "E", "{", "9", "}", "U", "O", "A", "{I", "9Y", "{}", "Ai", "@")
NO_PROSODY = ("'1", "'2", ",")
NO_CONSONANTS = ("p", "b", "t", "d", "k", "g", "f", "v", "s", "S", "C", "h", "m", "n", "N", "l", "r",
                 "j", "t`", "d`", "n`", "s`", "l`")

TOKENS_NOEN: tuple[str, ...] = (
    TOKENS_V2 + tuple(f"NO:{p}" for p in NO_VOWELS + NO_PROSODY + NO_CONSONANTS)
)
VOCAB_SIZE_NOEN = len(TOKENS_NOEN)

TOKEN_SETS[TOKEN_SET_NOEN] = TOKENS_NOEN


# ---------------- token set "da-en": Danish + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes in the NST SAMPA notation (src/vtts/frontend/da/, lexicon from the NST pronunciation
# lexicon for Danish): 15 short vowels (i e E a A y 2 9 u o O Q, @ = schwa, V = the open o of
# "op" and "kom", 6 = the r-schwa of "-er"), 12 long vowels, the glides j~ w 6~ (vocalized j,
# v/g and r after a vowel: vej, hav, bord), 18 consonants (p t k aspirated, b d g unaspirated
# (also after s and after a vowel), D = soft d, R = the onset r, N = ng, s' = sj), the stød "?"
# (after the long vowel or the voiced consonant that carries it), and the stress marks '"'
# (primary) and "%" (secondary) after the stressed vowel.

TOKEN_SET_DAEN = "da-en"

DA_SHORT = ("i", "e", "E", "a", "A", "y", "2", "9", "u", "o", "O", "Q", "@", "V", "6")
DA_LONG = ("i:", "e:", "E:", "a:", "A:", "y:", "2:", "9:", "u:", "o:", "O:", "Q:")
DA_GLIDES = ("j~", "w", "6~")
DA_CONSONANTS = ("p", "t", "k", "b", "d", "g", "f", "v", "s", "s'", "h", "m", "n", "N", "l", "R",
                 "j", "D")
DA_PROSODY = ("?", '"', "%")

TOKENS_DAEN: tuple[str, ...] = (
    TOKENS_V2 + tuple(f"DA:{p}" for p in DA_SHORT + DA_LONG + DA_GLIDES + DA_CONSONANTS + DA_PROSODY)
)
VOCAB_SIZE_DAEN = len(TOKENS_DAEN)

TOKEN_SETS[TOKEN_SET_DAEN] = TOKENS_DAEN


# ---------------- token set "lo-en": Lao + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes from the spelling rules of src/vtts/frontend/lo/ (the layout of th-en): a syllable is
# LO:I:initial [LO:I:second consonant: w of ກວ, l of ຼ] LO:V:vowel [LO:F:final] LO:Ttone. Initials
# are the 21 initial sounds (c = ຈ, ny = ຍ, j = ຢ, ? = the glottal stop of ອ); vowels the nine
# monophthongs short and long (ue = ɯ, ae = ɛ, or = ɔ, oe = ɤ; doubled = long) and the diphthongs
# ia, uea, ua; finals the six final sounds k p t m n ng and the glides w j. Tones T1..T6 of
# Vientiane Lao: low rising, high rising, mid, low falling, high falling, mid rising.

TOKEN_SET_LOEN = "lo-en"

LO_INITIALS = ("k", "kh", "ng", "c", "s", "ny", "d", "t", "th", "n", "b", "p", "ph", "f", "m", "j",
               "r", "l", "w", "h", "?")
LO_VOWELS = ("a", "aa", "i", "ii", "ue", "uue", "u", "uu", "e", "ee", "ae", "aae", "o", "oo",
             "or", "oor", "oe", "ooe", "ia", "uea", "ua")
LO_FINALS = ("k", "p", "t", "m", "n", "ng", "w", "j")
LO_TONE_COUNT = 6

TOKENS_LOEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"LO:I:{c}" for c in LO_INITIALS)
    + tuple(f"LO:V:{v}" for v in LO_VOWELS)
    + tuple(f"LO:F:{c}" for c in LO_FINALS)
    + tuple(f"LO:T{i}" for i in range(1, LO_TONE_COUNT + 1))
)
VOCAB_SIZE_LOEN = len(TOKENS_LOEN)

TOKEN_SETS[TOKEN_SET_LOEN] = TOKENS_LOEN


# ---------------- token set "km-en": Khmer + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes of the Khmer rules and lexicon of src/vtts/frontend/km/ (the phonemes of the Google Khmer
# lexicon): a syllable is KM:consonant [KM:consonant [KM:consonant]] KM:vowel [KM:F:final].
# Consonants: ? = glottal stop, b d = the implosives ɓ ɗ, ny ng = ɲ ŋ, aspirated kh ch th ph, and f g
# z of loanwords. Vowels: short and long (doubled) i y(ɨ) u e @(ə) o E(ɛ) a A(ɑ) O(ɔ), and ae a@ ao
# ie i@ ea oa u@ y@ E@ (the two series of the script give different vowels, the token is the
# sound). Finals: ? k c t p m n ny ng j w l h and f s of loanwords. Khmer has no tone; no stress.

TOKEN_SET_KMEN = "km-en"

KM_CONSONANTS = ("?", "k", "kh", "c", "ch", "d", "t", "th", "b", "p", "ph", "m", "n", "ny", "ng",
                 "j", "r", "l", "w", "s", "h", "f", "g", "z")
KM_VOWELS = ("i", "ii", "y", "yy", "u", "uu", "e", "ee", "@", "@@", "o", "oo", "E", "EE", "a", "aa",
             "A", "AA", "O", "OO", "ae", "a@", "ao", "ie", "i@", "ea", "oa", "u@", "y@", "E@")
KM_FINALS = ("?", "k", "c", "t", "p", "m", "n", "ny", "ng", "j", "w", "l", "h", "f", "s")

TOKENS_KMEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"KM:{c}" for c in KM_CONSONANTS)
    + tuple(f"KM:{v}" for v in KM_VOWELS)
    + tuple(f"KM:F:{c}" for c in KM_FINALS)
)
VOCAB_SIZE_KMEN = len(TOKENS_KMEN)

TOKEN_SETS[TOKEN_SET_KMEN] = TOKENS_KMEN


# ---------------- token set "my-en": Burmese + English (ids 0..106 = v2 unchanged) ----------------
# Phonemes of the Burmese rules of src/vtts/frontend/my/ (after Google's Burmese grammar): a syllable
# is MY:I:initial [MY:M:y] [MY:M:w] MY:V:vowel [MY:F:N | MY:F:?] [MY:Ttone]. Initials: hng hny hn hm
# hl hw the voiceless nasals, laterals and w (ှ), S = ʃ, T = θ, ? = glottal stop, sh = sʰ; the
# glides y (ျ ြ; ကျ = k + y is [tɕ]) and w (ွ). r (ɹ of loanwords) and D (ð, the voiced θ of
# compounds) are reserved: the spelling rules do not produce them (a lexicon could). Vowels: i u e o E(ɛ) O(ɔ) a @(ə, reduced, no tone)
# and I(ɪ) U(ʊ) ei ou ai au before the finals N (nasalized) and ? (glottal stop). Tones: T1 low,
# T2 high (း), T3 creaky (့), T4 checked (a syllable ending in ?).

TOKEN_SET_MYEN = "my-en"

MY_INITIALS = ("k", "kh", "g", "ng", "hng", "s", "sh", "z", "ny", "hny", "t", "th", "d", "n", "hn",
               "p", "ph", "b", "m", "hm", "y", "r", "S", "l", "hl", "w", "hw", "T", "D", "h", "?")
MY_GLIDES = ("y", "w")
MY_VOWELS = ("i", "u", "e", "o", "E", "O", "a", "@", "I", "U", "ei", "ou", "ai", "au")
MY_FINALS = ("N", "?")
MY_TONE_COUNT = 4

TOKENS_MYEN: tuple[str, ...] = (
    TOKENS_V2
    + tuple(f"MY:I:{c}" for c in MY_INITIALS)
    + tuple(f"MY:M:{g}" for g in MY_GLIDES)
    + tuple(f"MY:V:{v}" for v in MY_VOWELS)
    + tuple(f"MY:F:{f}" for f in MY_FINALS)
    + tuple(f"MY:T{i}" for i in range(1, MY_TONE_COUNT + 1))
)
VOCAB_SIZE_MYEN = len(TOKENS_MYEN)

TOKEN_SETS[TOKEN_SET_MYEN] = TOKENS_MYEN


# ---------------- text modes of the pair token sets ----------------
# text_to_ids(text, mode) with a pair mode returns ids of that mode's token set; the modes vi, en
# and auto use vi-en. A new pair adds its token set above, one entry here, its language module
# (languages.py) and its tagging rule (lang.py).

PAIR_MODES: dict[str, str] = {"zh": TOKEN_SET_ZHEN, "ko": TOKEN_SET_KOEN, "ja": TOKEN_SET_JAEN,
                              "es": TOKEN_SET_ESEN, "id": TOKEN_SET_IDEN,
                              "pt": TOKEN_SET_PTEN, "th": TOKEN_SET_THEN, "hi": TOKEN_SET_HIEN}
PAIR_MODES["nl"] = TOKEN_SET_NLEN
PAIR_MODES["sv"] = TOKEN_SET_SVEN
PAIR_MODES["no"] = TOKEN_SET_NOEN
PAIR_MODES["fr"] = TOKEN_SET_FREN
PAIR_MODES["de"] = TOKEN_SET_DEEN
PAIR_MODES["it"] = TOKEN_SET_ITEN
PAIR_MODES["tr"] = TOKEN_SET_TREN
PAIR_MODES["ru"] = TOKEN_SET_RUEN
PAIR_MODES["pl"] = TOKEN_SET_PLEN
PAIR_MODES["ar"] = TOKEN_SET_AREN
PAIR_MODES["fi"] = TOKEN_SET_FIEN
PAIR_MODES["el"] = TOKEN_SET_ELEN
PAIR_MODES["ms"] = TOKEN_SET_MSEN
PAIR_MODES["tl"] = TOKEN_SET_TLEN
PAIR_MODES["sw"] = TOKEN_SET_SWEN
PAIR_MODES["da"] = TOKEN_SET_DAEN
PAIR_MODES["lo"] = TOKEN_SET_LOEN
PAIR_MODES["km"] = TOKEN_SET_KMEN
PAIR_MODES["my"] = TOKEN_SET_MYEN

_TOKEN_INDEX: dict[str, dict[str, int]] = {}


def token_index(token_set: str) -> dict[str, int]:
    """token -> id in a token set of TOKEN_SETS."""
    if token_set not in _TOKEN_INDEX:
        _TOKEN_INDEX[token_set] = {tok: i for i, tok in enumerate(TOKEN_SETS[token_set])}
    return _TOKEN_INDEX[token_set]
