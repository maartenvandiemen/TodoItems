<!--
SYNC IMPACT REPORT
==================
Version change: (new) → 1.0.0
Added sections:
  - Core Principles (I–V, all new)
  - Technology Stack
  - Deployment & Pipeline Policy
  - Governance
Templates reviewed:
  - .specify/templates/plan-template.md       ✅ Constitution Check gates applicable
  - .specify/templates/spec-template.md       ✅ In-memory testing & readability constraints apply
  - .specify/templates/tasks-template.md      ✅ Pipeline-update tasks MUST be included when infrastructure changes
Deferred TODOs: none
-->

# TodoItems Constitution

## Core Principles

### I. Demo-First Readability (NON-NEGOTIABLE)

The application is primarily a live-demo vehicle. Code MUST remain concise and easy to
follow on a projector screen. Concretely:

- ASP.NET Core Minimal APIs MUST be used for all HTTP endpoints; controller-based routing
  is forbidden.
- Entity Framework Core is the only permitted ORM/data-access layer.
- All API route registrations and EF Core model configuration MUST reside in as few files
  as possible — the goal is a single `Program.cs` entry point that an audience can read
  top-to-bottom without scrolling through multiple files.
- No over-engineering: abstractions (repositories, mediators, service layers) MUST NOT be
  introduced unless the feature explicitly requires them.

### II. Dependency Management

All NuGet package dependencies MUST be declared in the project's `.csproj` file.
Version locking MUST be enforced via `packages.lock.json` (NuGet lock files enabled).
Updating a dependency MUST regenerate the lock file and commit both changes together.

### III. In-Memory Testing Only (NON-NEGOTIABLE)

- Integration tests MUST use the ASP.NET Core in-memory test server
  (`WebApplicationFactory`) and an in-memory database (EF Core `UseInMemoryDatabase`).
- TestContainers and any test strategy that requires an external or containerized
  database are FORBIDDEN.
- Each test MUST be self-contained: seed its own data, make no assumptions about
  pre-existing database state, and leave no side-effects for other tests.

### IV. Azure Deployment — Dual Pipeline, Dual Mode

The application MUST be deployable to Azure App Service through two independent CI/CD
systems and two packaging modes:

- **CI systems**: GitHub Actions AND Azure Pipelines — both MUST be kept in sync and
  produce equivalent deployment outcomes.
- **Packaging modes**: non-Docker (direct publish) AND Docker (containerized image) —
  both variants MUST be maintained for each CI system.
- Deployment infrastructure MUST be defined as Bicep templates under `Deployment/`.

### V. Pipeline Maintenance (NON-NEGOTIABLE)

Whenever a new infrastructure component (e.g., a new Azure resource, a new project, a
new build step) is added to the solution, ALL four pipeline definitions MUST be updated
in the same pull request/commit:

- `.github/workflows/main.nodocker.yml`
- `.github/workflows/main.docker.yml`
- `azure-pipelines/nodocker.yml` (or equivalent)
- `azure-pipelines/docker.yml` (or equivalent)

A change that adds infrastructure without updating all pipelines MUST NOT be merged.

## Technology Stack

| Concern | Choice |
|---|---|
| Runtime | ASP.NET Core (latest LTS) — Minimal API style |
| ORM | Entity Framework Core |
| Language | C# |
| Dependency manifest | `.csproj` per project |
| Dependency lock | `packages.lock.json` |
| IaC | Bicep (`Deployment/`) |
| CI | GitHub Actions + Azure Pipelines |
| Hosting | Azure App Service (Docker and non-Docker) |

## Deployment & Pipeline Policy

- Bicep templates under `Deployment/` are the authoritative infrastructure definition.
- Non-Docker deployments use `dotnet publish` output; Docker deployments use the
  `Dockerfile` at the solution root or project level.
- Pipeline secrets (passwords, service principals, subscription IDs) MUST be stored as
  pipeline secrets / variable groups — never hard-coded.
- New Azure resources MUST have a corresponding Bicep file added to `Deployment/` and
  referenced from the appropriate `main.*.bicep` entry point.

## Governance

This constitution supersedes all other practices and preferences for this repository.
Any deviation requires a documented amendment following the process below:

1. Open a PR that edits `.specify/memory/constitution.md` with the proposed change.
2. Bump the version according to semantic versioning
   (MAJOR: breaking/removal · MINOR: new principle or section · PATCH: clarification).
3. Update the Sync Impact Report comment at the top of the file.
4. Update any templates in `.specify/templates/` that reference affected principles.
5. All PRs MUST verify compliance with the principles above before merging.

**Version**: 1.0.0 | **Ratified**: 2026-03-10 | **Last Amended**: 2026-03-10
