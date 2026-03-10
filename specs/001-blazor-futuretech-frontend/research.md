# Research: Blazor Todo Frontend with FutureTech-Inspired Design

**Phase 0 output** | Branch: `001-blazor-futuretech-frontend` | Date: 2026-03-10

---

## RES-01: Blazor Hosting Model Selection

**Decision**: Blazor WebAssembly — standalone SPA (no ASP.NET Core host project)  
**Rationale**: The spec explicitly mandates Blazor WASM. Standalone mode (no `Hosted=true`) is the simplest model for a demo: one project, calls the API directly via HTTP from the browser. No server-side rendering infrastructure needed.  
**Alternatives considered**:  
- Blazor Server: requires persistent SignalR connection, not suitable for demo/offline scenarios  
- Blazor WASM Hosted: adds a server project (unnecessary complexity, violates demo-readability principle)  
- .NET MAUI Blazor Hybrid: mobile app, out of scope  

---

## RES-02: .NET Version

**Decision**: .NET 10.0 (`net10.0`)  
**Rationale**: `global.json` pins the SDK to `10.0.100`. The existing API targets `net10.0`. The Blazor project must match to avoid SDK version conflicts and align with the in-repo toolchain.  
**Alternatives considered**: .NET 8 LTS — rejected to maintain consistency with the rest of the solution.

---

## RES-03: CSS and Visual Design Approach

**Decision**: Vanilla CSS with CSS custom properties (variables), CSS `@keyframes` animations, and scoped component CSS isolation (`.razor.css` files) for per-component rules.  
**Rationale**:
- Zero additional NuGet or npm dependencies — preserves demo readability on a projector
- CSS variables make the neon theme (`--accent-cyan`, `--accent-purple`, `--bg-dark`) globally configurable from `app.css`
- Blazor CSS isolation scopes per-component animation without class name collisions
- No build toolchain (webpack, node) required — `dotnet publish` is sufficient  

**Theme palette** (derived from FutureTech reference + spec description):  
| Token | Value | Use |
|-------|-------|-----|
| `--bg-dark` | `#0a0a0f` | Page background |
| `--surface` | `#12121e` | Card / panel backgrounds |
| `--accent-cyan` | `#00f5ff` | Primary interactive accent |
| `--accent-purple` | `#9d00ff` | Secondary accent / gradients |
| `--text-primary` | `#e8e8ff` | Body text |
| `--text-dim` | `#6b6b9a` | Placeholder / secondary text |
| `--glow-cyan` | `0 0 12px #00f5ff80` | Box-shadow glow effect |
| `--glow-purple` | `0 0 12px #9d00ff80` | Secondary glow |

**Typography**: `'Orbitron'` (Google Fonts, free) for headings; `'Rajdhani'` or system `monospace` for body. Loaded in `index.html`.  

**Animations decided**:  
| Interaction | Animation | Duration |
|-------------|-----------|----------|
| Item added | `fade-slide-in` (opacity 0→1, translateY -20px→0) | 300 ms |
| Item deleted | `fade-slide-out` (opacity 1→0, translateX 0→40px) | 250 ms |
| Completion toggle | `pulse-glow` (box-shadow pulse) | 350 ms |
| Button hover | `glow-intensify` (box-shadow transition) | 150 ms |
| Error banner appear | `slide-down` | 200 ms |

**Alternatives considered**:  
- MudBlazor: excellent component library but adds 500 KB+ WASM payload, requires learning curve, masks demo CSS — rejected  
- Tailwind CSS: requires npm + PostCSS build step — rejected  
- Bootstrap: not futuristic-looking out of the box — rejected  

---

## RES-04: HttpClient and API Communication Pattern

**Decision**: Named `HttpClient` registered in `Program.cs` with `BaseAddress` sourced from configuration; injected into a single `TodoApiService` class.  

```csharp
// Program.cs
builder.Services.AddHttpClient<TodoApiService>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["ApiBaseUrl"]!);
});
```

**Rationale**:  
- Typed `HttpClient` via `AddHttpClient<TClient>` provides automatic `IHttpClientFactory` lifecycle management  
- `ApiBaseUrl` from `wwwroot/appsettings.json` (prd) / `appsettings.Development.json` (dev) — matches spec assumption  
- Single service class keeps all HTTP calls in one projector-friendly file  
- No Refit or other HTTP abstraction libraries (violates demo-readability)  

**API base URL configuration**:  

```json
// wwwroot/appsettings.json (production placeholder — overridden at deploy time via pipeline)
{ "ApiBaseUrl": "https://<api-app-service>.azurewebsites.net" }

// wwwroot/appsettings.Development.json
{ "ApiBaseUrl": "https://localhost:7001" }
```

**Alternatives considered**:  
- `builder.Services.AddScoped(sp => new HttpClient { BaseAddress = ... })`: simpler but bypasses `IHttpClientFactory` — rejected  
- Refit / RestSharp: extra dependency, not demo-friendly — rejected  

---

## RES-05: CORS Policy for TodoItems.Api

**Decision**: Add a named CORS policy `"BlazorWasmPolicy"` to `TodoItems.Api/Program.cs` that allows the Blazor origin. Origin configured via `appsettings.json` key `AllowedOrigins:Blazor`.  

```csharp
// builder.Services section
builder.Services.AddCors(options =>
{
    options.AddPolicy("BlazorWasmPolicy", policy =>
        policy.WithOrigins(builder.Configuration["AllowedOrigins:Blazor"]!)
              .AllowAnyHeader()
              .AllowAnyMethod());
});

// app middleware section (before MapHealthChecks)
app.UseCors("BlazorWasmPolicy");
```

