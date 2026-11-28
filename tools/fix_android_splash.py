"""Цвет системной заставки Android в готовом APK.

В шаблоне Godot (сборка без Gradle) у темы заставки атрибут windowSplashScreenBackground ссылается
на картинку @mipmap/icon_background, а Android ждёт там цвет — и на светлой теме телефона показывает
белое окно со значком. Скрипт заменяет ссылку на цвет прямо в resources.arsc.
После него APK нужно выровнять (zipalign) и подписать заново (apksigner) — это делает tools/build_apk.sh.

Заодно умеет оставить в APK движок только для одной архитектуры процессора: движок Godot занимает
98 % файла и лежит там дважды (arm64-v8a для современных телефонов и armeabi-v7a для старых 32-битных).

Запуск:  python tools/fix_android_splash.py вход.apk выход.apk 2b2a67 [arm64-v8a|armeabi-v7a]
"""
import struct
import sys
import zipfile

ATTR = 0x0101062C          # android:windowSplashScreenBackground
TYPE_REFERENCE = 0x01
TYPE_COLOR_ARGB8 = 0x1C


def patch_arsc(data: bytes, rgb: int) -> bytes:
    key = struct.pack('<I', ATTR)
    out = bytearray(data)
    n = 0
    i = out.find(key)
    while i >= 0:
        # За именем атрибута идёт Res_value: size=8, res0=0, dataType, data
        size, res0, dtype = struct.unpack_from('<HBB', out, i + 4)
        if size == 8 and res0 == 0 and dtype == TYPE_REFERENCE:
            struct.pack_into('<HBBI', out, i + 4, 8, 0, TYPE_COLOR_ARGB8, 0xFF000000 | rgb)
            n += 1
        i = out.find(key, i + 4)
    if n != 1:
        raise SystemExit(f'ожидалась одна ссылка windowSplashScreenBackground, найдено {n} — шаблон Godot изменился')
    return bytes(out)


def main() -> None:
    src, dst, color = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
    abi = sys.argv[4] if len(sys.argv) > 4 else ''
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w') as zout:
        for info in zin.infolist():
            if info.filename.startswith('META-INF/') and info.filename.rsplit('.', 1)[-1] in ('SF', 'RSA', 'DSA', 'EC', 'MF'):
                continue   # старая подпись: APK подписывается заново
            if abi and info.filename.startswith('lib/') and not info.filename.startswith(f'lib/{abi}/'):
                continue   # движок для другой архитектуры
            data = zin.read(info.filename)
            if info.filename == 'resources.arsc':
                data = patch_arsc(data, color)
            new = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            new.compress_type = info.compress_type      # несжатые файлы остаются несжатыми
            new.external_attr = info.external_attr
            zout.writestr(new, data)
    print('ok: #%06x %s' % (color, abi or 'all'))


if __name__ == '__main__':
    main()
