#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys


THREADS_QUERY = """
query($owner: String!, $repo: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              databaseId
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
"""

RESOLVE_MUTATION = """
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread {
      isResolved
    }
  }
}
"""


def valid_name(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]+", value))


def run_json(args: list[str]) -> dict:
    proc = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE)
    return json.loads(proc.stdout)


def fetch_review_threads(owner: str, repo: str, pr: int) -> list[dict]:
    threads = []
    after = None

    while True:
        command = [
            "gh",
            "api",
            "graphql",
            "-F",
            f"owner={owner}",
            "-F",
            f"repo={repo}",
            "-F",
            f"number={pr}",
            "-f",
            f"query={THREADS_QUERY}",
        ]
        if after:
            command.extend(["-F", f"after={after}"])

        data = run_json(command)
        review_threads = data["data"]["repository"]["pullRequest"]["reviewThreads"]
        threads.extend(review_threads["nodes"])

        page_info = review_threads["pageInfo"]
        if not page_info.get("hasNextPage"):
            return threads
        after = page_info.get("endCursor")


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve PR review threads by root comment id.")
    parser.add_argument("owner")
    parser.add_argument("repo")
    parser.add_argument("pr", type=int)
    parser.add_argument("comment_ids", type=int, nargs="+")
    args = parser.parse_args()

    if not valid_name(args.owner) or not valid_name(args.repo) or args.pr < 1:
        print("invalid owner, repo, or pr", file=sys.stderr)
        return 2
    if any(comment_id < 1 for comment_id in args.comment_ids):
        print("invalid comment id", file=sys.stderr)
        return 2

    threads = fetch_review_threads(args.owner, args.repo, args.pr)
    by_comment_id = {}
    for thread in threads:
        comments = thread.get("comments", {}).get("nodes", [])
        if comments:
            by_comment_id[comments[0].get("databaseId")] = thread

    resolved = []
    missing = []
    for comment_id in args.comment_ids:
        thread = by_comment_id.get(comment_id)
        if not thread:
            missing.append(comment_id)
            continue
        if not thread.get("isResolved"):
            run_json([
                "gh",
                "api",
                "graphql",
                "-F",
                f"threadId={thread['id']}",
                "-f",
                f"query={RESOLVE_MUTATION}",
            ])
        resolved.append(comment_id)

    result = {"resolved": resolved, "missing": missing}
    print(json.dumps(result, ensure_ascii=False))
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
