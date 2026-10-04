#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# A local stand-in for a Chat Completions endpoint, for the failure rows of `make e2e-live`.
# The first path component picks the behaviour; the rest is the usual /v1/chat/completions:
#   /hang/v1   answers 200 with an event-stream header, then sends nothing.
#   /cut/v1    streams two pieces of text, then closes the connection without finishing.
#   /slow/v1   streams one word every 100 ms for about 6 s, then finishes normally.
# It never reads or logs the request body beyond its length.
#
# Usage: scripts/fake-model.py <port>

import http.server
import json
import sys
import time


def chunk(text=None, finish=None):
    delta = {"content": text} if text is not None else {}
    body = {"choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
    return ("data: " + json.dumps(body, ensure_ascii=False) + "\n\n").encode()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        mode = self.path.strip("/").split("/")[0]
        if mode not in ("hang", "cut", "slow"):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.flush()
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
        self.close_connection = True


if __name__ == "__main__":
    port = int(sys.argv[1])
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    server.serve_forever()
