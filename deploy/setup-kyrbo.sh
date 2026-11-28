#!/usr/bin/env bash
# Установка/обновление сервера «Блок Бум!» на VPS с Caddy (kyrbo.com).
# Запуск на сервере одной командой:
#   curl -fsSL https://raw.githubusercontent.com/Mu7ic/block_boom/godot-port/deploy/setup-kyrbo.sh | sudo bash
# Повторный запуск безопасен: обновит код и перезапустит сервис.
set -euo pipefail

DOMAIN="${DOMAIN:-kyrbo.com}"
BRANCH="${BRANCH:-godot-port}"
DIR=/opt/blockboom
CADDYFILE=/etc/caddy/Caddyfile

step() { echo; echo "=== $* ==="; }

if [ "$(id -u)" -ne 0 ]; then
  echo "Нужны права root. Запустите так:  curl -fsSL https://raw.githubusercontent.com/Mu7ic/block_boom/godot-port/deploy/setup-kyrbo.sh | sudo bash"
  exit 1
fi

step "1/6 Node.js"
if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 18 ]; then
  apt-get update -y
  apt-get install -y curl ca-certificates git
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
command -v git >/dev/null || apt-get install -y git
node -v

step "2/6 Код игры ($BRANCH)"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch origin
  git -C "$DIR" checkout "$BRANCH"
  git -C "$DIR" pull --ff-only origin "$BRANCH"
else
  git clone -b "$BRANCH" https://github.com/Mu7ic/block_boom.git "$DIR"
fi

step "3/6 Зависимости и APK"
cd "$DIR/server"
npm install --omit=dev --no-audit --no-fund
# APK для страницы kyrbo.com/blockboom — последняя версия из GitHub Releases
if curl -fsSL -o "$DIR/site/BlockBoom.apk.new" https://github.com/Mu7ic/block_boom/releases/latest/download/BlockBoom.apk; then
  mv -f "$DIR/site/BlockBoom.apk.new" "$DIR/site/BlockBoom.apk"
  echo "APK: $(du -h "$DIR/site/BlockBoom.apk" | cut -f1)"
else
  echo "APK не скачан — страница будет отдавать ссылку на GitHub"
fi

# Где Caddy: в Docker-контейнере (образ caddy:*) или обычным сервисом.
# Из контейнера 127.0.0.1 — это сам контейнер, поэтому сервер игры слушает адрес
# шлюза Docker-сети (он виден только контейнерам и самому серверу, не из интернета).
CADDY_CT=$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | awk '$2 ~ /^caddy/ {print $1; exit}' || true)
if [ -n "$CADDY_CT" ]; then
  NET=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$CADDY_CT" | awk '{print $1}')
  GW=$(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' "$NET" | awk '{print $1}')
  SUBNET=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$NET" | awk '{print $1}')
  CADDYFILE=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{.Source}}{{end}}{{end}}' "$CADDY_CT")
  if [ -z "$CADDYFILE" ]; then
    d=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy"}}{{.Source}}{{end}}{{end}}' "$CADDY_CT")
    [ -n "$d" ] && CADDYFILE="$d/Caddyfile"
  fi
  LISTEN="$GW"
  echo "Caddy в контейнере $CADDY_CT, сеть $NET, шлюз $GW, конфиг $CADDYFILE"
else
  LISTEN=127.0.0.1
fi
[ -n "$LISTEN" ] && [ -f "$CADDYFILE" ] || { echo "Не нашёл Caddyfile ($CADDYFILE)"; exit 1; }
UPSTREAM="$LISTEN:8765"

caddy_cmd() {   # caddy validate/reload там, где он запущен
  if [ -n "$CADDY_CT" ]; then docker exec "$CADDY_CT" caddy "$@" --config /etc/caddy/Caddyfile --adapter caddyfile
  else caddy "$@" --config "$CADDYFILE" --adapter caddyfile; fi
}

