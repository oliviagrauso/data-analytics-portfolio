CREATE TABLE transactions (
	Invoice TEXT,
	StockCode TEXT,
	Description TEXT,
	Quantity INTEGER,
	InvoiceDate TIMESTAMP,
	Price NUMERIC,
	CustomerID INTEGER,
	Country TEXT
);

-- Issue importing the CSV data: SQL doesn't recognize CustomerID as an integer, so I'll change the data type.
ALTER TABLE transactions
ALTER COLUMN CustomerID TYPE NUMERIC;

------ DATA PREPARATION

-- Check if CustomerID field is complete before changing the data type; if not, leave as numeric for now.
SELECT COUNT(*) as total_nulls
FROM transactions
WHERE CustomerID IS NULL;

SELECT COUNT(*) FROM transactions;
-- 243.007 nulls from 1.067.371 rows. So, I'm leaving as numeric for now.

-- Create a new table to cleaning and transforming data, leaving the original.
CREATE TABLE transactions_clean AS
SELECT
	Invoice,
	CustomerID,
	StockCode,
	Description,
	Quantity,
	Price,
	InvoiceDate,
	Country
FROM transactions;

-- Invoice Column	
-- Add a column with the row number for each invoice.

ALTER TABLE transactions_clean
ADD COLUMN line_no INTEGER;

UPDATE transactions_clean
SET line_no = temptable.rownumb
FROM (
	SELECT ctid, ROW_NUMBER() OVER(PARTITION BY Invoice ORDER BY InvoiceDate) AS rownumb
	FROM transactions_clean) AS temptable
WHERE transactions_clean.ctid = temptable.ctid;

-- I checked all columns and found that CustomerID and Description have null values. Now, I'll investigate.

-- CustomerID Column
-- I want to verify if the CustomerID appears in a second row of the same invoice, and then fill in the null value.
SELECT
	Invoice,
	COUNT(*) AS total_rows,
	COUNT(CustomerID) AS rows_with_customer,
	COUNT(*) - COUNT(CustomerID) AS null_rows
FROM transactions_clean
GROUP BY Invoice
HAVING COUNT (*) - COUNT(CustomerID) > 0 -- at least one null row
	AND HAVING COUNT(CustomerID) > 0 -- AND at least one row with CustomerID in the same invoice;

-- Zero results. Therefore, invoices with empty CustomerID cannot be analyzed, and it is 23% of data.
DELETE FROM transactions_clean
WHERE CustomerID IS NULL;

-- Description Column
-- Now, I will check if any null value still exist in the Description column.
SELECT Description AS null_description
FROM transactions_clean
WHERE Description IS NULL;
-- Zero results. The rows with null value in Description were the same as the rows with null CustomerID, that have already been deleted.

-- Quantity Column
-- Exploring the dataset, I noticed negative quantities, and by looking deeper, all of these are related to credit notes.
-- So, I will confirm this, create a column to categorize the invoices, and create a column with net quantity.
SELECT Invoice, SUM(Quantity) AS sum_qty
FROM transactions_clean
GROUP BY Invoice, CustomerID
HAVING SUM(Quantity) < 0 AND Invoice NOT LIKE 'C%'; -- all negative qty are from invoices with 'C' at the beginning.

ALTER TABLE transactions_clean
ADD COLUMN invoice_status TEXT;

UPDATE transactions_clean
SET invoice_status = CASE
						WHEN Invoice LIKE 'C%' THEN 'credit'
						ELSE 'sale'
					END;

ALTER TABLE transactions_clean
ADD COLUMN net_quantity INTEGER;

UPDATE transactions_clean
SET net_quantity = CASE
						WHEN invoice_status = 'credit' THEN '0'
						ELSE Quantity
					END;

-- Understanding the quantities
SELECT
	ROUND(MIN(Quantity),2) AS min_qty, -- min 1
	ROUND(MAX(Quantity),2) AS max_qty, -- max 80995
	ROUND(AVG(Quantity),2) AS avg_qty, -- avg 13,31
	PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY Quantity) AS median_qty -- median 5
FROM transactions_clean
WHERE Quantity > 0;

