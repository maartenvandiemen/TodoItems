using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.Net.Http.Json;
using System.Threading;
using System.Threading.Tasks;
using Testcontainers.MsSql;

//Every test gets its own database (InMemory: a unique name, TestContainers: a unique database
//on the shared SQL Server), so the tests can run in parallel.
[assembly: Parallelize(Scope = ExecutionScope.MethodLevel)]

namespace TodoItems.Api.IntegrationTests
{
    [TestClass]
    public class IntegrationTests
    {
        //One SQL Server container for all tests in this class: starting one takes ~5 seconds and stopping
        //one ~10 seconds, so a container per test made those steps most of the test run.
        //Started on first use, so running only the InMemory tests does not need Docker.
        private static readonly Lazy<Task<MsSqlContainer>> SqlContainer = new(StartSqlContainerAsync, LazyThreadSafetyMode.ExecutionAndPublication);

        //The Azure SQL Database container fails parallel CREATE DATABASE statements ("Internal service error"),
        //so databases are created one at a time. The tests themselves still run in parallel.
        private static readonly SemaphoreSlim CreateDatabaseLock = new(1, 1);

        [ClassCleanup]
        public static async Task ClassCleanup()
        {
            if (SqlContainer.IsValueCreated)
            {
                //Dispose removes the container (and its data) in one go.
                await (await SqlContainer.Value).DisposeAsync();
            }
        }

        [TestMethod]
        [DataRow(Environment.InMemory)]
        [DataRow(Environment.TestContainers)]
        public async Task InitialDb_TodoItems_Empty(Environment environment)
        {
            //Arrange
            await using var application = await InitializeApplication(environment);
            var client = application.CreateClient();

            //Act
            var todoItems = await client.GetFromJsonAsync<List<Todo>>("/todoitems");

            //Assert
            Assert.IsNotNull(todoItems);
            Assert.IsEmpty(todoItems);
        }

        [TestMethod]
        [DataRow(Environment.InMemory)]
        [DataRow(Environment.TestContainers)]
        public async Task FilledDb_GetTodoItems_Returned(Environment environment)
        {
            //Arrange
            await using var application = await InitializeApplication(environment);
            using (var scope = application.Services.CreateScope())
            {
                var provider = scope.ServiceProvider;
                using var todoDbContext = provider.GetRequiredService<TodoDb>();

                await todoDbContext.Todos.AddAsync(new Todo { Name = "First todo", IsComplete = true });
                await todoDbContext.Todos.AddAsync(new Todo { Name = "Second todo", IsComplete = false });

                await todoDbContext.SaveChangesAsync();
            }
            var client = application.CreateClient();

            //Act
            var todoItems = await client.GetFromJsonAsync<List<Todo>>("/todoitems");

            //Assert
            Assert.IsNotNull(todoItems);
            Assert.HasCount(2, todoItems);
        }

        private static async Task<MsSqlContainer> StartSqlContainerAsync()
        {
            var container = new MsSqlBuilder("mcr.microsoft.com/mssql/azure-sql-db-server:latest")
                //Removes the container automatically if the test run is aborted before ClassCleanup.
                .WithCleanUp(true)
                .Build();
            await container.StartAsync();
            return container;
        }

        private static async Task<TodoItemsApiApplication> InitializeApplication(Environment environment)
        {
            string? connectionString = null;
            if (environment == Environment.TestContainers)
            {
                //A new database per test on the shared container: tests stay isolated without cleaning tables.
                var container = await SqlContainer.Value;
                connectionString = new SqlConnectionStringBuilder(container.GetConnectionString())
                {
                    InitialCatalog = $"TodoItems_{Guid.NewGuid():N}"
                }.ConnectionString;
            }

            var application = new TodoItemsApiApplication(environment, connectionString);

            using (var scope = application.Services.CreateScope())
            {
                var provider = scope.ServiceProvider;
                using var todoDbContext = provider.GetRequiredService<TodoDb>();
                //Creates the database (for TestContainers) and its tables.
                await CreateDatabaseLock.WaitAsync();
                try
                {
                    await todoDbContext.Database.EnsureCreatedAsync();
                }
                finally
                {
                    CreateDatabaseLock.Release();
                }
            }

            return application;
        }
    }
}
