# Tasks: Blazor Todo Frontend with FutureTech-Inspired Design

**Input**: Design documents from `/specs/001-blazor-futuretech-frontend/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/todoitems-api.md ✅, quickstart.md ✅

**Tests**: Test tasks are NOT included — not requested in the feature specification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths are included in each task description

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Bootstrap the Blazor WASM project and integrate it into the repository.

- [ ] T001 Create Blazor WASM project using `dotnet new blazorwasm --name TodoItems.Blazor --output TodoItems.Blazor --no-https false` from repository root
- [ ] T002 Add `TodoItems.Blazor` to `TodoItems.slnx` using `dotnet sln TodoItems.slnx add TodoItems.Blazor/TodoItems.Blazor.csproj`
- [ ] T003 Enable NuGet lock file in `TodoItems.Blazor/TodoItems.Blazor.csproj` (`<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>`), run `dotnet restore --force-evaluate`, and commit `packages.lock.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be fully implemented.

**⚠️ CRITICAL**: No user story component work can be completed until this phase is done.

- [ ] T004 [P] Add CORS configuration keys `AllowedOrigins:Blazor` to `TodoItems.Api/appsettings.json` (production placeholder) and `TodoItems.Api/appsettings.Development.json` (`https://localhost:7002`)
- [ ] T005 [P] Add CORS policy `"BlazorWasmPolicy"` (`WithOrigins` + `AllowAnyHeader` + `AllowAnyMethod`) and `app.UseCors("BlazorWasmPolicy")` middleware to `TodoItems.Api/Program.cs`
- [ ] T006 [P] Create `TodoItem`, `CreateTodoRequest`, and `UpdateTodoRequest` records in `TodoItems.Blazor/Models/TodoItem.cs`
- [ ] T007 [P] Create `FilterOption` enum (`All`, `Active`, `Completed`) in `TodoItems.Blazor/Models/FilterOption.cs`
- [ ] T008 [P] Configure API base URL in `TodoItems.Blazor/wwwroot/appsettings.json` (`ApiBaseUrl` production placeholder) and `TodoItems.Blazor/wwwroot/appsettings.Development.json` (`https://localhost:7001`)
- [ ] T009 [P] Set up `TodoItems.Blazor/wwwroot/index.html` as SPA host page: dark background (`#0a0a0f`), Google Fonts import for Orbitron and Rajdhani, Blazor WASM script tag
- [ ] T010 [P] Create global futuristic theme in `TodoItems.Blazor/wwwroot/css/app.css`: CSS custom properties (--bg-dark, --surface, --accent-cyan, --accent-purple, --text-primary, --text-dim, --glow-cyan, --glow-purple), and `@keyframes` for `fade-slide-in` (300ms), `fade-slide-out` (250ms), `pulse-glow` (350ms), `glow-intensify` (150ms), `slide-down` (200ms)
- [ ] T011 [P] Configure `TodoItems.Blazor/_Imports.razor` with required `@using` directives and set up `TodoItems.Blazor/App.razor` with `Router` component
- [ ] T012 Implement `TodoApiService` in `TodoItems.Blazor/Services/TodoApiService.cs` with `Items`, `Filter`, `IsLoading`, `ErrorMessage` state; `FilteredItems` and `ActiveCount` computed properties; and HTTP methods `LoadItemsAsync`, `AddItemAsync`, `ToggleItemAsync`, `DeleteItemAsync` using optimistic updates per data-model.md (depends on T006, T007)
- [ ] T013 Register `HttpClient<TodoApiService>` with `BaseAddress` from `Configuration["ApiBaseUrl"]` and `TodoApiService` as scoped service in `TodoItems.Blazor/Program.cs` (depends on T008, T012)

**Checkpoint**: Foundation ready — user story component implementation can begin

---

## Phase 3: User Story 1 - View and Manage Todo Items (Priority: P1) 🎯 MVP

**Goal**: Deliver a fully functional futuristic todo manager: load items, add, toggle completion, delete, empty-state message, loading indicator, and error banner with Retry/Dismiss.

**Independent Test**: Load the page → existing items appear; add a new item → it appears with fade-slide-in; toggle completion → item updates visually; delete an item → it disappears with fade-slide-out; disconnect API → error banner with Retry appears.

### Implementation for User Story 1

