/*
v1.0  - Jana Sattainathan [Twitter: @SQLJana] [Blog: sqljana.wordpress.com] - Initial Release - Feb.06.2019

0. Connect to a Utility database of your choice and create 2 linked servers to source and targets instances of compare
1. Replace all occurances of "1stInstanceName" with the SQL Server instance that will be the source of compare
2. Replace all occurances of "2ndInstanceName" with the SQL Server instance that will be the source of compare
3. Replace all occurances of "1stInstanceDBName" with the source DB to compare
4. Replace all occurances of "2ndInstanceDBName" with the target DB to compare
5. Search for DROP and drop all the existing tables if you are re-running
6. Run the script to see the differences
7. Optionally drop the linked servers that were created
*/


--Create linked server to 1st instance
EXEC master.dbo.sp_addlinkedserver
		@server = N'1stInstanceName',
		@srvproduct=N'SQL Server'

--Supply login details - You could use any user with adequate permissions
EXEC master.dbo.sp_addlinkedsrvlogin
		@rmtsrvname=N'1stInstanceName',
		@useself=N'False',
		@locallogin=NULL,
		@rmtuser=N'SA',
		@rmtpassword='********'

--Create linked server to 2nd instance
EXEC master.dbo.sp_addlinkedserver
		@server = N'2ndInstanceName',
		@srvproduct=N'SQL Server'

--Supply login details - You could use any user with adequate permissions
EXEC master.dbo.sp_addlinkedsrvlogin
		@rmtsrvname=N'2ndInstanceName',
		@useself=N'False',
		@locallogin=NULL,
		@rmtuser=N'SA',
		@rmtpassword='********'
GO


---------------------------------------------------------------------------



SELECT 'Tables/Views Differences';

--DROP TABLE DBA_TablesViews;

--Create a blank table to hold the data to compare/report
SELECT @@servername AS ServerName, *
INTO DBA_TablesViews
FROM INFORMATION_SCHEMA.TABLES
WHERE 0=1;

--Truncate in case this already exists
TRUNCATE TABLE DBA_TablesViews;

--Get 1st instance data into our table
INSERT INTO DBA_TablesViews
SELECT '1stInstanceName' as ServerName, *
FROM [1stInstanceName].[1stInstanceDBName].INFORMATION_SCHEMA.TABLES;

--Get 2nd instance data into our table
INSERT INTO DBA_TablesViews
SELECT '2ndInstanceName' as ServerName, *
FROM [2ndInstanceName].[2ndInstanceDBName].INFORMATION_SCHEMA.TABLES;

--Uncomment if needed for review/reporting
/*
--This is all the collected data - summary
SELECT ServerName, COUNT(1) AS RowCnt
FROM DBA_TablesViews
GROUP BY ServerName;

--This is all the collected data - details
SELECT *
FROM DBA_TablesViews
ORDER BY TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE, ServerName;
*/

--Data that exists only in first or second but not both
SELECT 'Only in first' AS Difference, a.*
FROM
(
	SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM DBA_TablesViews WHERE ServerName  = '1stInstanceName'
	EXCEPT
	SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM DBA_TablesViews WHERE ServerName = '2ndInstanceName'
) AS a
UNION ALL
SELECT 'Only in second' AS Difference, b.*
FROM
(
	--SELECTs reversed
	SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM DBA_TablesViews WHERE ServerName = '2ndInstanceName'
	EXCEPT
	SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM DBA_TablesViews WHERE ServerName = '1stInstanceName'
) AS b;



---------------------------------------------------------------------------



SELECT 'Tables RowCount Differences';

--DROP TABLE DBA_TableRowCounts

--Create a blank table to hold the data to compare/report
SELECT *
INTO DBA_TableRowCounts
FROM
(
	SELECT
	   @@servername as ServerName,
	   SCHEMA_NAME(schema_id) AS [SchemaName],
	   t.name AS [TableName],
	   SUM(p.[rows]) AS [TotalRowCount]
	FROM
	   sys.tables AS t
	   JOIN
		  sys.partitions AS p
		  ON t.[object_id] = p.[object_id]
		      AND p.index_id IN (0,1)
	WHERE 0=1
	GROUP BY
	   SCHEMA_NAME(schema_id),
	   t.name
) a;

--Truncate in case this already exists
TRUNCATE TABLE DBA_TableRowCounts;

