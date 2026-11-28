// Перенос прогресса: игра (Godot) против локального сервера, плюс проверка защиты от перебора кодов.
// Запуск:  node tools/backup_e2e.js "путь/к/Godot_console.exe"
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn } = require('child_process');
const WS = require(path.join(__dirname, '..', 'server', 'node_modules', 'ws'));

const GODOT = process.argv[2];
const PORT = 8990 + Math.floor(Math.random() * 100);
const DATA = path.join(os.tmpdir(), `bb-backup-${PORT}.json`);
fs.writeFileSync(DATA, '{"players":{},"daily":{}}');
const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'server.js')], {
  env: { ...process.env, PORT, HOST: '127.0.0.1', DATA_FILE: DATA }, stdio: 'ignore',
});
const done = code => { srv.kill(); try { fs.unlinkSync(DATA); } catch (e) { /* уже удалён */ } process.exit(code); };

setTimeout(() => {
  const g = spawn(GODOT, ['--path', path.join(__dirname, '..'), 'res://tools/backup_e2e.tscn', '--', '--test-save', `port=${PORT}`]);
  let out = '';
  g.stdout.on('data', d => { out += d; });
  g.on('exit', async () => {
    const lines = out.split(/\r?\n/).filter(l => /^(ok   |FAIL |E2E )/.test(l));
    console.log(lines.join('\n'));
    let fails = /E2E fails=0/.test(out) ? 0 : 1;
    // Перебор кодов с одного адреса: после 10 попыток в час сервер перестаёт отвечать по существу
    const w = new WS(`ws://127.0.0.1:${PORT}/ws`, { headers: { 'X-Forwarded-For': '10.9.9.9' } });
    const got = [];
    w.on('message', m => got.push(JSON.parse(m)));
    await new Promise(r => w.on('open', r));
    for (let k = 0; k < 12; k++) w.send(JSON.stringify({ t: 'restore', code: 'AAAA-AAAA-AAA' + 'ABCDEFGHJKLM'[k] }));
    await new Promise(r => setTimeout(r, 500));
    const notFound = got.filter(m => m.err === 'notFound').length, tooMany = got.filter(m => m.err === 'tooMany').length;
    const ok = notFound === 10 && tooMany === 2;
    console.log((ok ? 'ok   ' : 'FAIL ') + `перебор кодов: ${notFound} обычных отказов, затем ${tooMany} «слишком много попыток»`);
    if (!ok) fails++;
    console.log(fails ? 'ЕСТЬ ОШИБКИ' : 'ВСЁ ХОРОШО');
    done(fails ? 1 : 0);
  });
}, 1200);
setTimeout(() => { console.log('FAIL: время вышло'); done(1); }, 60000);
