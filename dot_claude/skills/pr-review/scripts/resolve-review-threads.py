#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys


THREADS_QUERY = """
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              databaseId
            }
          }
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

    data = run_json([
        "gh",
        "api",
        "graphql",
        "-F",
        f"owner={args.owner}",
        "-F",
        f"repo={args.repo}",
        "-F",
        f"number={args.pr}",
        "-f",
        f"query={THREADS_QUERY}",
    ])

    threads = data["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
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