--Get 1st instance data into our table
INSERT INTO DBA_TableRowCounts
SELECT
   '1stInstanceName' as ServerName,
   s.name AS [SchemaName],
   t.name AS [TableName],
   SUM(p.[rows]) AS [TotalRowCount]
FROM
   [1stInstanceName].[1stInstanceDBName].sys.tables AS t
   INNER JOIN
		[1stInstanceName].[1stInstanceDBName].sys.schemas AS s
		ON s.[schema_id] = t.[schema_id]
   INNER JOIN
      [1stInstanceName].[1stInstanceDBName].sys.partitions AS p
      ON t.[object_id] = p.[object_id]
      AND p.index_id IN (0,1)
GROUP BY
   s.name,
   t.name;

--Get 2nd instance data into our table
INSERT INTO DBA_TableRowCounts
SELECT
   '2ndInstanceName' as ServerName,
   s.name AS [SchemaName],
   t.name AS [TableName],
   SUM(p.[rows]) AS [TotalRowCount]
FROM
   [2ndInstanceName].[2ndInstanceDBName].sys.tables AS t
   INNER JOIN
		[2ndInstanceName].[2ndInstanceDBName].sys.schemas AS s
		ON s.[schema_id] = t.[schema_id]
   INNER JOIN
      [2ndInstanceName].[2ndInstanceDBName].sys.partitions AS p
      ON t.[object_id] = p.[object_id]
      AND p.index_id IN (0,1)
GROUP BY
   s.name,
   t.name;

--Uncomment if needed for review/reporting
/*
--This is all the collected data - summary
SELECT ServerName, COUNT(1) AS RowCnt
FROM DBA_TableRowCounts
GROUP BY ServerName;

--This is all the collected data - details
SELECT *
FROM DBA_TableRowCounts
ORDER BY [SchemaName], [TableName], ServerName, [TotalRowCount];
*/

--Tables with row count differences
SELECT a.[SchemaName], a.[TableName],
		a.TotalRowCount AS DB1RowCount, b.TotalRowCount AS DB2RowCount,
		a.TotalRowCount-b.TotalRowCount AS RowCountDifference
FROM
	(
		SELECT * FROM DBA_TableRowCounts WHERE ServerName = '1stInstanceName'
	) a
	INNER JOIN
	(
		SELECT * FROM DBA_TableRowCounts WHERE ServerName = '2ndInstanceName'
	) b
	ON a.[SchemaName] = b.[SchemaName]
		AND a.[TableName] = b.[TableName]
WHERE
	ABS(a.TotalRowCount-b.TotalRowCount) > 0
ORDER BY
	ABS(a.TotalRowCount-b.TotalRowCount) DESC;





---------------------------------------------------------------------------



SELECT 'Tables Column Differences';

--DROP TABLE DBA_TableColumns

--Create a blank table to hold the data to compare/report
SELECT *
INTO DBA_TableColumns
FROM
(
	SELECT
		'1stInstanceName' as ServerName,
		s.name AS SchemaName,
		o.name AS TableName,
		(
		   SELECT c.name + ', '
		   FROM [1stInstanceName].[1stInstanceDBName].sys.columns c
		   WHERE t.object_id = c.object_id
		   ORDER BY c.column_id
		   FOR XML PATH('')
		) AS Columns,
		t.create_date,
		t.modify_date,
		t.type_desc
	FROM [1stInstanceName].[1stInstanceDBName].sys.tables t
		INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.objects o
			ON t.object_id = o.object_id
		INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.schemas AS s
			ON s.[schema_id] = t.[schema_id]
	WHERE
		o.is_ms_shipped = 0
		AND 0=1
) a;

--Get 1st instance data into our table
INSERT INTO DBA_TableColumns
SELECT
	'1stInstanceName' as ServerName,
	s.name AS SchemaName,
	o.name AS TableName,
	(
		SELECT c.name + ', '
		FROM [1stInstanceName].[1stInstanceDBName].sys.columns c
		WHERE t.object_id = c.object_id
		ORDER BY c.column_id
		FOR XML PATH('')
	) AS Columns,
	t.create_date,
	t.modify_date,
	t.type_desc
FROM [1stInstanceName].[1stInstanceDBName].sys.tables t
	INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.objects o
		ON t.object_id = o.object_id
	INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.schemas AS s
		ON s.[schema_id] = t.[schema_id]
WHERE
	o.is_ms_shipped = 0;

