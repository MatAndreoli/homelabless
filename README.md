# Homelab

Self-hosted service stack on Windows + WSL2, fronted by Caddy as reverse proxy with Authelia SSO.

Last updated: 2026-06-20. Pinned versions: caddy 2.11, authelia 4.39.20, stirling-pdf 2.13.1, uptime-kuma 2, it-tools 2024.10.22-7ca5933, portainer 2.39.3, homepage v1.13.2.

## Architecture

```
              Windows browser
                    │
                    │ *.homelab.less (HTTP/HTTPS)
                    ▼
       ┌──── WSL2 (Docker daemon) ───────────┐
       │                                     │
       │  :80 / :443                         │
       │  ┌──────┐  forward_auth  ┌──────────┐
       │  │Caddy │ ──────────────▶│ Authelia │
       │  └──┬───┘   302 on miss  └──────────┘
       │     │  (reverse_proxy)              │
       │     ▼                               │
       │  ┌─────────┐  ┌──────┐  ┌────────┐  │
       │  │stirling │  │kuma  │  │it-tools│  │
       │  │  -pdf   │  │      │  │        │  │
       │  └─────────┘  └──────┘  └────────┘  │
       │  ┌────────┐  ┌──────────┐  ┌──────┐ │
       │  │homepage│  │ portainer│  │ login│ │
       │  │        │  │          │  │ UI   │ │
       │  └────────┘  └──────────┘  └──────┘ │
       │       all on `homelab` bridge net   │
       └─────────────────────────────────────┘
                    │
                    │ extra_hosts: WSL_HOST_IP
                    ▼
            ┌───────────────┐
            │  WSL host      │
            │  (odysseus)    │
            └───────────────┘
```

- All HTTP/HTTPS traffic enters via Caddy (no container publishes a host port except Caddy).
- Authelia gates every route via Caddy's `forward_auth`. A miss returns 302 → `login.homelab.less/?rd=...`.
- After login, session cookie lives on parent domain `homelab.less` and covers all `*.homelab.less`.
- WSL-host services (odysseus) are reached by IP via `extra_hosts` in compose + `reverse_proxy <WSL_IP>:<port>` in Caddyfile.

## Stack

| Service      | URL                              | Internal port | Purpose                                         | Auth                                 |
| ------------ | -------------------------------- | ------------- | ----------------------------------------------- | ------------------------------------ |
| Authelia     | <https://login.homelab.less>     | 9091          | SSO gate (login + 2FA)                          | —                                    |
| Homepage     | <https://dash.homelab.less>      | 3000          | Dashboard / launcher (primary entry point)      | required                             |
| Stirling-PDF | <https://pdf.homelab.less>       | 8080          | PDF tools (merge, split, OCR, convert)          | required                             |
| Uptime Kuma  | <https://status.homelab.less>    | 3001          | Uptime monitoring + alerts                      | required (except public status page) |
| IT-Tools     | <https://tools.homelab.less>     | 80            | Toolbox for devs (UUID, base64, JWT, hash, etc) | required                             |
| Portainer    | <https://portainer.homelab.less> | 9000          | Web UI for managing Docker                      | required                             |
| Odysseus     | <https://odysseus.homelab.less>  | (host port)   | Runs on WSL host, not in this stack             | required                             |

Internal port is what Caddy reverse-proxies to (`<container-name>:<port>`). Useful when adding monitors or wiring new services.

**Public paths** (no auth, see `Caddyfile`): `status.homelab.less/api/status-page/*`, `/api/badge/*`, `/api/incidents/*`, `/api/heartbeat/*`. These let external services embed a public status badge without an Authelia session.

## Files

