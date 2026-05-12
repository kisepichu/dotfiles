#!/usr/bin/env python3
import json
import re
import shlex
import sys


CONTROL_TOKENS = {"|", "|&", "&&", "||", ";", "&"}


def block(reason: str) -> None:
    print(f"Blocked gh api command: {reason}", file=sys.stderr)
    sys.exit(2)


def tokenize(command: str) -> list[str]:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        return list(lexer)
    except ValueError as exc:
        block(f"could not parse shell command: {exc}")


def parse_gh_api(tokens: list[str]) -> dict:
    if len(tokens) < 3 or tokens[0:2] != ["gh", "api"]:
        sys.exit(0)

    if any(token in CONTROL_TOKENS for token in tokens):
        block("compound commands are not allowed for gh api")

    args = tokens[2:]
    method = None
    endpoint = None
    fields: list[tuple[str, str]] = []
    jq_filters: list[str] = []
    unknown_flags: list[str] = []
    extras: list[str] = []

    i = 0
    while i < len(args):
        arg = args[i]

        if arg in {"-X", "--method"}:
            if i + 1 >= len(args):
                block(f"{arg} requires a value")
            method = args[i + 1].upper()
            i += 2
            continue

        if arg.startswith("--method="):
            method = arg.split("=", 1)[1].upper()
            i += 1
            continue

        if arg in {"-f", "--raw-field", "-F", "--field"}:
            if i + 1 >= len(args):
                block(f"{arg} requires a value")
            fields.append((arg, args[i + 1]))
            i += 2
            continue

        if arg in {"-q", "--jq"}:
            if i + 1 >= len(args):
                block(f"{arg} requires a value")
            jq_filters.append(args[i + 1])
            i += 2
            continue

        if arg.startswith("--jq="):
            jq_filters.append(arg.split("=", 1)[1])
            i += 1
            continue

        if arg.startswith("-"):
            unknown_flags.append(arg)
            i += 1
            continue

        if endpoint is None:
            endpoint = arg
        else:
            extras.append(arg)
        i += 1

    if endpoint is None:
        block("missing endpoint")

    return {
        "method": method,
        "endpoint": endpoint,
        "fields": fields,
        "jq_filters": jq_filters,
        "unknown_flags": unknown_flags,
        "extras": extras,
    }


def require_no_unknown(parsed: dict) -> None:
    if parsed["unknown_flags"]:
        block("unknown flags are not allowed: " + " ".join(parsed["unknown_flags"]))
    if parsed["extras"]:
        block("extra positional arguments are not allowed: " + " ".join(parsed["extras"]))


def field_key(field: str) -> str:
    return field.split("=", 1)[0]


def field_value(field: str) -> str:
    return field.split("=", 1)[1] if "=" in field else ""


def is_review_comments_get(parsed: dict) -> bool:
    endpoint = parsed["endpoint"]
    return bool(
        re.fullmatch(r"repos/[^/\s]+/[^/\s]+/pulls/[0-9]+/comments(?:\?per_page=[0-9]+)?", endpoint)
        and parsed["method"] in {None, "GET"}
        and not parsed["fields"]
    )


def is_review_comment_reply(parsed: dict) -> bool:
    endpoint = parsed["endpoint"]
    if not re.fullmatch(r"repos/[^/\s]+/[^/\s]+/pulls/[0-9]+/comments/[0-9]+/replies", endpoint):
        return False
    if parsed["method"] != "POST":
        return False

    fields = parsed["fields"]
    if len(fields) != 1:
        return False

    flag, value = fields[0]
    if field_key(value) != "body":
        return False

    if flag in {"-f", "--raw-field"}:
        return "=" in value

    if flag in {"-F", "--field"}:
        body = field_value(value)
        return body.startswith("@/tmp/pr-review-reply") and body.endswith(".md")

    return False


def graphql_query(parsed: dict) -> str:
    query_fields = [field_value(value) for _flag, value in parsed["fields"] if field_key(value) == "query"]
    if len(query_fields) != 1:
        block("graphql command must include exactly one query field")
    return query_fields[0]


def is_graphql_review_threads(parsed: dict) -> bool:
    if parsed["endpoint"] != "graphql":
        return False
    if parsed["method"] not in {None, "POST"}:
        return False

    allowed_keys = {"query", "owner", "repo", "name", "num", "number"}
    keys = {field_key(value) for _flag, value in parsed["fields"]}
    if not keys <= allowed_keys:
        block("graphql reviewThreads query contains unexpected fields: " + ", ".join(sorted(keys - allowed_keys)))

    query = graphql_query(parsed)
    if re.search(r"\bmutation\b", query, re.IGNORECASE):
        return False

    return all(term in query for term in ("repository", "pullRequest", "reviewThreads"))


def is_graphql_resolve_review_thread(parsed: dict) -> bool:
    if parsed["endpoint"] != "graphql":
        return False
    if parsed["method"] not in {None, "POST"}:
        return False

    allowed_keys = {"query", "thread_id", "threadId"}
    keys = {field_key(value) for _flag, value in parsed["fields"]}
    if not keys <= allowed_keys:
        block("resolveReviewThread mutation contains unexpected fields: " + ", ".join(sorted(keys - allowed_keys)))

    query = graphql_query(parsed)
    normalized = re.sub(r"\s+", " ", query)
    if not re.search(r"\bmutation\b", normalized, re.IGNORECASE):
        return False
    if "resolveReviewThread" not in normalized:
        return False

    forbidden = [
        "addComment",
        "addPullRequestReview",
        "closePullRequest",
        "createPullRequest",
        "delete",
        "dismissPullRequestReview",
        "mergePullRequest",
        "reopenPullRequest",
        "requestReviews",
        "submitPullRequestReview",
        "update",
    ]
    lowered = normalized.lower()
    if any(term.lower() in lowered for term in forbidden):
        block("only resolveReviewThread mutation is allowed")

    return True


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
        tokens = tokenize(command)
        parsed = parse_gh_api(tokens)
        require_no_unknown(parsed)

        if (
            is_review_comments_get(parsed)
            or is_review_comment_reply(parsed)
            or is_graphql_review_threads(parsed)
            or is_graphql_resolve_review_thread(parsed)
        ):
            return 0

        block(parsed["endpoint"] + " is not allowed for /pr-review")
    except SystemExit:
        raise
    except Exception as exc:
        block(f"validator error: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