- [ ] T014 [P] [US1] Create `TodoItems.Blazor/Components/ErrorBanner.razor` displaying `ErrorMessage` with Retry and Dismiss buttons; add `TodoItems.Blazor/Components/ErrorBanner.razor.css` with slide-down entry animation using `--accent-purple` glow
- [ ] T015 [P] [US1] Create `TodoItems.Blazor/Components/TodoItemRow.razor` with completion toggle checkbox (pulse-glow on click) and delete button (neon hover glow); add `TodoItems.Blazor/Components/TodoItemRow.razor.css` with completion strikethrough + color change styles; ensure 44×44px touch targets
- [ ] T016 [P] [US1] Create `TodoItems.Blazor/Components/AddTodoForm.razor` with name input (maxlength 100), whitespace/empty inline validation, submit on Enter and button click; add `TodoItems.Blazor/Components/AddTodoForm.razor.css` with neon input focus glow and 44×44px touch target for submit button
- [ ] T017 [US1] Create `TodoItems.Blazor/Components/TodoList.razor` as animated list container: wraps `TodoItemRow` components, applies `fade-slide-in` on add and `fade-slide-out` on delete, shows empty-state message when no items; add `TodoItems.Blazor/Components/TodoList.razor.css` (depends on T015)
- [ ] T018 [US1] Implement `TodoItems.Blazor/Pages/Home.razor` as main page composition root: injects `TodoApiService`, triggers `LoadItemsAsync` on init, renders `AddTodoForm`, `TodoList`, `ErrorBanner`, and loading indicator; add `TodoItems.Blazor/Pages/Home.razor.css` with page-level layout and futuristic dashboard header (depends on T014, T016, T017)

**Checkpoint**: User Story 1 fully functional and independently testable — MVP scope complete

---

## Phase 4: User Story 2 - Filter Items by Completion Status (Priority: P2)

**Goal**: Add All / Active / Completed filter buttons with active-item count badge. Filtered view updates immediately on selection.

**Independent Test**: Create a mix of complete and incomplete items; click "Completed" → only completed shown; click "Active" → only incomplete shown; click "All" → all shown; count badge reflects current filtered result.

### Implementation for User Story 2

- [ ] T019 [P] [US2] Create `TodoItems.Blazor/Components/FilterBar.razor` with All / Active / Completed toggle buttons and active-item count badge (`ActiveCount`); add `TodoItems.Blazor/Components/FilterBar.razor.css` with neon-active state and `--accent-cyan` border for selected filter; ensure 44×44px touch targets
- [ ] T020 [US2] Update `TodoItems.Blazor/Pages/Home.razor` to include `FilterBar`, pass `FilteredItems` from `TodoApiService` to `TodoList`, and wire `FilterBar` filter-change events to update `TodoApiService.Filter` triggering re-render (depends on T019)

**Checkpoint**: User Stories 1 and 2 both independently functional

---

## Phase 5: User Story 3 - Responsive Experience Across Devices (Priority: P3)

**Goal**: Application is fully usable from 320px to 2560px: layout reflows, no horizontal scroll, 44px touch targets maintained, futuristic design preserved on all viewports.

**Independent Test**: Load app in browser DevTools at 375px (mobile), 768px (tablet), 1440px (desktop) and 320px minimum; verify no horizontal scroll, all interactive elements reachable, layout reflows without overlap, neon theme intact.

### Implementation for User Story 3

- [ ] T021 [P] [US3] Add responsive CSS breakpoints to `TodoItems.Blazor/wwwroot/css/app.css`: mobile-first base (320px+), tablet breakpoint (768px), desktop breakpoint (1440px), wide breakpoint (2560px); ensure full-width single-column layout on mobile, max-width centered layout on desktop
- [ ] T022 [P] [US3] Add mobile-first layout overrides to `TodoItems.Blazor/Components/AddTodoForm.razor.css` and `TodoItems.Blazor/Components/FilterBar.razor.css`: full-width inputs/buttons on narrow viewports, minimum 44×44px touch targets confirmed at all breakpoints
- [ ] T023 [US3] Add mobile-first layout overrides to `TodoItems.Blazor/Components/TodoItemRow.razor.css` and `TodoItems.Blazor/Components/TodoList.razor.css`: full-width stack on narrow viewports, comfortable padding, no content clipping (depends on T022)