--Get 2nd instance data into our table
INSERT INTO DBA_TableColumns
SELECT
	'2ndInstanceName' as ServerName,
	s.name AS SchemaName,
	o.name AS TableName,
	(
		SELECT c.name + ', '
		FROM [2ndInstanceName].[2ndInstanceDBName].sys.columns c
		WHERE t.object_id = c.object_id
		ORDER BY c.column_id
		FOR XML PATH('')
	) AS Columns,
	t.create_date,
	t.modify_date,
	t.type_desc
FROM [2ndInstanceName].[2ndInstanceDBName].sys.tables t
	INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.objects o
		ON t.object_id = o.object_id
	INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.schemas AS s
		ON s.[schema_id] = t.[schema_id]
WHERE
	o.is_ms_shipped = 0;

--Uncomment if needed for review/reporting
/*
--This is all the collected data - summary
SELECT ServerName, COUNT(1) AS RowCnt
FROM DBA_TableColumns
GROUP BY ServerName;

--This is all the collected data - details
SELECT *
FROM DBA_TableColumns
ORDER BY [SchemaName], [TableName], ServerName;
*/

--Tables with column differences
SELECT a.[SchemaName], a.[TableName],
		a.Columns AS DB1Columns, b.Columns AS DB2Columns,
		ABS(LEN(a.Columns)-LEN(b.Columns)) AS HasDifference
FROM
	(
		SELECT * FROM DBA_TableColumns WHERE ServerName = '1stInstanceName'
	) a
	INNER JOIN
	(
		SELECT * FROM DBA_TableColumns WHERE ServerName = '2ndInstanceName'
	) b
	ON a.[SchemaName] = b.[SchemaName]
		AND a.[TableName] = b.[TableName]
WHERE
	ABS(LEN(a.Columns)-LEN(b.Columns))  > 0
ORDER BY
	ABS(LEN(a.Columns)-LEN(b.Columns)) DESC;

---------------------------------------------------------------------------



SELECT 'Index Differences';


--DROP TABLE DBA_TableIndexes

--Create a blank table to hold the data to compare/report
SELECT  *
INTO DBA_TableIndexes
FROM
	(
		SELECT
			@@servername AS ServerName,
			SchemaName = s.name,
			TableName = t.name,
			IndexName = ind.name,
			IndexId = ind.index_id,
			IndexType= ind.type_desc,
			ind.*
		FROM
			 [1stInstanceName].[1stInstanceDBName].sys.indexes ind
		INNER JOIN
			[1stInstanceName].[1stInstanceDBName].sys.tables t ON ind.object_id = t.object_id
			INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.schemas AS s
				ON s.[schema_id] = t.[schema_id]
		WHERE
			t.is_ms_shipped = 0
		--ORDER BY
		--	 t.name, ind.name, ind.index_id
	 ) a
WHERE 0=1;

--Truncate in case this already exists
TRUNCATE TABLE DBA_TableIndexes;

--Get 1st instance data into our table
INSERT INTO DBA_TableIndexes
SELECT
	'1stInstanceName' AS ServerName,
	SchemaName = s.name,
	TableName = t.name,
	IndexName = ind.name,
	IndexId = ind.index_id,
	IndexType= ind.type_desc,
	ind.*
FROM
	[1stInstanceName].[1stInstanceDBName].sys.indexes ind
	INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.tables t
		ON ind.object_id = t.object_id
	INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.schemas AS s
		ON s.[schema_id] = t.[schema_id]
WHERE
	t.is_ms_shipped = 0
ORDER BY
	 t.name, ind.name, ind.index_id;

--Get 2nd instance data into our table
INSERT INTO DBA_TableIndexes
SELECT
	'2ndInstanceName' AS ServerName,
	SchemaName = s.name,
	TableName = t.name,
	IndexName = ind.name,
	IndexId = ind.index_id,
	IndexType= ind.type_desc,
	ind.*
FROM
	[2ndInstanceName].[2ndInstanceDBName].sys.indexes ind
	INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.tables t
		ON ind.object_id = t.object_id
	INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.schemas AS s
		ON s.[schema_id] = t.[schema_id]
WHERE
	t.is_ms_shipped = 0
ORDER BY
	 t.name, ind.name, ind.index_id;

