---
name: time-tracking
description: Query the Cargas TimeTracking database on cargas-qa for sprint time entries. Shows what each developer is working on and how many hours they've logged. Use when Scott asks about sprint work, hours logged, or what his team is working on.
allowed-tools: Bash, Read
user-invocable: true
---

# Time Tracking Skill

Query the `TimeTracking` database on `cargas-qa` (Windows auth / `-E`) to see what developers are working on in a given sprint.

## Usage

```
/time-tracking                  # Queries current sprint for all direct reports
/time-tracking 2026.h           # Query a specific sprint by name
/time-tracking Ryan             # Filter to one developer
/time-tracking 2026.h Keith     # Sprint + developer filter
```

## Database Connection

```bash
sqlcmd -S cargas-qa -d TimeTracking -E -s"|" -W -Q "<query>"
```

- **Server:** `cargas-qa`
- **Database:** `TimeTracking`
- **Auth:** Windows (`-E`) — no username/password needed
- **Flags:** `-s"|"` pipe delimiter, `-W` removes trailing spaces

---

## Schema Reference

### `Sprint`
| Column | Type | Notes |
|--------|------|-------|
| id | int | PK |
| name | nvarchar | Sprint label, e.g. `2026.h` |
| startDate | datetime2 | |
| endDate | datetime2 | |
| description | nvarchar | Usually NULL |

### `Developer`
| Column | Type | Notes |
|--------|------|-------|
| id | int | PK |
| name | nvarchar | First name |
| email | nvarchar | e.g. `sdienner@cargas.com` |
| initials | nvarchar | e.g. `SD` |
| fullUserName | nvarchar | |
| loginUserName | varchar | |
| isAdmin | bit | |
| gitHubUserName | varchar | |
| teamId | int | NULL for most devs |

### `TimeEntry`
| Column | Type | Notes |
|--------|------|-------|
| id | int | PK |
| workDescription | nvarchar | Free-text description of work |
| sprintId | int | FK → Sprint.id |
| subcategoryId | int | FK → SubCategory.id |
| developerId | int | FK → Developer.id |
| jiraKey | nvarchar | e.g. `CAR-34189`, `CD-2446`, may be NULL |
| jiraKeyParent | varchar | Parent epic/story key |
| ParentSummary | varchar | Summary of parent ticket |
| priority | int | Sprint plan priority |
| CurrentWorkPriority | int | Live work priority (NULL = not yet active) |
| isPlanned | bit | 1 = was in sprint plan |
| isBillable | bit | 1 = billable to customer |
| plannedHours | int | Estimated hours |
| actualHours | decimal | Hours logged so far |
| carryOverHours | decimal | Hours carried from prior sprint |
| processId | int | FK → Process.id |
| WorkStartTime | datetime | When work started |
| is_epic | bit | 1 = this entry represents an epic |

### `SubCategory`
| Column | Type | Notes |
|--------|------|-------|
| id | int | PK |
| name | nvarchar | Short code, e.g. `Bug`, `Features`, `Meet`, `Learn` |
| description | nvarchar | |
| categoryId | int | FK → Category.id |

### `Category`
| Column | Type | Notes |
|--------|------|-------|
| id | int | PK |
| name | nvarchar | e.g. `Engineering`, `Admin`, `Custom` |

### Common SubCategory codes
| Code | Meaning |
|------|---------|
| Bug | Bug fix |
| Features | Feature work |
| Custom | Customer customization (CD-* tickets) |
| Cust-Disc | Customization discovery |
| Meet | Meetings |
| Admin | Administrative |
| Learn | Learning / study |
| School | Mentoring / pair programming |
| Rampup | Onboarding ramp-up |
| CR | Code review |
| Deploy | Deployments |
| Help-S | Support help |
| Help-C | Customer help |
| Disc | General discovery |
| Task | Task (non-bug, non-feature) |
| Switch | Task switching overhead |
| Unplan | Unplanned work |
| HF | Hotfix |
| Vac | Vacation |
| Leave | Other leave |
| IT | IT / infrastructure |
| Trouble | Troubleshooting |
| Release | Release work |
| Debt | Tech debt |
| Dev-tools | Developer tooling |
| SLOG | Slow log / perf investigation |
| Merge | PR merges |

---

## Scott's Direct Reports (Developer IDs)

