# ZenSched Water-Routes Reference Kit

A copy-pasteable setup for a 1–5 truck drinking-water delivery shop (20 L / 5-gal garrafón and jug routes — houses, tiendas, offices) that wants an AI assistant to run daily-route scheduling, GPS-verified Stop Records (fulls, empties, deposits, paid), a local deposit book, and invoicing for account customers. ZenSched handles the live schedule, the driver's phone app, GPS check-ins at the door, and the Stop Record form. A small local database on your computer holds your customers, stops, prices, cadence, visit summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule today", "add a weekly house", "how many empties did Diego pull at El Sol", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

This is the same shape as the [LPG cylinder-routes kit](https://github.com/zenschedmcp/zensched-lpg-routes-kit): customers → stops → visits, in/out counts per stop, bottle deposits, daily cadence.

## What this kit is not — read this first

**What it is:** GPS-verified proof that a driver was at the address, a Stop Record (bottles delivered, empties collected, deposits held, paid cash / account / unpaid), a local deposit book, and invoices built from Account visits. ZenSched meters are **always USD**.

**What it is not:**

- **Not a tax invoice.** `invoices` is a plain-text bill you paste into WhatsApp. It is not a SAT CFDI, not a GST e-invoice, not a fiscal receipt. Your accountant still files whatever your country requires.
- **Not a bottle-deposit contract.** `deposit_book` is *your* copy of the count the driver typed (how many jugs that stop currently holds). It is not a legal deposit receipt and not proof the customer agreed to a deposit.
- **Not a NOM-201 / COFEPRIS / FSSAI / NAFDAC / ESMA plant or licence log.** The Stop Record can collect fulls, empties, cash, and deposits. Official plant bitácora, lab tests, and inspector access stay in your binder or AquaOS / PaniHisab. Do not tell a COFEPRIS / FSSAI / NAFDAC inspector "it's in ZenSched."
- **Not plant / warehouse inventory.** This kit does not know how many fulls are on the truck or at the plant. GPS proves the driver was at the door, not that the bottles were filled.
- **Not a signed proof of delivery.** The Stop Record has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like the customer (or the driver) had signed a receipt. Submitting the form is just submitting the form.
- **Not billed in MXN / INR / NGN / AED.** Local bottle prices stay in your currency in SQLite. ZenSched's meter (GPS, form reads, geocode, invites) is always US dollars.

If any of those is a deal-breaker, this kit is not for you. If you want route cadence, door-GPS, and a local extract of fulls / empties / deposits, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (delivery stops with GPS coordinates; the check-in radius is a **policy** setting)
- Workers (drivers with the mobile app)
- Events (one "Water delivery" job per stop, renewed every 60 days)
- Shifts (each scheduled visit, with push notifications to the driver)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Stop Record form (bottles delivered, empties collected, deposits held, paid) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`water-ops.db`, on your computer):**

- Customer contact, per-bottle rate, deposit per bottle
- Stops (addresses), including access notes (gate, dog, "leave with the neighbor") that **never leave your computer**, plus frequency (daily / weekly / biweekly / monthly / on-demand) and next service date
- Your price list (20 L / 5-gal, 10 L, case of small bottles, dispenser rental)
- Drivers
- Completed visits with the Stop Record counts, the deposit book, and invoices
- Your settings (timezone, default driver, invoice prefix, Stop Record form id)

**Never duplicated:** the live schedule, punches, timesheets, and form originals stay in ZenSched. The local database only stores *references* to them plus the per-visit counts so you can answer "what did Diego leave at Carmen's" without paying to re-read reports.

### Privacy note

Gate codes, building codes, "leave with the neighbor", dogs, and **customer names** are stored only in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. Give access notes to your driver yourself, by whatever channel you trust (often WhatsApp). The ZenSched location label is **stop code + street** (e.g. `Casa - Av. México 1234`), never the customer name. ZenSched only ever sees that label, the street address, and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `water-ops.db` on your computer.

