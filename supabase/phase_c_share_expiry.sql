-- =====================================================
-- Phase C — share code expiry (7 dní) + search_path hardening
-- =====================================================
-- Spusti v Supabase → SQL Editor (ako owner). Idempotentné (IF NOT EXISTS /
-- CREATE OR REPLACE). Po spustení sa schéma reloadne cez NOTIFY na konci.
--
-- Čo robí:
--  1) pridá stĺpec household_shares.expires_at (nevyclaimované kódy expirujú),
--  2) claim_share_code odmietne expirovaný kód,
--  3) obe SECURITY DEFINER funkcie dostanú pinned search_path = '' a
--     schema-qualified názvy (fix "Function Search Path Mutable" hardening).

-- 1) Expiry stĺpec ------------------------------------------------------------
ALTER TABLE household_shares
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- 2) claim_share_code — odmietni expirovaný kód + search_path hardening --------
CREATE OR REPLACE FUNCTION claim_share_code(p_code TEXT)
RETURNS BIGINT
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql
AS $$
DECLARE
  v_share_id BIGINT;
  v_owner UUID;
  v_expires TIMESTAMPTZ;
BEGIN
  SELECT id, owner_id, expires_at INTO v_share_id, v_owner, v_expires
  FROM public.household_shares
  WHERE code = p_code AND recipient_id IS NULL
  FOR UPDATE;

  IF v_share_id IS NULL THEN
    RAISE EXCEPTION 'invalid_or_claimed_code'
      USING HINT = 'Kód neexistuje alebo už bol použitý.';
  END IF;

  IF v_expires IS NOT NULL AND v_expires < now() THEN
    RAISE EXCEPTION 'expired_code'
      USING HINT = 'Kód vypršal.';
  END IF;

  IF v_owner = auth.uid() THEN
    RAISE EXCEPTION 'self_claim_forbidden'
      USING HINT = 'Nemôžeš claim-núť svoj vlastný kód.';
  END IF;

  UPDATE public.household_shares
    SET recipient_id = auth.uid(),
        claimed_at = now(),
        code = NULL
  WHERE id = v_share_id;

  RETURN v_share_id;
END $$;

REVOKE ALL ON FUNCTION claim_share_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_share_code(TEXT) TO authenticated;

-- 3) get_user_emails — search_path hardening (logika nezmenená) ----------------
CREATE OR REPLACE FUNCTION get_user_emails(p_ids UUID[])
RETURNS TABLE(id UUID, email TEXT)
SECURITY DEFINER
SET search_path = ''
LANGUAGE sql
AS $$
  SELECT u.id, u.email::TEXT
  FROM auth.users u
  WHERE u.id = ANY(p_ids)
    AND (
      u.id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.household_shares s
        WHERE s.owner_id = auth.uid() AND s.recipient_id = u.id
      )
      OR EXISTS (
        SELECT 1 FROM public.household_shares s
        WHERE s.recipient_id = auth.uid() AND s.owner_id = u.id
      )
    );
$$;

REVOKE ALL ON FUNCTION get_user_emails(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_emails(UUID[]) TO authenticated;

-- Reload PostgREST schema cache (inak ~10s lag na nové stĺpce/fn signatúry)
NOTIFY pgrst, 'reload schema';
