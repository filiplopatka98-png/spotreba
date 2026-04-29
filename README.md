# Spotreba — Tracker energií

Webová aplikácia na sledovanie spotreby elektriny, vody a plynu (s podporou fotovoltaiky a viacerých domácností). Single-file HTML app s lokálnym ukladaním (IndexedDB) a cloudovou synchronizáciou cez Supabase.

## Vlastnosti

- 📊 Dashboard s mesačnou a ročnou spotrebou
- 📷 OCR čítanie hodnôt z fotky merača (Tesseract.js)
- 📈 Grafy: mesačná spotreba, kumulatívne, year-over-year, heatmapa
- ⚠️ Detekcia anomálií (porovnanie s historickým priemerom)
- 🏠 Viacero domácností (vlastný + rodičovský dom atď.)
- 🔌 Podpora výmeny meračov so zachovaním kontinuity spotreby
- ☁️ Cloud sync cez Supabase (multi-device)
- 🔐 Email + heslo prihlasovanie
- 🤝 Read-only zdieľanie domov medzi účtami cez jednorazový kód
- 📵 PWA — funguje plne offline (service worker), inštalovateľná na mobile
- 🌗 Tmavý dizajn

## Tech stack

- Single-file HTML (žiadny build step)
- React-free vanilla JS
- [Dexie.js](https://dexie.org/) — IndexedDB wrapper
- [Chart.js](https://www.chartjs.org/) — grafy
- [Tesseract.js](https://tesseract.projectnaptha.com/) — OCR
- [Supabase](https://supabase.com/) — auth + Postgres + RLS

## Lokálny vývoj

Appka potrebuje HTTP server (kvôli CORS pri Supabase). Stačí jeden riadok:

```bash
python3 -m http.server 8000
# alebo
npx serve .
```

Otvor `http://localhost:8000`.

## Deployment

### GitHub Pages (testovací)

Po pushnutí do `main` branch:
1. Repo Settings → Pages → Source: `Deploy from a branch`
2. Branch: `main`, folder: `/ (root)`
3. URL bude `https://USERNAME.github.io/REPO-NAME/`

### WebSupport (produkcia)

1. V administrácii WebSupport vytvor subdoménu `spotreba.tvojadomena.sk`
2. V root subdomény nahraj `index.html` a `.htaccess` cez FTP/File Manager
3. Aktivuj HTTPS (Let's Encrypt zadarmo cez WebSupport)

## Konfigurácia Supabase

V SQL Editore v Supabase projekte spusti **v tomto poradí**:

1. `supabase/schema.sql` — vytvorí základné tabuľky (households, meters, devices, readings, user_settings), RLS politiky a granty.
2. `supabase/phase_c_migration.sql` — pridá tabuľku `household_shares`, RPC funkcie `claim_share_code` + `get_user_emails`, prerobí RLS na split SELECT/mutate a doplní granty (Phase C — read-only zdieľanie).

Oba skripty sú **idempotentné** — môžeš ich pustiť aj viackrát bez chyby.

V `index.html` zmeň konštanty:

```js
const SUPABASE_URL = 'https://...';
const SUPABASE_ANON_KEY = '...';
```

> ⚠️ **Pozor na GRANTs.** Tabuľky vytvorené cez SQL Editor (na rozdiel od Dashboard UI) nedostanú automaticky `GRANT ... TO authenticated`. Bez nich appka 403-uje na každý query, ale silently — vidíš len červený sync indikátor. Naše SQL skripty granty obsahujú; ak by si pridával vlastnú tabuľku, nezabudni na `GRANT SELECT, INSERT, UPDATE, DELETE ON tabulka TO authenticated;` a `GRANT USAGE, SELECT ON SEQUENCE tabulka_id_seq TO authenticated;`.

## Bezpečnosť

- Anon key je verejný (štandard Supabase) — bezpečnosť zabezpečuje Row Level Security
- Po vytvorení všetkých účtov **vypni nové registrácie** v Supabase: Authentication → Providers → Email → Disable new user signups
- HTTPS je povinné v produkcii (Supabase auth cookies)

## Zdieľanie domov (Phase C)

Vlastník domu môže udeliť **read-only** prístup inému účtu cez jednorazový share kód:

1. **Owner**: Nastavenia → Zdieľanie domov → pri svojom dome klikne `+ Pozvánka` → dostane kód typu `SHARE-7K2P-9X4M` → pošle ho recipientovi (Messenger / SMS / na papieri).
2. **Recipient**: Nastavenia → Zdieľanie domov → vloží kód do políčka „Aktivovať" → potvrdí.
3. Recipient po refreshe vidí dom v switcheri označený 🔒, s bannerom „Iba na čítanie · Vlastník: …" a so skrytými cenami v €. Mutácie (pridať odpočet, upraviť, zmazať) sú zablokované cez UI aj cez RLS.

**Revoke:** Owner aj recipient môžu kedykoľvek zrušiť zdieľanie zo svojej strany v tej istej karte.

## Štruktúra repo

```
.
├── index.html                       # Hlavná appka (single-file)
├── service-worker.js                # PWA service worker (cache app shell + libs)
├── .htaccess                        # Apache config pre WebSupport (HTTPS, gzip, cache)
├── supabase/
│   ├── schema.sql                   # Inicializácia DB (Phase B — cloud sync)
│   └── phase_c_migration.sql        # Doplnok pre Phase C (read-only zdieľanie)
├── README.md
├── CLAUDE.md                        # Inštrukcie pre AI helpera
└── .gitignore
```

## Licencia

Súkromný projekt. Príď za mnou ak ťa zaujíma.
