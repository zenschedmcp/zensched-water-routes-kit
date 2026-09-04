# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified route proof plus a local extract of the Stop Record (fulls, empties, deposits, paid). It is **not** a tax invoice, **not** a bottle-deposit contract, and **not** a NOM-201 / COFEPRIS / FSSAI / NAFDAC / ESMA plant or licence log. ZenSched meters are **USD**.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\water-ops` (Windows) or `/Users/yourname/water-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\water-ops\\water-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Agua Clara del Valle". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my water-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Agua Clara del Valle in Guadalajara, Central time Mexico. Save that to settings and create the Stop Record form.

The AI saves your settings (`-06:00` year-round — Mexico abolished DST in 2022 except a few northern-border towns) and calls `form_create` once (free) to build the Stop Record your drivers fill in: bottles delivered, empties collected, deposits held, paid (Cash / Account / Unpaid). No signature. No photos. It stores the form id so every stop gets it. Meters it quotes later are USD.

## 6. Add your first two customers

> Add Carmen Ruiz, carmen@example.com, 33-5555-0144, Av. México 1234, Col. Americana, Guadalajara, Jalisco 44160. Weekly 20 L at $25/bottle starting Monday 2026-09-07 at 8. Knock twice, dog in the patio. Label the stop Casa.

> Add a daily account for Taquería El Sol, sol@example.com, 33-5555-0190, Calle López Cotilla 890, Guadalajara, Jalisco 44100, starting Tuesday 2026-09-08 at 7, $22/bottle, invoice weekly. Loading dock behind. Label the stop Tienda.

Behind the scenes the AI inserts each customer and stop, calls `location_create` with a **stop-code + street** label (never the customer name; geocode $0.03 USD, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` for the stop, attaches the Stop Record with `form_assign`, and saves the IDs. Gate / dock notes and customer names go only into the local database. You just see a confirmation.

## 7. Invite your driver

> Invite Diego Morales at diego@example.com as a driver and make him my default.

Diego gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give him the knock-twice note and the dock note yourself; the AI will not put them in ZenSched.

## 8. Schedule the week

> Schedule this week for Diego.

The AI reads `stops_due`, creates one shift per stop on ZenSched, and summarizes by day. Diego gets a push notification for each, with the Stop Record attached. It will confirm each stop is about $0.25 USD once he punches and you read the record. El Sol is daily — only Tuesday (its next date) is created; say "pre-build El Sol Wed–Sat" if you want the rest of the week now.

## 9. After the work is done

> Record this week's visits, show me the deposit book, then draft invoices for anyone with uninvoiced account work.

The AI pulls the completed, GPS-verified shifts and the Stop Records from ZenSched (reading records is metered, so it tells you the cost first), saves the counts, advances Carmen to next week and El Sol +1 day, shows the deposit book (your copy, not a contract), creates invoice records for Account visits, and writes out each invoice as text you can paste into WhatsApp. Cash visits are already collected and do not appear.

> El Sol paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the tax/deposit boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
