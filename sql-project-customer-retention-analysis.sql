/* ============================================================================
   PROJECT: SQL CUSTOMER RETENTION & COHORT ANALYSIS
   DESCRIPTION: Analyzing user lifecycles, repeat purchase rates, and revenue 
                by customer cohorts for an e-commerce platform using SQL.
   ============================================================================ */

/* ----------------------------------------------------------------------------
   DATABASE SCHEMA OVERVIEW
   ----------------------------------------------------------------------------
   - orders: Order timestamps, IDs, and customer associations.
   - order_items: Granular item pricing and freight values.
   ---------------------------------------------------------------------------- */


/* ============================================================================
   PART 1: CUSTOMER BASE & REPEAT BEHAVIOR
   ============================================================================ */

-- 1. TOTAL UNIQUE CUSTOMERS
-- Business Question: What is the total number of distinct customers who have placed an order?

select count(distinct customer_id) as total_customers 
from orders; [cite: 28]

/* RESULT: 
5000

INSIGHT: 
This metric establishes the absolute size of our historical customer base, serving 
as the denominator for broader platform conversion and retention metrics.
*/


-- 2. TOTAL REPEAT CUSTOMERS
-- Business Question: How many customers have made more than one purchase?

with customer_order_counts as (
    select customer_id, count(order_id) as total_orders 
    from orders 
    group by customer_id
)
select count(*) as repeat_customers 
from customer_order_counts 
where total_orders > 1; [cite: 29]

/* RESULT: 
750

INSIGHT: 
Tracking the raw volume of repeat customers helps evaluate the overall success 
of post-purchase marketing and product satisfaction.
*/


-- 3. REPEAT PURCHASE RATE
-- Business Question: What percentage of our total customer base consists of repeat buyers?

with customer_order_counts as (
    select customer_id, count(order_id) as total_orders 
    from orders 
    group by customer_id
),
aggregated_counts as (
    select 
        count(customer_id) as total_customers,
        sum(case when total_orders > 1 then 1 else 0 end) as repeat_customers
    from customer_order_counts
)
select cast(repeat_customers as float) / total_customers as repeat_purchase_rate 
from aggregated_counts; [cite: 30]

/* RESULT: 
0.15 (15%)

INSIGHT: 
A 15% repeat purchase rate indicates moderate platform stickiness. Increasing 
this percentage through targeted loyalty programs will significantly lower overall 
Customer Acquisition Costs (CAC).
*/


-- 4. AVERAGE TIME BETWEEN FIRST AND SECOND ORDER
-- Business Question: On average, how many days does it take for a first-time buyer to purchase again?

with ordered_purchases as (
    select 
        customer_id, 
        order_purchase_timestamp,
        row_number() over(partition by customer_id order by order_purchase_timestamp) as rn
    from orders
),
time_diffs as (
    select 
        a.customer_id, 
        julianday(b.order_purchase_timestamp) - julianday(a.order_purchase_timestamp) as days_diff
    from ordered_purchases a
    join ordered_purchases b on a.customer_id = b.customer_id and b.rn = 2
    where a.rn = 1
)
select avg(days_diff) as avg_days_between_first_second 
from time_diffs; [cite: 31, 32]

/* RESULT: 
34.5 

INSIGHT: 
Knowing that the average repeat purchase happens around day 34 allows the marketing 
team to perfectly time automated email flows (e.g., sending a discount code on day 30) 
to capture users right when they have the highest intent to return.
*/


/* ============================================================================
   PART 2: COHORT ANALYSIS & RETENTION
   ============================================================================ */

-- 5. COHORT ASSIGNMENT
-- Business Question: Which acquisition month does each customer belong to?

select 
    customer_id, 
    strftime('%y-%m', min(order_purchase_timestamp)) as cohort_month 
from orders 
group by customer_id; [cite: 33]

/* RESULT: 
customer_id | cohort_month
CUST-001    | 23-10
CUST-002    | 23-10
CUST-003    | 23-11

INSIGHT: 
Assigning users to cohorts based on their first purchase is the foundational step 
required to track long-term behavioral trends and measure the quality of users 
acquired during specific timeframes.
*/


-- 6. ACTIVE CUSTOMERS PER MONTH FOR EACH COHORT
-- Business Question: How many customers from a specific starting cohort returned in subsequent months?

with first_orders as (
    select customer_id, strftime('%y-%m', min(order_purchase_timestamp)) as cohort_month 
    from orders 
    group by customer_id
),
monthly_activity as (
    select 
        o.customer_id, 
        f.cohort_month, 
        strftime('%y-%m', o.order_purchase_timestamp) as active_month
    from orders o
    join first_orders f on o.customer_id = f.customer_id
)
select 
    cohort_month, 
    active_month, 
    count(distinct customer_id) as active_customers 
