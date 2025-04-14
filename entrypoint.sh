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
TMP_DIR="/tmp/configs-new"

mkdir -p "$CONFIG_DIR"
mkdir -p "$TMP_DIR"
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
  rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
  > "$TMP_DIR/proxies.txt"

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
    CFG="$TMP_DIR/3proxy_$PORT.cfg"
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
          echo "socks5://$CLIENT_USER:$CLIENT_PASS@<server_ip>:$i" >> "$TMP_DIR/proxies.txt"
        }
      done
    } > "$CFG"
  done

  save_proxy_map
}

hot_reload_configs() {
  echo "[*] Применение обновлений без даунтайма..."
  for CFG_NEW in "$TMP_DIR"/3proxy_*.cfg; do
    PORT=$(basename "$CFG_NEW" | sed -E 's/.*_([0-9]+)\\.cfg/\\1/')
    CFG_OLD="$CONFIG_DIR/3proxy_$PORT.cfg"

    if ! cmp -s "$CFG_NEW" "$CFG_OLD"; then
      echo "[~] Изменения на порту $PORT — перезапуск"
      pkill -f "3proxy $CFG_OLD" 2>/dev/null
      cp "$CFG_NEW" "$CFG_OLD"
      /usr/local/3proxy/bin/3proxy "$CFG_OLD" &
    else
      echo "[=] Порт $PORT — без изменений"
    fi
  done
  cp "$TMP_DIR/proxies.txt" "$CONFIG_DIR/proxies.txt"
}

# Первый запуск
generate_configs
hot_reload_configs

# Обновление каждый час
while true; do
  sleep 3600
  generate_configs
  hot_reload_configs
  echo "[*] Обновление завершено без прерывания доступа"
done
