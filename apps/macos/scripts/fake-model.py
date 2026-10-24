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
#   - with the translate-out task sentence in the user message, the `translateOuts` entry
#     whose text occurs in it, else the source text echoed; always behind MARK;
#   - otherwise a translation: the table's, else the source text echoed; always behind MARK.
#     The back-translation of a translate-out result is such a translation: `translations`
#     has the reverse of every `translateOuts` entry.
#   It streams the reply as a few deltas, a "stop" chunk, a usage chunk when the request
#   asks for one, and [DONE]. Every request field is accepted, so the client never drops
#   fields to retry.
#
# The first path component picks a failure instead, for the failure rows of `make e2e-live`:
#   /hang/v1   answers 200 with an event-stream header, then sends nothing.
#   /cut/v1    streams two pieces of text, then closes the connection without finishing.
#   /slow/v1   streams one word every 100 ms for about 6 s, then finishes normally.
#
# Two GETs list the one model, `mock`, for the Settings model list:
#   /v1/models  in the OpenAI shape, as a custom provider's base URL plus /models;
#   /api/tags   in the Ollama shape.
# Any other GET is a 404 with an OpenAI-shaped error body, {"error": {"message": …}}.
#
# Sign in with ChatGPT and the plan's Responses API, for the ChatGPT provider under
# DICT_MOCK_MODEL (ChatGPTEndpoints.mock): no real account, no real tokens.
#   GET  /auth/api/accounts/authorize     checks the parameters a first or later sign-in
#        sends, then 302s to the 127.0.0.1 redirect URI with a code, the state and, on a
#        first sign-in, the issued client id `oaiapp_mock`.
#   POST /auth/api/accounts/oauth/token   the code (PKCE checked with SHA-256, same
#        redirect URI) or a refresh token for new tokens, and an unsigned ID token whose
#        iss is this server's /auth; a spent or unknown token is `invalid_grant`.
#   POST /auth/api/accounts/oauth/revoke  forgets the refresh token; always 200.
#   GET  /chatgpt/v1/models               the plan's shape: `mock` listed, one hidden entry.
#   POST /chatgpt/v1/responses            the same replies as above as Responses SSE
#        events. It rejects what the plan rejects: no `store: false` or `stream: true`, a
#        system-role input item, or `max_output_tokens`, `temperature` and the other
#        unsupported fields, as `subscription_sharing_unsupported_capability` with `param`.
#        The model `mock-limit` answers 429 `subscription_sharing_usage_limit_exceeded`.
#   Both /chatgpt routes want an access token this server issued, else 401.
#
# Logs one line per request to stderr: the path, the reply kind and whether the table had
# it; never the text, a query string or a token.
#
# Usage: scripts/fake-model.py <port>
# Port 0 lets the system pick a free one; the port in use is printed as the first line of
# standard output once the server accepts connections.

import base64
import hashlib
import http.server
import json
import pathlib
import re
import secrets
import sys
import threading
import time
import urllib.parse

MARK = "[mock] "
REPLIES = pathlib.Path(__file__).resolve().parent.parent / "Fixtures/MockModel/replies.json"
SOURCE = re.compile(r"<(source_text_\w+)>\n(.*)\n</\1>", re.DOTALL)
# The task sentence of PromptBuilder.translateOut, after the source block.
TRANSLATE_OUT = "as the writer's own message"
FAILURES = ("hang", "cut", "slow")
MODEL_LISTS = {
    "/v1/models": {
        "object": "list",
        "data": [{"id": "mock", "object": "model", "created": 0, "owned_by": "dict-mock"}],
    },
    "/api/tags": {
        "models": [{
            "name": "mock", "model": "mock", "modified_at": "2026-01-01T00:00:00Z", "size": 0,
            "digest": "0" * 64,
            "details": {"format": "gguf", "family": "mock", "parameter_size": "0B",
                        "quantization_level": "none"},
        }],
    },
}


MOCK_CLIENT = "oaiapp_mock"
PLAN_SCOPE = "chatgpt.tokens.use.direct"
SCOPES = "openid profile email offline_access resource.invoke " + PLAN_SCOPE
CHATGPT_MODELS = {"models": [
    {"slug": "mock", "display_name": "Mock", "visibility": "list"},
    {"slug": "mock-hidden", "display_name": "Hidden", "visibility": "hide"},
]}
# Fields the plan's Responses API rejects (docs/reviews/chatgpt-login.md 2.6).
UNSUPPORTED = ("background", "conversation", "max_output_tokens", "max_tool_calls", "metadata",
               "moderation", "multi_agent", "prompt", "prompt_cache_retention",
               "safety_identifier", "temperature", "top_logprobs", "top_p", "truncation", "user",
               "previous_response_id")


