-- 01_setup_and_cleaning.sql
-- Tembo Hotel & Suites: load, audit and clean the raw booking file (PostgreSQL 14+).
-- Before running: change the path in the COPY command to where tembo_hotel_dirty.csv sits
-- on the database server (or import the file with the DBeaver Import Data wizard instead).
-- Run the script top to bottom. It drops and rebuilds tembo.staging_bookings and
-- tembo.clean_bookings (and the view that depends on it), so it is safe to run twice.


-- ======================================================================
-- Step 1: Ingest the CSV without losing a row
-- ======================================================================

CREATE SCHEMA IF NOT EXISTS tembo;
SET search_path TO tembo;

DROP TABLE IF EXISTS tembo.staging_bookings;
CREATE TABLE tembo.staging_bookings (
    booking_id          TEXT,
    guest_name          TEXT,
    guest_phone         TEXT,
    guest_city          TEXT,
    guest_nationality   TEXT,
    room_no             TEXT,
    room_type           TEXT,
    room_rate_per_night TEXT,
    check_in_date       TEXT,
    check_out_date      TEXT,
    nights_stayed       TEXT,
    staff_name          TEXT,
    staff_department    TEXT,
    staff_salary        TEXT,
    payment_method      TEXT,
    booking_status      TEXT,
    total_amount        TEXT,
    service_used        TEXT,
    service_price       TEXT,
    guest_rating        TEXT
);

COPY tembo.staging_bookings
FROM '/path/to/tembo_hotel_dirty.csv'
WITH (FORMAT csv, HEADER true);

SELECT COUNT(*) AS rows_loaded
FROM tembo.staging_bookings;

SELECT booking_id, guest_name, guest_phone, guest_city, room_type,
       check_in_date, total_amount
FROM tembo.staging_bookings
LIMIT 8;


-- ======================================================================
-- Step 2: Audit the damage before touching anything
-- ======================================================================

SELECT 'Duplicate booking_id rows' AS problem,
       COUNT(*) - COUNT(DISTINCT booking_id) AS rows_affected
FROM tembo.staging_bookings
UNION ALL SELECT 'Names with stray spaces or odd casing', COUNT(*)
  FROM tembo.staging_bookings WHERE guest_name <> INITCAP(TRIM(guest_name))
UNION ALL SELECT 'Phones with dashes, +254 or padding', COUNT(*)
  FROM tembo.staging_bookings WHERE guest_phone !~ '^0[0-9]{9}$'
UNION ALL SELECT 'Cities blank, misspelt or oddly cased', COUNT(*)
  FROM tembo.staging_bookings
  WHERE guest_city IS NULL OR guest_city !~ '^[A-Z][a-z]+$' OR guest_city = 'Thikax'
UNION ALL SELECT 'Nationality casing', COUNT(*)
  FROM tembo.staging_bookings WHERE guest_nationality <> 'Kenyan'
UNION ALL SELECT 'Room type aliases (Std, DLX, lower case)', COUNT(*)
  FROM tembo.staging_bookings WHERE room_type NOT IN ('Standard','Deluxe','Suite','Penthouse')
UNION ALL SELECT 'Payment method aliases', COUNT(*)
  FROM tembo.staging_bookings WHERE payment_method NOT IN ('Cash','Card','Bank Transfer','M-Pesa')
UNION ALL SELECT 'Booking status casing', COUNT(*)
  FROM tembo.staging_bookings WHERE booking_status NOT IN ('Checked Out','Cancelled','No Show')
UNION ALL SELECT 'Dates not in YYYY-MM-DD', COUNT(*)
  FROM tembo.staging_bookings
  WHERE check_in_date !~ '^\d{4}-\d{2}-\d{2}$' OR check_out_date !~ '^\d{4}-\d{2}-\d{2}$'
