# Data Model: Blazor Todo Frontend

**Phase 1 output** | Branch: `001-blazor-futuretech-frontend` | Date: 2026-03-10

---

## Entities

### TodoItem (Client-Side DTO)

The source of truth lives in the backend. The Blazor client mirrors the backend's `Todo` model as a plain C# record.

```csharp
// TodoItems.Blazor/Models/TodoItem.cs
public record TodoItem(int Id, string? Name, bool IsComplete);
```

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `Id` | `int` | Required, ≥ 1 | Assigned by backend on creation |
| `Name` | `string?` | 1–100 characters; not null/whitespace on creation | Validated client-side before submission |
| `IsComplete` | `bool` | — | `false` = active; `true` = completed |

**Validation rules** (client-side, before API call):
- Name must not be null, empty, or whitespace-only → FR-009
- Name must not exceed 100 characters → FR-002 / spec edge case

---

### CreateTodoRequest (Outbound DTO)

```csharp
// Inline record used by TodoApiService for POST body
public record CreateTodoRequest(string Name);
```

The backend `Todo` model accepts `Id` and `IsComplete` on POST but the client only supplies `Name` (Id is server-assigned; new items start incomplete).

---

### UpdateTodoRequest (Outbound DTO)

```csharp
// Inline record used by TodoApiService for PUT body
public record UpdateTodoRequest(string? Name, bool IsComplete);
```

Used when toggling completion status. `Name` is preserved from the existing item.

---

## View State

### FilterOption (UI Enum)

```csharp
public enum FilterOption { All, Active, Completed }
```

| Value | Displayed label | Items shown |
|-------|----------------|-------------|
| `All` | "All" | All items |
| `Active` | "Active" | `IsComplete == false` |
| `Completed` | "Completed" | `IsComplete == true` |

### AppState (held in `TodoApiService`)

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Items` | `List<TodoItem>` | `[]` | Master list from API |
| `Filter` | `FilterOption` | `All` | Current filter selection |
| `IsLoading` | `bool` | `false` | True while any HTTP call is in flight |
| `ErrorMessage` | `string?` | `null` | Set on HTTP failure; cleared on dismiss or successful retry |

**Derived / computed**:
| Name | Derivation |
|------|-----------|
| `FilteredItems` | `Items` filtered by `Filter` |
| `ActiveCount` | `Items.Count(i => !i.IsComplete)` |

---

## State Transitions

```
                   Page Load
                       │
               [LoadItems called]
                       │
              IsLoading = true
                       │
               ┌───────┴────────┐
           Success            Failure
               │                │
          Items = result   ErrorMessage = msg
          IsLoading=false  IsLoading=false
               │
          User interactions:
          ┌────┼────┬────────┐
         Add  Toggle Delete  Filter
          │    │     │        │
       POST   PUT  DELETE   (local)
          │    │     │
       Optimistic update → on failure → rollback + set ErrorMessage
```

**Optimistic update strategy**: For toggle and delete, update `Items` locally before the API call, then rollback on failure. For add, wait for the API response (to get the server-assigned `Id`) before inserting into the list. This approach keeps the UI responsive without complex conflict resolution.

---

## Relationships

```
FilterOption ──── governs ──── AppState.Filter
AppState.Items[] ──── contains ──── TodoItem
TodoItem ──── synced from/to ──── TodoItems.Api (REST)
```

All relationships are stateless (no graph; no navigation properties). The backend is the sole persistence layer.
