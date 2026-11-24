// Сервер онлайн-боя «Блок Бум!»
// - отдаёт игру (../index.html) по HTTP
// - по WebSocket на /ws держит комнаты на двоих: код из 4 цифр, общий таймер 3 минуты,
//   пересылает сопернику состояние поля, в конце сам объявляет итог.
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

// ---------- HTTP: отдаём игру ----------
const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  if (url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`ok rooms=${rooms.size} players=${wss.clients.size}`);
    return;
  }
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

// ---------- WebSocket: комнаты ----------
const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 32 * 1024 });
const rooms = new Map(); // код → { code, players: [ws], state: 'waiting'|'playing'|'ended', ... }

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
    send(p, { t: 'start', countdown: COUNTDOWN, duration: DURATION, opponent: other(room, p).name });
  }
  room.endTimer = setTimeout(() => finish(room), COUNTDOWN + DURATION + GRACE);
}

function finish(room) {
  room.state = 'ended';
  const [a, b] = room.players;
  if (!a || !b) return;
  const sa = room.scores.get(a) || 0, sb = room.scores.get(b) || 0;
  send(a, { t: 'end', you: sa, them: sb });
  send(b, { t: 'end', you: sb, them: sa });
}

function leave(ws) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  room.players = room.players.filter(p => p !== ws);
  const rest = room.players[0];
  if (rest) {
    if (room.state === 'playing') { clearTimeout(room.endTimer); room.state = 'ended'; }
    send(rest, { t: 'oppLeft' });
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
      case 'create': {
        leave(ws);
        const code = newCode();
        const r = { code, players: [ws], state: 'waiting' };
        r.waitTimer = setTimeout(() => { if (r.state === 'waiting') { send(ws, { t: 'error', msg: 'Время ожидания вышло' }); leave(ws); } }, WAIT_TTL);
        rooms.set(code, r);
        ws.room = r;
        ws.name = cleanName(m.name);
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
      case 'rematch': {
        if (!room || room.state !== 'ended' || room.players.length < 2) return;
        room.ready.add(ws);
        send(other(room, ws), { t: 'oppRematch' });
        if (room.ready.size === 2) startMatch(room);
        break;
      }
      case 'leave':
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
  console.log(`Блок Бум! сервер: http://localhost:${PORT}  (WebSocket: /ws)`);
});
