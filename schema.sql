-- ZenSched Water-Routes Local Database Schema
-- SQLite database for CRM, delivery cadence, bottle/empty/deposit
-- summaries, and billing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my water-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 water-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT A TAX INVOICE, NOT A DEPOSIT CONTRACT, AND NOT AN OFFICIAL PLANT LOG.
-- deposit_book is the owner's local extract of what the driver typed on the
-- Stop Record (date, stop, fulls, empties, deposits held, paid). It is not a
-- SAT / CFDI / GST invoice, not a bottle-deposit legal receipt, not a plant /
-- warehouse stock count, and not a NOM-201 / COFEPRIS bitácora, FSSAI / BIS
-- file, NAFDAC book, or ESMA / GSO mark. GPS proves the driver was at the
-- door, not that the bottles were filled at the plant.
-- ZenSched meters are always USD; local bottle prices stay in this file.
--
-- PRIVACY: stops.access_notes (gate, dog, "leave with the neighbor",
-- building code) and customer names live ONLY in this file on your computer.
-- They are never sent to ZenSched. The location label is stop_label + street.
-- SKILL.md forbids the agent from putting names or access notes in any
-- ZenSched field.
--
-- Shape: customers → stops → visits. Same as the LPG cylinder kit: one
-- customer can have a house and a shop; cadence and the ZenSched pin live
-- on the stop. Daily routes advance +1 day per recorded visit.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default driver, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Water Route');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-06:00');  -- Guadalajara / CDMX year-round; MX abolished DST 2022 except some northern-border municipios. Gulf +04:00, IN +05:30, NG +01:00 — no DST.
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '07:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '10');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '7');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('stop_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_deposit_per_bottle', '50');

-- Services: your price list. Seeded with common jug sizes; edit prices freely.
-- Prices are in the owner's currency. visits.amount is bottles_delivered times
-- the customer's per-bottle service_rate (which may differ from the list).
CREATE TABLE IF NOT EXISTS services (
  service_id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,                        -- short handle: 'garrafon_20l'
  service_name TEXT NOT NULL,                       -- shown on invoices
  default_minutes INTEGER NOT NULL,                 -- shift length on ZenSched
  price REAL NOT NULL,                              -- default per-bottle (or per-rental)
  is_active INTEGER DEFAULT 1,
  notes TEXT
);

INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('garrafon_20l', '20 L / 5-gal bottle', 10, 25.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('bottle_10l', '10 L bottle', 10, 18.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('case_small', 'Case of small bottles', 10, 40.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('dispenser', 'Dispenser rental', 20, 80.00);

-- Customers: contact, default product, per-bottle rate, deposit amount.
-- Cadence lives on stops (a house can be weekly while the shop is daily).
CREATE TABLE IF NOT EXISTS customers (
  customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,                               -- WhatsApp number; stays local
  service_id INTEGER,                               -- default product
  service_rate REAL NOT NULL,                       -- price per bottle (may differ from the list)
  deposit_per_bottle REAL,                          -- bottle deposit; NULL = settings.default_deposit_per_bottle
  zensched_worker_id INTEGER,                       -- preferred driver; NULL = settings.default_worker_id
  billing_notes TEXT,                               -- 'pays cash', 'invoice weekly', 'WhatsApp only'
  is_active INTEGER DEFAULT 1,                      -- 0 = paused / cancelled
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Stops: delivery addresses with ZenSched references.
-- One ZenSched LOCATION per stop, created once and kept forever.
-- One ZenSched EVENT per stop per rolling window of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a visit date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
-- Cadence (frequency + next_service_date) lives here, not on the customer.
CREATE TABLE IF NOT EXISTS stops (
  stop_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  stop_label TEXT,                                  -- 'Casa', 'Tienda', 'Office'
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  access_notes TEXT,                                -- LOCAL ONLY: gate, dog, neighbor, building code
  stop_order INTEGER DEFAULT 1
    CHECK (stop_order IS NULL OR stop_order >= 1),
  service_frequency TEXT NOT NULL
    CHECK (service_frequency IN ('daily', 'weekly', 'biweekly', 'monthly', 'on-demand')),
  next_service_date TEXT,                           -- ISO date: '2026-09-07'
  last_service_date TEXT,                           -- set automatically when a visit is recorded
  preferred_start TEXT                              -- 'HH:MM' 24-hour local; NULL = settings.default_shift_start
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  bottles_on_deposit INTEGER DEFAULT 0,             -- running count; trigger copies visits.deposits_held
  zensched_worker_id INTEGER,                       -- pin this stop to a driver; else customer; else default
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Drivers: your roster. zensched_worker_id comes from worker_invite.
CREATE TABLE IF NOT EXISTS drivers (
  driver_id INTEGER PRIMARY KEY AUTOINCREMENT,
  driver_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per COMPLETED delivery, linked to the ZenSched shift and
-- the Stop Record form submission. This is the billing record plus a small
-- summary so deposit_book / unpaid_stops are local queries.
-- paid is CHECK-constrained to the form's option labels.
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  stop_id INTEGER NOT NULL,
  service_id INTEGER NOT NULL,
  driver_id INTEGER,                                -- local roster row (trigger fills from worker id)
  completed_date TEXT NOT NULL,                     -- ISO date: '2026-09-07'
  amount REAL NOT NULL,                             -- bottles_delivered * customer.service_rate
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,                                   -- from shift_status / timesheet_export
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  report_dc_id INTEGER,                             -- Stop Record submission_id
  bottles_delivered INTEGER,                        -- number from the form
  empties_collected INTEGER,                        -- number from the form
  deposits_held INTEGER,                            -- number from the form (running bottles on deposit)
  paid TEXT CHECK (paid IS NULL OR paid IN ('Cash', 'Account', 'Unpaid')),
  notes TEXT,
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice (Cash auto-marks)
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (stop_id) REFERENCES stops(stop_id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(service_id),
  FOREIGN KEY (driver_id) REFERENCES drivers(driver_id) ON DELETE SET NULL
);

-- Invoices: billing records for Account stops (Cash is already collected).
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually WhatsApped / emailed it
  line_items TEXT,                                  -- JSON array of visit references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active);
CREATE INDEX IF NOT EXISTS idx_customers_service ON customers(service_id);
CREATE INDEX IF NOT EXISTS idx_stops_next_service ON stops(next_service_date, is_active);
CREATE INDEX IF NOT EXISTS idx_stops_customer ON stops(customer_id);
CREATE INDEX IF NOT EXISTS idx_stops_zensched_location ON stops(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_stops_zensched_event ON stops(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_drivers_worker ON drivers(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_visits_customer ON visits(customer_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_stop ON visits(stop_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_invoiced ON visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_visits_paid ON visits(paid);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_customer_timestamp
AFTER UPDATE ON customers
BEGIN
  UPDATE customers SET updated_at = datetime('now') WHERE customer_id = NEW.customer_id;
END;

CREATE TRIGGER IF NOT EXISTS update_stop_timestamp
AFTER UPDATE ON stops
BEGIN
  UPDATE stops SET updated_at = datetime('now') WHERE stop_id = NEW.stop_id;
END;

CREATE TRIGGER IF NOT EXISTS update_driver_timestamp
AFTER UPDATE ON drivers
BEGIN
  UPDATE drivers SET updated_at = datetime('now') WHERE driver_id = NEW.driver_id;
END;

-- Fill driver_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_driver
AFTER INSERT ON visits
WHEN NEW.driver_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE visits
  SET driver_id = (SELECT driver_id FROM drivers WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Recording a completed visit automatically advances that stop's cadence.
-- daily is +1 day. on-demand clears the next date.
-- The agent should NOT hand-maintain next_service_date after this.
-- A one-off recorded on a recurring stop also moves the cadence; if the
-- owner wants the regular stop kept, set next_service_date back explicitly.
CREATE TRIGGER IF NOT EXISTS advance_service_date_on_visit
AFTER INSERT ON visits
BEGIN
  UPDATE stops
  SET last_service_date = NEW.completed_date,
      next_service_date = CASE service_frequency
        WHEN 'daily'     THEN date(NEW.completed_date, '+1 day')
        WHEN 'weekly'    THEN date(NEW.completed_date, '+7 days')
        WHEN 'biweekly'  THEN date(NEW.completed_date, '+14 days')
        WHEN 'monthly'   THEN date(NEW.completed_date, '+1 month')
        ELSE NULL                                    -- on-demand: no automatic next visit
      END
  WHERE stop_id = NEW.stop_id;
END;

-- Copy the driver's deposits_held count onto the stop (running bottles on deposit).
CREATE TRIGGER IF NOT EXISTS apply_deposit_held
AFTER INSERT ON visits
WHEN NEW.deposits_held IS NOT NULL
BEGIN
  UPDATE stops
  SET bottles_on_deposit = NEW.deposits_held
  WHERE stop_id = NEW.stop_id;
END;

-- Cash collected at the door is already paid — do not put it on an invoice.
CREATE TRIGGER IF NOT EXISTS mark_cash_invoiced
AFTER INSERT ON visits
WHEN NEW.paid = 'Cash'
BEGIN
  UPDATE visits SET invoiced = 1 WHERE visit_id = NEW.visit_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days (today + 6). The agent's scheduling query.
-- One row = one shift_create call. Columns ending in _iso are ready to pass
-- as shift_create start/end; idempotency_key is ready too.
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
-- access_notes is included so the agent can tell the owner to pass it to the
-- driver; it must never go into a ZenSched field.
-- A daily stop appears once (its next_service_date). After you record it,
-- tomorrow appears. Pre-create extra weekdays with explicit dates if asked.
CREATE VIEW IF NOT EXISTS stops_due AS
SELECT
  s.stop_id,
  s.stop_label,
  s.address,
  s.city,
  s.state,
  s.zip,
  s.access_notes,
  s.stop_order,
  s.service_frequency,
  s.next_service_date,
  s.bottles_on_deposit,
  s.zensched_location_id,
  s.zensched_event_id,
  s.event_valid_until,
  CASE WHEN s.event_valid_until IS NULL OR s.event_valid_until < s.next_service_date THEN 1 ELSE 0 END AS event_needs_roll,
  COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  c.customer_id,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  c.service_rate,
  c.deposit_per_bottle,
  c.billing_notes,
  sv.service_id,
  sv.code                                    AS service_code,
  sv.service_name,
  COALESCE(sv.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) AS default_minutes,
  COALESCE(s.zensched_worker_id, c.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT d.driver_name FROM drivers d
    WHERE d.zensched_worker_id = COALESCE(s.zensched_worker_id, c.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS driver_name,
  s.next_service_date || 'T'
    || COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      s.next_service_date || ' '
      || COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || COALESCE(sv.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-stop-' || s.stop_id || '-' || strftime('%Y%m%d', s.next_service_date) AS idempotency_key
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id AND c.is_active = 1
LEFT JOIN services sv ON sv.service_id = c.service_id
WHERE s.is_active = 1
  AND s.next_service_date IS NOT NULL
  AND s.next_service_date <= date('now', '+7 days')
ORDER BY s.next_service_date, COALESCE(s.stop_order, 1),
         COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')),
         c.customer_name;

-- Stops whose current ZenSched event expires within 14 days (or has none)
-- and that belong to an active customer. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  s.stop_id,
  s.stop_label,
  c.customer_name,
  s.address,
  s.zensched_location_id,
  s.zensched_event_id,
  s.event_valid_until
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id AND c.is_active = 1
WHERE s.is_active = 1
  AND (s.event_valid_until IS NULL OR s.event_valid_until <= date('now', '+14 days'))
ORDER BY s.event_valid_until;

-- Account visits that have not been invoiced yet. Cash is auto-marked
-- invoiced. Unpaid cash-at-the-door stays on unpaid_stops, not here.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.customer_id,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  c.billing_notes,
  COUNT(v.visit_id)       AS visit_count,
  SUM(v.amount)           AS total_amount,
  SUM(v.bottles_delivered) AS bottles,
  MIN(v.completed_date)   AS first_visit_date,
  MAX(v.completed_date)   AS last_visit_date
FROM visits v
JOIN customers c ON c.customer_id = v.customer_id
WHERE v.invoiced = 0
  AND v.paid = 'Account'
GROUP BY c.customer_id
ORDER BY c.customer_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN customers c ON c.customer_id = i.customer_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Owner's local deposit book: stops that currently hold bottles on deposit.
-- Liability uses the customer's deposit_per_bottle, or the settings default.
-- This is the owner's copy, not a legal deposit contract.
CREATE VIEW IF NOT EXISTS deposit_book AS
SELECT
  s.stop_id,
  c.customer_id,
  c.customer_name,
  s.stop_label,
  s.address,
  s.city,
  s.bottles_on_deposit,
  COALESCE(c.deposit_per_bottle,
           CAST((SELECT value FROM settings WHERE key = 'default_deposit_per_bottle') AS REAL)) AS deposit_per_bottle,
  s.bottles_on_deposit * COALESCE(c.deposit_per_bottle,
           CAST((SELECT value FROM settings WHERE key = 'default_deposit_per_bottle') AS REAL)) AS deposit_liability,
  s.last_service_date
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id
WHERE s.is_active = 1
  AND s.bottles_on_deposit IS NOT NULL
  AND s.bottles_on_deposit > 0
ORDER BY c.customer_name, s.stop_label;

-- Stops where the driver marked Paid = Unpaid. Lead with these.
CREATE VIEW IF NOT EXISTS unpaid_stops AS
SELECT
  v.visit_id,
  v.completed_date,
  c.customer_name,
  c.contact_phone,
  s.address,
  s.stop_label,
  v.bottles_delivered,
  v.empties_collected,
  v.deposits_held,
  v.amount,
  v.paid,
  COALESCE(d.driver_name, 'driver ' || v.zensched_worker_id) AS driver,
  v.zensched_shift_id,
  v.report_dc_id
FROM visits v
JOIN stops s ON s.stop_id = v.stop_id
JOIN customers c ON c.customer_id = v.customer_id
LEFT JOIN drivers d ON d.driver_id = v.driver_id
WHERE v.paid = 'Unpaid'
ORDER BY v.completed_date DESC, c.customer_name;
