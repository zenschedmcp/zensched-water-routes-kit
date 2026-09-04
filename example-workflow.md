# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **Agua Clara del Valle**, Guadalajara, Jalisco, Mexico (`-06:00`). Two customers (weekly house + daily tienda), one driver, then invoice.

Access notes (knock twice, loading dock) and customer names stay in SQLite. They are never sent to ZenSched. Location labels are stop code + street. ZenSched meters in the billing blobs are **USD**. Guadalajara is `-06:00` year-round (Mexico abolished DST in 2022 except a few northern-border municipios).

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Water Route, timezone_offset = -06:00,
    default_worker_id = NULL, default_shift_start = 07:00,
    default_shift_minutes = 10, invoice_due_days = 7, invoice_prefix = INV,
    stop_record_form_id = NULL, event_window_days = 60,
    default_deposit_per_bottle = 50
sqlite_query:   SELECT * FROM unpaid_stops WHERE completed_date >= date('now', '-7 days');
  → (none)
```

## "My business is Agua Clara del Valle in Guadalajara, Central time Mexico."

```
sqlite_execute: UPDATE settings SET value = 'Agua Clara del Valle' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-06:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Mexico Central time (-06:00 year-round; no DST here). You don't have a Stop Record form yet; it's free to create and every stop will come back with bottles delivered, empties collected, deposits held, and paid (Cash / Account / Unpaid). No signature — this is an internal stop record, not a tax invoice, not a deposit contract, and not a NOM-201 / COFEPRIS / FSSAI / NAFDAC plant log. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Stop Record"
  idempotency_key: "form-stop-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Stop record", "identifier": "sec_stop",
   "text": "Fill this in before you leave. Count fulls left and empties taken. This is an internal stop record, not a tax invoice, not a bottle-deposit contract, and not a NOM-201 / COFEPRIS / FSSAI / NAFDAC / ESMA plant or licence log."},
  {"type": "number", "label": "Bottles delivered", "identifier": "bottles_delivered", "required": true},
  {"type": "number", "label": "Empties collected", "identifier": "empties_collected", "required": true},
  {"type": "number", "label": "Deposits held", "identifier": "deposits_held", "required": true},
  {"type": "select", "label": "Paid", "identifier": "paid", "required": true,
   "options": ["Cash", "Account", "Unpaid"]}
]
```

```
  → form_id: 401, fields: [ ...5 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '401' WHERE key = 'stop_record_form_id';
```

> Stop Record form created. I'll attach it to every stop automatically. There is no signature step and no photo — reading a record is $0.05.

## "Add Carmen Ruiz, carmen@example.com, 33-5555-0144, Av. México 1234, Col. Americana, Guadalajara, Jalisco 44160. Weekly 20 L at $25/bottle starting Monday 2026-09-07 at 8. Knock twice, dog in the patio. Label the stop Casa."

```
sqlite_query:   SELECT service_id, price, default_minutes FROM services WHERE code = 'garrafon_20l';
  → 1, 25.00, 10

sqlite_execute:
  INSERT INTO customers (customer_name, contact_email, contact_phone, service_id, service_rate,
                         deposit_per_bottle, billing_notes)
  VALUES ('Carmen Ruiz', 'carmen@example.com', '33-5555-0144', 1, 25.00,
          50.00, 'pays cash');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO stops (customer_id, stop_label, address, city, state, zip, access_notes,
                     service_frequency, next_service_date, preferred_start, stop_order)
  VALUES (1, 'Casa', 'Av. México 1234', 'Guadalajara', 'Jalisco', '44160',
          'Knock twice. Dog in patio — wait for owner.',
          'weekly', '2026-09-07', '08:00', 1);
  → lastInsertRowid = 1
```

Agent (first metered call this session, rule 11):

> Creating Carmen's address on ZenSched costs $0.03 USD for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Casa - Av. México 1234"
  street_address: "Av. México 1234, Col. Americana, Guadalajara, Jalisco 44160"
  checkin_radius_m: 75
  idempotency_key: "loc-stop-1"
  → location_id: 9101, lat: 20.6737, lng: -103.3654, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

The knock-twice note is **not** in `notes`. Carmen's name is **not** in `name`. Both live only in SQLite. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

```
event_create:
  location_id: 9101
  title: "Water delivery - Av. México 1234"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-stop-1-20260907"
  → event_id: 7101

form_assign:
  form_id: 401
  event_id: 7101
  idempotency_key: "assign-stop-record-7101"
  → status: "assigned", form_id: 401, event_id: 7101, policy_id: 0

sqlite_execute:
  UPDATE stops SET zensched_location_id = 9101, zensched_event_id = 7101, event_valid_until = '2026-11-05'
  WHERE stop_id = 1;
```

> Added Carmen Ruiz, Av. México 1234 (Casa). Weekly 20 L at $25/bottle, next stop Monday Sep 7 at 8:00. The access note is saved on your computer only; give it to Diego directly. Her ZenSched event runs through Nov 5; I'll renew it automatically when scheduling gets that far.

## "Add a daily account for Taquería El Sol, sol@example.com, 33-5555-0190, Calle López Cotilla 890, Guadalajara, Jalisco 44100, starting Tuesday 2026-09-08 at 7, $22/bottle, invoice weekly. Loading dock behind. Label the stop Tienda."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session). Frequency is `daily`. Rate is $22 (off-list).

```
sqlite_query:   SELECT service_id, default_minutes FROM services WHERE code = 'garrafon_20l';
  → 1, 10

sqlite_execute:
  INSERT INTO customers (customer_name, contact_email, contact_phone, service_id, service_rate,
                         billing_notes)
  VALUES ('Taquería El Sol', 'sol@example.com', '33-5555-0190', 1, 22.00,
          'invoice weekly');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO stops (customer_id, stop_label, address, city, state, zip, access_notes,
                     service_frequency, next_service_date, preferred_start, stop_order)
  VALUES (2, 'Tienda', 'Calle López Cotilla 890', 'Guadalajara', 'Jalisco', '44100',
          'Loading dock behind. Ask for kitchen.',
          'daily', '2026-09-08', '07:00', 1);
  → lastInsertRowid = 2

location_create:
  name: "Tienda - Calle López Cotilla 890"
  street_address: "Calle López Cotilla 890, Guadalajara, Jalisco 44100"
  checkin_radius_m: 75
  idempotency_key: "loc-stop-2"
  → location_id: 9102

event_create:
  location_id: 9102
  title: "Water delivery - Calle López Cotilla 890"
  start_date: "2026-09-08"
  end_date:   "2026-11-06"
  idempotency_key: "event-stop-2-20260908"
  → event_id: 7102

form_assign: form_id 401, event_id 7102, idempotency_key "assign-stop-record-7102"

sqlite_execute:
  UPDATE stops SET zensched_location_id = 9102, zensched_event_id = 7102, event_valid_until = '2026-11-06'
  WHERE stop_id = 2;
```

> Added Taquería El Sol, Calle López Cotilla 890 (Tienda). Daily 20 L at $22/bottle, next stop Tuesday Sep 8 at 7:00, invoice weekly. Dock note is local only.

## "Invite Diego Morales, diego@example.com, and make him the default."

> Inviting a driver costs $0.25 USD. OK?

Owner: *"yes"*

```
worker_invite:
  email: "diego@example.com"
  first_name: "Diego"
  last_name: "Morales"
  idempotency_key: "worker-diego@example.com"
  → worker_id: 601, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO drivers (driver_name, email, zensched_worker_id)
  VALUES ('Diego Morales', 'diego@example.com', 601);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '601' WHERE key = 'default_worker_id';
```

> Invited Diego. He'll get an email with the app link and an activation code. He's the default driver now. Remember to give him Carmen's knock-twice note and El Sol's dock note; I keep those off ZenSched on purpose.

Optional, if the owner wants a wider circle for mercados / apartment blocks:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 150}'
```

The radius is on the **policy**, not on either location.

## "Schedule this week for Diego."

```
sqlite_query: SELECT * FROM stops_due;
  → 2026-09-07 | Carmen Ruiz | Casa | weekly | $25 | garrafon_20l | 10 min
               | stop 1 | evt 7101 | event_needs_roll 0 | worker 601 Diego
               | start_iso 2026-09-07T08:00:00-06:00 | end_iso 2026-09-07T08:10:00-06:00
               | shift-stop-1-20260907
    2026-09-08 | Taquería El Sol | Tienda | daily | $22 | garrafon_20l | 10 min
               | stop 2 | evt 7102 | event_needs_roll 0 | worker 601 Diego
               | start_iso 2026-09-08T07:00:00-06:00 | end_iso 2026-09-08T07:10:00-06:00
               | shift-stop-2-20260908
  (2 rows)

shift_create:
  event_id: 7101
  worker_id: 601
  start: "2026-09-07T08:00:00-06:00"
  end:   "2026-09-07T08:10:00-06:00"
  idempotency_key: "shift-stop-1-20260907"
  → shift_id: 88011, status: "scheduled", forms_installed: [401]

shift_create:
  event_id: 7102
  worker_id: 601
  start: "2026-09-08T07:00:00-06:00"
  end:   "2026-09-08T07:10:00-06:00"
  idempotency_key: "shift-stop-2-20260908"
  → shift_id: 88012, status: "scheduled", forms_installed: [401]
```

> Scheduled 2 stops for Diego this week:
> - Mon 9/7  8:00–8:10  Carmen Ruiz, Av. México 1234 — weekly
> - Tue 9/8  7:00–7:10  Taquería El Sol, Calle López Cotilla 890 — daily
>
> Diego has been notified in the app and both stops have the Stop Record attached. Each stop is about $0.25 USD once he punches in and out and you read the record ($0.10 + $0.10 + $0.05). El Sol is daily — only Tuesday (its next date) is on this list. Say the word and I'll pre-build Wed–Sat. Pass him the access notes yourself.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same two shifts instead of creating duplicates.

## Diego does the work

Monday 7:58, at Av. México 1234, in the ZenSched app: **Check in** (GPS: 14 m from the pin, verified, $0.10). Leaves 2 fulls, pulls 2 empties. Opens **Stop Record**: Bottles delivered = 2; Empties collected = 2; Deposits held = 4; Paid = Cash. Submits (no signature). **Check out** 8:07 ($0.10).

Tuesday 6:55, Calle López Cotilla 890: check in at the dock. Leaves 4, pulls 3 (they kept one extra). Stop Record: delivered = 4; empties = 3; deposits held = 8; Paid = Account. Check out 7:08.

## "Record this week's visits."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 88011, event_id: 7101, worker_id: 601, date: "2026-09-07", start: "08:00", end: "08:10", status: "checked_out" },
      { shift_id: 88012, event_id: 7102, worker_id: 601, date: "2026-09-08", start: "07:00", end: "07:10", status: "checked_out" }
    ], count: 2

