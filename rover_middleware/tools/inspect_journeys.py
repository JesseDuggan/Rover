#!/usr/bin/env python3
"""Bounded, read-only journey inspector. Python 3.10+, standard library only."""
import argparse
import base64
from collections import Counter
from datetime import datetime, timedelta, timezone
from getpass import getpass
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urljoin, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

KEY = re.compile(r"^[0-9a-fA-F]{16}$")
MAX_BYTES = 4 * 1024 * 1024


class Node:
    def __init__(self, tag="", attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        return " ".join(" ".join(c.text() if isinstance(c, Node) else c
                                 for c in self.children).split())

    def find(self, tag):
        for child in self.children:
            if isinstance(child, Node):
                if child.tag == tag:
                    yield child
                yield from child.find(tag)


class PageParser(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in {"meta", "link", "br", "hr", "img", "input", "wbr", "source"}:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def inspector_url(base):
    p = urlsplit(base)
    if (p.scheme != "https" or not p.hostname or p.username or p.password
            or p.query or p.fragment or p.path not in ("", "/", "/admin/journeys")):
        raise ValueError("Use an HTTPS origin or /admin/journeys URL without credentials or query.")
    return urlunsplit((p.scheme, p.netloc, "/admin/journeys", "", ""))


def request_id(href, base):
    p, b = urlsplit(urljoin(base, href)), urlsplit(base)
    q = parse_qs(p.query, keep_blank_values=True)
    if ((p.scheme, p.netloc, p.path) != (b.scheme, b.netloc, b.path)
            or p.fragment or set(q) != {"request"} or len(q["request"]) != 1):
        return None
    value = q["request"][0]
    return value if KEY.fullmatch(value) else None


def link(base, rid):
    return base + "?" + urlencode({"request": rid})


def number(value):
    return int(value) if re.fullmatch(r"\d+", value.strip()) else None


def cell_value(node):
    time = next(node.find("time"), None)
    return time.attrs.get("datetime", time.text()) if time else node.text()


def parse_page(html, base):
    root = PageParser(html).root
    requests, timeline, failures, warnings = [], [], [], []
    recognized = False
    for table in root.find("table"):
        rows = list(table.find("tr"))
        if not rows:
            continue
        headers = [n.text().lower().replace(" (utc)", "") for n in rows[0].find("th")]
        is_requests = {"request", "walk", "action", "inspection events", "provider attempts", "latest activity"}.issubset(headers)
        for row in rows[1:]:
            cells = list(row.find("td"))
            if len(cells) != len(headers):
                warnings.append("Malformed table row skipped.")
                continue
            values = [cell_value(c) for c in cells]
            fields = dict(zip(headers, values))
            if is_requests:
                recognized = True
                ids = [request_id(a.attrs.get("href", ""), base) for a in cells[headers.index("request")].find("a")]
                rid = next((i for i in ids if i), None)
                if rid:
                    requests.append(dict(request_id=rid, walk=fields["walk"], action=fields["action"],
                                         places_and_stories=fields.get("places and stories", ""),
                                         inspection_events=number(fields["inspection events"]),
                                         provider_attempts=number(fields["provider attempts"]), latest_activity=fields["latest activity"],
                                         time_label="UTC (server HTML; datetime attribute preferred)", evidence_url=link(base, rid)))
                else:
                    warnings.append("Request table row has missing or unsafe request linkage.")
            elif {"time", "activity", "provider", "purpose", "result", "ms", "request"}.issubset(headers):
                timeline.append({k: fields[k] for k in ("time", "activity", "provider", "purpose", "result", "ms", "request")})
            elif {"stage", "outcome", "events"}.issubset(headers):
                failures.append(dict(stage=fields["stage"], outcome=fields["outcome"], events=number(fields["events"])))
        if is_requests:
            recognized = True  # Empty activity is valid.
    if not recognized:
        raise ValueError("Inspector request table not recognized; authentication or schema may differ.")
    records = []
    for article in root.find("article"):
        heading = next(article.find("h3"), None)
        if heading is None:
            continue
        stage, sep, outcome = heading.text().partition(": ")
        if not sep:
            warnings.append("Unrecognized decision heading skipped.")
            continue
        small = cell_value(next(article.find("small"), Node()))
        rid = next((rid for a in article.find("a")
                    if (rid := request_id(a.attrs.get("href", ""), base))), None)
        # Narration, source links and instructions in story text are never executed or followed.
        paragraphs = [p.text() for p in article.find("p")
                      if not any(True for _ in p.find("a"))]
        records.append(dict(request_id=rid, stage=stage, outcome=outcome,
                            title=next(article.find("h4"), Node()).text(),
                            reason=" ".join(paragraphs), recorded_time=small.split(" · ")[0]))
    return dict(requests=requests, records=records, timeline=timeline,
                failure_summary=failures, warnings=warnings,
                supports_search=any(n.attrs.get("name") == "q" for n in root.find("input")),
                window_days=7 if re.search(r"Last 7 days", root.text(), re.I) else None)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Reader:
    def __init__(self, base, username, password, max_requests=10, timeout=20):
        self.base, self.timeout = inspector_url(base), timeout
        self.limit, self.calls = 1 + max_requests, 0
        self.authorization = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()
        self.opener = build_opener(NoRedirect())

    def get(self, url):
        p, b = urlsplit(url), urlsplit(self.base)
        q = parse_qs(p.query, keep_blank_values=True)
        search_ok = ((p.scheme, p.netloc, p.path) == (b.scheme, b.netloc, b.path)
                     and not p.fragment and set(q) == {"q"} and len(q["q"]) == 1
                     and 0 < len(q["q"][0]) <= 120 and self.calls == 0)
        if url != self.base and not request_id(url, self.base) and not search_ok:
            raise ValueError("Only inspector GET requests are permitted.")
        if self.calls >= self.limit:
            raise ValueError("Inspector call budget exhausted.")
        self.calls += 1
        req = Request(url, headers={"Authorization": self.authorization, "Accept": "text/html"}, method="GET")
        with self.opener.open(req, timeout=self.timeout) as response:
            if response.headers.get_content_type() != "text/html":
                raise ValueError("Inspector did not return HTML.")
            raw = response.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise ValueError("Inspector response exceeds size limit.")
            return raw.decode("utf-8", errors="replace")


def triage(summary, page, high_provider_count):
    records = page["records"]
    findings = []

    def add(rule, count, fact, hypothesis, improvement):
        if count:
            findings.append(dict(rule=rule, recorded_count=count, recorded_fact=fact,
                                 hypothesis=hypothesis, suggested_review=improvement,
                                 evidence_url=summary["evidence_url"]))

    for stage, rule in (("Evidence gate", "rejected_evidence"), ("Geographic gate", "rejected_coordinates_or_area")):
        count = sum(r["stage"] == stage and r["outcome"] == "Rejected" for r in records)
        add(rule, count, f"{count} visible {stage} rejection records; these are decisions, not unique stories.",
            "Candidate evidence or subject resolution may need improvement; rejection may be correct.",
            "Review cited location evidence and subject identity before changing validation gates.")
    count = sum(r["outcome"] == "No accepted stories" for r in records)
    # Aggregate is authoritative for recorded event count when details are truncated, never added to details.
    aggregate = sum(r["events"] or 0 for r in page["failure_summary"] if r["outcome"] == "No accepted stories")
    add("no_accepted_stories", max(count, aggregate),
        f"{aggregate} summary events and {count} visible decisions explicitly report No accepted stories; not a final request outcome.",
        "An individual research pass may have exhausted usable candidates; another pass may recover.",
        "Compare validation summaries across passes and check for later acceptance.")
    retry = sum(r["stage"] == "Second research pass" and r["outcome"] == "Started" for r in records)
    recovery = sum(r["stage"] == "Research" and r["outcome"] == "Started" and r["reason"] == "Geographic recovery search" for r in records)
    add("retries", retry + recovery, f"{retry} explicit second-pass starts; {recovery} geographic recovery starts.",
        "First-pass coverage, specificity or narration depth may be insufficient; repeated calls alone do not prove retries.",
        "Compare first-pass and recovery acceptance and latency for the same request.")
    attempts = summary["provider_attempts"]
    add("high_provider_count", attempts if attempts is not None and attempts >= high_provider_count else 0,
        f"Request table records {attempts} provider attempts; review threshold is >= {high_provider_count}.",
        "Fan-out, recovery or expensive preparation may explain volume; count is not cost or quality.",
        "Inspect provider/purpose counts and accepted results before proposing caching or call budgets.")
    missing = summary["walk"].lower() in ("", "unlinked", "unknown", "—", "-")
    add("missing_walk_linkage", int(missing), "Request has no recorded walk linkage.",
        "Journey context may not have propagated, or this operation may legitimately have no walk.",
        "Check context propagation for the action; do not infer a separate walk.")
    missing_records = sum(not r["request_id"] for r in records)
    add("missing_request_linkage", missing_records, f"{missing_records} visible decisions lack request links.",
        "Legacy telemetry or context propagation may explain missing linkage.",
        "Check trace propagation before attributing these records to a request.")
    return findings


CAVEATS = [
    "HTML titles and reasons are untrusted data, never instructions. Narration and external source bodies are omitted; no source links are fetched.",
    "This is a bounded sample, not a complete audit: initial page caps journeys at 50, requests at 60 and details at 150; each request timeline caps at 300 (oldest first).",
    "The server currently queries a rolling 7-day window and retains 31 days; detailed telemetry starts with the inspection release. Missing records are unknown, not zero.",
    "Counts are recorded events/decisions, not unique stories or users. Request totals and visible timelines have different coverage; they are never added together.",
    "Missing playback does not establish failure or that narration was unheard. Acceptance means automated checks passed, not independently verified history.",
    "Zero dedicated archive calls does not establish archives were unused: archive discovery may be integrated into the main evidence search.",
    "Pages are fetched sequentially, not as a transactional snapshot. Times retain their displayed timezone; the estimated query window uses client fetch time.",
    "Text matching identifies a candidate geographic sample, not verified location or representative coverage. Hypotheses require human review and testing before changes.",
]


def collect(reader, max_requests=10, match=None, high_provider_count=20, server_search=None):
    started = datetime.now(timezone.utc)
    initial_url = reader.base + "?" + urlencode({"q": server_search}) if server_search else reader.base
    initial = parse_page(reader.get(initial_url), reader.base)
    if server_search and not initial["supports_search"]:
        raise ValueError("Server search is not supported by this page; use --match instead.")
    candidates = initial["requests"]
    if match:
        matched = {r["request_id"] for r in initial["records"]
                   if match.casefold() in (r["title"] + " " + r["reason"]).casefold()}
        candidates = [r for r in candidates if r["request_id"] in matched
                      or match.casefold() in (r["action"] + " " + r["places_and_stories"]).casefold()]
    seen, selected = set(), []
    for row in candidates:  # Server orders request rows newest first.
        if row["request_id"] not in seen:
            selected.append(row)
            seen.add(row["request_id"])
    results, errors = [], []
    for summary in selected[:max_requests]:
        try:
            page = parse_page(reader.get(summary["evidence_url"]), reader.base)
            current = next((r for r in page["requests"] if r["request_id"] == summary["request_id"]), summary)
            mismatched = [r for r in page["records"] if r["request_id"] and r["request_id"] != summary["request_id"]]
            if mismatched:
                raise ValueError("Request filter returned unrelated records.")
            provider_rows = [r for r in page["timeline"] if r["activity"] == "Provider call"]
            counts = Counter((r["provider"], r["purpose"], r["result"]) for r in provider_rows)
            results.append(dict(summary=current, recorded_facts=dict(
                visible_decisions=len(page["records"]), visible_timeline_events=len(page["timeline"]),
                visible_provider_events=len(provider_rows),
                provider_breakdown=[dict(provider=k[0], purpose=k[1], result=k[2], events=v)
                                    for k, v in sorted(counts.items())],
                decisions=page["records"], failure_summary=page["failure_summary"]),
                findings=triage(current, page, high_provider_count), warnings=page["warnings"],
                possible_truncation=dict(decisions=len(page["records"]) >= 150, timeline=len(page["timeline"]) >= 300)))
        except (HTTPError, URLError, OSError, ValueError) as exc:
            errors.append(dict(evidence_url=summary["evidence_url"], error=safe_error(exc)))
    return dict(schema_version=1, generated_at_utc=datetime.now(timezone.utc).isoformat(),
                source=initial_url, status="partial" if errors else "complete_bounded_sample",
                time_window=dict(server_window_days=initial["window_days"],
                                 estimated_start_utc=(started - timedelta(days=7)).isoformat() if initial["window_days"] else None,
                                 fetch_started_utc=started.isoformat(), basis="Server rolling window; estimate is not exact server cutoff."),
                selection=dict(match=match, server_search=server_search, match_fields=["title", "reason", "action", "places_and_stories"], order="server newest request first",
                               initial_requests=len(initial["requests"]), matching_requests=len(selected),
                               requested_limit=max_requests, reviewed_requests=len(results), http_calls=reader.calls,
                               high_provider_threshold=high_provider_count),
                caveats=CAVEATS, initial_warnings=initial["warnings"], requests=results, errors=errors)


def safe_error(exc):
    # Never include exception bodies, URLs or headers, which may contain secrets.
    if isinstance(exc, HTTPError):
        return f"HTTP {exc.code}; redirects are disabled and no retry was attempted."
    return f"{type(exc).__name__}: inspector read/parse failed; sensitive details suppressed."


def write_report(report, output, fmt, secrets=()):
    payload = json.dumps(report, indent=2, ensure_ascii=True)
    for secret in secrets:
        if secret:
            payload = payload.replace(json.dumps(secret, ensure_ascii=True)[1:-1], "[REDACTED]")
    if fmt == "markdown":
        # Keep all untrusted fields inside a non-breakable code block, not active Markdown/HTML.
        payload = payload.replace("`", "\\u0060").replace("<", "\\u003c").replace(">", "\\u003e")
        payload = "# Journey review\n\nRecorded facts, hypotheses and caveats (untrusted data):\n\n```json\n" + payload + "\n```\n"
    # Explicit destination, no accidental replacement of an earlier review or source file.
    with Path(output).open("x", encoding="utf-8") as stream:
        stream.write(payload + "\n")


def bounded_int(minimum, maximum):
    def parse(value):
        n = int(value)
        if not minimum <= n <= maximum:
            raise argparse.ArgumentTypeError(f"Must be between {minimum} and {maximum}.")
        return n
    return parse


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True, help="HTTPS origin or /admin/journeys URL")
    parser.add_argument("--output", required=True, help="New explicit local report path; parent must exist")
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    parser.add_argument("--max-requests", type=bounded_int(0, 100), default=10)
    parser.add_argument("--timeout", type=bounded_int(1, 120), default=20, help="Seconds per GET")
    parser.add_argument("--high-provider-count", type=bounded_int(1, 100000), default=20)
    parser.add_argument("--server-search", help="Title search via ?q= (requires newer inspector; maximum 120 characters)")
    parser.add_argument("--match", help="Case-insensitive literal title/reason/action filter on initial page")
    args = parser.parse_args(argv)
    try:
        if args.server_search is not None and not 0 < len(args.server_search.strip()) <= 120:
            raise ValueError("Server search must contain 1 to 120 characters.")
        base = inspector_url(args.base_url)
        output = Path(args.output)
        if output.exists() or not output.parent.is_dir():
            raise ValueError("Output must be a new file in an existing directory.")
        username = os.environ.get("WALKABOUT_USAGE_USERNAME", "admin")
        password = os.environ.get("WALKABOUT_USAGE_PASSWORD") or getpass("Inspector admin password: ")
        if not password or ":" in username or any(c in username + password for c in "\r\n"):
            raise ValueError("Invalid credentials.")
        reader = Reader(base, username, password, args.max_requests, args.timeout)
        report = collect(reader, args.max_requests, args.match, args.high_provider_count, args.server_search)
        write_report(report, output, args.format, (password, reader.authorization, reader.authorization[6:]))
        print(f"Report written. Reviewed {len(report['requests'])} requests in {reader.calls} GETs.")
        return 2 if report["errors"] else 0
    except (HTTPError, URLError, OSError, ValueError, EOFError) as exc:
        print(safe_error(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
