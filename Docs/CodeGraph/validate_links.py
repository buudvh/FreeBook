#!/usr/bin/env python3
"""Validate FreeBook CodeGraph documents and their manifest.

Run without arguments for a read-only validation. Use --update-hashes after
intentional source/document changes to refresh canonical SHA-256 values.
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
FRONT_MATTER_KEYS = {
    "generated_by",
    "generator_version",
    "generated_at",
    "git_commit",
    "source_files",
    "document_version",
}


def normalized_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def source_hash(source_files: list[str]) -> str:
    digest = hashlib.sha256()
    for relative_path in source_files:
        normalized_path = Path(relative_path).as_posix()
        digest.update(normalized_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(normalized_bytes(ROOT / relative_path))
        digest.update(b"\0")
    return digest.hexdigest()


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


def current_git_commit() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "UNKNOWN"


def managed_markdown_files() -> set[str]:
    return {
        path.name
        for path in DOCS_DIR.glob("*.md")
        if MANAGED_DOC_PATTERN.match(path.name) or path.name == "rules.md"
    }


def update_hashes(manifest: dict[str, Any]) -> None:
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for document in manifest["documents"]:
        document_path = DOCS_DIR / document["filename"]
        new_source_hash = source_hash(document["sourceFiles"])
        new_generated_hash = generated_hash(document_path)
        if (
            document.get("sourceHash") != new_source_hash
            or document.get("generatedHash") != new_generated_hash
        ):
            document["sourceHash"] = new_source_hash
            document["generatedHash"] = new_generated_hash
            document["generatedAt"] = now

    manifest["generatedAt"] = now
    manifest["gitCommit"] = current_git_commit()
    manifest["sourceFileCount"] = len(list((ROOT / "Sources").rglob("*.swift")))
    manifest["documentCount"] = len(manifest["documents"])
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def validate(manifest: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    errors = validate_schema(manifest, schema)
    documents = manifest.get("documents", [])
    filenames = [document.get("filename", "") for document in documents if isinstance(document, dict)]

    for markdown_path in sorted(DOCS_DIR.glob("*.md")):
        errors.extend(validate_markdown_links(markdown_path))

    if len(filenames) != len(set(filenames)):
        errors.append("manifest contains duplicate document filenames")
    if manifest.get("documentCount") != len(documents):
        errors.append("manifest documentCount does not match documents length")

    swift_file_count = len(list((ROOT / "Sources").rglob("*.swift")))
    if manifest.get("sourceFileCount") != swift_file_count:
        errors.append(
            f"manifest sourceFileCount is {manifest.get('sourceFileCount')}, expected {swift_file_count}"
        )

    manifest_docs = set(filenames)
    orphan_docs = managed_markdown_files() - manifest_docs
    missing_docs = manifest_docs - managed_markdown_files()
    if orphan_docs:
        errors.append(f"managed documents missing from manifest: {', '.join(sorted(orphan_docs))}")
    if missing_docs:
        errors.append(f"manifest documents missing on disk: {', '.join(sorted(missing_docs))}")

    for document in documents:
        if not isinstance(document, dict):
            continue
        filename = document.get("filename", "")
        document_path = DOCS_DIR / filename
        if not document_path.is_file():
            continue

        errors.extend(validate_front_matter(document_path))
        try:
            actual_generated_hash = generated_hash(document_path)
        except ValueError as error:
            errors.append(f"{document_path.relative_to(ROOT)}: {error}")
            continue

        source_files = document.get("sourceFiles", [])
        missing_sources = [
            source for source in source_files if not (ROOT / source).is_file()
        ]
        for source in missing_sources:
            errors.append(f"{filename}: missing source file: {source}")

        expected_source_hash = document.get("sourceHash", "")
        expected_generated_hash = document.get("generatedHash", "")
        if not HASH_PATTERN.fullmatch(expected_source_hash):
            errors.append(f"{filename}: sourceHash is not lowercase SHA-256")
        if not HASH_PATTERN.fullmatch(expected_generated_hash):
            errors.append(f"{filename}: generatedHash is not lowercase SHA-256")
        if not missing_sources and source_hash(source_files) != expected_source_hash:
            errors.append(f"{filename}: sourceHash does not match sourceFiles")
        if actual_generated_hash != expected_generated_hash:
            errors.append(f"{filename}: generatedHash does not match GENERATED content")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--update-hashes",
        action="store_true",
        help="refresh canonical manifest hashes and timestamps before validating",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    if args.update_hashes:
        update_hashes(manifest)
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    errors = validate(manifest, schema)
    if errors:
        print("CodeGraph validation FAILED:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(
        "CodeGraph validation PASS: "
        f"{manifest['documentCount']} documents, "
        f"{manifest['sourceFileCount']} Swift files."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
