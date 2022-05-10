USE master;
GO
DROP DATABASE backup_test;
GO
CREATE DATABASE backup_test;
GO

USE backup_test;
GO

CREATE TABLE dbo.MyValues (
	RecID INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
	MyValue VARCHAR(500),
	MyReversedValue VARCHAR(500),
	MyDate DATETIME
);
GO

SET NOCOUNT ON
GO

INSERT INTO dbo.MyValues (
	MyValue, MyReversedValue, MyDate
)
SELECT '1234567890', REVERSE('1234567890'), GETDATE() UNION ALL
SELECT 'ABCDEFGHIJ', REVERSE('ABCDEFGHIJ'), GETDATE() UNION ALL
SELECT 'KLMNOPQRST', REVERSE('KLMNOPQRST'), GETDATE() UNION ALL
SELECT '0987654321', REVERSE('0987654321'), GETDATE() UNION ALL
SELECT 'QRSTUVWXYZ', REVERSE('QRSTUVWXYZ'), GETDATE();
GO 1000

--
-- Activate Trace Flag to print output to query window
DBCC TRACEON(3604, 1);
GO

-- Get page information
DBCC IND(backup_test, MyValues, 1 /* IndexID */);

-- PageTypes
--  1 = data page
--  2 = index page
--  3 = text pages
--  4 = text pages
--  8 = GAM page
--  9 = SGAM page
-- 10 = IAM page
-- 11 = PFS page
-----
-- Use DBCC PAGE to examine contents of data page
-- DBCC PAGE([DatabaseName], [FileNumber], [PageID], [OutputType])
-- OutputType = 0 -> View Page Header Only
-- OutputType = 2 -> Header plus whole page hex dump 
-- OutputType = 3 -> Per Record Breakdown
-- Select a few pages to examine.  Use allocated_page_page_id from prior output
DBCC PAGE(backup_test, 1, 336, 2);

DBCC PAGE(backup_test, 1, 344, 2);
GO

-- Create a raw backup
BACKUP DATABASE backup_test 
	TO DISK = 'D:\MSSQL14.MSSQLSERVER\Data\backup_test_raw.bak' 
	WITH INIT, NO_COMPRESSION;
GO

-- SHUT DOWN SQL SERVER AND COMPARE FILES
-- Beyond Compare 4 works great as a fast hex editor comparison. Has 30 day free trial.
-- https://www.scootersoftware.com/download.php