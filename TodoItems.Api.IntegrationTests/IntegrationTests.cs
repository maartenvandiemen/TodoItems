using DotNet.Testcontainers.Builders;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Collections.Generic;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Testcontainers.MsSql;

namespace TodoItems.Api.IntegrationTests
{
    [TestClass]
    public class IntegrationTests
    {
        private MsSqlContainer? _sqlContainer;

        [TestInitialize]
        public void TestInitialize()
        {
            _sqlContainer = new MsSqlBuilder()
                .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
                //Will remove the image automatically after all tests have been run.
                .WithCleanUp(true)
                .Build();            
        }

        [TestMethod]
        [DoNotParallelize]
        [DataRow(Environment.InMemory)]
        [DataRow(Environment.ExternalDatabase)]
        [DataRow(Environment.TestContainers)]

        public async Task InitialDb_TodoItems_Empty(Environment environment)
        {
            try
            {
                //Arrange
                await using var application = await InitializeApplication(environment);
                var client = application.CreateClient();

                //Act
                var todoItems = await client.GetFromJsonAsync<List<Todo>>("/todoitems");

                //Assert
                Assert.IsNotNull(todoItems);
                Assert.AreEqual(0, todoItems.Count);
            }
            finally
            {
                await Teardown(environment);
            }
        }

        [TestMethod]
        [DoNotParallelize]
        [DataRow(Environment.InMemory)]
        [DataRow(Environment.ExternalDatabase)]
        [DataRow(Environment.TestContainers)]
        public async Task FilledDb_GetTodoItems_Returned(Environment environment)
        {
            try
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
                Assert.AreEqual(2, todoItems.Count);
            }
            finally
            {
                await Teardown(environment);
            }
        }

        private async Task<TodoItemsApiApplication> InitializeApplication(Environment environment)
        {
            if(environment == Environment.TestContainers)
            {
                await _sqlContainer!.StartAsync();
            }

            var application = new TodoItemsApiApplication(environment, _sqlContainer!);

            using (var scope = application.Services.CreateScope())
            {
                var provider = scope.ServiceProvider;
                using var todoDbContext = provider.GetRequiredService<TodoDb>();
                await todoDbContext.Database.EnsureCreatedAsync();
            }

            return application;
        }

        private async Task Teardown(Environment environment)
        {
            var connectionstring = DetermineConnectionstring(environment);

            using var sc = new SqlConnection(connectionstring);
            using var cmd = sc.CreateCommand();
            sc.Open();
            cmd.CommandText = "DELETE FROM Todos";
            cmd.ExecuteNonQuery();

            if (environment == Environment.TestContainers)
            {
                await _sqlContainer!.StopAsync();
            }
        }

        private string DetermineConnectionstring(Environment environment)
        {
            if (environment == Environment.TestContainers)
            {
                return _sqlContainer!.GetConnectionString();
            }
            else
            {
                var config = new ConfigurationBuilder()
                                    .AddJsonFile("appsettings.integration.json")
                                    .AddEnvironmentVariables(prefix: "integrationtests_")
                                    .Build();

                return config.GetConnectionString("TodoDb")!;
            }
        }
    }
}
