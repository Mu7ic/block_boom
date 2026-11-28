// Проверка защиты сервера от накруток. Сам поднимает сервер на свободном порту с короткими боями.
// Запуск:  node tools/anticheat_test.js
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn } = require('child_process');
const WS = require(path.join(__dirname, '..', 'server', 'node_modules', 'ws'));

const PORT = 8790 + Math.floor(Math.random() * 100);
const DATA = path.join(os.tmpdir(), `bb-anticheat-${PORT}.json`);
fs.writeFileSync(DATA, '{"players":{},"daily":{}}');
const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT, HOST: '127.0.0.1', DATA_FILE: DATA, DURATION_MS: '1200', MAX_NEW_IDS_PER_IP_DAY: '4' },
  stdio: 'ignore',
});

let fails = 0;
const check = (ok, what) => { console.log((ok ? 'ok   ' : 'FAIL ') + what); if (!ok) fails++; };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const id = ch => ch.repeat(32);

function open(ip) {
  return new Promise((res, rej) => {
    const w = new WS(`ws://127.0.0.1:${PORT}/ws`, { headers: { 'X-Forwarded-For': ip } });
    w.q = [];
    w.on('message', m => w.q.push(JSON.parse(m)));
    w.on('open', () => res(w));
    w.on('error', rej);
    w.tx = m => w.send(JSON.stringify(m));
    w.rx = (t, ms = 9000) => new Promise((r, j) => {
      const t0 = Date.now();
      const i = setInterval(() => {
        const k = w.q.findIndex(m => m.t === t);
        if (k >= 0) { clearInterval(i); r(w.q.splice(k, 1)[0]); }
        else if (Date.now() - t0 > ms) { clearInterval(i); j(new Error('нет ответа ' + t)); }
      }, 15);
    });
  });
}
const board = cells => { const b = Array(64).fill(null); cells.forEach(i => { b[i] = '#ff0000'; }); return b; };

(async () => {
  await sleep(1200);
  // --- 1. Честные ходы засчитываются, невозможный счёт — нет
  const a = await open('10.0.0.1'), b = await open('10.0.0.2');
  a.tx({ t: 'quick', id: id('a'), name: 'A' });
  b.tx({ t: 'quick', id: id('b'), name: 'B' });
  let sa = await a.rx('start'); await b.rx('start');
  check(sa.ranked === true && sa.why === '', 'разные сети: бой рейтинговый');
  await sleep(3100);   // отсчёт
  a.tx({ t: 'state', score: 40, board: board([0, 1, 2, 3]), placed: [0, 1, 2, 3], cleared: [], n: 0 });
  await sleep(200);
  a.tx({ t: 'state', score: 3180, board: board([]), placed: [4, 5, 6, 7], cleared: [0, 1, 2, 3, 4, 5, 6, 7].map(i => [i, '#f00']), n: 1 });
  let o = await b.rx('opp'); o = await b.rx('opp');
  check(o.score === 3180, `честный ход с линией и чистым полем принят (${o.score})`);
  b.tx({ t: 'state', score: 999999, board: board([10]), placed: [10], cleared: [], n: 0 });
  o = await a.rx('opp');
  check(o.score === 10, `миллион за одну клетку урезан до 10 (${o.score})`);
  await sleep(200);
  b.tx({ t: 'state', score: 1999999, board: board([10, 11]), placed: [11], cleared: Array(39).fill([0, '#f00']), n: 6 });
  o = await a.rx('opp');
  check(o.score === 10, `линии без клеток на поле не засчитаны (${o.score})`);
  let ea = await a.rx('end'), eb = await b.rx('end');
  check(ea.you === 3180 && eb.you === 10 && ea.delta > 0 && eb.delta < 0, `итог боя по честному счёту: ${ea.you}:${eb.you}, рейтинг ${ea.delta}/${eb.delta}`);

  // --- 2. Одна пара — не больше 3 рейтинговых боёв в день
  for (let k = 2; k <= 4; k++) {
    a.tx({ t: 'rematch' }); b.tx({ t: 'rematch' });
    sa = await a.rx('start'); await b.rx('start');
    if (k <= 3) check(sa.ranked === true, `бой ${k} этой пары — рейтинговый`);
    else check(sa.ranked === false && sa.why === 'pairLimit', `бой ${k} этой пары — без рейтинга (${sa.why})`);
    ea = await a.rx('end'); await b.rx('end');
    if (k === 4) check(ea.delta === undefined, 'после лимита рейтинг не меняется');
  }
  a.close(); b.close();

  // --- 3. Два игрока с одного IP — без рейтинга
  const c = await open('10.0.0.9'), d = await open('10.0.0.9');
  c.tx({ t: 'quick', id: id('c'), name: 'C' });
  d.tx({ t: 'quick', id: id('d'), name: 'D' });
  const sc = await c.rx('start');
  check(sc.ranked === false && sc.why === 'sameNet', `одна сеть: бой без рейтинга (${sc.why})`);
  c.close(); d.close();

  // --- 4. Новые профили с одного IP ограничены (в тесте — 4 в день; c и d уже заняли два)
  const e = await open('10.0.0.9');
  const got = [];
  for (const ch of ['1', '2', '3']) {
    e.tx({ t: 'hello', id: id(ch), name: 'X' });
    await sleep(150);
    got.push(e.q.splice(0).map(m => m.t).join(','));
  }
  check(got[0] === 'profile' && got[1] === 'profile' && got[2] === 'error', `пятый новый профиль с IP отклонён (${got.join(' | ')})`);
  e.tx({ t: 'hello', id: id('c'), name: 'C' });
  check((await e.rx('profile')).rating > 0, 'старый профиль с этого IP работает');
  e.close();

  // --- 5. Вызов дня: неправдоподобный счёт не попадает в таблицу
  const f = await open('10.0.0.20');
  f.tx({ t: 'daily', id: id('f'), name: 'F', score: 50000000 });
  let t = await f.rx('dailyTop');
  check(t.total === 0, `50 миллионов в вызове дня отклонены (в таблице ${t.total})`);
  f.tx({ t: 'daily', id: id('f'), name: 'F', score: 12000 });
  t = await f.rx('dailyTop');
  check(t.total === 1 && t.top[0].score === 12000, 'обычный результат принят');
  f.tx({ t: 'daily', id: id('f'), name: 'F', score: 90000 });
  t = await f.rx('dailyTop');
  check(t.top[0].score === 12000, 'повторная отправка через секунду не принята');
  f.close();

  // --- 6. Поток сообщений с одного соединения обрезается
  const g = await open('10.0.0.30');
  for (let k = 0; k < 200; k++) g.tx({ t: 'top', id: id('9') });
  await sleep(600);
  const n = g.q.filter(m => m.t === 'topList').length;
  check(n > 0 && n <= 80, `из 200 запросов подряд обработано ${n}`);
  g.close();
})().catch(e => { console.log('FAIL ' + e.message); fails++; }).finally(() => {
  srv.kill();
  try { fs.unlinkSync(DATA); } catch (e) { /* уже удалён */ }
  console.log(fails ? `ОШИБОК: ${fails}` : 'ВСЁ ХОРОШО');
  process.exit(fails ? 1 : 0);
});
