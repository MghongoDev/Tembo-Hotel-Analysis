-- 02_business_analysis.sql
-- Tembo Hotel & Suites: the six groups of business questions from the project brief.
-- Requires tembo.v_clean_bookings, created at the end of 01_setup_and_cleaning.sql.
-- "Revenue" means bookings with status 'Checked Out'. Each stay counts in its check-in month.


-- ======================================================================
-- Step 5: Answer the Director's questions
-- ======================================================================


-- ======================================================================
-- Q1. Where does the money come from?
-- ======================================================================

SELECT TO_CHAR(stay_month, 'YYYY-MM') AS month,
       COUNT(*)          AS stays,
       SUM(total_amount) AS revenue
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY stay_month
ORDER BY stay_month;

SELECT room_type,
       COUNT(*)          AS stays,
       SUM(total_amount) AS revenue,
       ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS revenue_share_pct
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY room_type
ORDER BY revenue DESC;

SELECT payment_method,
       COUNT(*)          AS stays,
       SUM(total_amount) AS revenue,
       ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS revenue_share_pct
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY payment_method
ORDER BY revenue DESC;


-- ======================================================================
-- Q2. Which rooms are booked most, and for how long?
-- ======================================================================

SELECT room_type,
       COUNT(*)                    AS stays,
       SUM(nights_stayed)          AS room_nights,
       ROUND(AVG(nights_stayed), 2) AS avg_nights
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY room_type
ORDER BY stays DESC;


-- ======================================================================
-- Q3. Who are our guests, and are they happy?
-- ======================================================================

SELECT guest_city,
       COUNT(*)          AS stays,
       SUM(total_amount) AS revenue
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY guest_city
ORDER BY stays DESC, revenue DESC
LIMIT 10;

SELECT room_type,
       ROUND(AVG(guest_rating), 2) AS avg_rating,
       COUNT(guest_rating)         AS ratings_counted
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY room_type
ORDER BY avg_rating DESC;

SELECT guest_rating,
       COUNT(*) AS stays,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
  AND guest_rating IS NOT NULL
GROUP BY guest_rating
ORDER BY guest_rating;


-- ======================================================================
-- Q4. How is the staff performing?
-- ======================================================================

WITH staff_stats AS (
    SELECT staff_name,
           staff_department,
           COUNT(*) AS bookings_handled,
           COUNT(*) FILTER (WHERE booking_status = 'Checked Out') AS completed_stays,
           COUNT(*) FILTER (WHERE booking_status IN ('Cancelled', 'No Show')) AS lost_bookings,
           SUM(total_amount) FILTER (WHERE booking_status = 'Checked Out') AS revenue
    FROM tembo.v_clean_bookings
    GROUP BY staff_name, staff_department
)
SELECT RANK() OVER (ORDER BY bookings_handled DESC) AS rank_by_bookings,
       staff_name,
       staff_department,
       bookings_handled,
       completed_stays,
       lost_bookings,
       revenue
FROM staff_stats
ORDER BY rank_by_bookings, revenue DESC;

SELECT staff_department,
       COUNT(*)          AS stays,
       SUM(total_amount) AS revenue,
       ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS revenue_share_pct
FROM tembo.v_clean_bookings
WHERE booking_status = 'Checked Out'
GROUP BY staff_department
ORDER BY revenue DESC;


-- ======================================================================
-- Q5. What is the trend?
-- ======================================================================

WITH monthly_revenue AS (
    SELECT stay_month,
           COUNT(*)          AS stays,
           SUM(total_amount) AS revenue
    FROM tembo.v_clean_bookings
    WHERE booking_status = 'Checked Out'
    GROUP BY stay_month
),
monthly_growth AS (
    SELECT stay_month, stays, revenue,
           LAG(revenue) OVER (ORDER BY stay_month) AS prev_revenue
    FROM monthly_revenue
)
SELECT TO_CHAR(stay_month, 'YYYY-MM') AS month,
       stays,
       revenue,
       prev_revenue,
       ROUND((revenue - prev_revenue) * 100.0 / prev_revenue, 2) AS growth_pct,
       RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM monthly_growth
ORDER BY stay_month;

(SELECT 'Busiest' AS label,
        TO_CHAR(stay_month, 'YYYY-MM') AS month,
        COUNT(*) AS stays,
        SUM(total_amount) AS revenue
 FROM tembo.v_clean_bookings
 WHERE booking_status = 'Checked Out' AND stay_month >= '2024-01-01'
 GROUP BY stay_month
 ORDER BY revenue DESC
 LIMIT 3)
UNION ALL
(SELECT 'Quietest',
        TO_CHAR(stay_month, 'YYYY-MM'),
        COUNT(*),
        SUM(total_amount)
 FROM tembo.v_clean_bookings
 WHERE booking_status = 'Checked Out' AND stay_month >= '2024-01-01'
 GROUP BY stay_month
 ORDER BY SUM(total_amount)
 LIMIT 3);


-- ======================================================================
-- Q6. What do cancellations cost?
-- ======================================================================

SELECT room_type,
       COUNT(*) AS total_bookings,
       COUNT(*) FILTER (WHERE booking_status IN ('Cancelled', 'No Show')) AS lost_bookings,
       ROUND(100.0 * COUNT(*) FILTER (WHERE booking_status IN ('Cancelled', 'No Show'))
             / COUNT(*), 2) AS cancellation_rate_pct,
       SUM(total_amount) FILTER (WHERE booking_status IN ('Cancelled', 'No Show')) AS lost_revenue
FROM tembo.v_clean_bookings
GROUP BY room_type
ORDER BY cancellation_rate_pct DESC;

SELECT booking_status,
       COUNT(*)          AS bookings,
       SUM(total_amount) AS value,
       ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS share_of_booked_value_pct
FROM tembo.v_clean_bookings
GROUP BY booking_status
ORDER BY value DESC;

SELECT payment_method,
       COUNT(*) AS bookings,
       COUNT(*) FILTER (WHERE booking_status IN ('Cancelled', 'No Show')) AS lost_bookings,
       ROUND(100.0 * COUNT(*) FILTER (WHERE booking_status IN ('Cancelled', 'No Show'))
             / COUNT(*), 1) AS lost_rate_pct,
       COUNT(DISTINCT staff_name) AS staff_handling
FROM tembo.v_clean_bookings
GROUP BY payment_method
ORDER BY lost_rate_pct DESC;
