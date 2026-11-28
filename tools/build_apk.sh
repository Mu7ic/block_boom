#!/usr/bin/env bash
# Сборка APK для Android: экспорт из Godot, исправление цвета системной заставки, выравнивание, подпись.
# Запуск из корня проекта (Git Bash):
#   tools/build_apk.sh          — выпуск для игроков: build/BlockBoom.apk (современные телефоны, arm64)
#                                 и build/BlockBoom-32bit.apk (старые 32-битные)
#   tools/build_apk.sh debug    — отладочная сборка тем же ключом (нужна, чтобы достать сохранение по кабелю)
# Нужны: Godot (GODOT), Android build-tools (zipalign, apksigner), JDK из настроек редактора Godot, python.
# Ключ подписи — в папке вне проекта (BB_KEYS, по умолчанию D:/Games/BlockBoom-release-key):
#   blockboom-release.keystore (алиас blockboom) и password.txt. Пароль на экран не выводится.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-release}"
GODOT="${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}"
BT="$(ls -d "$LOCALAPPDATA"/Android/Sdk/build-tools/*/ | tail -1)"
SETTINGS="$(ls "$APPDATA"/Godot/editor_settings-4*.tres | tail -1)"
# Значение настройки редактора Godot (пусто, если её нет)
val() { { grep -m1 "^export/android/$1 = " "$SETTINGS" || true; } | sed -E 's/^[^=]+= "(.*)"$/\1/'; }
export JAVA_HOME="$(val java_sdk_path)"
export PATH="$JAVA_HOME/bin:$PATH"

KEYS="${BB_KEYS:-D:/Games/BlockBoom-release-key}"
KS="$KEYS/blockboom-release.keystore"
KS_USER=blockboom
[ -f "$KS" ] && [ -f "$KEYS/password.txt" ] || { echo "нет ключа подписи в $KEYS"; exit 1; }
KS_PASS="$(cat "$KEYS/password.txt")"
export KS_PASS
# Этим же ключом Godot подписывает выпуск при экспорте
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KS_USER"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KS_PASS"

SPLASH_COLOR=2b2a67          # фон заставки = boot_splash/bg_color в project.godot
TMP=build/tmp
mkdir -p "$TMP"

echo "1/2 экспорт ($MODE)"
"$GODOT" --headless --path . "--export-$MODE" "Android" "$TMP/raw.apk" 2>&1 | grep -iE "error|\[ DONE \].*export" || true
[ -s "$TMP/raw.apk" ] || { echo "экспорт не удался"; exit 1; }

# Заставка, выравнивание и подпись одного файла; abi пусто — движок для всех архитектур
pack() {   # pack <выходной файл> [abi]
  python tools/fix_android_splash.py "$TMP/raw.apk" "$TMP/patched.apk" "$SPLASH_COLOR" ${2:-}
  "$BT/zipalign.exe" -p -f 4 "$TMP/patched.apk" "$TMP/aligned.apk"
  "$BT/apksigner.bat" sign --ks "$KS" --ks-key-alias "$KS_USER" --ks-pass env:KS_PASS --key-pass env:KS_PASS --out "$1" "$TMP/aligned.apk"
  "$BT/apksigner.bat" verify --print-certs "$1" | grep -m1 "SHA-256" || { echo "подпись не прошла проверку"; exit 1; }
  rm -f build/tmp/patched.apk build/tmp/aligned.apk "$1.idsig"
}

echo "2/2 заставка, выравнивание, подпись"
if [ "$MODE" = debug ]; then
  pack build/BlockBoom-debug.apk
else
  pack build/BlockBoom.apk arm64-v8a
  pack build/BlockBoom-32bit.apk armeabi-v7a
fi
rm -f build/tmp/raw.apk build/tmp/raw.apk.idsig
rmdir build/tmp 2>/dev/null || true
ls -la build/*.apk