**Checkpoint**: All user stories functional and fully responsive across all target viewports

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Infrastructure, deployment pipelines, and solution-wide integration. All four CI/CD pipelines updated in the same PR per Principle V.

- [ ] T024 [P] Create `Deployment/blazorService.bicep` as a new App Service module for Blazor WASM (Linux, DOTNETCORE|10.0), following the pattern of existing `Deployment/appService.bicep`
- [ ] T025 [P] Update `Deployment/main.nodocker.webapp.bicep` to reference the `blazorService` module and expose its outputs (app service name, URL)
- [ ] T026 [P] Update `Deployment/main.docker.webapp.bicep` to reference the `blazorService` module with appropriate Docker parameters
- [ ] T027 [P] Update `.github/workflows/build.yml` to publish the `TodoItems.Blazor` artifact (`dotnet publish TodoItems.Blazor/TodoItems.Blazor.csproj`) alongside the existing API artifact
- [ ] T028 [P] Update `.github/workflows/main.nodocker.yml` to add a deploy step that deploys the Blazor artifact to the `blazorService` App Service (non-Docker)
- [ ] T029 [P] Update `.github/workflows/main.docker.yml` to add a deploy step for Blazor (Docker variant)
- [ ] T030 [P] Update `.azuredevops/build.yml` to publish the `todoItemsBlazor` artifact alongside the existing API artifact
- [ ] T031 [P] Update `.azuredevops/main.nodocker.yml` to add a Blazor deploy stage
- [ ] T032 [P] Update `.azuredevops/main.docker.yml` to add a Blazor deploy stage (Docker variant)
- [ ] T033 Run `quickstart.md` validation: start API locally, run Blazor project, confirm CORS works (DevTools network tab shows `Access-Control-Allow-Origin` header), confirm all CRUD operations work end-to-end

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user story component work
- **User Story Phases (3–5)**: All depend on Phase 2 completion; can proceed in priority order (US1 → US2 → US3) or in parallel if staffed
- **Polish (Phase 6)**: Infrastructure tasks (T024–T032) can start after Phase 1; T033 depends on all stories complete

### User Story Dependencies

| Story | Depends on | Notes |
|-------|-----------|-------|
| US1 (P1) | Phase 2 complete | No story dependencies — MVP scope |
| US2 (P2) | Phase 2 complete + US1 `Home.razor` exists | Adds `FilterBar`; reads `FilteredItems` from `TodoApiService` |
| US3 (P3) | Phase 2 complete | CSS-only additions — no logic dependencies on US1/US2 |

### Within Each User Story

- Models → Service → Components → Page composition
- Leaf components (T014, T015, T016) before container (T017) before page (T018)
- `FilterBar` (T019) before `Home.razor` update (T020)

### Parallel Opportunities

- **Phase 2**: T004–T011 are all independent — can run in parallel (CORS config, models, CSS, HTML, config files)
- **Phase 3**: T014, T015, T016 can run in parallel; T017 needs T015; T018 needs T014+T016+T017
- **Phase 4**: T019 before T020
- **Phase 5**: T021, T022 in parallel; T023 needs T022
- **Phase 6**: T024–T032 all independent — can run in parallel

---

## Parallel Example: User Story 1

```bash
# After Phase 2 completes, run these in parallel:
Agent-A: T014  # ErrorBanner.razor + css
Agent-B: T015  # TodoItemRow.razor + css
Agent-C: T016  # AddTodoForm.razor + css

# Then:
Agent-A: T017  # TodoList.razor (needs T015)

# Then:
Agent-A: T018  # Home.razor (needs T014+T016+T017)
```

---

## Implementation Strategy

**MVP First**: Deliver Phase 1 → Phase 2 → Phase 3 (User Story 1) in sequence. This produces a fully working futuristic todo manager that satisfies all P1 acceptance scenarios.

**Incremental Delivery**:
1. Phase 3 complete → full CRUD todo manager (SC-001, SC-002, SC-006 for FR-001–FR-011, FR-014)
2. Phase 4 added → filtering available (SC-006 for FR-005, FR-006)
3. Phase 5 added → fully responsive (SC-003, SC-004, SC-006 for FR-012–FR-013)
4. Phase 6 added → deployable to Azure via all four pipelines
