#!/usr/bin/env python3
"""
FreeBook Architecture Compliance Checker (v2 Fail-Closed)
Scans Sources/ directory for architectural rules violations and compares against baseline allowlist schema.
Exits with 0 on SUCCESS, 1 on VIOLATION.
"""

import os
import re
import sys
import json
from datetime import datetime

# Force UTF-8 output encoding if possible
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCES_DIR = os.path.join(ROOT_DIR, "Sources")
ALLOWLIST_PATH = os.path.join(ROOT_DIR, "Scripts", "architecture_allowlist.json")

SCOPED_VIEWS = {
    "Sources/Views/Shelf/ShelfMain/ShelfView.swift",
    "Sources/Views/Search/SearchView.swift",
    "Sources/Views/Discovery/DiscoveryView.swift",
    "Sources/Views/BookDetail/BookDetailView.swift",
    "Sources/Views/Reader/ReaderView.swift",
    "Sources/Views/Extensions/Manager/RepositoryManagerView.swift"
}

def load_allowlist():
    if not os.path.exists(ALLOWLIST_PATH):
        print(f"[FAIL] Allowlist file not found at {ALLOWLIST_PATH}")
        sys.exit(1)
    
    try:
        with open(ALLOWLIST_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[FAIL] Failed to parse allowlist JSON at {ALLOWLIST_PATH}: {e}")
        sys.exit(1)

    version = data.get("schema_version") or data.get("version")
    if version != 2:
        print(f"[FAIL] Invalid schema_version in {ALLOWLIST_PATH}: expected 2, got {version}")
        sys.exit(1)

    return data

def strip_comments_and_strings(code_text):
    # Remove block comments /* ... */
    code_text = re.sub(r'/\*.*?\*/', '', code_text, flags=re.DOTALL)
    # Remove single line comments // ...
    code_text = re.sub(r'//.*$', '', code_text, flags=re.MULTILINE)
    # Remove string literals "..."
    code_text = re.sub(r'"([^"\\]|\\.)*"', '""', code_text)
    return code_text

def count_top_level_primary_types(code_text):
    clean = strip_comments_and_strings(code_text)
    pattern = r'^(?:public\s+|internal\s+|fileprivate\s+|private\s+|final\s+|open\s+|@\w+(?:\([^)]*\))?\s+)*(?:class|struct|enum|actor)\s+\w+'
    matches = []
    for line in clean.splitlines():
        # Only match lines starting at indentation level 0 (top-level)
        if line and not line[0].isspace():
            if re.match(pattern, line.strip()):
                matches.append(line.strip())
    return len(matches)

# Rule 6 (WHITE_TINT_FILL) — xem chú thích ở run_checks.
_ACCENT_BACKGROUND = re.compile(
    r"\.background\([^)]*?Color\.accentColor(?!\.opacity\(\s*0?\.[0-4])"   # nền màu nhấn đặc (mờ < 50% thì được)
    r"|\.background\(\s*\.(?:tint|accentColor)\b"                          # .background(.tint) / (.accentColor)
)
_SAFE_TINT = re.compile(r"\.tint\((?!\s*(?:\.white|Color\.white|\.accentColor|Color\.accentColor)\s*\))")
_FILLED_HINT = "dùng .buttonStyle(.appFilled) (AppFilledButtonStyle) hoặc nền màu cố định khác trắng"


def find_white_tint_fills(raw_lines):
    """(số dòng, thông điệp) của các chỗ tô nền đặc bằng màu nhấn — với tint trắng toàn cục là trắng trên trắng."""
    found = []
    for index, line in enumerate(raw_lines):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if ".borderedProminent" in line:
            # Chỉ chuỗi modifier của chính nút này: dòng ngay trước nếu là `.tint(`, dòng hiện tại, và tối đa 4 dòng sau
            # cho tới khi gặp nút khác — không "mượn" tint của nút liền kề.
            window = [line]
            if index > 0 and raw_lines[index - 1].strip().startswith(".tint("):
                window.append(raw_lines[index - 1])
            for other in raw_lines[index + 1: index + 5]:
                if "Button(" in other or ".buttonStyle(" in other:
                    break
                window.append(other)
            if not any(_SAFE_TINT.search(other) for other in window):
                found.append((index + 1, ".borderedProminent không kèm .tint(<màu khác trắng>) — nền trắng; " + _FILLED_HINT))
        if _ACCENT_BACKGROUND.search(line):
            found.append((index + 1, "nền Color.accentColor đặc (tint toàn app là trắng) — " + _FILLED_HINT))
    return found


def run_checks():
    allowlist = load_allowlist()
    
    size_allowlist = {}
    view_write_allowlist = set()
    service_toast_allowlist = set()
    multi_type_allowlist = set()

    now = datetime.now()

    for item in allowlist.get("violations", []):
        rule = item.get("rule")
        path = item.get("path", "").replace("\\", "/")
        expires = item.get("expires") or item.get("expiresAt")
        if expires:
            try:
                exp_date = datetime.strptime(expires, "%Y-%m-%d")
                if now > exp_date:
                    print(f"[FAIL] Expired allowlist record for {path} (rule {rule}, expired {expires})")
                    sys.exit(1)
            except ValueError:
                print(f"[FAIL] Invalid expiration date format for {path}: {expires}")
                sys.exit(1)

        if rule == "FILE_SIZE_LIMIT":
            size_allowlist[path] = item.get("baseline_value", 400)
        elif rule == "VIEW_SWIFTDATA_MUTATION":
            view_write_allowlist.add(path)
        elif rule == "SERVICE_TOAST_COUPLING":
            service_toast_allowlist.add(path)
        elif rule == "MULTI_PRIMARY_TYPES":
            multi_type_allowlist.add(path)

    errors = []
    
    for root, dirs, files in os.walk(SOURCES_DIR):
        for file in files:
            if not file.endswith(".swift"):
                continue
            
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, ROOT_DIR).replace("\\", "/")
            
            with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                raw_lines = f.readlines()
            
            physical_lines = len(raw_lines)
            code_text = "".join(raw_lines)
            clean_code = strip_comments_and_strings(code_text)
            
            # Rule 1: File physical line limit (Max 400 lines for new files, or baseline limit)
            if rel_path in size_allowlist:
                allowed = size_allowlist[rel_path]
                if physical_lines > allowed:
                    errors.append(f"[LINE_LIMIT_EXCEEDED] {rel_path}: {physical_lines} physical lines exceeds baseline allowed {allowed}")
            else:
                if physical_lines > 400:
                    errors.append(f"[NEW_FILE_TOO_LARGE] {rel_path}: {physical_lines} physical lines exceeds maximum 400 lines limit for new files")
            
            # Rule 2: One Primary Type per file for non-allowlisted files
            if rel_path not in multi_type_allowlist:
                top_types_count = count_top_level_primary_types(code_text)
                if top_types_count > 1:
                    errors.append(f"[MULTI_PRIMARY_TYPES] {rel_path}: Contains {top_types_count} top-level primary types (expected <= 1)")

            # Rule 3: SwiftData mutations in Views (modelContext.insert, delete, save, direct @Model property assignments, or ignored coordinator Results)
            is_scoped_view = rel_path in SCOPED_VIEWS or any(v.replace(".swift", "") in rel_path for v in SCOPED_VIEWS)
            if rel_path.startswith("Sources/Views/"):
                has_context_mutation = re.search(r'modelContext\.(insert|delete|save)', clean_code)
                # `self.<prop> = ...` bị loại: trong một View (struct) `self` không bao giờ là @Model,
                # đó chỉ là init gán thuộc tính của chính View (vd DiscoveryCategoryTabView.init).
                has_model_property_mutation = is_scoped_view and re.search(r'(?<!\bself)\.(isOnShelf|isPinned|localPath|version|downloadUrl|titleTrans|lastUpdated|currentChapterIndex)\s*=', clean_code)
                has_ignored_coordinator_call = is_scoped_view and re.search(r'_\s*=\s*(BookTransactionCoordinator|ExtensionTransactionCoordinator)', clean_code)
                if has_context_mutation or has_model_property_mutation or has_ignored_coordinator_call:
                    if rel_path not in view_write_allowlist:
                        errors.append(f"[VIEW_SWIFTDATA_MUTATION] {rel_path}: Contains direct modelContext mutation, @Model property assignment, or ignored transaction Result in View layer")
            
            # Rule 4: ToastManager.shared calls in Services
            if rel_path.startswith("Sources/Services/"):
                if "ToastManager.shared" in clean_code:
                    if rel_path not in service_toast_allowlist:
                        errors.append(f"[SERVICE_TOAST_COUPLING] {rel_path}: Service layer calls ToastManager.shared directly")
            
            # Rule 5: SwiftUI imports in Services (except platform adapters)
            if rel_path.startswith("Sources/Services/"):
                if "import SwiftUI" in clean_code and not rel_path.endswith("WebViewLoader.swift"):
                    errors.append(f"[SERVICE_SWIFTUI_IMPORT] {rel_path}: Service layer imports SwiftUI framework")

            # Rule 6: nền đặc bằng màu nhấn. `MainTabView` đặt `.tint(.white)` toàn cục ⇒ `Color.accentColor` và
            # `.borderedProminent` không kèm tint là NỀN TRẮNG; chữ trắng lên đó là vô hình (1.3.447, 1.3.572).
            if rel_path.startswith("Sources/Views/"):
                for line_no, message in find_white_tint_fills(raw_lines):
                    errors.append(f"[WHITE_TINT_FILL] {rel_path}:{line_no}: {message}")

    print("\n--- FreeBook Architecture Compliance Checker ---")
    if errors:
        print(f"[FAIL] Found {len(errors)} architecture violation(s):")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)
    else:
        print("[PASS] 0 architecture violations found. Codebase complies with rules.")
        sys.exit(0)

if __name__ == "__main__":
    run_checks()
