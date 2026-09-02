---
name: zod
description: Use when migrating airport-control NestJS class-validator/@ApiProperty DTOs to Zod schemas. Triggers on "zod migration", "migrate dto", "migrate <package> dto", "zod skill". Lists remaining decorated DTO CLASSES, asks which individual class(es) to migrate, then runs the migration.
---

# Zod DTO Migration (airport-control)

Migrate decorated NestJS DTOs (`@ApiProperty` / `@ApiPropertyOptional` +
`class-validator`) into browser-safe Zod schemas so domain libraries stop
pulling `@nestjs/*` server runtime into browser bundles (root cause of the
`safety-level-drawer` build error).

Target pattern, canonically implemented in `wilbur/libs/aircraft-domain`:

- **Domain lib** exports Zod schemas (`.meta({...})` for OpenAPI) + `z.infer`
  types + enums. Deps shrink to `zod` only.
- **NestJS app** (`wilbur-rest-connector`) owns the runtime `createZodDto`
  classes (via `nestjs-zod`) and validates with `ZodValidationPipe`.

Always follow the three phases below in order. Operate ONLY on the DTO
class(es) the user selects.

---

## Phase 1 — List remaining DTO classes

Discover every DTO class that still needs migrating (i.e. still uses
`@ApiProperty`/`@ApiPropertyOptional` or `class-validator` decorators and is
NOT yet a `createZodDto` subclass).

Known NestJS-shipping domain libs (verify each still ships `@nestjs/swagger`
in its `package.json`):

- `wilbur/libs/smart-roads-domain`
- `wilbur/libs/irm-message`
- `wilbur/libs/flirt-domain`
- `wilbur/libs/flights-domain`

Run discovery (do not rely on this list being current — re-scan every time):

```bash
# Domain libs that still ship nestjs swagger
for p in wilbur/libs/*/package.json; do
  grep -q '"@nestjs/swagger"' "$p" && echo "$(dirname "$p")"
done

# Files with decorated DTOs still present
grep -rln "@ApiProperty\|ApiPropertyOptional\|class-validator" wilbur/libs/*/src

# Already-migrated markers (exclude these)
grep -rln "createZodDto" wilbur/libs/*/src
```

Then read each decorated DTO file and enumerate the individual `export class X`
declarations. A class is UNMIGRATED if it has `@ApiProperty`/
`@ApiPropertyOptional`/`class-validator` decorators and does NOT
`extends createZodDto(...)`.

Present the result as a table grouped by package, ordered smallest-effort
first (fewest classes / fewest cross-class dependencies first):

1. `smart-roads-domain` — `ceintuurbaan/measurement.dto.ts`
2. `irm-message` — `irm4/dto.ts` (`IRMMessageDTO`, `@deprecated`)
3. `flirt-domain` — `flights/flirt-flight.dto.ts`
4. `flights-domain` — `flights/{flight.dto.ts, arrival-flight.dto.ts, departure-flight.dto.ts}`

For each class list: file, class name, whether it `extends` another DTO class,
and any nested DTO-typed properties (so dependency order is visible).

## Phase 2 — Ask which class(es) to migrate

Use the `question` tool. Offer selection at the INDIVIDUAL DTO CLASS level
(`multiple: true`). Recommend the smallest remaining class first.

Enforce dependency integrity: if the user picks a class that `extends` or
nests another still-unmigrated class, warn that the dependency must be
migrated too (offer to include it). Migrate base/nested classes before the
classes that depend on them.

## Phase 3 — Run the migration (per selected class)

Reference implementation to mirror exactly:
`wilbur/libs/aircraft-domain/src/shared/schemas/aircraft-movements.ts` and
`wilbur/libs/aircraft-domain/src/server/dto/aircraft-movements.ts`.

1. **Create the Zod schema in the domain lib.** Add/extend a schema module
   (e.g. `src/schemas/<name>.ts`), one Zod object schema per DTO class.
   Compose inheritance with schema nesting or `.extend()`. Use Zod v4
   (`import { z } from 'zod'`).

