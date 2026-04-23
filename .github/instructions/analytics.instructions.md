---
applyTo: "lib/journalex_web/live/analytics/**,lib/journalex/analytics*.ex,lib/journalex_web/live/components/chart_component.ex,lib/journalex_web/live/components/analytics_filter_bar.ex,lib/journalex_web/live/components/kpi_card.ex"
---

# Analytics Visualization — Journalex

**IMPORTANT:** Before working on any file matched by this instruction, load the analytics-visualization skill by reading:

`c:\projects\journalex\.github\skills\analytics-visualization\SKILL.md`

That skill file is the single source of truth for:
- All locked architecture and design decisions (chart library, version filter design, done? filter, R-multiples, etc.)
- The full page catalog with routes, chart types, and which Analytics context functions each page uses
- The ECharts + Hooks.Chart integration pattern
- The `Journalex.Analytics` context function signatures and opts shape
- JSONB query patterns for metadata fields
- The shared component contracts (ChartComponent, AnalyticsFilterBar, KpiCard)
- The build order and current phase status
- The living Changelog of what has been built and decided

**After completing any analytics task**, append a dated entry to the `## Changelog` section of the SKILL.md file so the next agent has full context.
