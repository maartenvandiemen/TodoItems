var builder = DistributedApplication.CreateBuilder(args);

// Same SQL Server version as the integration tests and the CI pipeline.
// Persistent lifetime keeps the container (and its data) alive between F5 sessions.
var sql = builder.AddSqlServer("sql")
    .WithImageTag("2025-latest")
    .WithLifetime(ContainerLifetime.Persistent);

// The resource name is the connection string name the API reads: ConnectionStrings:TodoDb
var todoDb = sql.AddDatabase("TodoDb");

builder.AddProject<Projects.TodoItems_Api>("todoitems-api")
    .WithReference(todoDb)
    .WaitFor(todoDb)
    // Plain F5 on the API uses the in-memory database (see appsettings.Development.json); here we want the real thing.
    .WithEnvironment("UseInMemoryDatabase", "false")
    .WithHttpHealthCheck("/health")
    .WithUrlForEndpoint("http", url => url.DisplayText = "API")
    .WithExternalHttpEndpoints();

builder.Build().Run();
