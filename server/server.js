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
let db = { players: {}, daily: {}, act: {}, stats: {} };
try { db = { players: {}, daily: {}, act: {}, stats: {}, ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) }; } catch (e) { /* первый запуск */ }
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
function profile(id, name) {
  if (!validId(id)) return null;
  let p = db.players[id];
  if (!p) { p = db.players[id] = { name: 'Игрок', rating: START_RATING, games: 0, wins: 0 }; saveDb(); }
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
const APK_FILE = process.env.APK_FILE || path.join(SITE_DIR, 'BlockBoom.apk');
const APK_FALLBACK = 'https://github.com/Mu7ic/block_boom/releases/latest/download/BlockBoom.apk';
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
  if (url === '/blockboom/BlockBoom.apk') {
    if (!fs.existsSync(APK_FILE)) {
      res.writeHead(302, { Location: APK_FALLBACK });
      res.end();
      return;
    }
    return sendFile(res, APK_FILE, 'application/vnd.android.package-archive',
      { 'Content-Disposition': 'attachment; filename="BlockBoom.apk"', 'Cache-Control': 'no-cache' });
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
  room.scores = new Map(room.players.map(p => [p, 0]));
  room.ready = new Set();
  room.endAt = Date.now() + COUNTDOWN + DURATION;
  for (const p of room.players) {
    send(p, { t: 'start', countdown: COUNTDOWN, duration: DURATION, opponent: other(room, p).name, ranked: !!room.ranked });
  }
  room.endTimer = setTimeout(() => finish(room), COUNTDOWN + DURATION + GRACE);
}

function finish(room) {
  room.state = 'ended';
  const [a, b] = room.players;
  if (!a || !b) return;
  const sa = room.scores.get(a) || 0, sb = room.scores.get(b) || 0;
  const ra = {}, rb = {};
  if (room.ranked) applyRating(a, b, sa > sb ? 1 : sa < sb ? 0 : 0.5, ra, rb);
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
      if (room.ranked) applyRating(rest, ws, 1, msg, {});   // вышел из рейтингового боя — поражение
    }
    send(rest, msg);
  }
  if (!room.players.length) {
    clearTimeout(room.endTimer);
    clearTimeout(room.waitTimer);
    rooms.delete(room.code);
  }
}

wss.on('connection', ws => {
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });

  ws.on('message', raw => {
    let m;
    try { m = JSON.parse(raw); } catch (e) { return; }
    const room = ws.room;

    switch (m.t) {
      case 'hello': {
        // Профиль игрока: рейтинг и число боёв
        const p = profile(m.id, m.name && cleanName(m.name));
        if (!p) return send(ws, { t: 'error', msg: 'Нет профиля' });
        ws.pid = m.id;
        send(ws, publicProfile(p));
        break;
      }
      case 'quick': {
        const p = profile(m.id, cleanName(m.name));
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
        if (m.score !== undefined && m.score !== null) {
          const score = Math.max(0, Math.min(1e7, Math.floor(Number(m.score) || 0)));
          const b = db.daily[day] || (db.daily[day] = {});
          const e = b[m.id];
          if (!e || score > e.score) b[m.id] = { name: cleanName(m.name), score };
          else e.name = cleanName(m.name);
          pruneDaily();
          saveDb();
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
        const score = Math.max(0, Math.floor(Number(m.score) || 0));
        room.scores.set(ws, score);
        send(other(room, ws), { ...m, t: 'opp', score });
        break;
      }
      case 'ev': {
        // Обезличенные события игры (запуск, сыгранная партия) — для статистики
        if (!validId(m.id) || !Array.isArray(m.list)) return;
        trackEvents(m);
        send(ws, { t: 'evAck', latest: LATEST.code });
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
