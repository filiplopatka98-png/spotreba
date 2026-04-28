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

Schéma tabuliek je v `supabase/schema.sql`. Spusti v SQL Editore v Supabase projekte.

V `index.html` zmeň konštanty:

```js
const SUPABASE_URL = 'https://...';
const SUPABASE_ANON_KEY = '...';
```

## Bezpečnosť

- Anon key je verejný (štandard Supabase) — bezpečnosť zabezpečuje Row Level Security
- Po vytvorení všetkých účtov **vypni nové registrácie** v Supabase: Authentication → Providers → Email → Disable new user signups
- HTTPS je povinné v produkcii (Supabase auth cookies)

## Štruktúra repo

```
.
├── index.html           # Hlavná appka (single-file)
├── .htaccess            # Apache config pre WebSupport (HTTPS, gzip, cache)
├── supabase/
│   └── schema.sql       # SQL na inicializáciu DB
├── README.md
└── .gitignore
```

## Licencia

Súkromný projekt. Príď za mnou ak ťa zaujíma.
