# CLAUDE.md — pre AI session na tomto projekte

## Čo je Spotreba

Single-file HTML aplikácia na sledovanie spotreby energií (elektrina/FV/voda/plyn). Lokálne uložené v IndexedDB (Dexie), synchronizované do Supabase (Postgres + RLS). Detaily ficiek pozri [README.md](README.md).

## Tech a runtime

- **Single-file HTML** — všetko (HTML, CSS, vanilla JS) je v `index.html` (~4700 riadkov). Žiadny build step, žiadny npm.
- Externé knižnice cez CDN: Dexie, Chart.js, Tesseract.js, Supabase JS SDK.
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

- **Push** (lokálne → cloud): debounced 800ms po každej zmene, cez `schedulePush()` → `pushAll()`.
- **Pull** (cloud → lokálne): pri prihlásení a manuálne cez "Vykonať plnú synchronizáciu" v Settings.
- **Mapovanie**: lokálne PK ↔ cloud ID je v `Sync.maps`, perzistované v `db.settings` pod kľúčom `syncMaps`.
- **Konflikty**: nie sú riešené — last-write-wins. Pri jednom userovi cez viacero zariadení v praxi neproblém.

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

## Bežné úlohy a kde to žije v `index.html`

| Téma | Riadky (orientačne) |
|---|---|
| Supabase client init | ~1530 |
| Auth UI + handlers | ~2020, ~2150 |
| `pullFromCloud` | ~1760 |
| `pushAll` | ~1970 |
| Dexie schema | ~2110 |
| State (`activeHouseholdId`, `household`, `meters`) | ~2310 |
| Household switcher render | ~3950 |
| Settings tab HTML | ~1290 |
| Phase C JS (sharing, RO mode) | ~4310–4520 |
| Excel import/export modul | ~4970–5300 |
| Event handlery (button bindings) | ~4540+ |
| `startApp` | ~4670 |

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
