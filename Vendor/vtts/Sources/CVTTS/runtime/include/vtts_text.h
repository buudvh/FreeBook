/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text.h -- on-device text front-end: UTF-8 text -> phoneme id chunks.
 *
 * vtts_text_to_ids: Vietnamese, phoneme set v1 (the released Vietnamese models).
 * vtts_text_to_ids_ex: bilingual Vietnamese + English, phoneme set v2, like text_to_ids(text, lang)
 * in src/vtts/frontend/text.py (sentence split, language per word, Vietnamese or English
 * normalization per run, English G2P with the VLEX lexicon, chunks of <= 40 words / 318 tokens).
 *
 * Mirrors src/vtts/frontend (normalize -> split_sentences -> g2p -> encode) for the
 * device subset: Vietnamese words, letters/acronyms, loanwords, abbreviations, numbers
 * (integers, decimals, thousands separators, negatives), percent, dates (d/m, d/m/yyyy),
 * times (8:30, 8h30, 8h), punctuation. Not supported on device: e-mail, URLs, phone
 * numbers, ISO dates, currency and units (the host front-end handles them).
 *
 * VTTS_LANG_ZH: Mandarin + English, token set zh-en (ids 0..106 = v2, Mandarin from 107), like
 * text_to_ids(text, "zh"): Chinese normalization (numbers, dates, times, money, percent, product
 * codes), readings from the ZLEX blob (vtts_zlex.h), English words with the VLEX lexicon.
 *
 * VTTS_LANG_KO: Korean + English, token set ko-en (ids 0..106 = v2, Korean from 107), like
 * text_to_ids(text, "ko"): Korean normalization (Sino-Korean and native numbers with counters, dates,
 * times, money, units, phone numbers, product codes), the exception table and the standard
 * pronunciation rules (tables compiled in, no blob), English words with the VLEX lexicon.
 *
 * VTTS_LANG_HI: Hindi + English, token set hi-en (ids 0..106 = v2, Hindi from 107), like
 * text_to_ids(text, "hi"): Hindi normalization (numbers 0-99 from a table with sau, hazaar, lakh and
 * crore, decimals, dates, years, times, rupees and paise, units, percentages, phone numbers, ordinals,
 * product codes, Devanagari digits; the danda ends a sentence), the Devanagari letter, nasal and
 * schwa-deletion rules with the exception table (tables compiled in, no blob), English words with
 * the VLEX lexicon.
 * VTTS_LANG_JA: Japanese + English, token set ja-en (ids 0..106 = v2, Japanese from 107), like
 * text_to_ids(text, "ja"): Japanese normalization (NFKC, numbers with counters and their sound
 * changes, dates, times, money, units, phone numbers, product codes), readings by forward longest
 * match over the JLEX blob (vtts_jlex.h: words, context tables, kanji defaults), kana -> phonemes,
 * English words with the VLEX lexicon.
 * VTTS_LANG_ES, VTTS_LANG_ID, VTTS_LANG_PT: Spanish, Indonesian, Brazilian Portuguese + English, token
 * sets es-en, id-en, pt-en (ids 0..106 = v2, the language from 107), like text_to_ids(text, "es" |
 * "id" | "pt"): plain Latin words tagged by latin.py (own letters, word lists, CamelCase, acronyms,
 * spelling), the language's normalizer (dates, times, phone numbers, money, percent, units, ordinals,
 * ranges, product codes, numbers, acronyms), its spelling rules and stress (tables compiled in, no
 * blob), English words with the VLEX lexicon.
 * VTTS_LANG_IT, VTTS_LANG_TR: Italian, Turkish + English, token sets it-en, tr-en, like
 * text_to_ids(text, "it" | "tr"): the Latin-script rules of latin.py with elision (sull'iPhone) and
 * suffixes after an apostrophe (iPhone'da), the language's normalizer and spelling rules (tables
 * compiled in, no blob). Each is compiled only with VTTS_ENABLE_IT / VTTS_ENABLE_TR (1 by default;
 * the firmware enables the languages of its models).
 * VTTS_LANG_FI: Finnish + English, token set fi-en (ids 0..106 = v2, Finnish from 107), like
 * text_to_ids(text, "fi"): Finnish normalization (numbers written as one word, ordinals with a dot,
 * dates, times, euros, units with the partitive, ranges, abbreviations), spelling rules with
 * length and stress, Latin words tagged by the Latin-script rules; a dot before a lower-case
 * letter or a digit does not end a sentence. Compiled when VTTS_ENABLE_FI is not 0 (default 1).
 * VTTS_LANG_EL: Greek + English, token set el-en (ids 0..106 = v2, Greek from 107), like
 * text_to_ids(text, "el"): Greek normalization (numbers with gender, ordinals, dates with month
 * genitives, times, euros, units, abbreviations, Greek acronyms), the Greek letter, digraph,
 * synizesis and stress rules, Latin words in English; ";" is the question mark. Compiled when
 * VTTS_ENABLE_EL is not 0 (default 1).
 * VTTS_LANG_KM: Khmer + English, token set km-en (ids 0..106 = v2, Khmer from 107), like
 * text_to_ids(text, "km"): Khmer normalization (Khmer digits, numbers, dates, times, riel, percent, units,
 * phone numbers, abbreviations, ៗ; spaces between Khmer runs are pauses), word segmentation over the word
 * list, cluster and syllable rules, onset, rhyme and override tables (compiled in when VTTS_ENABLE_KM,
 * no blob), English words with the VLEX lexicon.
 * VTTS_LANG_MY: Burmese + English, token set my-en (ids 0..106 = v2, Burmese from 107), like
 * text_to_ids(text, "my"): Zawgyi detection and conversion, canonical mark order, Burmese normalization
 * (Burmese digits, numbers, dates, times, kyat, percent, units, phone numbers; ။ ends a sentence),
 * syllables, onsets, rhymes and tones (compiled in when VTTS_ENABLE_MY, no blob), English words with the
 * VLEX lexicon.
 * VTTS_LANG_TH: Thai + English, token set th-en (ids 0..106 = v2, Thai from 107), like
 * text_to_ids(text, "th"): Thai normalization (numbers, dates, times, money, percent, units, phone
 * numbers, abbreviations), word segmentation over the word list, the spelling rules and tones
 * (tables compiled in, about 80 KB of flash, no blob), English words with the VLEX lexicon.
 * VTTS_LANG_FR: French + English, token set fr-en (ids 0..106 = v2, French from 107), like
 * text_to_ids(text, "fr"): plain Latin words tagged by latin.py rules (an elided clitic follows its
 * word), French normalization (numbers, ordinals, dates, times, money, percent, units, phone numbers
 * in pairs, Roman numerals, abbreviations, inverted verbs) and liaison, the spelling rules, e muet and
 * mid vowels (tables compiled in, no blob; only when built with VTTS_ENABLE_FR, the default),
 * English words with the VLEX lexicon.
 * VTTS_LANG_DE: German + English, token set de-en (ids 0..106 = v2, German from 107), like
 * text_to_ids(text, "de"): German sentence split (ordinals and abbreviations keep their dot),
 * Latin words tagged by latin.py rules, German normalization (numbers, ordinals, dates, times, money,
 * percent, units, phone numbers, abbreviations, product codes, acronyms), the morph split over the
 * stem list, spelling rules and stress (tables compiled in, no blob; only when VTTS_ENABLE_DE),
 * English words with the VLEX lexicon.
 * VTTS_LANG_RU: Russian + English, token set ru-en (ids 0..106 = v2, Russian from 107), like
 * text_to_ids(text, "ru"): Russian normalization (numbers with cheap agreement, decimals, dates and
 * years as ordinals, centuries, times, money, units, ordinals, phone numbers, abbreviations,
 * acronyms), stress from the RLEX blob (vtts_rlex.h), the spelling, reduction and voicing rules,
 * English words with the VLEX lexicon. Compiled when VTTS_ENABLE_RU is non-zero (default 1).
 * VTTS_LANG_PL: Polish + English, token set pl-en (ids 0..106 = v2, Polish from 107), like
 * text_to_ids(text, "pl"): plain Latin words tagged by latin.py's rules for Polish, Polish
 * normalization (numbers, decimals, dates and years as ordinals, centuries, times, złoty, units, phone
 * numbers, abbreviations, acronyms), the spelling, nasal, voicing and stress rules (tables and the
 * normalizer's patterns compiled in, no blob), English words with the VLEX lexicon. Compiled when
 * VTTS_ENABLE_PL is non-zero (default 1).
 *
 * Every language other than Vietnamese and English is compiled only when its VTTS_ENABLE_<L> is 1
 * (vtts_langs.h; all 1 by default, the firmware enables those of its models): otherwise its mode is
 * not offered (vtts_text_lang_for, vtts_text_default_lang) and vtts_text_to_ids_ex returns -1 for it.
 *
 * VTTS_LANG_AR: Arabic (Modern Standard Arabic) + English, token set ar-en (ids 0..106 = v2, Arabic
 * from 107), like text_to_ids(text, "ar"): Arabic normalization (Arabic-Indic and Eastern digits,
 * numbers, dates, times, years with h/m, money, percent, units, phone numbers, ranges, product codes,
 * abbreviations; Arabic ? ; and full stop end a sentence), vowel restoration (spelling table, the
 * word's own marks, the word table with clitics and endings, word patterns), pausal reading and
 * stress (tables compiled in, no blob), English words with the VLEX lexicon. Only compiled with
 * VTTS_ENABLE_AR (default 1; the firmware enables it only for ar-en models).
 * VTTS_LANG_TL: Tagalog (Filipino) + English, token set tl-en (ids 0..106 = v2, Tagalog from 107), like
 * text_to_ids(text, "tl"): plain Latin words tagged by latin.py (ñ and accent marks, word lists,
 * hyphenated English, CamelCase, acronyms, spelling), normalize_tl (native numbers with the linker,
 * Spanish-derived clock times and peso prices, dates, phone numbers, units, ordinals, reduplication),
 * the spelling rules, glottal stops and the stress table (tables compiled in, no blob), English
 * words with the VLEX lexicon. Compiled only with VTTS_ENABLE_TL (default 1); without it the mode
 * is unknown (vtts_text_lang_for fails, vtts_text_to_ids_ex returns -1).
 * VTTS_LANG_SW: Swahili + English, token set sw-en (ids 0..106 = v2, Swahili from 107), like
 * text_to_ids(text, "sw"): plain Latin words tagged by latin.py (word lists, CamelCase, acronyms,
 * Swahili spelling; ng' is one word), normalize_sw (counting-form numbers, dates with tarehe, times
 * with saa, phone numbers, shilingi/dola before the amount, asilimia, units, wa kwanza / ya pili,
 * ranges, product codes, acronyms), the spelling rules and penultimate stress (tables compiled in, no
 * blob), English words with the VLEX lexicon. Compiled only with VTTS_ENABLE_SW (default 1); without
 * it the mode is unknown (vtts_text_lang_for fails, vtts_text_to_ids_ex returns -1).
 *
 * VTTS_LANG_NL, VTTS_LANG_SV, VTTS_LANG_NO: Dutch, Swedish, Norwegian (Bokmål) + English, token sets
 * nl-en, sv-en, no-en (ids 0..106 = v2, the language from 107), like text_to_ids(text, "nl" | "sv" |
 * "no"): the sentence split of scan_norm.py (abbreviations, initials and Norwegian ordinal dots keep
 * their dot), Latin words tagged by latin.py rules, the shared scanner normalizer with the language's
 * tables (numbers, ordinals, dates, times, money, percent, units, phone numbers, abbreviations, codes,
 * acronyms), the Dutch rules of g2p_nl.py or the Swedish / Norwegian rules of scand_g2p.py with word
 * tones (tables compiled in, no blob; each only when VTTS_ENABLE_NL / _SV / _NO), English words with the
 * VLEX lexicon.
 * VTTS_LANG_LO: Lao + English, token set lo-en (ids 0..106 = v2, Lao from 107), like text_to_ids(text,
 * "lo"): Lao normalization (the Thai passes with Lao tables: numbers, dates, times, kip and other money,
 * percent, units, phone numbers, abbreviations), word segmentation over the word list, the spelling
 * patterns and the six Vientiane tones (tables compiled in, no blob), English words with the VLEX
 * lexicon. Compiled only with VTTS_ENABLE_LO (default 1); without it the mode is unknown
 * (vtts_text_lang_for fails, vtts_text_to_ids_ex returns -1).
 * VTTS_LANG_DA: Danish + English, token set da-en (ids 0..106 = v2, Danish from 107), like
 * text_to_ids(text, "da"): plain Latin words tagged by latin.py (æ ø å é, word lists, CamelCase,
 * acronyms, known words and compounds, spelling), normalize_da (Danish numbers, ordinals, dates, times,
 * kroner and øre, units, phone numbers, abbreviations; a dot before a lower-case word or a digit does
 * not end a sentence), the NST readings of the frequent words, compounds and the spelling rules with
 * stress and stød (tables compiled in, no blob), English words with the VLEX lexicon. Compiled only
 * with VTTS_ENABLE_DA (default 1); without it the mode is unknown.
 *
 * No malloc: the caller provides a workspace (about 145 KB with the v2, zh and ko scratch; PSRAM is fine).
 * Not re-entrant per workspace.
 */
#ifndef VTTS_TEXT_H
#define VTTS_TEXT_H

#include <stdint.h>

#include "vtts_langs.h" /* VTTS_ENABLE_<L>: the optional languages compiled in */
#include "vtts_lex.h"
#include "vtts_zlex.h"
#include "vtts_jlex.h"
#include "vtts_rlex.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VTTS_TEXT_MAX_CP 4096     /* code points per call */
#define VTTS_TEXT_MAX_WORDS 1536  /* normalized words per sentence */
#define VTTS_TEXT_WORD_BYTES 16384
#define VTTS_TEXT_MAX_IDS 320     /* ids per chunk: 40 syllables x <= 7 tokens + BOS/EOS */
#define VTTS_TEXT_EN_CAP 6144     /* code points of an English run after expansion (v2) */
#define VTTS_TEXT_MAX_ITEMS 2048  /* words and marks per sentence (v2) */
#define VTTS_TEXT_POOL 16384      /* token ids of one sentence (v2) */

typedef struct {
    uint32_t cp[VTTS_TEXT_MAX_CP];
    uint8_t date_start[VTTS_TEXT_MAX_CP]; /* bit 0: a date starts here; bit 1: digit of a product code */
    int n_cp;
    char words[VTTS_TEXT_WORD_BYTES]; /* normalized words of the current sentence, NUL separated */
    int word_off[VTTS_TEXT_MAX_WORDS];
    int n_words, words_used;
    int32_t ids[VTTS_TEXT_MAX_IDS];
    /* v2 (bilingual) scratch; the whole workspace is about 145 KB, so place it in PSRAM */
    uint32_t run[VTTS_TEXT_MAX_CP];                     /* one language run, words joined by spaces */
    uint32_t en_a[VTTS_TEXT_EN_CAP], en_b[VTTS_TEXT_EN_CAP];
    char en_out[VTTS_TEXT_EN_CAP];
    uint16_t item_off[VTTS_TEXT_MAX_ITEMS];
    uint16_t item_len[VTTS_TEXT_MAX_ITEMS]; /* a Korean word may be one item of up to 318 tokens */
    uint8_t item_punct[VTTS_TEXT_MAX_ITEMS];
    uint8_t item_join[VTTS_TEXT_MAX_ITEMS]; /* 1: a syllable joined to the previous one without SPACE (zh) */
    uint8_t pool[VTTS_TEXT_POOL];
    int n_items, pool_used;
} vtts_text_ws;

typedef enum {
    VTTS_LANG_V1 = 0, VTTS_LANG_VI, VTTS_LANG_EN, VTTS_LANG_AUTO, VTTS_LANG_ZH, VTTS_LANG_KO,
    VTTS_LANG_HI, VTTS_LANG_JA, VTTS_LANG_ES, VTTS_LANG_ID, VTTS_LANG_PT, VTTS_LANG_TH,
    VTTS_LANG_FR, VTTS_LANG_DE, VTTS_LANG_IT, VTTS_LANG_TR, VTTS_LANG_RU, VTTS_LANG_PL,
    VTTS_LANG_AR, VTTS_LANG_FI, VTTS_LANG_EL, VTTS_LANG_MS, VTTS_LANG_TL, VTTS_LANG_SW,
    VTTS_LANG_NL, VTTS_LANG_SV, VTTS_LANG_NO, VTTS_LANG_DA, VTTS_LANG_LO,
    VTTS_LANG_KM, VTTS_LANG_MY
} vtts_lang;

/* lang: VTTS_LANG_V1 is vtts_text_to_ids; VI, EN and AUTO select the mode of text_to_ids(text,
 * "vi" | "en" | "auto") with phoneme set v2; ZH selects text_to_ids(text, "zh") with token set
 * zh-en; KO selects text_to_ids(text, "ko") with token set ko-en; HI selects text_to_ids(text, "hi") with
 * token set hi-en; JA selects text_to_ids(text, "ja") with token set ja-en; ES, ID and PT select
 * text_to_ids(text, "es" | "id" | "pt") with token set es-en, id-en, pt-en (ES..PT are consecutive); TH
 * selects text_to_ids(text, "th") with token set th-en; FR, DE, IT, TR, RU, PL, AR, FI, EL, MS, TL,
 * SW, NL, SV and NO select text_to_ids(text, mode) with mode "fr" | "de" | "it" | "tr" | "ru" | "pl" | "ar" | "fi" |
 * "el" | "ms" | "tl" | "sw" | "nl" | "sv" | "no" and token set fr-en ... no-en (each when compiled in, vtts_langs.h).
 * lex: the English lexicon (NULL: English words are not pronounced, only acronyms are spelled). zh: the
 * Mandarin reading tables (NULL: Han characters are not pronounced; only used by VTTS_LANG_ZH). ja: the
 * Japanese reading tables (NULL: Japanese characters are not pronounced and NFKC is skipped; only used
 * by VTTS_LANG_JA). ru: the Russian stress tables (NULL: words are stressed by the default rule only;
 * only used by VTTS_LANG_RU). */
typedef struct {
    vtts_lang lang;
    const vtts_lex *lex;
    const vtts_zlex *zh;
    const vtts_jlex *ja;
    const vtts_rlex *ru;
} vtts_text_opts;

/* Called once per chunk (<= 40 syllables) with ids including BOS ... EOS.
 * Return non-zero to stop. */
typedef int (*vtts_ids_cb)(const int32_t *ids, int n, void *user);

/* Returns the number of chunks emitted (0 for empty/punctuation-only text) or < 0 on error. */
int vtts_text_to_ids(const char *utf8, vtts_text_ws *ws, vtts_ids_cb cb, void *user);

/* Same, with options (NULL or VTTS_LANG_V1: vtts_text_to_ids). v2 chunks hold <= 40 words and
 * <= 318 tokens plus BOS/EOS. */
int vtts_text_to_ids_ex(const char *utf8, vtts_text_ws *ws, const vtts_text_opts *o, vtts_ids_cb cb,
                        void *user);

/* Text modes per model token set (token_set: vtts_token_set_t from vtts.h), the modes of
 * MODE_LANGS in src/vtts/frontend/lang.py that the device front-end implements:
 *   v1    "vi" (VTTS_LANG_V1)                  default vi
 *   vi-en "vi" | "en" | "auto"                 default vi
 *   zh-en "zh" (Han -> Mandarin, Latin -> English, numbers in Mandarin)   default zh
 *   ko-en "ko" (Hangul -> Korean, Latin -> English, numbers in Korean)    default ko
 *   hi-en "hi" (Devanagari -> Hindi, Latin -> English, numbers in Hindi)  default hi
 *   ja-en "ja" (kana/kanji -> Japanese, Latin -> English, numbers in Japanese) default ja
 *   es-en "es", id-en "id", pt-en "pt" (Latin words by latin.py rules -> the language or English)
 *   th-en "th" (Thai -> Thai, Latin -> English, numbers in Thai)          default th
 *   fr-en "fr" (Latin words by the fr rules -> French or English)        default fr (VTTS_ENABLE_FR)
 *   de-en "de" (Latin words by latin.py rules -> German or English; needs VTTS_ENABLE_DE)
 *   it-en "it", tr-en "tr" (Latin words by latin.py rules; only when compiled in)
 *   ru-en "ru" (Cyrillic -> Russian, Latin -> English, numbers in Russian) default ru (VTTS_ENABLE_RU)
 *   pl-en "pl" (Latin words by latin.py rules -> Polish or English)        default pl (VTTS_ENABLE_PL)
 *   ar-en "ar" (Arabic -> Arabic, Latin -> English, numbers in Arabic)    default ar (VTTS_ENABLE_AR)
 *   fi-en "fi" (Finnish, Latin words by the Latin-script rules)           default fi (VTTS_ENABLE_FI)
 *   el-en "el" (Greek -> Greek, Latin -> English, numbers in Greek)       default el (VTTS_ENABLE_EL)
 *   ms-en "ms", tl-en "tl", sw-en "sw" (Latin words by latin.py rules -> the language or English)
 *   nl-en "nl", sv-en "sv", no-en "no" (Latin words by latin.py rules; their own sentence split)
 *   lo-en "lo" (Lao -> Lao, Latin -> English, numbers in Lao; VTTS_ENABLE_LO) default lo
 *   da-en "da" (Latin words by latin.py rules -> Danish or English; VTTS_ENABLE_DA) default da
 *   unknown: no device front-end (token ids from a host front-end only).
 * vtts_text_lang_for: 0 and *out set when `mode` is valid for the set, else < 0.
 * vtts_text_default_lang: 0 and *out set, or < 0 when the set has no device front-end. */
int vtts_text_lang_for(int token_set, const char *mode, vtts_lang *out);
int vtts_text_default_lang(int token_set, vtts_lang *out);
/* The text mode a model starts in: the mode named by its text_mode dim (vtts_model.text_mode, e.g.
 * "en" for the English-only voice nu-en, which uses the vi-en token set) when the set offers it, else
 * vtts_text_default_lang. Returns 0 and *out set, or < 0 when the set has no device front-end. */
int vtts_text_model_lang(int token_set, int text_mode, vtts_lang *out);
const char *vtts_text_modes(int token_set); /* "vi", "vi|en|auto", "zh", "ko", "hi", "ja", "es", "id", "pt", "th",
                                               "fr", "de", "it", "tr", "ru", "pl", "ar", "fi", "el", "ms", "tl", "sw", "nl", "sv", "no" or "" */
const char *vtts_text_lang_name(vtts_lang lang); /* "vi" (V1 and VI), "en", "auto", "zh", "ko", "hi", "ja", "es",
                                                    "id", "pt", "th", "fr", "de", "it", "tr", "ru", "pl",
                                                    "ar", "fi", "el", "ms", "tl", "sw", "nl", "sv", "no" */

#ifdef __cplusplus
}
#endif
#endif
