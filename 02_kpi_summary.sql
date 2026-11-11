-- =============================================================================
-- FILE       : 02_kpi_summary.sql
-- PROJECT    : Loan Portfolio Risk Analysis
-- DESCRIPTION: Executive-level KPI dashboard queries.
--              Answers the board-level question: "How is our loan book performing?"
--              Covers total portfolio metrics, good vs. bad loan split,
--              and key rate indicators.
-- =============================================================================

USE loan_portfolio_db;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A │ OVERALL PORTFOLIO SNAPSHOT
-- ─────────────────────────────────────────────────────────────────────────────

-- A1. Top-line Portfolio Summary
-- Mirrors the headline KPIs typically shown on an executive dashboard.
SELECT
    COUNT(*)                                            AS total_applications,
    ROUND(SUM(loan_amount)    / 1e6, 2)                 AS total_funded_usd_m,
    ROUND(SUM(total_payment)  / 1e6, 2)                 AS total_received_usd_m,
    ROUND(AVG(int_rate)  * 100, 2)                      AS avg_interest_rate_pct,
    ROUND(AVG(dti)       * 100, 2)                      AS avg_dti_pct,
    ROUND(AVG(loan_amount),    2)                       AS avg_loan_size_usd,
    ROUND(AVG(installment),    2)                       AS avg_monthly_installment_usd
FROM financial_loan;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B │ GOOD LOAN vs. BAD LOAN SPLIT
-- ─────────────────────────────────────────────────────────────────────────────
-- Definition:
--   Good Loan → loan_status IN ('Fully Paid', 'Current')
--   Bad  Loan → loan_status = 'Charged Off'

-- B1. Good Loan KPIs
SELECT
    'Good Loan'                                         AS segment,
    COUNT(*)                                            AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)  AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                  AS funded_usd_m,
    ROUND(SUM(total_payment) / 1e6, 2)                  AS received_usd_m
FROM financial_loan
WHERE loan_status IN ('Fully Paid', 'Current');


-- B2. Bad Loan KPIs
SELECT
    'Bad Loan'                                          AS segment,
    COUNT(*)                                            AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)  AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                  AS funded_usd_m,
    ROUND(SUM(total_payment) / 1e6, 2)                  AS received_usd_m,
    -- Estimated gross loss = money disbursed that was NOT recovered
    ROUND(SUM(loan_amount - total_payment) / 1e6, 2)    AS estimated_gross_loss_usd_m
FROM financial_loan
WHERE loan_status = 'Charged Off';


-- B3. Side-by-Side Comparison (single query, useful for Tableau)
SELECT
    CASE
        WHEN loan_status IN ('Fully Paid', 'Current') THEN 'Good Loan'
        WHEN loan_status = 'Charged Off'              THEN 'Bad Loan'
        ELSE 'Other'
    END                                                 AS loan_category,
    COUNT(*)                                            AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)  AS pct_of_total,
    ROUND(SUM(loan_amount)   / 1e6, 2)                  AS funded_usd_m,
    ROUND(SUM(total_payment) / 1e6, 2)                  AS received_usd_m
FROM financial_loan
GROUP BY loan_category
ORDER BY applications DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C │ LOAN STATUS GRANULAR BREAKDOWN
-- ─────────────────────────────────────────────────────────────────────────────

-- C1. All statuses with full financials
SELECT
    loan_status,
    COUNT(*)                                            AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)  AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                  AS funded_usd_m,
    ROUND(SUM(total_payment) / 1e6, 2)                  AS received_usd_m,
    ROUND(AVG(int_rate) * 100, 2)                       AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100, 2)                       AS avg_dti_pct,
    ROUND(AVG(loan_amount), 2)                          AS avg_loan_size_usd
FROM financial_loan
GROUP BY loan_status
ORDER BY applications DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION D │ PORTFOLIO HEALTH SCORECARD
-- ─────────────────────────────────────────────────────────────────────────────

-- D1. Single-row executive scorecard — copy these numbers into your PDF/slides
WITH loan_totals AS (
    SELECT
        COUNT(*)                                        AS total_apps,
        SUM(loan_amount)                                AS total_funded,
        SUM(total_payment)                              AS total_received,
        SUM(CASE WHEN loan_status = 'Charged Off'
                 THEN 1 ELSE 0 END)                     AS bad_loan_count,
        SUM(CASE WHEN loan_status = 'Charged Off'
                 THEN loan_amount ELSE 0 END)           AS bad_loan_funded,
        SUM(CASE WHEN loan_status = 'Charged Off'
                 THEN (loan_amount - total_payment)
                 ELSE 0 END)                            AS gross_loss
    FROM financial_loan
)
SELECT
    total_apps,
    ROUND(total_funded    / 1e6, 2)                     AS total_funded_usd_m,
    ROUND(total_received  / 1e6, 2)                     AS total_received_usd_m,
    ROUND(gross_loss      / 1e6, 2)                     AS estimated_gross_loss_usd_m,
    -- Bad Loan Rate (count-based)
    ROUND(bad_loan_count  * 100.0 / total_apps,    2)   AS bad_loan_rate_pct,
    -- Bad Loan Rate (value-based — more meaningful for credit risk)
    ROUND(bad_loan_funded * 100.0 / total_funded,  2)   AS bad_loan_value_rate_pct,
    -- Recovery Rate on defaulted loans
    ROUND((bad_loan_funded - gross_loss) * 100.0
          / NULLIF(bad_loan_funded, 0),            2)   AS default_recovery_rate_pct
FROM loan_totals;
