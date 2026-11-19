"""Disposable HTTPS upstream for a read-only Git repo and one JSON endpoint."""

import argparse
import hmac
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl
import subprocess
from urllib.parse import urlsplit


class Fixture(BaseHTTPRequestHandler):
    def reply(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self, capability):
        headers = self.headers.get_all("Authorization") or []
        expected = (self.server.secrets / capability / "credential").read_bytes()
        return len(headers) == 1 and hmac.compare_digest(headers[0].encode(), expected)

    def do_GET(self):
        if self.path == "/private":
            if not self.authorized("json"):
                self.reply(401, "text/plain", b"authorization required\n")
                return
            self.reply(200, "application/json", b'{"fixture":"protected"}\n')
            return
        self.git("GET", "/repo.git/info/refs", "service=git-upload-pack")

    def do_POST(self):
        self.git("POST", "/repo.git/git-upload-pack", "")

    def git(self, method, path, query):
        request = urlsplit(self.path)
        if request.path != path or request.query != query:
            self.reply(404, "text/plain", b"unknown route\n")
            return
        if not self.authorized("git"):
            self.reply(401, "text/plain", b"authorization required\n")
            return
        size = self.headers.get("Content-Length", "0")
        if not size.isdecimal() or int(size) > 1024 * 1024:
            self.reply(413, "text/plain", b"request too large\n")
            return
        env = {
            "PATH": os.environ["PATH"],
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_PROJECT_ROOT": str(self.server.root),
            "GIT_HTTP_EXPORT_ALL": "1",
            "PATH_INFO": path,
            "QUERY_STRING": query,
            "REQUEST_METHOD": method,
            "CONTENT_LENGTH": size,
            "CONTENT_TYPE": self.headers.get("Content-Type", ""),
        }
        if self.headers.get("Git-Protocol") == "version=2":
            env["HTTP_GIT_PROTOCOL"] = "version=2"
        result = subprocess.run(
            ["git", "http-backend"],
            input=self.rfile.read(int(size)),
            env=env,
            capture_output=True,
            timeout=15,
        )
        headers, separator, body = result.stdout.partition(b"\r\n\r\n")
        cgi_headers = dict(line.split(b": ", 1) for line in headers.splitlines() if b": " in line)
        if result.returncode or not separator or b"Content-Type" not in cgi_headers:
            self.reply(502, "text/plain", b"git backend error\n")
            return
        status = int(cgi_headers.get(b"Status", b"200").split()[0])
        self.reply(status, cgi_headers[b"Content-Type"].decode("ascii"), body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("secrets", type=Path)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8444)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), Fixture)
    server.root = args.root
    server.secrets = args.secrets
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.secrets / "tls/tls.crt", args.secrets / "tls/tls.key")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print(server.server_port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
