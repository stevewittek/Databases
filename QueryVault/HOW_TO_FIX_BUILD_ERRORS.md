# How to Fix Build Errors

## Problem
The SSDT project is trying to validate deployment scripts and SQL Agent job scripts as database objects, causing 89 build errors.

## Solution

### Step 1: Close Visual Studio
Close the QueryVault solution in Visual Studio (the project file is locked while the solution is open).

### Step 2: Run the Fix Script
Open PowerShell in the `QueryVault` directory and run:

```powershell
.\FixBuildErrors.ps1
```

This script will:
- Change deployment scripts from `<Build>` to `<None>` (Deploy.sql, Deploy_Standalone.sql)
- Change job creation scripts from `<Build>` to `<None>` (CreateArchiveJob_*.sql)
- Change utility scripts from `<Build>` to `<None>` (EnableQueryStore.sql, FixSQL2019Compatibility.sql, etc.)
- Remove duplicate root-level Build entries

### Step 3: Reopen Visual Studio
Open the QueryVault solution again. All build errors should be resolved.

## What These Changes Do

**Build Items (`<Build Include="...">`)**
- Are validated by SSDT as database objects
- Must contain valid T-SQL for CREATE/ALTER statements
- Examples: Tables, stored procedures, functions, partition functions/schemes

**None Items (`<None Include="...">`)**
- Are included in the project for reference only
- Are NOT validated during build
- Examples: Deployment scripts, job creation scripts, utility scripts, documentation

## Affected Files

The following files will be changed from Build to None:
- `CreateArchiveJob_Template.sql`
- `CreateArchiveJob_AllDatabases.sql`
- `Deploy.sql` 
- `Deploy_Standalone.sql`
- `Jobs\CreateArchiveJob_AllDatabases.sql`
- `Jobs\CreateArchiveJob_Template.sql`
- `Scripts\Deploy.sql`
- `Scripts\Deploy_Standalone.sql`
- `EnableQueryStore.sql`
- `FixSQL2019Compatibility.sql`
- `CompleteSQL2019Fix.sql`
- `ups_ArchiveQueryStore.sql` (if exists - typo file)

Duplicate root-level Build references will also be removed (the correct subfolder references will remain).

## After the Fix

All database objects (tables, stored procedures, partitions) will still be validated during build, but deployment and utility scripts will be skipped.

You can still deploy the database using:
1. Visual Studio publish
2. PowerShell deployment scripts
3. SQLCMD deployment scripts
