:on error exit

/*
===============================================================================
SETUP: Create the target database and its schemas
===============================================================================
Purpose:
    Creates the database named by the sqlcmd variable DatabaseName and the
    three schemas (bronze, silver, gold) that all other scripts in this
    repository expect to exist.

    This script is idempotent and NON-destructive: if the database or a schema
    already exists it is left untouched. It never drops anything.

    The first line (:on error exit) makes sqlcmd stop at the first error, so
    that a failed CREATE DATABASE or USE can never lead to schemas being
    created in the wrong database.

Usage (DatabaseName is required; there is no default):
    sqlcmd -S <server> -E -b -v DatabaseName="DataWarehouse_Test" ^
           -i scripts\init_database.sql
===============================================================================
*/

USE master;
GO

IF DB_ID('$(DatabaseName)') IS NULL
    CREATE DATABASE [$(DatabaseName)];
GO

USE [$(DatabaseName)];
GO

/*
CREATE SCHEMA must be the only statement in its batch, so it is run through
EXEC. The IF checks keep the script re-runnable.
*/

IF SCHEMA_ID('bronze') IS NULL
    EXEC('CREATE SCHEMA bronze');
GO

IF SCHEMA_ID('silver') IS NULL
    EXEC('CREATE SCHEMA silver');
GO

IF SCHEMA_ID('gold') IS NULL
    EXEC('CREATE SCHEMA gold');
GO
