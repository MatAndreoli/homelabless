# Homelab

Self-hosted service stack on Windows + WSL2, fronted by Caddy as reverse proxy.

## Stack

| Service | URL | Purpose |
|---|---|---|
| Homarr | https://dash.home | Dashboard / launcher |
| Stirling-PDF | https://pdf.home | PDF tools (merge, split, OCR, convert) |
| Uptime Kuma | https://status.home | Uptime monitoring + alerts |
| Odysseus | https://odysseus.home | (runs on WSL host, not in this stack) |

All services are reachable only through Caddy on ports 80 (HTTP) and 443
(HTTPS). HTTP requests are automatically redirected to HTTPS. No container
publishes a host port directly (except Caddy itself).

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Service definitions. |
| `Caddyfile` | Reverse proxy routes + global security headers. |
| `.env.example` | Template for the `.env` secrets file. Copy to `.env` and fill in. |
| `.env` | Real secrets. **Never committed.** |
| `homarr-data/` | Homarr persistent state (DB, uploads). Not committed. |
| `stirling-data/` | Stirling-PDF persistent state. Not committed. |
| `uptime-kuma-data/` | Uptime Kuma persistent state. Not committed. |

## First-time setup (after cloning)

1. Copy the env template and generate a fresh secret:
   ```bash
   cp .env.example .env
   openssl rand -hex 32 | xargs -I {} sed -i "s/replace_me_with_output_of_openssl_rand_hex_32/{}/" .env
   ```
2. Install `mkcert` and generate the TLS certs (see [HTTPS setup](#https-setup) below).
3. Find your WSL host IP (used by Caddy to reach the WSL host and by Windows to reach WSL):
   ```bash
   hostname -I
   ```
4. Edit `docker-compose.yml` and `Caddyfile` to replace `172.27.95.84` with your IP (see comments inline).
5. Add the hostnames to `C:\Windows\System32\drivers\etc\hosts` (Administrator):
   ```
   <WSL_IP>   dash.home
   <WSL_IP>   pdf.home
   <WSL_IP>   status.home
   <WSL_IP>   odysseus.home
   ```
6. Flush DNS in PowerShell (Admin):
   ```powershell
   ipconfig /flushdns
   ```
7. Start the stack:
   ```bash
   docker compose up -d
   ```
8. Visit `https://dash.home` in a browser private window (Zen/Firefox DNS cache workaround).

## Adding a new service

Three things to touch per new service:

1. Add a block to `docker-compose.yml` (snippet below).
2. Add an `https://` route + an `http://` redirect in `Caddyfile` (snippet below).
3. Add the hostname to Windows `hosts`.

Then reload:

```bash
docker compose up -d
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### 1. docker-compose.yml snippet

```yaml
  <service-name>:
    # Internal port: <PORT> (proxied by Caddy as <service>.home)
    image: <image>:<tag>
    container_name: <service-name>
    restart: unless-stopped
    environment:
      # - KEY=value  # uncomment if the service needs config
    volumes:
      - ./<service-name>-data:/data
    networks:
      - homelab
```

**Do not publish a host port** (`ports:`) unless you really need direct access — keep the surface minimal. Caddy reaches the container by name on the `homelab` network.

If the service has no persistent state, omit the `volumes:` block. If it needs a sidecar (DB, cache), add another service in the same compose file on the `homelab` network.

### 2. Caddyfile snippet

```caddyfile
http://<service>.home {
    redir https://<service>.home{uri} permanent
}

https://<service>.home {
    import secure_headers
    tls /certs/<service>.home.pem /certs/<service>.home.key
    reverse_proxy <service-name>:<PORT>
}
```

If the service runs **on the WSL host** (outside this compose stack), point at the host IP:

```caddyfile
reverse_proxy <WSL_IP>:<PORT>
```

Don't forget to generate a TLS cert for the new hostname:

```bash
cd /home/matandreoli/homelab
mkcert -cert-file certs/<service>.home.pem -key-file certs/<service>.home.key <service>.home
```

### 3. Windows hosts snippet

Append to `C:\Windows\System32\drivers\etc\hosts` (open as Administrator):

```
<WSL_IP>   <service>.home
```

Then `ipconfig /flushdns` in PowerShell (Admin). In Zen/Firefox, open a private window (`Ctrl+Shift+P`) for the first visit to bypass the browser DNS cache.

---

## Common service ports

Cheat sheet for apps you might add. Always verify against the image's current docs — default ports change.

| App | Image | Port | Hostname suggestion |
|---|---|---|---|
| Uptime Kuma | `louislam/uptime-kuma:2` | 3001 | `status.home` |
| Vaultwarden | `vaultwarden/server:latest` | 80 | `vault.home` |
| Portainer CE | `portainer/portainer-ce:latest` | 9000 | `portainer.home` |
| Dockge | `louislam/dockge:1` | 5001 | `dockge.home` |
| Nextcloud | `nextcloud:29-apache` | 80 | `cloud.home` |
| Jellyfin | `jellyfin/jellyfin:10.10` | 8096 | `media.home` |
| Navidrome | `deluan/navidrome:latest` | 4533 | `music.home` |
| Immich | `ghcr.io/immich-app/immich-server:release` | 2283 | `photos.home` |
| Audiobookshelf | `ghcr.io/advplyr/audiobookshelf:latest` | 80 | `books.home` |
| Paperless-ngx | `ghcr.io/paperless-ngx/paperless-ngx:latest` | 8000 | `docs.home` |
| Dozzle | `amir20/dozzle:latest` | 8080 | `logs.home` |
| IT-Tools | `corentinth/it-tools:latest` | 80 | `tools.home` |
| Mealie | `ghcr.io/mealie-recipes/mealie:latest` | 9000 | `recipes.home` |
| Glances | `nicolargo/glances:latest` | 61208 | `stats.home` |
| Homepage | `ghcr.io/gethomepage/homepage:latest` | 3000 | `hp.home` |
| Trilium Notes | `zadam/trilium:latest` | 8080 | `notes.home` |
| Linkding | `sissbruecker/linkding:latest` | 9090 | `links.home` |
| Changedetection | `ghcr.io/dgtlmoon/changedetection.io:latest` | 5000 | `watch.home` |
| n8n | `n8nio/n8n:latest` | 5678 | `n8n.home` |
| Excalidraw | `excalidraw/excalidraw:latest` | 80 | `draw.home` |
| Filebrowser | `filebrowser/filebrowser:latest` | 80 | `files.home` |

---

## Removing a service

1. Delete the service block from `docker-compose.yml`.
2. Delete the route from `Caddyfile`.
3. Delete the line from Windows `hosts`.
4. Run:
   ```bash
   docker compose down <service-name>
   docker exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```
5. Optionally delete the data folder `./<service-name>-data/`.

---

## Updating image versions

```bash
docker compose pull
docker compose up -d
```

Image tags are pinned in `docker-compose.yml`. To upgrade a service to a new major version, edit the tag manually and re-pull.

---

## Troubleshooting

- **Browser hits a public IP instead of the WSL service:** Zen/Firefox is caching an old DNS. Open in a private window (`Ctrl+Shift+P`) or clear `about:config` → `network.dnsCacheEntries` → 0.
- **Caddy 502 on a route:** the upstream service isn't running, or `extra_hosts` doesn't reach the WSL host. Check `docker compose ps` and `docker exec caddy wget http://service:port/`.
- **WSL IP changed after reboot:** run `hostname -I` in WSL, then update `docker-compose.yml`, `Caddyfile`, and Windows `hosts` with the new IP. Restart the stack.
- **Browser warns about untrusted cert:** the mkcert root CA isn't installed in your browser. See [HTTPS setup](#https-setup) below. Zen/Firefox keeps its own trust store — restart the browser after importing.