class AuthState:
    """The codes and tokens this server issued, shared by the handler threads."""

    def __init__(self):
        self.lock = threading.Lock()
        self.codes = {}
        self.refresh_tokens = set()
        self.access_tokens = set()

    def issue(self):
        access = "mock-access-" + secrets.token_hex(8)
        refresh = "mock-refresh-" + secrets.token_hex(8)
        with self.lock:
            self.access_tokens.add(access)
            self.refresh_tokens.add(refresh)
        return access, refresh

    def spend_refresh(self, token):
        with self.lock:
            if token not in self.refresh_tokens:
                return False
            self.refresh_tokens.discard(token)
            return True

    def knows_access(self, token):
        with self.lock:
            return token in self.access_tokens


AUTH = AuthState()


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def id_token(issuer, nonce):
    """An unsigned compact JWT: Dict checks the claims of a token it got straight from the
    token endpoint, not a signature."""
    header = b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
    now = int(time.time())
    claims = {"iss": issuer, "aud": MOCK_CLIENT, "sub": "mock-user", "email": "mock@example.com",
              "exp": now + 3600, "iat": now, "nonce": nonce}
    return f"{header}.{b64url(json.dumps(claims).encode())}.mock"


def token_answer(issuer, nonce=None):
    access, refresh = AUTH.issue()
    answer = {"access_token": access, "refresh_token": refresh, "token_type": "Bearer",
              "expires_in": 3600, "scope": SCOPES}
    if nonce is not None:
        answer["id_token"] = id_token(issuer, nonce)
    return answer


def first(fields, name):
    return (fields.get(name) or [""])[0]


def authorize_redirect(query):
    """The Location for a well-formed authorization request and None, or None and why not."""
    client = first(query, "client_id")
    registering = client == "dynamic_agent_client"
    if not registering and client != MOCK_CLIENT:
        return None, "unknown client_id"
    if registering and not first(query, "agent_name_hint"):
        return None, "a first sign-in needs agent_name_hint"
    redirect = first(query, "redirect_uri")
    if not re.fullmatch(r"http://127\.0\.0\.1:\d+/auth/callback", redirect):
        return None, "redirect_uri must be http://127.0.0.1:<port>/auth/callback"
    for name in ("ext_agent_host_id", "state", "nonce", "code_challenge", "resource"):
        if not first(query, name):
            return None, f"missing {name}"
    if first(query, "response_type") != "code" or first(query, "code_challenge_method") != "S256":
        return None, "response_type=code and code_challenge_method=S256 are required"
    if PLAN_SCOPE not in first(query, "scope").split():
        return None, "scope lacks " + PLAN_SCOPE
    code = "mock-code-" + secrets.token_hex(8)
    with AUTH.lock:
        AUTH.codes[code] = {"challenge": first(query, "code_challenge"), "redirect": redirect,
                            "nonce": first(query, "nonce")}
    params = {"code": code, "state": first(query, "state"), "scope": SCOPES}
    if registering:
        params["client_id"] = MOCK_CLIENT
    return redirect + "?" + urllib.parse.urlencode(params), None


def token_grant(form, issuer):
    """The status and JSON answer of the token endpoint for a parsed form."""
    if first(form, "client_id") != MOCK_CLIENT or not first(form, "resource"):
        return 400, {"error": "invalid_client"}
    grant_type = first(form, "grant_type")
    if grant_type == "authorization_code":
        with AUTH.lock:
            grant = AUTH.codes.pop(first(form, "code"), None)
        challenge = b64url(hashlib.sha256(first(form, "code_verifier").encode()).digest())
        if (not grant or grant["redirect"] != first(form, "redirect_uri")
                or grant["challenge"] != challenge):
            return 400, {"error": "invalid_grant"}
        return 200, token_answer(issuer, grant["nonce"])
    if grant_type == "refresh_token":
        if not AUTH.spend_refresh(first(form, "refresh_token")):
            return 400, {"error": "invalid_grant"}
        return 200, token_answer(issuer)
    return 400, {"error": "unsupported_grant_type"}


def unsupported(request):
    """The parameter of a Responses request the plan would reject, or None."""
    if request.get("store") is not False:
        return "store"
    if request.get("stream") is not True:
        return "stream"
    for name in UNSUPPORTED:
        if name in request:
            return name
    for item in request.get("input") or []:
        if isinstance(item, dict) and item.get("role") == "system":
            return "input.role"
    return None


