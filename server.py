from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent / "dist"


def main() -> None:
    parser = argparse.ArgumentParser(description="AI응용 개인과제 통합 웹 서버")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args()

    if not (ROOT / "index.html").is_file():
        raise SystemExit("dist/index.html이 없습니다. scripts/build-static.sh를 먼저 실행하세요.")
    handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT))
    server = ThreadingHTTPServer((args.host, args.port), handler)
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
