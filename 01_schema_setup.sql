-- =============================================================================
-- FILE       : 01_schema_setup.sql
-- PROJECT    : Loan Portfolio Risk Analysis
-- AUTHOR     : Saurav Raj
-- DESCRIPTION: Creates the database schema and loads the financial_loan dataset.
--              Run this file first before executing any other SQL scripts.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. DATABASE SETUP
-- ----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS loan_portfolio_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE loan_portfolio_db;


-- ----------------------------------------------------------------------------
-- 2. DROP & RECREATE TABLE (idempotent)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS financial_loan;

CREATE TABLE financial_loan (
    id                    INT             NOT NULL,
    address_state         VARCHAR(5)      NULL COMMENT 'US state abbreviation of borrower address',
    application_type      VARCHAR(20)     NULL COMMENT 'INDIVIDUAL or JOINT',
    emp_length            VARCHAR(20)     NULL COMMENT 'Employment length band (e.g. < 1 year, 10+ years)',
    emp_title             VARCHAR(100)    NULL COMMENT 'Job title of borrower',
    grade                 CHAR(1)         NULL COMMENT 'LendingClub assigned loan grade A-G',
    home_ownership        VARCHAR(20)     NULL COMMENT 'RENT / OWN / MORTGAGE / OTHER',
    issue_date            DATE            NULL COMMENT 'Date the loan was issued',
    last_credit_pull_date DATE            NULL COMMENT 'Most recent credit bureau pull date',
    last_payment_date     DATE            NULL COMMENT 'Date of most recent payment received',
    loan_status           VARCHAR(30)     NULL COMMENT 'Fully Paid / Charged Off / Current',
    next_payment_date     DATE            NULL COMMENT 'Scheduled next payment date',
    member_id             BIGINT          NULL COMMENT 'Unique member identifier',
    purpose               VARCHAR(50)     NULL COMMENT 'Stated purpose of the loan',
    sub_grade             VARCHAR(5)      NULL COMMENT 'Refined grade (e.g. A1, B3, C5)',
    term                  VARCHAR(20)     NULL COMMENT 'Loan repayment term (36 or 60 months)',
    verification_status   VARCHAR(30)     NULL COMMENT 'Not Verified / Source Verified / Verified',
    annual_income         DECIMAL(15, 2)  NULL COMMENT 'Annual income of borrower (USD)',
    dti                   DECIMAL(8, 4)   NULL COMMENT 'Debt-to-income ratio at time of application',
    installment           DECIMAL(10, 2)  NULL COMMENT 'Monthly installment amount (USD)',
    int_rate              DECIMAL(6, 4)   NULL COMMENT 'Interest rate on the loan (decimal, e.g. 0.1527 = 15.27%)',
    loan_amount           DECIMAL(12, 2)  NULL COMMENT 'Principal loan amount disbursed (USD)',
    total_acc             INT             NULL COMMENT 'Total number of credit lines in borrower credit file',
    total_payment         DECIMAL(12, 2)  NULL COMMENT 'Total payments received to date (USD)',

    PRIMARY KEY (id),
    INDEX idx_loan_status  (loan_status),
    INDEX idx_grade        (grade),
    INDEX idx_issue_date   (issue_date),
    INDEX idx_state        (address_state),
    INDEX idx_purpose      (purpose)
) ENGINE=InnoDB
  COMMENT='LendingClub loan portfolio data — 38,576 records (2021)';


-- ----------------------------------------------------------------------------
-- 3. DATA LOAD
-- NOTE: Update the file path below to match your local environment.
--       MySQL must have FILE privilege and secure_file_priv must allow the path.
--       Alternatively, import via MySQL Workbench: Table Data Import Wizard.
-- ----------------------------------------------------------------------------

/*
LOAD DATA INFILE '/path/to/financial_loan.csv'
INTO TABLE financial_loan
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS                          -- skip header row
(
    id, address_state, application_type, emp_length, emp_title, grade,
    home_ownership,
    @issue_date, @last_credit_pull_date, @last_payment_date,
    loan_status, @next_payment_date,
    member_id, purpose, sub_grade, term, verification_status,
    annual_income, dti, installment, int_rate, loan_amount, total_acc, total_payment
)
SET
    -- Convert DD-MM-YYYY strings to MySQL DATE format
    issue_date            = STR_TO_DATE(@issue_date,            '%d-%m-%Y'),
    last_credit_pull_date = STR_TO_DATE(@last_credit_pull_date, '%d-%m-%Y'),
    last_payment_date     = STR_TO_DATE(@last_payment_date,     '%d-%m-%Y'),
    next_payment_date     = NULLIF(STR_TO_DATE(@next_payment_date, '%d-%m-%Y'), '0000-00-00');
*/


-- ----------------------------------------------------------------------------
-- 4. QUICK SANITY CHECK
-- ----------------------------------------------------------------------------
-- Run after loading data to verify row count and column completeness.

SELECT
    COUNT(*)                                          AS total_rows,
    COUNT(DISTINCT loan_status)                       AS distinct_statuses,
    COUNT(DISTINCT grade)                             AS distinct_grades,
    COUNT(DISTINCT address_state)                     AS distinct_states,
    MIN(issue_date)                                   AS earliest_issue,
    MAX(issue_date)                                   AS latest_issue,
    ROUND(SUM(loan_amount) / 1000000, 2)              AS total_portfolio_usd_m,
    ROUND(AVG(int_rate) * 100, 2)                     AS avg_interest_rate_pct
FROM financial_loan;
