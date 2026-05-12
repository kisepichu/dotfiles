#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys


def valid_name(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]+", value))


def valid_body_file(path: str) -> bool:
    normalized = os.path.abspath(path)
    return normalized.startswith("/tmp/") and normalized.endswith(".md") and os.path.isfile(normalized)


def main() -> int:
    parser = argparse.ArgumentParser(description="Reply to a PR review comment.")
    parser.add_argument("owner")
    parser.add_argument("repo")
    parser.add_argument("pr", type=int)
    parser.add_argument("comment_id", type=int)
    parser.add_argument("body_file")
    args = parser.parse_args()

    if not valid_name(args.owner) or not valid_name(args.repo) or args.pr < 1 or args.comment_id < 1:
        print("invalid owner, repo, pr, or comment id", file=sys.stderr)
        return 2
    if not valid_body_file(args.body_file):
        print("body file must be an existing /tmp/*.md file", file=sys.stderr)
        return 2

    endpoint = f"repos/{args.owner}/{args.repo}/pulls/{args.pr}/comments/{args.comment_id}/replies"
    proc = subprocess.run(
        [
            "gh",
            "api",
            "-X",
            "POST",
            endpoint,
            "-F",
            f"body=@{os.path.abspath(args.body_file)}",
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    reply = json.loads(proc.stdout)
    print(reply.get("id", ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
