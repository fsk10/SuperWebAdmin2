// Development helper: http://127.0.0.1:7798/ -> the local SWA2 test server with Basic
// Auth added, so a browser (or browser automation) can look at the pages without an
// auth dialog. The browser's Host header is passed through unchanged, so the CSRF
// check sees a same-origin request. Loopback only.
//   node tests/auth_proxy.mjs [user]      (user: admin (default) | mod | smod)
import http from 'node:http'
import { readFileSync } from 'node:fs'

const env = Object.fromEntries(
  readFileSync(new URL('../testserver/credentials.env', import.meta.url), 'latin1')
    .split(/\r?\n/).filter(l => l.includes('=')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))
const who = (process.argv[2] || 'admin').toUpperCase()
const user = env[`SWA_${who}_USER`], pass = env[`SWA_${who}_PASS`]
const target = new URL(env.SWA_URL)
const authz = 'Basic ' + Buffer.from(`${user}:${pass}`).toString('base64')

http.createServer((req, res) => {
  const up = http.request({
    host: target.hostname, port: target.port, method: req.method, path: req.url,
    headers: { ...req.headers, authorization: authz },
  }, r => { res.writeHead(r.statusCode, r.headers); r.pipe(res) })
  up.on('error', e => { res.writeHead(502); res.end('proxy: ' + e.message) })
  req.pipe(up)
}).listen(7798, '127.0.0.1', () => console.log(`auth proxy for ${user} on http://127.0.0.1:7798/`))
