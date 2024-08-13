/*******************************************************************************
* Shrink File Test
* 
* Written By: Andy Yun
* Created On: 2024-08-07
* 
* Question:
* If a customer has a large MDF/NDF file and deletes a bunch of data out of it, 
* then shrinks the file, we want to confirm what happens on the array itself.
* 
* Conclusion:
* This is against a single database, data file on a solo vvol (t-log elsewhere).  
* Adapted Paul's script methodology for this test.
* 
* After loading the filler table and second "prod" table (all GUIDs to try and 
* get some random-ish), total DB size reported in SQL Server was 33GB.  On the 
* array, the vvol volume showed:

vvol-ayun-sql22-01-261d769b-vg / ShrinkTest
Volume Size - 234.00 G 
Virtual - 31.11 G
Data Reduction - 1.2 to 1
Total - 25.75 G

* Dropped the filler table... no change in the array side.  Then ran shrink.  
* After shrink, SQL Server size = 15.88GB

vvol-ayun-sql22-01-261d769b-vg / ShrinkTest
Volume Size - 234.00 G 
Virtual - 15.94 G
Data Reduction - 1.1 to 1
Total - 13.85 G

*
* References:
* - https://sqlbek.wordpress.com/2024/08/13/pure-storage-flasharray-will-a-delete-and-or-shrink-reclaim-space/
* - https://www.sqlskills.com/blogs/paul/why-you-should-not-shrink-your-data-files/
*
*******************************************************************************/
 

------------------------------------------
-- SETUP START
------------------------------------------
USE [master];
GO

IF DATABASEPROPERTYEX (N'ShrinkTest', N'Version') IS NOT NULL
    DROP DATABASE [ShrinkTest];
GO
 


-----
-- Make sure the data file is on an isolated individual volume (used VMware vVol)
-- Don't care where the t-log goes either
-- Can also use SIMPLE RECOVERY here since we only care about the data file behavior
CREATE DATABASE [ShrinkTest] ON PRIMARY (
	NAME = N'ShrinkTest', 
	FILENAME = N'U:\Data\ShrinkTest.mdf', 
	SIZE = 8192KB, 
	FILEGROWTH = 1024KB 
)
LOG ON ( 
	NAME = N'ShrinkTest_log', 
	FILENAME = N'L:\log\ShrinkTest_log.ldf', 
	SIZE = 8192KB, 
	FILEGROWTH = 65536KB
)
GO
ALTER DATABASE [ShrinkTest] SET RECOVERY SIMPLE 
GO

USE [ShrinkTest];
GO
 
SET NOCOUNT ON;
GO



-- Quick database size check
SELECT
	'Size Check - no data loaded' AS Label,
	@@SERVERNAME, 
    DB_NAME(database_id) as [Database Name],
    SUM(size) * 8.0 / 1024 / 1024 as 'Size (GB)'
FROM sys.master_files
WHERE DB_NAME(database_id) = 'ShrinkTest'
GROUP BY database_id
ORDER BY DB_NAME(database_id);
GO

-- Create filler table at the 'front' of the data file
CREATE TABLE [FillerTable] (
    [c0] BIGINT IDENTITY (1, 1), 
	[c1] UNIQUEIDENTIFIER, [c2] UNIQUEIDENTIFIER, [c3] UNIQUEIDENTIFIER,
	[c4] UNIQUEIDENTIFIER, [c5] UNIQUEIDENTIFIER, [c6] UNIQUEIDENTIFIER,
	[c7] UNIQUEIDENTIFIER, [c8] UNIQUEIDENTIFIER, [c9] UNIQUEIDENTIFIER
);
GO



-----
PRINT '---'
PRINT 'Loading FillerTable - Start'
GO
 
-- Fill up the filler table
INSERT INTO [FillerTable] (c1, c2, c3, c4, c5, c6, c7, c8, c9)
SELECT TOP 50000 NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID()
FROM sys.objects t1
CROSS APPLY sys.columns t2
GO 2000



-- Quick database size check
SELECT
	'Filler Table Loaded' AS Label,
	@@SERVERNAME, 
    DB_NAME(database_id) as [Database Name],
    SUM(size) * 8.0 / 1024 / 1024 as 'Size (GB)'
FROM sys.master_files
WHERE DB_NAME(database_id) = 'ShrinkTest'
GROUP BY database_id
ORDER BY DB_NAME(database_id);
GO



-----
PRINT '---'
PRINT 'Loading ProdTable - Start'
GO

-- Create the production table, which will be 'after' the filler table in the data file
CREATE TABLE [ProdTable] (
    [c0] BIGINT IDENTITY (1, 1), 
	[c1] UNIQUEIDENTIFIER, [c2] UNIQUEIDENTIFIER, [c3] UNIQUEIDENTIFIER,
	[c4] UNIQUEIDENTIFIER, [c5] UNIQUEIDENTIFIER, [c6] UNIQUEIDENTIFIER,
	[c7] UNIQUEIDENTIFIER, [c8] UNIQUEIDENTIFIER, [c9] UNIQUEIDENTIFIER
);
CREATE CLUSTERED INDEX [prod_cl] ON [ProdTable] ([c0]);
GO
 
INSERT INTO [ProdTable] (c1, c2, c3, c4, c5, c6, c7, c8, c9)
SELECT TOP 50000 NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID(), NEWID()
FROM sys.objects t1
CROSS APPLY sys.columns t2
GO 2000