--Uncomment if needed for review/reporting
/*
--This is all the collected data - summary
SELECT ServerName, COUNT(1) AS RowCnt
FROM DBA_TableIndexes
GROUP BY ServerName;

--This is all the collected data - details
SELECT *
FROM DBA_TableIndexes
ORDER BY TableName, IndexName, IndexType, ServerName;
*/

--Data that exists only in first or second but not both
SELECT 'Only in first' AS Difference, a.*
FROM
(
	SELECT TableName, IndexName, IndexType FROM DBA_TableIndexes WHERE ServerName  = '1stInstanceName'
	EXCEPT
	SELECT TableName, IndexName, IndexType FROM DBA_TableIndexes WHERE ServerName = '2ndInstanceName'
) AS a
UNION ALL
SELECT 'Only in second' AS Difference, b.*
FROM
(
	--SELECTs reversed
	SELECT TableName, IndexName, IndexType FROM DBA_TableIndexes WHERE ServerName = '2ndInstanceName'
	EXCEPT
	SELECT TableName, IndexName, IndexType FROM DBA_TableIndexes WHERE ServerName = '1stInstanceName'
) AS b



---------------------------------------------------------------------------



SELECT 'Index Column Differences';


--DROP TABLE DBA_TableIndexColumns

--Create a blank table to hold the data to compare/report
SELECT  *
INTO DBA_TableIndexColumns
FROM
	(
		SELECT
			'2ndInstanceName' as ServerName,
			s.name as SchemaName,
			o.name as TableName,
			i.name as IndexName,
			(
			   SELECT c.name + ', '
			   FROM [1stInstanceName].[1stInstanceDBName].sys.index_columns ic
				INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.columns c
					ON ic.column_id = c.column_id
						AND ic.object_id = c.object_id
			   WHERE i.object_id = ic.object_id AND i.index_id = ic.index_id
				 AND ic.is_included_column = 0
			   ORDER BY ic.index_column_id
			   FOR XML PATH('')
			) AS Key_Columns,
			(
			   SELECT c.name + ', '
			   FROM [1stInstanceName].[1stInstanceDBName].sys.index_columns ic
				INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.columns c
					ON ic.column_id = c.column_id
						AND ic.object_id = c.object_id
			   WHERE i.object_id = ic.object_id AND i.index_id = ic.index_id
				 AND ic.is_included_column = 1
			   ORDER BY ic.index_column_id
			   FOR XML PATH('')
			) AS IncludedColumns,
			i.type_desc as IndexType,
			i.is_unique as IsUnique,
			i.is_primary_key as IsPrimaryKey
		FROM [1stInstanceName].[1stInstanceDBName].sys.indexes i
			INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.objects o
				ON i.object_id = o.object_id
			INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.schemas AS s
					ON o.[schema_id] = s.[schema_id]
		WHERE
			o.is_ms_shipped = 0
			AND 0=1
	 ) a
WHERE 0=1;

--Truncate in case this already exists
TRUNCATE TABLE DBA_TableIndexColumns;

--Get 1st instance data into our table
INSERT INTO DBA_TableIndexColumns
SELECT
	'1stInstanceName' as ServerName,
	s.name as SchemaName,
	o.name as TableName,
	i.name as IndexName,
	(
		SELECT c.name + ', '
		FROM [1stInstanceName].[1stInstanceDBName].sys.index_columns ic
		INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.columns c
			ON ic.column_id = c.column_id
				AND ic.object_id = c.object_id
		WHERE i.object_id = ic.object_id AND i.index_id = ic.index_id
			AND ic.is_included_column = 0
		ORDER BY ic.index_column_id
		FOR XML PATH('')
	) AS Key_Columns,
	(
		SELECT c.name + ', '
		FROM [1stInstanceName].[1stInstanceDBName].sys.index_columns ic
		INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.columns c
			ON ic.column_id = c.column_id
				AND ic.object_id = c.object_id
		WHERE i.object_id = ic.object_id AND i.index_id = ic.index_id
			AND ic.is_included_column = 1
		ORDER BY ic.index_column_id
		FOR XML PATH('')
	) AS IncludedColumns,
	i.type_desc as IndexType,
	i.is_unique as IsUnique,
	i.is_primary_key as IsPrimaryKey
FROM [1stInstanceName].[1stInstanceDBName].sys.indexes i
	INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.objects o
		ON i.object_id = o.object_id
	INNER JOIN [1stInstanceName].[1stInstanceDBName].sys.schemas AS s
			ON o.[schema_id] = s.[schema_id]