sqlite_query: SELECT zensched_shift_id FROM visits WHERE zensched_shift_id IN (88011, 88012);
  → (none; not yet recorded)

sqlite_query: SELECT s.stop_id, s.customer_id, c.service_id, c.service_rate
              FROM stops s JOIN customers c USING (customer_id)
              WHERE s.zensched_event_id = 7101;
  → 1, 1, 1, 25.00
```

Agent (metered read, rule 11):

> There are 2 Stop Records to pull, no photos, so about $0.10 USD ($0.05 each). I'll read them once and keep the counts locally. That's the last piece of the ~$0.25/stop USD meter (punches already billed when Diego checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 401
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 2, rows: [
      { submission_id: 4401, worker_id: 601, event_id: 7101, submitted_at: "2026-09-07 08:05:12",
        data: { bottles_delivered: 2, empties_collected: 2, deposits_held: 4, paid: "cash" } },
      { submission_id: 4402, worker_id: 601, event_id: 7102, submitted_at: "2026-09-08 07:06:40",
        data: { bottles_delivered: 4, empties_collected: 3, deposits_held: 8, paid: "account" } }
    ]
    billing: { meter: "form_basic", units: 2, price: 0.10 }

shift_status: shift_id 88011
  → status "checked_out", actual_in "2026-09-07T07:58:10-06:00", actual_out "2026-09-07T08:07:05-06:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 14 },
               { type: "out", gps_verified: true, distance_from_site_m: 11 } ]
(free)

sqlite_execute:
  INSERT INTO visits (customer_id, stop_id, service_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                      bottles_delivered, empties_collected, deposits_held, paid)
  VALUES (1, 1, 1, '2026-09-07', 50.00,
          88011, 7101, 601,
          '2026-09-07T07:58:10-06:00', '2026-09-07T08:07:05-06:00', 9, 1, 4401,
          2, 2, 4, 'Cash');
  -- trigger: stops.next_service_date for Carmen → 2026-09-14 (+7)
  -- trigger: stops.bottles_on_deposit → 4
  -- trigger: visits.invoiced → 1 (Cash)
  -- trigger: visits.driver_id → 1 (Diego)

sqlite_execute:
  INSERT INTO visits (customer_id, stop_id, service_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                      bottles_delivered, empties_collected, deposits_held, paid)
  VALUES (2, 2, 1, '2026-09-08', 88.00,
          88012, 7102, 601,
          '2026-09-08T06:55:02-06:00', '2026-09-08T07:08:18-06:00', 13, 1, 4402,
          4, 3, 8, 'Account');
  -- trigger: stops.next_service_date for El Sol → 2026-09-09 (+1 day)
  -- trigger: stops.bottles_on_deposit → 8
```