UNION ALL SELECT 'Check-out before check-in', COUNT(*)
  FROM tembo.staging_bookings
  WHERE check_in_date ~ '^\d{4}-\d{2}-\d{2}$' AND check_out_date ~ '^\d{4}-\d{2}-\d{2}$'
    AND check_out_date < check_in_date
UNION ALL SELECT 'Nights stayed below 1', COUNT(*)
  FROM tembo.staging_bookings WHERE nights_stayed::INT < 1
UNION ALL SELECT 'Staff salary unreadable', COUNT(*)
  FROM tembo.staging_bookings WHERE staff_salary !~ '^\d+$'
UNION ALL SELECT 'Total amount blank or not a plain number', COUNT(*)
  FROM tembo.staging_bookings WHERE total_amount IS NULL OR total_amount !~ '^\d+$'
UNION ALL SELECT 'Rating padded or outside 1 to 5', COUNT(*)
  FROM tembo.staging_bookings WHERE guest_rating !~ '^[1-5]$';


-- ======================================================================
-- Step 3: Fix the data, one defect at a time
-- ======================================================================


-- ======================================================================
-- 3.1 Duplicate bookings
-- ======================================================================

SELECT booking_id, guest_name, check_in_date, total_amount, COUNT(*) AS copies
FROM tembo.staging_bookings
GROUP BY booking_id, guest_name, check_in_date, total_amount
HAVING COUNT(*) > 1;

DELETE FROM tembo.staging_bookings
WHERE ctid NOT IN (
    SELECT MIN(ctid)
    FROM tembo.staging_bookings
    GROUP BY booking_id
);

SELECT COUNT(*) AS rows_left, COUNT(DISTINCT booking_id) AS unique_ids
FROM tembo.staging_bookings;


-- ======================================================================
-- 3.2 Guest names
-- ======================================================================

SELECT guest_name, LENGTH(guest_name) AS chars, COUNT(*) AS rows_affected
FROM tembo.staging_bookings
WHERE guest_name <> INITCAP(TRIM(guest_name))
GROUP BY guest_name
ORDER BY rows_affected DESC;

UPDATE tembo.staging_bookings
SET guest_name = INITCAP(TRIM(guest_name))
WHERE guest_name <> INITCAP(TRIM(guest_name));

SELECT guest_name, LENGTH(guest_name) AS chars, COUNT(*) AS rows_affected
FROM tembo.staging_bookings
WHERE guest_name <> INITCAP(TRIM(guest_name))
GROUP BY guest_name;


-- ======================================================================
-- 3.3 Phone numbers
-- ======================================================================

SELECT QUOTE_LITERAL(guest_phone) AS phone_as_typed, COUNT(*) AS rows_affected
FROM tembo.staging_bookings
WHERE guest_phone !~ '^0[0-9]{9}$'
GROUP BY guest_phone
ORDER BY rows_affected DESC;

UPDATE tembo.staging_bookings
SET guest_phone = CASE
    WHEN NULLIF(TRIM(guest_phone), '') IS NULL THEN NULL
    WHEN TRIM(guest_phone) LIKE '+254%'
        THEN '0' || SUBSTRING(REGEXP_REPLACE(guest_phone, '[^0-9]', '', 'g') FROM 4)
    ELSE REGEXP_REPLACE(guest_phone, '[^0-9]', '', 'g')
END
WHERE guest_phone !~ '^0[0-9]{9}$';

SELECT COUNT(*) FILTER (WHERE guest_phone IS NULL) AS missing_phones,
       COUNT(*) FILTER (WHERE guest_phone !~ '^0[0-9]{9}$') AS malformed_phones
FROM tembo.staging_bookings;


-- ======================================================================
-- 3.4 Cities
-- ======================================================================

SELECT QUOTE_LITERAL(guest_city) AS city_as_typed, COUNT(*) AS bookings
FROM tembo.staging_bookings
GROUP BY guest_city
ORDER BY bookings DESC;

