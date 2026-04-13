-- Expanded seed data for launch testing
-- Run after 001 + 002 migrations

-- ── More products ─────────────────────────────────────────────────────────────
INSERT INTO products (barcode, name, brand, category, eligible_from) VALUES
  ('012345678906', 'Greek Yogurt 500g',        'DairyPure',   'Dairy',      '2024-01-01'),
  ('012345678907', 'Orange Juice 1L',           'SunFresh',    'Beverages',  '2024-01-01'),
  ('012345678908', 'Whole Wheat Pasta 500g',    'PastaPlus',   'Pantry',     '2024-01-01'),
  ('012345678909', 'Almond Milk 1L',            'NutriBlend',  'Dairy',      '2024-03-01'),
  ('012345678910', 'Dark Chocolate 100g',       'CocoaBliss',  'Snacks',     '2024-01-01'),
  ('012345678911', 'Coconut Water 330ml',       'TropicFresh', 'Beverages',  '2024-06-01'),
  ('012345678912', 'Baby Spinach 200g',         'GreenLeaf',   'Produce',    '2024-01-01'),
  ('012345678913', 'Cheddar Cheese 400g',       'GreenFarm',   'Dairy',      '2024-01-01')
ON CONFLICT (barcode) DO NOTHING;

-- ── Campaigns for new products ────────────────────────────────────────────────
INSERT INTO campaigns (product_id, name, cashback_type, cashback_value, max_claims, starts_at, ends_at)
SELECT p.id,
       'Summer Refresh – ' || p.name,
       'fixed',
       1.00,
       500,
       NOW() - INTERVAL '5 days',
       NOW() + INTERVAL '60 days'
FROM products p
WHERE p.barcode IN ('012345678906','012345678907','012345678910','012345678912','012345678913')
ON CONFLICT DO NOTHING;

INSERT INTO campaigns (product_id, name, cashback_type, cashback_value, max_cashback, max_claims, starts_at, ends_at)
SELECT p.id,
       '25% Back on Plant-Based',
       'percent',
       25.00,
       2.50,
       200,
       NOW() - INTERVAL '1 day',
       NOW() + INTERVAL '45 days'
FROM products p
WHERE p.barcode IN ('012345678909','012345678911')
ON CONFLICT DO NOTHING;
