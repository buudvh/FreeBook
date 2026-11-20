/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_langs.h -- which optional languages of the device front-end are compiled in.
 *
 * Vietnamese and English (phoneme sets v1 and v2: token sets v1, vi-en) are always built. Every
 * other language is compiled only when its VTTS_ENABLE_<L> is 1: its module (vtts_text_<l>.c) is
 * then an empty translation unit when 0, its mode is not offered by vtts_text_lang_for and
 * vtts_text_to_ids_ex returns -1 for it. Host builds and `make test` default every language to 1;
 * the firmware sets each switch from the token sets of the models it embeds (main/CMakeLists.txt,
 * VTTS_LANGS=all for everything).
 *
 * The blob-backed languages need their blob only when enabled: zh (lex_zh.bin, vtts_zlex.h), ja
 * (lex_ja.bin, vtts_jlex.h) and ru (lex_ru.bin, vtts_rlex.h). */
#ifndef VTTS_LANGS_H
#define VTTS_LANGS_H

#ifndef VTTS_ENABLE_ZH
#define VTTS_ENABLE_ZH 1 /* Mandarin, zh-en (vtts_text_zh.c, ZLEX blob) */
#endif
#ifndef VTTS_ENABLE_KO
#define VTTS_ENABLE_KO 1 /* Korean, ko-en (vtts_text_ko.c) */
#endif
#ifndef VTTS_ENABLE_JA
#define VTTS_ENABLE_JA 1 /* Japanese, ja-en (vtts_text_ja.c, JLEX blob) */
#endif
#ifndef VTTS_ENABLE_HI
#define VTTS_ENABLE_HI 1 /* Hindi, hi-en (vtts_text_hi.c) */
#endif
#ifndef VTTS_ENABLE_TH
#define VTTS_ENABLE_TH 1 /* Thai, th-en (vtts_text_th.c) */
#endif
#ifndef VTTS_ENABLE_ES
#define VTTS_ENABLE_ES 1 /* Spanish, es-en (vtts_text_lt.c) */
#endif
#ifndef VTTS_ENABLE_ID
#define VTTS_ENABLE_ID 1 /* Indonesian, id-en (vtts_text_lt.c) */
#endif
#ifndef VTTS_ENABLE_PT
#define VTTS_ENABLE_PT 1 /* Brazilian Portuguese, pt-en (vtts_text_lt.c) */
#endif
#ifndef VTTS_ENABLE_FR
#define VTTS_ENABLE_FR 1 /* French, fr-en (vtts_text_fr.c) */
#endif
#ifndef VTTS_ENABLE_DE
#define VTTS_ENABLE_DE 1 /* German, de-en (vtts_text_de.c) */
#endif
#ifndef VTTS_ENABLE_IT
#define VTTS_ENABLE_IT 1 /* Italian, it-en (vtts_text_it.c) */
#endif
#ifndef VTTS_ENABLE_TR
#define VTTS_ENABLE_TR 1 /* Turkish, tr-en (vtts_text_tr.c) */
#endif
#ifndef VTTS_ENABLE_RU
#define VTTS_ENABLE_RU 1 /* Russian, ru-en (vtts_text_ru.c, vtts_re.c, RLEX blob) */
#endif
#ifndef VTTS_ENABLE_PL
#define VTTS_ENABLE_PL 1 /* Polish, pl-en (vtts_text_pl.c, vtts_re.c) */
#endif
#ifndef VTTS_ENABLE_AR
#define VTTS_ENABLE_AR 1 /* Arabic, ar-en (vtts_text_ar.c) */
#endif
#ifndef VTTS_ENABLE_FI
#define VTTS_ENABLE_FI 1 /* Finnish, fi-en (vtts_text_fi.c) */
#endif
#ifndef VTTS_ENABLE_EL
#define VTTS_ENABLE_EL 1 /* Greek, el-en (vtts_text_el.c) */
#endif
#ifndef VTTS_ENABLE_MS
#define VTTS_ENABLE_MS 1 /* Malay, ms-en (vtts_text_lt.c: the Indonesian code with Malay tables) */
#endif
#ifndef VTTS_ENABLE_TL
#define VTTS_ENABLE_TL 1 /* Tagalog, tl-en (vtts_text_tl.c) */
#endif
#ifndef VTTS_ENABLE_SW
#define VTTS_ENABLE_SW 1 /* Swahili, sw-en (vtts_text_sw.c) */
#endif
#ifndef VTTS_ENABLE_NL
#define VTTS_ENABLE_NL 1 /* Dutch, nl-en (vtts_text_nx.c, vtts_text_nx_nl.c) */
#endif
#ifndef VTTS_ENABLE_SV
#define VTTS_ENABLE_SV 1 /* Swedish, sv-en (vtts_text_nx.c, vtts_text_nx_sc.c) */
#endif
#ifndef VTTS_ENABLE_NO
#define VTTS_ENABLE_NO 1 /* Norwegian Bokmål, no-en (vtts_text_nx.c, vtts_text_nx_sc.c) */
#endif
#ifndef VTTS_ENABLE_DA
#define VTTS_ENABLE_DA 1 /* Danish, da-en (vtts_text_da.c) */
#endif
#ifndef VTTS_ENABLE_LO
#define VTTS_ENABLE_LO 1 /* Lao, lo-en (vtts_text_lo.c) */
#endif
#ifndef VTTS_ENABLE_KM
#define VTTS_ENABLE_KM 1 /* Khmer, km-en (vtts_text_km.c, vtts_text_nsp.c) */
#endif
#ifndef VTTS_ENABLE_MY
#define VTTS_ENABLE_MY 1 /* Burmese, my-en (vtts_text_my.c, vtts_text_nsp.c) */
#endif

/* es, id, pt and ms share one module (vtts_text_lt.c) */
#define VTTS_ENABLE_LT (VTTS_ENABLE_ES || VTTS_ENABLE_ID || VTTS_ENABLE_PT || VTTS_ENABLE_MS)
/* nl, sv and no share the scanner normalizer (vtts_text_nx.c) */
#define VTTS_ENABLE_NX (VTTS_ENABLE_NL || VTTS_ENABLE_SV || VTTS_ENABLE_NO)
/* km and my share the no-space normalizer engine (vtts_text_nsp.c) */
#define VTTS_ENABLE_NSP (VTTS_ENABLE_KM || VTTS_ENABLE_MY)

#endif
