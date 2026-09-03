# QueryVault Screenshot Plan

No screenshots are committed yet. Capture only from an actual QueryVault
Grafana instance after datasource, permission, and data validation pass. Do not
mock panels, paste secrets, expose connection settings, or use the unrelated
Voyager2 CapLab Grafana instance without explicit approval.

| Filename | UI state and required data | Caption | Documentation section |
| --- | --- | --- | --- |
| `docs/images/grafana-overview-period.png` | QueryVault Overview; source server/database selected; a current completed, post-safeguard period; all KPI and wait panels visible | QueryVault Overview summarizes one safely completed archive period through `qv_report`. | README, Key capabilities |
| `docs/images/grafana-overview-periods-classification.png` | Overview scrolled to Available Archived Periods and Period Classifications; at least three completed periods; `Unclassified (not recorded)` visible | Available periods are selectable; classification remains explicitly unrecorded in V1. | GRAFANA_REPORTING_PLAN, QueryVault Overview |
| `docs/images/grafana-period-comparison.png` | Period Comparison; two equal-duration post-safeguard periods; delta KPIs and workload table visible | Baseline and comparison workload deltas use source-native query identity within one source database. | QueryVault-Guide, Compare periods |
| `docs/images/grafana-query-regressions.png` | Period Comparison scrolled to regressed/improved queries and plan changes; non-empty rows | Query-level regressions, improvements, and observed plan-count changes. | GRAFANA_REPORTING_PLAN, Period Comparison |
| `docs/images/grafana-wait-analysis.png` | Wait Analysis; selected period and baseline with wait data; category selected; distribution and delta panels visible | Wait distribution and baseline change use archived Query Store wait categories. | GRAFANA_REPORTING_PLAN, Wait Analysis |
| `docs/images/grafana-wait-contributors.png` | Wait Analysis scrolled to top contributing queries; query previews readable but no sensitive business text | Top queries contributing to the selected archived wait category. | Troubleshooting, Wait panels |
| `docs/images/grafana-query-detail.png` | Query Detail; one non-sensitive query; multiple post-safeguard periods; KPI, timeline, and wait profile visible | Query Detail tracks executions, resources, waits, and plans across selected archive periods. | GRAFANA_REPORTING_PLAN, Query Detail |
| `docs/images/grafana-plan-metadata.png` | Query Detail scrolled to plan metadata; period/query/plan IDs visible; XML payload not displayed | Grafana lists plan identifiers and metadata while plan rendering remains an SSMS responsibility. | Grafana-Setup, Native Showplan XML |
| `docs/images/ssms-showplan-xml-result.png` | SSMS execution of `qv_report.usp_GetShowplanXml`; IDs from preceding screenshot; XML link visible; no credential UI | The reporting procedure returns native SQL Server Showplan XML. | Grafana-Setup, Native Showplan XML |
| `docs/images/ssms-showplan-opened.png` | The exported `.sqlplan` opened in SSMS graphical plan viewer | Native Showplan XML exported from QueryVault opens directly in SSMS. | Architecture, System boundary |

Before capture, confirm the selected periods are not Voyager2 RunIDs 1, 2, 5,
6, 7, 8, 9, 14, or 15. Use a test workload or redact query text through source
data choice—not by editing the screenshot into a misleading state. Record the
Grafana version and selected period IDs in the pull request description.
