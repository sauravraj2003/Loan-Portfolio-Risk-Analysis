-- =============================================================================
-- FILE       : 05_time_series.sql
-- PROJECT    : Loan Portfolio Risk Analysis
-- DESCRIPTION: Temporal trend analysis — tracks how portfolio volume, quality,
--              and risk evolve month-over-month.
--              Answers: "Is the book growing? Are conditions improving or worsening?"
--              Uses LAG() for period-over-period comparisons.
-- =============================================================================

USE loan_portfolio_db;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A │ MONTHLY ORIGINATION TRENDS
-- ─────────────────────────────────────────────────────────────────────────────

-- A1. Monthly loan volume, funded amount, and average interest rate
WITH monthly_stats AS (
    SELECT
        DATE_FORMAT(issue_date, '%Y-%m')                  AS month,
        COUNT(*)                                          AS applications,
        ROUND(SUM(loan_amount)   / 1e6, 3)                AS funded_usd_m,
        ROUND(SUM(total_payment) / 1e6, 3)                AS received_usd_m,
        ROUND(AVG(int_rate) * 100, 2)                     AS avg_int_rate_pct,
        ROUND(AVG(dti)      * 100, 2)                     AS avg_dti_pct,
        ROUND(AVG(loan_amount),    2)                     AS avg_loan_size_usd
    FROM financial_loan
    GROUP BY month
)
SELECT
    month,
    applications,
    funded_usd_m,
    received_usd_m,
    avg_int_rate_pct,
    avg_dti_pct,
    avg_loan_size_usd,
    -- Month-over-Month change in applications
    LAG(applications)  OVER (ORDER BY month)              AS prev_month_apps,
    applications - LAG(applications) OVER (ORDER BY month)
                                                          AS mom_app_change,
    ROUND((applications - LAG(applications) OVER (ORDER BY month))
          * 100.0 / NULLIF(LAG(applications) OVER (ORDER BY month), 0), 2)
                                                          AS mom_app_growth_pct,
    -- Month-over-Month change in funded amount
    LAG(funded_usd_m)  OVER (ORDER BY month)              AS prev_month_funded_m,
    ROUND(funded_usd_m - LAG(funded_usd_m) OVER (ORDER BY month), 3)
                                                          AS mom_funded_change_m,
    ROUND((funded_usd_m - LAG(funded_usd_m) OVER (ORDER BY month))
          * 100.0 / NULLIF(LAG(funded_usd_m) OVER (ORDER BY month), 0), 2)
                                                          AS mom_funded_growth_pct
FROM monthly_stats
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B │ MONTHLY DEFAULT RATE TREND
-- ─────────────────────────────────────────────────────────────────────────────

-- B1. Is the portfolio's credit quality improving or deteriorating over time?
WITH monthly_risk AS (
    SELECT
        DATE_FORMAT(issue_date, '%Y-%m')                  AS month,
        COUNT(*)                                          AS total_loans,
        SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
                                                          AS defaults,
        ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
              * 100.0 / COUNT(*), 2)                      AS default_rate_pct,
        ROUND(SUM(CASE WHEN loan_status = 'Charged Off'
                       THEN (loan_amount - total_payment) ELSE 0 END) / 1e6, 3)
                                                          AS net_loss_usd_m
    FROM financial_loan
    GROUP BY month
)
SELECT
    month,
    total_loans,
    defaults,
    default_rate_pct,
    net_loss_usd_m,
    -- Compare default rate to previous month
    LAG(default_rate_pct) OVER (ORDER BY month)           AS prev_month_default_rate,
    ROUND(default_rate_pct
          - LAG(default_rate_pct) OVER (ORDER BY month), 2)
                                                          AS mom_default_rate_change_pp,
    -- Cumulative defaults over time
    SUM(defaults)    OVER (ORDER BY month)                AS cumulative_defaults,
    ROUND(SUM(net_loss_usd_m) OVER (ORDER BY month), 3)   AS cumulative_loss_usd_m
FROM monthly_risk
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C │ QUARTERLY COHORT PERFORMANCE
-- ─────────────────────────────────────────────────────────────────────────────
-- Loan cohorts group loans by the quarter they were issued.
-- Comparing cohorts shows whether underwriting quality changed over time.

-- C1. Quarterly origination cohorts
SELECT
    CONCAT(YEAR(issue_date), '-Q',
           QUARTER(issue_date))                           AS issue_cohort,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount)   / 1e6, 2)                    AS funded_usd_m,
    ROUND(AVG(int_rate) * 100, 2)                         AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100, 2)                         AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off'
                   THEN (loan_amount - total_payment) ELSE 0 END) / 1e6, 3)
                                                          AS net_loss_usd_m,
    -- Grade mix of each cohort (A+B % = prime borrower concentration)
    ROUND(SUM(CASE WHEN grade IN ('A','B') THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS prime_grade_pct
FROM financial_loan
GROUP BY issue_cohort
ORDER BY issue_cohort;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION D │ RUNNING TOTALS & CUMULATIVE EXPOSURE
-- ─────────────────────────────────────────────────────────────────────────────

-- D1. Cumulative funded amount — tracks portfolio book build over time
SELECT
    DATE_FORMAT(issue_date, '%Y-%m')                      AS month,
    ROUND(SUM(loan_amount) / 1e6, 2)                      AS monthly_funded_usd_m,
    ROUND(SUM(SUM(loan_amount)) OVER (ORDER BY
        DATE_FORMAT(issue_date, '%Y-%m')) / 1e6, 2)       AS cumulative_funded_usd_m,
    ROUND(SUM(SUM(total_payment)) OVER (ORDER BY
        DATE_FORMAT(issue_date, '%Y-%m')) / 1e6, 2)       AS cumulative_received_usd_m
FROM financial_loan
GROUP BY month
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION E │ GRADE MIX SHIFT OVER TIME
-- ─────────────────────────────────────────────────────────────────────────────
-- E1. Is the portfolio drifting towards riskier grades?
--     A shift from A/B towards D/E/F/G signals deteriorating credit standards.
SELECT
    DATE_FORMAT(issue_date, '%Y-%m')                      AS month,
    grade,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER (PARTITION BY DATE_FORMAT(issue_date, '%Y-%m')), 2)
                                                          AS pct_of_month_volume
FROM financial_loan
GROUP BY month, grade
ORDER BY month, grade;
