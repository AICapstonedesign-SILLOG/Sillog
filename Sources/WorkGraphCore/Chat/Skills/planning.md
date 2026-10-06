Use this for project plans, requirement documents, priorities, roadmaps, and schedules.

**Good output.** A plan that starts from where the work actually stands:
- 목표와 완료 조건: measurable, taken from the task goal or the requirement source.
- 현재 상태: done (with evidence), in progress, requested, and not started.
- 작업 분해: items with their predecessors and effort estimates with their bases. Name an owner only when a source names one.
- 일정: dates from sources, or derived from the stated estimates, with the critical path marked.
- 위험과 대응: from unresolved problems, external dependencies, and tight estimates.
- 지금 할 일: the first concrete step, with the file, page, or repository to reopen, taken from the last session on that task.
Make a CSV for checklists and roadmaps the user will track in a spreadsheet.

**Evidence only Sillog has.**
- Current state: each task's goal, status, last_active, recent session summaries, open LaterItems, problems without a resolution, AI-tool requests without a matching commit, and deadlines or requirements stated in notices, emails, or forms.
- Estimates from the user's own history: the all-time active time of comparable past tasks (the same task type, project, or kind of work). Example: "비슷한 이전 업무(결제 API 연동) 약 9시간 → 이번 작업 약 8~12시간 추정." When there is no comparable history, say so and give a range or [확인 필요].
- A reality check: the planned effort against the user's recent active time per week across tasks. Say plainly when the plan doesn't fit before the deadline.
- External dependencies found in the records, such as waiting for a file, a review, or an answer, each with its source.

**Routing.** For a complex project, delegate the current state to a context agent and the implementation constraints to a repository or research agent. When revising an earlier plan, find it and show what moved: completed, slipped (with the cause the records show), added, and dropped.

완료 기준: the current state is backed by evidence; every estimate states its basis; dependencies and risks are sourced; no date is invented; the plan has a first step the user can take now.
