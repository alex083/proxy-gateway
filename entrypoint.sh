#!/bin/bash

API_URL=${API_URL:-https://api.runonflux.io/apps/location/proxypoolusa}
START_PORT=${START_PORT:-5000}
END_PORT=${END_PORT:-5055}
CLIENT_USER=${CLIENT_USER:-client}
CLIENT_PASS=${CLIENT_PASS:-clientpass}
REMOTE_USER=${REMOTE_USER:-proxyuser}
REMOTE_PASS=${REMOTE_PASS:-proxypass}
REMOTE_PORT=${REMOTE_PORT:-3405}
MAX_PARALLEL=10
PROXY_MAP_FILE="/proxy-map.txt"
CONFIG_DIR="/configs"

declare -A PORT_MAP
declare -A USED_IPS

load_proxy_map() {
  if [[ -f "$PROXY_MAP_FILE" ]]; then
    while IFS=":" read -r port ip; do
      PORT_MAP["$port"]="$ip"
      USED_IPS["$ip"]=1
    done < "$PROXY_MAP_FILE"
  fi
}

save_proxy_map() {
  > "$PROXY_MAP_FILE"
  for port in "${!PORT_MAP[@]}"; do
    echo "$port:${PORT_MAP[$port]}" >> "$PROXY_MAP_FILE"
  done
}

check_proxy() {
  local ip=$1
  timeout 6 curl --silent --socks5-hostname "$REMOTE_USER:$REMOTE_PASS@$ip:$REMOTE_PORT" http://ip-api.com/json | jq -r '.query' | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  return $?
}

generate_configs() {
  echo "[*] Генерация конфигураций..."
  load_proxy_map
  rm -rf "$CONFIG_DIR"/*
  mkdir -p "$CONFIG_DIR"
  > /proxies.txt

  echo "[*] Проверка текущих прокси..."
  for ((PORT=START_PORT; PORT<=END_PORT; PORT++)); do
    IP=${PORT_MAP[$PORT]}
    if [[ -n "$IP" ]]; then
      if check_proxy "$IP"; then
        USED_IPS["$IP"]=1
        echo "[✓] $IP на порту $PORT — рабочий"
        continue
      else
        echo "[-] $IP на порту $PORT — нерабочий"
        unset PORT_MAP["$PORT"]
        unset USED_IPS["$IP"]
      fi
    fi
  done

  echo "[*] Получаем IP из API..."
  IP_LIST=$(curl -s "$API_URL" | jq -r '.data[].ip' | cut -d':' -f1)
  echo "$IP_LIST" > /tmp/iplist.txt

  parallel_jobs=0
  for IP in $IP_LIST; do
    [[ ${USED_IPS[$IP]} ]] && continue
    for ((PORT=START_PORT; PORT<=END_PORT; PORT++)); do
      if [[ -z "${PORT_MAP[$PORT]}" ]]; then
        if check_proxy "$IP"; then
          echo "[+] Назначен $IP на порт $PORT"
          PORT_MAP["$PORT"]="$IP"
          USED_IPS["$IP"]=1
          break
        fi
      fi
    done
  done

  echo "[*] Генерация конфигов по блокам..."
  for ((PORT=START_PORT; PORT<=END_PORT; PORT+=5)); do
    CFG="$CONFIG_DIR/3proxy_$PORT.cfg"
    {
      echo "nserver 8.8.8.8"
      echo "nscache 65536"
      echo "users $CLIENT_USER:CL:$CLIENT_PASS"
      echo "auth strong"
      echo "allow *"
      for ((i=PORT; i<PORT+5 && i<=END_PORT; i++)); do
        IP=${PORT_MAP[$i]}
        [[ -n "$IP" ]] && {
          echo "parent 1000 socks5 $IP $REMOTE_PORT $REMOTE_USER $REMOTE_PASS"
          echo "socks -p$i -a -i0.0.0.0"
          echo "socks5://$CLIENT_USER:$CLIENT_PASS@<server_ip>:$i" >> /proxies.txt
        }
      done
    } > "$CFG"
  done

  save_proxy_map
}

start_all_3proxy() {
  echo "[*] Запуск 3proxy-процессов..."
  for cfg in "$CONFIG_DIR"/*.cfg; do
    /usr/local/3proxy/bin/3proxy "$cfg" &
  done
}

stop_all_3proxy() {
  echo "[*] Остановка всех процессов 3proxy..."
  pkill -f 3proxy
}

# Первый запуск
generate_configs && start_all_3proxy

# Обновление каждый час
while true; do
  sleep 3600
  stop_all_3proxy
  generate_configs && start_all_3proxy
done