UPDATE tembo.staging_bookings
SET guest_city = CASE
    WHEN NULLIF(TRIM(guest_city), '') IS NULL THEN 'Unknown'
    WHEN LOWER(TRIM(guest_city)) = 'thikax' THEN 'Thika'
    ELSE INITCAP(TRIM(guest_city))
END
WHERE guest_city IS NULL OR guest_city !~ '^[A-Z][a-z]+$' OR guest_city = 'Thikax';

SELECT guest_city, COUNT(*) AS bookings
FROM tembo.staging_bookings
GROUP BY guest_city
ORDER BY bookings DESC;


-- ======================================================================
-- 3.5 Short vocabularies: room type, payment, status, nationality
-- ======================================================================

UPDATE tembo.staging_bookings
SET room_type = CASE
    WHEN UPPER(TRIM(room_type)) IN ('STANDARD', 'STD') THEN 'Standard'
    WHEN UPPER(TRIM(room_type)) IN ('DELUXE', 'DLX')   THEN 'Deluxe'
    WHEN UPPER(TRIM(room_type)) = 'SUITE'              THEN 'Suite'
    WHEN UPPER(TRIM(room_type)) = 'PENTHOUSE'          THEN 'Penthouse'
    ELSE room_type
END
WHERE room_type NOT IN ('Standard', 'Deluxe', 'Suite', 'Penthouse');

UPDATE tembo.staging_bookings
SET payment_method = 'M-Pesa'
WHERE UPPER(TRIM(payment_method)) IN ('MPESA', 'M PESA')
  AND payment_method <> 'M-Pesa';

UPDATE tembo.staging_bookings
SET booking_status = INITCAP(TRIM(booking_status))
WHERE booking_status <> INITCAP(TRIM(booking_status));

UPDATE tembo.staging_bookings
SET guest_nationality = INITCAP(TRIM(guest_nationality))
WHERE guest_nationality <> INITCAP(TRIM(guest_nationality));

SELECT 'room_type' AS column_name, room_type AS value, COUNT(*) AS bookings
FROM tembo.staging_bookings GROUP BY room_type
UNION ALL
SELECT 'payment_method', payment_method, COUNT(*)
FROM tembo.staging_bookings GROUP BY payment_method
UNION ALL
SELECT 'booking_status', booking_status, COUNT(*)
FROM tembo.staging_bookings GROUP BY booking_status
UNION ALL
SELECT 'guest_nationality', guest_nationality, COUNT(*)
FROM tembo.staging_bookings GROUP BY guest_nationality
ORDER BY column_name, bookings DESC;


-- ======================================================================
-- 3.6 Dates, the hard one
-- ======================================================================

SELECT CASE
           WHEN check_in_date ~ '^\d{4}-\d{2}-\d{2}$' THEN 'YYYY-MM-DD'
           WHEN check_in_date ~ '^\d{2}/\d{2}/\d{4}$' THEN 'NN/NN/YYYY'
           WHEN check_in_date ~ '^\d{2}-\d{2}-\d{2}$' THEN 'NN-NN-YY'
           WHEN check_in_date ~ '^\d{2}-\d{2}-\d{4}$' THEN 'NN-NN-YYYY'
       END AS date_shape,
       COUNT(*) AS bookings,
       MIN(check_in_date) AS example
FROM tembo.staging_bookings
GROUP BY 1
ORDER BY bookings DESC;

CREATE OR REPLACE FUNCTION tembo.fix_date(d TEXT) RETURNS DATE AS $$
    SELECT CASE
        WHEN d ~ '^\d{4}-\d{2}-\d{2}$' THEN d::DATE
        WHEN d ~ '^\d{2}/\d{2}/\d{4}$' THEN TO_DATE(d, 'DD/MM/YYYY')
        WHEN d ~ '^\d{2}-\d{2}-\d{2}$' THEN TO_DATE(d, 'DD-MM-YY')
        WHEN d ~ '^\d{2}-\d{2}-\d{4}$' AND SPLIT_PART(d, '-', 1)::INT > 12
            THEN TO_DATE(d, 'DD-MM-YYYY')
        WHEN d ~ '^\d{2}-\d{2}-\d{4}$' THEN TO_DATE(d, 'MM-DD-YYYY')
    END
