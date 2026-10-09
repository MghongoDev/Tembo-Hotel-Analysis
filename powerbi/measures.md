# DAX measure reference

Every measure in the Tembo Hotel semantic model, grouped by display folder. Use this page to look up what a measure does, how it is written and where it appears. For the story behind the choices, read the [Power BI article](../article/tembo_powerbi_dashboard_article.md).

## About this reference

- **Source:** `powerbi/project/Tembo_hotel.SemanticModel`, table `tembo_hotel v_clean_bookings`. The table imports the view `tembo_hotel.v_clean_bookings` built by `sql/01_setup_and_cleaning.sql`.
- **Size:** 25 measures in 7 display folders. Each measure carries a one-line description in the model.
- **Layout:** the code is copied from the model and broken into lines for reading. The logic is unchanged. A script checked that each measure is identical to the original once whitespace is ignored.
- **Money rules live in SQL.** `Realised Revenue` and `Lost Revenue` sum the view's `realised_revenue` and `lost_revenue` columns. The `Checked Out` rule behind completed stays and ratings lives in DAX.
- **Number formats:** counts and money use `#,##0`, ratings and average nights use `0.00`, shares and rates use `0.0%`. The "K" on the cards and the payment donut is a visual setting (label display units set to Thousands), not part of the measure.

> **Share pattern.** Every share measure divides a value by the same value with the filter on its own category removed (`REMOVEFILTERS`). `DIVIDE` returns a blank on a zero denominator, where `/` would raise an error.

## Index

