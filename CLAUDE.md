# CLAUDE.md — pre AI session na tomto projekte

## Čo je Spotreba

Single-file HTML aplikácia na sledovanie spotreby energií (elektrina/FV/voda/plyn). Lokálne uložené v IndexedDB (Dexie), synchronizované do Supabase (Postgres + RLS). Detaily ficiek pozri [README.md](README.md).

## Tech a runtime

- **Single-file HTML** — všetko (HTML, CSS, vanilla JS) je v `index.html` (~5300 riadkov). Žiadny build step, žiadny npm.
- Externé knižnice cez CDN (s SRI integrity hashmi):
  - Eager v `<head>`: Dexie 3.2.4, Supabase JS 2.45.4 (potrebné pri startApp pre auth + lokálnu DB)
  - Lazy-loaded cez `loadScriptOnce(url, integrity)` helper: Chart.js 4.4.0 (preload v startApp), Tesseract.js 5.0.4 (na prvý OCR), SheetJS 0.18.5 (na prvý Excel import/export)
- PWA: `service-worker.js` (network-first pre app shell, cache-first pre CDN libs), `manifest.json`, kompletné ikony (SVG zdroj + PNG 16/32/180/192/512), iOS apple-touch-icon.
- Cieľové prostredia: GitHub Pages (live), WebSupport (plánované), `python3 -m http.server 8000` (lokálne).

## Ako spustiť lokálne

```bash
python3 -m http.server 8000
# otvor http://localhost:8000
```

HTTP server je nutný (nie `file://`) kvôli CORS pri Supabase auth cookies.

## Kde žijú dáta

| | Kde | Čo |
|---|---|---|
| **Lokálne** | IndexedDB `spotrebaDB_v2` (per-origin!) | households, meters, devices, readings, settings, sync mapy |
| **Cloud** | Supabase Postgres | households, meters, devices, readings, user_settings, household_shares (Phase C) |
| **Auth** | Supabase Auth | users (managed by Supabase) |

> ⚠️ **IndexedDB je per-origin** — `localhost`, `github.io`, `file://` majú každý SVOJU lokálnu DB. Dáta z localhost nie sú na github.io a naopak. Sync ich zlúči len cez Supabase (zdieľaný backend).

## Sync model (Phase B + Phase C)

- **Push** (lokálne → cloud): debounced 800ms po každej zmene, cez `schedulePush()` → `pushAll()`. `is_shared` domy sa do push-u filtrujú preč (read-only).
- **Pull** (cloud → lokálne): pri prihlásení a manuálne cez "Vykonať plnú synchronizáciu" v Settings.
- **Mapovanie**: lokálne PK ↔ cloud ID je v `Sync.maps`, perzistované v `db.settings` pod kľúčom `syncMaps`.
- **Konflikty**: nie sú riešené — last-write-wins. Pri jednom userovi cez viacero zariadení v praxi neproblém.
- **User-switch wipe**: `startApp` na úvode porovná `Sync.user.id` proti uloženému `lastUserId` v `db.settings`. Ak sa user zmenil → vyčistí lokálnu Dexie pred sync-om. Bez tohto by sa cudzie dáta pushli pod nového user_id (cross-account leak — fix z 2026-04-29).

## Phase C — read-only zdieľanie domov

- Dom má lokálne flag `is_shared` (true = niekto mi ho zdieľa, je read-only).
- Read-only enforcement: `body.ro-shared` CSS class skryje tlačidlá + €. JS guard `ensureWritable()` v mutation handleroch.
- Share lifecycle: owner generuje single-use kód v `household_shares` (`code` set, `recipient_id NULL`); recipient claim cez RPC `claim_share_code(p_code)` (atomic, SECURITY DEFINER); revoke = DELETE z oboch strán.
- Owner email pre banner sa resolvuje cez RPC `get_user_emails(p_ids[])` (SECURITY DEFINER, server-side filtruje len users s ktorými existuje share vzťah).

## Excel import/export

- **SheetJS** (`xlsx@0.18.5`) lazy-loaded z CDN pri prvom kliku na Export/Import (cache-uje SW).
- Header dynamický podľa `enabled_meters` aktívneho domu, fixed order: `plyn → voda → elektrina → fv-predaj`. Každé meradlo = pár stĺpcov (stav, spotreba).
- Slovak date utils: `SK_MONTHS_GEN` (genitive: januára), `SK_MONTHS_NOM` (nominative: január), `parseDateMaybe()` (4 stratégie: Date object, Excel serial, Slovak string, ISO), `fmtDateSk()`.
- **Replacement detection** pri importe: ak `current_stav < previous_stav AND spotreba > 0`, vytvorí nový `device` záznam s odhadnutým initial=0/final=prev_stav. Užívateľ ich má fine-tune-núť v Settings → Výmena merača.
- **Conflict detection**: pre každý import-row skontroluje `db.readings.where('[meterPk+date]')`; preview zobrazí počet + zoznam konfliktov, jedna voľba pre všetky (Prepísať / Ponechať / Zrušiť).
- Read-only domy blokujú import cez `ensureWritable()`; export funguje aj na zdieľaných.
- Export filename: `spotreba-<dom>-YYYYMMDD.xlsx`. Datum write-uje ako Slovak string (nie Date object) — bit-perfect roundtrip.

