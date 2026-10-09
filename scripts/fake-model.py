#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# A local stand-in for a Chat Completions endpoint, so that tests and the Dev app can run
# without a real model and without spending tokens. It listens on 127.0.0.1 only.
#
# /v1/chat/completions answers like a model, from Fixtures/MockModel/replies.json:
#   - with a `json_schema` response format named "proofread", the edit list of the table
#     entry whose text occurs in the last user message, else no edits;
#   - with one named "card", the card of the term in the {"term", "context"} object of the
#     source block: the `cards` entry of that term (also matched lowercased), else
#     `cardFallback` with {term} filled in; a non-empty definition is always behind MARK;
#   - otherwise a translation: the table's, else the source text echoed; always behind MARK.
#   It streams the reply as a few deltas, a "stop" chunk, a usage chunk when the request
#   asks for one, and [DONE]. Every request field is accepted, so the client never drops
#   fields to retry.
#
# The first path component picks a failure instead, for the failure rows of `make e2e-live`:
#   /hang/v1   answers 200 with an event-stream header, then sends nothing.
#   /cut/v1    streams two pieces of text, then closes the connection without finishing.
#   /slow/v1   streams one word every 100 ms for about 6 s, then finishes normally.
#
# Logs one line per request to stderr: the path, the reply kind and whether the table had
# it; never the text.
#
# Usage: scripts/fake-model.py <port>
# Port 0 lets the system pick a free one; the port in use is printed as the first line of
# standard output once the server accepts connections.

import http.server
import json
import pathlib
import re
import sys
import time

MARK = "[mock] "
REPLIES = pathlib.Path(__file__).resolve().parent.parent / "Fixtures/MockModel/replies.json"
SOURCE = re.compile(r"<(source_text_\w+)>\n(.*)\n</\1>", re.DOTALL)
FAILURES = ("hang", "cut", "slow")


def chunk(text=None, finish=None):
    delta = {"content": text} if text is not None else {}
    body = {"choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
    return ("data: " + json.dumps(body, ensure_ascii=False) + "\n\n").encode()


def usage_chunk(prompt, completion):
    usage = {"prompt_tokens": prompt, "completion_tokens": completion,
             "total_tokens": prompt + completion}
    return ("data: " + json.dumps({"choices": [], "usage": usage}) + "\n\n").encode()


def pieces(text, count=4):
    """`text` cut into up to `count` deltas."""
    size = max(1, -(-len(text) // count))
    return [text[i:i + size] for i in range(0, len(text), size)] or [""]


def card(table, user):
    """The card JSON for a card request's user message, and whether the table had it."""
    match = SOURCE.search(user)
    try:
        query = json.loads(match.group(2)) if match else {}
    except ValueError:
        query = {}
    if not isinstance(query, dict):
        query = {}
    term = str(query.get("term") or "").strip()
    entry = table["cards"].get(term) or table["cards"].get(term.lower())
    if entry:
        found = dict(entry["card"])
    else:
        # {term} goes in as JSON string content, so quotes in the term stay valid JSON.
        template = json.dumps(table["cardFallback"], ensure_ascii=False)
        found = json.loads(template.replace("{term}", json.dumps(term, ensure_ascii=False)[1:-1]))
        if not query.get("context"):
            found["contextTranslation"] = ""
    if found["definition"]:
        found["definition"] = MARK + found["definition"]
    return json.dumps(found, ensure_ascii=False), bool(entry)


def lookup(table, user):
    """The entry of `table` whose key occurs in `user`, the longest when several do."""
    keys = [key for key in table if key in user]
    return table[max(keys, key=len)] if keys else None


def reply(request):
    """The reply text for a parsed request body, its kind, and whether the table had it."""
    messages = request.get("messages") or []
    user = next((m.get("content") or "" for m in reversed(messages)
                 if m.get("role") == "user"), "")
    if not isinstance(user, str):
        user = ""
    table = json.loads(REPLIES.read_text(encoding="utf-8"))
    schema = (request.get("response_format") or {}).get("json_schema") or {}
    if schema.get("name") == "proofread":
        found = lookup(table["proofreads"], user)
        return json.dumps(found or {"edits": []}, ensure_ascii=False), "proofread", bool(found)
    if schema.get("name") == "card":
        text, found = card(table, user)
        return text, "card", found
    found = lookup(table["translations"], user)
    if found:
        return MARK + found, "translation", True
    match = SOURCE.search(user)
    return MARK + (match.group(2) if match else user), "translation", False


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def log(self, line):
        print(time.strftime("%H:%M:%S"), "POST", self.path, line, file=sys.stderr, flush=True)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        mode = self.path.strip("/").split("/")[0]
        if mode in FAILURES:
            self.log(mode)
            self.fail(mode)
        elif mode == "v1" and self.path.rstrip("/").endswith("/chat/completions"):
            try:
                request = json.loads(raw or b"{}")
            except ValueError:
                self.log("400 bad json")
                self.send_error(400)
                return
            self.answer(request)
        else:
            self.log("404")
            self.send_error(404)
            return
        self.close_connection = True

    def start_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.flush()

    def answer(self, request):
        text, kind, found = reply(request)
        self.log(f"200 {kind} {'table' if found else 'fallback'}")
        self.start_stream()
        try:
            # A card comes in more deltas, so the cuts land inside keys, values and escapes.
            for piece in pieces(text, 12 if kind == "card" else 4):
                self.wfile.write(chunk(piece))
                self.wfile.flush()
                time.sleep(0.04)
            self.wfile.write(chunk(finish="stop"))
            if (request.get("stream_options") or {}).get("include_usage"):
                prompt = sum(len(str(m.get("content", ""))) for m in request.get("messages", []))
                self.wfile.write(usage_chunk(prompt // 4, len(text) // 4))
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def fail(self, mode):
        self.start_stream()
        try:
            if mode == "hang":
                time.sleep(60)
            elif mode == "cut":
                for text in ["部分", "译文"]:
                    self.wfile.write(chunk(text))
                    self.wfile.flush()
                    time.sleep(0.1)
            else:
                for index in range(60):
                    self.wfile.write(chunk(f"词{index} "))
                    self.wfile.flush()
                    time.sleep(0.1)
                self.wfile.write(chunk(finish="stop"))
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


def make_server(port):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    return server


if __name__ == "__main__":
    server = make_server(int(sys.argv[1]))
    print(server.server_address[1], flush=True)
    server.serve_forever()
