-----
-- Run this on the target server AFTER the snapshots have been
-- taken to verify new data now on target.
USE AdventureWorks2016_EXT
GO


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