SELECT
	CASE
		WHEN Quantity BETWEEN 1 AND 50 THEN 'a) 1-50'			-- 782233
		WHEN Quantity BETWEEN 51 AND 150 THEN 'b) 51-150'		-- 17572
		WHEN Quantity BETWEEN 151 AND 300 THEN 'c) 151-300'		-- 3905
		WHEN Quantity BETWEEN 301 AND 500 THEN 'd) 301-500'		-- 959
		WHEN Quantity BETWEEN 501 AND 1000 THEN 'e) 501-1000'	-- 646
		WHEN Quantity BETWEEN 1001 AND 9999 THEN 'f) 1001-9999'	-- 293
		ELSE 'g) 10000+'										-- 12
	END AS qty_range,
	COUNT(*) AS num_rows
FROM transactions_clean
WHERE Quantity > 0
GROUP BY qty_range
ORDER BY qty_range;

-- InvoiceDate Column
-- The dataset is about invoices between 2009-2011, and I want to confirm this, and create a new column without time.
SELECT
	MIN(invoicedate) AS min_date,
	MAX(invoicedate) AS max_date
FROM transactions_clean; -- Ok, from 01-12-2009 to 09-12-2011

ALTER TABLE transactions_clean
ADD COLUMN invoice_date DATE;

UPDATE transactions_clean
SET invoice_date = InvoiceDate::DATE;

-- Price Column
SELECT * 
FROM transactions_clean
WHERE price < 0 AND invoice_status = 'sale'; -- all sales invoice has price > 0

SELECT * 
FROM transactions_clean
WHERE price = 0; -- There are 71 rows with price = 0. No consistent pattern, and no significant impact on revenue analysis. I suppose they are samples.

-- Add Revenue Column
ALTER TABLE transactions_clean
ADD COLUMN Revenue NUMERIC;

UPDATE transactions_clean
SET Revenue = ROUND((Quantity * Price),2);

SELECT
	ROUND(AVG(price),2) AS price_avg,	-- avg 3,68
	MIN(price) AS min_price,			-- min 0
	MAX(price) AS max_price				-- max 38970
FROM transactions_clean;

WITH invoice_revenue AS (
	SELECT
		invoice,
		SUM(revenue) AS invoice_revenue
	FROM transactions_clean
	WHERE revenue > 0
	GROUP BY invoice
)

SELECT
	ROUND(MIN(invoice_revenue),2) AS min_revenue, 									-- min revenue 0,38
	ROUND(MAX(invoice_revenue),2) AS max_revenue,									-- max revenue 168469,6
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY invoice_revenue) AS median_revenue, -- 50% <= 305,25
	PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY invoice_revenue) AS p90_revenue,	-- 90% <= 851,67
	PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY invoice_revenue) AS p99_revenue	-- 99% <= 3697,92
FROM invoice_revenue;

-- Just checking if the invoice numbers of the credit notes (starting with C) matching with the sales order numbers.
SELECT COUNT(*) AS matched_invoices
FROM transactions_clean cancel
JOIN transactions_clean sorder
	ON sorder.Invoice = SUBSTRING(cancel.Invoice FROM 2)
WHERE cancel.Invoice LIKE 'C%';

-- Country Column
SELECT
	Country,
	COUNT(Country) AS row_qty
FROM transactions_clean
GROUP BY Country
ORDER BY Country ASC;

-- Standardizing some country names
UPDATE transactions_clean SET Country = 'South Africa' WHERE Country = 'RSA';
UPDATE transactions_clean SET Country = 'Ireland' WHERE Country = 'EIRE';
UPDATE transactions_clean SET Country = 'European Union' WHERE Country = 'European Community';

SELECT COUNT(*) AS null_countries
FROM transactions_clean
WHERE Country IS NULL OR TRIM(Country) = '';

SELECT
	Country,
	LENGTH(Country) AS len_original,
	LENGTH(TRIM(Country)) AS len_clean
FROM transactions_clean
WHERE LENGTH(TRIM(Country)) <> LENGTH(Country);

UPDATE transactions_clean
SET Country = TRIM(Country);

SELECT
  Country,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM transactions_clean
GROUP BY Country
ORDER BY pct DESC;

-- Now that I have transactions_clean table transformed, I will create the table like as the ERD.

CREATE TABLE Customer AS
SELECT DISTINCT
	CustomerID::Integer,
	Country
FROM transactions_clean;

CREATE TABLE Product AS
SELECT DISTINCT
	StockCode AS ProductID,
	Description
FROM transactions_clean;

CREATE TABLE Date AS
SELECT
	d::date AS Date,
	EXTRACT(YEAR FROM d)::integer AS Year,
	EXTRACT(MONTH FROM d)::integer AS Month,
	EXTRACT(DAY FROM d)::integer AS Day,
	EXTRACT(QUARTER FROM d)::integer AS Quarter