---

## HTTPS setup

This stack uses [mkcert](https://github.com/FiloSottile/mkcert) to issue
local TLS certificates signed by a private CA. Browsers trust them only
if the mkcert root CA is installed in their trust store. No public CA,
no domain, no internet required.

### One-time setup (per machine)

1. Install mkcert:
   ```bash
   sudo apt install mkcert
   ```
2. Install the mkcert root CA into the Linux trust store (also handles
   browsers running inside WSL):
   ```bash
   mkcert -install
   ```
3. Generate a cert per hostname. The certs land in `./certs/` and are
   bind-mounted into Caddy at `/certs/`:
   ```bash
   cd /home/matandreoli/homelab
   mkdir -p certs
   mkcert -cert-file certs/dash.home.pem     -key-file certs/dash.home.key     dash.home
   mkcert -cert-file certs/pdf.home.pem      -key-file certs/pdf.home.key      pdf.home
   mkcert -cert-file certs/status.home.pem   -key-file certs/status.home.key   status.home
   mkcert -cert-file certs/odysseus.home.pem -key-file certs/odysseus.home.key odysseus.home
   ```
4. **Install the mkcert root CA in your browser** (Zen / Firefox):
   - Open `about:preferences#privacy` → Certificates → View Certificates
   - Tab **Authorities** → **Import**
   - Path: `\\wsl$\Ubuntu\home\matandreoli\.local\share\mkcert\rootCA.pem`
   - Check **"Trust this CA to identify websites"** → OK
   - Restart the browser

   To trust from native Windows tools (PowerShell, curl.exe, etc), also
   import the cert into the Windows trust store via `certmgr.msc`.

5. Recreate the Caddy container so the new volume mount takes effect:
   ```bash
   docker compose up -d caddy
   ```

### Renewing certs

mkcert certs are valid for ~2 years. To regenerate (same commands
overwrite the existing files):

```bash
cd /home/matandreoli/homelab
mkcert -cert-file certs/dash.home.pem -key-file certs/dash.home.key dash.home
# ... repeat for other hostnames
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

The mkcert root CA itself doesn't expire but you can check its status
with `mkcert -CAROOT`.

### Why not Let's Encrypt?

LE requires a public domain and DNS pointing to a public IP, plus an
ACME challenge on port 80 (or DNS challenge). This stack is on a
private WSL2 network with no public domain, so LE is not an option.
mkcert gives a "real" HTTPS experience (green padlock, valid TLS 1.3,
HSTS) without any of that.
