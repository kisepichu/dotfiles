#!/usr/bin/env python3
"""Wait for a Claude (GitHub Actions) PR review, mirroring wait-copilot-review.py.

Trigger: post an "@claude review" comment (with --request); the claude-review.yml
workflow runs and `claude[bot]` posts inline review comments plus a summary that
contains a sentinel line:
    CLAUDE_REVIEW: no issues found        -> nothing to address
    CLAUDE_REVIEW: <N> issue(s) -- ...    -> inline comments were posted

Completion is detected by polling for a bot-authored marker (in an issue comment
or a formal PR review body) whose effective timestamp is newer than the trigger.

Exit codes match the Copilot waiter so the /pr-review loop is backend-agnostic:
    0  -> review done, no comments to address  (prints JSON, no_comments=true)
    20 -> review done, comments to address     (prints JSON, no_comments=false)
    1  -> timed out
    2  -> bad arguments
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import re
from typing import Any, Dict, List, Optional


def run_json(args: List[str]) -> Any:
    proc = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return json.loads(proc.stdout)


def valid_name(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]+", value))


def is_bot(login: Optional[str], user_type: Optional[str], bot_login: str) -> bool:
    """True only for the exact reviewer bot.

    A loose prefix match would let anyone create a `claude-*` account and post a
    fake `CLAUDE_REVIEW: no issues found` to end the local loop early on a public
    repo, so require an exact login and (when the API gives it) a Bot type. If
    the real app login differs, pass --bot-login rather than loosening this.
    """
    if not login or login != bot_login:
        return False
    return user_type in (None, "Bot")


def issue_comment_markers(owner: str, repo: str, pr: int, bot_login: str, marker: str) -> List[Dict[str, Any]]:
    """Bot-authored issue comments containing the sentinel, with effective ts.

    The action may edit one sticky comment in place across rounds, so the
    effective timestamp is max(created_at, updated_at) -- an edit this round
    pushes it past the trigger even though created_at is from a prior round.
    """
    pages = run_json([
        "gh", "api", "--paginate", "--slurp",
        f"repos/{owner}/{repo}/issues/{pr}/comments?per_page=100",
    ])
    out = []
    for page in pages:
        for c in page:
            user = c.get("user") or {}
            body = c.get("body") or ""
            if is_bot(user.get("login"), user.get("type"), bot_login) and marker in body:
                ts = max(c.get("created_at") or "", c.get("updated_at") or "")
                out.append({"source": "issue_comment", "id": c.get("id"), "ts": ts, "body": body})
    return out


def review_markers(owner: str, repo: str, pr: int, bot_login: str, marker: str) -> List[Dict[str, Any]]:
    """Bot-authored formal PR reviews whose body contains the sentinel."""
    pages = run_json([
        "gh", "api", "--paginate", "--slurp",
        f"repos/{owner}/{repo}/pulls/{pr}/reviews?per_page=100",
    ])
    out = []
    for page in pages:
        for r in page:
            user = r.get("user") or {}
            body = r.get("body") or ""
            if is_bot(user.get("login"), user.get("type"), bot_login) and marker in body:
                out.append({"source": "review", "id": r.get("id"), "ts": r.get("submitted_at") or "", "body": body})
    return out


def latest_marker(owner: str, repo: str, pr: int, bot_login: str, marker: str) -> Optional[Dict[str, Any]]:
    found = issue_comment_markers(owner, repo, pr, bot_login, marker) + review_markers(owner, repo, pr, bot_login, marker)
    if not found:
        return None
    return max(found, key=lambda m: m["ts"])


def head_commit_time(owner: str, repo: str, pr: int) -> str:
    """ISO timestamp of the PR's latest commit, or '' if unknown.

    Used to reject a stale review: an existing marker from before the current
    head (new commits pushed since) must not be reported as a fresh result.
    """
    try:
        pages = run_json([
            "gh", "api", "--paginate", "--slurp",
            f"repos/{owner}/{repo}/pulls/{pr}/commits?per_page=100",
        ])
    except Exception:
        return ""
    commits = [c for page in pages for c in page]
    if not commits:
        return ""
    return (((commits[-1].get("commit") or {}).get("committer") or {}).get("date")) or ""


def post_trigger(owner: str, repo: str, pr: int, body: str) -> str:
    """Post the '@claude review' comment; return its server-side created_at."""
    created = run_json([
        "gh", "api", "-X", "POST",
        f"repos/{owner}/{repo}/issues/{pr}/comments",
        "-f", f"body={body}",
    ])
    return created.get("created_at") or ""


def emit(marker_hit: Dict[str, Any], no_issues_phrase: str) -> int:
    body = marker_hit.get("body") or ""
    no_comments = no_issues_phrase.lower() in body.lower()
    print(json.dumps({
        "source": marker_hit.get("source"),
        "id": marker_hit.get("id"),
        "ts": marker_hit.get("ts"),
        "no_comments": no_comments,
    }, ensure_ascii=False))
    return 0 if no_comments else 20


def main() -> int:
    parser = argparse.ArgumentParser(description="Wait for a Claude PR review.")
    parser.add_argument("owner")
    parser.add_argument("repo")
    parser.add_argument("pr", type=int)
    parser.add_argument("--request", action="store_true", help="post '@claude review' before waiting")
    parser.add_argument("--bot-login", default="claude[bot]", help="review author login to match")
    parser.add_argument("--marker", default="CLAUDE_REVIEW:", help="sentinel substring in the summary")
    parser.add_argument("--no-issues", default="no issues found", help="phrase meaning nothing to address")
    parser.add_argument("--trigger-body", default="@claude review")
    parser.add_argument("--attempts", type=int, default=90)
    parser.add_argument("--interval", type=int, default=10)
    args = parser.parse_args()

    if not valid_name(args.owner) or not valid_name(args.repo):
        print("invalid owner or repo", file=sys.stderr)
        return 2
    if args.pr < 1:
        print("invalid pr number", file=sys.stderr)
        return 2

    before = latest_marker(args.owner, args.repo, args.pr, args.bot_login, args.marker)
    before_ts = before["ts"] if before else ""

    # No new request: report an already-present completed review (like the
    # Copilot waiter), but ONLY if it provably covers the current head. Accept
    # it solely when the head commit time is known AND the marker is at least as
    # new. Any uncertainty (head time unknown, or marker older) fails safe to
    # triggering a fresh review rather than trusting a possibly-stale result.
    need_trigger = args.request or not before
    if before and not args.request:
        head_ts = head_commit_time(args.owner, args.repo, args.pr)
        if head_ts and before_ts >= head_ts:
            return emit(before, args.no_issues)
        need_trigger = True

    # Trigger a (re-)review by posting the @claude comment. Use the comment's
    # server timestamp as the baseline so clock skew can't hide the result.
    baseline = before_ts
    if need_trigger:
        baseline = post_trigger(args.owner, args.repo, args.pr, args.trigger_body) or before_ts

    for _ in range(args.attempts):
        latest = latest_marker(args.owner, args.repo, args.pr, args.bot_login, args.marker)
        if latest and latest["ts"] > baseline:
            return emit(latest, args.no_issues)
        time.sleep(args.interval)

    print("Timed out waiting for Claude review.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
