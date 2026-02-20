-- Exported from QuickDBD: https://www.quickdatabasediagrams.com/
-- Link to schema: https://app.quickdatabasediagrams.com/#/d/chPqef
-- NOTE! If you have used non-SQL datatypes in your design, you will have to change these here.

-- Project Retail ERD

CREATE TABLE "Customer" (
    "CustomerID" integer   NOT NULL,
    "Country" text   NOT NULL,
    CONSTRAINT "pk_Customer" PRIMARY KEY (
        "CustomerID"
     )
);

CREATE TABLE "Invoice" (
    "InvoiceID" text   NOT NULL,
    "InvoiceLine" integer   NOT NULL,
    "CustomerID" integer   NOT NULL,
    "ProductID" text   NOT NULL,
    "Quantity" integer   NOT NULL,
    "UnitPrice" numeric   NOT NULL,
    "Total" numeric   NOT NULL,
    "InvoiceDate" date   NOT NULL,
    "TypeOrder" text   NOT NULL,
    CONSTRAINT "pk_Invoice" PRIMARY KEY (
        "InvoiceID"
     )
);

CREATE TABLE "Product" (
    "ProductID" text   NOT NULL,
    "Description" text   NOT NULL,
    CONSTRAINT "pk_Product" PRIMARY KEY (
        "ProductID"
     )
);

CREATE TABLE "Date" (
    "Date" date   NOT NULL,
    "Year" integer   NOT NULL,
    "Month" integer   NOT NULL,
    "Day" integer   NOT NULL,
    "Quarter" integer   NOT NULL,
    CONSTRAINT "pk_Date" PRIMARY KEY (
        "Date"
     )
);

CREATE TABLE "CustomerRFM" (
    "CustomerID" integer   NOT NULL,
    "Recency" integer   NOT NULL,
    "Frequency" integer   NOT NULL,
    "Monetary" numeric   NOT NULL,
    "RecencyScore" integer   NOT NULL,
    "FrequencyScore" integer   NOT NULL,
    "MonetaryScore" integer   NOT NULL,
    "RFM_Score" integer   NOT NULL,
    "CustomerSegment" text   NOT NULL,
    "FrequencyDrop" integer   NOT NULL,
    "AvgTicket" numeric   NOT NULL,
    "LTV_Simple" integer   NOT NULL,
    CONSTRAINT "pk_CustomerRFM" PRIMARY KEY (
        "CustomerID"
     )
);

ALTER TABLE "Customer" ADD CONSTRAINT "fk_Customer_CustomerID" FOREIGN KEY("CustomerID")
REFERENCES "CustomerRFM" ("CustomerID");

ALTER TABLE "Invoice" ADD CONSTRAINT "fk_Invoice_CustomerID" FOREIGN KEY("CustomerID")
REFERENCES "Customer" ("CustomerID");

ALTER TABLE "Invoice" ADD CONSTRAINT "fk_Invoice_ProductID" FOREIGN KEY("ProductID")
REFERENCES "Product" ("ProductID");

ALTER TABLE "Invoice" ADD CONSTRAINT "fk_Invoice_InvoiceDate" FOREIGN KEY("InvoiceDate")
REFERENCES "Date" ("Date");

