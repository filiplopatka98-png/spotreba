-- =====================================================
-- SPOTREBA — schéma pre cloud sync s Row Level Security
-- =====================================================
-- Spusti v Supabase SQL Editore pri inicializácii projektu.

-- HOUSEHOLDS: každý dom patrí jednému užívateľovi
CREATE TABLE households (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT,
  enabled_meters TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- METERS: meradlá v rámci domu
CREATE TABLE meters (
  id BIGSERIAL PRIMARY KEY,
  household_id BIGINT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  name TEXT NOT NULL,
  unit TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- DEVICES: fyzické merače (s podporou výmeny)
CREATE TABLE devices (
  id BIGSERIAL PRIMARY KEY,
  household_id BIGINT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  meter_id BIGINT NOT NULL REFERENCES meters(id) ON DELETE CASCADE,
  installed_date DATE NOT NULL,
  initial_value NUMERIC NOT NULL,
  replaced_date DATE,
  final_value NUMERIC,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- READINGS: jednotlivé odpočty
CREATE TABLE readings (
  id BIGSERIAL PRIMARY KEY,
  household_id BIGINT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  meter_id BIGINT NOT NULL REFERENCES meters(id) ON DELETE CASCADE,
  device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  value NUMERIC NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- USER_SETTINGS: prahy upozornení, tarify atď.
CREATE TABLE user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexy
CREATE INDEX idx_meters_household ON meters(household_id);
CREATE INDEX idx_devices_household ON devices(household_id);
CREATE INDEX idx_devices_meter ON devices(meter_id);
CREATE INDEX idx_readings_household ON readings(household_id);
CREATE INDEX idx_readings_meter_date ON readings(meter_id, date);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE households ENABLE ROW LEVEL SECURITY;
ALTER TABLE meters ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users see own households" ON households
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users see own meters" ON meters
  FOR ALL USING (EXISTS (
    SELECT 1 FROM households WHERE households.id = meters.household_id AND households.user_id = auth.uid()
  )) WITH CHECK (EXISTS (
    SELECT 1 FROM households WHERE households.id = meters.household_id AND households.user_id = auth.uid()
  ));

CREATE POLICY "users see own devices" ON devices
  FOR ALL USING (EXISTS (
    SELECT 1 FROM households WHERE households.id = devices.household_id AND households.user_id = auth.uid()
  )) WITH CHECK (EXISTS (
    SELECT 1 FROM households WHERE households.id = devices.household_id AND households.user_id = auth.uid()
  ));

CREATE POLICY "users see own readings" ON readings
  FOR ALL USING (EXISTS (
    SELECT 1 FROM households WHERE households.id = readings.household_id AND households.user_id = auth.uid()
  )) WITH CHECK (EXISTS (
    SELECT 1 FROM households WHERE households.id = readings.household_id AND households.user_id = auth.uid()
  ));

CREATE POLICY "users see own settings" ON user_settings
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- =====================================================
-- Trigger pre auto-aktualizáciu updated_at
-- =====================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER households_updated BEFORE UPDATE ON households FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER meters_updated BEFORE UPDATE ON meters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER devices_updated BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER readings_updated BEFORE UPDATE ON readings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER user_settings_updated BEFORE UPDATE ON user_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- GRANTY pre rolu authenticated (RLS aj tak filtruje riadky)
-- POZN: Tabuľky vytvorené cez SQL Editor nedostanú auto-grant
-- (oproti vytvoreniu cez Dashboard UI). Bez týchto grantov
-- by každý query klienta vrátil 403 / "permission denied".
-- =====================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON households    TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON meters        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON devices       TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON readings      TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_settings TO authenticated;

GRANT USAGE, SELECT ON SEQUENCE households_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE meters_id_seq     TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE devices_id_seq    TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE readings_id_seq   TO authenticated;
-- user_settings má UUID PK, nepotrebuje sequence grant.
