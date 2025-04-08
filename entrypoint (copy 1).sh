#!/bin/bash

set -e

API_URL=${API_URL:-https://api.runonflux.io/apps/location/proxypoolusa}
START_PORT=${START_PORT:-5000}
END_PORT=${END_PORT:-5055}
CLIENT_USER=${CLIENT_USER:-client}
CLIENT_PASS=${CLIENT_PASS:-clientpass}
REMOTE_USER=${REMOTE_USER:-proxyuser}
REMOTE_PASS=${REMOTE_PASS:-proxypass}
REMOTE_PORT=${REMOTE_PORT:-3405}

generate_config() {
  echo "Fetching proxy list..."
  IP_LIST=$(curl -s "$API_URL" | jq -r '.data[].ip')

  PORT=$START_PORT
  echo "nserver 8.8.8.8" > /etc/3proxy.cfg
  echo "nscache 65536" >> /etc/3proxy.cfg
  echo "users $CLIENT_USER:CL:$CLIENT_PASS" > /etc/3proxy.cfg
  echo "auth strong" >> /etc/3proxy.cfg
  echo "allow *" >> /etc/3proxy.cfg

  for IP in $IP_LIST; do
    [[ $PORT -gt $END_PORT ]] && break
    IP_ONLY=$(echo "$IP" | cut -d':' -f1)

    echo "socks -p$PORT -a -i0.0.0.0 -e0.0.0.0" >> /etc/3proxy.cfg
    echo "parent 1000 socks5 $IP_ONLY $REMOTE_PORT $REMOTE_USER $REMOTE_PASS" >> /etc/3proxy.cfg

    PORT=$((PORT+1))
  done
}

# Первая генерация и запуск
generate_config
echo "[*] Starting 3proxy..."
/usr/local/3proxy/bin/3proxy /etc/3proxy.cfg &

# Обновляем список раз в час
while true; do
  sleep 3600
  echo "[*] Updating proxy list..."
  generate_config
  echo "[*] Restarting 3proxy..."
  pkill -f 3proxy
  /usr/local/3proxy/bin/3proxy /etc/3proxy.cfg &
done