WHERE
	o.is_ms_shipped = 0;

--Get 2nd instance data into our table
INSERT INTO DBA_TableIndexColumns
SELECT
	'2ndInstanceName' as ServerName,
	s.name as SchemaName,
	o.name as TableName,
	i.name as IndexName,
	(
		SELECT c.name + ', '
		FROM [2ndInstanceName].[2ndInstanceDBName].sys.index_columns ic
		INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.columns c
			ON ic.column_id = c.column_id
				AND ic.object_id = c.object_id
		WHERE i.object_id = ic.object_id AND i.index_id = ic.index_id
			AND ic.is_included_column = 0
		ORDER BY ic.index_column_id
		FOR XML PATH('')
	) AS Key_Columns,
	(
		SELECT c.name + ', '
		FROM [2ndInstanceName].[2ndInstanceDBName].sys.index_columns ic
		INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.columns c
			ON ic.column_id = c.column_id
				AND ic.object_id = c.object_id
		WHERE i.object_id = ic.object_id AND i.index_id = ic.index_id
			AND ic.is_included_column = 1
		ORDER BY ic.index_column_id
		FOR XML PATH('')
	) AS IncludedColumns,
	i.type_desc as IndexType,
	i.is_unique as IsUnique,
	i.is_primary_key as IsPrimaryKey
FROM [2ndInstanceName].[2ndInstanceDBName].sys.indexes i
	INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.objects o
		ON i.object_id = o.object_id
	INNER JOIN [2ndInstanceName].[2ndInstanceDBName].sys.schemas AS s
			ON o.[schema_id] = s.[schema_id]
WHERE
	o.is_ms_shipped = 0;

--Uncomment if needed for review/reporting
/*
--This is all the collected data - summary
SELECT ServerName, COUNT(1) AS RowCnt
FROM DBA_TableIndexColumns
GROUP BY ServerName;

--This is all the collected data - details
SELECT *
FROM DBA_TableIndexColumns
ORDER BY SchemaName, TableName, IndexName, Key_Columns, IncludedColumns, ServerName;
*/

--Tables with index column differences
SELECT COALESCE(a.[SchemaName],b.[SchemaName]) AS SchemaName,
		COALESCE(a.[TableName],b.[TableName]) AS TableName,
		CASE WHEN a.TableName IS NULL
			THEN 'Index is only in DB2'
			WHEN b.TableName IS NULL
			THEN 'Index is only in DB1'
			ELSE 'Index is in both with differences'
		END AS Diff,
		a.Key_Columns AS DB1KeyColumns,
		b.Key_Columns AS DB2KeyColumns,
		a.IncludedColumns AS DB1IncludedColumns, b.IncludedColumns AS DB2IncludedColumns,
		a.IndexType AS DB1IndexType, b.IndexType AS DB2IndexType,
		a.IsUnique AS DB1IsUnique, b.IsUnique AS DB2IsUnique,
		a.IsPrimaryKey AS DB1IsPrimaryKey, b.IsPrimaryKey AS DB2IsPrimaryKey
FROM
	(
		SELECT * FROM DBA_TableIndexColumns WHERE ServerName = '1stInstanceName'
	) a
	FULL JOIN
	(
		SELECT * FROM DBA_TableIndexColumns WHERE ServerName = '2ndInstanceName'
	) b
	ON a.[SchemaName] = b.[SchemaName]
		AND a.[TableName] = b.[TableName]
		AND a.[IndexName] = b.[IndexName]
WHERE
	a.IndexType <> b.IndexType
	OR COALESCE(a.Key_Columns,'~') <> COALESCE(b.Key_Columns,'~')
	OR COALESCE(a.IncludedColumns,'~') <> COALESCE(b.IncludedColumns,'~')
	OR a.IsUnique <> b.IsUnique
	OR a.IsPrimaryKey <> b.IsPrimaryKey
ORDER BY
	a.[SchemaName], a.[TableName], a.IndexName;



---------------------------------------------------------------------------



--Drop linked servers
/*
USE [master]
GO
EXEC master.dbo.sp_dropserver
     @server=N'1stInstanceName',
     @droplogins='droplogins'
GO 

EXEC master.dbo.sp_dropserver
     @server=N'2ndInstanceName',
     @droplogins='droplogins'
GO

*/