step "4/6 Сервис blockboom (слушает $UPSTREAM)"
id blockboom >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin blockboom
chown -R blockboom:blockboom "$DIR/server"     # сервер пишет data.json
cp "$DIR/deploy/blockboom.service" /etc/systemd/system/blockboom.service
mkdir -p /etc/systemd/system/blockboom.service.d
printf '[Service]\nEnvironment=HOST=%s\n' "$LISTEN" > /etc/systemd/system/blockboom.service.d/host.conf
systemctl daemon-reload
systemctl enable blockboom >/dev/null
systemctl restart blockboom
sleep 2
curl -fsS "http://$UPSTREAM/health" && echo
if [ -n "${SUBNET:-}" ] && command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow from "$SUBNET" to any port 8765 proto tcp >/dev/null && echo "ufw: разрешён доступ из $SUBNET"
fi

step "5/6 Caddy: $DOMAIN/ws и $DOMAIN/blockboom -> $UPSTREAM"
BAK="$CADDYFILE.bak.$(date +%s)"
cp "$CADDYFILE" "$BAK"
NEW=$(cat "$CADDYFILE")

## Строка «reverse_proxy <путь> <адрес>» в блоке kyrbo.com: добавить, поправить адрес или оставить.
## Ставится сразу после «kyrbo.com {». reverse_proxy в Caddy срабатывает раньше file_server,
## поэтому остальной сайт не меняется. WebSocket Caddy проксирует сам.
caddy_route() {
  local route="$1" re
  re=$(printf '%s' "$route" | sed 's/[*]/\\*/g')
  if printf '%s\n' "$NEW" | grep -qE "reverse_proxy $re $UPSTREAM\$"; then
    echo "$route: уже настроено"
  elif printf '%s\n' "$NEW" | grep -qE "reverse_proxy $re "; then
    NEW=$(printf '%s\n' "$NEW" | sed -E "s#reverse_proxy $re [^[:space:]]+#reverse_proxy $route $UPSTREAM#")
    echo "$route: адрес обновлён"
  else
    if ! printf '%s\n' "$NEW" | grep -qE "^[[:space:]]*(https?://)?$DOMAIN([[:space:]]|,|\{)"; then
      echo "В $CADDYFILE нет блока $DOMAIN — добавьте вручную:  reverse_proxy $route $UPSTREAM"; exit 1
    fi
    NEW=$(printf '%s\n' "$NEW" | sed -E "0,/^[[:space:]]*(https?:\/\/)?${DOMAIN//./\\.}([[:space:]]|,).*\{/s//&\n\treverse_proxy ${route//\//\\/} $UPSTREAM/")
    echo "$route: добавлено"
  fi
}
caddy_route "/ws"
caddy_route "/blockboom*"
printf '%s\n' "$NEW" > "$CADDYFILE"   # запись поверх, а не замена файла: так её видит и контейнер

if ! caddy_cmd validate >/dev/null 2>&1; then
  echo "Caddyfile не прошёл проверку — возвращаю прежний"
  caddy_cmd validate || true
  cat "$BAK" > "$CADDYFILE"; exit 1
fi
caddy_cmd reload

step "6/6 Проверка"
sleep 1
code=$(curl -s -o /dev/null -w '%{http_code}' --http1.1 -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -m 5 "https://$DOMAIN/ws" || true)
page=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "https://$DOMAIN/blockboom/" || true)
sleep 2   # сервер сохраняет ключ статистики через секунду после первого запуска
skey=$(node -e 'try{process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).statsKey||"")}catch(e){}' "$DIR/server/data.json" || true)
[ -n "$skey" ] && echo "Статистика (ссылка только для вас): https://$DOMAIN/blockboom/stats?key=$skey"
echo "Страница https://$DOMAIN/blockboom/ — ответ $page"
if [ "$code" = "101" ] && [ "$page" = "200" ]; then echo "ГОТОВО: wss://$DOMAIN/ws и https://$DOMAIN/blockboom/ работают"; else echo "Ответ $code — смотрите: journalctl -u blockboom -n 50; docker logs ${CADDY_CT:-caddy} --tail 50"; fi