**Rationale**:  
- Origin is never hardcoded in source — follows spec assumption and constitutional principle I (no magic strings)  
- `AllowAnyHeader` + `AllowAnyMethod` covers all REST verbs used by the API  
- Single policy, applied globally to all routes via `app.UseCors` (Minimal API style)  

**Alternatives considered**:  
- `WithOrigins("*")`: wildcard CORS is a security risk, rejected  
- `.AllowCredentials()`: not needed (no cookies/auth), not added  

---

## RES-06: Client-Side State Management

**Decision**: Simple injectable `TodoStateService` (or fold state into `TodoApiService`) with `Action` events to notify components of changes. No Fluxor, no Redux pattern.  

**Rationale**: The application has one page and one list. A single service holding `List<TodoItem>` and raising `OnChange` events is the minimal viable state model. This is projector-friendly and the standard Blazor pattern for small apps.  

**Alternatives considered**:  
- Fluxor (Redux pattern): excellent for large apps, massive overkill for a single-page demo — rejected  
- Cascading values: viable for theming but not for shared mutable state — not applicable  

---

## RES-07: Blazor WASM Hosting on Azure App Service

**Decision**: Deploy the Blazor WASM project to a **dedicated Linux Azure App Service** using the `DOTNETCORE|10.0` runtime stack. The `dotnet publish` output runs `dotnet TodoItems.Blazor.dll` which serves the static WASM files via a minimal Kestrel host.  

**Rationale**:  
- Reuses existing Bicep module pattern (`appService.bicep`) — minimal new Bicep code  
- Linux App Service with dotnet runtime handles 404 → `index.html` rewrite automatically when configured  
- Consistent with how the API is hosted; simpler than setting up a separate Azure Static Web Apps resource  
- Separate App Service URL enables independent deployment and scaling  

**Key Bicep settings for Blazor App Service**:  
- No Key Vault reference needed (Blazor has no secrets; API URL is public)  
- No health check path (Blazor is static; no `/health` endpoint)  
- `linuxFxVersion: 'DOTNETCORE|10.0'`  

**Alternatives considered**:  
- Azure Static Web Apps: purpose-built for SPAs, free tier available, but introduces a different resource type and a different CI/CD deploy action — adds complexity to all four pipelines — rejected to keep infrastructure uniform  
- CDN (Azure Blob + CDN): most cost-efficient at scale but requires new resource types and no Blazor-specific 404 handling — out of scope for demo  
- Serve static files from `TodoItems.Api` wwwroot: couples projects, prevents independent deployment, conflicts with API paths — rejected per spec  

---

## RES-08: Pipeline Integration Strategy

**Decision**: Modify the existing `build.yml` (shared) to add a second `dotnet publish` step for `TodoItems.Blazor`. Add a `todoItemsBlazor` artifact upload. Modify all four main pipeline files to add a deploy step for the Blazor App Service. Create `blazorService.bicep` and update both `main.*.webapp.bicep` files.  

**Details per pipeline file**:

| File | Change |
|------|--------|
| `.github/workflows/build.yml` | Add `dotnet publish TodoItems.Blazor/...` + `upload-artifact todoItemsBlazor` |
| `.github/workflows/main.nodocker.yml` | Download `todoItemsBlazor` artifact; zip + deploy to Blazor App Service via `azure/webapps-deploy` |
| `.github/workflows/main.docker.yml` | Same deploy step (Blazor is always non-Docker — static WASM files don't benefit from containerisation); add Blazor App Service name as output from `create_env` |
| `.azuredevops/build.yml` | Add `DotNetCoreCLI@2` publish for Blazor + `PublishPipelineArtifact@1` for `todoItemsBlazor` |
| `.azuredevops/main.nodocker.yml` | Add deploy stage for Blazor App Service using `AzureWebApp@1` |
| `.azuredevops/main.docker.yml` | Same Blazor deploy step |
| `Deployment/blazorService.bicep` | NEW — creates Blazor App Service (no SQL, no Key Vault) |
| `Deployment/main.nodocker.webapp.bicep` | Add `module blazorService` + outputs `blazorWebAppName`, `blazorWebAppUrl` |
| `Deployment/main.docker.webapp.bicep` | Same additions (Blazor itself is never Dockerised) |

**Note on Docker mode**: The Blazor WASM app produces browser-executable static files. Containerising these offers no benefit. In Docker pipeline mode, the *API* uses Docker; the Blazor project is still deployed as a dotnet publish artifact to its own App Service. Both Bicep templates therefore add the same `blazorService.bicep` module.  

---

## RES-09: 404 / Deep-Link Handling for Blazor SPA

**Decision**: Configure the Azure App Service startup command to ensure all routes return `index.html`. For .NET Blazor WASM hosted with Kestrel, the default behavior already handles this when `UseStaticFiles` + fallback routing is configured. Ensure `web.config` (auto-generated by publish) or startup correctly rewrites unmatched paths to `index.html`.  

**Rationale**: Blazor WASM uses client-side routing. If a user bookmarks a deep link, the server must return `index.html` for any path, not a 404. The generated dotnet host handles this by default with the `UseBlazorFrameworkFiles` + `MapFallbackToFile("index.html")` pattern.  

---

## Summary of Decisions

| Topic | Decision |
|-------|----------|
| Hosting model | Blazor WebAssembly standalone |
| .NET version | 10.0 |
| CSS approach | Vanilla CSS + custom properties + CSS isolation |
| HTTP client | `AddHttpClient<TodoApiService>` with config-driven base URL |
| CORS | Named policy, origin from config |
| State management | Single injectable service with `Action` events |
| Azure hosting | Dedicated Linux App Service (`DOTNETCORE|10.0`) |
| Pipeline strategy | Modify all 4 pipelines; new `blazorService.bicep`; Blazor always non-Docker |
