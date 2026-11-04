#!/usr/bin/env python3
"""A loopback stand-in for Witty's update feed, to see exactly what a check sends.

Serves the feed on loopback only, shaped like GitHub's: a check asks for
http://127.0.0.1:<port>/latest/download/appcast.xml, which answers with a 302 to
/download/appcast.xml, as github.com's /releases/latest/download/ does. Every
response sets a cookie naming its check, as github.com's do, so the probe sees
both a cookie kept from an earlier check and one a check's second request sends
back from its first. Prints each request; after --checks checks, exits 0 if every
request was a GET with no query string, no body and no cookie other than one set
earlier in the same check, and 1 otherwise. A cookie sent back within one check
is reported, not failed.

Use it with a build whose feed is this server (UpdateController accepts plain http
only for loopback), then choose Witty → Check for Updates… twice:

    python3 macos/scripts/update_probe.py --port 8765
    zig build -Demit-macos-app \\
      -Dmacos-update-feed-url=http://127.0.0.1:8765/latest/download/appcast.xml \\
      -Dmacos-update-public-ed-key=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=

The key can be any well-formed EdDSA public key (base64 of 32 bytes); Sparkle
refuses to start with any other. macos/build.nu cannot set either value: it runs
xcodebuild with a clean environment.

Without --appcast it serves an empty, unsigned feed, which the app rejects with an
update error after the request was made; that does not affect what was sent.

    python3 macos/scripts/update_probe.py --self-test   # the probe's own test
"""

from __future__ import annotations

import argparse
import contextlib
import http.cookiejar
import http.server
import io
import re
import sys
import threading
import urllib.request

FIRST_HOP = "/latest/download/appcast.xml"
SECOND_HOP = "/download/appcast.xml"
COOKIE = "witty_probe"
COOKIE_VALUE_RE = re.compile(r"check(\d+)-request(\d+)")

EMPTY_FEED = (b'<?xml version="1.0" encoding="utf-8"?>\n'
              b'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">'
              b"<channel><title>Witty</title></channel></rss>\n")


def sent_cookies(headers: list[tuple[str, str]]) -> list[tuple[str, str]]:
    found = []
    for name, value in headers:
        if name.lower() != "cookie":
            continue
        for pair in value.split(";"):
            cookie_name, _, cookie_value = pair.strip().partition("=")
            found.append((cookie_name, cookie_value))
    return found


class Probe:
    def __init__(self, body: bytes):
        self.body = body
        self.requests: list[dict] = []
        self.checks = 0
        self.finished = 0
        self.lock = threading.Lock()
        self.done = threading.Event()
        self.wanted = 0

    def problems(self) -> list[str]:
        found = []
        for n, r in enumerate(self.requests, 1):
            if r["method"] != "GET":
                found.append(f"request {n} is a {r['method']}, not a GET")
            if "?" in r["path"]:
                found.append(f"request {n} has a query string: {r['path']}")
            if r["body"]:
                found.append(f"request {n} has a {len(r['body'])}-byte body")
            for name, value in sent_cookies(r["headers"]):
                m = COOKIE_VALUE_RE.fullmatch(value) if name == COOKIE else None
                if not m:
                    found.append(f"request {n} sent a cookie the probe never set: {name}={value}")
                elif int(m[1]) < r["check"]:
                    found.append(f"request {n} (check {r['check']}) sent the cookie set by check {m[1]}: {name}={value}")
        return found

    def notes(self) -> list[str]:
        found = []
        for n, r in enumerate(self.requests, 1):
            for name, value in sent_cookies(r["headers"]):
                m = COOKIE_VALUE_RE.fullmatch(value) if name == COOKIE else None
                if m and int(m[1]) == r["check"]:
                    found.append(f"request {n} (check {r['check']}) sent back the cookie request {m[2]}"
                                 f" of the same check set: {name}={value}")
        return found