-- Quick database size check
SELECT
	'Prod Table Loaded' AS Label,
	@@SERVERNAME, 
    DB_NAME(database_id) as [Database Name],
    SUM(size) * 8.0 / 1024 / 1024 as 'Size (GB)'
FROM sys.master_files
WHERE DB_NAME(database_id) = 'ShrinkTest'
GROUP BY database_id
ORDER BY DB_NAME(database_id);
GO

------------------------------------------
-- STOP - check FlashArray volume
--
-- BE SURE TO WAIT SEVERAL MINUTES
-- FA space reporting can take a few 
-- minutes to catch up.
--
/*
vvol-ayun-sql22-01-261d769b-vg / ShrinkTest
Volume Size - 234.00 G 
Virtual - 31.11 G
Data Reduction - 1.2 to 1
Unique - 25.75 G
Snapshots - 0.00
Total - 25.75 G

Size Check - no data loaded	ayun-sql22-01	ShrinkTest	0.01562500000
Filler Table Loaded	ayun-sql22-01	ShrinkTest	17.33398437500
Prod Table Loaded	ayun-sql22-01	ShrinkTest	33.20996093750
*/
------------------------------------------

------------------------------------------
-- SETUP END
------------------------------------------




------------------------------------------
-- TEST START
------------------------------------------
USE [ShrinkTest];
GO
 
SET NOCOUNT ON;
GO



-- Quick database size check
SELECT
	'Initial Size Check' AS Label,
	@@SERVERNAME, 
    DB_NAME(database_id) as [Database Name],
    SUM(size) * 8.0 / 1024 / 1024 as 'Size (GB)'
FROM sys.master_files
WHERE DB_NAME(database_id) = 'ShrinkTest'
GROUP BY database_id
ORDER BY DB_NAME(database_id);
GO
 
-- Check the fragmentation of the production table
SELECT
    [avg_fragmentation_in_percent]
FROM sys.dm_db_index_physical_stats (
    DB_ID (N'ShrinkTest'), OBJECT_ID (N'ProdTable'), 1, NULL, 'LIMITED');
GO

/*
Label	(No column name)	Database Name	Size (GB)
Initial Size Check	ayun-sql22-01	ShrinkTest	33.21093750000

[avg_fragmentation_in_percent]
0.193206936241711
*/



------------------------------------------
-- STOP - check FlashArray volume
--
-- BE SURE TO WAIT SEVERAL MINUTES
-- FA space reporting can take a few 
-- minutes to catch up.
/*
vvol-ayun-sql22-01-261d769b-vg / ShrinkTest
Volume Size - 234.00 G 
Virtual - 31.11 G
Data Reduction - 1.2 to 1
Unique - 25.75 G
Snapshots - 0.00
Total - 25.75 G
*/
------------------------------------------



------------------------------------------
-- Drop the filler table, creating equivalent free space at the 'front' of the data file
DROP TABLE [FillerTable];
GO
 
-----
-- Quick database size check
SELECT
	'After Filler Table Drop' AS Label,
	@@SERVERNAME, 
    DB_NAME(database_id) as [Database Name],
    SUM(size) * 8.0 / 1024 / 1024 as 'Size (GB)'
FROM sys.master_files
WHERE DB_NAME(database_id) = 'ShrinkTest'
GROUP BY database_id
ORDER BY DB_NAME(database_id);
GO

/*
Label	(No column name)	Database Name	Size (GB)
After Filler Table Drop	ayun-sql22-01	ShrinkTest	33.21093750000
*/

------------------------------------------
-- STOP - check FlashArray volume
--
-- BE SURE TO WAIT SEVERAL MINUTES
-- FA space reporting can take a few 
-- minutes to catch up.
/*
vvol-ayun-sql22-01-261d769b-vg / ShrinkTest
Volume Size - 234.00 G 
Virtual - 31.40 G
Data Reduction - 1.2 to 1
Unique - 25.92 G
Snapshots - 0.00
Total - 25.92 G
*/



------------------------------------------
-- Shrink the database
DBCC SHRINKDATABASE ([ShrinkTest]);
GO

-----
-- Quick database size check
SELECT
	'After SHRINK Database' AS Label,
	@@SERVERNAME, 
    DB_NAME(database_id) as [Database Name],
    SUM(size) * 8.0 / 1024 / 1024 as 'Size (GB)'
FROM sys.master_files
WHERE DB_NAME(database_id) = 'ShrinkTest'
GROUP BY database_id
ORDER BY DB_NAME(database_id);
GO


/*
DbId	FileId	CurrentSize	MinimumSize	UsedPages	EstimatedPages
18	1	2080560	1024	2051296	2051296
18	2	1024	1024	1024	1024


Label	(No column name)	Database Name	Size (GB)
After SHRINK Database	ayun-sql22-01	ShrinkTest	15.88122558593
*/

------------------------------------------
-- STOP - check FlashArray volume
--
-- BE SURE TO WAIT SEVERAL MINUTES
-- FA space reporting can take a few 
-- minutes to catch up.
/*

vvol-ayun-sql22-01-261d769b-vg / ShrinkTest
Volume Size - 234.00 G 
Virtual - 15.94 G
Data Reduction - 1.1 to 1
Unique - 13.85 G
Snapshots - 0.00
Total - 13.85 G

avg_fragmentation_in_percent
98.1297196171925
*/
------------------------------------------
 
-- Check the index fragmentation again
SELECT
    [avg_fragmentation_in_percent]
FROM sys.dm_db_index_physical_stats (
    DB_ID (N'ShrinkTest'), OBJECT_ID (N'ProdTable'), 1, NULL, 'LIMITED');
GO