| File / dir                   | Purpose                                                                                                              |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `docker-compose.yml`         | Service definitions: 7 containers, shared `homelab` network, healthchecks, log rotation, `x-logging` anchor.         |
| `Caddyfile`                  | Reverse proxy routes + global security headers. Uses `{{WSL_HOST_IP}}` placeholder (substituted at container start). |
| `caddy/entrypoint.sh`        | Substitutes `{{WSL_HOST_IP}}` in `Caddyfile` and starts Caddy.                                                       |
| `.env.example`               | Template for the `.env` secrets file. Copy to `.env` and fill in.                                                    |
| `.env`                       | Real secrets. **Never committed.**                                                                                   |
| `certs/`                     | TLS certs and mkcert root CA. **Not committed.**                                                                     |
| `authelia/configuration.yml` | Authelia config (cookie domain, ACL, secrets via `${VAR}`).                                                          |
| `authelia/users.yml`         | User database with bcrypt hash. **Gitignored.**                                                                      |
| `authelia/users.yml.example` | Template for `users.yml`. Committed.                                                                                 |
| `homepage/`                  | Homepage config (services, widgets, settings, images). Not committed.                                                |
| `stirling-data/`             | Stirling-PDF persistent state. Bind mount. Not committed.                                                            |
| `uptime-kuma-data/`          | Uptime Kuma persistent state. Bind mount. Not committed.                                                             |
| `homepage/logs/`             | Homepage access logs. Not committed.                                                                                 |
| `portainer_data`             | Docker named volume for Portainer's config.                                                                          |
| `authelia_data`              | Docker named volume for Authelia SQLite + notifications.                                                             |
| `caddy_data`, `caddy_config` | Docker named volumes for Caddy's cert cache and runtime config.                                                      |

## Network

Single shared bridge network named `homelab`. All services attach to it. Properties:

- **Service-name DNS**: every container can reach every other by name (`http://stirling-pdf:8080`, `http://uptime-kuma:3001`, etc). This is how Homepage widgets and Kuma monitors probe services without going through Caddy/Authelia/TLS — see [Configuring internal monitors](#configuring-internal-monitors-kuma--homepage).
- **No host port publishing** except Caddy (`80`, `443`). The `homelab` network is the only ingress. Reduces attack surface.
- **Host services (odysseus)** are reached by IP. Compose adds an `extra_hosts` entry mapping `WSL_HOST_IP` to the Docker bridge gateway so containers can dial the WSL host:

  ```yaml
  caddy:
    extra_hosts:
      - "host.docker.internal:host-gateway" # for any service that needs it
  ```

  Then in Caddyfile: `reverse_proxy <WSL_IP>:<port>` (the `<WSL_IP>` is substituted from `.env` at container start via `caddy/entrypoint.sh`).

## Volumes

Two kinds:

**Bind mounts** (data lives in the repo, easy to back up with `cp -a` or `rsync`):

- `./stirling-data/` → `/usr/share/tessdata` in stirling-pdf
- `./uptime-kuma-data/` → `/app/data` in uptime-kuma
- `./homepage/` → `/app/config` in homepage
- `./certs/` → `/certs` in caddy (read-only)
- `./authelia/configuration.yml` → `/config/configuration.yml` in authelia (read-only)
- `./authelia/users.yml` → `/config/users.yml` in authelia (read-only)

**Named volumes** (Docker-managed, only back up via `docker run --rm -v VOL busybox tar`):

- `caddy_data`, `caddy_config` — Caddy's cert cache + runtime config (lost on recreate, Caddy re-bootstraps)
- `portainer_data` — Portainer's config (containers, stacks, settings)
- `authelia_data` — Authelia's SQLite DB (sessions, TOTP secrets, notification queue)

See [Backups](#backups) for what to copy and how.

## Secrets

All in `.env` (gitignored, never committed). The repo ships `.env.example` as a template.

| Variable                          | Purpose                                   | How to generate               |
| --------------------------------- | ----------------------------------------- | ----------------------------- |
| `WSL_HOST_IP`                     | WSL2 eth0 IP (substituted into Caddyfile) | `hostname -I` in WSL          |
| `PORTAINER_API_KEY`               | Homepage widget talks to Portainer API    | Portainer UI → Settings → API |
| `AUTHELIA_JWT_SECRET`             | JWT signing key                           | `openssl rand -hex 32`        |
| `AUTHELIA_SESSION_SECRET`         | Session cookie encryption                 | `openssl rand -hex 32`        |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | SQLite DB encryption                      | `openssl rand -hex 32`        |

**Why are the 3 Authelia secrets separate?** Authelia v4.38+ separated the storage encryption key from the JWT/session secrets. All 3 are required. If you rotate `STORAGE_ENCRYPTION_KEY`, you must delete the `authelia_data` volume (`docker volume rm homelab_authelia_data`) — the DB can't be re-encrypted in place.

After editing `.env`, recreate affected containers:

```bash
docker compose up -d caddy authelia homepage
```

## First-time setup (after cloning)

1. **Bootstrap the environment**:

   ```bash
   cp .env.example .env
   $EDITOR .env   # fill in WSL_HOST_IP and the 3 Authelia secrets (openssl rand -hex 32)
   ```

2. **Install mkcert and generate the TLS certs** (see [HTTPS setup](#https-setup) below).

3. **Add hostnames to Windows** `C:\Windows\System32\drivers\etc\hosts` (open as Administrator). Use the same IP from step 1:

   ```
   <WSL_IP>   login.homelab.less
   <WSL_IP>   dash.homelab.less
   <WSL_IP>   pdf.homelab.less
   <WSL_IP>   status.homelab.less
   <WSL_IP>   tools.homelab.less
   <WSL_IP>   portainer.homelab.less
   <WSL_IP>   odysseus.homelab.less
   ```

4. **Flush DNS** in PowerShell (Admin):

   ```powershell
   ipconfig /flushdns
   ```

5. **Start the stack**:

   ```bash
   docker compose up -d
   ```

6. **Bootstrap Authelia**:

   ```bash
   htpasswd -nbBC 10 "" 'ChangeMe!2026' | tr -d ':\n' > /tmp/hash
   # paste the hash into authelia/users.yml under the `password:` field
   ```

   Add to `authelia/users.yml`:

   ```yaml
   users:
     matandreoli:
       displayname: "matandreoli"
       password: "<paste hash>"
       email: matandreoli@example.invalid
   ```

7. **Visit** `https://login.homelab.less` in a private browser window. Log in with `matandreoli` / `ChangeMe!2026`, then **change the password** (top-right user menu → Change Password). Optionally enroll a TOTP device, then flip `authelia/configuration.yml` from `default_policy: one_factor` to `default_policy: two_factor` and restart Authelia:

   ```bash
   docker compose up -d authelia
   ```

8. **Land on the dashboard** at `https://dash.homelab.less`. All other `*.homelab.less` URLs work without re-authenticating (session cookie on `homelab.less` covers them all).

### Renaming hostnames (e.g. `.home` → `.homelab.less`)

The single-user case is rare; multi-day if you have multiple stacks. Steps:

1. Update `authelia/configuration.yml` → `cookies.domain`, the `bypass:` rules, and any ACL entries.
2. Rename all certs in `certs/`: delete old, generate new with mkcert.
3. Update the Caddyfile (every `https://...` line + the `WSL_HOST_IP` substitution list).
4. Update `homepage/services.yaml` (every `href:` and `siteMonitor:` URL).
5. Update `uptime-kuma-data/` (manually via the UI, or wipe and re-add monitors).
6. Update Windows `hosts` (delete old entries, add new) + `ipconfig /flushdns`.
7. Restart everything: `docker compose up -d`.

## Adding a new service

Four places to touch per new service:

1. `docker-compose.yml` — service block (snippet below).
2. `Caddyfile` — HTTP redirect + HTTPS vhost with `import authelia` (snippet below).
3. `certs/` — generate a TLS cert with mkcert.
4. Windows `hosts` — add `<WSL_IP> <service>.homelab.less`.

Then reload:

```bash
docker compose up -d
```

If only the Caddyfile changed, `caddy reload` is enough (but the `{{WSL_HOST_IP}}` placeholder only re-renders at container start, so a Caddyfile that uses it needs a container restart, not just `reload`).

### 1. docker-compose.yml snippet

```yaml
<service-name>:
  image: <image>:<pinned-tag>           # pin a tag, not :latest
  container_name: <service-name>
  restart: unless-stopped
  logging: *default-logging             # 10m × 3 rotation, see top of compose
  healthcheck:
    test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:<PORT>/"]
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 30s
  environment:
    # - KEY=value   # uncomment if the service needs config
  volumes:
    - ./<service-name>-data:/data
  networks:
    - homelab
```

If the service runs on the **WSL host** (not in this stack), use `extra_hosts` so Caddy can reach it:

```yaml
caddy:
  # already has these — add to whatever service needs host access
  extra_hosts:
    - "host.docker.internal:host-gateway"
```

If the service has **no persistent state**, omit the `volumes:` block. If it needs a **sidecar** (DB, cache), add another service in the same compose file on the `homelab` network.

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

`import authelia` gates the route behind SSO. **Omit it** only if the service must be publicly reachable (e.g. a public read-only status page). In that case also add a `bypass` rule in `authelia/configuration.yml` (under `access_control.rules`) so the default `one_factor` policy doesn't redirect anonymous users.

If the service has **public sub-paths** (like Kuma's `/api/status-page/*`), split the handler:

```caddyfile
https://<service>.homelab.less {
    import secure_headers
    tls /certs/<service>.homelab.less.pem /certs/<service>.homelab.less.key

    @public path /api/status-page/* /api/badge/* /api/heartbeat/* /api/incidents/*
    handle @public {
        reverse_proxy <service-name>:<PORT>
    }
    handle {
        import authelia
        reverse_proxy <service-name>:<PORT>
    }
}
```

If the service runs **on the WSL host**:

```caddyfile
reverse_proxy <WSL_IP>:<PORT>   # <WSL_IP> substituted from .env at container start
```

### 3. Generate the TLS cert

```bash
cd /home/matandreoli/homelab
mkcert -cert-file certs/<service>.homelab.less.pem \
       -key-file  certs/<service>.homelab.less.key  \
       <service>.homelab.less
```

### 4. Windows hosts

Append to `C:\Windows\System32\drivers\etc\hosts` (Administrator):

```
<WSL_IP>   <service>.homelab.less
```

Then `ipconfig /flushdns` in PowerShell (Admin). In Zen/Firefox, open a private window (`Ctrl+Shift+P`) for the first visit to bypass the browser DNS cache.

## Adding a new Authelia user

1. Generate a bcrypt hash (cost 10):

   ```bash
   htpasswd -nbBC 10 "" '<password>' | tr -d ':\n'
   ```

   The output looks like `$2a$10$...`.

2. Append to `authelia/users.yml`:

   ```yaml
   users:
     <username>:
       displayname: "<Display Name>"
       password: "<bcrypt hash from step 1>"
       email: <user>@example.invalid
   ```

3. No restart needed — Authelia watches `users.yml` for changes. New user logs in immediately.

**Reset a forgotten password**: regenerate the hash, replace the `password:` line, save. Next login uses the new password.

## Configuring internal monitors (Kuma + Homepage)

Kuma and Homepage's siteMonitor probe services periodically. If they hit the public `*.homelab.less` URLs through Caddy, Authelia returns 302 → monitors mark services down.

**Fix: point monitors at internal Docker DNS instead.** No Caddy, no Authelia, no TLS overhead.

In Uptime-Kuma, change each monitor's URL:

- `https://pdf.homelab.less` → `http://stirling-pdf:8080`
- `https://status.homelab.less` → `http://uptime-kuma:3001`
- `https://dash.homelab.less` → `http://homepage:3000`
- `https://tools.homelab.less` → `http://it-tools:80`
- `https://portainer.homelab.less` → `http://portainer:9000`
- `https://login.homelab.less` → `http://authelia:9091/api/health`

In `homepage/services.yaml`, the user-facing `href:` stays as `https://*.homelab.less` (clickable links). The `widget.url` and `siteMonitor:` fields should be the internal Docker URL:

```yaml
- Uptime Kuma:
    href: https://status.homelab.less # user click target
    siteMonitor: http://uptime-kuma:3001 # internal probe (no Authelia)
    widget:
      type: uptimekuma
      url: http://uptime-kuma:3001 # internal API
```

---

## Common service ports

Cheat sheet for apps you might add. **Always verify against the image's current docs** — default ports change. The `Image` column shows the `:latest` reference; in this stack we pin tags in `docker-compose.yml`.

| App             | Image                                        | Port  | Hostname suggestion                     |
| --------------- | -------------------------------------------- | ----- | --------------------------------------- |
| Uptime Kuma     | `louislam/uptime-kuma:2`                     | 3001  | `status.homelab.less`                   |
| Vaultwarden     | `vaultwarden/server:latest`                  | 80    | `vault.homelab.less`                    |
| Portainer CE    | `portainer/portainer-ce:latest`              | 9000  | `portainer.homelab.less`                |
| Dockge          | `louislam/dockge:1`                          | 5001  | `dockge.homelab.less`                   |
| Homarr          | `ghcr.io/homarr-labs/homarr:latest`          | 7575  | `dash.homelab.less` (replaces Homepage) |
| Nextcloud       | `nextcloud:29-apache`                        | 80    | `cloud.homelab.less`                    |
| Jellyfin        | `jellyfin/jellyfin:10.10`                    | 8096  | `media.homelab.less`                    |
| Navidrome       | `deluan/navidrome:latest`                    | 4533  | `music.homelab.less`                    |
| Immich          | `ghcr.io/immich-app/immich-server:release`   | 2283  | `photos.homelab.less`                   |
| Audiobookshelf  | `ghcr.io/advplyr/audiobookshelf:latest`      | 80    | `books.homelab.less`                    |
| Paperless-ngx   | `ghcr.io/paperless-ngx/paperless-ngx:latest` | 8000  | `docs.homelab.less`                     |
| Dozzle          | `amir20/dozzle:latest`                       | 8080  | `logs.homelab.less`                     |
| IT-Tools        | `corentinth/it-tools:latest`                 | 80    | `tools.homelab.less`                    |
| Authelia        | `authelia/authelia:4.39.x`                   | 9091  | `login.homelab.less`                    |
| Mealie          | `ghcr.io/mealie-recipes/mealie:latest`       | 9000  | `recipes.homelab.less`                  |
| Glances         | `nicolargo/glances:latest`                   | 61208 | `stats.homelab.less`                    |
| Homepage        | `ghcr.io/gethomepage/homepage:latest`        | 3000  | `hp.homelab.less`                       |
| Trilium Notes   | `zadam/trilium:latest`                       | 8080  | `notes.homelab.less`                    |
| Linkding        | `sissbruecker/linkding:latest`               | 9090  | `links.homelab.less`                    |
| Changedetection | `ghcr.io/dgtlmoon/changedetection.io:latest` | 5000  | `watch.homelab.less`                    |
| n8n             | `n8nio/n8n:latest`                           | 5678  | `n8n.homelab.less`                      |
| Excalidraw      | `excalidraw/excalidraw:latest`               | 80    | `draw.homelab.less`                     |
| Filebrowser     | `filebrowser/filebrowser:latest`             | 80    | `files.homelab.less`                    |

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

5. Optionally delete the data folder `./<service-name>-data/` (bind mount) or the named volume (`docker volume rm homelab_<name>`).

---

## Updating image versions

```bash
docker compose pull
docker compose up -d
```

Image tags are pinned in `docker-compose.yml`. To upgrade a service to a new major version, edit the tag manually and re-pull. After a major version bump, check the service's release notes for breaking changes to config files, env vars, or volume formats.

---

## Backups

Five things to back up, in priority order:

1. `authelia/users.yml` — user database. Without this, all users are locked out.
2. `authelia_data` volume — Authelia's SQLite (TOTP secrets, sessions, notifications). Backup:

   ```bash
   docker run --rm -v homelab_authelia_data:/data -v "$PWD":/backup alpine \
       tar czf /backup/authelia_data_$(date +%F).tgz -C /data .
   ```

3. `./stirling-data/` — user-uploaded PDFs, OCR data, settings. `rsync` or `tar`.
4. `./uptime-kuma-data/` — monitors, status pages, history. Same.
5. `./homepage/` — services.yaml, widgets, bookmarks, settings. Same.

`portainer_data`, `caddy_data`, `caddy_config` are not critical — Portainer re-discovers containers; Caddy regenerates its cert cache on first run.

Recovery: restore the directory or volume, then `docker compose up -d <service>`.

---

## Troubleshooting

- **Browser hits a public IP instead of the WSL service:** Zen/Firefox is caching an old DNS. Open in a private window (`Ctrl+Shift+P`) or clear `about:config` → `network.dnsCacheEntries` → 0.
- **Caddy 502 on a route:** the upstream service isn't running, or `extra_hosts` doesn't reach the WSL host. Check `docker compose ps` and `docker exec caddy wget http://service:port/`.
- **WSL IP changed after reboot:** run `hostname -I` in WSL, then update **only** `WSL_HOST_IP` in `.env` and the matching lines in Windows `hosts`. Restart Caddy: `docker compose up -d caddy`. The `Caddyfile` placeholder `{{WSL_HOST_IP}}` is substituted at Caddy container start.
- **`docker compose up -d` didn't pick up my change:** env-only or label changes require a recreate, not a restart. Use `docker compose up -d --force-recreate <service>` or recreate the whole stack. To see what's actually in effect: `docker compose config`.
- **Caddyfile change not active:** `caddy reload` updates the running config, but if the Caddyfile uses `{{WSL_HOST_IP}}` it only re-renders at container start. After editing the Caddyfile placeholder logic, `docker compose up -d caddy` (not just `caddy reload`).
- **Authelia returns 302 instead of letting me through:** your session cookie isn't set. Either you haven't logged in yet, or the cookie domain doesn't match. The cookie is on parent domain `homelab.less` — any `*.homelab.less` URL should work. If you came in via a different TLD (e.g. `127.0.0.1:port`), it won't.
- **Authelia 401 after password change:** expected. Log in again with the new password. Sessions don't survive password rotation.
- **Browser warns about untrusted cert:** the mkcert root CA isn't installed in your browser. See [HTTPS setup](#https-setup) below. Zen/Firefox keeps its own trust store — restart the browser after importing.
- **Portainer is empty / doesn't see the other stacks:** Portainer only sees containers it can reach via the Docker socket. If you want to manage stacks in other compose projects (e.g. `odysseus`, `cartus`) from Portainer, run them on the same Docker daemon with compose files in a known location, then add the parent directory in Portainer → Stacks → Add stack.
- **Service marked down in Kuma/Homepage but the URL works in a browser:** the monitor is hitting the public `*.homelab.less` URL, getting 302 from Authelia. Switch the monitor URL to the internal Docker DNS (see [Configuring internal monitors](#configuring-internal-monitors-kuma--homepage)).
- **`HOMEPAGE_ALLOWED_HOSTS` not effective:** env var change requires a recreate, not a restart: `docker compose up -d homepage`.

---

## HTTPS setup

This stack uses [mkcert](https://github.com/FiloSottile/mkcert) to issue local TLS certificates signed by a private CA. Browsers trust them only if the mkcert root CA is installed in their trust store. No public CA, no domain, no internet required.

### One-time setup (per machine)

1. Install mkcert:

   ```bash
   sudo apt install mkcert
   ```

2. Install the mkcert root CA into the Linux trust store (also handles browsers running inside WSL):

   ```bash
   mkcert -install
   ```

3. Generate a cert per hostname. The certs land in `./certs/` and are bind-mounted into Caddy at `/certs/`:

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

   Portainer also needs the mkcert root CA to validate HTTPS on the other services it monitors. Mount it into the container:

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

   To trust from native Windows tools (PowerShell, curl.exe, etc), also import the cert into the Windows trust store via `certmgr.msc`.

5. Recreate the Caddy container so the new volume mount takes effect:

   ```bash
   docker compose up -d caddy
   ```

### Renewing certs

mkcert certs are valid for ~2 years. To regenerate (same commands overwrite the existing files):

```bash
cd /home/matandreoli/homelab
mkcert -cert-file certs/dash.homelab.less.pem -key-file certs/dash.homelab.less.key dash.homelab.less
# ... repeat for other hostnames
docker compose up -d caddy
```

The mkcert root CA itself doesn't expire but you can check its status with `mkcert -CAROOT`.

### Why not Let's Encrypt?

LE requires a public domain and DNS pointing to a public IP, plus an ACME challenge on port 80 (or DNS challenge). This stack is on a private WSL2 network with no public domain, so LE is not an option. mkcert gives a "real" HTTPS experience (green padlock, valid TLS 1.3, HSTS) without any of that.

---

## Decision log

Why this stack is the way it is:

- **`.homelab.less` TLD**: not a real TLD (reserved/invalid per RFC 6761), so DNS can never leak. `.local` is mDNS-reserved and breaks in some setups. `.home` is real and may collide.
- **Caddy over Nginx/Traefik**: zero-config HTTPS, native `forward_auth` support, single binary, Caddyfile is shorter than nginx.conf. Traefik's labels-on-everything model gets messy with 7+ services.
- **Authelia over Authentik**: 1 user, single Go binary + SQLite, no Postgres/Redis overhead. Authentik is a Kubernetes-grade IdP for orgs with dozens of users and OAuth clients.
- **Authelia 4.39 over 4.38**: 4.38+ moved `storage.encryption_key` to its own field. We pin 4.39.20 because 4.40 changed `/api/firstfactor` path semantics.
- **mkcert over LE**: no public domain needed, no port 80 ACME challenge, works offline.
- **`homelab` bridge network over host networking**: isolation + service-name DNS + no port collision.
- **No `ports:` except Caddy**: each published port is a potential attack surface. Caddy is the only entry; everything else is internal DNS.
- **Pinned image tags**: reproducibility. `:latest` rotates underneath you; you don't notice the breaking config change until 3am.
- **Named volumes for secrets, bind mounts for everything else**: secrets are opaque to `ls` and survive repo moves; bind mounts are `cp -a` to back up.
- **Default policy `one_factor`, not `deny`**: `deny` returns 403 to anonymous, which confuses external integrations. `one_factor` returns 302 → login, which works for both humans and OAuth callbacks.
- **x-logging anchor (10m × 3)**: bounded disk usage, ~30MB/container. Enough to debug "what happened yesterday", small enough to not fill a disk.
- **Healthchecks everywhere**: lets Docker restart failed services. `wget` is in every base image; `curl` is not (stirling-pdf, it-tools had to be added explicitly).
- **Public status page paths exempted from Authelia**: the whole point of a status page is to be public. 4 paths exempt; everything else requires login.

---

## Glossary

- **SSO** — Single Sign-On. One login covers multiple apps.
- **`forward_auth`** — Caddy delegates the auth check to an external service (here Authelia). On miss: 302 to login. On pass: request proceeds to upstream.
- **mkcert** — local CA for issuing browser-trusted TLS certs without a public domain.
- **Bind mount** — `host_path:container_path`. Data lives on the host filesystem. Easy to back up.
- **Named volume** — Docker-managed, not visible on host. Back up with `docker run --rm -v VOL busybox tar`.
- **`extra_hosts`** — adds entries to a container's `/etc/hosts`. Used here so containers can resolve `host.docker.internal` to the WSL host.
- **Cookie domain** — the parent domain a session cookie is scoped to. `homelab.less` covers all `*.homelab.less`.
- **`bypass` (Authelia ACL)** — rule that lets requests through without any factor. Used for public sub-paths.
- **`one_factor` / `two_factor`** — Authelia policies: password-only vs password+TOTP. We default to `one_factor`, flip to `two_factor` after enrolling.
- **`siteMonitor` (Homepage)** — a per-service health probe. Should use internal Docker URL, not public HTTPS.
