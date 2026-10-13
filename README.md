# Laptop Squid proxy

Canonical's `ubuntu/squid:latest`, running through Docker Compose.
The initial image pulled on setup contains Squid 6.13 (ARM64).

## Connect from another PC

Use a **manual HTTP proxy**:

- Address: `192.168.1.94`
- Port: `43128` (an unused high, non-privileged port at setup)
- Username/password: not required initially
- Use the same proxy for HTTP and HTTPS. This is not a SOCKS proxy.

Both computers must be on the same LAN, with client isolation disabled.
HTTPS uses CONNECT tunneling; no custom certificate or TLS interception is needed.
Only destination ports 80 and 443 are allowed.

Test from the other PC (use `curl.exe` in Windows PowerShell):

```sh
curl --noproxy "" --proxy http://192.168.1.94:43128 https://example.com
```

The proxy binds only to this laptop's LAN IP. Its source ACL permits the
`192.168.1.0/24` subnet and the exact Docker Desktop gateway `192.168.65.1`,
which was observed replacing the original client IP during testing.
Because Docker may translate client addresses, Squid cannot reliably enforce
per-PC or LAN-subnet restrictions for translated connections; the LAN-only bind,
router and host firewall provide the network boundary. Do not forward this port
from your router or expose it to the internet. No-auth mode lets anyone who can
reach this LAN endpoint use the proxy.

## Manage

Run commands from this directory:

```sh
bash proxy.sh status
bash proxy.sh logs
bash proxy.sh stop
bash proxy.sh start
```

`start` explicitly selects **no-auth mode**, including after auth has been enabled.
Docker Compose configuration and Squid configuration are checked before startup.
The container restarts automatically while Docker is running. Docker Desktop must
be running and the laptop must be awake and connected to the LAN.

If DHCP changes the laptop IP, update `PROXY_BIND_IP` in [.env](.env), then
recreate the container in the desired mode. Update the `lan` ACL in
[squid.conf](squid.conf) if the subnet changes. A router DHCP reservation is
recommended. Do not disable the firewall; allow Docker incoming connections if
macOS prompts. Docker was already allowed at setup.

## Enable username/password later

```sh
bash proxy.sh auth myuser
```

This prompts twice for a hidden password, stores only a SHA-512 crypt hash in
the git-ignored `auth/passwords` file, and recreates the proxy with authentication
required for every request. This setup supports one user; rerunning the command
replaces that user's credentials. It does not widen LAN access.

Test: without credentials you should receive HTTP `407 Proxy Authentication Required`.
With credentials, curl prompts for the password rather than putting it in shell history:

```sh
curl --noproxy "" --proxy http://192.168.1.94:43128 https://example.com
curl --noproxy "" --proxy http://192.168.1.94:43128 --proxy-user myuser https://example.com
```

Basic proxy authentication is **not encrypted between the PC and the proxy**,
even when the destination uses HTTPS. Use it only on a trusted LAN; for untrusted
networks, use a VPN or a TLS-protected proxy instead.

To keep auth enabled when applying configuration changes or after pulling an image:

```sh
docker compose -f compose.yaml -f compose.auth.yaml up -d --force-recreate
```

To return to no-auth mode:

```sh
bash proxy.sh start
```

## Update the image

```sh
bash proxy.sh update
```

Then recreate in the desired mode as described above. Pulling alone does not
replace the running container or change its authentication mode.
