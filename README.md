# Homelab

Self-hosted service stack on Windows + WSL2, fronted by Caddy as reverse proxy.

## Stack

| Service      | URL                          | Purpose                                         | Auth                                 |
| ------------ | ---------------------------- | ----------------------------------------------- | ------------------------------------ |
| Authelia     | <https://login.homelab.less>     | SSO gate (login + 2FA)                          | —                                    |
| Homepage     | <https://dash.homelab.less>      | Dashboard / launcher (primary entry point)      | required                             |
| Stirling-PDF | <https://pdf.homelab.less>       | PDF tools (merge, split, OCR, convert)          | required                             |
| Uptime Kuma  | <https://status.homelab.less>    | Uptime monitoring + alerts                      | required (except public status page) |
| IT-Tools     | <https://tools.homelab.less>     | Toolbox for devs (UUID, base64, JWT, hash, etc) | required                             |
| Portainer    | <https://portainer.homelab.less> | Web UI for managing Docker                      | required                             |
| Odysseus     | <https://odysseus.homelab.less>  | (runs on WSL host, not in this stack)           | required                             |

All services are reachable only through Caddy on ports 80 (HTTP) and 443
(HTTPS). HTTP requests are automatically redirected to HTTPS. No container
publishes a host port directly (except Caddy itself).

**Authelia** sits in front of every route via Caddy's `forward_auth`:

- One login covers all `*.homelab.less` hostnames (session cookie on parent domain `homelab.less`).
- Hitting any gated route redirects to `https://login.homelab.less/?rd=<original-url>`.
- After login, redirected back to the original URL.
- Initial credentials: `matandreoli` / `ChangeMe!2026` — **change immediately** after first login.
- Default policy: `one_factor` (password only). Switch to `two_factor` in `authelia/configuration.yml` after enrolling a TOTP device via the registration flow.

**Public paths** (no auth, see `Caddyfile`): `status.homelab.less/api/status-page/*`, `/api/badge/*`, `/api/incidents/*`, `/api/heartbeat/*`.

## Files

| File                  | Purpose                                                                                                              |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `docker-compose.yml`  | Service definitions.                                                                                                 |
| `Caddyfile`           | Reverse proxy routes + global security headers. Uses `{{WSL_HOST_IP}}` placeholder (substituted at container start). |
| `caddy/entrypoint.sh` | Substitutes `{{WSL_HOST_IP}}` in `Caddyfile` and starts Caddy.                                                       |
| `.env.example`        | Template for the `.env` secrets file. Copy to `.env` and fill in.                                                    |
| `.env`                | Real secrets. **Never committed.**                                                                                   |
| `certs/`              | TLS certs and mkcert root CA. **Not committed.**                                                                     |
| `authelia/`           | Authelia config (`configuration.yml`) + user database (`users.yml`). Not committed.                                  |
| `homepage/`           | Homepage config (services, widgets, settings, images). Not committed.                                                |
| `stirling-data/`      | Stirling-PDF persistent state. Not committed.                                                                        |
| `uptime-kuma-data/`   | Uptime Kuma persistent state. Not committed.                                                                         |
| `portainer_data/`     | Docker named volume for Portainer's config.                                                                          |
| `authelia_data`       | Docker named volume for Authelia SQLite + notifications.                                                             |

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
   <WSL_IP>   login.homelab.less
   <WSL_IP>   dash.homelab.less
   <WSL_IP>   pdf.homelab.less
   <WSL_IP>   status.homelab.less
   <WSL_IP>   tools.homelab.less
   <WSL_IP>   portainer.homelab.less
   <WSL_IP>   odysseus.homelab.less
   ```

4. Flush DNS in PowerShell (Admin):

   ```powershell
   ipconfig /flushdns
   ```

5. Start the stack:

   ```bash
   docker compose up -d
   ```

6. Visit `https://login.homelab.less` in a private browser window. Log in with
   `matandreoli` / `ChangeMe!2026`, then **change the password** (top-right
   user menu → Change Password). Optionally enroll a TOTP device, then flip
   `authelia/configuration.yml` from `default_policy: one_factor` to
   `default_policy: two_factor` and restart Authelia.
7. After login, you'll land on `https://dash.homelab.less`. All other `*.homelab.less`
   URLs work without re-authenticating (session cookie on `homelab.less` covers them all).

### Configuring internal monitors (Kuma + Homepage)

Kuma and Homepage's siteMonitor probe services periodically. If they hit the
public `*.homelab.less` URLs through Caddy, Authelia returns 302 → monitors mark
services down.

**Fix: point monitors at internal Docker DNS instead.** No Caddy, no Authelia,
no TLS overhead.

In Uptime-Kuma, change each monitor's URL:

- `https://pdf.homelab.less` → `http://stirling-pdf:8080`
- `https://status.homelab.less` → `http://uptime-kuma:3001`
- `https://dash.homelab.less` → `http://homepage:3000`
- `https://tools.homelab.less` → `http://it-tools:80`
- `https://portainer.homelab.less` → `http://portainer:9000`
- `https://login.homelab.less` → `http://authelia:9091`

In `homepage/services.yaml`, the user-facing `href:` stays as `https://*.homelab.less`
(clickable links). The `widget.url` and `siteMonitor:` fields should be the
internal Docker URL:

```yaml
- Uptime Kuma:
    href: https://status.homelab.less # user click target
    siteMonitor: http://uptime-kuma:3001 # internal probe
    widget:
      type: uptimekuma
      url: http://uptime-kuma:3001 # internal API
```

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
  # Internal port: <PORT> (proxied by Caddy as <service>.homelab.less)
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
http://<service>.homelab.less {
    redir https://<service>.homelab.less{uri} permanent
}

https://<service>.homelab.less {
    import secure_headers
    tls /certs/<service>.homelab.less.pem /certs/<service>.homelab.less.key
    import authelia
    reverse_proxy <service-name>:<PORT>
}
```

The `import authelia` line gates the new route behind SSO. Omit it only if
the service must be publicly reachable (e.g. a public read-only status page);
in that case also add a `bypass` rule in `authelia/configuration.yml` if the
default `one_factor` policy would otherwise redirect anonymous users.

If the service runs **on the WSL host** (outside this compose stack), point at the host IP:

```caddyfile
reverse_proxy <WSL_IP>:<PORT>
```

Don't forget to generate a TLS cert for the new hostname:

```bash
cd /home/matandreoli/homelab
mkcert -cert-file certs/<service>.homelab.less.pem -key-file certs/<service>.homelab.less.key <service>.homelab.less
```

### 3. Windows hosts snippet

Append to `C:\Windows\System32\drivers\etc\hosts` (open as Administrator):

```
<WSL_IP>   <service>.homelab.less
```

Then `ipconfig /flushdns` in PowerShell (Admin). In Zen/Firefox, open a private window (`Ctrl+Shift+P`) for the first visit to bypass the browser DNS cache.

---

## Common service ports

Cheat sheet for apps you might add. Always verify against the image's current docs — default ports change.

| App             | Image                                        | Port  | Hostname suggestion                          |
| --------------- | -------------------------------------------- | ----- | -------------------------------------------- |
| Uptime Kuma     | `louislam/uptime-kuma:2`                     | 3001  | `status.homelab.less`                          |
| Vaultwarden     | `vaultwarden/server:latest`                  | 80    | `vault.homelab.less`                           |
| Portainer CE    | `portainer/portainer-ce:latest`              | 9000  | `portainer.homelab.less`                       |
| Dockge          | `louislam/dockge:1`                          | 5001  | `dockge.homelab.less`                          |
| Homarr          | `ghcr.io/homarr-labs/homarr:latest`          | 7575  | `dash.homelab.less` (or replace with Homepage) |
| Nextcloud       | `nextcloud:29-apache`                        | 80    | `cloud.homelab.less`                           |
| Jellyfin        | `jellyfin/jellyfin:10.10`                    | 8096  | `media.homelab.less`                           |
| Navidrome       | `deluan/navidrome:latest`                    | 4533  | `music.homelab.less`                           |
| Immich          | `ghcr.io/immich-app/immich-server:release`   | 2283  | `photos.homelab.less`                          |
| Audiobookshelf  | `ghcr.io/advplyr/audiobookshelf:latest`      | 80    | `books.homelab.less`                           |
| Paperless-ngx   | `ghcr.io/paperless-ngx/paperless-ngx:latest` | 8000  | `docs.homelab.less`                            |
| Dozzle          | `amir20/dozzle:latest`                       | 8080  | `logs.homelab.less`                            |
| IT-Tools | `corentinth/it-tools:latest` | 80 | `tools.homelab.less` |
| Authelia | `authelia/authelia:4.39.x` | 9091 | `login.homelab.less` |
| Mealie          | `ghcr.io/mealie-recipes/mealie:latest`       | 9000  | `recipes.homelab.less`                         |
| Glances         | `nicolargo/glances:latest`                   | 61208 | `stats.homelab.less`                           |
| Homepage        | `ghcr.io/gethomepage/homepage:latest`        | 3000  | `hp.homelab.less`                              |
| Trilium Notes   | `zadam/trilium:latest`                       | 8080  | `notes.homelab.less`                           |
| Linkding        | `sissbruecker/linkding:latest`               | 9090  | `links.homelab.less`                           |
| Changedetection | `ghcr.io/dgtlmoon/changedetection.io:latest` | 5000  | `watch.homelab.less`                           |
| n8n             | `n8nio/n8n:latest`                           | 5678  | `n8n.homelab.less`                             |
| Excalidraw      | `excalidraw/excalidraw:latest`               | 80    | `draw.homelab.less`                            |
| Filebrowser     | `filebrowser/filebrowser:latest`             | 80    | `files.homelab.less`                           |

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
   mkcert -cert-file certs/login.homelab.less.pem     -key-file certs/login.homelab.less.key     login.homelab.less
   mkcert -cert-file certs/dash.homelab.less.pem      -key-file certs/dash.homelab.less.key      dash.homelab.less
   mkcert -cert-file certs/pdf.homelab.less.pem       -key-file certs/pdf.homelab.less.key       pdf.homelab.less
   mkcert -cert-file certs/status.homelab.less.pem    -key-file certs/status.homelab.less.key    status.homelab.less
   mkcert -cert-file certs/tools.homelab.less.pem     -key-file certs/tools.homelab.less.key     tools.homelab.less
   mkcert -cert-file certs/portainer.homelab.less.pem -key-file certs/portainer.homelab.less.key portainer.homelab.less
   mkcert -cert-file certs/odysseus.homelab.less.pem  -key-file certs/odysseus.homelab.less.key  odysseus.homelab.less
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
mkcert -cert-file certs/dash.homelab.less.pem -key-file certs/dash.homelab.less.key dash.homelab.less
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