FROM generate_series(
	DATE'2009-01-01',
	DATE'2011-12-31',
	INTERVAL '1 day'
) d;

CREATE TABLE Invoice AS
SELECT
	Invoice AS InvoiceID,
	Line_No AS InvoiceLine,
	CustomerID::integer,
	StockCode AS ProductID,
	Quantity,
	ROUND(Price,2) AS UnitPrice,
	ROUND((Price * Quantity),2) AS Total,
	Invoice_Date AS InvoiceDate,
	Invoice_Status AS TypeOrder
FROM transactions_clean;

-- Miss a change about zero price. I need to describe these lines as 'sample'.
UPDATE transactions_clean
SET invoice_status = 'sample' WHERE Price = 0; -- 71 rows

SELECT * FROM transactions_clean WHERE Price = 0;


-- Customer RFM Table: Recency, Frequency and Monetary metrics + scores + additional metrics

CREATE TABLE Customer_RFM AS
WITH reference_date AS (
	SELECT MAX(InvoiceDate) AS ref_date
	FROM Invoice
	WHERE TypeOrder = 'sale'
),
rfm_base AS (
	SELECT
		i.CustomerID,
		(ref.ref_date - MAX(InvoiceDate))::integer AS Recency,
		COUNT(DISTINCT i.InvoiceID) AS Frequency,
		SUM(i.Total) AS Monetary
	FROM Invoice i
	CROSS JOIN reference_date ref
	WHERE i.TypeOrder = 'sale'
	GROUP BY i.CustomerID, ref.ref_date
),
rfm_scored AS (
	SELECT
		*,
		NTILE(5) OVER (ORDER BY Recency DESC) AS RecencyScore,
		NTILE(5) OVER (ORDER BY Frequency) AS FrequencyScore,
		NTILE(5) OVER (ORDER BY Monetary) AS MonetaryScore
	FROM rfm_base
)
SELECT
	*,
	(RecencyScore + FrequencyScore + MonetaryScore) AS RFM_Score
FROM rfm_scored;

ALTER TABLE Customer_RFM
ADD COLUMN AVG_Ticket numeric;

UPDATE Customer_RFM
SET AVG_Ticket = ROUND((Monetary / NULLIF(Frequency, 0)),2);

ALTER TABLE Customer_RFM
ADD COLUMN FrequencyDrop boolean;

WITH reference_date AS (
	SELECT MAX(InvoiceDate) as ref_date
	FROM Invoice
),
customer_span AS (
	SELECT
		i.CustomerID,
		MIN(i.InvoiceDate) AS first_purchase_date,
		ref.ref_date
	FROM Invoice i
	CROSS JOIN reference_date ref
	WHERE i.TypeOrder = 'sale'
	GROUP BY i.CustomerID, ref.ref_date
),
freq_calc AS (
	SELECT
		i.CustomerID,
		COUNT(DISTINCT i.InvoiceID) FILTER (
			WHERE i.InvoiceDate >= cs.ref_date - INTERVAL '3 months'
				AND i.TypeOrder = 'sale'
		) AS freq_recent,
		COUNT(DISTINCT i.InvoiceID) FILTER (
			WHERE i.TypeOrder = 'sale'
		) AS freq_total,
		GREATEST(
			DATE_PART('month', AGE(cs.ref_date, cs.first_purchase_date)) + 
			DATE_PART('year', AGE(cs.ref_date, cs.first_purchase_date)) * 12,
			1
		) AS total_months
	FROM Invoice i
	JOIN customer_span cs
		ON i.CustomerID = cs.CustomerID
	GROUP BY i.CustomerID, cs.first_purchase_date, cs.ref_date
)

UPDATE Customer_RFM c
SET FrequencyDrop = ((freq_recent / 3) < (freq_total / total_months))
FROM freq_calc fc
WHERE c.CustomerID = fc.CustomerID;

SELECT
	COUNT(rfm_score) FILTER (WHERE rfm_score > 0 AND rfm_score <= 5) as one_five,
	COUNT(rfm_score) FILTER (WHERE rfm_score > 5 AND rfm_score <= 10) as six_ten,
	COUNT(rfm_score) FILTER (WHERE rfm_score > 10 AND rfm_score <= 15) as eleven_fifth
FROM Customer_RFM;


-- The final column will classify customers into segments to support retention prioritization.

