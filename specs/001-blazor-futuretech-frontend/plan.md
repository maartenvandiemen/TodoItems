# Implementation Plan: Blazor Todo Frontend with FutureTech-Inspired Design

**Branch**: `001-blazor-futuretech-frontend` | **Date**: 2026-03-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-blazor-futuretech-frontend/spec.md`

## Summary

Add a standalone Blazor WebAssembly SPA (`TodoItems.Blazor`) that provides a futuristic, neon-themed todo management UI. The application calls the existing `TodoItems.Api` REST backend directly from the browser. The backend is extended with a CORS policy. The new project is colocated in the repository and deployed to a dedicated Azure App Service via all four CI/CD pipelines (GitHub Actions + Azure DevOps, Docker + non-Docker).

## Technical Context

**Language/Version**: C# / .NET 10.0 — Blazor WebAssembly (standalone, no server-side render)  
**Primary Dependencies**: `Microsoft.AspNetCore.Components.WebAssembly` 10.x; `HttpClient` (built-in); vanilla CSS with CSS custom properties (no external CSS framework)  
**Storage**: N/A — all state owned by `TodoItems.Api` backend; no local persistence  
**Testing**: bUnit for Blazor component unit tests (best-effort); existing integration test suite unchanged  
**Target Platform**: Browser (WASM) hosted on Azure App Service (Linux, DOTNETCORE|10.0)  
**Project Type**: Web application — SPA frontend  
**Performance Goals**: <2 s initial load on broadband; animated transitions ≤400 ms  
**Constraints**: Responsive 320 px–2560 px; 44 px minimum touch targets; no offline support; no pagination; API URL never hardcoded  
**Scale/Scope**: Single-user demo; ~8 Blazor components; 1 page

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | **Demo-First Readability** — Minimal API only; no repositories/mediators | ✅ PASS | `TodoItems.Api` is unchanged except for a 3-line CORS policy. Blazor project uses a single service class; components are self-contained and projector-friendly. |
| II | **Dependency Management** — `.csproj` + `packages.lock.json` | ✅ PASS | New `TodoItems.Blazor.csproj` will enable `RestorePackagesWithLockFile=true`; lock file committed with each dependency change. |
| III | **In-Memory Testing Only** | ✅ PASS | No database access in Blazor project. bUnit tests are fully in-memory. Existing API integration tests unaffected. |
| IV | **Azure Deployment — Dual Pipeline, Dual Mode** | ⚠️ ACTION REQUIRED | New project = new App Service. A new `blazorService.bicep` module and updates to `main.nodocker.webapp.bicep` and `main.docker.webapp.bicep` are required. Both CI systems must deploy the Blazor app. |
| V | **Pipeline Maintenance — All 4 pipelines in sync** | ⚠️ ACTION REQUIRED | ALL four pipeline definitions must be updated in the same PR: `.github/workflows/main.nodocker.yml`, `.github/workflows/main.docker.yml`, `.azuredevops/main.nodocker.yml`, `.azuredevops/main.docker.yml`. The shared `build.yml` files in both systems must also publish the Blazor artifact. |

**Gate Result**: PASS WITH REQUIRED ACTIONS — Violations IV and V are expected and justified: adding a new deployable project inherently requires new infrastructure and pipeline updates, which are explicitly permitted by the constitution when done correctly in a single PR.

## Project Structure

### Documentation (this feature)

```text
specs/001-blazor-futuretech-frontend/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Frontend Blazor WASM project (new)
TodoItems.Blazor/
├── Components/
│   ├── AddTodoForm.razor          # Input + submit with validation
│   ├── ErrorBanner.razor          # Error state with Retry + Dismiss
│   ├── FilterBar.razor            # All / Active / Completed filter buttons
│   ├── TodoItemRow.razor          # Single item: toggle + delete
│   └── TodoList.razor             # Animated list container
├── Models/
│   └── TodoItem.cs                # Client-side DTO (Id, Name, IsComplete)
├── Pages/
│   └── Home.razor                 # Main page — composition root
├── Services/
│   └── TodoApiService.cs          # HttpClient wrapper for all API calls
├── wwwroot/
│   ├── appsettings.json           # { "ApiBaseUrl": "<prod url>" }
│   ├── appsettings.Development.json  # { "ApiBaseUrl": "https://localhost:7001" }
│   ├── css/
│   │   └── app.css                # Global futuristic theme (CSS variables, animations)
│   └── index.html                 # SPA host page (dark bg, font imports)
├── App.razor
├── _Imports.razor
├── Program.cs                     # DI registration: HttpClient, TodoApiService
└── TodoItems.Blazor.csproj

# Backend — minimal changes (new)
TodoItems.Api/
└── Program.cs                     # Add CORS policy (3 lines) for Blazor origin

# Infrastructure — new / modified files
Deployment/
├── blazorService.bicep            # NEW — App Service for Blazor WASM (Linux dotnet)
├── main.nodocker.webapp.bicep     # MODIFIED — add blazorService module + outputs
└── main.docker.webapp.bicep       # MODIFIED — add blazorService module + docker param

# CI/CD pipelines — all four modified in same PR
.github/workflows/
├── build.yml                      # MODIFIED — also publish TodoItems.Blazor artifact
├── main.nodocker.yml              # MODIFIED — deploy Blazor to its App Service
└── main.docker.yml                # MODIFIED — deploy Blazor (Docker variant)

.azuredevops/
├── build.yml                      # MODIFIED — also publish todoItemsBlazor artifact
├── main.nodocker.yml              # MODIFIED — deploy Blazor in non-Docker pipeline
└── main.docker.yml                # MODIFIED — deploy Blazor in Docker pipeline

# Solution manifest
TodoItems.slnx                     # MODIFIED — add TodoItems.Blazor project reference
```

**Structure Decision**: Web application (Option 2 variant). Frontend (`TodoItems.Blazor`) and backend (`TodoItems.Api`) are separate projects at the repository root, matching the existing project layout. No `frontend/` or `backend/` subfolder nesting is introduced to avoid restructuring existing paths referenced by all four pipelines.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| New App Service (Principle IV) | Blazor WASM is a separate origin from the API; requires its own host URL for CORS to work correctly | Serving Blazor static files from the API's `wwwroot` would couple both projects, make independent deployment impossible, and conflict with the API's health-check and OpenAPI paths |
| 4 pipeline updates (Principle V) | New deployable project inherently adds build + deploy steps | Updating fewer than all four pipelines would leave Docker or Azure DevOps pipelines broken — constitution explicitly forbids this |
