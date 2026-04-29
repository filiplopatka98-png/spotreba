/* =============================================================
   Spotreba — service worker (PWA full offline)
   ============================================================= */

const CACHE_NAME = 'spotreba-v1';

// Pre-cache iba app shell. Všetko ostatné (CDN libs, fonts, Tesseract
// data) sa cachuje lazy pri prvom fetchi.
const SHELL = ['./', './index.html'];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((c) => c.addAll(SHELL))
  );
  // POZN: schválne NEvoláme self.skipWaiting() — nový SW čaká,
  // kým user neklikne "Aktualizovať" v banneri (stránka pošle 'skipWaiting').
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', (e) => {
  if (e.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (e) => {
  // Pass-through pre non-GET (POST/PUT/DELETE nikdy necacheovať)
  if (e.request.method !== 'GET') return;

  const url = new URL(e.request.url);

  // Pass-through pre Supabase API — auth a sync musia byť vždy live
  if (url.hostname.endsWith('.supabase.co')) return;

  // App shell (vlastná doména, root alebo index.html) → network-first
  // (aby user dostal najnovšiu verziu pri každom load-e online)
  const isAppShell = url.origin === self.location.origin
    && (url.pathname.endsWith('/') || url.pathname.endsWith('/index.html'));

  if (isAppShell) {
    e.respondWith(networkFirst(e.request));
  } else {
    // Všetko ostatné (CDN libs, fonts, Tesseract assety) → cache-first
    e.respondWith(cacheFirst(e.request));
  }
});

async function networkFirst(req) {
  try {
    const res = await fetch(req);
    if (res.ok) {
      const copy = res.clone();
      caches.open(CACHE_NAME).then((c) => c.put(req, copy));
    }
    return res;
  } catch (err) {
    const cached = await caches.match(req);
    if (cached) return cached;
    throw err;
  }
}

async function cacheFirst(req) {
  const cached = await caches.match(req);
  if (cached) return cached;
  const res = await fetch(req);
  // Opaque responses (no-cors) — quota issues, neukladáme
  if (res.ok && res.type !== 'opaque') {
    const copy = res.clone();
    caches.open(CACHE_NAME).then((c) => c.put(req, copy));
  }
  return res;
}