When you say "schedule today," the AI reads who is due from the local database (`next_service_date` in the next 7 days), creates one shift per stop on ZenSched, and tells you what it did. Your driver sees the stops in the app, checks in at the door (GPS-verified), leaves fulls, pulls empties, fills in the Stop Record, and checks out. Later you say "record today's visits" and the AI pulls the completed shifts and records, saves the counts locally, advances each stop's next date (daily +1 day, weekly +7, on-demand clears it), updates the deposit book, and flags anything marked Unpaid. "Who holds deposits" is a local query. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical stop costs about **$0.25 USD** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading a Stop Record **without photos** $0.05. Geocoding a new stop is $0.03 once. Meters are always US dollars. The AI states the USD cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\water-ops`
- Mac: `/Users/yourname/water-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\water-ops.db` (Windows) or `/water-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "water-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/water-ops/water-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\water-ops\\water-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Water Route" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my water-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `water-ops.db` file now exists in your folder, pre-loaded with a starter price list you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 water-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Agua Clara del Valle in Guadalajara (Central time, Mexico). Save that in settings, and set up the Stop Record form.

It writes those to the `settings` table, creates the Stop Record form on ZenSched (free), and saves the form id so every stop gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=75` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per stop. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a house-and-driveway circle. For an apartment block, a mercado, or a pin that lands on the road, ask the AI to "set the check-in radius to 150 m" (`policy_update`) or to move the pin onto the building (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered **in USD**: creating a location (geocoding, $0.03), inviting a driver ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Stop Record ($0.05; this form has no photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit (USD), which is credited to your balance. You will not be charged without seeing this first.

A typical stop is about $0.25 USD (in + out + Stop Record). A driver doing 40 stops a day is about $10 USD in meters that day, plus $0.03 the first time you add each address. The AI states the USD cost before it spends. Local bottle prices stay in your currency.

## Using it

Everything after setup is plain English. Examples:

- "Add Carmen Ruiz, carmen@example.com, 33-5555-0144, Av. México 1234, Col. Americana, Guadalajara Jalisco 44160. Weekly 20 L at $25/bottle starting Monday 8. Knock twice, dog in the patio."
- "Add a daily account for Taquería El Sol at Calle López Cotilla 890, Guadalajara, $22/bottle, 7am, invoice weekly. Loading dock behind."
- "Invite Diego Morales, diego@example.com, and make him the default driver."
- "Schedule today for Diego."
- "Record today's visits."
- "Who holds deposits?"
- "Draft invoices for account customers."
- "Who still owes me money?"
- "El Sol paid INV-2026-0001."
- "Pause Carmen until November."
- "Drop 6 extra bottles at Carmen's Thursday."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which visits) and the AI writes out a plain-text invoice you can paste into WhatsApp or email, with a line per stop and a note that the visit was GPS-verified. It does **not** generate a PDF, a SAT CFDI, email it for you, or collect payment. Cash stops are already collected and do not appear. When the customer pays, tell the AI ("El Sol paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for drivers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a driver, they get an email, install the app, and can immediately see their stops, check in and out with GPS verification, and fill in the Stop Record. The record is attached to each stop automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `water-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, or the AI flipped the offset for "DST" | "Set my timezone offset to -06:00 in settings" (use your own offset). MX except some northern-border towns, plus Gulf / IN / NG, have **no DST** — do not change `-06:00` to `-05:00` in summer |
| Shift creation fails for dates a couple of months out | The stop's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Driver's check-in not GPS-verified at a house | Geocoded pin is at the mailbox, driver parked far away, or a large lot | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the location), or run `location_update` / `location_refine` ($0.10) |
| Driver does not see the Stop Record | Form not assigned to that stop's event | "Attach the Stop Record to Carmen's event" (`form_assign`) |
| "Deposit book" comes back empty | Visits not recorded yet, or the driver typed 0 deposits held | "Record today's visits" first |
| Daily customer only got one shift this week | Working as intended | `stops_due` emits the *next* date only. Say "pre-build El Sol Tue–Sat" |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a gate code in ZenSched | Working as intended | Give it to the driver directly |
| AI offers a SAT invoice, a signed POD, or a NOM-201 / FSSAI / NAFDAC plant log | It shouldn't | This kit does not produce those; official filing stays in your binder or AquaOS / PaniHisab |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, cadence, bottle/empty/deposit summaries, and billing; each side stores only the other's **integer** IDs, plus per-visit counts cached locally because submission reads are metered.

**Data model decisions.**

- **customers → stops → visits**, same shape as the LPG kit. One customer can have a house (weekly) and a shop (daily). Cadence and the ZenSched pin live on the **stop**.
- One ZenSched **location** per stop, permanent, stored on `stops.zensched_location_id` as an integer. Created with `location_create(name="<stop_label> - <street>", street_address=..., checkin_radius_m=75, idempotency_key=...)` — the label is stop code + street, never the customer name. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template. Each stop holds its *current* event in `stops.zensched_event_id` and its last covered date in `stops.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Water delivery - <street>", start_date, end_date=start+59 days, idempotency_key="event-stop-{stop_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it, and updates the row. `stops_due` exposes `event_needs_roll` per row and `events_expiring` lists stops due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches a stop, the agent falls back to `event_get(event_id).location_id` against `stops.zensched_location_id`.
- **Cadence is next-service-date on the stop.** `stops.service_frequency` is `daily | weekly | biweekly | monthly | on-demand`. `stops_due` is every active stop with `next_service_date <= today+7` joined to an active customer, emitting `start_iso` / `end_iso` (preferred start or `settings.default_shift_start`, duration from the service or `default_shift_minutes`) and the shift `idempotency_key`. A daily stop appears **once** (its next date); after recording, tomorrow appears. Pre-building the rest of a week is extra `shift_create` calls with explicit dates, not extra view rows.
- **The `advance_service_date_on_visit` trigger** sets `last_service_date` and `next_service_date` on every visit insert: **+1 day** / +7 / +14 / +1 month / NULL. Recording a one-off on a recurring stop also moves the cadence; `SKILL.md` tells the agent to set the date back if the owner says so.
- Rate lives on the **customer** (`service_rate`, per bottle) so a shop can charge off-list. `visits.amount` = `bottles_delivered * service_rate`.
- `visits.zensched_shift_id` and `drivers.zensched_worker_id` are integer `UNIQUE`. `visits.report_dc_id` holds the form `submission_id`. `paid` is `CHECK`-constrained to the form's option labels (`Cash` | `Account` | `Unpaid`).
- `fill_visit_driver` sets `driver_id` from `zensched_worker_id` when the agent leaves it NULL.
- `apply_deposit_held` copies `visits.deposits_held` onto `stops.bottles_on_deposit` (running count the driver confirmed after the stop).
- `mark_cash_invoiced` sets `invoiced = 1` when `paid = 'Cash'` so door collections never land on `visits_to_invoice`.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`.
- **`deposit_book`** is a view over stops with `bottles_on_deposit > 0`. Liability uses `customers.deposit_per_bottle` or `settings.default_deposit_per_bottle`. It does not transmit anything and is not a legal contract.
- **`unpaid_stops`** is every visit with `paid = 'Unpaid'`. The agent leads with these.
- `stops.access_notes` and customer names must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. The location label is `<stop_label> - <street>`. `stops_due` still *selects* `access_notes` so the agent can tell the owner to pass them to the driver.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Stop Record form.** Created once with `form_create(title, fields_json, idempotency_key="form-stop-record")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`bottles_delivered`, `empties_collected`, `deposits_held`, `paid`; section `sec_stop`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); `Cash` / `Account` / `Unpaid` become `cash` / `account` / `unpaid`. **No `signature` field** — the phone keeps a Submit button, and submitting is not a legal attestation. **No `photo` field** — reads bill `form_basic` $0.05, never `form_media`. Attaching is `form_assign(form_id, event_id=...)`.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-stop-{stop_id}`
- event: `event-stop-{stop_id}-{YYYYMMDD window start}`
- shift: `shift-stop-{stop_id}-{YYYYMMDD}` (a same-day extra visit or a driver-swap replacement appends `-2`, then `-3`, … — never reuse a suffix, or the 24-hour replay returns the cancelled shift)
- worker: `worker-{email}`
- form: `form-stop-record`; assignment: `assign-stop-record-{event_id}`
- cancel: `cancel-shift-{shift_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T07:00:00-06:00`), never `Z`. The view builds these strings so the agent does not have to. MX (except some northern-border municipios), Gulf, India, and Nigeria have **no DST** — do not flip `-06:00` to `-05:00` in "summer."

**Metered reads (USD).** `form_submissions` and `form_export` bill $0.05 per submission read (this form has no media); each submission bills once ever, replays free. `form_export` is preferred for a week at a time. The kit stores the counts on `visits` on first read so later deposit-book questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 49 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 7 tables, 6 views, and 8 triggers present; every view on an empty database; the `advance_service_date_on_visit` trigger for daily (+1), weekly (+7), biweekly (+14), monthly (+1 month), and on-demand (NULL); `fill_visit_driver` from `zensched_worker_id`; `apply_deposit_held`; `mark_cash_invoiced`; `UNIQUE` on `zensched_shift_id`; every `CHECK` (frequency, `preferred_start`, `paid`); `stops_due` `start_iso` / `end_iso` / `idempotency_key` / worker / minutes; `event_needs_roll` flipping exactly when `event_valid_until < next_service_date`; inactive and +20-day rows excluded; `events_expiring`; `deposit_book` omitting zero-deposit stops; `visits_to_invoice` only Account; `unpaid_stops`; invoice numbering (auto `INV-2026-0001`, explicit number kept); cascade delete and driver set-null; `updated_at`; integer types on ZenSched ID columns. Form payload validated against `_validate_fields` (5 fields, no signature, no photo, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters). 92 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
