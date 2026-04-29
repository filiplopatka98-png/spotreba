-- =====================================================
-- SPOTREBA — Phase C: read-only household sharing
-- =====================================================
-- Spusti v Supabase SQL Editore JEDEN RAZ po deploynutí pôvodnej schema.sql.
-- Idempotentný: dá sa pustiť opakovane bez chyby.

-- =====================================================
-- 1) Tabuľka household_shares
-- =====================================================

CREATE TABLE IF NOT EXISTS household_shares (
  id BIGSERIAL PRIMARY KEY,
  household_id BIGINT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT,
  recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shares_household ON household_shares(household_id);
CREATE INDEX IF NOT EXISTS idx_shares_owner ON household_shares(owner_id);
CREATE INDEX IF NOT EXISTS idx_shares_recipient
  ON household_shares(recipient_id) WHERE recipient_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_shares_code
  ON household_shares(code) WHERE code IS NOT NULL;

DROP TRIGGER IF EXISTS household_shares_updated ON household_shares;
CREATE TRIGGER household_shares_updated
  BEFORE UPDATE ON household_shares
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- 2) RLS na household_shares
-- =====================================================

ALTER TABLE household_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "share parties can read" ON household_shares;
CREATE POLICY "share parties can read"
  ON household_shares FOR SELECT
  USING (auth.uid() = owner_id OR auth.uid() = recipient_id);

DROP POLICY IF EXISTS "owner can create share" ON household_shares;
CREATE POLICY "owner can create share"
  ON household_shares FOR INSERT
  WITH CHECK (
    auth.uid() = owner_id
    AND EXISTS (
      SELECT 1 FROM households
      WHERE id = household_id AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "either party can delete" ON household_shares;
CREATE POLICY "either party can delete"
  ON household_shares FOR DELETE
  USING (auth.uid() = owner_id OR auth.uid() = recipient_id);

-- Žiadna UPDATE policy — claim ide cez SECURITY DEFINER funkciu nižšie.

-- =====================================================
-- 3) Split SELECT/mutate policies na existujúcich tabuľkách
--    (pôvodné FOR ALL policies sa nahrádzajú)
-- =====================================================

-- HOUSEHOLDS
DROP POLICY IF EXISTS "users see own households" ON households;
DROP POLICY IF EXISTS "households select" ON households;
DROP POLICY IF EXISTS "households insert" ON households;
DROP POLICY IF EXISTS "households update" ON households;
DROP POLICY IF EXISTS "households delete" ON households;

CREATE POLICY "households select" ON households FOR SELECT USING (
  auth.uid() = user_id
  OR EXISTS (
    SELECT 1 FROM household_shares s
    WHERE s.household_id = households.id
      AND s.recipient_id = auth.uid()
      AND s.claimed_at IS NOT NULL
  )
);
CREATE POLICY "households insert" ON households FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "households update" ON households FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "households delete" ON households FOR DELETE
  USING (auth.uid() = user_id);

-- METERS
DROP POLICY IF EXISTS "users see own meters" ON meters;
DROP POLICY IF EXISTS "meters select" ON meters;
DROP POLICY IF EXISTS "meters insert" ON meters;
DROP POLICY IF EXISTS "meters update" ON meters;
DROP POLICY IF EXISTS "meters delete" ON meters;

CREATE POLICY "meters select" ON meters FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM households h
    WHERE h.id = meters.household_id AND (
      h.user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM household_shares s
        WHERE s.household_id = h.id
          AND s.recipient_id = auth.uid()
          AND s.claimed_at IS NOT NULL
      )
    )
  )
);
CREATE POLICY "meters insert" ON meters FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM households WHERE id = meters.household_id AND user_id = auth.uid())
);
CREATE POLICY "meters update" ON meters FOR UPDATE
  USING (EXISTS (SELECT 1 FROM households WHERE id = meters.household_id AND user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM households WHERE id = meters.household_id AND user_id = auth.uid()));
CREATE POLICY "meters delete" ON meters FOR DELETE USING (
  EXISTS (SELECT 1 FROM households WHERE id = meters.household_id AND user_id = auth.uid())
);

-- DEVICES
DROP POLICY IF EXISTS "users see own devices" ON devices;
DROP POLICY IF EXISTS "devices select" ON devices;
DROP POLICY IF EXISTS "devices insert" ON devices;
DROP POLICY IF EXISTS "devices update" ON devices;
DROP POLICY IF EXISTS "devices delete" ON devices;

CREATE POLICY "devices select" ON devices FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM households h
    WHERE h.id = devices.household_id AND (
      h.user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM household_shares s
        WHERE s.household_id = h.id
          AND s.recipient_id = auth.uid()
          AND s.claimed_at IS NOT NULL
      )
    )
  )
);
CREATE POLICY "devices insert" ON devices FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM households WHERE id = devices.household_id AND user_id = auth.uid())
);
CREATE POLICY "devices update" ON devices FOR UPDATE
  USING (EXISTS (SELECT 1 FROM households WHERE id = devices.household_id AND user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM households WHERE id = devices.household_id AND user_id = auth.uid()));
