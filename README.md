# Tembo Hotel & Suites: Cleaning and Analysing Booking Data in SQL

A hotel keeps its bookings in a spreadsheet, and the spreadsheet is a mess. This project loads that file into PostgreSQL, finds and fixes every defect with plain SQL, and answers the Hotel Director's business questions: which rooms earn the most, which months are busiest, how the staff perform, and whether guests are happy.

The whole pipeline is two SQL scripts you can run top to bottom. A long-form article walks through the same work with the output of every query.

## Contents

- [Key results](#key-results)
- [Project at a glance](#project-at-a-glance)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [The data](#the-data)
- [How the analysis works](#how-the-analysis-works)
- [Decisions and assumptions](#decisions-and-assumptions)
- [Open questions for the hotel](#open-questions-for-the-hotel)
- [Troubleshooting](#troubleshooting)
- [Limits and next steps](#limits-and-next-steps)


## Key results

These figures come from the cleaned data, counting only bookings with status `Checked Out` unless the row says otherwise.

| Question | Answer |
| --- | --- |
| Which room type earns the most? | Suites: 2,659,600 KES, 34.3% of revenue, from 54 stays |
| Which room type is booked most? | Standard: 97 stays, 21.0% of revenue |
| Which payment method leads? | Cash: 29.8% of revenue, with M-Pesa (27.2%) and card (26.4%) close behind |
| Which department earns the most? | Front Desk: 30.4% of revenue |
| Best month in 2024 | April 2024: 704,500 KES |
| How much booked value never arrived? | 1,175,300 KES (about 13.2%) across 32 cancellations and no-shows |
| Which room type loses the most bookings? | Penthouse: about 24% cancelled or no-show |
| Are guests happy? | They split. 39.5% of ratings are a 1 or a 2, and 43.7% are a 4 or a 5 |

The finding that most needs follow-up: all 32 lost bookings were paid by bank transfer, and only two staff members handle bank-transfer bookings. The [article](https://dev.to/david_mwandairo/cleaning-and-analyzing-tembo-hotels-bookings-41o5) explains why the data cannot tell us which of the two facts is the cause.

## Project at a glance

| Item | Detail |
| --- | --- |
| Business | Tembo Hotel & Suites, a mid-range business hotel in Nairobi, open since 2023 |
| Source | `tembo_hotel_dirty.csv`: 286 rows, 20 columns, one row per booking |
| After cleaning | 285 bookings (one exact duplicate removed), 10 rooms, 8 staff, 5 departments |
| Period covered | 10 June 2023 to 31 December 2024 |
| Database | PostgreSQL 14 or newer (built and tested on PostgreSQL 16) |
| Client used | DBeaver (any client that runs PostgreSQL scripts works) |
| Techniques | Staging tables, regular expressions, `CASE`, `NULLIF`, `COALESCE`, `ctid` de-duplication, CTEs, window functions (`LAG`, `RANK`, `SUM() OVER`), `FILTER`, constraints, views |

## Repository layout

```text
tembo-hotel-sql-analysis/
├── README.md
├── data/
│   └── raw/
│       └── tembo_hotel_dirty.csv
├── docs/
│   └── Tembo_Hotel_Project_Brief.docx
├── sql/
    ├── 01_setup_and_cleaning.sql
    └── 02_business_analysis.sql

```

| Path | What it holds | Read it when |
| --- | --- | --- |
| `data/raw/tembo_hotel_dirty.csv` | The untouched export from the hotel. Never edit this file. | You want to see the original mess |
| `docs/Tembo_Hotel_Project_Brief.docx` | The scenario, the Director's message and the six groups of business questions | You want to know what was asked and why |
| `sql/01_setup_and_cleaning.sql` | Creates the `tembo` schema, loads the CSV, audits the damage, fixes it, builds the typed table and the analysis view | You want to rebuild the clean data |
| `sql/02_business_analysis.sql` | One query (or a few) for each business question | You want the answers |

The scripts are numbered because order matters: script 02 reads a view that script 01 creates.

## Quick start

### Before you begin

- PostgreSQL 14 or newer, running, with a database you may create schemas in.
- A SQL client such as DBeaver or `psql`.
- Permission to read the CSV file from the database server (see step 2 for the alternative if you lack it).

### Steps

1. **Get the files.** Clone the repository, or download it as a ZIP and unpack it.

2. **Point the script at the CSV.** Open `sql/01_setup_and_cleaning.sql` and find the `COPY` command:

   ```sql
   COPY tembo.staging_bookings
   FROM '/path/to/tembo_hotel_dirty.csv'
   WITH (FORMAT csv, HEADER true);
   ```

   Replace `/path/to/tembo_hotel_dirty.csv` with the full path to the file **as the database server sees it**. If the server runs on another machine, or you lack the rights to use `COPY`, skip that command and load the file with the DBeaver wizard instead: right-click `tembo.staging_bookings`, choose **Import Data**, pick **CSV**, and map the columns in order.

3. **Run script 01.** Run the whole file. In DBeaver, press `Alt+X` (Execute script). It is safe to run twice, because it drops and rebuilds the staging and clean tables first.

4. **Check the load.** Run this query. You should see 285 bookings:

   ```sql
   SELECT COUNT(*) AS bookings,
          MIN(check_in_date) AS first_check_in,
          MAX(check_in_date) AS last_check_in
   FROM tembo.v_clean_bookings;
   ```

   | bookings | first_check_in | last_check_in |
   | ---: | --- | --- |
   | 285 | 2023-06-10 | 2024-12-31 |

5. **Run script 02.** Run it the same way, or select one question at a time and press `Ctrl+Enter`. Each section is headed `Q1` to `Q6` to match the brief.

> **Tip:** If step 4 shows 286 rows, the duplicate booking was not removed. Re-run script 01 from the top and watch for an error in the log.

## The data

The raw file has 20 columns. Script 01 turns them into the types below in `tembo.clean_bookings`.

| Column | Clean type | Meaning and rules |
| --- | --- | --- |
| `booking_id` | `VARCHAR(10)`, primary key | Unique booking reference, such as `BK0001` |
| `guest_name` | `VARCHAR(100)` | Title case, no stray spaces |
| `guest_phone` | `VARCHAR(10)` | Local form `07xxxxxxxx`. 14 rows are `NULL` (never recorded) |
| `guest_city` | `VARCHAR(60)` | Nine Kenyan cities, plus `Unknown` for 14 blanks |
| `guest_nationality` | `VARCHAR(30)` | `Kenyan` for every row |
| `room_no` | `VARCHAR(5)` | Ten rooms: 101 to 104, 201 to 203, 301, 302 and 401 |
| `room_type` | `VARCHAR(20)` | `Standard`, `Deluxe`, `Suite` or `Penthouse` |
| `room_rate_per_night` | `NUMERIC(10,2)` | Fixed per type: 5,500 / 8,500 / 15,000 / 25,000 KES |
| `check_in_date` | `DATE` | Always earlier than `check_out_date` |
| `check_out_date` | `DATE` | See above |
| `nights_stayed` | `INTEGER`, must be above 0 | Equals `check_out_date - check_in_date` in every row |
| `staff_name` | `VARCHAR(100)` | The staff member who handled the booking (8 people) |
| `staff_department` | `VARCHAR(30)` | Front Desk, Housekeeping, Management, Restaurant or Security |
| `staff_salary` | `NUMERIC(10,2)` | One salary per person |
| `payment_method` | `VARCHAR(20)` | `Cash`, `Card`, `M-Pesa` or `Bank Transfer` |
| `booking_status` | `VARCHAR(20)` | `Checked Out`, `Cancelled` or `No Show` |
| `total_amount` | `NUMERIC(10,2)` | Room rate x nights + service price (283 of 285 rows follow this rule) |
| `service_used` | `VARCHAR(50)` | One of seven extras, or `NULL` when none was bought (97 rows have one) |
| `service_price` | `NUMERIC(10,2)` | Price of the extra, or `NULL` |
| `guest_rating` | `INTEGER`, 1 to 5 | `NULL` when missing or outside the scale (15 rows) |

> **Privacy check before you push.** The file holds guest names and phone numbers. The brief supplies it as practice data. If any of it came from real guests, keep `data/raw/` out of a public repository (add it to `.gitignore`) and publish the scripts alone.

## How the analysis works

The work follows a front-desk routine: register the guest first, hand over the key second. Data goes into a permissive holding table, gets checked and fixed, and only then moves into a strict table.

```text
tembo_hotel_dirty.csv
        |
        v
tembo.staging_bookings      every column is TEXT, so the load never fails
        |   audit, then fix with UPDATE and DELETE
        v
tembo.clean_bookings        real types and CHECK constraints
        |
        v
tembo.v_clean_bookings      adds a stay_month column for grouping
        |
        v
six groups of business questions (script 02)
```

### Stage 1: Ingest

The staging table has 20 `TEXT` columns. A strict table would reject the first `KES 34000` it met in a numeric column, and the load would stop. With text, every row arrives and the cleaning happens where you can watch it.

### Stage 2: Audit

One query counts each kind of damage before anything changes. The counts below are from the raw 286 rows.

| Defect | Rows affected |
| --- | ---: |
| Duplicate `booking_id` | 1 |
| Names with stray spaces or odd casing | 45 |
| Phones with dashes, `+254` prefix or padding | 29 |
| Cities blank, misspelt or oddly cased | 45 |
| Nationality casing | 1 |
| Room type aliases (`Std`, `DLX`, lower case) | 29 |
| Payment method aliases | 15 |
| Booking status casing | 15 |
| Dates not in `YYYY-MM-DD` | 44 |
| Check-out before check-in | 2 |
| Nights stayed below 1 | 1 |
| Staff salary unreadable | 14 |
| Total amount blank or not a plain number | 30 |
| Rating padded or outside 1 to 5 | 17 |

After the fixes, the same audit returns zero for every line.

### Stage 3: Clean

Each fix follows one rhythm: look at the problem, write the `UPDATE`, run a check that proves it worked. Every `UPDATE` has a `WHERE` clause, so the "Updated Rows" count in the client shows how many rows really changed.

| Defect | Rule applied | SQL technique |
| --- | --- | --- |
| Duplicate booking | Keep the first physical row for each `booking_id` | `DELETE ... WHERE ctid NOT IN (SELECT MIN(ctid) ...)` |
| Names | Trim, then capitalise each word | `INITCAP(TRIM(...))` |
| Phones | Keep digits only, turn a leading `254` into `0`, blank becomes `NULL` | `REGEXP_REPLACE`, `SUBSTRING`, `CASE` |
| Cities | Fix casing, map `Thikax` to `Thika`, blank becomes `Unknown` | `INITCAP`, `CASE` |
| Room type, payment, status, nationality | Map every known variant to one spelling | `CASE`, `UPPER(TRIM(...))` |
| Dates | Four formats parsed by shape, with a check against `nights_stayed` | Custom function `tembo.fix_date`, `TO_DATE` |
| Swapped dates | If check-out is before check-in, swap the two | One `UPDATE` (right-hand sides read the old row) |
| Nights below 1 | Recompute from the dates | Date subtraction |
| Salary | Blank the junk, then copy the person's known salary from their other rows | Self-join `UPDATE ... FROM` |
| Totals | Strip `KES` and commas, then rebuild blanks as rate x nights + service | `REGEXP_REPLACE`, `COALESCE` |
| Ratings | Trim padding, set anything outside 1 to 5 to `NULL` | `NULLIF`, `BETWEEN` |

The date step deserves a closer look, since a wrong guess there is invisible. The raw file mixes `YYYY-MM-DD`, `DD/MM/YYYY`, `DD-MM-YY` and `MM-DD-YYYY`. The function reads each by its shape, and the `nights_stayed` column acts as a witness: after parsing, the gap between check-in and check-out must equal the recorded nights. All 285 rows pass.

### Stage 4: Constrain

`tembo.clean_bookings` uses proper types plus `CHECK` constraints (nights above 0, rating between 1 and 5, check-out after check-in) and a primary key on `booking_id`. All 285 rows load without complaint, which is the real test of the cleaning. The script also shows an insert with a rating of 6 being refused. That statement is commented out, because it fails by design.

The view `tembo.v_clean_bookings` adds `stay_month` (the first day of the check-in month) so every monthly query groups the same way.

### Stage 5: Analyse

`sql/02_business_analysis.sql` answers the brief one section at a time.

| Section | Brief question | Main technique |
| --- | --- | --- |
| Q1 | Revenue by month, room type and payment method | `GROUP BY`, `SUM(SUM(...)) OVER ()` for shares |
| Q2 | Rooms booked most, average nights per room type | `COUNT`, `AVG` |
| Q3 | Top 10 guest cities, average rating per room type, rating spread | `ORDER BY ... LIMIT`, `COUNT(guest_rating)` |
| Q4 | Staff with the most bookings, revenue by department | CTE, `RANK()`, `COUNT(*) FILTER (WHERE ...)` |
| Q5 | Month-over-month growth, busiest and quietest months | Two CTEs, `LAG()`, `RANK()`, `UNION ALL` |
| Q6 | Cancellation rate per room type, revenue lost, loss by payment method | `FILTER`, window share |

## Decisions and assumptions

Every cleaning rule that involves a judgement is listed here, so a reader can overrule it.

1. **Revenue means `Checked Out` bookings only.** `Cancelled` and `No Show` rows carry a `total_amount`, but the hotel never collected it. Question Q6 is the one place those rows count.
2. **A stay belongs to its check-in month.** A stay that crosses a month end is not split.
3. **`Thikax` is a typo for `Thika`.** It appears about as often as the other small towns, and no place has that name.
4. **`NN/NN/YYYY` dates are day first.** `NN-NN-YYYY` dates are month first, unless the first number is above 12. `NN-NN-YY` dates are day first. The `nights_stayed` check confirms these readings for all 285 rows.
5. **Two swapped dates are swapped back.** In both, the gap between the dates matches the recorded nights.
6. **The dates beat `nights_stayed`.** One booking had `-3` nights; the dates say three nights, so the dates won.
7. **Missing values stay missing.** A blank phone or rating is `NULL`. A blank city is `Unknown` so it shows in reports. Ratings of 0 or 6 become `NULL` rather than a guess.
8. **Blank totals are rebuilt from the pricing rule** (rate x nights + service price). Two stored totals omit the service charge and are left as stored.
9. **Ratings on cancelled bookings are ignored** in rating averages, because no one can rate a night they did not spend.
10. **Q5 reads 2024 for busiest and quietest months.** The 2023 data covers seven months with few stays, and growth between such small numbers mostly measures noise.

## Open questions for the hotel

The data raises four questions that SQL cannot answer.

1. Why do only two colleagues handle bank-transfer bookings, and why do all the lost bookings sit there?
2. Why do Security and Housekeeping staff enter bookings at all?
3. Why do blank cities and phone numbers still get past the front desk?
4. What happened to the service charge on the two bookings whose totals leave it out?

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `could not open file ... for reading: No such file or directory` | `COPY` reads from the database server, not your computer | Give the server-side path, or use the DBeaver **Import Data** wizard |
| `must be superuser or have privileges of the pg_read_server_files role` | Your role may not read server files | Ask an administrator, use `\copy` in `psql`, or use the DBeaver wizard |
| `relation "tembo.staging_bookings" does not exist` | Script 01 has not run, or it stopped early | Run script 01 from the top and read the first error |
| `relation "tembo.v_clean_bookings" does not exist` when running script 02 | The view is created at the end of script 01 | Finish script 01 first |
| Row count is 286, not 285 | The de-duplication step did not run | Re-run script 01 |
| Some dates show year `0024` | A two-digit year parsed with a four-digit format | Use `DD-MM-YY` for two-digit years, as `tembo.fix_date` does |
| Empty fields load as empty strings, not `NULL` | Some import tools differ from `COPY` | Script 01 converts blank phones, cities and services already, so no action is needed |
| `MIN(ctid)` fails or misbehaves | Older PostgreSQL versions | Upgrade to 14 or newer, or de-duplicate with `ROW_NUMBER()` in a CTE |

## Limits and next steps

- **No dashboard yet.** The brief asks for Power BI visuals. The view `tembo.v_clean_bookings` is ready to connect, and the queries in script 02 map to one visual each.
- **Small samples.** 285 bookings over 19 months is enough to see patterns, and not enough to prove them. Treat month-to-month swings with care.
- **Questions worth adding.** Which room number is busiest? Do M-Pesa guests rate higher? What do extra services add to revenue per stay?


