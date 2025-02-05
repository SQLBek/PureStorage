-----
-- Restore [AdventureWorks2016_EXT]
-- This is for the source server, aka the SOURCE. 
-- Change out paths to match your environment
USE [master]
RESTORE DATABASE [AdventureWorks2016_EXT] 
FROM 
	DISK = N'\\ayun-win2019\DB Backups\AdventureWorks\AdventureWorks2016_EXT.bak' 
WITH FILE = 1,  
	MOVE N'AdventureWorks2016_EXT_Data' TO N'M:\mssql\data\AdventureWorks2016_EXT_Data.mdf',  
	MOVE N'AdventureWorks2016_EXT_Log' TO N'M:\mssql\log\AdventureWorks2016_EXT_Log.ldf',  
	MOVE N'AdventureWorks2016_EXT_mod' TO N'M:\mssql\data\AdventureWorks2016_EXT_mod',  
	NOUNLOAD,  STATS = 5

GO

-----
-- Using MS Sample Script/documentation to make memory optimized objects and data
-- https://docs.microsoft.com/en-us/sql/relational-databases/in-memory-oltp/overview-and-usage-scenarios?view=sql-server-ver15
ALTER DATABASE [AdventureWorks2016_EXT] SET MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT=ON;
GO

USE [AdventureWorks2016_EXT]
GO

-- memory-optimized table
CREATE TABLE dbo.table1
( c1 INT IDENTITY PRIMARY KEY NONCLUSTERED,
  c2 NVARCHAR(MAX))
WITH (MEMORY_OPTIMIZED=ON);
GO
-- non-durable table
CREATE TABLE dbo.temp_table1
( c1 INT IDENTITY PRIMARY KEY NONCLUSTERED,
  c2 NVARCHAR(MAX))
WITH (MEMORY_OPTIMIZED=ON,
      DURABILITY=SCHEMA_ONLY);
GO

-- memory-optimized table type
CREATE TYPE dbo.tt_table1 AS TABLE
( c1 INT IDENTITY,
  c2 NVARCHAR(MAX),
  is_transient BIT NOT NULL DEFAULT (0),
  INDEX ix_c1 HASH (c1) WITH (BUCKET_COUNT=1024))
WITH (MEMORY_OPTIMIZED=ON);
GO

-- natively compiled stored procedure
CREATE PROCEDURE dbo.usp_ingest_table1
  @table1 dbo.tt_table1 READONLY
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC
    WITH (TRANSACTION ISOLATION LEVEL=SNAPSHOT,
          LANGUAGE=N'us_english')

  DECLARE @i INT = 1

  WHILE @i > 0
  BEGIN
    INSERT dbo.table1
    SELECT c2
    FROM @table1
    WHERE c1 = @i AND is_transient=0

    IF @@ROWCOUNT > 0
      SET @i += 1
    ELSE
    BEGIN
      INSERT dbo.temp_table1
      SELECT c2
      FROM @table1
      WHERE c1 = @i AND is_transient=1

      IF @@ROWCOUNT > 0
        SET @i += 1
      ELSE
        SET @i = 0
    END
  END

END
GO

-----
-- sample execution of the proc
USE AdventureWorks2016_EXT
GO

DECLARE @table1 dbo.tt_table1;

INSERT @table1 (c2, is_transient) SELECT TOP 10000 N'sample durable', 0 FROM sys.objects CROSS APPLY sys.columns;

INSERT @table1 (c2, is_transient) SELECT TOP 10000 N'sample non-durable', 1 FROM sys.objects CROSS APPLY sys.columns;

EXECUTE dbo.usp_ingest_table1 @table1=@table1;
GO 15


-----
-- summary query contents of both tables
SELECT 'memory-optimized table', COUNT(1)
FROM AdventureWorks2016_EXT.dbo.table1;

SELECT 'non-durable table', COUNT(1)
FROM AdventureWorks2016_EXT.dbo.temp_table1;
GO

-----
-- query memory-optimized table
SELECT c1, c2 
FROM AdventureWorks2016_EXT.dbo.table1;
GO

-----
-- query non-durable table
SELECT c1, c2 
FROM AdventureWorks2016_EXT.dbo.temp_table1;
GO

