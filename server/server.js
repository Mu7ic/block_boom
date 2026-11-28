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
let db = { players: {}, daily: {} };
try { db = { players: {}, daily: {}, ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) }; } catch (e) { /* первый запуск */ }
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
  t: 'profile', rating: p.rating, games: p.games, wins: p.wins,
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

server.listen(PORT, HOST, () => {
  console.log(`Block Boom сервер: http://localhost:${PORT}  (WebSocket: /ws)`);
});
