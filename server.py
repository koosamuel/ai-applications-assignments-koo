from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parent
PUBLIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json; charset=utf-8"),
    "/sw.js": ("sw.js", "text/javascript; charset=utf-8"),
}


class AppShellHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        public_file = PUBLIC_FILES.get(urlsplit(self.path).path)
        if not public_file:
            self.send_error(404)
            return
        filename, content_type = public_file
        payload = (ROOT / filename).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> None:
    parser = argparse.ArgumentParser(description="AI응용 개인·팀과제 통합 웹 서버")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args()

    if not (ROOT / "index.html").is_file():
        raise SystemExit("index.html이 없습니다. 생성기를 먼저 실행하세요.")
    server = ThreadingHTTPServer((args.host, args.port), AppShellHandler)
    print(f"Local URL: http://{args.host}:{args.port}", flush=True)
    print(f"Serving: {ROOT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
