var builder = DistributedApplication.CreateBuilder(args);

var sql = builder.AddSqlServer("sql")
    .WithImageTag("2025-latest");

var sqldb = sql.AddDatabase("sqldb");

var api = builder.AddProject<Projects.TodoItems_Api>("api")
                            .WaitFor(sqldb)
                            .WithReference(sqldb);

builder.Build().Run();
