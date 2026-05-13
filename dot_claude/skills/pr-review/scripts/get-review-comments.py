#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys


def valid_name(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]+", value))


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch PR review comments.")
    parser.add_argument("owner")
    parser.add_argument("repo")
    parser.add_argument("pr", type=int)
    args = parser.parse_args()

    if not valid_name(args.owner) or not valid_name(args.repo) or args.pr < 1:
        print("invalid owner, repo, or pr", file=sys.stderr)
        return 2

    endpoint = f"repos/{args.owner}/{args.repo}/pulls/{args.pr}/comments?per_page=100"
    proc = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", endpoint],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    pages = json.loads(proc.stdout)
    comments = [comment for page in pages for comment in page]
    result = [
        {
            "id": comment.get("id"),
            "in_reply_to_id": comment.get("in_reply_to_id"),
            "created_at": comment.get("created_at"),
            "path": comment.get("path"),
            "line": comment.get("line"),
            "body": comment.get("body"),
            "user": (comment.get("user") or {}).get("login"),
        }
        for comment in comments
    ]
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
