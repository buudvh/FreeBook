#!/usr/bin/env python3
"""Đăng IPA lên GitHub Release và cập nhật nguồn LiveContainer (định dạng nguồn AltStore).

Chạy trong `.github/workflows/build-ipa.yml` sau khi đóng gói IPA thành công, chỉ với lượt push lên `main`.

1. Tạo release `build-<số build>` đính kèm `TangCongCac-<version>-<số build>.ipa`. Lượt chạy lại (`Re-run`) giữ
   nguyên số build ⇒ release cùng tag bị xoá rồi tạo lại.
2. Chỉ giữ `--keep` release `build-*` mới nhất; release cũ hơn bị xoá kèm tag (`--cleanup-tag`).
3. Dựng `apps.json` từ các release còn lại rồi đẩy lên nhánh riêng `source` (không phải `main` ⇒ không kích hoạt
   build lại, không đụng lịch sử code). Push bị từ chối (hai lượt build đẩy cùng lúc) ⇒ tải lại nhánh, dựng lại từ
   danh sách release mới nhất rồi đẩy lại.

URL nguồn cố định: https://raw.githubusercontent.com/<repo>/source/apps.json — app đọc ở `AppDistributionSource`.

Cần `gh` (có sẵn trên runner macOS), biến môi trường `GH_TOKEN` (quyền `contents: write`) và `REPO` (`owner/name`).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

TAG_RE = re.compile(r"^build-(\d+)$")
ASSET_RE = re.compile(r"^TangCongCac-(\d+\.\d+\.\d+)-(\d+)\.ipa$")
SOURCE_BRANCH = "source"
BUNDLE_ID = "com.raikiri1498.FreeBook"


def run(cmd, check=True, capture=False, cwd=None):
    result = subprocess.run(cmd, check=False, text=True, cwd=cwd,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if check and result.returncode != 0:
        detail = (result.stderr or "").strip() if capture else ""
        raise RuntimeError(f"Lệnh lỗi ({result.returncode}): {cmd[0]} {cmd[1]} {detail}")
    return result


def list_build_releases(repo):
    # `--slurp` gói mọi trang vào một mảng ngoài ⇒ `[[trang 1], [trang 2], …]`.
    out = run(["gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"], capture=True).stdout
    pages = json.loads(out) if out.strip() else []
    releases = [rel for page in pages for rel in page]
    builds = []
    for rel in releases:
        match = TAG_RE.match(rel.get("tag_name", ""))
        if match:
            builds.append((int(match.group(1)), rel))
    builds.sort(key=lambda item: item[0], reverse=True)
    return builds


def publish_release(repo, ipa, version, build, notes, sha):
    tag = f"build-{build}"
    asset_name = f"TangCongCac-{version}-{build}.ipa"
    staged_dir = tempfile.mkdtemp()
    staged = os.path.join(staged_dir, asset_name)
    shutil.copyfile(ipa, staged)
    if run(["gh", "release", "view", tag, "--repo", repo], check=False, capture=True).returncode == 0:
        print(f"Release {tag} đã có (chạy lại workflow) ⇒ xoá rồi tạo lại.")
        run(["gh", "release", "delete", tag, "--repo", repo, "--cleanup-tag", "--yes"])
    run(["gh", "release", "create", tag, staged, "--repo", repo, "--target", sha,
         "--title", f"Tàng Công Các {version} ({build})", "--notes", notes or f"Build {build}"])
    print(f"Đã tạo release {tag} với {asset_name}.")


def prune_releases(repo, keep):
    for number, rel in list_build_releases(repo)[keep:]:
        tag = rel["tag_name"]
        result = run(["gh", "release", "delete", tag, "--repo", repo, "--cleanup-tag", "--yes"],
                     check=False, capture=True)
        print(f"Xoá release cũ {tag}: {'ok' if result.returncode == 0 else 'lỗi ' + (result.stderr or '').strip()}")


def build_source(repo, keep):
    raw_base = f"https://raw.githubusercontent.com/{repo}/{SOURCE_BRANCH}"
    versions = []
    for number, rel in list_build_releases(repo)[:keep]:
        for asset in rel.get("assets", []):
            match = ASSET_RE.match(asset.get("name", ""))
            if not match:
                continue
            versions.append({
                "version": match.group(1),
                "buildVersion": match.group(2),
                "date": rel.get("published_at") or rel.get("created_at"),
                "localizedDescription": (rel.get("body") or "").strip(),
                "downloadURL": asset["browser_download_url"],
                "size": asset.get("size", 0),
                "minOSVersion": "17.0",
            })
            break
    if not versions:
        raise RuntimeError("Không có release build-* nào kèm IPA để dựng nguồn.")
    latest = versions[0]
    app = {
        "name": "Tàng Công Các",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": repo.split("/")[0],
        "subtitle": "Đọc truyện, truyện tranh, xem phim, nghe đọc truyện",
        "localizedDescription": "Đọc truyện chữ, truyện tranh và xem phim từ tiện ích nguồn; dịch VietPhrase, nghe đọc truyện (TTS).",
        "iconURL": f"{raw_base}/icon.png",
        "tintColor": "#2BB3A3",
        "versions": versions,
        # Trường kiểu cũ (một bản) cho trình đọc nguồn chưa hiểu `versions`.
        "version": latest["version"],
        "versionDate": latest["date"],
        "versionDescription": latest["localizedDescription"],
        "downloadURL": latest["downloadURL"],
        "size": latest["size"],
        "appPermissions": {},
    }
    return {
        "name": "Tàng Công Các",
        "identifier": f"{BUNDLE_ID}.source",
        "sourceURL": f"{raw_base}/apps.json",
        "iconURL": f"{raw_base}/icon.png",
        "apps": [app],
        "news": [],
    }


def push_source(repo, token, icon, keep, label, attempts=3):
    remote = f"https://x-access-token:{token}@github.com/{repo}.git"
    for attempt in range(1, attempts + 1):
        work = tempfile.mkdtemp()
        has_branch = run(["git", "ls-remote", "--exit-code", "--heads", remote, SOURCE_BRANCH],
                         check=False, capture=True).returncode == 0
        if has_branch:
            run(["git", "clone", "--quiet", "--depth", "1", "--branch", SOURCE_BRANCH, remote, work], capture=True)
        else:
            run(["git", "init", "--quiet", work], capture=True)
            run(["git", "checkout", "--quiet", "--orphan", SOURCE_BRANCH], cwd=work, capture=True)
            run(["git", "remote", "add", "origin", remote], cwd=work, capture=True)
        source = build_source(repo, keep)
        with open(os.path.join(work, "apps.json"), "w", encoding="utf-8") as fh:
            json.dump(source, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        shutil.copyfile(icon, os.path.join(work, "icon.png"))
        with open(os.path.join(work, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("# Nguồn LiveContainer của Tàng Công Các\n\n"
                     "Nhánh này do CI (`build-ipa.yml`) tự ghi sau mỗi lần build thành công — đừng sửa tay.\n\n"
                     f"Thêm nguồn vào LiveContainer: `https://raw.githubusercontent.com/{repo}/{SOURCE_BRANCH}/apps.json`\n")
        run(["git", "add", "apps.json", "icon.png", "README.md"], cwd=work, capture=True)
        if run(["git", "diff", "--cached", "--quiet"], cwd=work, check=False).returncode == 0:
            print("Nguồn không đổi, không cần đẩy.")
            return
        run(["git", "-c", "user.name=github-actions[bot]",
             "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
             "commit", "--quiet", "-m", f"source: Tàng Công Các {label}"], cwd=work, capture=True)
        pushed = run(["git", "push", "--quiet", "origin", f"HEAD:{SOURCE_BRANCH}"], cwd=work,
                     check=False, capture=True)
        if pushed.returncode == 0:
            print(f"Đã đẩy apps.json ({len(source['apps'][0]['versions'])} bản) lên nhánh {SOURCE_BRANCH}.")
            return
        print(f"Đẩy nhánh {SOURCE_BRANCH} bị từ chối (lần {attempt}), thử lại.")
        time.sleep(5 * attempt)
    raise RuntimeError(f"Không đẩy được nhánh {SOURCE_BRANCH} sau {attempts} lần.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--notes", default="")
    parser.add_argument("--icon", required=True)
    parser.add_argument("--keep", type=int, default=5)
    args = parser.parse_args()

    repo = os.environ["REPO"]
    token = os.environ["GH_TOKEN"]
    sha = os.environ.get("GITHUB_SHA", "main")

    publish_release(repo, args.ipa, args.version, args.build, args.notes, sha)
    prune_releases(repo, args.keep)
    push_source(repo, token, args.icon, args.keep, f"{args.version} ({args.build})")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 — CI chỉ cần dòng lỗi rõ ràng
        print(f"::error::{error}")
        sys.exit(1)
