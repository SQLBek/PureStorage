-----
-- Run this on the source server, to generate some fresh data
-- sample execution of the proc
USE AdventureWorks2016_EXT
GO

DECLARE @table1 dbo.tt_table1;

INSERT @table1 (c2, is_transient) SELECT TOP 1250 N'sample durable', 0 FROM sys.objects CROSS APPLY sys.columns;

INSERT @table1 (c2, is_transient) SELECT TOP 1250 N'sample non-durable', 1 FROM sys.objects CROSS APPLY sys.columns;

EXECUTE dbo.usp_ingest_table1 @table1=@table1;
GO 5


-----
-- summary query contents of both tables
SELECT @@SERVERNAME, 'memory-optimized table', COUNT(1), MAX(c1)
FROM AdventureWorks2016_EXT.dbo.table1;

SELECT @@SERVERNAME, 'non-durable table', COUNT(1), MAX(c1)
FROM AdventureWorks2016_EXT.dbo.temp_table1;
GO

-----
-- query memory-optimized table
SELECT TOP 10000 
	@@SERVERNAME, c1, c2 
FROM AdventureWorks2016_EXT.dbo.table1;
GO

-----
-- query non-durable table
SELECT TOP 10000 
	@@SERVERNAME, c1, c2 
FROM AdventureWorks2016_EXT.dbo.temp_table1;
GO

