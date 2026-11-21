#!/usr/bin/env node
// Mock M6 glasses app: a WebSocket SERVER (like the real glasses app) on port 8765.
// Prints each state snapshot from the iPhone and lets you send glasses actions from stdin.
// Zero dependencies (hand-rolled RFC 6455 framing, text frames only). See docs/PROTOCOL.md.
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

const http = require('http');
const crypto = require('crypto');
const readline = require('readline');

const PORT = Number(process.argv[2] || 8765);
const TONES = ['neutral', 'warm', 'firm', 'joking'];
let client = null;
let last = null;

function frame(text) {
  const p = Buffer.from(text, 'utf8');
  let h;
  if (p.length < 126) h = Buffer.from([0x81, p.length]);
  else if (p.length < 65536) { h = Buffer.alloc(4); h[0] = 0x81; h[1] = 126; h.writeUInt16BE(p.length, 2); }
  else { h = Buffer.alloc(10); h[0] = 0x81; h[1] = 127; h.writeBigUInt64BE(BigInt(p.length), 2); }
  return Buffer.concat([h, p]);
}

function send(obj) {
  if (!client) return console.log('! no iPhone connected');
  const s = JSON.stringify(obj);
  client.write(frame(s));
  console.log('-> ' + s);
}

function render(st) {
  const line = '─'.repeat(50);
  console.log(`\n┌${line}  rev ${st.rev}`);
  if (st.state === 'help') console.log('│  ██ HELP SENT ██');
  else if (st.state === 'speaking') console.log(`│  Said: ${st.said}`);
  else {
    console.log(`│  "${st.caption}"   [${st.state}, mic ${st.mic}]`);
    (st.replies || []).forEach((r, i) => console.log(`│  ${i + 1}. ${r}`));
    console.log(`│  ${(st.quick || []).join(' · ')}`);
  }
  console.log(`└${line}`);
}

const server = http.createServer((_, res) => { res.writeHead(426); res.end('WebSocket only'); });
server.on('upgrade', (req, sock) => {
  const key = req.headers['sec-websocket-key'];
  const accept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC11B65').digest('base64');
  sock.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  if (client) client.destroy();
  client = sock;
  console.log(`+ iPhone connected from ${sock.remoteAddress}`);
  let buf = Buffer.alloc(0);
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= 2) {
      const op = buf[0] & 0x0f, masked = buf[1] & 0x80;
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const need = off + (masked ? 4 : 0) + len;
      if (buf.length < need) return;
      let payload = buf.subarray(off + (masked ? 4 : 0), need);
      if (masked) { const m = buf.subarray(off, off + 4); payload = Buffer.from(payload.map((b, i) => b ^ m[i % 4])); }
      buf = buf.subarray(need);
      if (op === 0x9) { const pong = Buffer.concat([Buffer.from([0x8a, payload.length]), payload]); sock.write(pong); }
      else if (op === 0x8) { sock.end(); }
      else if (op === 0x1) {
        try { last = JSON.parse(payload.toString('utf8')); render(last); }
        catch { console.log('? bad json'); }
      }
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
    let words = rest, tone;
    if (TONES.includes(words[words.length - 1])) tone = words.pop();
    const msg = { action: 'select', text: words.join(' ') };
    if (tone) msg.tone = tone;
    send(msg);
  } else console.log('commands: c | s <text> [tone] | 1 2 3 | h | x | k');
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`mock glasses listening on ws://0.0.0.0:${PORT}/`);
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
