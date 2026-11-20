/* SPDX-License-Identifier: Apache-2.0 */
/* vtts_re.c -- backtracking matcher over the parse trees of Python `re` patterns (see vtts_re.h). */
#include "vtts_langs.h"
#if VTTS_ENABLE_RU || VTTS_ENABLE_PL /* its only users; else an empty unit */

#include "vtts_re.h"

#include <stddef.h>

#include "vtts_text_lt.h" /* vtts_u_word, vtts_u_digit, vtts_u_space */

#define MAX_DEPTH 4000 /* nested continuations; a deeper match fails */

enum { K_SEQ = 1, K_GROUP_END, K_REPEAT, K_END_AT };

typedef struct cont {
    int kind;
    uint32_t start; /* K_SEQ: the sequence and the node to continue at */
    int len, idx;
    int group, gstart;          /* K_GROUP_END */
    const vtts_re_node *rep;    /* K_REPEAT: the repeat, the count reached, where this pass began */
    int count, last;
    int target;                 /* K_END_AT: a lookbehind must end here */
    const struct cont *up;
} cont_t;

typedef struct {
    const vtts_re *re;
    const uint32_t *s;
    int n, depth;
    int gs[VTTS_RE_MAX_GROUPS + 1], ge[VTTS_RE_MAX_GROUPS + 1];
} ctx_t;

static int run_seq(ctx_t *c, uint32_t start, int len, int idx, int pos, const cont_t *k);

static int is_word(uint32_t ch) { return vtts_u_word(ch); }

static int in_class(const ctx_t *c, const vtts_re_node *nd, uint32_t ch) {
    int hit = 0;
    for (int i = 0; i < nd->len && !hit; i++) {
        const vtts_re_item *it = &c->re->items[nd->a + i];
        switch (it->kind) {
        case VTTS_RE_I_LIT: hit = ch == it->lo; break;
        case VTTS_RE_I_RANGE: hit = ch >= it->lo && ch <= it->hi; break;
        case VTTS_RE_I_DIGIT: hit = vtts_u_digit(ch) >= 0; break;
        case VTTS_RE_I_NDIGIT: hit = vtts_u_digit(ch) < 0; break;
        case VTTS_RE_I_WORD: hit = is_word(ch); break;
        case VTTS_RE_I_NWORD: hit = !is_word(ch); break;
        case VTTS_RE_I_SPACE: hit = vtts_u_space(ch); break;
        case VTTS_RE_I_NSPACE: hit = !vtts_u_space(ch); break;
        default: break;
        }
    }
    return nd->flag & 1 ? !hit : hit;
}

/* a single-character node matches s[pos] */
static int one(const ctx_t *c, const vtts_re_node *nd, int pos) {
    if (pos >= c->n) return 0;
    uint32_t ch = c->s[pos];
    switch (nd->op) {
    case VTTS_RE_LIT: return ch == nd->a;
    case VTTS_RE_NLIT: return ch != nd->a;
    case VTTS_RE_ANY: return ch != '\n';
    case VTTS_RE_IN: return in_class(c, nd, ch);
    default: return 0;
    }
}

static int single(const vtts_re_node *nd) {
    return nd->op == VTTS_RE_LIT || nd->op == VTTS_RE_NLIT || nd->op == VTTS_RE_ANY || nd->op == VTTS_RE_IN;
}

static int resume(ctx_t *c, const cont_t *k, int pos);

/* greedy repeat of a body that is not a single character: one more pass first, then the rest */
static int rep_try(ctx_t *c, const vtts_re_node *nd, int count, int pos, const cont_t *after) {
    if ((uint32_t)count < nd->b) {
        cont_t f = {0};
        f.kind = K_REPEAT;
        f.rep = nd;
        f.count = count + 1;
        f.last = pos;
        f.up = after;
        int r = run_seq(c, nd->body, nd->len, 0, pos, &f);
        if (r >= 0) return r;
    }
    if ((uint32_t)count >= nd->a) return resume(c, after, pos);
    return -1;
}

static int resume(ctx_t *c, const cont_t *k, int pos) {
    if (!k) return pos;
    switch (k->kind) {
    case K_SEQ: return run_seq(c, k->start, k->len, k->idx, pos, k->up);
    case K_GROUP_END: {
        int os = c->gs[k->group], oe = c->ge[k->group];
        c->gs[k->group] = k->gstart;
        c->ge[k->group] = pos;
        int r = resume(c, k->up, pos);
        if (r < 0) { c->gs[k->group] = os; c->ge[k->group] = oe; }
        return r;
    }
    case K_REPEAT:
        if (pos == k->last) /* an empty pass ends the repeat (like sre) */
            return (uint32_t)k->count >= k->rep->a ? resume(c, k->up, pos) : -1;
        return rep_try(c, k->rep, k->count, pos, k->up);
    case K_END_AT: return pos == k->target ? pos : -1;
    default: return -1;
    }
}

static int at(const ctx_t *c, uint32_t kind, int pos) {
    switch (kind) {
    case 1: return pos == 0;
    case 5: return pos == c->n;
    case 2: return pos == c->n || (pos == c->n - 1 && c->s[pos] == '\n');
    case 3:
    case 4: {
        int a = pos > 0 && is_word(c->s[pos - 1]), b = pos < c->n && is_word(c->s[pos]);
        return kind == 3 ? a != b : a == b;
    }
    default: return 0;
    }
}

