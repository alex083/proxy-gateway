#!/bin/bash

API_URL=${API_URL:-https://api.runonflux.io/apps/location/proxypoolusa}
START_PORT=${START_PORT:-5000}
CLIENT_USER=${CLIENT_USER:-client}
CLIENT_PASS=${CLIENT_PASS:-clientpass}
REMOTE_USER=${REMOTE_USER:-proxyuser}
REMOTE_PASS=${REMOTE_PASS:-proxypass}
REMOTE_PORT=${REMOTE_PORT:-3405}

echo "Fetching proxy list..."
IP_LIST=$(curl -s "$API_URL" | jq -r '.data[].ip')

PORT=$START_PORT

echo "users $CLIENT_USER:CL:$CLIENT_PASS" > /etc/3proxy.cfg
echo "auth strong" >> /etc/3proxy.cfg
echo "allow *" >> /etc/3proxy.cfg

for IP in $IP_LIST; do
  IP_ONLY=$(echo "$IP" | cut -d':' -f1)

  echo "proxy -p$PORT -a -i0.0.0.0 -e0.0.0.0" >> /etc/3proxy.cfg
  echo "parent 1000 socks5 $IP_ONLY $REMOTE_PORT $REMOTE_USER $REMOTE_PASS" >> /etc/3proxy.cfg

  PORT=$((PORT+1))
done

echo "[*] Starting 3proxy with config:"
cat /etc/3proxy.cfg

/usr/local/3proxy/bin/3proxy /etc/3proxy.cfg
