// Сервер онлайн-боя «Блок Бум!»
// - отдаёт игру (../index.html) по HTTP
// - по WebSocket на /ws держит комнаты на двоих: код из 4 цифр, общий таймер 3 минуты,
//   пересылает сопернику состояние поля, в конце сам объявляет итог.
// - быстрый поиск соперника с рейтингом Эло (бои по коду комнаты рейтинг не меняют)
// - ежедневный вызов: таблица лучших результатов дня
// Профили и таблицы хранятся в data.json рядом с сервером (переменная DATA_FILE).
//
// Запуск:  cd server && npm install && npm start      (порт: переменная PORT, по умолчанию 8765)

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 8765;
const HOST = process.env.HOST || '0.0.0.0';
const GAME_FILE = path.join(__dirname, '..', 'index.html');

const COUNTDOWN = 3000;          // отсчёт «3-2-1» перед стартом, мс
const DURATION = Number(process.env.DURATION_MS) || 180000; // длительность боя, мс (для тестов можно сократить)
const GRACE = 1500;              // ждём запоздавшие ходы после конца, мс
const WAIT_TTL = 15 * 60 * 1000; // комната без соперника живёт 15 минут
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, 'data.json');
const START_RATING = 1000;
const DAILY_KEEP = 7;            // сколько дней хранить таблицы ежедневного вызова
const DAILY_TOP = 10;

// ---------- Хранилище: профили (рейтинг) и таблицы дня ----------
// Игрок опознаётся по случайному токену, который клиент создаёт сам и хранит у себя.
// Токен никому не показывается: в таблицах только имена и очки.
let db = { players: {}, daily: {}, act: {}, stats: {}, backups: {}, codes: {} };
try { db = { players: {}, daily: {}, act: {}, stats: {}, backups: {}, codes: {}, ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) }; } catch (e) { /* первый запуск */ }
let saveTimer = null;
function saveDb() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    const tmp = DATA_FILE + '.tmp';
    fs.writeFile(tmp, JSON.stringify(db), err => {
      if (err) return console.error('data.json:', err.message);
      fs.rename(tmp, DATA_FILE, e => { if (e) console.error('data.json:', e.message); });
    });
  }, 1000);
}
const validId = id => typeof id === 'string' && /^[a-f0-9]{16,64}$/.test(id);

// ---------- Копия прогресса и код восстановления ----------
// db.backups[id] = { data: строка JSON с сохранением игры, at: время, code }
// db.codes[code] = id. Код — как пароль: кто его знает, тот забирает прогресс и рейтинг.
const BACKUP_MAX = 16000;                              // символов в копии
const CODE_ABC = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // без похожих O/0, I/1
const RESTORE_TRIES_PER_HOUR = 10;                     // попыток ввести код с одного IP
const restoreTries = new Map();                        // ip → [время попыток]
function newBackupCode() {
  let c;
  do {
    const b = crypto.randomBytes(12);
    c = Array.from(b, x => CODE_ABC[x % 32]).join('');
  } while (db.codes[c]);
  return c;
}
const fmtCode = c => c.match(/.{4}/g).join('-');
const normCode = s => String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
function restoreAllowed(ip) {
  const now = Date.now();
  const t = (restoreTries.get(ip) || []).filter(x => now - x < 3600000);
  if (t.length >= RESTORE_TRIES_PER_HOUR) { restoreTries.set(ip, t); return false; }
  t.push(now);
  restoreTries.set(ip, t);
  return true;
}

// ---------- Защита от накруток ----------
// 1. Договорные бои: одна и та же пара разыгрывает рейтинг не больше PAIR_RATED_PER_DAY раз в день,
//    а бой двух игроков с одного IP (одна сеть, два своих телефона) идёт без рейтинга.
// 2. Счёт: сервер ведёт серию комбо и число клеток на поле каждого игрока и не принимает ход,
//    который даёт больше очков, чем возможно по правилам (см. checkMove).
// 3. Частота: ограничены соединения и сообщения с одного IP, новые профили и результаты вызова дня.
const PAIR_RATED_PER_DAY = 3;
const MAX_CONN_PER_IP = Number(process.env.MAX_CONN_PER_IP) || 12;
const MAX_MSG_PER_10S = 80;          // сообщений с одного соединения за 10 секунд
const MAX_NEW_IDS_PER_IP_DAY = Number(process.env.MAX_NEW_IDS_PER_IP_DAY) || 20;
const MIN_MOVE_MS = 150;             // в среднем быстрее человек фигуры не ставит
const MOVE_BURST = 4;                // столько ходов может прийти подряд без паузы
const DAILY_MAX_SCORE = 3000000;     // выше в вызове дня честно не набрать
const DAILY_MIN_GAP = 8000;          // результат вызова дня — не чаще раза в 8 секунд
const SCORE = { cell: 10, line: 100, perfect: 3000, grace: 3 };   // как в scripts/scoring.gd

