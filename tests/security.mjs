// Negative tests against the local SWA2 test server (phase 1 fixes).
// Usage: node tests/security.mjs   (reads testserver/credentials.env)
// None of these requests may cause a map change; the server log is checked by hand.
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

async function req(path, { authz = admin, form } = {}) {
  const res = await fetch(base + path, {
    method: form ? 'POST' : 'GET',
    headers: { Authorization: authz, ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}) },
    body: form ? new URLSearchParams(form).toString() : undefined,
  })
  return { status: res.status, text: await res.text() }
}

const XSS = '"><script>alert(1)</script>'

// 1. URL injection through MapSelect (old code passed it straight into ServerTravel)
let r = await req('/current_game', { form: { MapSelect: 'CTF-Anarchy-LE113.unr?mutator=Botpack.LowGrav', SwitchMap: 'Switch' } })
check('MapSelect with ?mutator= is rejected', /Unknown map/.test(r.text))
r = await req('/current_game', { form: { MapSelect: 'CTF-DoesNotExist.unr', SwitchMap: 'Switch' } })
check('unknown map is rejected', /Unknown map/.test(r.text))
r = await req('/current_game', { form: { MapSelect: XSS, SwitchMap: 'Switch' } })
check('MapSelect is not reflected unescaped', !r.text.includes('<script>alert(1)'))

// 2. Game type switch needs the privilege that shows the controls (mod = level 1)
r = await req('/current_game', { authz: mod, form: { GameTypeSelect: 'Botpack.DeathMatchPlus', MapSelect: 'CTF-Anarchy-LE113.unr', SwitchGameTypeAndMap: 'Switch' } })
check('level 1 cannot POST SwitchGameTypeAndMap', /sufficient privileges|Tournament/.test(r.text) && !/Please Wait/.test(r.text))
r = await req('/current_game', { authz: mod, form: { GameTypeSelect: 'Botpack.DeathMatchPlus', SwitchGameType: 'Switch' } })
check('level 1 cannot POST SwitchGameType', /sufficient privileges|Tournament/.test(r.text) && !/Please Wait/.test(r.text))
if (env.SWA_SMOD_USER) {
  // Level 3 (ServerModerator) may log in during tournaments but not switch game type.
  const smod = auth(env.SWA_SMOD_USER, env.SWA_SMOD_PASS)
  r = await req('/current_game', { authz: smod, form: { GameTypeSelect: 'Botpack.DeathMatchPlus', MapSelect: 'CTF-Anarchy-LE113.unr', SwitchGameTypeAndMap: 'Switch' } })
  check('level 3 cannot POST SwitchGameTypeAndMap', /sufficient privileges/.test(r.text) && !/Please Wait/.test(r.text))
}
r = await req('/current_game', { form: { GameTypeSelect: 'Botpack.DoesNotExist', SwitchGameType: 'Switch' } })
check('unknown game type is rejected', /Unknown game type/.test(r.text))
r = await req('/current_game', { form: { GameTypeSelect: XSS, SwitchGameType: 'Switch' } })
check('GameTypeSelect is not reflected unescaped', !r.text.includes('<script>alert(1)'))

// 3. Mutators page
const before = await req('/current_mutators')
const other = t => (t.match(/name="OtherMutators"[^>]*value="([^"]*)"/) || [])[1]
// the ordered "next map" list: <select id="used"> with <option value="Class">
const included = t => [...((t.split('id="used"')[1] || '').split('</select>')[0]).matchAll(/<option value="([^"]*)"/g)].map(m => m[1])
const otherBefore = other(before.text)

r = await req('/current_mutators', { form: { OtherMutators: 'Botpack.LowGrav?game=Botpack.DeathMatchPlus', UpdateOther: 'Set' } })
check('Other Mutators with ? is ignored', !included(r.text).some(v => v.includes('?')) && !(other(r.text) || '').includes('?'))
r = await req('/current_mutators', { form: { OtherMutators: 'SWATestMuts.NoIntMut,Nope.NotAMutator', UpdateOther: 'Set' } })
check('unknown class in Other Mutators is dropped', other(r.text) === 'SWATestMuts.NoIntMut', other(r.text))
r = await req('/current_mutators', { form: { OtherMutators: 'SWATestMuts.NoIntMut', UpdateOther: 'Set' } })
check('a single Other Mutator is kept (old bug B7)', other(r.text) === 'SWATestMuts.NoIntMut')

