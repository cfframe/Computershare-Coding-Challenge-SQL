----------------------------------------------------------------------------------------------------
-- Computershare Challenge entry from Colin Frame
--
-- ASSUMPTIONS
-- Targets SQL Server 2017 or above (untested with lower)
-- User has permissions to create databases 
-- It's acceptable to create and use the database named in the CREATE DATABASE statement
--
-- WHAT THIS CODE WILL DO
-- Create database
-- Create splitter function (thanks to Jeff Moden, https://www.sqlservercentral.com/articles/tally-oh-an-improved-sql-8k-“csv-splitter”-function)
-- Create procedure to process data line
-- Use sample data to exercise procedure
--
-- WHAT IT WON'T DO
-- No validation
--
-- USAGE FOR OTHER SAMPLE DATA (after running main script below)
-- Use the SQL immediately below as a template, populate the @RawData variable.
--
/*
    DECLARE 
        @RawData VARCHAR(8000),
        @Result VARCHAR(8000);

    SELECT @RawData = '18.93,20.25,17.05,16.59,21.09,16.22,21.43,27.13,18.62,21.31,23.96,25.52,19.64,23.49,15.28,22.77,23.1,26.58,27.03,23.75,27.39,15.93,17.83,18.82,21.56,25.33,25,19.33,22.08,24.03';

    EXEC dbo.IdentifyLargestProfitFromMonthData @RawData, @Result OUTPUT;

    SELECT [Result 1] = @Result;
*/
-- CLEAN UP
/*
    USE master;
    DROP DATABASE BasicShareProfitAttemptFromColinFrame;
*/
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
-- Create database
----------------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT * FROM master.sys.databases d WHERE name = 'BasicShareProfitAttemptFromColinFrame')
BEGIN
    CREATE DATABASE BasicShareProfitAttemptFromColinFrame;
END; 
GO

USE BasicShareProfitAttemptFromColinFrame;
GO

----------------------------------------------------------------------------------------------------
-- Create splitter function
----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.DelimitedSplit8K') IS NOT NULL
    DROP FUNCTION [dbo].[DelimitedSplit8K];
GO

CREATE FUNCTION [dbo].[DelimitedSplit8K]
    (@StringToSplit VARCHAR(8000), @Delimiter CHAR(1))

--WARNING!!! DO NOT USE MAX DATA-TYPES HERE!  IT WILL KILL PERFORMANCE!

RETURNS TABLE WITH SCHEMABINDING AS

RETURN
    -- "Inline" CTE Driven "Tally Table" produces values from 1 up to 10,000...
    -- enough to cover VARCHAR(8000)
    WITH E1(N) AS 
    (
        SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL
        SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL
        SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
    ),                          --10E+1 or 10 rows
    E2(N) AS 
    (
        SELECT 1 FROM E1 a FULL OUTER JOIN E1 b ON a.N = b.N
    ), --10E+2 or 100 rows
    E4(N) AS 
    (
        SELECT 1 FROM E2 a FULL OUTER JOIN E2 b ON a.N = b.N
    ), --10E+4 or 10,000 rows max
    cteTally(N) AS 
    (
        -- This provides the "base" CTE and limits the number of rows right up front
        -- for both a performance gain and prevention of accidental "overruns"
        SELECT TOP (ISNULL(DATALENGTH(@StringToSplit), 0)) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM E4
    ),
    cteStart(N1) AS 
    (
        --==== This returns N+1 (starting position of each "element" just once for each delimiter)
        SELECT 1 
        
        UNION ALL
        
        SELECT t.N + 1 
        FROM cteTally t 
        WHERE SUBSTRING(@StringToSplit, t.N, 1) = @Delimiter
    ),
    cteLen(N1, L1) AS
    (
        -- Return start and length (for use in substring)
        SELECT 
            s.N1,
            ISNULL(NULLIF(CHARINDEX(@Delimiter, @StringToSplit, s.N1), 0) - s.N1, 8000)
        FROM cteStart s
    )
    -- Do the actual split. The ISNULL/NULLIF combo handles the length for the final element when no delimiter is found.
    SELECT 
        ItemNumber = ROW_NUMBER() OVER(ORDER BY l.N1),
        Item       = SUBSTRING(@StringToSplit, l.N1, l.L1)
    FROM cteLen l