| ID | Name | Email |
|----|------|-------|
| 1 | Keith | kmcellhenney@cargas.com |
| 3 | Nate | nkindrew@cargas.com |
| 5 | Tom | tgroff@cargas.com |
| 7 | Justin | jmadilla@cargas.com |
| 8 | Ryan | rschubert@cargas.com |
| 10 | Matt | mhahn@cargas.com |
| 11 | Jonathan | jbowman@cargas.com |
| 12 | Devin | dstrickler@cargas.com |
| 13 | Casey | cholland@cargas.com |
| 14 | Anne | anguyen@cargas.com |

Scott's own developer ID is **9** (`sdienner@cargas.com`). Exclude him from direct-report queries.

Direct report ID list for `WHERE` clauses: `(1, 3, 5, 7, 8, 10, 11, 12, 13, 14)`

---

## How to Execute

### Step 1: Resolve the sprint

If no sprint name is given, find the current or most recent active sprint:

```sql
SELECT TOP 1 id, name, startDate, endDate
FROM Sprint
WHERE startDate <= GETDATE()
ORDER BY startDate DESC
```

If a sprint name is given (e.g. `2026.h`):

```sql
SELECT id, name, startDate, endDate
FROM Sprint
WHERE name = '2026.h'
```

Note the sprint `id` for subsequent queries.

### Step 2: Query time entries

Full query for all direct reports in a sprint:

```sql
SELECT
    d.name AS Developer,
    te.jiraKey,
    te.workDescription,
    sc.name AS SubCategory,
    te.plannedHours,
    te.actualHours,
    te.isPlanned,
    te.isBillable,
    te.CurrentWorkPriority
FROM TimeEntry te
JOIN Developer d ON te.developerId = d.id
JOIN SubCategory sc ON te.subcategoryId = sc.id
WHERE te.sprintId = <sprintId>
  AND d.id IN (1, 3, 5, 7, 8, 10, 11, 12, 13, 14)
ORDER BY d.name, te.CurrentWorkPriority, te.priority
```

To filter to one developer, add: `AND d.name = 'Ryan'`

### Step 3: Format results

Group output by developer. For each developer, show:

1. **Planned/active Jira tickets** (where `jiraKey IS NOT NULL`) — these are the core work items
2. **Support and overhead** (Meet, Admin, Learn, Switch, etc.) — summarize as a block
3. **Total actual hours** logged this sprint

Use a markdown table per developer:

```markdown
## <Developer Name>
| Jira | Work | Category | Hrs |
|------|------|----------|-----|
| CAR-34189 | <workDescription or ticket summary> | Bug | 11.0 |
| — | Meetings & admin | Meet/Admin | 5.0 |
```

Add a **sprint summary table** at the top with hours per person:

```markdown
## Sprint 2026.h Summary (Apr 12–25)
| Developer | Jira Items | Actual Hrs |
|-----------|-----------|-----------|
| Keith | 5 | 47.5 |
| Ryan | 3 | 39.0 |
...
```

### Step 4: Flag anything notable

After the tables, call out:
- Anyone with very low logged hours relative to sprint length (possible time tracking gap)
- Anyone on vacation (Vac subcategory)
- Unplanned work spikes (high `Unplan` hours)
- Items with `CurrentWorkPriority = 1` (highest priority, actively in flight)

---

## Useful Supplementary Queries

### List all sprints (most recent first)
```sql
SELECT TOP 20 id, name, startDate, endDate
FROM Sprint
ORDER BY startDate DESC
```

### Hours summary by developer for a sprint
```sql
SELECT d.name, SUM(te.actualHours) AS totalHours
FROM TimeEntry te
JOIN Developer d ON te.developerId = d.id
WHERE te.sprintId = <sprintId>
  AND d.id IN (1, 3, 5, 7, 8, 10, 11, 12, 13, 14)
GROUP BY d.name
ORDER BY d.name
```

### Hours by subcategory for a developer in a sprint
```sql
SELECT sc.name AS SubCategory, SUM(te.actualHours) AS hours
FROM TimeEntry te
JOIN SubCategory sc ON te.subcategoryId = sc.id
WHERE te.sprintId = <sprintId>
  AND te.developerId = <devId>
GROUP BY sc.name
ORDER BY hours DESC
```

### Look up a specific developer ID
```sql
SELECT id, name, email FROM Developer WHERE name LIKE '%<name>%'
```