## Supabase gotchas (read this!)

1. **GRANTs**: tabuľky vytvorené cez SQL Editor (`CREATE TABLE`) **nedostávajú auto-grant** pre `authenticated` rolu. Bez `GRANT SELECT, INSERT, UPDATE, DELETE ON tabulka TO authenticated;` všetky requesty 403-ujú. Aj sequences treba: `GRANT USAGE, SELECT ON SEQUENCE tabulka_id_seq TO authenticated;`. Naše SQL skripty to obsahujú — pri pridávaní novej tabuľky NEZABUDNI.
2. **RLS policy referencujúca inú tabuľku** (cez `EXISTS` subquery) vyžaduje GRANT aj na referencovanú tabuľku — inak query zlyhá s 403 už pri vyhodnocovaní policy.
3. Po zmene grantov: `NOTIFY pgrst, 'reload schema';` aby PostgREST okamžite obnovil cache (inak ~10s lag).
4. Anon key (`SUPABASE_ANON_KEY` v `index.html`) je verejný — bezpečnosť rieši RLS.

## Bezpečnosť

- **CSP** v `<meta http-equiv>` aj `.htaccess` Header. Allowlists: `cdn.jsdelivr.net`, `unpkg.com` (Tesseract core), `tessdata.projectnaptha.com` (Tesseract jazykové dáta), `*.supabase.co`, Google Fonts.
- **SRI** (`integrity="sha384-..."`) na všetkých 5 CDN scriptoch (Dexie, Supabase, Chart.js, Tesseract, SheetJS). Pri update verzie knižnice nezabudni prepočítať hash: `curl -sL <url> | openssl dgst -sha384 -binary | openssl base64 -A`.
- **HSTS + Permissions-Policy** v `.htaccess` (WebSupport). GitHub Pages ich nepodporuje, ale meta CSP + robots.txt + noindex meta to čiastočne nahradzujú.
- **noindex** — `<meta name="robots">`, `robots.txt`, `X-Robots-Tag` HTTP header. Súkromná appka.
- **XSS escape**: `escHtml(s)` (globálna funkcia) sa POVINNE volá pri každej user-content interpolácii do `innerHTML` (názov domu, poznámka odpočtu, owner email, atď.). Pri pridávaní novej render funkcie nezabudni!

## Bežné úlohy a kde to žije v `index.html`

| Téma | Riadky (orientačne) |
|---|---|
| Supabase client init | ~1640 |
| Auth UI + handlers | ~2130, ~2260 |
| `pullFromCloud` | ~1860 |
| `pushAll` | ~2070 |
| Dexie schema | ~2210 |
| State (`activeHouseholdId`, `household`, `meters`) | ~2410 |
| Household switcher render | ~4470 |
| Settings tab HTML | ~1390 |
| Phase C JS (sharing, RO mode) | ~4630–4870 |
| Excel import/export modul | ~5070–5400 |
| Lazy-loader + lib loaders (`loadChartJs`, `loadTesseract`, `loadXlsx`) | ~5040 |
| PWA SW registration + update prompt | ~5410 |
| Event handlery (button bindings) | ~4870+ |
| `startApp` | ~5060 |

Pre presné lokácie použi grep — riadky sa posúvajú s editmi.

## Štýl a workflow

- **Vanilla JS** — žiadny TypeScript, žiadne frameworky.
- **Žiadny build step** — všetko musí fungovať po `cp index.html` na server.
- **Slovak naming/UI** — komentáre a UI texty sú v slovenčine (technické termíny ako "households", "sync" zostávajú anglicky kde je to čitateľnejšie).
- **Sync indikátor v hlavičke** je zlatá pravda stavu — zelená/oranžová/červená/sivá. Pri debugovaní vždy najprv pozri ten + DevTools → Application → IndexedDB.

## Čo NECOMMITUJ

- `docs/superpowers/` — design specy, brainstorming, plány. Ostávajú lokálne (gitignored). Vidieť [`memory/feedback_no_planning_docs_in_git.md`](../.claude/projects/-Users-filiplopatka-Downloads-repo/memory/feedback_no_planning_docs_in_git.md) pre detail.
- `.env*`, credentials.

## Deployment

- **GitHub Pages**: `git push` na `main` → auto-deploy na https://filiplopatka98-png.github.io/spotreba/ za ~1-2 min.
- **WebSupport** (plánované): subdoména + manuálny FTP upload `index.html` + `.htaccess`. Potenciálne neskôr GitHub Action.

## Pre debugovanie sync problémov

1. Sync indikátor v hlavičke — zelená/oranžová/červená/sivá + hover text.
2. DevTools → Console → vidieť `Sync.user`, `Sync.status`, `Sync.maps`.
3. DevTools → Network → filter `supabase.co` — status codes.
4. Supabase Dashboard → SQL Editor → `SELECT count(*) FROM households;` (ako admin, vidíš všetko).
5. RLS test: `SELECT has_table_privilege('authenticated', 'public.tabulka', 'SELECT');` — ak `false`, chýba GRANT.