2. **Map every validator 1:1 (exact parity):**
   | class-validator / decorator        | Zod                                   |
   | ---------------------------------- | ------------------------------------- |
   | `@IsString()`                      | `z.string()`                          |
   | `@IsInt()` / `type: 'integer'`     | `z.number().int()`                    |
   | `@IsBoolean()`                     | `z.boolean()`                         |
   | `@IsEnum(E)` / `enum: E`           | `z.enum(E)`                           |
   | `@IsISO8601()`                     | `z.iso.datetime({ offset: true })` (match precision if the original does) |
   | `@MaxLength(n)`                    | `.max(n)`                             |
   | `@MinLength(n)`                    | `.min(n)`                             |
   | `@IsArray()` + `@ValidateNested()` | `z.array(<childSchema>)`              |
   | nested object (`@Type(() => X)`)   | reference/nest the child Zod schema   |
   | `@IsDefined()` (required)          | required (no `.optional()`)           |
   | `@CanBeUndefined()` / optional     | `.optional()` or `.nullish()` — match the ORIGINAL field's optionality/nullability exactly |

3. **Preserve OpenAPI metadata + vendor extensions.** For each field, carry the
   original `@ApiProperty({ description, example, ... })` into
   `.meta({ description, example, title, 'x-path': ..., 'x-source': ... })`.
   `x-path`/`x-source` MUST be preserved (they are emitted into OpenAPI as
   vendor extensions). Do NOT use `.describe()` or `patchNestJsSwagger`.

4. **Export the inferred type from the domain `.` entrypoint:**
   `export const X = <schema>; export type X = z.infer<typeof X>;`
   This keeps the ~40 `import type { X }` consumers working unchanged.

5. **Move the runtime `createZodDto` class into `wilbur-rest-connector`.**
   Create it under `wilbur/apps/wilbur-rest-connector/src/modules/<area>/dto/`:
   ```ts
   import { createZodDto } from 'nestjs-zod';
   import { X } from '@schiphol-ac/<domain>';
   export class XDto extends createZodDto(X) {}
   ```
   Update the controller `@Body()` types to the app-local DTO class and switch
   the affected route (or module) to `nestjs-zod`'s `ZodValidationPipe`.
   RISK: `wilbur-rest-connector` registers a global
   `ValidationPipe({ whitelist: true })` (`src/index.ts`). Confirm its scope
   before swapping; keep both pipes coexisting if other non-migrated
   controllers depend on class-validator.

6. **Update runtime consumers** (only when migrating the flights DTOs):
   - `wilbur/apps/wilbur-rest-connector/src/modules/flights/flights.controller.ts`
     (`@Body() CISSArrivalFlight` / `CISSDepartureFlight`).
   - `wilbur/apps/wilbur-arrival-flights-projection/src/wilbur-arrival-flights.ts:40`
     — replace `plainToInstance(CISSArrivalFlight, flight)` with
     `CISSArrivalFlight.parse(flight)` (or `.passthrough` equivalent +
     `structuredClone`).
   These are the ONLY two runtime consumers of the flights DTO classes; every
   other consumer uses `import type`.

7. **Clean up the domain lib** once the class is fully migrated and no runtime
   reference remains: remove now-unused `@nestjs/common`, `@nestjs/core`,
   `@nestjs/swagger`, `nestjs-zod`, `class-validator`, `class-transformer`,
   `reflect-metadata`, and the local `api-property.ts` wrapper from the
   package's source and `package.json`.

## Verification (run after each migrated class)

1. **OpenAPI contract diff.** Snapshot `wilbur-rest-connector`'s generated
   OpenAPI JSON BEFORE starting and AFTER; diff for zero drift in schema,
   `description`, `example`, `required`, and `x-*` vendor extensions.
   (`wilbur-rest-api` only documents `security-officer`, so it is unaffected.)
2. `rush build --to <package>` and `rush build:check --to <package>`.
3. `rush test --to <package>` (esp. flights-domain builders/projections specs).
4. Final acceptance: `rush build --to safety-level-drawer` and
   `rush build:check` succeed WITHOUT any rsbuild `@nestjs/swagger` alias —
   confirms the browser-bundle root cause is resolved.
5. `rush prettier --branch origin/main --check`.

## Guardrails

- Migrate ONLY the DTO class(es) the user selected in Phase 2 (plus mandatory
  base/nested dependencies, with the user's consent).
- Do not commit, push, or open PRs unless explicitly asked.
- Do not weaken validation parity to make a build pass.
- Prefer editing existing schema/dto files over creating new packages.
- Report the validation commands run and any environment limitations.
