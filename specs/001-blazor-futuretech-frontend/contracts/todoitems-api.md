# API Contract: TodoItems REST API

**Phase 1 output** | Branch: `001-blazor-futuretech-frontend` | Date: 2026-03-10  
**Consumer**: `TodoItems.Blazor` (Blazor WebAssembly SPA)  
**Provider**: `TodoItems.Api` (ASP.NET Core Minimal API)  
**Base URL**: Configured in `wwwroot/appsettings.json` as `ApiBaseUrl`

---

## Overview

The Blazor frontend communicates with the existing REST API exclusively via HTTP/JSON. No changes to API contracts are required. The only backend change is adding a CORS policy.

All requests are unauthenticated. All responses use `application/json`.

---

## Endpoints

### GET /todoitems

**Purpose**: Load all todo items (used on initial page load and after retry).  
**Request**: No body, no query parameters.  
**Response**:

```json
// 200 OK
[
  { "id": 1, "name": "Buy groceries", "isComplete": false },
  { "id": 2, "name": "Write tests",   "isComplete": true  }
]
```

| Status | Meaning | UI behaviour |
|--------|---------|-------------|
| 200 | Success | Render list |
| 5xx / network error | Server unavailable | Show error banner with Retry button |

---

### POST /todoitems

**Purpose**: Create a new todo item.  
**Request body**:

```json
{ "name": "New task" }
```

| Field | Type | Constraints |
|-------|------|-------------|
| `name` | string | 1–100 chars; client validates before sending |

**Response**:

```json
// 201 Created — Location: /todoitems/3
{ "id": 3, "name": "New task", "isComplete": false }
```

| Status | Meaning | UI behaviour |
|--------|---------|-------------|
| 201 | Item created | Append returned item to list; play fade-slide-in animation |
| 400 | Validation error | Show inline field error |
| 5xx / network error | Server error | Show error banner; item not added |

---

### PUT /todoitems/{id}

**Purpose**: Update an existing todo item (used to toggle `isComplete`).  
**Path parameter**: `id` — integer, the item's identifier.  
**Request body**:

```json
{ "name": "Buy groceries", "isComplete": true }
```

Both fields are required. The client supplies the existing `name` from its local state.

**Response**:

```json
// 204 No Content — empty body
```

| Status | Meaning | UI behaviour |
|--------|---------|-------------|
| 204 | Update accepted | Confirm optimistic update |
| 404 | Item not found | Rollback optimistic update; show error banner; refresh list |
| 5xx / network error | Server error | Rollback optimistic update; show error banner |

---

### DELETE /todoitems/{id}

**Purpose**: Delete a todo item.  
**Path parameter**: `id` — integer.  
**Request body**: None.  
**Response**:

```json
// 200 OK
{ "id": 1, "name": "Buy groceries", "isComplete": false }
```

| Status | Meaning | UI behaviour |
|--------|---------|-------------|
| 200 | Item deleted | Confirm optimistic removal; play fade-slide-out animation |
| 404 | Already deleted | Show error banner; refresh list |
| 5xx / network error | Server error | Rollback optimistic removal; show error banner |

---

## CORS Policy (Backend Change)

The API must allow cross-origin requests from the Blazor origin.

**Configuration key added to `TodoItems.Api`**:

```json
// appsettings.json
{
  "AllowedOrigins": {
    "Blazor": "https://<blazor-app-service>.azurewebsites.net"
  }
}

// appsettings.Development.json
{
  "AllowedOrigins": {
    "Blazor": "https://localhost:7002"
  }
}
```

**Policy** (added to `TodoItems.Api/Program.cs`):

```csharp
builder.Services.AddCors(options =>
{
    options.AddPolicy("BlazorWasmPolicy", policy =>
        policy.WithOrigins(builder.Configuration["AllowedOrigins:Blazor"]!)
              .AllowAnyHeader()
              .AllowAnyMethod());
});

// Applied globally before MapHealthChecks:
app.UseCors("BlazorWasmPolicy");
```

---

## Error Handling Contract

The Blazor client treats any non-success HTTP status code or network exception as an error condition. The UI response is:

1. Rollback any optimistic update (for toggle/delete)
2. Set `ErrorMessage` to a user-friendly string (never expose raw server error detail)
3. Render `ErrorBanner` component with the message, a **"Retry"** button, and a dismiss (×) button
4. No automatic retry is performed

---

## Endpoints NOT Used

| Endpoint | Reason |
|----------|--------|
| `GET /todoitems/{id}` | Not needed; the client tracks full item state locally |
| `GET /todoitems/complete` | Not needed; client-side filtering is used instead |
| `GET /health` | Not consumed by Blazor; used by Azure App Service health checks only |
| `GET /openapi` / Scalar | Dev tooling only |
