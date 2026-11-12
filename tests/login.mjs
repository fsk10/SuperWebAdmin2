// Browser login (session cookie) tests against the local SWA2 test server.
// Usage: node tests/login.mjs   (reads testserver/credentials.env)
import { readFileSync } from 'node:fs'

const env = Object.fromEntries(
  readFileSync(new URL('../testserver/credentials.env', import.meta.url), 'latin1')
    .split(/\r?\n/).filter(l => l.includes('=')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))
const base = env.SWA_URL
const host = new URL(base).host

let failed = 0
const check = (name, ok, info = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  - ' + info : ''}`)
  if (!ok) failed++
}
const browser = { Accept: 'text/html,application/xhtml+xml', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Site': 'same-origin' }
const login = (user, pass, extra = {}) => fetch(base + '/login', {
  method: 'POST', redirect: 'manual',
  headers: { ...browser, 'Content-Type': 'application/x-www-form-urlencoded', Origin: `http://${host}`, ...extra },
  body: new URLSearchParams({ Username: user, Password: pass, Next: '/current_mutators' }).toString(),
})

// a browser without login gets the login page (no Basic Auth popup); scripts get 401 + challenge
let r = await fetch(base + '/current_game', { headers: browser })
let t = await r.text()
check('browser without login -> login page', t.includes('action="/login"') && !r.headers.get('www-authenticate'))
check('login page shows the server name', /class="name">[^<]+</.test(t), (t.match(/class="name">([^<]*)</) || [])[1])
check('login page returns to the requested page', t.includes('name="Next" value="/current_game"'))
r = await fetch(base + '/current_game')
check('script without login -> 401 with Basic challenge', r.status === 401 && /basic/i.test(r.headers.get('www-authenticate') || ''))

r = await login(env.SWA_ADMIN_USER, 'wrong-password')
t = await r.text()
check('wrong password -> error on the login page', r.status === 200 && t.includes('Wrong username or password'))

r = await login(env.SWA_ADMIN_USER, env.SWA_ADMIN_PASS, { 'Sec-Fetch-Site': 'cross-site', Origin: 'http://evil.example' })
check('cross-site login refused', r.status === 403)

r = await login(env.SWA_ADMIN_USER, env.SWA_ADMIN_PASS)
const cookie = (r.headers.get('set-cookie') || '').split(';')[0]
check('login -> 303 to the requested page', r.status === 303 && r.headers.get('location') === '/current_mutators', `${r.status} ${r.headers.get('location')}`)
check('session cookie is HttpOnly + SameSite=Strict', /^swa2s=[0-9A-F]{32}$/.test(cookie) && /HttpOnly/.test(r.headers.get('set-cookie')) && /SameSite=Strict/.test(r.headers.get('set-cookie')))

r = await fetch(base + '/current_players', { headers: { ...browser, Cookie: cookie } })
t = await r.text()
check('page with session cookie', r.status === 200 && t.includes('class="topbar"') && t.includes(`<b>${env.SWA_ADMIN_USER}</b>`))
r = await fetch(base + '/current_players', { headers: { ...browser, Cookie: 'swa2s=0123456789ABCDEF0123456789ABCDEF' } })
check('made-up session cookie -> login page', (await r.text()).includes('action="/login"'))

r = await login(env.SWA_ADMIN_USER, env.SWA_ADMIN_PASS, {})
const next = (await fetch(base + '/login', { method: 'POST', redirect: 'manual', headers: { ...browser, 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ Username: env.SWA_ADMIN_USER, Password: env.SWA_ADMIN_PASS, Next: '//evil.example/x' }).toString() })).headers.get('location')
check('Next cannot point to another site', next && next.startsWith('/') && !next.startsWith('//'), next)

r = await fetch(base + '/logout?u=' + env.SWA_ADMIN_USER, { headers: { ...browser, Cookie: cookie }, redirect: 'manual' })
check('logout -> login page, cookie cleared', r.status === 303 && r.headers.get('location').startsWith('/login') && /Max-Age=0/.test(r.headers.get('set-cookie') || ''))
r = await fetch(base + '/current_players', { headers: { ...browser, Cookie: cookie } })
check('session is gone after logout', (await r.text()).includes('action="/login"'))

// Basic Auth (c00lbot, UpdateScript) still works
r = await fetch(base + '/current_players', { headers: { Authorization: 'Basic ' + Buffer.from(`${env.SWA_ADMIN_USER}:${env.SWA_ADMIN_PASS}`).toString('base64') } })
check('Basic Auth still works for scripts', r.status === 200 && /No Players Connected|KickPlayer/.test(await r.text()))

console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED')
process.exit(failed ? 1 : 0)