def handler_for(probe: Probe) -> type[http.server.BaseHTTPRequestHandler]:
    class Handler(http.server.BaseHTTPRequestHandler):
        def handle_any(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            path = self.path.split("?")[0]
            with probe.lock:
                if path == FIRST_HOP:
                    probe.checks += 1
                check = probe.checks
                probe.requests.append({
                    "method": self.command,
                    "path": self.path,
                    "check": check,
                    "headers": list(self.headers.items()),
                    "body": self.rfile.read(length) if length else b"",
                })
                n = len(probe.requests)
            print(f"--- request {n} (check {check}): {self.command} {self.path}")
            for name, value in self.headers.items():
                print(f"    {name}: {value}")
            body = b""
            if path == FIRST_HOP:
                self.send_response(302)
                self.send_header("Location", f"http://127.0.0.1:{self.server.server_address[1]}{SECOND_HOP}")
            elif path == SECOND_HOP:
                self.send_response(200)
                self.send_header("Content-Type", "application/xml")
                body = probe.body
            else:
                self.send_response(404)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Set-Cookie", f"{COOKIE}=check{check}-request{n}; Max-Age=31536000; Path=/")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            if path == SECOND_HOP:
                with probe.lock:
                    probe.finished += 1
                    if probe.wanted and probe.finished >= probe.wanted:
                        probe.done.set()

        do_GET = do_HEAD = do_POST = do_PUT = handle_any

        def log_message(self, *args) -> None:
            pass

    return Handler


def serve(probe: Probe, port: int) -> http.server.ThreadingHTTPServer:
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler_for(probe))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def self_test() -> int:
    """Each thing the probe fails on must be caught, and clients that do none of
    them must pass, with a cookie sent back within one check reported. Otherwise a
    clean capture would prove nothing."""
    # name, cookies kept ("none", "per check", "across checks"), method, query, body,
    # extra headers, expect clean, expect a within-check note
    cases = [
        ("a client that keeps cookies from one check to the next", "across checks", "GET", "", None, {}, False, True),
        # urllib follows the 302 with a GET, so only each check's first request is a POST.
        ("a client that sends a POST", "none", "POST", "", None, {}, False, False),
        ("a client that adds a query string", "none", "GET", "?id=1", None, {}, False, False),
        ("a client that sends a body", "none", "GET", "", b"id=1", {}, False, False),
        ("a client that sends a cookie of its own", "none", "GET", "", None, {"Cookie": "id=1"}, False, False),
        ("a client that keeps cookies only within a check", "per check", "GET", "", None, {}, True, True),
        ("a client that sends no cookie", "none", "GET", "", None, {}, True, False),
    ]
    failed = 0
    for name, cookies, method, query, body, headers, expect_clean, expect_note in cases:
        probe = Probe(EMPTY_FEED)
        server = serve(probe, 0)
        url = f"http://127.0.0.1:{server.server_address[1]}{FIRST_HOP}{query}"
        jar = http.cookiejar.CookieJar()
        with contextlib.redirect_stdout(io.StringIO()):
            for _ in range(2):
                if cookies == "per check":
                    jar = http.cookiejar.CookieJar()
                handlers = [urllib.request.HTTPCookieProcessor(jar)] if cookies != "none" else []
                opener = urllib.request.build_opener(*handlers)
                request = urllib.request.Request(url, data=body, headers=headers, method=method)
                opener.open(request, timeout=5).read()
        server.shutdown()
        clean, noted = not probe.problems(), bool(probe.notes())
        ok = clean == expect_clean and noted == expect_note and probe.checks == 2 and len(probe.requests) == 4
        print(f"{'ok  ' if ok else 'FAIL'} - {name} {'passes' if expect_clean else 'is caught'}"
              f"{', with a note' if expect_note else ''}"
              f"{'' if ok else f' (problems: {probe.problems()}; notes: {probe.notes()}; {len(probe.requests)} requests)'}")
        failed |= not ok
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--appcast", type=argparse.FileType("rb"), help="feed to serve (default: an empty one)")
    parser.add_argument("--checks", type=int, default=2, help="checks to wait for (default: 2)")
    parser.add_argument("--timeout", type=float, default=600, help="seconds to wait (default: 600)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    probe = Probe(args.appcast.read() if args.appcast else EMPTY_FEED)
    probe.wanted = args.checks
    server = serve(probe, args.port)
    print(f"Feed: http://127.0.0.1:{args.port}{FIRST_HOP}; waiting for {args.checks} checks…")
    finished = probe.done.wait(args.timeout)
    server.shutdown()
    if not finished:
        print(f"error: only {probe.finished} of {args.checks} checks within {args.timeout:.0f} s", file=sys.stderr)
        return 1
    problems = probe.problems()
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    for note in probe.notes():
        print(f"note: {note}")
    if not problems:
        print(f"OK: {probe.finished} checks in {len(probe.requests)} requests, each a GET with no query or body,"
              " and none with a cookie from an earlier check")
        if not probe.notes():
            print("No request sent a cookie at all.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
