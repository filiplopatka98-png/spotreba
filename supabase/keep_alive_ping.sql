-- =====================================================
-- Keep-alive ping RPC — drží free-tier Supabase "bdelý"
-- =====================================================
-- Spusti v Supabase → SQL Editor (ako owner). Idempotentné (CREATE OR REPLACE).
-- Po spustení sa schéma reloadne cez NOTIFY na konci.
--
-- Prečo:
--  GitHub Action (.github/workflows/keep-supabase-alive.yml) pinguje projekt,
--  aby sa nepauzoval po ~7 dňoch nečinnosti. Pôvodne pingoval REST /households
--  s anon kľúčom, lenže anon nemá GRANT na households → vracalo to 42501
--  "permission denied" (HTTP 401). Taký zamietnutý request Supabase nepočíta
--  ako aktivitu, takže projekt aj tak dostal pause warning.
--
--  Táto funkcia dá anonovi jeden legitímny, úspešný (200) DB call, ktorý sa
--  reálne vykoná v Postgrese → jednoznačne sa počíta ako aktivita.
--  Neexponuje žiadne dáta (vracia len konštantu 'pong').

-- ping() — vracia 'pong', volateľná anonom -----------------------------------
CREATE OR REPLACE FUNCTION public.ping()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT 'pong'::text;
$$;

-- Grant execute pre anon (a authenticated nech to má tiež) --------------------
GRANT EXECUTE ON FUNCTION public.ping() TO anon, authenticated;

-- Reload PostgREST schema cache, nech je RPC hneď dostupné --------------------
NOTIFY pgrst, 'reload schema';
