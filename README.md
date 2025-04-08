# 🌀 Proxy Gateway — Docker-based Proxy Pool with Dynamic Routing

This project launches an HTTP proxy server using [3proxy](https://3proxy.ru), which:

- Listens on local ports (5000+)
- Forwards traffic through external SOCKS5 proxies (from Flux API)
- Requires authentication (username/password)
- Dynamically generates the config on container startup

Perfect for:
- Routing traffic through a rotating pool of proxies
- Avoiding IP bans or blocks
- Managing multiple exit IPs through ports

## ⚙️ Technology Stack

- **Docker + Docker Compose**
- **3proxy** — lightweight, configurable proxy server
- **Bash + curl + jq** — used for config generation

## 📦 Environment Variables

| Variable         | Description                                                | Default Value         |
|------------------|------------------------------------------------------------|------------------------|
| `CLIENT_USER`    | Username for clients using this proxy                      | `client`              |
| `CLIENT_PASS`    | Password for clients                                       | `clientpass`          |
| `REMOTE_USER`    | Username for upstream SOCKS5 proxy                         | `proxyuser`           |
| `REMOTE_PASS`    | Password for upstream SOCKS5 proxy                         | `proxypass`           |
| `REMOTE_PORT`    | Port used by upstream proxies                              | `3405`                |
| `API_URL`        | API URL that returns proxy list (in JSON)                 | `https://api.runonflux.io/apps/location/proxypoolusa` |
| `START_PORT`     | Port to start mapping local proxies from                   | `5000`                |

## 🚀 Quick Start

1. Clone the repo:

```bash
git clone https://github.com/<your-user>/proxy-gateway.git
cd proxy-gateway
```

2. Edit `docker-compose.yml` or `.env` with your own credentials.

3. Build and run the container:

```bash
docker-compose up --build -d
```

4. Use any of the exposed ports (e.g. 5000) as a proxy:

```
http://<CLIENT_USER>:<CLIENT_PASS>@<SERVER_IP>:5000
```

## 🔍 Test a Proxy

```bash
curl -x http://client:clientpass@127.0.0.1:5000 https://api.ipify.org
```

## 📜 Sample Output

```
[*] Starting 3proxy with config:
users client:CL:clientpass
auth strong
allow *
proxy -p5000 ...
parent 1000 socks5 47.185.27.119 3405 proxyuser proxypass
```

## 🔐 Notes

- Make sure your server's IP is allowed by upstream proxy providers.
- Optionally, add automatic validation/filtering of dead proxies.

## 🛠 Author

This project is for educational or personal use only.  
**Do not use it for spam, DDoS, or any activity that violates ToS.**
