#!/usr/bin/env bash
# Сборка APK для Android: экспорт из Godot, исправление цвета системной заставки, выравнивание, подпись.
# Запуск из корня проекта (Git Bash):  tools/build_apk.sh
# Нужны: Godot (GODOT), Android build-tools (zipalign, apksigner), JDK (JAVA_HOME), python.
# Ключ подписи берётся из настроек редактора Godot (export/android/debug_keystore*), пароль на экран не выводится.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}"
BT="$(ls -d "$LOCALAPPDATA"/Android/Sdk/build-tools/*/ | tail -1)"
SETTINGS="$(ls "$APPDATA"/Godot/editor_settings-4*.tres | tail -1)"
# Значение настройки редактора Godot (пусто, если её нет)
val() { { grep -m1 "^export/android/$1 = " "$SETTINGS" || true; } | sed -E 's/^[^=]+= "(.*)"$/\1/'; }
export JAVA_HOME="$(val java_sdk_path)"
export PATH="$JAVA_HOME/bin:$PATH"
SPLASH_COLOR=2b2a67          # фон заставки = boot_splash/bg_color в project.godot
OUT=build/BlockBoom.apk
TMP=build/tmp
mkdir -p "$TMP"

echo "1/4 экспорт"
"$GODOT" --headless --path . --export-debug "Android" "$TMP/raw.apk" 2>&1 | grep -iE "error|\[ DONE \].*export" || true
[ -s "$TMP/raw.apk" ] || { echo "экспорт не удался"; exit 1; }

echo "2/4 цвет системной заставки"
python tools/fix_android_splash.py "$TMP/raw.apk" "$TMP/patched.apk" "$SPLASH_COLOR"

echo "3/4 выравнивание"
"$BT/zipalign.exe" -p -f 4 "$TMP/patched.apk" "$TMP/aligned.apk"

echo "4/4 подпись"
KS="$(val debug_keystore)"
KS_USER="$(val debug_keystore_user)"
KS_USER="${KS_USER:-androiddebugkey}"
KS_PASS="$(val debug_keystore_pass)"
export KS_PASS
"$BT/apksigner.bat" sign --ks "$KS" --ks-key-alias "$KS_USER" --ks-pass env:KS_PASS --key-pass env:KS_PASS --out "$OUT" "$TMP/aligned.apk"
"$BT/apksigner.bat" verify "$OUT" && echo "подпись в порядке"
rm -f build/tmp/raw.apk build/tmp/raw.apk.idsig build/tmp/patched.apk build/tmp/aligned.apk build/BlockBoom.apk.idsig
rmdir build/tmp 2>/dev/null || true
ls -la "$OUT"