$$ LANGUAGE sql IMMUTABLE;

SELECT booking_id,
       check_in_date  AS raw_in,
       check_out_date AS raw_out,
       tembo.fix_date(check_in_date)  AS parsed_in,
       tembo.fix_date(check_out_date) AS parsed_out,
       nights_stayed
FROM tembo.staging_bookings
WHERE booking_id IN ('BK0003', 'BK0006', 'BK0007', 'BK0020', 'BK9005')
ORDER BY booking_id;

UPDATE tembo.staging_bookings
SET check_in_date  = tembo.fix_date(check_in_date)::TEXT,
    check_out_date = tembo.fix_date(check_out_date)::TEXT
WHERE check_in_date  !~ '^\d{4}-\d{2}-\d{2}$'
   OR check_out_date !~ '^\d{4}-\d{2}-\d{2}$';

UPDATE tembo.staging_bookings
SET check_in_date  = check_out_date,
    check_out_date = check_in_date
WHERE check_out_date::DATE < check_in_date::DATE;

UPDATE tembo.staging_bookings
SET nights_stayed = (check_out_date::DATE - check_in_date::DATE)::TEXT
WHERE nights_stayed::INT <> (check_out_date::DATE - check_in_date::DATE);

SELECT COUNT(*) AS bookings,
       COUNT(*) FILTER (
           WHERE check_out_date::DATE - check_in_date::DATE = nights_stayed::INT
       ) AS dates_agree_with_nights,
       MIN(check_in_date) AS first_check_in,
       MAX(check_in_date) AS last_check_in
FROM tembo.staging_bookings;


-- ======================================================================
-- 3.7 Staff salary
-- ======================================================================

SELECT staff_name, staff_salary, COUNT(*) AS rows_affected
FROM tembo.staging_bookings
GROUP BY staff_name, staff_salary
ORDER BY staff_name, staff_salary;

UPDATE tembo.staging_bookings
SET staff_salary = NULL
WHERE staff_salary !~ '^\d+$';

UPDATE tembo.staging_bookings s
SET staff_salary = k.salary
FROM (
    SELECT staff_name, MAX(staff_salary) AS salary
    FROM tembo.staging_bookings
    WHERE staff_salary IS NOT NULL
    GROUP BY staff_name
) k
WHERE s.staff_name = k.staff_name
  AND s.staff_salary IS NULL;

SELECT staff_name, staff_department, staff_salary, COUNT(*) AS bookings
FROM tembo.staging_bookings
GROUP BY staff_name, staff_department, staff_salary
ORDER BY staff_name;


-- ======================================================================
-- 3.8 Money: totals and service prices
-- ======================================================================

SELECT booking_id, room_rate_per_night AS rate, nights_stayed AS nights,
       service_price, QUOTE_LITERAL(total_amount) AS total_as_typed
FROM tembo.staging_bookings
WHERE total_amount !~ '^\d+$'
ORDER BY booking_id
LIMIT 8;

UPDATE tembo.staging_bookings
SET service_used  = NULLIF(TRIM(service_used), ''),
    service_price = NULLIF(TRIM(service_price), '')
WHERE service_used = '' OR service_price = '';

UPDATE tembo.staging_bookings
SET total_amount = NULLIF(REGEXP_REPLACE(total_amount, '[^0-9]', '', 'g'), '')
WHERE total_amount !~ '^\d+$';

UPDATE tembo.staging_bookings
SET total_amount = (room_rate_per_night::INT * nights_stayed::INT
                    + COALESCE(service_price::INT, 0))::TEXT
WHERE total_amount IS NULL;

SELECT COUNT(*) AS bookings,
       COUNT(*) FILTER (
           WHERE total_amount::INT = room_rate_per_night::INT * nights_stayed::INT
                                     + COALESCE(service_price::INT, 0)
       ) AS totals_that_add_up
