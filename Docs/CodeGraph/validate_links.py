#!/usr/bin/env python3
"""Validate FreeBook CodeGraph documents and their manifest.

Chế độ chạy:
  (không cờ)                 kiểm tra read-only, FAIL nếu có doc bị stale
  --explain [--since REF]    in ra doc nào cần cập nhật và vì sao
  --accept DOC...            ghi nhận doc đã được cập nhật (bắt buộc vùng GENERATED đã đổi)
  --no-change-needed DOC...  ghi nhận "đã xem, không cần đổi" cho doc (có audit trail)
  --update-hashes            accept mọi doc có GENERATED đã đổi; FAIL nếu còn doc stale
  --bootstrap                tính lại toàn bộ hash, không kiểm tra gì (chỉ dùng khi sửa sourcePatterns)

Staleness được tính theo `staleOn` của từng doc:
  structure  -> chỉ stale khi *tập* file khớp sourcePatterns thay đổi (thêm/xoá/đổi tên)
  content    -> stale khi tập file thay đổi *hoặc* nội dung file khớp pattern thay đổi
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
DOCS_DIR = ROOT / "Docs" / "CodeGraph"
MANIFEST_PATH = DOCS_DIR / "manifest.json"
SCHEMA_PATH = DOCS_DIR / "codegraph.schema.json"
GENERATED_START = "<!-- GENERATED START -->"
GENERATED_END = "<!-- GENERATED END -->"
HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*]\(([^)]+)\)")
MANAGED_DOC_PATTERN = re.compile(r"^\d{2}_.+\.md$")
STALE_MODES = {"structure", "content"}
MAX_LISTED_PATHS = 8
FRONT_MATTER_KEYS = {
    "generated_by",
    "generator_version",
    "generated_at",
    "git_commit",
    "source_files",
    "document_version",
}


# --------------------------------------------------------------------------
# Hashing & source resolution
# --------------------------------------------------------------------------


def normalized_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def resolve_sources(patterns: list[str]) -> list[str]:
    """Giải các glob trong sourcePatterns thành danh sách đường dẫn tương đối."""
    resolved: set[str] = set()
    for pattern in patterns:
        for path in ROOT.glob(pattern):
            if not path.is_file():
                continue
            try:
                resolved.add(path.relative_to(ROOT).as_posix())
            except ValueError:
                continue
    return sorted(resolved)


def structure_hash(source_files: list[str]) -> str:
    """Băm *tập đường dẫn* — đổi khi thêm/xoá/đổi tên file, không đổi khi sửa nội dung."""
    digest = hashlib.sha256()
    for relative_path in source_files:
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
    return digest.hexdigest()


def source_hash(source_files: list[str]) -> str:
    """Băm đường dẫn + nội dung đã chuẩn hoá LF."""
    digest = hashlib.sha256()
    for relative_path in source_files:
        normalized_path = Path(relative_path).as_posix()
        digest.update(normalized_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(normalized_bytes(ROOT / relative_path))
        digest.update(b"\0")
    return digest.hexdigest()


def all_swift_files() -> list[str]:
    return sorted(
        path.relative_to(ROOT).as_posix() for path in (ROOT / "Sources").rglob("*.swift")
    )


def generated_region(document_path: Path) -> str:
    content = document_path.read_text(encoding="utf-8")
    if content.count(GENERATED_START) != 1 or content.count(GENERATED_END) != 1:
        raise ValueError("must contain exactly one GENERATED marker pair")
    start = content.index(GENERATED_START) + len(GENERATED_START)
    end = content.index(GENERATED_END)
    if start > end:
        raise ValueError("GENERATED END appears before GENERATED START")
    return content[start:end].replace("\r\n", "\n").replace("\r", "\n")


def generated_hash(document_path: Path) -> str:
    return hashlib.sha256(generated_region(document_path).encode("utf-8")).hexdigest()


def git_output(args: list[str]) -> str | None:
    try:
        return subprocess.run(
            ["git", *args],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def current_git_commit() -> str:
    return git_output(["rev-parse", "HEAD"]) or "UNKNOWN"


def changed_swift_files(since: str | None) -> list[str] | None:
    """File Swift đã đổi so với `since` (mặc định: cây làm việc so với HEAD)."""
    args = ["diff", "--name-only"]
    if since:
        args.append(f"{since}...HEAD")
    else:
        args.append("HEAD")
    args.extend(["--", "Sources"])
    output = git_output(args)
    if output is None:
        return None
    return sorted(
        line.strip()
        for line in output.splitlines()
        if line.strip().endswith(".swift")
    )


# --------------------------------------------------------------------------
# Manifest schema validation
# --------------------------------------------------------------------------


def type_matches(value: Any, schema_type: str) -> bool:
    if schema_type == "object":
        return isinstance(value, dict)
    if schema_type == "array":
        return isinstance(value, list)
    if schema_type == "string":
        return isinstance(value, str)
    if schema_type == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if schema_type == "boolean":
        return isinstance(value, bool)
    return True


def validate_schema_value(value: Any, schema: dict[str, Any], path: str) -> list[str]:
    errors: list[str] = []
    schema_type = schema.get("type", "")
    if schema_type and not type_matches(value, schema_type):
        return [f"{path} must be {schema_type}"]

    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path} is missing required field: {key}")
        for key, property_schema in schema.get("properties", {}).items():
            if key in value:
                errors.extend(
                    validate_schema_value(value[key], property_schema, f"{path}.{key}")
                )

    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            errors.extend(
                validate_schema_value(item, schema["items"], f"{path}[{index}]")
            )

    if isinstance(value, str) and schema.get("format") == "date-time":
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                raise ValueError
        except ValueError:
            errors.append(f"{path} must be an RFC 3339 date-time")
    return errors


def validate_schema(manifest: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    return validate_schema_value(manifest, schema, "manifest")


# --------------------------------------------------------------------------
# Document-level checks
# --------------------------------------------------------------------------


def validate_front_matter(document_path: Path) -> list[str]:
    content = document_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not content.startswith("---\n"):
        return [f"{document_path.relative_to(ROOT)}: missing YAML front matter"]
    end = content.find("\n---\n", 4)
    if end < 0:
        return [f"{document_path.relative_to(ROOT)}: unterminated YAML front matter"]

    keys = {
        line.split(":", 1)[0].strip()
        for line in content[4:end].splitlines()
        if ":" in line
    }
    missing = sorted(FRONT_MATTER_KEYS - keys)
    if missing:
        return [
            f"{document_path.relative_to(ROOT)}: missing front matter keys: {', '.join(missing)}"
        ]
    return []


def validate_markdown_links(document_path: Path) -> list[str]:
    errors: list[str] = []
    content = document_path.read_text(encoding="utf-8")
    for raw_target in MARKDOWN_LINK_PATTERN.findall(content):
        target = raw_target.strip()
        if target.startswith("<") and ">" in target:
            target = target[1:target.index(">")]
        else:
            target = target.split(maxsplit=1)[0]
        target = unquote(target)
        if not target or target.startswith(("#", "http://", "https://", "mailto:", "app://")):
            continue

        file_part = target.split("#", 1)[0]
        if not file_part:
            continue
        linked_path = (
            ROOT / file_part.lstrip("/")
            if file_part.startswith("/")
            else document_path.parent / file_part
        ).resolve()
        try:
            linked_path.relative_to(ROOT)
        except ValueError:
            errors.append(
                f"{document_path.relative_to(ROOT)}: link escapes repository: {raw_target}"
            )
            continue
        if not linked_path.exists():
            errors.append(
                f"{document_path.relative_to(ROOT)}: broken link: {raw_target}"
            )
    return errors


def managed_markdown_files() -> set[str]:
    return {
        path.name
        for path in DOCS_DIR.glob("*.md")
        if MANAGED_DOC_PATTERN.match(path.name) or path.name == "rules.md"
    }


# --------------------------------------------------------------------------
# Staleness evaluation
# --------------------------------------------------------------------------


def listed(paths: list[str]) -> str:
    if len(paths) <= MAX_LISTED_PATHS:
        return ", ".join(paths)
    head = ", ".join(paths[:MAX_LISTED_PATHS])
    return f"{head} (+{len(paths) - MAX_LISTED_PATHS} file nữa)"


def evaluate(document: dict[str, Any]) -> dict[str, Any]:
    """Tính giá trị hash thực tế của một document theo sourcePatterns hiện tại."""
    document_path = DOCS_DIR / document.get("filename", "")
    resolved = resolve_sources(document.get("sourcePatterns", []))
    actual: dict[str, Any] = {
        "sourceFiles": resolved,
        "structureHash": structure_hash(resolved),
        "sourceHash": source_hash(resolved),
        "generatedHash": None,
        "generatedError": None,
    }
    try:
        actual["generatedHash"] = generated_hash(document_path)
    except (ValueError, OSError) as error:
        actual["generatedError"] = str(error)
    return actual


def staleness(document: dict[str, Any], actual: dict[str, Any]) -> list[str]:
    """Trả về danh sách lý do doc bị stale; rỗng nghĩa là doc còn khớp source."""
    reasons: list[str] = []
    stale_on = document.get("staleOn", "content")

    if document.get("structureHash") != actual["structureHash"]:
        previous = set(document.get("sourceFiles", []))
        current = set(actual["sourceFiles"])
        added = sorted(current - previous)
        removed = sorted(previous - current)
        parts = []
        if added:
            parts.append(f"thêm: {listed(added)}")
        if removed:
            parts.append(f"xoá/đổi tên: {listed(removed)}")
        reasons.append(
            "tập file khớp sourcePatterns đã đổi"
            + (f" ({'; '.join(parts)})" if parts else "")
        )

    if stale_on == "content" and document.get("sourceHash") != actual["sourceHash"]:
        since = document.get("reviewedCommit")
        changed = changed_swift_files(since if since and since != "UNKNOWN" else None)
        scope = set(actual["sourceFiles"])
        relevant = sorted(set(changed or []) & scope)
        detail = f" ({listed(relevant)})" if relevant else ""
        reasons.append(f"nội dung file khớp sourcePatterns đã đổi{detail}")

    return reasons


# --------------------------------------------------------------------------
# Review bookkeeping
# --------------------------------------------------------------------------


def apply_review(
    document: dict[str, Any],
    actual: dict[str, Any],
    mode: str,
    now: str,
    commit: str,
) -> None:
    """Ghi nhận doc đã được xem xét: đồng bộ mọi hash và audit trail."""
    document["sourceFiles"] = actual["sourceFiles"]
    document["structureHash"] = actual["structureHash"]
    document["sourceHash"] = actual["sourceHash"]
    if actual["generatedHash"] is not None:
        document["generatedHash"] = actual["generatedHash"]
    document["generatedAt"] = now
    document["reviewedAt"] = now
    document["reviewedCommit"] = commit
    document["reviewMode"] = mode


def write_manifest(manifest: dict[str, Any], now: str, commit: str) -> None:
    manifest["schemaVersion"] = 2
    manifest["generatedAt"] = now
    manifest["gitCommit"] = commit
    manifest["sourceFileCount"] = len(all_swift_files())
    manifest["documentCount"] = len(manifest.get("documents", []))
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def normalize_doc_name(raw: str) -> str:
    """Chấp nhận `08`, `08_lifecycle.md`, `rules`, hoặc đường dẫn đầy đủ."""
    name = Path(raw.replace("\\", "/")).name
    if not name.endswith(".md"):
        name = f"{name}.md"
    if (DOCS_DIR / name).exists():
        return name
    prefix = name[:-3]
    matches = sorted(
        path.name for path in DOCS_DIR.glob(f"{prefix}*.md")
    )
    if len(matches) == 1:
        return matches[0]
    return name


# --------------------------------------------------------------------------
# Read-only validation
# --------------------------------------------------------------------------


def check_coverage(manifest: dict[str, Any]) -> list[str]:
    """Mọi file Swift phải thuộc phạm vi một doc, và phải có doc content-mode phụ trách.

    Điều kiện thứ hai là thứ bảo đảm "sửa logic thì có doc bị stale": doc `structure`
    chỉ phản ứng khi tập file đổi, nên nếu một file chỉ được doc `structure` phủ thì
    sửa nội dung nó sẽ không làm doc nào bị stale.
    """
    messages: list[str] = []
    every: set[str] = set()
    content_only: set[str] = set()
    for document in manifest.get("documents", []):
        resolved = resolve_sources(document.get("sourcePatterns", []))
        every.update(resolved)
        if document.get("staleOn", "content") == "content":
            content_only.update(resolved)

    swift_files = set(all_swift_files())
    missing = sorted(swift_files - every)
    if missing:
        messages.append(
            f"{len(missing)} file Swift không khớp sourcePatterns của bất kỳ doc nào: "
            f"{listed(missing)}"
        )
    uncovered_content = sorted(swift_files - content_only - set(missing))
    if uncovered_content:
        messages.append(
            f"{len(uncovered_content)} file Swift chỉ được doc staleOn=structure phủ nên "
            f"sửa nội dung sẽ không làm doc nào stale: {listed(uncovered_content)}"
        )
    return messages


def validate(
    manifest: dict[str, Any], schema: dict[str, Any]
) -> tuple[list[str], dict[str, list[str]]]:
    errors = validate_schema(manifest, schema)
    documents = manifest.get("documents", [])
    declared = {document.get("filename", "") for document in documents}
    managed = managed_markdown_files()

    for name in sorted(managed - declared):
        errors.append(f"manifest thiếu doc: {name}")
    for name in sorted(declared - managed):
        errors.append(f"manifest khai doc không tồn tại: {name}")

    swift_count = len(all_swift_files())
    if manifest.get("sourceFileCount") != swift_count:
        errors.append(
            f"manifest.sourceFileCount = {manifest.get('sourceFileCount')} "
            f"nhưng repo có {swift_count} file Swift"
        )
    if manifest.get("documentCount") != len(documents):
        errors.append(
            f"manifest.documentCount = {manifest.get('documentCount')} "
            f"nhưng documents có {len(documents)} phần tử"
        )
    errors.extend(check_coverage(manifest))

    for path in sorted(DOCS_DIR.glob("*.md")):
        errors.extend(validate_markdown_links(path))
    return errors, per_document_checks(documents, errors)


def per_document_checks(
    documents: list[dict[str, Any]], errors: list[str]
) -> dict[str, list[str]]:
    """Kiểm tra từng doc; trả về map doc -> lý do stale. `errors` được bổ sung tại chỗ."""
    stale: dict[str, list[str]] = {}
    for document in documents:
        name = document.get("filename", "")
        document_path = DOCS_DIR / name
        if not document_path.exists():
            errors.append(f"{name}: file không tồn tại trong Docs/CodeGraph")
            continue

        errors.extend(validate_front_matter(document_path))

        if document.get("staleOn", "content") not in STALE_MODES:
            errors.append(
                f"{name}: staleOn = {document.get('staleOn')!r} không hợp lệ "
                f"(chỉ nhận {sorted(STALE_MODES)})"
            )
        if not document.get("sourcePatterns"):
            errors.append(f"{name}: thiếu sourcePatterns")
        for key in ("structureHash", "sourceHash", "generatedHash"):
            value = document.get(key)
            if not isinstance(value, str) or not HASH_PATTERN.match(value):
                errors.append(f"{name}: {key} không phải sha256 hợp lệ")

        actual = evaluate(document)
        if actual["generatedError"]:
            errors.append(f"{name}: {actual['generatedError']}")
        elif actual["generatedHash"] != document.get("generatedHash"):
            errors.append(
                f"{name}: vùng GENERATED đã đổi nhưng generatedHash chưa được ghi nhận "
                f"(chạy --accept {name})"
            )

        reasons = staleness(document, actual)
        if reasons:
            stale[name] = reasons
    return stale


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def report(
    manifest: dict[str, Any], errors: list[str], stale: dict[str, list[str]]
) -> int:
    for message in errors:
        print(f"FAIL: {message}")
    for name, reasons in sorted(stale.items()):
        print(f"STALE: {name}: {'; '.join(reasons)}")
    if errors or stale:
        if stale:
            print(
                "\nDoc bị stale nghĩa là source đã đổi mà doc chưa được xem lại. "
                "Chạy `--explain` để biết đổi ở đâu, sửa doc rồi `--accept DOC`, "
                "hoặc `--no-change-needed DOC` nếu doc vẫn đúng."
            )
        return 1
    print(
        f"PASS: {len(manifest.get('documents', []))} documents, "
        f"{len(all_swift_files())} Swift files"
    )
    return 0


def report_explain(manifest: dict[str, Any], since: str | None) -> int:
    changed = changed_swift_files(since)
    print(f"So sánh với: {since or 'HEAD (cây làm việc)'}")
    if changed is None:
        print("  ! git không dùng được — chỉ dựa vào hash trong manifest")
        changed = []
    else:
        print(f"  File Swift đã đổi: {len(changed)}")
        for relative_path in changed:
            print(f"    - {relative_path}")

    for message in check_coverage(manifest):
        print(f"\n! {message}")
        print("  => thêm file vào sourcePatterns của doc phụ trách rồi chạy --bootstrap")
    return explain_documents(manifest)


def explain_documents(manifest: dict[str, Any]) -> int:
    pending: list[str] = []
    for document in manifest.get("documents", []):
        name = document.get("filename", "")
        actual = evaluate(document)
        reasons = staleness(document, actual)
        generated_changed = (
            actual["generatedHash"] is not None
            and actual["generatedHash"] != document.get("generatedHash")
        )
        if not reasons:
            if generated_changed:
                pending.append(name)
                print(f"\n{name}")
                print("  - vùng GENERATED đã sửa nhưng chưa được ghi nhận")
                print(f"  => --accept {name}")
            continue
        pending.append(name)
        print(f"\n{name} (staleOn={document.get('staleOn', 'content')})")
        for reason in reasons:
            print(f"  - {reason}")
        if generated_changed:
            print(f"  => vùng GENERATED đã sửa, ghi nhận bằng: --accept {name}")
        else:
            print(
                "  => vùng GENERATED chưa sửa. Sửa doc rồi --accept, hoặc "
                f"--no-change-needed {name} nếu doc vẫn đúng với code mới"
            )

    if not pending:
        print("\nKhông doc nào cần cập nhật.")
        return 0
    print(f"\n{len(pending)} doc cần xem lại: {', '.join(pending)}")
    return 1


# --------------------------------------------------------------------------
# Write modes
# --------------------------------------------------------------------------


def record_reviews(
    manifest: dict[str, Any],
    accept: list[str],
    no_change_needed: list[str],
    now: str,
    commit: str,
) -> int:
    by_name = {
        document.get("filename", ""): document
        for document in manifest.get("documents", [])
    }
    errors: list[str] = []
    recorded: list[str] = []

    for mode, raw_names in (("accept", accept), ("no-change-needed", no_change_needed)):
        for raw_name in raw_names:
            name = normalize_doc_name(raw_name)
            document = by_name.get(name)
            if document is None:
                errors.append(f"{raw_name}: không có doc {name} trong manifest")
                continue
            actual = evaluate(document)
            if actual["generatedError"]:
                errors.append(f"{name}: {actual['generatedError']}")
                continue
            generated_changed = actual["generatedHash"] != document.get("generatedHash")
            if mode == "accept" and not generated_changed:
                errors.append(
                    f"{name}: vùng GENERATED không đổi nên không thể --accept. "
                    f"Sửa doc, hoặc dùng --no-change-needed {name} nếu doc vẫn đúng"
                )
                continue
            apply_review(document, actual, mode, now, commit)
            recorded.append(f"{name} [{mode}]")

    if errors:
        for message in errors:
            print(f"FAIL: {message}")
        return 1

    write_manifest(manifest, now, commit)
    for entry in recorded:
        print(f"RECORDED: {entry}")
    return 0


def update_hashes(manifest: dict[str, Any], now: str, commit: str) -> int:
    """Accept mọi doc có GENERATED đã đổi; doc còn stale vẫn FAIL."""
    accepted: list[str] = []
    for document in manifest.get("documents", []):
        actual = evaluate(document)
        if actual["generatedError"]:
            print(f"FAIL: {document.get('filename', '')}: {actual['generatedError']}")
            return 1
        if actual["generatedHash"] != document.get("generatedHash"):
            apply_review(document, actual, "accept", now, commit)
            accepted.append(document.get("filename", ""))

    write_manifest(manifest, now, commit)
    for name in accepted:
        print(f"RECORDED: {name} [accept]")
    if not accepted:
        print("Không doc nào có vùng GENERATED thay đổi.")

    remaining = explain_documents(manifest)
    if remaining:
        print(
            "\nFAIL: còn doc stale. --update-hashes chỉ ghi nhận doc đã sửa; "
            "doc còn lại cần --accept sau khi sửa hoặc --no-change-needed."
        )
    return remaining


def bootstrap(manifest: dict[str, Any], now: str, commit: str) -> int:
    for document in manifest.get("documents", []):
        actual = evaluate(document)
        if actual["generatedError"]:
            print(f"FAIL: {document.get('filename', '')}: {actual['generatedError']}")
            return 1
        apply_review(document, actual, "bootstrap", now, commit)
    write_manifest(manifest, now, commit)
    print(
        f"BOOTSTRAP: {len(manifest.get('documents', []))} documents, "
        f"{len(all_swift_files())} Swift files"
    )
    for message in check_coverage(manifest):
        print(f"! {message}")
    return 0


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate FreeBook CodeGraph documents and their manifest.",
    )
    parser.add_argument(
        "--explain", action="store_true", help="in ra doc nào cần cập nhật và vì sao"
    )
    parser.add_argument(
        "--since", metavar="REF", help="mốc git để so sánh khi dùng --explain"
    )
    parser.add_argument(
        "--accept", nargs="+", metavar="DOC", default=[],
        help="ghi nhận doc đã được cập nhật (vùng GENERATED phải đã đổi)",
    )
    parser.add_argument(
        "--no-change-needed", nargs="+", metavar="DOC", default=[],
        dest="no_change_needed",
        help="ghi nhận đã xem doc và kết luận không cần đổi",
    )
    parser.add_argument(
        "--update-hashes", action="store_true", dest="update_hashes",
        help="accept mọi doc có GENERATED đã đổi; FAIL nếu còn doc stale",
    )
    parser.add_argument(
        "--bootstrap", action="store_true",
        help="tính lại toàn bộ hash, không kiểm tra gì (chỉ khi sửa sourcePatterns)",
    )
    return parser.parse_args()


def use_utf8_output() -> None:
    """Console Windows mặc định không phải UTF-8; thông báo tiếng Việt sẽ vỡ nếu không đổi."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def main() -> int:
    use_utf8_output()
    args = parse_args()
    manifest = load_json(MANIFEST_PATH)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    commit = current_git_commit()

    if args.explain:
        return report_explain(manifest, args.since)
    if args.bootstrap:
        return bootstrap(manifest, now, commit)
    if args.accept or args.no_change_needed:
        return record_reviews(
            manifest, args.accept, args.no_change_needed, now, commit
        )
    if args.update_hashes:
        return update_hashes(manifest, now, commit)

    errors, stale = validate(manifest, load_json(SCHEMA_PATH))
    return report(manifest, errors, stale)


if __name__ == "__main__":
    sys.exit(main())
