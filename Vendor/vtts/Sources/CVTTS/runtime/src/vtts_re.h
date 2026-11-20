/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_re.h -- a small backtracking matcher for Python `re` patterns of the text front-ends
 * (internal).
 *
 * The patterns are not parsed on the device: runtime/tools/gen_text_tables.py parses each Python
 * pattern with Python's own parser (re._parser) and writes the parse tree as node tables, so the
 * device matches what Python matches: the same alternation order, greedy repeats that give back one
 * step at a time, lookarounds (lookbehinds of a fixed width), back references, and Python's Unicode
 * classes for str patterns (\d \w \s via vtts_u_digit / vtts_u_word / vtts_u_space). Only what the
 * generated patterns use is supported (no flags, no lazy repeats). No malloc; the recursion depth
 * grows with the repeats of groups (a repeat of a single character or class is iterative). */
#ifndef VTTS_RE_H
#define VTTS_RE_H

#include <stdint.h>

enum {
    VTTS_RE_LIT = 1,  /* a: code point */
    VTTS_RE_NLIT,     /* a: code point (any other) */
    VTTS_RE_ANY,      /* any code point except \n */
    VTTS_RE_IN,       /* class: items [a, a + len), flag 1: negated */
    VTTS_RE_REPEAT,   /* body [body, body + len) repeated a..b times (b = VTTS_RE_INF), greedy */
    VTTS_RE_GROUP,    /* capturing group a (1-based) around [body, body + len) */
    VTTS_RE_BRANCH,   /* alternatives [a, a + len) of the alternatives table, tried in order */
    VTTS_RE_ASSERT,   /* lookaround of [body, body + len); flag bit 0: negative, bit 1: behind (width a) */
    VTTS_RE_AT,       /* a: 1 beginning, 2 end (or before a final \n), 3 \b, 4 \B, 5 \Z */
    VTTS_RE_GROUPREF  /* a: group (1-based) */
};
enum { VTTS_RE_I_LIT = 1, VTTS_RE_I_RANGE, VTTS_RE_I_DIGIT, VTTS_RE_I_NDIGIT, VTTS_RE_I_WORD, VTTS_RE_I_NWORD,
       VTTS_RE_I_SPACE, VTTS_RE_I_NSPACE };
#define VTTS_RE_INF 0xFFFFFFFFu
#define VTTS_RE_MAX_GROUPS 10

typedef struct { uint8_t op, flag; uint16_t len; uint32_t body, a, b; } vtts_re_node;
typedef struct { uint8_t kind; uint32_t lo, hi; } vtts_re_item;
typedef struct { uint32_t start; uint16_t len; } vtts_re_alt;

typedef struct {
    const vtts_re_node *nodes;
    const vtts_re_item *items;
    const vtts_re_alt *alts;
    uint32_t start;
    uint16_t len;
    uint8_t groups; /* number of capturing groups */
} vtts_re;

/* One match: the overall span and the groups (-1 when a group did not take part). */
typedef struct { int start, end, gs[VTTS_RE_MAX_GROUPS + 1], ge[VTTS_RE_MAX_GROUPS + 1]; } vtts_re_match;

/* Match at exactly position pos of s (n code points): 1 and *m filled, or 0. */
int vtts_re_match_at(const vtts_re *re, const uint32_t *s, int n, int pos, vtts_re_match *m);

/* re.search from position pos: 1 and *m filled for the leftmost match, or 0. */
int vtts_re_search(const vtts_re *re, const uint32_t *s, int n, int pos, vtts_re_match *m);

/* An output buffer of code points (err set when it is full). */
typedef struct { uint32_t *p; int n, cap, err; } vtts_re_buf;

/* re.sub(re, fn, s) into out: the text between the matches is copied, fn writes each replacement. */
typedef void (*vtts_re_fn)(const uint32_t *s, int n, const vtts_re_match *m, vtts_re_buf *out, void *user);
void vtts_re_sub(const vtts_re *re, const uint32_t *s, int n, vtts_re_buf *out, vtts_re_fn fn, void *user);

#endif
