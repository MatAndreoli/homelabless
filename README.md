# Homelab

Self-hosted service stack on Windows + WSL2, fronted by Caddy as reverse proxy.

## Stack

| Service | URL | Purpose |
|---|---|---|
| Homarr | http://dash.home | Dashboard / launcher |
| Stirling-PDF | http://pdf.home | PDF tools (merge, split, OCR, convert) |
| Uptime Kuma | http://status.home | Uptime monitoring + alerts |
| Odysseus | http://odysseus.home | (runs on WSL host, not in this stack) |

All services are reachable only through Caddy on port 80. No container
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
2. Find your WSL host IP (used by Caddy to reach the WSL host and by Windows to reach WSL):
   ```bash
   hostname -I
   ```
3. Edit `docker-compose.yml` and `Caddyfile` to replace `172.27.95.84` with your IP (see comments inline).
4. Add the hostnames to `C:\Windows\System32\drivers\etc\hosts` (Administrator):
   ```
   <WSL_IP>   dash.home
   <WSL_IP>   pdf.home
   <WSL_IP>   status.home
   <WSL_IP>   odysseus.home
   ```
5. Flush DNS in PowerShell (Admin):
   ```powershell
   ipconfig /flushdns
   ```
6. Start the stack:
   ```bash
   docker compose up -d
   ```
7. Visit `http://dash.home` in a browser private window (Zen/Firefox DNS cache workaround).

## Adding a new service

Three things to touch per new service:

1. Add a block to `docker-compose.yml` (snippet below).
2. Add a route to `Caddyfile` (snippet below).
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
    import secure_headers
    reverse_proxy <service-name>:<PORT>
}
```

If the service runs **on the WSL host** (outside this compose stack), point at the host IP:

```caddyfile
http://<service>.home {
    import secure_headers
    reverse_proxy <WSL_IP>:<PORT>
}
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