| Folder | Measure | Format | On a visual |
| --- | --- | --- | --- |
| 01 Booking Volume | [Total Bookings](#total-bookings) | `#,##0` | Yes |
| 01 Booking Volume | [Completed Stays](#completed-stays) | `#,##0` | Yes |
| 02 Revenue | [Realised Revenue](#realised-revenue) | `#,##0` | Yes |
| 02 Revenue | [Room Type Revenue Share](#room-type-revenue-share) | `0.0%` | No |
| 02 Revenue | [Payment Method Revenue Share](#payment-method-revenue-share) | `0.0%` | No |
| 02 Revenue | [Department Revenue Share](#department-revenue-share) | `0.0%` | Yes |
| 03 Room Demand | [Room Nights](#room-nights) | `#,##0` | Helper |
| 03 Room Demand | [Average Stay Nights](#average-stay-nights) | `0.00` | Yes |
| 04 Guest Satisfaction | [Rated Stays](#rated-stays) | `#,##0` | Helper |
| 04 Guest Satisfaction | [Average Guest Rating](#average-guest-rating) | `0.00` | Yes |
| 04 Guest Satisfaction | [Rating Distribution Share](#rating-distribution-share) | `0.0%;-0.0%;0.0%` | Yes |
| 04 Guest Satisfaction | [Low Rating Share](#low-rating-share) | `0.0%;-0.0%;0.0%` | No |
| 04 Guest Satisfaction | [Guest City Stay Rank](#guest-city-stay-rank) | `0` | No |
| 05 Staff Performance | [Bookings Handled](#bookings-handled) | `#,##0` | Yes |
| 05 Staff Performance | [Staff Booking Rank](#staff-booking-rank) | `0` | Yes |
| 05 Staff Performance | [Staff Handling Count](#staff-handling-count) | `#,##0` | Yes |
| 06 Booking Losses | [Lost Bookings](#lost-bookings) | `#,##0` | Yes |
| 06 Booking Losses | [Lost Booking Rate](#lost-booking-rate) | `0.0%` | Yes |
| 06 Booking Losses | [Lost Revenue](#lost-revenue) | `#,##0` | Yes |
| 06 Booking Losses | [Booked Value](#booked-value) | `#,##0` | Helper |
| 06 Booking Losses | [Lost Value Share](#lost-value-share) | `0.0%` | No |
| 06 Booking Losses | [Booking Status Value Share](#booking-status-value-share) | `0.0%` | Yes |
| 07 Monthly Trend | [Previous Month Revenue](#previous-month-revenue) | `#,##0` | Helper |
| 07 Monthly Trend | [Revenue Month-over-Month Growth](#revenue-month-over-month-growth) | `0.0%` | No |
| 07 Monthly Trend | [Revenue Month Rank](#revenue-month-rank) | `0` | No |

"Helper" means no visual uses the measure directly, but another measure builds on it. "No" means the measure is finished and waiting for a visual.

## 01 Booking Volume

### Total Bookings

All bookings in the current filter context.

```dax
Total Bookings =
COUNTROWS('tembo_hotel v_clean_bookings')
```

- **Format:** `#,##0`
- **Used on:** Executive Overview: Card
- **Used by measures:** `Completed Stays`, `Bookings Handled`, `Lost Bookings`, `Lost Booking Rate`

### Completed Stays

Checked-out bookings; the project definition of completed stays.

```dax
Completed Stays =
CALCULATE(
    [Total Bookings],
    'tembo_hotel v_clean_bookings'[booking_status] = "Checked Out"
)
```

- **Format:** `#,##0`
- **Used on:** Executive Overview: Completed Stays; Rooms & Guests: Completed Stays by Guest City; Rooms & Guests: Completed Stays by Room Type; Staff & Risk: Staff Performance
- **Used by measures:** `Average Stay Nights`, `Guest City Stay Rank`

## 02 Revenue

### Realised Revenue

Collected revenue from checked-out bookings only, in KES.

```dax
Realised Revenue =
SUM('tembo_hotel v_clean_bookings'[realised_revenue])
```

- **Format:** `#,##0`
- **Used on:** Executive Overview: Monthly Realised Revenue (KES); Executive Overview: Realised Revenue (KES); Executive Overview: Revenue by Payment Method (KES); Executive Overview: Revenue by Room Type (KES); Staff & Risk: Realised Revenue by Department (KES); Staff & Risk: Staff Performance
- **Used by measures:** `Room Type Revenue Share`, `Payment Method Revenue Share`, `Department Revenue Share`, `Previous Month Revenue`, `Revenue Month-over-Month Growth`, `Revenue Month Rank`

### Room Type Revenue Share

Share of realised revenue within the current filters, across room types.

```dax
Room Type Revenue Share =
DIVIDE(
    [Realised Revenue],
    CALCULATE(
        [Realised Revenue],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[room_type])
    )
)
```

- **Format:** `0.0%`
- **Used on:** no visual yet

### Payment Method Revenue Share

Share of realised revenue within the current filters, across payment methods.

```dax
Payment Method Revenue Share =
DIVIDE(
    [Realised Revenue],
    CALCULATE(
        [Realised Revenue],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[payment_method])
    )
)
```

- **Format:** `0.0%`
- **Used on:** no visual yet

### Department Revenue Share

Share of realised revenue within the current filters, across staff departments.

```dax
Department Revenue Share =
DIVIDE(
    [Realised Revenue],
    CALCULATE(
        [Realised Revenue],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[staff_department])
    )
)
```

- **Format:** `0.0%`
- **Used on:** Executive Overview: Revenue Share by Department

## 03 Room Demand

### Room Nights

Nights from checked-out bookings.

```dax
Room Nights =
CALCULATE(
    SUM('tembo_hotel v_clean_bookings'[nights_stayed]),
    'tembo_hotel v_clean_bookings'[booking_status] = "Checked Out"
)
```

- **Format:** `#,##0`
- **Used by measures:** `Average Stay Nights`

### Average Stay Nights

Average nights per completed stay.

```dax
Average Stay Nights =
DIVIDE([Room Nights], [Completed Stays])
```

- **Format:** `0.00`
- **Used on:** Rooms & Guests: Average Stay Length by Room Type

## 04 Guest Satisfaction

### Rated Stays

Completed stays with a valid guest rating.

```dax
Rated Stays =
CALCULATE(
    COUNT('tembo_hotel v_clean_bookings'[guest_rating]),
    'tembo_hotel v_clean_bookings'[booking_status] = "Checked Out"
)
```

- **Format:** `#,##0`
- **Used by measures:** `Rating Distribution Share`, `Low Rating Share`

### Average Guest Rating

Average guest rating for completed stays.

```dax
Average Guest Rating =
CALCULATE(
    AVERAGE('tembo_hotel v_clean_bookings'[guest_rating]),
    'tembo_hotel v_clean_bookings'[booking_status] = "Checked Out"
)
```

- **Format:** `0.00`
- **Used on:** Executive Overview: Average Guest Rating / 5; Rooms & Guests: Average Rating by Room Type

### Rating Distribution Share

Share of rated completed stays for each rating value.

```dax
Rating Distribution Share =
DIVIDE(
    [Rated Stays],
    CALCULATE(
        [Rated Stays],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[guest_rating])
    )
)
```

- **Format:** `0.0%;-0.0%;0.0%`
- **Used on:** Rooms & Guests: Guest Rating Distribution

### Low Rating Share

Share of rated completed stays with a rating of 1 or 2.

```dax
Low Rating Share =
DIVIDE(
    CALCULATE(
        [Rated Stays],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[guest_rating]),
        'tembo_hotel v_clean_bookings'[guest_rating] <= 2
    ),
    CALCULATE(
        [Rated Stays],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[guest_rating])
    )
)
```

- **Format:** `0.0%;-0.0%;0.0%`
- **Used on:** no visual yet

### Guest City Stay Rank

Guest city rank by completed stays; use as a Top 10 visual filter.

```dax
Guest City Stay Rank =
RANKX(
    ALL('tembo_hotel v_clean_bookings'[guest_city]),
    [Completed Stays],
    ,
    DESC,
    DENSE
)
```

- **Format:** `0`
- **Used on:** no visual yet

## 05 Staff Performance

### Bookings Handled

All bookings handled, regardless of final booking status.

```dax
Bookings Handled =
[Total Bookings]
```

- **Format:** `#,##0`
- **Used on:** Staff & Risk: Staff Performance
- **Used by measures:** `Staff Booking Rank`

### Staff Booking Rank

Staff rank by bookings handled, highest count first.

```dax
Staff Booking Rank =
RANKX(
    ALL('tembo_hotel v_clean_bookings'[staff_name]),
    [Bookings Handled],
    ,
    DESC,
    DENSE
)
```

> **Known issue.** `ALL` on `staff_name` clears the name filter but leaves the department filter from the table row, so each person is ranked only inside their own department. Six of eight staff show rank 1, and the total row shows 1. The fix is to clear both columns, `ALL(staff_name, staff_department)`, and to show a rank only where `HASONEVALUE(staff_name)` is true. The [Power BI article](../article/tembo_powerbi_dashboard_article.md#7-what-i-would-do-differently) shows the full measure.

- **Format:** `0`
- **Used on:** Staff & Risk: Staff Performance

### Staff Handling Count

Distinct staff members represented in the current filter context.

```dax
Staff Handling Count =
DISTINCTCOUNT('tembo_hotel v_clean_bookings'[staff_name])
```

- **Format:** `#,##0`
- **Used on:** Staff & Risk: Lost Bookings by Payment Method

## 06 Booking Losses

### Lost Bookings

Cancelled and no-show bookings.

```dax
Lost Bookings =
COALESCE(
    CALCULATE(
        [Total Bookings],
        'tembo_hotel v_clean_bookings'[booking_status] IN {"Cancelled", "No Show"}
    ),
    0
)
```

- **Format:** `#,##0`
- **Used on:** Staff & Risk: Lost Bookings by Payment Method; Staff & Risk: Staff Performance
- **Used by measures:** `Lost Booking Rate`

### Lost Booking Rate

Share of bookings cancelled or marked as no-show.

```dax
Lost Booking Rate =
DIVIDE([Lost Bookings], [Total Bookings], 0)
```

- **Format:** `0.0%`
- **Used on:** Staff & Risk: Cancellation and No-Show Rate by Room Type; Staff & Risk: Lost Bookings by Payment Method

### Lost Revenue

Booked value associated with cancellations and no-shows, in KES; not collected revenue.

```dax
Lost Revenue =
SUM('tembo_hotel v_clean_bookings'[lost_revenue])
```

- **Format:** `#,##0`
- **Used on:** Executive Overview: At-Risk Booking Value (KES); Staff & Risk: Lost Bookings by Payment Method
- **Used by measures:** `Lost Value Share`

### Booked Value

Total stated booking value across statuses, in KES.

```dax
Booked Value =
SUM('tembo_hotel v_clean_bookings'[total_amount])
```

- **Format:** `#,##0`
- **Used by measures:** `Lost Value Share`, `Booking Status Value Share`

### Lost Value Share

Share of booked value represented by cancellation and no-show losses.

```dax
Lost Value Share =
DIVIDE(
    [Lost Revenue],
    CALCULATE(
        [Booked Value],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[booking_status])
    )
)
```

- **Format:** `0.0%`
- **Used on:** no visual yet

### Booking Status Value Share

Share of total stated booking value represented by each booking status.

```dax
Booking Status Value Share =
DIVIDE(
    [Booked Value],
    CALCULATE(
        [Booked Value],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[booking_status])
    )
)
```

- **Format:** `0.0%`
- **Used on:** Executive Overview: Booked Value by Status

## 07 Monthly Trend

### Previous Month Revenue

Realised revenue for the previous check-in month; use month_label or stay_month on the visual axis.

```dax
Previous Month Revenue =
VAR CurrentMonth = MAX('tembo_hotel v_clean_bookings'[stay_month])
RETURN
    CALCULATE(
        [Realised Revenue],
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[stay_month]),
        REMOVEFILTERS('tembo_hotel v_clean_bookings'[month_label]),
        'tembo_hotel v_clean_bookings'[stay_month] = EDATE(CurrentMonth, -1)
    )
```

- **Format:** `#,##0`
- **Used by measures:** `Revenue Month-over-Month Growth`

### Revenue Month-over-Month Growth

Percentage change in realised revenue from the previous check-in month.

```dax
Revenue Month-over-Month Growth =
DIVIDE([Realised Revenue] - [Previous Month Revenue], [Previous Month Revenue])
```

- **Format:** `0.0%`
- **Used on:** no visual yet

### Revenue Month Rank

Check-in month rank by realised revenue, highest first.

```dax
Revenue Month Rank =
RANKX(
    ALL(
        'tembo_hotel v_clean_bookings'[stay_month],
        'tembo_hotel v_clean_bookings'[month_label]
    ),
    [Realised Revenue],
    ,
    DESC,
    DENSE
)
```

- **Format:** `0`
- **Used on:** no visual yet
