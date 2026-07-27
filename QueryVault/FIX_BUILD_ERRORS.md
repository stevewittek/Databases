# How to Fix Build Errors in QueryVault.sqlproj

## Problem
The SQL Server Database Project is trying to build deployment scripts and SQL Agent job creation scripts that contain:
- SQLCMD commands (`:r` statements)  
- `msdb` database references for SQL Agent jobs
- Procedural batch scripts

These aren't compatible with SSDT build validation.

## Solution

### Option 1: Replace Project File (Recommended - Quick)

1. **Close Visual Studio** completely
2. Navigate to: `D:\Dev\QueryVault\Databases\QueryVault\`
3. **Rename** `QueryVault.sqlproj` to `QueryVault.sqlproj.old`
4. **Rename** `QueryVault_Fixed.sqlproj` to `QueryVault.sqlproj`
5. **Reopen Visual Studio** and reload the solution
6. **Rebuild** the project

The fixed project file:
- ✅ Includes all database objects (tables, stored procedures, partitions) for build validation
- ✅ Excludes deployment scripts and job scripts (they're marked as `<None>` instead of `<Build>`)
- ✅ Removes duplicate entries that were causing confusion

### Option 2: Manual Fix in Visual Studio

1. **Unload the QueryVault project**:
   - Right-click on QueryVault project → **Unload Project**

2. **Edit the project file**:
   - Right-click on QueryVault (unloaded) → **Edit Project File**

3. **Find the duplicate Build items** around line 95 and remove these entries:
   ```xml
   <Build Include="CreateArchiveJob_Template.sql" />
   <Build Include="CreateArchiveJob_AllDatabases.sql" />
   <Build Include="Deploy.sql" />
   <Build Include="Deploy_Standalone.sql" />
   <Build Include="Jobs\CreateArchiveJob_AllDatabases.sql" />
   <Build Include="Jobs\CreateArchiveJob_Template.sql" />
   <Build Include="Scripts\Deploy.sql" />
   <Build Include="Scripts\Deploy_Standalone.sql" />
   ```

4. **Also remove old root-level Build items** (e.g., `PartitionFunction.sql`, `RunMetadata.sql`) that don't have full paths

5. **Change deployment/job scripts to None**:
   ```xml
   <None Include="Scripts\Deploy.sql" />
   <None Include="Scripts\Deploy_Standalone.sql" />
   <None Include="Jobs\CreateArchiveJob_AllDatabases.sql" />
   <None Include="Jobs\CreateArchiveJob_Template.sql" />
   ```

6. **Save** and close the file
7. **Reload Project**: Right-click → Reload Project
8. **Rebuild** the solution

## Verify the Fix

After applying either option, build the project:
- **Build** → **Rebuild Solution**

You should see:
```
Build succeeded.
	0 Error(s)
	0 Warning(s)
```

All database objects (14 tables + 4 stored procedures) will build successfully.

## Important Notes

✅ **Database is already deployed** - The QueryVaultDB is live on your localhost and working perfectly!

✅ **Scripts still work** - The deployment and job creation scripts are still in the project, just not built/validated by SSDT. You can still:
- Run `Scripts\Deploy.sql` to redeploy
- Run `Scripts\DeployQueryVault.ps1` for PowerShell deployment
- Use job scripts in `Jobs\` folder to create SQL Agent jobs

✅ **No functionality lost** - This only affects build validation, not deployment or runtime functionality.

## What Each Script Does

| Script | Purpose | How to Use |
|--------|---------|------------|
| `Scripts\Deploy.sql` | SQLCMD deployment with `:r` includes | Use SQLCMD or SQL Server Management Studio |
| `Scripts\DeployQueryVault.ps1` | PowerShell automated deployment | Run from PowerShell |
| `Jobs\CreateArchiveJob_Template.sql` | Single database job | Execute in SSMS against `msdb` |
| `Jobs\CreateArchiveJob_AllDatabases.sql` | Multi-database job | Execute in SSMS against `msdb` |

These scripts are **deployment tools**, not database schema objects, so they don't need to be part of the SSDT build.