const pairRated = {};    // день → { 'idA|idB': число рейтинговых боёв }
const newIds = {};       // день → { ip: число новых профилей }
const connByIp = new Map();
const pairKey = (a, b) => [a.pid, b.pid].sort().join('|');
function bump(table, key) {
  const day = dayStr();
  for (const d of Object.keys(table)) if (d !== day) delete table[d];
  const t = table[day] || (table[day] = {});
  return (t[key] = (t[key] || 0) + 1);
}
const peek = (table, key) => (table[dayStr()] || {})[key] || 0;

// Почему бой этой пары не идёт в рейтинг ('' — идёт)
function unrankedWhy(a, b) {
  if (a.ip && a.ip === b.ip) return 'sameNet';
  if (peek(pairRated, pairKey(a, b)) >= PAIR_RATED_PER_DAY) return 'pairLimit';
  return '';
}

// Новый профиль с этого IP: false — лимит на сегодня исчерпан
function allowNewId(ip) {
  if (!ip) return true;
  if (peek(newIds, ip) >= MAX_NEW_IDS_PER_IP_DAY) return false;
  bump(newIds, ip);
  return true;
}

// Проверка хода в бою. st — состояние игрока на сервере:
// { score: принятый счёт, claimed: счёт со слов клиента, combo, miss, cnt: клеток на поле, at }.
// Сервер сам копит счёт: за ход прибавляет не больше, чем возможно по правилам. Невозможный ход
// очков не даёт, но бой продолжается — случайный сбой стоит одного хода, а не всей игры.
function checkMove(st, m, now) {
  const claimed = Math.floor(Number(m.score)) || 0;
  const gain = Math.max(0, claimed - st.claimed);
  st.claimed = Math.max(st.claimed, claimed);
  const board = Array.isArray(m.board) && m.board.length === 64 ? m.board : null;
  const cnt = board ? board.filter(c => c).length : st.cnt;
  const before = st.cnt;
  st.cnt = cnt;
  if (m.reset) { st.combo = 0; st.miss = 0; return gain === 0; }   // нет ходов — поле очищено, очков за это нет
  if (!Array.isArray(m.placed)) return gain === 0;                 // сообщение без хода (начало боя)
  const p = m.placed.length, c = Array.isArray(m.cleared) ? m.cleared.length : 0, n = Math.floor(Number(m.n)) || 0;
  // Темп: в среднем не чаще хода в MIN_MOVE_MS. Соседние сообщения могут прийти вплотную
  // (клиент шлёт ход после подбора новых фигур), поэтому считаем запас, а не паузу между двумя ходами.
  st.tok = Math.min(MOVE_BURST, st.tok + (now - st.at) / MIN_MOVE_MS);
  st.at = now;
  const fast = st.tok < 1;
  if (!fast) st.tok -= 1;
  let ok = p >= 1 && p <= 9 && n >= 0 && n <= 6 && !fast;
  // n линий — это минимум 8n клеток минус пересечения строк со столбцами
  if (n > 0 ? c < 8 * n - Math.floor(n / 2) * Math.ceil(n / 2) : c !== 0) ok = false;
  if (board && cnt !== before + p - c) ok = false;                 // клетки не берутся из ниоткуда
  if (!ok) { st.combo = 0; st.miss = 0; return gain === 0; }
  if (n > 0) { st.combo++; st.miss = 0; } else if (++st.miss >= SCORE.grace) st.combo = 0;
  const max = p * SCORE.cell + (n > 0 ? SCORE.line * n * (n + 1) / 2 * st.combo + (cnt === 0 ? SCORE.perfect : 0) : 0);
  st.score += Math.min(gain, max);
  return gain <= max;
}
function profile(id, name, ip) {
  if (!validId(id)) return null;
  let p = db.players[id];
  if (!p) {
    if (!allowNewId(ip)) return null;
    p = db.players[id] = { name: 'Игрок', rating: START_RATING, games: 0, wins: 0 };
    saveDb();
  }
  if (name && p.name !== name) { p.name = name; saveDb(); }
  rollSeason(p);
  return p;
}
const publicProfile = p => ({
  t: 'profile', rating: p.rating, games: p.games, wins: p.wins, latest: LATEST.code,
  season: { id: seasonId(), left: Math.max(0, Math.round((seasonEnd() - Date.now()) / 1000)) },
  reward: p.reward || null,
});