ALTER TABLE Customer_RFM
ADD COLUMN CustomerSegment text;

-- Before filling the CustomerSegment column, I would test my idea about the categories to analyze if it has sense.

SELECT 
    segment_test,
    COUNT(*) AS total_customers,
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),2) AS percentage_customers,
	ROUND(SUM(monetary),2) AS total_revenue,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (),2) AS percentage_revenue
FROM (
	SELECT 
	customerid,
	monetary,
    recencyscore,
    frequencyscore,
    monetaryscore,
    CASE
        WHEN recencyscore >= 4 AND frequencyscore >= 4 AND monetaryscore >= 4
        THEN 'Champions'

        WHEN frequencyscore >= 4 AND monetaryscore >= 3 AND recencyscore >= 3
        THEN 'Loyal Customers'

        WHEN monetaryscore >= 4 AND frequencyscore <= 3 
		THEN 'Big Spenders'

        WHEN recencyscore <= 2 AND (frequencyscore >= 3 OR monetaryscore >= 3)
        THEN 'At Risk'

        WHEN recencyscore >= 4 AND frequencyscore <= 2
        THEN 'New Customers'

		WHEN recencyscore >= 3 AND frequencyscore BETWEEN 2 AND 3 AND monetaryscore BETWEEN 2 AND 3
		THEN 'Regular Customers'

        WHEN recencyscore <= 2 AND frequencyscore <= 2 AND monetaryscore <= 2
        THEN 'Hibernating'

        ELSE 'Others'
    END AS segment_test
FROM customer_rfm
) t
GROUP BY segment_test
ORDER BY total_customers DESC;

-- Now, I can define the segments because I first analyzed my idea about them:
-- Champions: Most recent, frequent and highest-value ticket. The ideal customer group.
-- Loyal Customers: Frequent customers with consistent purchasing behavior and solid revenue contribution.
-- Big Spenders: Customers with high spending per purchase but lower purchase frequency.
-- At Risk: Previously active or valuable customers who have not purchased recently.
-- New Customers: Recently acquired customers with low purchase frequency.
-- Regular Customers: Customers with average recency, frequency and monetary value. Stable but not highly engaged.
-- Hibernating: Inactive customers with low recency, frequency and monetary value.
-- Others: Customers who do not clearly fit into the defined behavioral segments.

UPDATE Customer_RFM
SET CustomerSegment = 
	CASE
		WHEN RecencyScore >= 4 AND FrequencyScore >= 4 AND MonetaryScore >= 4
		THEN 'Champions'
		
		WHEN FrequencyScore >= 4 AND MonetaryScore >= 3 AND RecencyScore >= 3
		THEN 'Loyal Customers'
		
		WHEN MonetaryScore >= 4 AND FrequencyScore BETWEEN 2 AND 3 AND RecencyScore >= 3
		THEN 'Big Spenders'
		
		WHEN RecencyScore <= 2 AND (FrequencyScore >= 3 OR MonetaryScore >= 3)
		THEN 'At Risk'
		
		WHEN RecencyScore >= 4 AND FrequencyScore <= 2
		THEN 'New Customers'

		WHEN RecencyScore >= 3 AND FrequencyScore BETWEEN 2 AND 3 AND MonetaryScore BETWEEN 2 AND 3
		THEN 'Regular Customers'
		
		WHEN RecencyScore <= 2 AND FrequencyScore <= 2 AND MonetaryScore <= 2
		THEN 'Hibernating'
		
		ELSE 'Others'
	END;


-- Since I defined the RFM Score using the NTILE function, which assigns scores based on quintiles, I need to understand the range of each KPI (Recency, Frequency, and Monetary), to explain it in the dashboard

SELECT
	RecencyScore,
	MIN(Recency) AS min_recency,
	MAX(Recency) AS max_recency,
	COUNT(*) AS customers
FROM customer_rfm
GROUP BY RecencyScore
ORDER BY RecencyScore DESC;

SELECT
	FrequencyScore,
	MIN(Frequency) AS min_frequency,
	MAX(Frequency) AS max_frequency,
	COUNT(*) AS customers
FROM customer_rfm
GROUP BY FrequencyScore
ORDER BY FrequencyScore DESC;

SELECT
	MonetaryScore,
	MIN(Monetary) AS min_monetary,
	MAX(Monetary) AS max_monetary,
	COUNT(*) AS customers
FROM customer_rfm
GROUP BY MonetaryScore
ORDER BY MonetaryScore DESC;