CREATE POLICY "devices delete" ON devices FOR DELETE USING (
  EXISTS (SELECT 1 FROM households WHERE id = devices.household_id AND user_id = auth.uid())
);

-- READINGS
DROP POLICY IF EXISTS "users see own readings" ON readings;
DROP POLICY IF EXISTS "readings select" ON readings;
DROP POLICY IF EXISTS "readings insert" ON readings;
DROP POLICY IF EXISTS "readings update" ON readings;
DROP POLICY IF EXISTS "readings delete" ON readings;

CREATE POLICY "readings select" ON readings FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM households h
    WHERE h.id = readings.household_id AND (
      h.user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM household_shares s
        WHERE s.household_id = h.id
          AND s.recipient_id = auth.uid()
          AND s.claimed_at IS NOT NULL
      )
    )
  )
);
CREATE POLICY "readings insert" ON readings FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM households WHERE id = readings.household_id AND user_id = auth.uid())
);
CREATE POLICY "readings update" ON readings FOR UPDATE
  USING (EXISTS (SELECT 1 FROM households WHERE id = readings.household_id AND user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM households WHERE id = readings.household_id AND user_id = auth.uid()));
CREATE POLICY "readings delete" ON readings FOR DELETE USING (
  EXISTS (SELECT 1 FROM households WHERE id = readings.household_id AND user_id = auth.uid())
);

-- =====================================================
-- 4) RPC: claim_share_code (atomický single-use claim)
-- =====================================================

CREATE OR REPLACE FUNCTION claim_share_code(p_code TEXT)
RETURNS BIGINT
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
  v_share_id BIGINT;
  v_owner UUID;
BEGIN
  SELECT id, owner_id INTO v_share_id, v_owner
  FROM household_shares
  WHERE code = p_code AND recipient_id IS NULL
  FOR UPDATE;

  IF v_share_id IS NULL THEN
    RAISE EXCEPTION 'invalid_or_claimed_code'
      USING HINT = 'Kód neexistuje alebo už bol použitý.';
  END IF;

  IF v_owner = auth.uid() THEN
    RAISE EXCEPTION 'self_claim_forbidden'
      USING HINT = 'Nemôžeš claim-núť svoj vlastný kód.';
  END IF;

  UPDATE household_shares
    SET recipient_id = auth.uid(),
        claimed_at = NOW(),
        code = NULL
  WHERE id = v_share_id;

  RETURN v_share_id;
END $$;

REVOKE ALL ON FUNCTION claim_share_code(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_share_code(TEXT) TO authenticated;

-- =====================================================
-- 5) RPC: get_user_emails (resolve owner/recipient labels)
--    Vráti email iba pre user-ov s ktorými má caller share vzťah.
-- =====================================================

CREATE OR REPLACE FUNCTION get_user_emails(p_ids UUID[])
RETURNS TABLE(id UUID, email TEXT)
SECURITY DEFINER
LANGUAGE sql
AS $$
  SELECT u.id, u.email::TEXT
  FROM auth.users u
  WHERE u.id = ANY(p_ids)
    AND (
      u.id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM household_shares s
        WHERE s.owner_id = auth.uid() AND s.recipient_id = u.id
      )
      OR EXISTS (
        SELECT 1 FROM household_shares s
        WHERE s.recipient_id = auth.uid() AND s.owner_id = u.id
      )
    );
$$;

REVOKE ALL ON FUNCTION get_user_emails(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_emails(UUID[]) TO authenticated;

-- =====================================================
-- 6) Table-level grants pre rolu authenticated
--    (RLS politiky stále platia nad týmto — toto je len
--     postgres-úroveňové povolenie použiť tabuľku vôbec.)
--
--    Tabuľky vytvorené cez SQL Editor (vrátane originálnej
--    schema.sql) nedostávajú auto-grant. Idempotentne to tu
--    dohnáme aj pre staré tabuľky, nielen household_shares —
--    bez tohto by sync silently 403-oval pre všetkých.
-- =====================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON households       TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON meters           TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON devices          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON readings         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_settings    TO authenticated;
GRANT SELECT, INSERT,         DELETE ON household_shares TO authenticated;

GRANT USAGE, SELECT ON SEQUENCE households_id_seq       TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE meters_id_seq           TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE devices_id_seq          TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE readings_id_seq         TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE household_shares_id_seq TO authenticated;

-- Vynúti reload PostgREST schema cache, aby grants fungovali okamžite.
NOTIFY pgrst, 'reload schema';

-- =====================================================
-- Hotovo. Po spustení by všetky CREATE/DROP/GRANT mali prejsť bez chyby.
-- =====================================================