r = await req('/current_mutators', { form: { ExcludeMutatorsSelect: 'SWATestMuts.TestMut050', AddMutator: ' > ' } })
check('add mutator #50 appends it', included(r.text).at(-1) === 'SWATestMuts.TestMut050', included(r.text).join(','))
r = await req('/current_mutators', { form: { IncludeMutatorsSelect: 'SWATestMuts.TestMut050', DelMutator: ' < ' } })
check('remove it again', !included(r.text).includes('SWATestMuts.TestMut050'))
check('Other Mutators unchanged after add/remove', other(r.text) === otherBefore, `${other(r.text)} vs ${otherBefore}`)
check('mutator page escapes values', !r.text.includes('<script>alert'))

// 4. Authentication
if (env.SWA_LONG_USER) {
  r = await req('/current_rules', { authz: auth(env.SWA_LONG_USER, env.SWA_LONG_PASS) })
  check('40 character password works (old bug B6)', r.status === 200)
}
check('account with empty password: empty login refused', (await req('/', { authz: auth('nopass', '') })).status === 401)
check('account with empty password: any password refused', (await req('/', { authz: auth('nopass', 'x') })).status === 401)

// 5. CSRF: browsers send Sec-Fetch-Site / Origin; scripts (c00lbot) send neither
async function raw(path, headers, body) {
  const res = await fetch(base + path, { method: 'POST', headers: { Authorization: admin, 'Content-Type': 'application/x-www-form-urlencoded', ...headers }, body })
  return { status: res.status, text: await res.text() }
}
const rulesBody = 'MaxPlayers=10&MaxSpectators=4&GamePassword=&Apply=Apply'
check('cross-site POST (Sec-Fetch-Site) refused', (await raw('/current_rules', { 'Sec-Fetch-Site': 'cross-site' }, rulesBody)).status === 403)
check('cross-site POST (Origin) refused', (await raw('/current_rules', { Origin: 'http://evil.example' }, rulesBody)).status === 403)
check('same-origin POST allowed', (await raw('/current_rules', { 'Sec-Fetch-Site': 'same-origin', Origin: base }, rulesBody)).status === 200)
check('POST without browser headers allowed (c00lbot)', (await raw('/current_rules', {}, rulesBody)).status === 200)

// 6. Game password validation
r = await req('/current_rules', { form: { MaxPlayers: 10, MaxSpectators: 4, GamePassword: 'a b', Apply: 'Apply' } })
check('game password with space -> 400', r.status === 400)
r = await req('/current_rules', { form: { MaxPlayers: 10, MaxSpectators: 4, GamePassword: 'ab1;cd2;ef3', Apply: 'Apply' } })
check('c00lbot style password accepted', r.status === 200 && r.text.includes('value="ab1;cd2;ef3"'))
r = await req('/current_rules', { form: { MaxPlayers: '10 bTournament', MaxSpectators: 4, GamePassword: '', Apply: 'Apply' } })
check('MaxPlayers is clamped to a number', r.status === 200 && /value="10"/.test(r.text))

// 7. Usernames with ':' would create a passwordless account in the colon separated list
r = await req('/superadmin_adminwebadmin1', { form: { Username: 'bob::5', Password: 'x1', ConfPassword: 'x1', Priv: '5', Add2: 'Add' } })
check('username with : is refused', /Invalid username/.test(r.text))

// 8. Brute force lockout (last: locks 127.0.0.1 for 60 s)
if (process.argv.includes('--lockout')) {
  for (let i = 0; i < 5; i++) await req('/', { authz: auth('admin', 'wrong' + i) })
  check('after 5 failures even the right password is refused', (await req('/')).status === 401)
  console.log('      waiting 62 s for the lockout to expire ...')
  await new Promise(res => setTimeout(res, 62000))
  check('login works again after the lockout', (await req('/')).status === 200)
}

console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED')
process.exit(failed ? 1 : 0)
