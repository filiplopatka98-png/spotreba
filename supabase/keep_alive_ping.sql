-- =====================================================
-- Keep-alive ping — snaha držať free-tier Supabase "bdelý"
-- =====================================================
-- Spusti v Supabase → SQL Editor (ako owner). Idempotentné.
-- Po spustení sa schéma reloadne cez NOTIFY na konci.
--
-- HISTÓRIA A REALITA (čítaj, než tomu začneš veriť):
--  v1 pingovala REST /households s anon kľúčom → 42501 "permission denied"
--      (HTTP 401). Zamietnutý request sa ako aktivita nepočíta.
--  v2 pridala ping() = SELECT 'pong' → HTTP 200, ale projekt sa 2026-08-17
--      AJ TAK PAUZOL. 15/15 behov success, posledný ping 7,5 h pred warning
--      mailom. Dôvod: Supabase nepauzuje pri "no activity", ale pri
--      "low activity in a 7-day period" — 15 mikro-requestov za mesiac je
--      pod (nikde nedokumentovaným) prahom.
--  v3 (toto) = best-effort pokus, NIE garancia:
--      - workflow beží denne namiesto raz za 3 dni
--      - ping() robí reálny UPDATE (WAL zápis, dead tuple, autovacuum),
--        nie len vyhodnotenie konštanty bez dotyku na dáta
--  Ak sa projekt pauzne znova, ping cestou už nejdeme — vtedy je na stole
--  len Pro plán alebo vlastný backend.

-- Heartbeat tabuľka — jeden riadok, ktorý sa prepisuje ------------------------
CREATE TABLE IF NOT EXISTS public.keep_alive (
  id         smallint    PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  last_ping  timestamptz NOT NULL DEFAULT now(),
  ping_count bigint      NOT NULL DEFAULT 0
);

INSERT INTO public.keep_alive (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- RLS zapnutá a ZÁMERNE bez policies → cez REST sa k tabuľke nikto nedostane.
-- Zapisuje sa výhradne cez ping() nižšie, ktorá beží ako owner (SECURITY
-- DEFINER) a RLS ju teda neobmedzuje. Tabuľke naschvál nedávame žiadny GRANT.
ALTER TABLE public.keep_alive ENABLE ROW LEVEL SECURITY;

-- ping() — zapíše heartbeat a vráti počítadlo, volateľná anonom -------------
CREATE OR REPLACE FUNCTION public.ping()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  n bigint;
BEGIN
  UPDATE public.keep_alive
     SET last_ping = now(),
         ping_count = ping_count + 1
   WHERE id = 1
  RETURNING ping_count INTO n;

  RETURN 'pong ' || n::text;
END;
$$;

-- Grant execute pre anon (a authenticated nech to má tiež) --------------------
GRANT EXECUTE ON FUNCTION public.ping() TO anon, authenticated;

-- Reload PostgREST schema cache, nech je RPC hneď dostupné --------------------
NOTIFY pgrst, 'reload schema';
