USE loan_portfolio_db;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A │ BY LOAN GRADE
-- ─────────────────────────────────────────────────────────────────────────────

-- A1. Portfolio distribution across grades A-G
SELECT
    grade,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                    AS funded_usd_m,
    ROUND(SUM(total_payment) / 1e6, 2)                    AS received_usd_m,
    ROUND(AVG(int_rate) * 100,  2)                        AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100,  2)                        AS avg_dti_pct,
    ROUND(AVG(loan_amount),     2)                        AS avg_loan_size_usd,
    -- Default rate by grade — key risk indicator
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY grade
ORDER BY grade;


-- A2. Sub-Grade Breakdown (granular risk ladder)
SELECT
    sub_grade,
    LEFT(sub_grade, 1)                                    AS grade,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount) / 1e6,  2)                     AS funded_usd_m,
    ROUND(AVG(int_rate)    * 100,  2)                     AS avg_int_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY sub_grade
ORDER BY sub_grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B │ BY LOAN PURPOSE
-- ─────────────────────────────────────────────────────────────────────────────

-- B1. Volume and risk by stated purpose
SELECT
    purpose,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                    AS funded_usd_m,
    ROUND(AVG(loan_amount),         2)                    AS avg_loan_size_usd,
    ROUND(AVG(int_rate) * 100,      2)                    AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100,      2)                    AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    -- Rank by default rate to identify highest-risk purposes
    RANK() OVER (ORDER BY
        SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*) DESC)                          AS default_rate_rank
FROM financial_loan
GROUP BY purpose
ORDER BY default_rate_rank;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C │ BY US STATE (Geographic Exposure)
-- ─────────────────────────────────────────────────────────────────────────────

-- C1. State-level portfolio exposure (top 20 by volume)
SELECT
    address_state                                         AS state,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount)   / 1e6, 2)                    AS funded_usd_m,
    ROUND(SUM(total_payment) / 1e6, 2)                    AS received_usd_m,
    ROUND(AVG(int_rate) * 100,      2)                    AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100,      2)                    AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY address_state
ORDER BY funded_usd_m DESC
LIMIT 20;


-- C2. Highest-risk states by default rate (min 100 loans for statistical validity)
SELECT
    address_state                                         AS state,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount) / 1e6, 2)                      AS funded_usd_m,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off'
                   THEN (loan_amount - total_payment) ELSE 0 END) / 1e6, 2)
                                                          AS estimated_loss_usd_m,
    RANK() OVER (ORDER BY
        SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*) DESC)                          AS risk_rank
FROM financial_loan
GROUP BY address_state
HAVING COUNT(*) >= 100
ORDER BY default_rate_pct DESC
LIMIT 15;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION D │ BY LOAN TERM
-- ─────────────────────────────────────────────────────────────────────────────

-- D1. 36-month vs 60-month comparison
SELECT
    TRIM(term)                                            AS term,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                    AS funded_usd_m,
    ROUND(AVG(loan_amount),         2)                    AS avg_loan_size_usd,
    ROUND(AVG(int_rate) * 100,      2)                    AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100,      2)                    AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY TRIM(term)
ORDER BY term;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION E │ BY EMPLOYMENT LENGTH
-- ─────────────────────────────────────────────────────────────────────────────

-- E1. Default rate by borrower employment tenure
--     Hypothesis: longer-tenured employees are more stable borrowers
SELECT
    emp_length,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount) / 1e6,  2)                     AS funded_usd_m,
    ROUND(AVG(annual_income),      2)                     AS avg_annual_income_usd,
    ROUND(AVG(loan_amount),        2)                     AS avg_loan_size_usd,
    ROUND(AVG(dti) * 100,          2)                     AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY emp_length
-- Custom sort order for logical employment tenure sequence
ORDER BY
    CASE emp_length
        WHEN '< 1 year' THEN 1
        WHEN '1 year'   THEN 2
        WHEN '2 years'  THEN 3
        WHEN '3 years'  THEN 4
        WHEN '4 years'  THEN 5
        WHEN '5 years'  THEN 6
        WHEN '6 years'  THEN 7
        WHEN '7 years'  THEN 8
        WHEN '8 years'  THEN 9
        WHEN '9 years'  THEN 10
        WHEN '10+ years' THEN 11
        ELSE 12
    END;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION F │ BY HOME OWNERSHIP
-- ─────────────────────────────────────────────────────────────────────────────

-- F1. Homeownership status as a credit proxy
SELECT
    home_ownership,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(AVG(annual_income),      2)                     AS avg_annual_income_usd,
    ROUND(AVG(loan_amount),        2)                     AS avg_loan_size_usd,
    ROUND(AVG(dti) * 100,          2)                     AS avg_dti_pct,
    ROUND(AVG(int_rate) * 100,     2)                     AS avg_int_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY home_ownership
ORDER BY applications DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION G │ BY VERIFICATION STATUS
-- ─────────────────────────────────────────────────────────────────────────────

-- G1. Does income verification reduce defaults?
--     This is a key policy question for underwriting teams.
SELECT
    verification_status,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(AVG(annual_income),      2)                     AS avg_annual_income_usd,
    ROUND(AVG(loan_amount),        2)                     AS avg_loan_size_usd,
    ROUND(AVG(int_rate) * 100,     2)                     AS avg_int_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY verification_status
ORDER BY default_rate_pct DESC;
-- NOTE: If verified loans show higher default rates, this warrants a
--       deeper investigation into the verification process quality.