def as_chat(request):
    """A Responses request in the Chat Completions shape `reply` reads."""
    messages = []
    if request.get("instructions"):
        messages.append({"role": "system", "content": request["instructions"]})
    messages += [item for item in request.get("input") or [] if isinstance(item, dict)]
    chat = {"messages": messages}
    fmt = (request.get("text") or {}).get("format") or {}
    if fmt.get("type") == "json_schema":
        chat["response_format"] = {"type": "json_schema", "json_schema": {"name": fmt.get("name")}}
    return chat


def responses_event(kind, **fields):
    fields["type"] = kind
    return f"event: {kind}\ndata: {json.dumps(fields, ensure_ascii=False)}\n\n".encode()


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
    if TRANSLATE_OUT in user:
        found = lookup(table["translateOuts"], user)
        match = SOURCE.search(user)
        text = found or (match.group(2) if match else user)
        return MARK + text, "translateOut", bool(found)
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
        print(time.strftime("%H:%M:%S"), self.command, self.path.split("?")[0], line,
              file=sys.stderr, flush=True)

    def send_json(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def issuer(self):
        return f"http://{self.headers.get('Host') or '127.0.0.1'}/auth"

    def has_access_token(self):
        header = self.headers.get("Authorization") or ""
        return AUTH.knows_access(header.removeprefix("Bearer "))

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        if path == "/auth/api/accounts/authorize":
            query = urllib.parse.parse_qs(self.path.partition("?")[2])
            location, error = authorize_redirect(query)
            if location:
                self.log("302 authorize")
                self.send_response(302)
                self.send_header("Location", location)
                self.send_header("Content-Length", "0")
                self.end_headers()
            else:
                self.log(f"400 authorize: {error}")
                self.send_json(400, {"error": "invalid_request", "error_description": error})
            return
        if path == "/chatgpt/v1/models":
            if self.has_access_token():
                self.log("200 chatgpt models")
                self.send_json(200, CHATGPT_MODELS)
            else:
                self.log("401 chatgpt models")
                self.send_json(401, {"detail": "Unauthorized"})
            return
        found = path in MODEL_LISTS
        status = 200 if found else 404
        # Errors in the OpenAI shape, which the model list reads its message from.
        body = MODEL_LISTS[path] if found else {"error": {"message": f"no route {path}"}}
        payload = json.dumps(body).encode()
        self.log(f"{status} models" if found else "404")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        mode = self.path.strip("/").split("/")[0]
        path = self.path.split("?")[0].rstrip("/")
        if path == "/auth/api/accounts/oauth/token":
            form = urllib.parse.parse_qs(raw.decode("utf-8", "replace"))
            status, answer = token_grant(form, self.issuer())
            self.log(f"{status} token {first(form, 'grant_type')}")
            self.send_json(status, answer)
            return
        if path == "/auth/api/accounts/oauth/revoke":
            form = urllib.parse.parse_qs(raw.decode("utf-8", "replace"))
            AUTH.spend_refresh(first(form, "token"))
            self.log("200 revoke")
            self.send_json(200, {})
            return
        if path == "/chatgpt/v1/responses":
            self.answer_responses(raw)
            self.close_connection = True
            return
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

    def answer_responses(self, raw):
        if not self.has_access_token():
            self.log("401 responses")
            self.send_json(401, {"detail": "Unauthorized"})
            return
        try:
            request = json.loads(raw or b"{}")
        except ValueError:
            self.log("400 bad json")
            self.send_json(400, {"error": {"message": "invalid JSON"}})
            return
        param = unsupported(request)
        if param:
            self.log(f"400 responses unsupported {param}")
            self.send_json(400, {"error": {
                "code": "subscription_sharing_unsupported_capability",
                "message": f"Unsupported parameter: {param}", "param": param}})
            return
        if request.get("model") == "mock-limit":
            self.log("429 responses limit")
            self.send_json(429, {"error": {
                "code": "subscription_sharing_usage_limit_exceeded",
                "message": "Usage limit reached"}})
            return
        text, kind, found = reply(as_chat(request))
        self.log(f"200 responses {kind} {'table' if found else 'fallback'}")
        self.start_stream()
        try:
            self.wfile.write(responses_event("response.created",
                                             response={"status": "in_progress"}))
            for piece in pieces(text, 12 if kind == "card" else 4):
                self.wfile.write(responses_event("response.output_text.delta", delta=piece))
                self.wfile.flush()
                time.sleep(0.04)
            usage = {"input_tokens": len(raw) // 4, "output_tokens": len(text) // 4}
            self.wfile.write(responses_event(
                "response.completed", response={"status": "completed", "usage": usage}))
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
