# Deploy (Web em produção)

Alvo: `https://umbraheim.proflow.online`, num servidor Linux x86_64 (Debian ou Ubuntu).

```
Navegador ──HTTPS──► nginx (443) ──► /var/www/umbraheim (index.html, .wasm, .pck)
Navegador ──wss://umbraheim.proflow.online/ws──► nginx ──ws://127.0.0.1:7777──► Godot headless (systemd)
```

Na Web, quando a página é HTTPS, o cliente conecta sozinho em `wss://<host da página>/ws`
(`client/client_main.gd`, `_server_url`). Não há nada para configurar no cliente.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `tools/deploy/deploy.sh` | instala ou atualiza tudo, menos nginx e certificado (rodar como root) |
| `tools/deploy/umbraheim.service` | serviço systemd do servidor de jogo |
| `tools/deploy/nginx-umbraheim.conf` | site do nginx: arquivos estáticos e proxy do WebSocket em `/ws` |

## Primeira instalação

1. DNS: registro `A` (e `AAAA`, se houver IPv6) de `umbraheim.proflow.online` para o IP do servidor.
2. Código e build: `git clone https://github.com/mariomcj/umbraheim.git /tmp/umbraheim && sudo bash /tmp/umbraheim/tools/deploy/deploy.sh`.
   - Baixa a Godot 4.7.2 (Linux) e os export templates do GitHub oficial da Godot (cerca de 1,2 GB nos templates; só na primeira vez).
   - Clona o repositório em `/opt/umbraheim/app`, importa (a primeira importação leva minutos), exporta a build Web para `/var/www/umbraheim` e liga o serviço `umbraheim`.
3. nginx: `apt install nginx certbot python3-certbot-nginx`; copiar `tools/deploy/nginx-umbraheim.conf` para `/etc/nginx/sites-available/umbraheim`, ligar com `ln -s` em `sites-enabled`, `nginx -t && systemctl reload nginx`.
4. Certificado: `certbot --nginx -d umbraheim.proflow.online` (o certbot acrescenta o bloco 443 e o redirecionamento).
5. Firewall: abrir 80 e 443; **não** abrir 7777 (o servidor escuta só em 127.0.0.1).

## Atualizar

`sudo bash /opt/umbraheim/app/tools/deploy/deploy.sh` (puxa o `main`, refaz a build e reinicia o serviço).
Os jogadores conectados caem na reinicialização e reconectam sozinhos.

## Conferir

- `systemctl status umbraheim` e `journalctl -u umbraheim -f` (procure `[server] escutando ws://127.0.0.1:7777`).
- `curl -sI https://umbraheim.proflow.online/index.pck` → 200.
- WebSocket pelo proxy:
  `curl -i -N --http1.1 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" https://umbraheim.proflow.online/ws` → `101 Switching Protocols`.
- No navegador: abrir o site, criar conta e personagem, entrar no mundo; console sem erros.

## Banco e backup

- SQLite em `/var/lib/umbraheim/umbraheim.db` (contas, personagens, guildas, castelo). O servidor grava a cada `server.autosave_interval_s` e ao sair.
- Backup diário sugerido (cron do root): `sqlite3 /var/lib/umbraheim/umbraheim.db ".backup '/var/backups/umbraheim-$(date +\%F).db'"` e apagar os antigos.

## Observações

- Nunca usar `--allow-gm` em produção (comandos de GM pelo chat).
- O servidor roda direto do código-fonte com a Godot headless (precisa do `--import` que o `deploy.sh` faz). Alternativa: exportar o preset "Servidor Linux" (`build/server/`), que usa a mesma biblioteca SQLite de Linux já incluída em `addons/godot-sqlite/bin`.
- Memória: o servidor usa pouco; a importação e a exportação usam mais (recomendado 2 GB de RAM livre na hora do deploy).
- `assets/_raw/` e `downloads/` não estão no repositório (originais de áudio e assets). Não fazem falta para rodar nem para exportar.
