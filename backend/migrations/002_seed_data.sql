-- Seed: sample products and one active campaign for development/testing

INSERT INTO products (barcode, name, brand, category, eligible_from) VALUES
  ('012345678901', 'Organic Whole Milk 1L',      'GreenFarm',   'Dairy',    '2024-01-01'),
  ('012345678902', 'Sparkling Water 500ml',       'AquaPure',    'Beverages','2024-01-01'),
  ('012345678903', 'Free Range Eggs x12',         'HappyHen',    'Dairy',    '2024-03-01'),
  ('012345678904', 'Sourdough Bread Loaf',        'BakersChoice','Bakery',   '2024-01-01'),
  ('012345678905', 'Extra Virgin Olive Oil 750ml','Medi Gold',   'Pantry',   '2024-06-01');

-- Active campaigns (fixed cashback)
INSERT INTO campaigns (product_id, name, cashback_type, cashback_value, max_claims, starts_at, ends_at)
SELECT
  p.id,
  'Spring Launch – ' || p.name,
  'fixed',
  1.50,
  1000,
  NOW() - INTERVAL '7 days',
  NOW() + INTERVAL '90 days'
FROM products p
WHERE p.barcode IN ('012345678901', '012345678902');

-- Percent-based campaign
INSERT INTO campaigns (product_id, name, cashback_type, cashback_value, max_cashback, max_claims, starts_at, ends_at)
SELECT
  p.id,
  '20% Back on Olive Oil',
  'percent',
  20.00,
  3.00,
  500,
  NOW() - INTERVAL '2 days',
  NOW() + INTERVAL '30 days'
FROM products p
WHERE p.barcode = '012345678905';
