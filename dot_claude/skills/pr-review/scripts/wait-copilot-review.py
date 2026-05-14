#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional


COPILOT_LOGIN = "copilot-pull-request-reviewer"
NO_COMMENTS_RE = re.compile(r"generated no( new)? comments", re.IGNORECASE)


def run_json(args: List[str]) -> Dict[str, Any]:
    proc = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return json.loads(proc.stdout)


def run(args: List[str]) -> None:
    subprocess.run(args, check=True)


def latest_copilot_review(owner: str, repo: str, pr: int) -> Optional[Dict[str, Any]]:
    data = run_json([
        "gh",
        "pr",
        "view",
        str(pr),
        "-R",
        f"{owner}/{repo}",
        "--json",
        "reviews",
    ])
    reviews = [
        review
        for review in data.get("reviews", [])
        if review.get("author", {}).get("login") == COPILOT_LOGIN
        and review.get("state") == "COMMENTED"
    ]
    if not reviews:
        return None
    return max(reviews, key=lambda review: review.get("submittedAt", ""))


def main() -> int:
    parser = argparse.ArgumentParser(description="Wait for Copilot PR review.")
    parser.add_argument("owner")
    parser.add_argument("repo")
    parser.add_argument("pr", type=int)
    parser.add_argument("--request", action="store_true", help="request or re-request Copilot review before waiting")
    parser.add_argument("--attempts", type=int, default=90)
    parser.add_argument("--interval", type=int, default=10)
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.owner):
        print("invalid owner", file=sys.stderr)
        return 2
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.repo):
        print("invalid repo", file=sys.stderr)
        return 2
    if args.pr < 1:
        print("invalid pr number", file=sys.stderr)
        return 2

    before = latest_copilot_review(args.owner, args.repo, args.pr)
    before_submitted_at = before.get("submittedAt", "") if before else ""

    if before and not args.request:
        body = before.get("body") or ""
        result = {
            "submittedAt": before.get("submittedAt", ""),
            "id": before.get("id", ""),
            "no_comments": bool(NO_COMMENTS_RE.search(body)),
        }
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result["no_comments"] else 20

    if args.request or not before:
        run([
            "gh",
            "pr",
            "edit",
            str(args.pr),
            "-R",
            f"{args.owner}/{args.repo}",
            "--add-reviewer",
            "@copilot",
        ])

    for _ in range(args.attempts):
        review = latest_copilot_review(args.owner, args.repo, args.pr)
        if review and review.get("submittedAt", "") > before_submitted_at:
            body = review.get("body") or ""
            result = {
                "submittedAt": review.get("submittedAt", ""),
                "id": review.get("id", ""),
                "no_comments": bool(NO_COMMENTS_RE.search(body)),
            }
            print(json.dumps(result, ensure_ascii=False))
            return 0 if result["no_comments"] else 20
        time.sleep(args.interval)

    print("Timed out waiting for Copilot review.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
