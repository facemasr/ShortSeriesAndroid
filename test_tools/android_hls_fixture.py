#!/usr/bin/env python3
"""Synthetic local HLS server for Android CI — never serves real channels."""
from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class HeaderValidatedStream(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".m3u8": "application/vnd.apple.mpegurl",
        ".ts": "video/mp2t",
    }

    def _valid(self) -> bool:
        return (
            self.headers.get("User-Agent") == "EGYSHOW-Android-Control/1.0"
            and self.headers.get("Referer") == "https://provider.example/player"
        )

    def do_GET(self):
        if not self._valid():
            self.send_error(403, "Required provider media headers missing")
            return
        return super().do_GET()

    def do_HEAD(self):
        if not self._valid():
            self.send_error(403, "Required provider media headers missing")
            return
        return super().do_HEAD()

    def log_message(self, fmt: str, *args):
        # This fixture never echoes HTTP headers or signed media URLs.
        print("HLS_FIXTURE: " + (fmt % args), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    handler = partial(HeaderValidatedStream, directory=args.root)
    with ThreadingHTTPServer(("0.0.0.0", args.port), handler) as server:
        print("HLS_FIXTURE_READY", flush=True)
        server.serve_forever()
