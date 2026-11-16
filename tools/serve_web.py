"""Servidor HTTP local para testar a build Web (build/web) no navegador.

Uso:  python tools/serve_web.py [porta]
Abre em http://localhost:8060 . Como a build é single-thread, não precisa de
COOP/COEP; os cabeçalhos são enviados mesmo assim para facilitar testar a
variante com threads no futuro. O jogo conecta em ws://<host>:7777 (servidor
headless rodando em paralelo) ou em ?server=ws://outro-host:porta .
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    if not os.path.isfile(os.path.join(ROOT, "index.html")):
        sys.exit("build/web/index.html não existe. Rode antes: .\\tools\\build_web.ps1")
    print(f"Servindo {ROOT} em http://localhost:{PORT}  (Ctrl+C para parar)")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
