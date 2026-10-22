# Steven Wittek

**Senior SQL Server Database Engineer | SQL Performance, T-SQL and Database Platform Engineering**

I troubleshoot the SQL Server problems that sit between application code and production infrastructure: slow queries, plan regressions, difficult releases, and databases that need to stay reliable while they change.

I have **17+ years of SQL Server experience**, combining hands-on development and performance tuning with database administration, high availability, recovery, monitoring and deployment engineering. I've supported multi-terabyte environments and worked closely with software teams where query behavior and production reliability directly affect the business.

**Based in New Jersey.** Interested in senior SQL Server engineering, database platform and performance-focused roles in NJ, NYC and remote US.

[Engineering portfolio at Netherwood Data Partners](https://netherwooddatapartners.com/about/) | [LinkedIn](https://www.linkedin.com/in/steven-wittek-64956965) | [SQL Server articles](https://netherwooddatapartners.com/articles/)

## Featured engineering work

### [QueryVault: keep the performance evidence after Query Store history disappears](https://github.com/stevewittek/Databases)

QueryVault was built around a recurring performance-engineering problem: a load-test database gets refreshed, or Query Store retention removes older statistics, before the team has finished measuring the results of a long-running improvement effort.

It captures selected, completed **SQL Server Query Store** periods into a separate, retained archive. An engineer can preserve a baseline, make changes over weeks or months, and compare a later representative workload without depending on the original Query Store history remaining available.

The implementation includes **T-SQL stored procedures, partitioned columnstore history, retention safeguards, SQL Server Agent automation, a stable reporting interface and Grafana dashboards**.

| Archived workload overview | Before-and-after period comparison |
| :---: | :---: |
| [![Actual Grafana archive overview from a controlled SQL Server lab](https://raw.githubusercontent.com/stevewittek/Databases/master/docs/images/grafana-overview-period.jpg)](https://github.com/stevewittek/Databases/blob/master/docs/SCREENSHOT_PLAN.md) | [![Actual Grafana archived-period comparison from a controlled SQL Server lab](https://raw.githubusercontent.com/stevewittek/Databases/master/docs/images/grafana-period-comparison.jpg)](https://github.com/stevewittek/Databases/blob/master/docs/SCREENSHOT_PLAN.md) |

*Actual September 2026 SQL Server lab captures using the WideWorldImporters sample database, not fabricated production results. July-to-October quarterly benchmarking is an illustrative use case.*

**Explore:** [Implementation](https://github.com/stevewittek/Databases/tree/master/QueryVault) | [Why it exists](https://github.com/stevewittek/Databases/blob/master/docs/USE_CASES.md) | [All four Grafana views](https://github.com/stevewittek/Databases/blob/master/docs/SCREENSHOT_PLAN.md) | [Validation results and limits](https://github.com/stevewittek/Databases/blob/master/docs/VALIDATION_REPORT.md)

### PageMover: seeing what SQL Server index maintenance is doing

[PageMover](https://netherwooddatapartners.com/products/sql-server-index-maintenance-visualizer/) is a local SQL Server index and heap analysis utility with a Windows 95/98-inspired physical-page visualizer. It separates read-only inspection from maintenance, shows the proposed SQL, and requires deliberate confirmation before execution.

[![Actual PageMover application screenshot using synthetic offline demonstration data](https://raw.githubusercontent.com/stevewittek/Toolkit/main/assets/pagemover-demo.png)](https://github.com/stevewittek/Toolkit/blob/main/docs/PAGEMOVER_OVERVIEW.md)

*Actual PageMover interface; synthetic test values and index pages, not an operating production database.*

**Explore:** [Design, safety and demo walkthrough](https://github.com/stevewittek/Toolkit/blob/main/docs/PAGEMOVER_OVERVIEW.md) | [Product overview](https://netherwooddatapartners.com/products/sql-server-index-maintenance-visualizer/)

The source is currently private while release and security checks are completed. This is an **unsigned developer preview**, not a production-certified maintenance product.

### [Netherwood Data Partners: software and database engineering](https://github.com/stevewittek/netherwood-data-partners)

My independent engineering and software work includes SQL Server performance tools, data integrations, web applications and database platform experiments. The public repository contains the business website, articles and selected implementation details.

## Technical focus

| SQL Server | Platform and delivery |
| --- | --- |
| T-SQL, stored procedures, query tuning, execution plans | Always On availability groups, backup/restore, HA/DR |
| Indexing, statistics, Query Store, Extended Events | Azure SQL Database, Azure SQL Managed Instance |
| Wait analysis, production troubleshooting, monitoring | Git, Azure DevOps, SQL database projects, PowerShell, CI/CD |

## How I work

I start with evidence, not assumptions. Find the slow path, understand the workload and its constraints, make a controlled change, and compare the result with a credible baseline. I value code reviews, deployment safety, restore readiness and documentation that someone else can actually use.

**Connect:** [LinkedIn](https://www.linkedin.com/in/steven-wittek-64956965) | [Netherwood Data Partners](https://netherwooddatapartners.com/) | [QueryVault](https://github.com/stevewittek/Databases)