;
GO

----------------------------------------------------------------------------------------------------
-- Create procedure to process data line
----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.IdentifyLargestProfitFromMonthData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.IdentifyLargestProfitFromMonthData;
GO

CREATE PROCEDURE dbo.IdentifyLargestProfitFromMonthData 
( 
    @RawData VARCHAR(8000),
    @Result VARCHAR(8000) OUTPUT
)
AS
BEGIN
    DECLARE @DailyData AS TABLE 
    (
        DayNumber INT NOT NULL, 
        OpeningValue DECIMAL (5,2) NOT NULL
    );
    
    -- Set default result - no guarantee that a profit can be made
    SET @Result = 'No valid days to make a profit';

    -- Generate table of data
    INSERT @DailyData (DayNumber, OpeningValue)
        SELECT ItemNumber, Item 
        FROM [dbo].[DelimitedSplit8K] (@RawData, ',');

    -- Set-based calculation
    WITH ProfitOptions (BuyDay, SellDay, Profit) AS 
    (
        SELECT buy.DayNumber, sell.DayNumber, sell.OpeningValue - buy.OpeningValue
        FROM @DailyData buy 
        JOIN @DailyData sell ON buy.DayNumber < sell.DayNumber AND buy.OpeningValue < sell.OpeningValue
    ),
    Result (BuyDay, BuyValue, SellDay, SellValue) AS 
    (
        -- Need only 1 instance. Requirements do not stipulate which one if multiple possibilities with same max profit.
        SELECT TOP (1)
            po.BuyDay, BuyValue = CONVERT(VARCHAR(6), buy.OpeningValue),
            po.SellDay, SellValue = CONVERT(VARCHAR(6), sell.OpeningValue)
        FROM ProfitOptions po 
        JOIN @DailyData buy ON po.BuyDay = buy.DayNumber
        JOIN @DailyData sell ON po.SellDay = sell.DayNumber
        WHERE po.Profit = (SELECT MAX(ProfitOptions.Profit) FROM ProfitOptions)
        ORDER BY po.SellDay
    )
    SELECT 
        @Result = FORMATMESSAGE('%i(%s),%i(%s)', r.BuyDay, r.BuyValue, r.SellDay, r.SellValue)
    FROM Result r;
END
GO

----------------------------------------------------------------------------------------------------
-- Use sample data to exercise procedure
----------------------------------------------------------------------------------------------------
DECLARE 
    @RawData VARCHAR(8000),
    @Result VARCHAR(8000);

-- Sample 1
SELECT @RawData = '18.93,20.25,17.05,16.59,21.09,16.22,21.43,27.13,18.62,21.31,23.96,25.52,19.64,23.49,15.28,22.77,23.1,26.58,27.03,23.75,27.39,15.93,17.83,18.82,21.56,25.33,25,19.33,22.08,24.03';

EXEC dbo.IdentifyLargestProfitFromMonthData @RawData = @RawData, @Result = @Result OUTPUT;

SELECT [Result 1] = @Result;

SELECT @RawData = '22.74,22.27,20.61,26.15,21.68,21.51,19.66,24.11,20.63,20.96,26.56,26.67,26.02,27.20,19.13,16.57,26.71,25.91,17.51,15.79,26.19,18.57,19.03,19.02,19.97,19.04,21.06,25.94,17.03,15.61';

EXEC dbo.IdentifyLargestProfitFromMonthData @RawData = @RawData, @Result = @Result OUTPUT;

SELECT [Result 2] = @Result;


SELECT @RawData = '22.74,22.27,20.61';

EXEC dbo.IdentifyLargestProfitFromMonthData @RawData = @RawData, @Result = @Result OUTPUT;

SELECT [Result 3] = @Result;

