# Quickstart: Blazor Todo Frontend

**Phase 1 output** | Branch: `001-blazor-futuretech-frontend` | Date: 2026-03-10

---

## Prerequisites

- .NET 10 SDK (`dotnet --version` → `10.0.x`)
- `TodoItems.Api` running locally (see below)

---

## 1. Start the backend API

```powershell
cd TodoItems.Api
dotnet run
# API listens at https://localhost:7001 (check Properties/launchSettings.json)
```

The API uses an in-memory database in Development mode — no SQL Server required.

---

## 2. Create and run the Blazor WASM project

```powershell
# From repository root — create the new Blazor project
dotnet new blazorwasm --name TodoItems.Blazor --output TodoItems.Blazor --no-https false

cd TodoItems.Blazor
dotnet run
# Blazor dev server listens at https://localhost:7002 (adjust launchSettings.json if needed)
```

Open `https://localhost:7002` in your browser. The app connects to the API at `https://localhost:7001`.

---

## 3. Add the project to the solution

```powershell
# From repository root
dotnet sln TodoItems.slnx add TodoItems.Blazor/TodoItems.Blazor.csproj
```

---

## 4. Verify CORS is working

After adding the CORS policy to `TodoItems.Api`, confirm:

1. Open browser DevTools → Network
2. Load the Blazor app
3. Inspect the `GET /todoitems` request — the response should include `Access-Control-Allow-Origin: https://localhost:7002`

If you see a CORS error, check that `AllowedOrigins:Blazor` in `TodoItems.Api/appsettings.Development.json` matches your Blazor dev server URL exactly (including port).

---

## 5. Enable NuGet lock file

In `TodoItems.Blazor.csproj`, ensure this property is set:

```xml
<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
```

After adding packages, regenerate the lock file:

```powershell
cd TodoItems.Blazor
dotnet restore --force-evaluate
```

Commit both `TodoItems.Blazor.csproj` and `packages.lock.json` together.

---

## 6. Run integration tests (API only)

The existing integration test suite is unchanged:

```powershell
cd TodoItems.Api.IntegrationTests
dotnet test
```

---

## Key configuration files

| File | Purpose |
|------|---------|
| `TodoItems.Blazor/wwwroot/appsettings.json` | Production API base URL (`ApiBaseUrl`) |
| `TodoItems.Blazor/wwwroot/appsettings.Development.json` | Dev API base URL |
| `TodoItems.Api/appsettings.Development.json` | CORS allowed origin for local Blazor dev server |
| `Deployment/blazorService.bicep` | Azure infrastructure for Blazor App Service |

---

## Useful commands

```powershell
# Publish Blazor for production (produces wwwroot static files + host)
dotnet publish TodoItems.Blazor/TodoItems.Blazor.csproj -c Release -o artifacts/TodoItems.Blazor

# Build entire solution
dotnet build TodoItems.slnx

# Lint Bicep templates
az bicep lint --file Deployment/main.nodocker.webapp.bicep
az bicep lint --file Deployment/main.docker.webapp.bicep
```

---

## Architecture at a glance

```
Browser
  └─► TodoItems.Blazor  (WASM, https://blazor.azurewebsites.net)
           │ HttpClient (JSON)
           ▼
      TodoItems.Api      (ASP.NET Core, https://api.azurewebsites.net)
           │ EF Core
           ▼
        SQL Server       (Azure SQL)
```