// ---------- Сезоны: неделя с понедельника (UTC) ----------
// В конце сезона игрок, сыгравший хотя бы один рейтинговый бой, получает ключи по лиге,
// а рейтинг наполовину возвращается к стартовому — чтобы каждую неделю было за что бороться.
const SEASON_KEYS = [[1600, 6], [1400, 4], [1250, 3], [1100, 2], [0, 1]];
function seasonStart(ms = Date.now()) {
  const d = new Date(ms);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - (d.getUTCDay() + 6) % 7);
}
const seasonEnd = (ms = Date.now()) => seasonStart(ms) + 7 * 86400000;
const seasonId = (ms = Date.now()) => new Date(seasonStart(ms)).toISOString().slice(0, 10);
function rollSeason(p) {
  const cur = seasonId();
  if (p.season === cur) return;
  if (p.season && p.seasonGames > 0) {
    p.reward = { season: p.season, rating: p.rating, keys: SEASON_KEYS.find(([r]) => p.rating >= r)[1] };
    p.rating = Math.round(START_RATING + (p.rating - START_RATING) * 0.5);
  }
  p.season = cur;
  p.seasonGames = 0;
  saveDb();
}

// Рейтинг Эло: новичкам (меньше 10 боёв) рейтинг меняется быстрее
function rate(pa, pb, result) {   // result: 1 — победил a, 0 — b, 0.5 — ничья
  rollSeason(pa); rollSeason(pb);
  pa.seasonGames = (pa.seasonGames || 0) + 1;
  pb.seasonGames = (pb.seasonGames || 0) + 1;
  const ea = 1 / (1 + Math.pow(10, (pb.rating - pa.rating) / 400));
  const ka = pa.games < 10 ? 40 : 24, kb = pb.games < 10 ? 40 : 24;
  const da = Math.round(ka * (result - ea));
  const dbb = Math.round(kb * ((1 - result) - (1 - ea)));
  pa.rating = Math.max(0, pa.rating + da);
  pb.rating = Math.max(0, pb.rating + dbb);
  pa.games++; pb.games++;
  if (result === 1) pa.wins++; else if (result === 0) pb.wins++;
  saveDb();
  return [da, dbb];
}

// День в UTC, как у клиента: 2026-11-27
const dayStr = (ms = Date.now()) => new Date(ms).toISOString().slice(0, 10);
function dailyBoard(day) {
  const b = db.daily[day] || {};
  return Object.entries(b).map(([id, e]) => ({ id, name: e.name, score: e.score })).sort((x, y) => y.score - x.score);
}
function dailyReply(day, id) {
  const all = dailyBoard(day);
  const i = all.findIndex(e => e.id === id);
  return {
    t: 'dailyTop', day, total: all.length,
    rank: i >= 0 ? i + 1 : 0, best: i >= 0 ? all[i].score : 0,
    top: all.slice(0, DAILY_TOP).map(e => ({ name: e.name, score: e.score, you: e.id === id })),
  };
}
function pruneDaily() {
  const days = Object.keys(db.daily).sort();
  while (days.length > DAILY_KEEP) delete db.daily[days.shift()];
}

// ---------- HTTP: отдаём игру ----------
const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  if (url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`ok rooms=${rooms.size} players=${wss.clients.size} queue=${queue.length}`);
    return;
  }
  if (url.startsWith('/blockboom')) return serveSite(url, req, res);
  if (url !== '/' && url !== '/index.html') {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Не найдено');
    return;
  }
  fs.readFile(GAME_FILE, (err, data) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Файл игры не найден');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' });
    res.end(data);
  });
});

// ---------- Версия игры: клиент старее LATEST.code показывает «Есть обновление» ----------
let LATEST = { code: 0, name: '' };
try { LATEST = { ...LATEST, ...JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'site', 'version.json'), 'utf8')) }; } catch (e) { /* нет файла — подсказки не будет */ }