static int run_seq(ctx_t *c, uint32_t start, int len, int idx, int pos, const cont_t *k) {
    if (++c->depth > MAX_DEPTH) { c->depth--; return -1; }
    int r = -1;
    while (idx < len) {
        const vtts_re_node *nd = &c->re->nodes[start + idx];
        if (single(nd)) {
            if (!one(c, nd, pos)) goto done;
            pos++;
            idx++;
            continue;
        }
        if (nd->op == VTTS_RE_AT) {
            if (!at(c, nd->a, pos)) goto done;
            idx++;
            continue;
        }
        cont_t rest = {0}; /* the nodes after this one */
        rest.kind = K_SEQ;
        rest.start = start;
        rest.len = len;
        rest.idx = idx + 1;
        rest.up = k;
        switch (nd->op) {
        case VTTS_RE_REPEAT:
            if (nd->len == 1 && single(&c->re->nodes[nd->body])) {
                const vtts_re_node *b = &c->re->nodes[nd->body];
                uint32_t m = 0;
                while (m < nd->b && one(c, b, pos + (int)m)) m++;
                for (;; m--) {
                    if (m < nd->a) break;
                    r = run_seq(c, start, len, idx + 1, pos + (int)m, k);
                    if (r >= 0 || m == 0) break;
                }
            } else {
                r = rep_try(c, nd, 0, pos, &rest);
            }
            goto done;
        case VTTS_RE_GROUP: {
            cont_t g = {0};
            g.kind = K_GROUP_END;
            g.group = (int)nd->a;
            g.gstart = pos;
            g.up = &rest;
            r = run_seq(c, nd->body, nd->len, 0, pos, &g);
            goto done;
        }
        case VTTS_RE_BRANCH:
            for (int i = 0; i < nd->len && r < 0; i++) {
                const vtts_re_alt *alt = &c->re->alts[nd->a + i];
                r = run_seq(c, alt->start, alt->len, 0, pos, &rest);
            }
            goto done;
        case VTTS_RE_ASSERT: {
            int neg = nd->flag & 1, behind = nd->flag & 2, hit;
            int gs[VTTS_RE_MAX_GROUPS + 1], ge[VTTS_RE_MAX_GROUPS + 1];
            for (int i = 0; i <= VTTS_RE_MAX_GROUPS; i++) { gs[i] = c->gs[i]; ge[i] = c->ge[i]; }
            if (behind) {
                int from = pos - (int)nd->a;
                cont_t e = {0};
                e.kind = K_END_AT;
                e.target = pos;
                hit = from >= 0 && run_seq(c, nd->body, nd->len, 0, from, &e) >= 0;
            } else {
                hit = run_seq(c, nd->body, nd->len, 0, pos, NULL) >= 0;
            }
            if (neg || !hit)
                for (int i = 0; i <= VTTS_RE_MAX_GROUPS; i++) { c->gs[i] = gs[i]; c->ge[i] = ge[i]; }
            if (hit == neg) goto done;
            idx++;
            continue;
        }
        case VTTS_RE_GROUPREF: {
            int g = (int)nd->a, a = c->gs[g], e = c->ge[g];
            if (a < 0 || e < 0) goto done;
            for (int i = a; i < e; i++)
                if (pos >= c->n || c->s[pos++] != c->s[i]) goto done;
            idx++;
            continue;
        }
        default: goto done;
        }
    }
    r = resume(c, k, pos);
done:
    c->depth--;
    return r;
}

int vtts_re_match_at(const vtts_re *re, const uint32_t *s, int n, int pos, vtts_re_match *m) {
    ctx_t c;
    c.re = re;
    c.s = s;
    c.n = n;
    c.depth = 0;
    for (int i = 0; i <= VTTS_RE_MAX_GROUPS; i++) c.gs[i] = c.ge[i] = -1;
    int e = run_seq(&c, re->start, re->len, 0, pos, NULL);
    if (e < 0) return 0;
    m->start = pos;
    m->end = e;
    for (int i = 0; i <= VTTS_RE_MAX_GROUPS; i++) {
        int set = i <= re->groups && c.gs[i] >= 0 && c.ge[i] >= 0;
        m->gs[i] = set ? c.gs[i] : -1;
        m->ge[i] = set ? c.ge[i] : -1;
    }
    m->gs[0] = pos;
    m->ge[0] = e;
    return 1;
}

int vtts_re_search(const vtts_re *re, const uint32_t *s, int n, int pos, vtts_re_match *m) {
    for (int i = pos; i <= n; i++)
        if (vtts_re_match_at(re, s, n, i, m)) return 1;
    return 0;
}

static void put_n(vtts_re_buf *d, const uint32_t *s, int n) {
    for (int i = 0; i < n; i++) {
        if (d->n < d->cap) d->p[d->n++] = s[i];
        else d->err = 1;
    }
}

void vtts_re_sub(const vtts_re *re, const uint32_t *s, int n, vtts_re_buf *out, vtts_re_fn fn, void *user) {
    int pos = 0, copied = 0;
    vtts_re_match m;
    while (pos <= n && vtts_re_search(re, s, n, pos, &m)) {
        put_n(out, s + copied, m.start - copied);
        fn(s, n, &m, out, user);
        copied = m.end;
        if (m.end == m.start) { /* an empty match: the next character is copied (like re.sub) */
            put_n(out, s + m.end, m.end < n ? 1 : 0);
            copied = pos = m.end + 1;
        } else {
            pos = m.end;
        }
    }
    if (copied < n) put_n(out, s + copied, n - copied);
}

#endif /* VTTS_ENABLE_RU || VTTS_ENABLE_PL */
