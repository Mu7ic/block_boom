"""Варианты значка игры: design/icons/v1…v5.svg (512×512) и предпросмотр design/icons/preview.html.
Запуск:  python tools/make_icons.py
Каждый вариант — фон (bg) и рисунок (fg) в поле 512×512; рисунок держится в центральных 66 %,
чтобы его не обрезала круглая маска значка на Android.
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), '..', 'design', 'icons')
os.makedirs(OUT, exist_ok=True)

PAL = {'red': ('#ff5d6c', '#c93a4f'), 'orange': ('#ffa93b', '#d07a17'), 'yellow': ('#ffd84d', '#d9a81c'),
       'green': ('#4fd67a', '#2ba457'), 'blue': ('#36c3ff', '#1790c9'), 'indigo': ('#5d7bff', '#3a55d0'),
       'violet': ('#b45dff', '#8537cf'), 'pink': ('#ff6fc8', '#d2439b'), 'white': ('#ffffff', '#cfd5f5')}


def block(x, y, s, col, hi=True):
    c, d = PAL[col]
    r = round(s * 0.2, 1)
    out = f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="{d}"/>'
    out += f'<rect x="{x}" y="{y}" width="{s}" height="{round(s * 0.9, 1)}" rx="{r}" fill="{c}"/>'
    if hi:
        out += f'<rect x="{round(x + s * 0.16, 1)}" y="{round(y + s * 0.11, 1)}" width="{round(s * 0.68, 1)}" height="{round(s * 0.1, 1)}" rx="{round(s * 0.05, 1)}" fill="#fff" opacity=".4"/>'
    return out


def burst(cx, cy, r1, r2, n, fill, rot=0.0):
    pts = []
    for i in range(n * 2):
        a = math.pi * i / n + rot
        r = r1 if i % 2 == 0 else r2
        pts.append(f'{round(cx + r * math.sin(a), 1)},{round(cy - r * math.cos(a), 1)}')
    return f'<polygon points="{" ".join(pts)}" fill="{fill}"/>'


def spark(cx, cy, r, fill='#fff'):
    return burst(cx, cy, r, r * 0.28, 4, fill)


V = []

# 1. Сетка: поле из блоков, в центре — взрыв
g = ''
cols = ['red', 'orange', 'yellow', 'green', None, 'blue', 'indigo', 'violet', 'pink']
for i, c in enumerate(cols):
    if c:
        g += block(98 + (i % 3) * 108, 98 + (i // 3) * 108, 100, c)
g += burst(256, 256, 62, 26, 8, '#ffd84d') + '<circle cx="256" cy="256" r="17" fill="#fff"/>'
V.append(('Сетка', 'Поле из блоков со вспышкой в центре — развитие нынешнего значка', '#2b2f7a', g, ''))

# 2. Буква B из блоков
g = ''
rows = ['XXX.', 'X..X', 'XXX.', 'X..X', 'XXX.']
rc = ['red', 'orange', 'yellow', 'green', 'blue']
for r, row in enumerate(rows):
    for c, ch in enumerate(row):
        if ch == 'X':
            g += block(127 + c * 66, 94 + r * 66, 60, rc[r])
g += spark(392, 118, 30) + spark(108, 408, 20)
V.append(('Буква B', 'Первая буква названия, собранная из блоков', '#1d2757', g, ''))

# 3. Взрыв: блок разлетается
g = burst(256, 256, 176, 104, 12, '#ffd84d') + burst(256, 256, 128, 78, 12, '#fff3b0', math.pi / 12)
g += f'<g transform="rotate(-12 256 256)">{block(186, 186, 140, "indigo")}</g>'
for (x, y, s, c, a) in [(112, 110, 46, 'pink', -24), (354, 96, 40, 'green', 18), (372, 350, 48, 'blue', 30), (96, 352, 38, 'orange', -14)]:
    g += f'<g transform="rotate({a} {x + s / 2} {y + s / 2})">{block(x, y, s, c)}</g>'
V.append(('Взрыв', 'Блок взрывается — самый яркий и «громкий» вариант', '#ff4f7b', g, ''))

# 4. Линия: собранный ряд исчезает
BAND = '<rect x="0" y="196" width="512" height="120" fill="#463f9e"/>'   # полоса — часть фона, не рисунка
g = ''
for i, c in enumerate(['yellow', 'green', 'blue', 'pink']):
    g += block(94 + i * 82, 216, 78, c)
g += block(176, 118, 78, 'orange') + block(258, 118, 78, 'orange')
g += spark(128, 150, 26) + spark(400, 152, 34) + spark(256, 372, 30) + spark(150, 356, 16) + spark(366, 350, 18)
V.append(('Линия', 'Фигура падает и закрывает ряд — показывает суть игры; фон как в самой игре', '#2b2a67', g, BAND))

# 5. Глазастик: блок-персонаж
g = block(126, 126, 260, 'blue')
for cx in (212, 300):
    g += f'<ellipse cx="{cx}" cy="238" rx="30" ry="36" fill="#fff"/><circle cx="{cx + 6}" cy="246" r="15" fill="#1d2757"/><circle cx="{cx + 11}" cy="240" r="5" fill="#fff"/>'
g += '<path d="M214 296 Q256 336 298 296" fill="none" stroke="#1d2757" stroke-width="12" stroke-linecap="round"/>'
g += spark(398, 122, 28, '#fff') + spark(112, 392, 18, '#fff')
V.append(('Глазастик', 'Блок-персонаж: запоминается и выделяется среди похожих игр', '#ffc93c', g, ''))

for i, (name, note, bg, fg, under) in enumerate(V, 1):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="{bg}"/>{under}{fg}</svg>\n'
    open(os.path.join(OUT, f'v{i}.svg'), 'w', encoding='utf-8', newline='\n').write(svg)
    open(os.path.join(OUT, f'v{i}_fg.svg'), 'w', encoding='utf-8', newline='\n').write(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">{fg}</svg>\n')

# Предпросмотр: значок (скруглённый и круглый) и экран открытия
cards = ''
for i, (name, note, bg, fg, under) in enumerate(V, 1):
    ink = '#1d2757' if bg in ('#ffc93c',) else '#ffffff'
    cards += f'''<div class="card"><div class="row">
<svg class="ic sq" viewBox="0 0 512 512"><rect width="512" height="512" fill="{bg}"/>{under}{fg}</svg>
<svg class="ic rd" viewBox="0 0 512 512"><rect width="512" height="512" fill="{bg}"/>{under}{fg}</svg>
<div class="ph" style="background:{bg}"><svg viewBox="0 0 512 512">{fg}</svg><b style="color:{ink}">BLOCK<br>BOOM</b></div>
</div><p class="nm">{i}. {name}</p><p class="nt">{note}</p></div>
'''
html = f'''<!doctype html><meta charset="utf-8"><title>Block Boom — варианты значка</title>
<style>body{{margin:0;padding:24px;font:15px system-ui,sans-serif;background:#f3f1ea;color:#222}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}}
.card{{background:#fff;border-radius:16px;padding:16px}}.row{{display:flex;gap:14px;align-items:center}}
.ic{{width:92px;height:92px;flex:none}}.sq{{border-radius:22%}}.rd{{border-radius:50%}}
.ph{{width:78px;height:150px;border-radius:12px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;flex:none}}
.ph svg{{width:60px;height:60px}}.ph b{{font-size:11px;line-height:1.05;text-align:center;letter-spacing:.5px}}
.nm{{font-weight:600;margin:12px 0 2px}}.nt{{margin:0;color:#666;font-size:13px}}</style>
<div class="grid">{cards}</div>'''
open(os.path.join(OUT, 'preview.html'), 'w', encoding='utf-8', newline='\n').write(html)
print('ok', len(V), 'вариантов ->', os.path.normpath(OUT))