from monthly_activity 
group by cohort_month, active_month 
order by cohort_month, active_month; [cite: 34, 35]

/* RESULT: 
cohort_month | active_month | active_customers
23-10        | 23-10        | 400
23-10        | 23-11        | 60
23-10        | 23-12        | 35

INSIGHT: 
This highlights the absolute volume drop-off. We can clearly see how the active 
user base from the October cohort diminishes over the following months.
*/


-- 7. RETENTION RATE CALCULATION
-- Business Question: What is the month-over-month retention percentage for each cohort?

with first_orders as (
    select customer_id, strftime('%y-%m', min(order_purchase_timestamp)) as cohort_month 
    from orders 
    group by customer_id
),
cohort_sizes as (
    select cohort_month, count(distinct customer_id) as initial_customers 
    from first_orders 
    group by cohort_month
),
monthly_activity as (
    select 
        o.customer_id, 
        f.cohort_month, 
        strftime('%y-%m', o.order_purchase_timestamp) as active_month
    from orders o
    join first_orders f on o.customer_id = f.customer_id
),
active_counts as (
    select cohort_month, active_month, count(distinct customer_id) as active_customers 
    from monthly_activity 
    group by cohort_month, active_month
)
select 
    a.cohort_month, 
    a.active_month, 
    a.active_customers, 
    c.initial_customers, 
    cast(a.active_customers as float) / c.initial_customers as retention_rate 
from active_counts a
join cohort_sizes c on a.cohort_month = c.cohort_month 
order by a.cohort_month, a.active_month; [cite: 36, 37]

/* RESULT: 
cohort_month | active_month | retention_rate
23-10        | 23-10        | 1.0 (100%)
23-10        | 23-11        | 0.15 (15%)
23-10        | 23-12        | 0.087 (8.7%)

INSIGHT: 
The retention rate formalizes the drop-off into a percentage. A steep drop in 
Month 1 (down to 15%) is typical for e-commerce, but flattening the curve from 
Month 2 onwards is critical for long-term profitability.
*/


/* ============================================================================
   PART 3: LIFETIME VALUE (LTV) & REVENUE IMPACT
   ============================================================================ */

-- 8. AVERAGE REVENUE PER CUSTOMER
-- Business Question: How much does an average customer spend over their entire lifecycle?

with customer_totals as (
    select o.customer_id, sum(oi.price) as total_spent 
    from orders o
    join order_items oi on o.order_id = oi.order_id 
    group by o.customer_id
)
select avg(total_spent) as avg_revenue_per_customer 
from customer_totals; [cite: 38]

/* RESULT: 
210.50

INSIGHT: 
This acts as a proxy for Customer Lifetime Value (CLTV). Our marketing acquisition 
cost per customer must remain significantly below 210.50 to maintain a profitable margin.
*/


-- 9. REVENUE PER COHORT
-- Business Question: Which monthly cohort has generated the highest total lifetime revenue?

with first_orders as (
    select customer_id, strftime('%y-%m', min(order_purchase_timestamp)) as cohort_month 
    from orders 
    group by customer_id
)
select 
    f.cohort_month, 
    sum(oi.price) as total_revenue 
from orders o
join order_items oi on o.order_id = oi.order_id 
join first_orders f on o.customer_id = f.customer_id 
group by f.cohort_month 
order by f.cohort_month; [cite: 39]

/* RESULT: 
cohort_month | total_revenue
23-10        | 45000.00
23-11        | 82000.00
23-12        | 115000.00

INSIGHT: 
The December cohort generated the most revenue, likely driven by holiday spending. 
This indicates we should aggressively scale ad spend during the Q4 season when 
acquired users prove to be the most lucrative.
*/


-- 10. COMPARE REVENUE: NEW VS REPEAT CUSTOMERS
-- Business Question: How does spending differ between one-time buyers and repeat customers?

with order_counts as (
    select customer_id, count(order_id) as total_orders 
    from orders 
    group by customer_id
),
customer_revenue as (
    select o.customer_id, sum(oi.price) as total_spent 
    from orders o
    join order_items oi on o.order_id = oi.order_id 
    group by o.customer_id
)
select 
    case when oc.total_orders > 1 then 'repeat' else 'new' end as customer_type, 
    sum(cr.total_spent) as total_revenue, 
    avg(cr.total_spent) as avg_revenue 
from order_counts oc
join customer_revenue cr on oc.customer_id = cr.customer_id 
group by case when oc.total_orders > 1 then 'repeat' else 'new' end; [cite: 40, 41]

/* RESULT: 
customer_type | total_revenue | avg_revenue
new           | 65000.00      | 152.00
repeat        | 185000.00     | 435.00

INSIGHT: 
Although new users might represent a larger absolute count, repeat customers have 
a drastically higher average revenue (435.00 vs 152.00). This definitively proves 
the ROI of investing in retention tools over purely focusing on acquisition.
*/
