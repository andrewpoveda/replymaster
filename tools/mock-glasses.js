#!/usr/bin/env node
// Mock M6 glasses app: a TCP SERVER on port 8787 speaking newline-delimited JSON, like glasses-hello's
// caption receiver. Prints each snapshot from the iPhone and lets you send glasses actions from stdin.
// Zero dependencies. No Bonjour: in Vocal, type this Mac's IP (simulator: 127.0.0.1). See docs/PROTOCOL.md.
//
//   node tools/mock-glasses.js [port]
//   c            -> {"action":"choosing"}
//   s <text>     -> {"action":"select","text":"<text>"}   (trailing tone word: neutral|warm|firm|joking)
//   1 / 2 / 3    -> select reply #n from the last snapshot
//   h            -> {"action":"help"}
//   x            -> {"action":"help_cancel"}
//   k            -> {"action":"cancel"}
//
// Non-interactive (for scripted tests): MOCK_SCRIPT="c;1;h;x" with optional MOCK_STEP_MS.

const net = require('net');
const readline = require('readline');

const PORT = Number(process.argv[2] || 8787);
const TONES = ['neutral', 'warm', 'firm', 'joking'];
let client = null;
let last = null;

function send(obj) {
  if (!client) return console.log('! no iPhone connected');
  const s = JSON.stringify(obj);
  client.write(s + '\n');
  console.log('-> ' + s);
}

function render(st) {
  const line = '─'.repeat(50);
  console.log(`\n┌${line}  rev ${st.rev}  [${st.state}, mic ${st.mic}]`);
  for (const l of String(st.text || '').split('\n')) console.log(`│  ${l}`);
  console.log(`└${line}`);
}

const server = net.createServer((sock) => {
  if (client) client.destroy();
  client = sock;
  sock.setNoDelay(true);
  console.log(`+ iPhone connected from ${sock.remoteAddress}`);
  let buf = '';
  sock.on('data', (d) => {
    buf += d.toString('utf8');
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const lineStr = buf.slice(0, i); buf = buf.slice(i + 1);
      if (!lineStr.trim()) continue;
      try { last = JSON.parse(lineStr); render(last); } catch { console.log('? bad json: ' + lineStr.slice(0, 80)); }
    }
  });
  sock.on('close', () => { if (client === sock) { client = null; console.log('- iPhone disconnected'); } });
  sock.on('error', () => {});
});

function command(raw) {
  const line = raw.trim();
  if (!line) return;
  const [cmd, ...rest] = line.split(' ');
  if (cmd === 'c') send({ action: 'choosing' });
  else if (cmd === 'h') send({ action: 'help' });
  else if (cmd === 'x') send({ action: 'help_cancel' });
  else if (cmd === 'k') send({ action: 'cancel' });
  else if (['1', '2', '3'].includes(cmd)) {
    const r = last && last.replies && last.replies[Number(cmd) - 1];
    r ? send({ action: 'select', text: r }) : console.log('! no such reply');
  } else if (cmd === 's') {
    const words = rest.slice();
    let tone;
    if (TONES.includes(words[words.length - 1])) tone = words.pop();
    const msg = { action: 'select', text: words.join(' ') };
    if (tone) msg.tone = tone;
    send(msg);
  } else console.log('commands: c | s <text> [tone] | 1 2 3 | h | x | k');
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`mock glasses listening on tcp://0.0.0.0:${PORT} (newline JSON)`);
  if (process.env.MOCK_SCRIPT) {
    const steps = process.env.MOCK_SCRIPT.split(';');
    const ms = Number(process.env.MOCK_STEP_MS || 3000);
    const wait = setInterval(() => {
      if (!client) return;
      clearInterval(wait);
      steps.forEach((s, i) => setTimeout(() => command(s), (i + 1) * ms));
    }, 200);
  } else {
    readline.createInterface({ input: process.stdin }).on('line', command);
  }
});
