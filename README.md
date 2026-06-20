# Homelab

Self-hosted service stack on Windows + WSL2, fronted by Caddy as reverse proxy.

## Stack

| Service | URL | Purpose |
|---|---|---|
| Homepage | https://dash.home | Dashboard / launcher (primary entry point) |
| Stirling-PDF | https://pdf.home | PDF tools (merge, split, OCR, convert) |
| Uptime Kuma | https://status.home | Uptime monitoring + alerts |
| IT-Tools | https://tools.home | Toolbox for devs (UUID, base64, JWT, hash, etc) |
| Portainer | https://portainer.home | Web UI for managing Docker |
| Odysseus | https://odysseus.home | (runs on WSL host, not in this stack) |

All services are reachable only through Caddy on ports 80 (HTTP) and 443
(HTTPS). HTTP requests are automatically redirected to HTTPS. No container
publishes a host port directly (except Caddy itself).

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Service definitions. |
| `Caddyfile` | Reverse proxy routes + global security headers. Uses `{{WSL_HOST_IP}}` placeholder (substituted at container start). |
| `caddy/entrypoint.sh` | Substitutes `{{WSL_HOST_IP}}` in `Caddyfile` and starts Caddy. |
| `.env.example` | Template for the `.env` secrets file. Copy to `.env` and fill in. |
| `.env` | Real secrets. **Never committed.** |
| `certs/` | TLS certs and mkcert root CA. **Not committed.** |
| `homepage/` | Homepage config (services, widgets, settings, images). Not committed. |
| `stirling-data/` | Stirling-PDF persistent state. Not committed. |
| `uptime-kuma-data/` | Uptime Kuma persistent state. Not committed. |
| `portainer_data/` | Docker named volume for Portainer's config. |

## First-time setup (after cloning)

1. Copy the env template:
   ```bash
   cp .env.example .env
   ```
   Fill in any values you need:
   - `WSL_HOST_IP` — your WSL2 eth0 IP (run `hostname -I` to get it).
     This is the **only** place you set the IP. It's used in
     `docker-compose.yml` (extra_hosts) and rendered into `Caddyfile`
     at container start via `caddy/entrypoint.sh`.
   - `PORTAINER_API_KEY` — for the Homepage widget.
2. Install `mkcert` and generate the TLS certs (see [HTTPS setup](#https-setup) below).
3. Add the hostnames to `C:\Windows\System32\drivers\etc\hosts` (Administrator).
   Use the same IP you set in `WSL_HOST_IP`:
   ```
   <WSL_IP>   dash.home
   <WSL_IP>   pdf.home
   <WSL_IP>   status.home
   <WSL_IP>   tools.home
   <WSL_IP>   portainer.home
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
8. Visit `https://dash.home` (Homepage, the new primary dashboard) in a
   browser private window (Zen/Firefox DNS cache workaround).

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
| Homarr | `ghcr.io/homarr-labs/homarr:latest` | 7575 | `dash.home` (or replace with Homepage) |
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
- **WSL IP changed after reboot:** run `hostname -I` in WSL, then update **only** `WSL_HOST_IP` in `.env` and the matching line in Windows `hosts`. Restart the stack (`docker compose up -d`). The `Caddyfile` placeholder `{{WSL_HOST_IP}}` is substituted at Caddy container start, so no compose or Caddyfile edit is needed.
- **Browser warns about untrusted cert:** the mkcert root CA isn't installed in your browser. See [HTTPS setup](#https-setup) below. Zen/Firefox keeps its own trust store — restart the browser after importing.
- **Portainer is empty / doesn't see the other stacks:** Portainer only sees containers it can reach via the Docker socket. If you want to manage stacks in other compose projects (e.g. `odysseus`, `cartus`) from Portainer, run them on the same Docker daemon with compose files in a known location, then add the parent directory in Portainer → Stacks → Add stack.

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
   mkcert -cert-file certs/dash.home.pem      -key-file certs/dash.home.key      dash.home
   mkcert -cert-file certs/pdf.home.pem       -key-file certs/pdf.home.key       pdf.home
   mkcert -cert-file certs/status.home.pem    -key-file certs/status.home.key    status.home
   mkcert -cert-file certs/tools.home.pem     -key-file certs/tools.home.key     tools.home
   mkcert -cert-file certs/portainer.home.pem -key-file certs/portainer.home.key portainer.home
   mkcert -cert-file certs/odysseus.home.pem  -key-file certs/odysseus.home.key  odysseus.home
   ```

   Portainer also needs the mkcert root CA to validate HTTPS on the other
   services it monitors. Mount it into the container:
   ```bash
   cp ~/.local/share/mkcert/rootCA.pem certs/rootCA.pem
   ```
   (Already wired in `docker-compose.yml` via `NODE_EXTRA_CA_CERTS`.)
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