FROM tembo.staging_bookings;

SELECT booking_id, service_used, service_price, total_amount,
       room_rate_per_night::INT * nights_stayed::INT
           + COALESCE(service_price::INT, 0) AS rule_says
FROM tembo.staging_bookings
WHERE total_amount::INT <> room_rate_per_night::INT * nights_stayed::INT
                           + COALESCE(service_price::INT, 0);


-- ======================================================================
-- 3.9 Ratings
-- ======================================================================

SELECT QUOTE_LITERAL(guest_rating) AS rating_as_typed, COUNT(*) AS bookings
FROM tembo.staging_bookings
GROUP BY guest_rating
ORDER BY guest_rating;

UPDATE tembo.staging_bookings
SET guest_rating = NULLIF(TRIM(guest_rating), '')
WHERE guest_rating <> TRIM(guest_rating) OR guest_rating = '';

UPDATE tembo.staging_bookings
SET guest_rating = NULL
WHERE guest_rating::INT NOT BETWEEN 1 AND 5;

SELECT guest_rating, COUNT(*) AS bookings
FROM tembo.staging_bookings
GROUP BY guest_rating
ORDER BY guest_rating;


-- ======================================================================
-- Step 4: Move the clean rows into a table that says no
-- ======================================================================

DROP TABLE IF EXISTS tembo.clean_bookings CASCADE;

CREATE TABLE tembo.clean_bookings (
    booking_id          VARCHAR(10) PRIMARY KEY,
    guest_name          VARCHAR(100),
    guest_phone         VARCHAR(10),
    guest_city          VARCHAR(60),
    guest_nationality   VARCHAR(30),
    room_no             VARCHAR(5),
    room_type           VARCHAR(20),
    room_rate_per_night NUMERIC(10,2),
    check_in_date       DATE,
    check_out_date      DATE,
    nights_stayed       INTEGER CHECK (nights_stayed > 0),
    staff_name          VARCHAR(100),
    staff_department    VARCHAR(30),
    staff_salary        NUMERIC(10,2),
    payment_method      VARCHAR(20),
    booking_status      VARCHAR(20),
    total_amount        NUMERIC(10,2),
    service_used        VARCHAR(50),
    service_price       NUMERIC(10,2),
    guest_rating        INTEGER CHECK (guest_rating BETWEEN 1 AND 5),
    CHECK (check_out_date > check_in_date)
);

INSERT INTO tembo.clean_bookings
SELECT booking_id, guest_name, guest_phone, guest_city, guest_nationality,
       room_no, room_type, room_rate_per_night::NUMERIC,
       check_in_date::DATE, check_out_date::DATE, nights_stayed::INT,
       staff_name, staff_department, staff_salary::NUMERIC,
       payment_method, booking_status, total_amount::NUMERIC,
       service_used, service_price::NUMERIC, guest_rating::INT
FROM tembo.staging_bookings;

-- Expected to FAIL: shows the CHECK constraint rejecting a rating of 6.
-- Uncomment to run it.
-- INSERT INTO tembo.clean_bookings
--     (booking_id, guest_name, room_type, check_in_date, check_out_date, nights_stayed, guest_rating)
-- VALUES
--     ('BK9999', 'Test Guest', 'Suite', '2025-01-10', '2025-01-12', 2, 6);

CREATE OR REPLACE VIEW tembo.v_clean_bookings AS
SELECT b.*,
       DATE_TRUNC('month', check_in_date)::DATE AS stay_month
FROM tembo.clean_bookings b;

SELECT COUNT(*) AS bookings,
       MIN(check_in_date) AS first_check_in,
       MAX(check_in_date) AS last_check_in,
       COUNT(DISTINCT room_no) AS rooms,
       COUNT(*) FILTER (WHERE guest_rating IS NULL) AS unrated
FROM tembo.v_clean_bookings;
