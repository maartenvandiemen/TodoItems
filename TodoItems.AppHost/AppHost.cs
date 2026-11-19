var builder = DistributedApplication.CreateBuilder(args);

// Same Azure SQL Database container (public preview) as the integration tests and the CI pipelines.
// Persistent lifetime keeps the container (and its data) alive between F5 sessions.
var sql = builder.AddSqlServer("sql")
    .WithImageRegistry("mcr.microsoft.com")
    .WithImage("mssql/azure-sql-db-server")
    .WithImageTag("latest")
    .WithLifetime(ContainerLifetime.Persistent);

// The resource name is the connection string name the API reads: ConnectionStrings:TodoDb
var todoDb = sql.AddDatabase("TodoDb");

builder.AddDotnetProject("todoitems-api", "../TodoItems.Api/TodoItems.Api.csproj")
    .WithReference(todoDb)
    .WaitFor(todoDb)
    // Plain F5 on the API uses the in-memory database (see appsettings.Development.json); here we want the real thing.
    .WithEnvironment("UseInMemoryDatabase", "false")
    .WithHttpHealthCheck("/health")
    .WithUrlForEndpoint("http", url => url.DisplayText = "API")
    .WithExternalHttpEndpoints();

builder.Build().Run();
