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

step "3/6 Зависимости"
cd "$DIR/server"
npm install --omit=dev --no-audit --no-fund

step "4/6 Сервис blockboom"
id blockboom >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin blockboom
chown -R blockboom:blockboom "$DIR/server"     # сервер пишет data.json
cp "$DIR/deploy/blockboom.service" /etc/systemd/system/blockboom.service
systemctl daemon-reload
systemctl enable blockboom >/dev/null
systemctl restart blockboom
sleep 2
curl -fsS http://127.0.0.1:8765/health && echo

step "5/6 Caddy: $DOMAIN/ws -> 127.0.0.1:8765"
if grep -q "reverse_proxy /ws 127.0.0.1:8765" "$CADDYFILE"; then
  echo "уже настроено"
else
  cp "$CADDYFILE" "$CADDYFILE.bak.$(date +%s)"
  # Строка сразу после «kyrbo.com {». reverse_proxy в Caddy срабатывает раньше file_server,
  # поэтому остальной сайт не меняется. WebSocket Caddy проксирует сам.
  if ! grep -qE "^[[:space:]]*(https?://)?$DOMAIN([[:space:]]|,|\{)" "$CADDYFILE"; then
    echo "В $CADDYFILE нет блока $DOMAIN — добавьте вручную:  reverse_proxy /ws 127.0.0.1:8765"; exit 1
  fi
  sed -i -E "0,/^[[:space:]]*(https?:\/\/)?${DOMAIN//./\\.}([[:space:]]|,).*\{/s//&\n\treverse_proxy \/ws 127.0.0.1:8765/" "$CADDYFILE"
fi
if ! caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
  echo "Caddyfile не прошёл проверку — возвращаю прежний"
  last=$(ls -t "$CADDYFILE".bak.* | head -1); cp "$last" "$CADDYFILE"; exit 1
fi
systemctl reload caddy

step "6/6 Проверка"
sleep 1
code=$(curl -s -o /dev/null -w '%{http_code}' --http1.1 -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -m 5 "https://$DOMAIN/ws" || true)
if [ "$code" = "101" ]; then echo "ГОТОВО: wss://$DOMAIN/ws работает"; else echo "Ответ $code — смотрите: journalctl -u blockboom -n 50; journalctl -u caddy -n 50"; fi
