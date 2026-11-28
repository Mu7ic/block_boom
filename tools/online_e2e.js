// Настоящий бой: игра (Godot) против локального сервера. Сверяет счёт игры со счётом сервера.
// Запуск:  node tools/online_e2e.js "путь/к/Godot_console.exe"
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn } = require('child_process');
const WS = require(path.join(__dirname, '..', 'server', 'node_modules', 'ws'));

const GODOT = process.argv[2];
const PORT = 8890 + Math.floor(Math.random() * 100);
const DATA = path.join(os.tmpdir(), `bb-e2e-${PORT}.json`);
fs.writeFileSync(DATA, '{"players":{},"daily":{}}');
const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT, HOST: '127.0.0.1', DATA_FILE: DATA, DURATION_MS: '30000', BB_DEBUG: '1' }, stdio: ['ignore', 'ignore', 'inherit'],
});
const done = code => { srv.kill(); try { fs.unlinkSync(DATA); } catch (e) { /* уже удалён */ } process.exit(code); };

setTimeout(() => {
  // Соперник «из другой сети» — стоит в очереди и не ходит
  const w = new WS(`ws://127.0.0.1:${PORT}/ws`, { headers: { 'X-Forwarded-For': '10.1.1.1' } });
  let serverScore = -1, ranked = null;
  w.on('open', () => w.send(JSON.stringify({ t: 'quick', id: 'e'.repeat(32), name: 'Rival' })));
  w.on('message', raw => {
    const m = JSON.parse(raw);
    if (m.t === 'start') ranked = m.ranked;
    if (m.t === 'end') serverScore = m.them;
  });
  const g = spawn(GODOT, ['--path', path.join(__dirname, '..'), 'res://tools/online_e2e.tscn', '--', '--test-save', `port=${PORT}`]);
  let out = '';
  g.stdout.on('data', d => { out += d; });
  g.on('exit', async () => {
    for (let k = 0; k < 40 && serverScore < 0; k++) await new Promise(r => setTimeout(r, 100));
    const line = (out.match(/E2E .*/) || ['E2E нет вывода'])[0];
    console.log(line);
    const gameScore = Number((line.match(/score=(\d+)/) || [])[1]);
    console.log(`сервер принял счёт: ${serverScore}, рейтинговый: ${ranked}`);
    const ok = gameScore > 0 && gameScore === serverScore && ranked === true;
    console.log(ok ? 'ВСЁ ХОРОШО: счёт игры и сервера совпал' : 'FAIL: счёт игры и сервера разошёлся');
    done(ok ? 0 : 1);
  });
}, 1200);
setTimeout(() => { console.log('FAIL: время вышло'); done(1); }, 110000);
