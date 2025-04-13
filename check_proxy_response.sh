#!/bin/bash

CFG_PATH="/etc/3proxy.cfg"
MAX_TIME=3  # Максимально допустимая задержка (в секундах)

echo "🔍 Проверка parent-прокси на скорость отклика:"
echo "----------------------------------------------"

# Получаем все пары порт → IP из конфигурации
grep -E "socks -p|parent 1000 socks5" "$CFG_PATH" | paste - - | while IFS=$'\t' read -r socks parent; do
  port=$(echo "$socks" | grep -oP '\d+')
  ip=$(echo "$parent" | awk '{print $5}')
  login=$(echo "$parent" | awk '{print $6}')
  pass=$(echo "$parent" | awk '{print $7}')
  remote_port=$(echo "$parent" | awk '{print $4}')

  echo -n "🧪 Порт $port → $ip:$remote_port... "

  start=$(date +%s%3N)
  curl --socks5 "$login:$pass@$ip:$remote_port" -s --max-time 10 http://ip-api.com/json > /dev/null
  exit_code=$?
  end=$(date +%s%3N)
  elapsed=$((end - start))
  elapsed_s=$(echo "scale=2; $elapsed/1000" | bc)

  if [ "$exit_code" -eq 0 ]; then
    if (( elapsed > MAX_TIME * 1000 )); then
      echo "❌ $elapsed_s сек — медленно"
    else
      echo "✅ $elapsed_s сек — ок"
    fi
  else
    echo "❌ Ошибка подключения (timeout/блокировка)"
  fi
done
