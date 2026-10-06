Use this for recurring reports, monitoring, and periodic summaries. The rules under "Scheduled tasks" apply.

**Good output.** One completed run shown to the user, and a stored prompt that lets a run with no memory of this conversation produce a consistent report. The stored prompt includes:
- The period, relative to the run time: "실행 시점 기준 지난 7일."
- The sources and searches to use, including the task, project, and file names found in the first run.
- The report outline and a fixed title pattern such as "주간 업무 보고 – {시작일}~{종료일}," so that each run can find the previous one.
- An instruction to find the previous run's report with search_context and to lead with the changes since then.
- The change signals below.
- What to report when nothing changed: the range checked and "변경 없음," briefly.
- Who reads the report: the user, or others (see "The eventual reader").

**Evidence only Sillog has: change signals.** New tasks; tasks with no activity for 7 days or more; new problems and newly resolved ones; LaterItems still open and how long they have been open; new files and downloads linked to tasks; commits since the last run; deadlines found in the records that fall within the next two periods.

**Routing.** For complex research within a run, split it across sub-agents.

완료 기준: one completed run shown to the user; a self-contained stored prompt with the period, sources, outline, change rule, change signals, and no-change rule; a proposal the user can approve.
