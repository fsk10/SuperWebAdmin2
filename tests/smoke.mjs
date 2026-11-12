// Smoke test against the local SWA2 test server.
// Usage: node tests/smoke.mjs [--switch]   (reads testserver/credentials.env)
// --switch also performs c00lbot's map switch (server travels!).
import { readFileSync } from 'node:fs'

const env = Object.fromEntries(
  readFileSync(new URL('../testserver/credentials.env', import.meta.url), 'latin1')
    .split(/\r?\n/).filter(l => l.includes('=')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))

const base = env.SWA_URL
const auth = (u, p) => 'Basic ' + Buffer.from(`${u}:${p}`).toString('base64')
const admin = auth(env.SWA_ADMIN_USER, env.SWA_ADMIN_PASS)
const mod = auth(env.SWA_MOD_USER, env.SWA_MOD_PASS)

let failed = 0
const check = (name, ok, info = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  - ' + info : ''}`)
  if (!ok) failed++
}

export async function req(path, { method = 'GET', authz = admin, form } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(authz ? { Authorization: authz } : {}),
      ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
    },
    body: form ? new URLSearchParams(form).toString() : undefined,
  })
  return { status: res.status, text: await res.text(), type: res.headers.get('content-type') }
}

const pages = ['', 'current_players', 'current_game', 'current_mutators', 'current_rules', 'current_console',
  'defaults_maps', 'defaults_rules', 'defaults_settings', 'superadmin_server', 'superadmin_quicksetconfig']

check('no auth -> 401', (await req('/', { authz: null })).status === 401)
check('wrong password -> 401', (await req('/', { authz: auth('admin', 'wrong') })).status === 401)
for (const p of pages) {
  const r = await req('/' + p)
  check(`GET /${p}`, r.status === 200 && r.text.length > 50, `${r.text.length} bytes`)
}
const players = await req('/current_players')
check('UpdateScript marker in /current_players', /No Players Connected|KickPlayer/i.test(players.text))

const muts = await req('/current_mutators')
const opts = [...muts.text.matchAll(/<option value="([^"]*)"/g)].map(m => m[1])
console.log(`      mutator options listed: ${opts.length}`)

// c00lbot setPassword
const rules = await req('/current_rules', { method: 'POST', form: { MaxPlayers: 10, MaxSpectators: 4, GamePassword: 'smoketest', Apply: 'Apply' } })
check('c00lbot POST /current_rules', rules.status === 200)
const rules2 = await req('/current_rules', { method: 'POST', form: { MaxPlayers: 10, MaxSpectators: 4, GamePassword: '', Apply: 'Apply' } })
check('reset password', rules2.status === 200)

if (process.argv.includes('--switch')) {
  const map = process.argv[process.argv.indexOf('--switch') + 1] || 'CTF-Face'
  const r = await req('/current_game', { method: 'POST', form: { MapSelect: map + '.unr', SwitchMap: 'Switch' } })
  check(`c00lbot POST /current_game -> ${map}`, r.status === 200)
}

console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED')
process.exit(failed ? 1 : 0)
