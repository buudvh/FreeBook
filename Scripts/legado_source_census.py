#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kiểm kê cú pháp nguồn truyện JSON của Legado (Bước 0 của
Docs/Plans/2026-09-01-plan-nguon-truyen-json-legado.md).

Dùng: python Scripts/legado_source_census.py <file.json> [file2.json ...]
Mỗi file là mảng JSON các BookSource xuất từ Legado (ví dụ tải từ yckceo).
In bảng tần suất cú pháp + ước lượng % nguồn chạy được nếu chỉ làm P1.
Không sửa file nào, không gọi mạng.
"""
import json
import io
import re
import sys
from collections import Counter

RULE_GROUPS = {
    "ruleSearch": ["bookList", "name", "author", "intro", "kind", "lastChapter",
                   "updateTime", "bookUrl", "coverUrl", "wordCount", "checkKeyWord"],
    "ruleExplore": ["bookList", "name", "author", "intro", "kind", "lastChapter",
                    "updateTime", "bookUrl", "coverUrl", "wordCount"],
    "ruleBookInfo": ["init", "name", "author", "intro", "kind", "lastChapter", "updateTime",
                     "coverUrl", "tocUrl", "wordCount", "canReName", "downloadUrls"],
    "ruleToc": ["preUpdateJs", "chapterList", "chapterName", "chapterUrl", "formatJs",
                "isVolume", "isVip", "isPay", "updateTime", "nextTocUrl"],
    "ruleContent": ["content", "subContent", "title", "nextContentUrl", "webJs",
                    "sourceRegex", "replaceRegex", "imageStyle", "imageDecode",
                    "payAction", "callBackJs"],
}
URL_FIELDS = ["searchUrl", "exploreUrl"]
SOURCE_LEVEL_BLOCKERS = ["jsLib", "loginUrl", "loginUi", "loginCheckJs", "coverDecodeJs"]

JS_RE = re.compile(r"@js:|<js>", re.I)
WEBJS_RE = re.compile(r"@webjs:", re.I)
JAVA_FN_RE = re.compile(r"\bjava\.([A-Za-z_][A-Za-z0-9_]*)")
SOURCE_FN_RE = re.compile(r"\bsource\.([A-Za-z_][A-Za-z0-9_]*)")
INDEX_RE = re.compile(r"\[[-\d:,\s!]+\]")
DIALECT_RE = re.compile(r"(?:^|@)(class|tag|id|text|children)[.\[]", re.I)


def mode_of(rule):
    """Suy ra chế độ theo đúng thứ tự nhận biết ở AnalyzeRule.kt:644-677."""
    r = rule.strip()
    if not r:
        return None
    if WEBJS_RE.search(r):
        return "WebJs"
    if JS_RE.search(r):
        return "Js"
    low = r.lower()
    if low.startswith("@css:"):
        return "Default"
    if r.startswith("@@"):
        return "Default"
    if low.startswith("@xpath:"):
        return "XPath"
    if low.startswith("@json:"):
        return "Json"
    if r.startswith("$.") or r.startswith("$["):
        return "Json"
    if r.startswith("/"):
        return "XPath"
    if r.startswith(":"):
        return "Regex"
    return "Default"


def iter_rules(src):
    """Sinh (đường_dẫn, chuỗi_rule) cho mọi rule không rỗng của một nguồn."""
    for f in URL_FIELDS:
        v = src.get(f)
        if isinstance(v, str) and v.strip():
            yield f, v
    for group, fields in RULE_GROUPS.items():
        g = src.get(group)
        if isinstance(g, str):
            try:
                g = json.loads(g)
            except Exception:
                continue
        if not isinstance(g, dict):
            continue
        for f in fields:
            v = g.get(f)
            if isinstance(v, str) and v.strip():
                yield "%s.%s" % (group, f), v


def p1_blockers(src):
    """Cú pháp khiến nguồn KHÔNG chạy được nếu chỉ làm P1 (không JS, không XPath, không WebView)."""
    out = set()
    if src.get("bookSourceType", 0) != 0:
        out.add("type!=0")
    for f in SOURCE_LEVEL_BLOCKERS:
        if isinstance(src.get(f), str) and src[f].strip():
            out.add(f)
    for path, rule in iter_rules(src):
        m = mode_of(rule)
        if m == "Js":
            out.add("js")
        elif m == "WebJs":
            out.add("webjs")
        elif m == "XPath":
            out.add("xpath")
        if "{{" in rule and path not in URL_FIELDS:
            out.add("{{}}-in-rule")
        if '"webView"' in rule or "'webView'" in rule:
            out.add("webView")
        if "queryTTF" in rule or "replaceFont" in rule:
            out.add("font")
    return out


def essential_missing(src):
    """Nguồn thiếu rule tối thiểu để đọc được truyện."""
    missing = []
    if not (src.get("searchUrl") or "").strip():
        missing.append("searchUrl")
    for group, field in (("ruleSearch", "bookList"), ("ruleSearch", "bookUrl"),
                         ("ruleToc", "chapterList"), ("ruleContent", "content")):
        g = src.get(group)
        if isinstance(g, str):
            try:
                g = json.loads(g)
            except Exception:
                g = None
        if not isinstance(g, dict) or not (g.get(field) or "").strip():
            missing.append("%s.%s" % (group, field))
    return missing


def main(paths):
    sources = []
    seen = set()
    for p in paths:
        data = json.load(io.open(p, encoding="utf-8"))
        if isinstance(data, dict):
            data = [data]
        for s in data:
            key = s.get("bookSourceUrl") or ""
            if key and key in seen:
                continue
            seen.add(key)
            sources.append(s)

    total = len(sources)
    types = Counter(s.get("bookSourceType", 0) for s in sources)
    text_sources = [s for s in sources if s.get("bookSourceType", 0) == 0]

    modes = Counter()
    feature = Counter()
    java_fns = Counter()
    source_fns = Counter()
    blocker_hist = Counter()
    p1_ok = 0
    incomplete = 0

    for s in text_sources:
        feats = set()
        for path, rule in iter_rules(s):
            m = mode_of(rule)
            if m:
                modes[m] += 1
            if JS_RE.search(rule):
                feats.add("@js/<js>")
                for fn in JAVA_FN_RE.findall(rule):
                    java_fns[fn] += 1
                for fn in SOURCE_FN_RE.findall(rule):
                    source_fns[fn] += 1
            if WEBJS_RE.search(rule):
                feats.add("@webjs")
            if "{{" in rule:
                feats.add("{{...}}")
            if "@put:" in rule.lower():
                feats.add("@put")
            if "@get:" in rule.lower():
                feats.add("@get")
            if "##" in rule:
                feats.add("##replace")
            if "###" in rule:
                feats.add("###replaceFirst")
            if "||" in rule:
                feats.add("|| or")
            if "&&" in rule:
                feats.add("&& and")
            if "%%" in rule:
                feats.add("%% zip")
            if INDEX_RE.search(rule):
                feats.add("[a:b:c] index")
            if DIALECT_RE.search(rule):
                feats.add("class./tag./id. dialect")
            if path in URL_FIELDS or path.endswith("Url") or path.endswith("Urls"):
                if re.search(r",\s*\{", rule):
                    feats.add("url option {...}")
                if '"method"' in rule.lower() or "'method'" in rule.lower():
                    feats.add("POST/method")
                if "charset" in rule.lower():
                    feats.add("charset")
                if "webview" in rule.lower():
                    feats.add("webView:true")
                if re.search(r"<[^<>]{1,60},[^<>]{1,60}>", rule):
                    feats.add("<p1,p2> page list")
            if "searchKey" in rule or "searchPage" in rule:
                feats.add("legacy searchKey")
            if "::" in rule and path == "exploreUrl":
                feats.add("explore name::url")
            if path == "exploreUrl" and rule.strip().startswith("["):
                feats.add("explore JSON array")
        for f in SOURCE_LEVEL_BLOCKERS:
            if isinstance(s.get(f), str) and s[f].strip():
                feats.add(f)
        if isinstance(s.get("ruleToc"), dict) and (s["ruleToc"].get("nextTocUrl") or "").strip():
            feats.add("nextTocUrl")
        if isinstance(s.get("ruleContent"), dict) and (s["ruleContent"].get("nextContentUrl") or "").strip():
            feats.add("nextContentUrl")
        for f in feats:
            feature[f] += 1

        miss = essential_missing(s)
        if miss:
            incomplete += 1
        bl = p1_blockers(s)
        for b in bl:
            blocker_hist[b] += 1
        if not bl and not miss:
            p1_ok += 1

    def pct(n, d):
        return "%5.1f%%" % (100.0 * n / d) if d else "  n/a"

    print("== TONG QUAN ==")
    print("Tong so nguon (da bo trung bookSourceUrl): %d" % total)
    for t in sorted(types):
        print("  bookSourceType=%d: %d (%s)" % (t, types[t], pct(types[t], total)))
    print("Nguon truyen chu (type=0): %d" % len(text_sources))
    print("  thieu rule toi thieu: %d (%s)" % (incomplete, pct(incomplete, len(text_sources))))
    print("  CHAY DUOC voi P1 (khong JS/XPath/WebView/login): %d (%s)"
          % (p1_ok, pct(p1_ok, len(text_sources))))
    print()
    print("== CHE DO RULE (dem theo tung chuoi rule) ==")
    for m, n in modes.most_common():
        print("  %-8s %6d" % (m, n))
    print()
    print("== TAN SUAT CU PHAP (dem theo nguon type=0) ==")
    for f, n in feature.most_common():
        print("  %-26s %5d  %s" % (f, n, pct(n, len(text_sources))))
    print()
    print("== LY DO KHONG CHAY DUOC VOI P1 ==")
    for b, n in blocker_hist.most_common():
        print("  %-16s %5d  %s" % (b, n, pct(n, len(text_sources))))
    print()
    print("== java.* CAN BRIDGE (top 40) ==")
    for fn, n in java_fns.most_common(40):
        print("  java.%-22s %5d" % (fn, n))
    print()
    print("== source.* CAN BRIDGE ==")
    for fn, n in source_fns.most_common():
        print("  source.%-20s %5d" % (fn, n))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])


