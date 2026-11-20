/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_text_nx_int.h -- internals shared by vtts_text_nx.c (scanner normalizer, sentence split,
 * tagging) and the language files vtts_text_nx_nl.c (Dutch) and vtts_text_nx_sc.c (Swedish and
 * Norwegian). */
#ifndef VTTS_TEXT_NX_INT_H
#define VTTS_TEXT_NX_INT_H

#include <stdint.h>

#include "vtts_text_nx.h"

/* a UTF-8 byte buffer for number words (words separated by single spaces) */
typedef struct { char *p; int n, cap, err; } nx_buf;

void nx_cat(nx_buf *b, const char *s);   /* append a UTF-8 string */
void nx_word(nx_buf *b, const char *s);  /* a space (unless empty) and the string */

struct vtts_nx_spec_s;

/* one language: its normalizer Spec, number readers and word -> ids */
typedef struct {
    const void *spec;                                       /* const vtts_nx_spec * */
    void (*cardinal)(nx_buf *b, uint64_t n);                /* Spec.cardinal (n < 10**15) */
    void (*ordinal)(nx_buf *b, uint64_t n);                 /* Spec.ordinal (n >= 1) */
    void (*year)(nx_buf *b, int n);                         /* Spec.year (1100-1999) */
    void (*date)(nx_buf *b, int d, int m, int64_t y);       /* y < 0: no year */
    void (*time)(nx_buf *b, int h, int mi, int sec);        /* sec < 0: none */
    int (*word_ids)(const uint32_t *w, int n, void *scratch, uint8_t *out, int cap);
    int (*valid_spelling)(const char *w, int n);            /* lower-case ASCII letters */
} nx_lang_t;

#if VTTS_ENABLE_NL
extern const nx_lang_t vtts_nx_nl;
#endif
#if VTTS_ENABLE_SV
extern const nx_lang_t vtts_nx_sv;
#endif
#if VTTS_ENABLE_NO
extern const nx_lang_t vtts_nx_no;
#endif

/* Python re classes (vtts_text_lt.c) */
int vtts_u_word(uint32_t c);
int vtts_u_digit(uint32_t c);
int vtts_u_space(uint32_t c);
uint32_t vtts_u_lower(uint32_t c);
int vtts_lt_english_word(const char *low); /* lexicons/latin/english.txt */

/* helpers */
int nx_dec1(const char *s, uint32_t *c);                                /* one UTF-8 sequence */
int nx_u8_len(const char *s);                                           /* code points */
int nx_eq_u8(const uint32_t *w, int n, const char *k);                  /* w == k */
int nx_at_u8(const uint32_t *w, int n, int i, const char *k);           /* k at w[i]: its length or 0 */
int nx_ends_u8(const uint32_t *w, int n, const char *k);                /* w ends with k (and is longer) */
int nx_in_u8(uint32_t c, const char *set);                              /* c is one of set */
int nx_index_u8(uint32_t c, const char *set);                           /* its position or -1 */
int nx_in_sorted(const char *const *list, int n, const char *w);        /* binary search */
int nx_in_sorted_cp(const char *const *list, int n, const uint32_t *w, int len);
int nx_encode(uint32_t c, char *o);                                     /* UTF-8, returns bytes */

#endif