> Recorded 2 visits, both GPS-verified. Nothing unpaid.
>
> Carmen weekly: 2 full / 2 empty, deposits 4, cash $50. Next due Sep 14.
> El Sol daily: 4 full / 3 empty, deposits 8, account $88. Next due Sep 9.

## "Who holds deposits?"

```
sqlite_query: SELECT * FROM deposit_book;
  → Carmen Ruiz    | Casa   | Av. México 1234          | 4 bottles | 50 each | 200
    Taquería El Sol| Tienda | Calle López Cotilla 890  | 8 bottles | 50 each | 400
```

El Sol has no `deposit_per_bottle` on the customer, so the view uses `settings.default_deposit_per_bottle` (50).

> Your copy from the Stop Record — not a deposit contract and not a NOM-201 / COFEPRIS / FSSAI / NAFDAC plant log:
>
> | Customer | Stop | Bottles on deposit | Liability |
> |---|---|---|---|
> | Carmen Ruiz | Casa | 4 | 200 |
> | Taquería El Sol | Tienda | 8 | 400 |
>
> Keep whatever receipt your country wants separately.

## "Draft invoices for everyone with uninvoiced account work."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Taquería El Sol | 1 visit | 88.00 | 4 bottles | 2026-09-08 .. 2026-09-08
  (Carmen's cash visit is already invoiced = 1 and does not appear)

sqlite_execute:
  INSERT INTO invoices (customer_id, invoice_date, due_date, total_amount, line_items)
  SELECT j.customer_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(j.amount),
         json_group_array(json_object('visit_id', j.visit_id, 'date', j.completed_date,
                                      'bottles', j.bottles_delivered, 'empties', j.empties_collected,
                                      'amount', j.amount, 'shift_id', j.zensched_shift_id, 'stop_id', j.stop_id))
  FROM visits j
  WHERE j.invoiced = 0 AND j.paid = 'Account' AND j.customer_id = 2 GROUP BY j.customer_id;

sqlite_execute: UPDATE visits SET invoiced = 1 WHERE invoiced = 0 AND paid = 'Account' AND customer_id = 2;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-08 | 2026-09-15 | 88.00     (number assigned by trigger)
```

The agent then writes the invoice out as text:

> Here is your invoice. Paste it into WhatsApp or email.
>
> ```
> Agua Clara del Valle
> Invoice INV-2026-0001
> To: Taquería El Sol (sol@example.com)
> Date: Sep 8, 2026    Due: Sep 15, 2026
>
>   Sep 8    4 × 20 L, Calle López Cotilla 890    $88.00
>
> Total due: $88.00
> Visit GPS-verified at the stop.
> Official NOM-201 / COFEPRIS / FSSAI / NAFDAC / ESMA plant or licence filing stays in your binder — this is not that log.
> ```
>
> Carmen's Monday cash ($50) is already collected — not on an invoice. Say "sent" when El Sol's is out.

## "Sent. El Sol already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number = 'INV-2026-0001';
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked INV-2026-0001 sent and paid. Nothing outstanding.

## Eight weeks later: "Schedule this week."

```
sqlite_query: SELECT * FROM stops_due;
  → 2026-11-07 | Carmen Ruiz | weekly | evt 7101 | event_valid_until 2026-11-05 | event_needs_roll 1 | ...

event_create:
  location_id: 9101
  title: "Water delivery - Av. México 1234"
  start_date: "2026-11-07"
  end_date:   "2027-01-05"
  idempotency_key: "event-stop-1-20261107"
  → event_id: 7201

form_assign: form_id 401, event_id 7201, idempotency_key "assign-stop-record-7201"
sqlite_execute: UPDATE stops SET zensched_event_id = 7201, event_valid_until = '2027-01-05' WHERE stop_id = 1;

shift_create: event_id 7201, worker_id 601, start "2026-11-07T08:00:00-06:00",
              end "2026-11-07T08:10:00-06:00", idempotency_key "shift-stop-1-20261107"
```

> Scheduled Carmen for Sat Nov 7 8:00. Her ZenSched event was about to expire (Nov 5), so I renewed it through Jan 5. El Sol's next daily date depends on the last recorded visit — if it's already been recorded through last week, tomorrow is on the list; if not, say "record last week's visits" first.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Carmen's contact, $25 weekly, El Sol's $22 daily, prices | SQLite | CRM; ZenSched does not model rates or recurrence |
| Knock-twice, loading dock, customer names | SQLite **only** | Privacy; never sent to ZenSched (location label is stop code + street) |
| Each stop's GPS location | ZenSched (integer ID in `stops`) | Needed for geofenced check-in |
| Each stop's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `stops`) | Shifts hang off events; renewed by the agent |
| The Stop Record form | ZenSched (ID in `settings`) | Installed on the driver's phone per shift |
| Diego, his invite, his app | ZenSched (integer ID in `drivers`) | Workforce and notifications |
| The week's two shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Two Stop Records | ZenSched (originals); counts in `visits` | Read once (metered), then deposit book / invoices from SQLite |
| Two `visits` rows referencing shift and submission IDs | SQLite | Billing + deposit book |
| One invoice, paid (El Sol Account); Carmen Cash auto-invoiced | SQLite | Billing |
