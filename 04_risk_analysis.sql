USE loan_portfolio_db;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION A │ LOSS GIVEN DEFAULT (LGD) ANALYSIS
-- ─────────────────────────────────────────────────────────────────────────────
-- LGD = (Funded Amount − Total Recovered) / Funded Amount
-- Measures the proportion of the loan NOT recovered after default.
-- A key metric in Basel III credit risk frameworks (IFRS 9).

-- A1. Portfolio-wide LGD summary
SELECT
    COUNT(*)                                              AS charged_off_count,
    ROUND(SUM(loan_amount)                / 1e6, 2)       AS total_defaulted_usd_m,
    ROUND(SUM(total_payment)              / 1e6, 2)       AS total_recovered_usd_m,
    ROUND(SUM(loan_amount - total_payment)/ 1e6, 2)       AS total_net_loss_usd_m,
    -- Average LGD across all defaulted loans
    ROUND(AVG((loan_amount - total_payment) / loan_amount) * 100, 2)
                                                          AS avg_lgd_pct,
    -- Recovery Rate = 1 − LGD
    ROUND((1 - AVG((loan_amount - total_payment)
                   / loan_amount)) * 100, 2)              AS avg_recovery_rate_pct
FROM financial_loan
WHERE loan_status = 'Charged Off';


-- A2. LGD by Loan Grade — riskiest grades identified
SELECT
    grade,
    COUNT(*)                                              AS defaults,
    ROUND(SUM(loan_amount)                 / 1e6, 2)      AS defaulted_principal_usd_m,
    ROUND(SUM(loan_amount - total_payment) / 1e6, 2)      AS net_loss_usd_m,
    ROUND(AVG((loan_amount - total_payment)
              / loan_amount) * 100, 2)                    AS avg_lgd_pct,
    ROUND((1 - AVG((loan_amount - total_payment)
                   / loan_amount)) * 100, 2)              AS avg_recovery_rate_pct,
    RANK() OVER (ORDER BY
        AVG((loan_amount - total_payment) / loan_amount) DESC)
                                                          AS lgd_rank
FROM financial_loan
WHERE loan_status = 'Charged Off'
GROUP BY grade
ORDER BY avg_lgd_pct DESC;


-- A3. LGD by Loan Purpose — which purposes are most destructive?
SELECT
    purpose,
    COUNT(*)                                              AS defaults,
    ROUND(SUM(loan_amount - total_payment) / 1e6, 2)      AS net_loss_usd_m,
    ROUND(AVG((loan_amount - total_payment)
              / loan_amount) * 100, 2)                    AS avg_lgd_pct
FROM financial_loan
WHERE loan_status = 'Charged Off'
GROUP BY purpose
ORDER BY net_loss_usd_m DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION B │ DTI (DEBT-TO-INCOME) RISK SEGMENTATION
-- ─────────────────────────────────────────────────────────────────────────────

-- B1. DTI Risk Bucket Framework (analyst-defined segmentation)
--     Used to classify borrowers by leverage risk at origination.
SELECT
    CASE
        WHEN dti < 0.10              THEN '1 - Low        (DTI < 10%)'
        WHEN dti BETWEEN 0.10 AND 0.20 THEN '2 - Moderate   (DTI 10-20%)'
        WHEN dti BETWEEN 0.20 AND 0.30 THEN '3 - High       (DTI 20-30%)'
        WHEN dti > 0.30              THEN '4 - Very High  (DTI > 30%)'
        ELSE '5 - Unknown'
    END                                                   AS dti_risk_bucket,
    COUNT(*)                                              AS applications,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)    AS pct_of_portfolio,
    ROUND(SUM(loan_amount)   / 1e6, 2)                    AS funded_usd_m,
    ROUND(AVG(int_rate) * 100,      2)                    AS avg_int_rate_pct,
    ROUND(AVG(annual_income),       2)                    AS avg_annual_income_usd,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY dti_risk_bucket
ORDER BY dti_risk_bucket;


-- B2. DTI vs Interest Rate — are high-DTI borrowers being priced correctly?
--     If high-DTI borrowers are not charged higher rates, it signals
--     a potential underwriting policy gap.
SELECT
    CASE
        WHEN dti < 0.10              THEN 'Low'
        WHEN dti BETWEEN 0.10 AND 0.20 THEN 'Moderate'
        WHEN dti BETWEEN 0.20 AND 0.30 THEN 'High'
        WHEN dti > 0.30              THEN 'Very High'
    END                                                   AS dti_bucket,
    grade,
    COUNT(*)                                              AS applications,
    ROUND(AVG(int_rate) * 100, 2)                         AS avg_int_rate_pct,
    ROUND(AVG(dti)      * 100, 2)                         AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY dti_bucket, grade
