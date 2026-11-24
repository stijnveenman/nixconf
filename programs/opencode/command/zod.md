---
description: Run the zod DTO migration - list remaining decorated DTO classes, ask which to migrate, then migrate.
agent: build
---

Load and follow the `zod` skill via the skill tool. Then execute its workflow:

1. List all DTO classes across the airport-control NestJS-shipping domain libs that still need migrating (Phase 1).
2. Ask me which individual DTO class(es) to migrate (Phase 2).
3. Run the migration for the selected class(es) exactly as the skill describes, including verification (Phase 3).

$ARGUMENTS