// ---------- Статистика: обезличенные события игры ----------
// db.act[id]   = { f: первый день, d: [дни, когда игрок заходил], v: версия, p: платформа }
// db.stats[day] = { opens, games: { режим: число }, secs: секунд в партиях, cs: сумма очков «Классики» }
// Личных данных нет: только случайный токен игрока и счётчики.
const STATS_KEEP = 90;
const STATS_KEY = process.env.STATS_KEY || db.statsKey || (db.statsKey = crypto.randomBytes(12).toString('hex'));
const MODES = ['classic', 'daily', 'arcade', 'duel', 'online'];
function trackEvents(m) {
  const today = dayStr(), minDay = dayStr(Date.now() - 7 * 86400000);
  if (!db.act[m.id] && !allowNewId(m.ip)) return;
  const a = db.act[m.id] || (db.act[m.id] = { f: today, d: [] });
  for (const e of m.list.slice(0, 60)) {
    if (!e || typeof e !== 'object') continue;
    // События, накопленные без сети, приходят со своей датой (не старше недели)
    const day = typeof e.d === 'string' && /^\d{4}-\d\d-\d\d$/.test(e.d) && e.d <= today && e.d >= minDay ? e.d : today;
    if (day < a.f) a.f = day;
    if (!a.d.includes(day)) { a.d.push(day); a.d.sort(); if (a.d.length > 40) a.d.shift(); }
    const s = db.stats[day] || (db.stats[day] = { opens: 0, games: {}, secs: 0, cs: 0 });
    if (e.k === 'open') s.opens++;
    else if (e.k === 'game') {
      const mode = MODES.includes(e.m) ? e.m : 'other';
      s.games[mode] = (s.games[mode] || 0) + 1;
      s.secs += Math.min(3600, Math.max(0, Number(e.t) || 0));
      if (mode === 'classic') s.cs = (s.cs || 0) + Math.min(1e7, Math.max(0, Number(e.s) || 0));
    }
  }
  a.v = Math.floor(Number(m.ver)) || 0;
  a.p = String(m.plat || '').replace(/[^A-Za-z]/g, '').slice(0, 12);
  const days = Object.keys(db.stats).sort();
  while (days.length > STATS_KEEP) delete db.stats[days.shift()];
  saveDb();
}