ORDER BY dti_bucket, grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION C │ MULTI-FACTOR RISK MATRIX
-- ─────────────────────────────────────────────────────────────────────────────

-- C1. Grade × Purpose Default Rate Matrix
--     Which grade/purpose combinations are the most dangerous?
--     Output can be pivoted in Tableau as a heat map.
SELECT
    grade,
    purpose,
    COUNT(*)                                              AS applications,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(SUM(loan_amount) / 1e6, 2)                      AS funded_usd_m
FROM financial_loan
GROUP BY grade, purpose
HAVING COUNT(*) >= 30    -- filter out statistically thin cells
ORDER BY default_rate_pct DESC
LIMIT 25;


-- C2. Risk Concentration: Top 10 Highest-Loss Segments
--     Combines Grade + Purpose + Term into a single risk segment.
SELECT
    CONCAT(grade, ' | ', purpose, ' | ', TRIM(term))     AS risk_segment,
    COUNT(*)                                              AS applications,
    ROUND(SUM(loan_amount)                 / 1e6, 2)      AS funded_usd_m,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off'
                   THEN (loan_amount - total_payment)
                   ELSE 0 END) / 1e6, 2)                  AS net_loss_usd_m,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY risk_segment
HAVING COUNT(*) >= 50
ORDER BY net_loss_usd_m DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION D │ INCOME-TO-LOAN RATIO ANALYSIS
-- ─────────────────────────────────────────────────────────────────────────────

-- D1. Income vs. Loan Size — affordability segmentation
--     Loan-to-income ratio = loan_amount / annual_income
--     Higher ratios indicate stretched borrowers.
SELECT
    CASE
        WHEN (loan_amount / NULLIF(annual_income, 0)) < 0.10  THEN '1 - <10%  (Very Conservative)'
        WHEN (loan_amount / NULLIF(annual_income, 0)) < 0.20  THEN '2 - 10-20% (Conservative)'
        WHEN (loan_amount / NULLIF(annual_income, 0)) < 0.35  THEN '3 - 20-35% (Moderate)'
        WHEN (loan_amount / NULLIF(annual_income, 0)) < 0.50  THEN '4 - 35-50% (Aggressive)'
        ELSE                                                       '5 - >50%  (Very Aggressive)'
    END                                                   AS loan_to_income_bucket,
    COUNT(*)                                              AS applications,
    ROUND(AVG(annual_income),       0)                    AS avg_income_usd,
    ROUND(AVG(loan_amount),         0)                    AS avg_loan_usd,
    ROUND(AVG(int_rate) * 100,      2)                    AS avg_int_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct
FROM financial_loan
GROUP BY loan_to_income_bucket
ORDER BY loan_to_income_bucket;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION E │ INTEREST RATE SENSITIVITY
-- ─────────────────────────────────────────────────────────────────────────────

-- E1. Default rate by interest rate band
--     Validates whether pricing correctly reflects default risk.
SELECT
    CASE
        WHEN int_rate < 0.08              THEN '1 - <8%'
        WHEN int_rate BETWEEN 0.08 AND 0.12 THEN '2 - 8-12%'
        WHEN int_rate BETWEEN 0.12 AND 0.16 THEN '3 - 12-16%'
        WHEN int_rate BETWEEN 0.16 AND 0.20 THEN '4 - 16-20%'
        WHEN int_rate > 0.20              THEN '5 - >20%'
    END                                                   AS interest_rate_band,
    COUNT(*)                                              AS applications,
    ROUND(AVG(int_rate) * 100,      2)                    AS avg_int_rate_pct,
    ROUND(AVG(loan_amount),         2)                    AS avg_loan_size_usd,
    ROUND(AVG(dti) * 100,           2)                    AS avg_dti_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off' THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                          AS default_rate_pct,
    ROUND(SUM(CASE WHEN loan_status = 'Charged Off'
                   THEN (loan_amount - total_payment) ELSE 0 END) / 1e6, 2)
                                                          AS net_loss_usd_m
FROM financial_loan
GROUP BY interest_rate_band
ORDER BY interest_rate_band;
