#!/usr/bin/env python3
"""
Upload split ISO parts to a GitHub repo via the Contents API.

Why the Contents API and not `git push`: a 682MB ISO split into ~20MB
parts is still ~35 individual blobs, and the plain git-over-HTTPS push
path is more failure-prone for that many large binaries in one shot in
CI/build-container environments. The Contents API PUTs one file at a
time and is easy to resume if one part fails.

Usage:
    export GITHUB_TOKEN=ghp_xxx...            # needs 'repo' scope
    python3 upload_iso_parts.py \\
        --repo MGKFN/MorrowOS \\
        --dir morrowos \\
        --parts-glob "morrowos-part-*" \\
        --branch main

Each part must already be <=~20MB (see split command in the README/
build notes: `split -b 20M morrowos-vX.Y.iso morrowos-part-`).
"""
import argparse
import base64
import glob
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"


def gh_request(method, url, token, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def get_existing_sha(repo, path, branch, token):
    status, body = gh_request(
        "GET", f"{API}/repos/{repo}/contents/{path}?ref={branch}", token
    )
    if status == 200:
        return body.get("sha")
    return None


def upload_file(repo, dest_dir, filepath, branch, token, retries=3):
    filename = os.path.basename(filepath)
    dest_path = f"{dest_dir}/{filename}"
    with open(filepath, "rb") as f:
        content_b64 = base64.b64encode(f.read()).decode()

    existing_sha = get_existing_sha(repo, dest_path, branch, token)
    payload = {
        "message": f"Add {filename}",
        "content": content_b64,
        "branch": branch,
    }
    if existing_sha:
        payload["sha"] = existing_sha  # updating an existing part

    for attempt in range(1, retries + 1):
        status, body = gh_request(
            "PUT", f"{API}/repos/{repo}/contents/{dest_path}", token, payload
        )
        if status in (200, 201):
            print(f"  OK  {filename} ({os.path.getsize(filepath)/1e6:.1f} MB)")
            return True
        print(f"  attempt {attempt}/{retries} failed ({status}): "
              f"{body.get('message', body)}")
        time.sleep(2 * attempt)
    print(f"  FAILED: {filename}")
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="owner/repo, e.g. MGKFN/MorrowOS")
    ap.add_argument("--dir", required=True, help="target directory in the repo")
    ap.add_argument("--parts-glob", required=True, help="glob for part files")
    ap.add_argument("--branch", default="main")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        sys.exit("Set GITHUB_TOKEN in the environment first (repo-scoped PAT).")

    parts = sorted(glob.glob(args.parts_glob))
    if not parts:
        sys.exit(f"No files matched glob: {args.parts_glob}")

    print(f"Uploading {len(parts)} parts to {args.repo}:{args.dir} @ {args.branch}")
    failed = []
    for p in parts:
        if not upload_file(args.repo, args.dir, p, args.branch, token):
            failed.append(p)

    if failed:
        print(f"\n{len(failed)} part(s) failed — re-run with the same command, "
              f"already-uploaded parts will just be updated in place:")
        for f in failed:
            print(f"  {f}")
        sys.exit(1)
    print("\nAll parts uploaded.")


if __name__ == "__main__":
    main()
