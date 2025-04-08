#!/bin/bash

API_URL=${API_URL:-https://api.runonflux.io/apps/location/proxypoolusa}
START_PORT=${START_PORT:-5000}
END_PORT=${END_PORT:-5055}
CLIENT_USER=${CLIENT_USER:-client}
CLIENT_PASS=${CLIENT_PASS:-clientpass}
REMOTE_USER=${REMOTE_USER:-proxyuser}
REMOTE_PASS=${REMOTE_PASS:-proxypass}
REMOTE_PORT=${REMOTE_PORT:-3405}

generate_config() {
  echo "[*] Получаем список прокси..."
  IP_LIST=$(curl -s "$API_URL" | jq -r '.data[].ip')

  PORT=$START_PORT
  : > /etc/3proxy.cfg
  : > /proxies.txt

  echo "nserver 8.8.8.8" >> /etc/3proxy.cfg
  echo "nscache 65536" >> /etc/3proxy.cfg
  echo "users $CLIENT_USER:CL:$CLIENT_PASS" >> /etc/3proxy.cfg
  echo "auth strong" >> /etc/3proxy.cfg
  echo "allow *" >> /etc/3proxy.cfg

  for IP in $IP_LIST; do
    if [ "$PORT" -gt "$END_PORT" ]; then
      break
    fi

    IP_ONLY=$(echo "$IP" | cut -d':' -f1)

    # Пытаемся проверить parent напрямую
    echo "[*] Проверка $IP_ONLY..."
    timeout 6 curl --silent --socks5-hostname "$REMOTE_USER:$REMOTE_PASS@$IP_ONLY:$REMOTE_PORT" http://ip-api.com/json > /dev/null

    if [ $? -eq 0 ]; then
      echo "[+] Добавляем рабочий прокси на порт $PORT ($IP_ONLY)"
      echo "socks -p$PORT -a -i0.0.0.0" >> /etc/3proxy.cfg
      echo "parent 1000 socks5 $IP_ONLY $REMOTE_PORT $REMOTE_USER $REMOTE_PASS" >> /etc/3proxy.cfg
      echo "socks5://$CLIENT_USER:$CLIENT_PASS@<server_ip>:$PORT" >> /proxies.txt
      PORT=$((PORT + 1))
    else
      echo "[-] Пропускаем $IP_ONLY — не отвечает"
    fi
  done
}

generate_config
echo "[*] Запуск 3proxy..."
/usr/local/3proxy/bin/3proxy /etc/3proxy.cfg &

# Обновление раз в час
while true; do
  sleep 3600
  echo "[*] Обновление списка прокси..."
  pkill -f 3proxy
  generate_config
  /usr/local/3proxy/bin/3proxy /etc/3proxy.cfg &
done