function statsPage() {
  const acts = Object.values(db.act);
  const pct = (a, b) => b ? Math.round(100 * a / b) + '%' : '—';
  const rows = [];
  for (let k = 0; k < 21; k++) {
    const day = dayStr(Date.now() - k * 86400000);
    const s = db.stats[day] || { opens: 0, games: {}, secs: 0, cs: 0 };
    const dau = acts.filter(a => a.d.includes(day)).length;
    const fresh = acts.filter(a => a.f === day);
    const back = n => {
      const d2 = dayStr(new Date(day + 'T00:00:00Z').getTime() + n * 86400000);
      return d2 > dayStr() ? '…' : pct(fresh.filter(a => a.d.includes(d2)).length, fresh.length);
    };
    const games = Object.values(s.games).reduce((x, y) => x + y, 0);
    rows.push(`<tr><td>${day}</td><td>${dau}</td><td>${fresh.length}</td><td>${back(1)}</td><td>${back(7)}</td><td>${s.opens}</td><td>${games}</td>` +
      `<td>${dau ? (games / dau).toFixed(1) : '—'}</td><td>${games ? (s.secs / games / 60).toFixed(1) : '—'}</td>` +
      MODES.map(mo => `<td>${s.games[mo] || 0}</td>`).join('') +
      `<td>${s.games.classic ? Math.round((s.cs || 0) / s.games.classic) : '—'}</td></tr>`);
  }
  const vers = {};
  for (const a of acts) vers[`${a.p || '?'} v${a.v || '?'}`] = (vers[`${a.p || '?'} v${a.v || '?'}`] || 0) + 1;
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Block Boom — статистика</title>
<style>body{margin:0;padding:24px;background:#161a3a;color:#fff;font:15px system-ui,sans-serif}h1{margin:0 0 6px}p{opacity:.7;margin:4px 0 18px}
.wrap{overflow-x:auto}table{border-collapse:collapse;min-width:900px}th,td{padding:8px 12px;text-align:right;border-bottom:1px solid rgba(255,255,255,.1);white-space:nowrap}
th{font-size:13px;opacity:.7;font-weight:600}td:first-child,th:first-child{text-align:left}tr:hover td{background:rgba(255,255,255,.05)}</style></head><body>
<h1>Block Boom — статистика</h1>
<p>Всего игроков: ${acts.length} · сейчас на сервере: ${wss.clients.size} · последняя версия: ${LATEST.name} (${LATEST.code}) · установки: ${Object.entries(vers).map(([k, v]) => `${k} — ${v}`).join(', ') || '—'}</p>
<p>Дни по UTC. «Вернулись» — доля новых игроков этого дня, зашедших через 1 и 7 дней («…» — этот день ещё не наступил или не закончился).</p>
<div class="wrap"><table><tr><th>День</th><th>Игроков</th><th>Новых</th><th>Вернулись D1</th><th>Вернулись D7</th><th>Запусков</th><th>Партий</th><th>Партий на игрока</th><th>Минут на партию</th>
<th>Классика</th><th>Вызов дня</th><th>Аркада</th><th>Бот</th><th>Онлайн</th><th>Средний счёт Классики</th></tr>${rows.join('')}</table></div></body></html>`;
}

// ---------- Страница игры: /blockboom ----------
// /blockboom/            — страница со скачиванием (site/index.html)
// /blockboom/img/…       — картинки страницы
// /blockboom/play/       — веб-версия игры (для iPhone и ПК)
// /blockboom/BlockBoom.apk — APK; setup-kyrbo.sh кладёт его в site/, иначе ссылка на GitHub Releases
const SITE_DIR = path.join(__dirname, '..', 'site');
// BlockBoom.apk — для современных телефонов (arm64), BlockBoom-32bit.apk — для старых 32-битных
const APK_DIR = process.env.APK_DIR || SITE_DIR;
const APK_FALLBACK = 'https://github.com/Mu7ic/block_boom/releases/latest/download/';
const MIME = { '.webp': 'image/webp', '.svg': 'image/svg+xml', '.png': 'image/png' };

function sendFile(res, file, type, extra = {}) {
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Не найдено');
      return;
    }
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': st.size, ...extra });
    fs.createReadStream(file).pipe(res);
  });
}

function serveSite(url, req, res) {
  if (url === '/blockboom/stats') {
    // Статистика — только по секретной ссылке (ключ печатает deploy/setup-kyrbo.sh)
    const key = new URL(req.url, 'http://x').searchParams.get('key') || '';
    const ok = key.length === STATS_KEY.length && crypto.timingSafeEqual(Buffer.from(key), Buffer.from(STATS_KEY));
    res.writeHead(ok ? 200 : 404, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(ok ? statsPage() : 'Не найдено');
    return;
  }
  if (url === '/blockboom' || url === '/blockboom/play') {
    res.writeHead(301, { Location: url + '/' });
    res.end();
    return;
  }
  if (url === '/blockboom/' || url === '/blockboom/index.html')
    return sendFile(res, path.join(SITE_DIR, 'index.html'), 'text/html; charset=utf-8', { 'Cache-Control': 'no-cache' });
  if (url === '/blockboom/play/')
    return sendFile(res, GAME_FILE, 'text/html; charset=utf-8', { 'Cache-Control': 'no-cache' });
  const apk = url.match(/^\/blockboom\/(BlockBoom(-32bit)?\.apk)$/);
  if (apk) {
    const file = path.join(APK_DIR, apk[1]);
    if (!fs.existsSync(file)) {
      res.writeHead(302, { Location: APK_FALLBACK + apk[1] });
      res.end();
      return;
    }
    return sendFile(res, file, 'application/vnd.android.package-archive',
      { 'Content-Disposition': `attachment; filename="${apk[1]}"`, 'Cache-Control': 'no-cache' });
  }
  const m = url.match(/^\/blockboom\/img\/([a-z0-9_-]+\.(webp|svg|png))$/);
  if (m) return sendFile(res, path.join(SITE_DIR, 'img', m[1]), MIME['.' + m[2]], { 'Cache-Control': 'public, max-age=3600' });
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Не найдено');
}

// ---------- WebSocket: комнаты ----------
const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 32 * 1024 });
const rooms = new Map(); // код → { code, players: [ws], state: 'waiting'|'playing'|'ended', ranked, ... }
const queue = [];        // быстрый поиск: [{ ws, since }]

const send = (ws, msg) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg)); };
const other = (room, ws) => room.players.find(p => p !== ws);
const cleanName = n => String(n || '').replace(/[<>&"]/g, '').trim().slice(0, 16) || 'Игрок';

function newCode() {
  let c;
  do { c = String(1000 + Math.floor(Math.random() * 9000)); } while (rooms.has(c));
  return c;
}

function startMatch(room) {
  clearTimeout(room.endTimer);
  clearTimeout(room.waitTimer);
  room.state = 'playing';
  // Рейтинговая комната может сыграть бой без рейтинга: одна сеть или лимит боёв этой пары на сегодня
  const why = room.ranked ? unrankedWhy(room.players[0], room.players[1]) : '';
  room.rated = !!room.ranked && !why;
  room.check = new Map(room.players.map(p => [p, { score: 0, claimed: 0, combo: 0, miss: 0, cnt: 0, at: Date.now(), tok: MOVE_BURST, bad: 0 }]));
  room.scores = new Map(room.players.map(p => [p, 0]));
  room.ready = new Set();
  room.endAt = Date.now() + COUNTDOWN + DURATION;
  for (const p of room.players) {
    send(p, { t: 'start', countdown: COUNTDOWN, duration: DURATION, opponent: other(room, p).name, ranked: room.rated, why });
  }
  room.endTimer = setTimeout(() => finish(room), COUNTDOWN + DURATION + GRACE);
}

function finish(room) {
  room.state = 'ended';
  const [a, b] = room.players;
  if (!a || !b) return;
  const sa = room.scores.get(a) || 0, sb = room.scores.get(b) || 0;
  const ra = {}, rb = {};
  if (room.rated) { applyRating(a, b, sa > sb ? 1 : sa < sb ? 0 : 0.5, ra, rb); bump(pairRated, pairKey(a, b)); }
  send(a, { t: 'end', you: sa, them: sb, ...ra });
  send(b, { t: 'end', you: sb, them: sa, ...rb });
}

// Обновить рейтинг пары; в out-объекты кладём новый рейтинг и изменение для сообщений
function applyRating(a, b, result, outA, outB) {
  const pa = db.players[a.pid], pb = db.players[b.pid];
  if (!pa || !pb) return;
  const [da, dbb] = rate(pa, pb, result);
  Object.assign(outA, { rating: pa.rating, delta: da });
  Object.assign(outB, { rating: pb.rating, delta: dbb });
}

function unqueue(ws) {
  const i = queue.findIndex(q => q.ws === ws);
  if (i >= 0) queue.splice(i, 1);
}

// Подбор пар: чем дольше ждёшь, тем шире допустимая разница рейтинга
function matchQueue() {
  const now = Date.now();
  for (let i = 0; i < queue.length; i++) {
    const a = queue[i];
    const ra = db.players[a.ws.pid]?.rating ?? START_RATING;
    let best = -1, bestDiff = Infinity;
    for (let j = i + 1; j < queue.length; j++) {
      const b = queue[j];
      if (b.ws.pid === a.ws.pid) continue;   // один игрок в двух окнах
      const rb = db.players[b.ws.pid]?.rating ?? START_RATING;
      const diff = Math.abs(ra - rb);
      const allow = 150 + 40 * Math.min((now - a.since) / 1000, (now - b.since) / 1000);
      if (diff <= allow && diff < bestDiff) { best = j; bestDiff = diff; }
    }
    if (best < 0) continue;
    const b = queue[best];
    queue.splice(best, 1);
    queue.splice(i, 1);
    i--;
    const code = newCode();
    const r = { code, players: [a.ws, b.ws], state: 'waiting', ranked: true };
    rooms.set(code, r);
    a.ws.room = r;
    b.ws.room = r;
    startMatch(r);
  }
}
setInterval(matchQueue, 1000);

function leave(ws) {
  unqueue(ws);
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  room.players = room.players.filter(p => p !== ws);
  const rest = room.players[0];
  if (rest) {
    const msg = { t: 'oppLeft' };
    if (room.state === 'playing') {
      clearTimeout(room.endTimer);
      room.state = 'ended';
      if (room.rated) { applyRating(rest, ws, 1, msg, {}); bump(pairRated, pairKey(rest, ws)); }   // вышел из рейтингового боя — поражение
    }
    send(rest, msg);
  }
  if (!room.players.length) {
    clearTimeout(room.endTimer);
    clearTimeout(room.waitTimer);
    rooms.delete(room.code);
  }
}

wss.on('connection', (ws, req) => {
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });
  // Сервер стоит за прокси (Caddy/nginx) и снаружи не виден, поэтому адрес игрока — в X-Forwarded-For
  ws.ip = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress || '';
  const conns = (connByIp.get(ws.ip) || 0) + 1;
  connByIp.set(ws.ip, conns);
  ws.on('close', () => {
    const left = (connByIp.get(ws.ip) || 1) - 1;
    if (left > 0) connByIp.set(ws.ip, left); else connByIp.delete(ws.ip);
  });
  if (conns > MAX_CONN_PER_IP) { send(ws, { t: 'error', msg: 'Слишком много подключений' }); return ws.close(); }
  ws.msgAt = Date.now();
  ws.msgN = 0;

  ws.on('message', raw => {
    // Не больше MAX_MSG_PER_10S сообщений за 10 секунд с одного соединения
    const tnow = Date.now();
    if (tnow - ws.msgAt > 10000) { ws.msgAt = tnow; ws.msgN = 0; }
    if (++ws.msgN > MAX_MSG_PER_10S) return;
    let m;
    try { m = JSON.parse(raw); } catch (e) { return; }
    if (!m || typeof m !== 'object') return;
    const room = ws.room;

    switch (m.t) {
      case 'hello': {
        // Профиль игрока: рейтинг и число боёв
        const p = profile(m.id, m.name && cleanName(m.name), ws.ip);
        if (!p) return send(ws, { t: 'error', msg: 'Нет профиля' });
        ws.pid = m.id;
        send(ws, publicProfile(p));
        break;
      }
      case 'quick': {
        const p = profile(m.id, cleanName(m.name), ws.ip);
        if (!p) return send(ws, { t: 'error', msg: 'Нет профиля' });
        leave(ws);
        ws.pid = m.id;
        ws.name = cleanName(m.name);
        queue.push({ ws, since: Date.now() });
        send(ws, { ...publicProfile(p), t: 'queued' });
        matchQueue();
        break;
      }
      case 'daily': {
        // Результат ежедневного вызова; без score — просто запрос таблицы
        if (!validId(m.id)) return send(ws, { t: 'error', msg: 'Нет профиля' });
        const today = dayStr(), yesterday = dayStr(Date.now() - 86400000);
        const day = m.day === yesterday ? yesterday : today;   // партия могла начаться до полуночи
        const raw = Math.floor(Number(m.score));
        // Результат принимаем, если он правдоподобен, не слишком частый и профиль не из потока новых с одного IP
        if (m.score !== undefined && m.score !== null && raw >= 0 && raw <= DAILY_MAX_SCORE
            && Date.now() - (ws.dailyAt || 0) >= DAILY_MIN_GAP) {
          const b = db.daily[day] || (db.daily[day] = {});
          const e = b[m.id];
          if (e || allowNewId(ws.ip)) {
            ws.dailyAt = Date.now();
            if (!e || raw > e.score) b[m.id] = { name: cleanName(m.name), score: raw };
            else e.name = cleanName(m.name);
            pruneDaily();
            saveDb();
          }
        }
        send(ws, dailyReply(day, m.id));
        break;
      }
      case 'top': {
        // Лучшие по рейтингу (только сыгравшие рейтинговые бои) и своё место
        const all = Object.entries(db.players).filter(([, p]) => p.games > 0)
          .sort((x, y) => y[1].rating - x[1].rating);
        const i = all.findIndex(([id]) => id === m.id);
        send(ws, {
          t: 'topList', total: all.length, rank: i >= 0 ? i + 1 : 0,
          top: all.slice(0, 20).map(([id, p]) => ({ name: p.name, rating: p.rating, games: p.games, you: id === m.id })),
        });
        break;
      }
      case 'create': {
        leave(ws);
        const code = newCode();
        const r = { code, players: [ws], state: 'waiting' };
        r.waitTimer = setTimeout(() => { if (r.state === 'waiting') { send(ws, { t: 'error', msg: 'Время ожидания вышло' }); leave(ws); } }, WAIT_TTL);
        rooms.set(code, r);
        ws.room = r;
        ws.name = cleanName(m.name);
        if (validId(m.id)) ws.pid = m.id;
        send(ws, { t: 'created', code });
        break;
      }
      case 'join': {
        const r = rooms.get(String(m.code || '').trim());
        if (!r || !r.players.length) return send(ws, { t: 'error', msg: 'Комната не найдена' });
        if (r.players.includes(ws)) return;
        if (r.players.length >= 2) return send(ws, { t: 'error', msg: 'В этой комнате уже играют' });
        leave(ws);
        ws.name = cleanName(m.name);
        if (validId(m.id)) ws.pid = m.id;
        r.players.push(ws);
        ws.room = r;
        startMatch(r);
        break;
      }
      case 'state': {
        // Ход игрока: запоминаем очки и пересылаем поле сопернику
        if (!room || room.state !== 'playing') return;
        if (Date.now() > room.endAt + GRACE) return;
        // Счёт принимаем, только если ход возможен по правилам; иначе остаётся последний честный
        const st = room.check.get(ws);
        if (!st) return;
        if (!checkMove(st, m, Date.now())) {
          if (++st.bad === 1 || process.env.BB_DEBUG) console.warn(`подозрительный ход: ${ws.name} (${ws.ip}) счёт ${m.score} при ${st.score}, n=${m.n} placed=${(m.placed || []).length} cleared=${(m.cleared || []).length} combo=${st.combo} cnt=${st.cnt}`);
        }
        const score = st.score;
        room.scores.set(ws, score);
        send(other(room, ws), { ...m, t: 'opp', score });
        break;
      }
      case 'ev': {
        // Обезличенные события игры (запуск, сыгранная партия) — для статистики
        if (!validId(m.id) || !Array.isArray(m.list)) return;
        m.ip = ws.ip;
        trackEvents(m);
        send(ws, { t: 'evAck', latest: LATEST.code });
        break;
      }
      case 'backup': {
        // Сохранить копию прогресса; в ответ — код восстановления (один на игрока, не меняется)
        if (!validId(m.id) || typeof m.data !== 'string' || m.data.length > BACKUP_MAX) return send(ws, { t: 'error', msg: 'Копия не сохранена' });
        try { if (typeof JSON.parse(m.data) !== 'object') throw 0; } catch (e) { return send(ws, { t: 'error', msg: 'Копия не сохранена' }); }
        let b = db.backups[m.id];
        if (!b) {
          if (!allowNewId(ws.ip)) return send(ws, { t: 'error', msg: 'Копия не сохранена' });
          b = db.backups[m.id] = { code: newBackupCode() };
          db.codes[b.code] = m.id;
        }
        b.data = m.data;
        b.at = Date.now();
        saveDb();
        send(ws, { t: 'backupOk', code: fmtCode(b.code) });
        break;
      }
      case 'restore': {
        // Вернуть прогресс по коду
        if (!restoreAllowed(ws.ip)) return send(ws, { t: 'restoreData', err: 'tooMany' });
        const id = db.codes[normCode(m.code)];
        const b = id && db.backups[id];
        if (!b) return send(ws, { t: 'restoreData', err: 'notFound' });
        send(ws, { t: 'restoreData', data: b.data, at: b.at });
        break;
      }
      case 'emoji': {
        // Реакция сопернику: номер смайлика, не чаще раза в секунду
        const e = Math.floor(Number(m.e));
        if (!room || !(e >= 0 && e < 16) || Date.now() - (ws.emojiAt || 0) < 900) return;
        ws.emojiAt = Date.now();
        send(other(room, ws), { t: 'emoji', e });
        break;
      }
      case 'rewardAck': {
        // Клиент получил награду за сезон — больше не присылаем
        const p = db.players[ws.pid];
        if (p && p.reward && p.reward.season === m.season) { delete p.reward; saveDb(); }
        break;
      }
      case 'rematch': {
        if (!room || room.state !== 'ended' || room.players.length < 2) return;
        room.ready.add(ws);
        send(other(room, ws), { t: 'oppRematch' });
        if (room.ready.size === 2) startMatch(room);
        break;
      }
      case 'leave':
      case 'cancel':
        leave(ws);
        break;
    }
  });

  ws.on('close', () => leave(ws));
  ws.on('error', () => leave(ws));
});

// Пинг раз в 25 с: держит соединение через прокси и выкидывает «мёртвые» сокеты
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 25000);

if (!process.env.STATS_KEY) saveDb();   // ключ статистики создан при первом запуске — сохраняем
server.listen(PORT, HOST, () => {
  console.log(`Block Boom сервер: http://localhost:${PORT}  (WebSocket: /ws)`);
});
