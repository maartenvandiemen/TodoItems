using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Collections.Generic;
using System.Net.Http.Json;
using System.Threading.Tasks;

namespace TodoItems.Api.UnitTests
{
    [TestClass]
    public class IntegrationTests
    {
        [TestCleanup]
        public void TestInitialize()
        {
            var config = new ConfigurationBuilder()
                .AddJsonFile("appsettings.integration.json")
                .AddEnvironmentVariables(prefix: "integrationtests_")
                .Build();

            var connectionstring = config.GetConnectionString("TodoDb");

            using var sc = new SqlConnection(connectionstring);
            using var cmd = sc.CreateCommand();
            sc.Open();
            cmd.CommandText = "DELETE FROM Todos";
            cmd.ExecuteNonQuery();
        }

        [TestMethod]
        [DoNotParallelize]
        [DataRow(Environment.Development)]
        [DataRow(Environment.Integration)]
        public async Task InitialDb_TodoItems_Empty(Environment environment)
        {
            //Arrange
            await using var application = new TodoItemsApiApplication(environment);
            var client = application.CreateClient();

            //Act
            var todoItems = await client.GetFromJsonAsync<List<Todo>>("/todoitems");

            //Assert
            Assert.IsNotNull(todoItems);
            Assert.AreEqual(0, todoItems.Count);
        }

        [TestMethod]
        [DoNotParallelize]
        [DataRow(Environment.Development)]
        [DataRow(Environment.Integration)]
        public async Task FilledDb_GetTodoItems_Returned(Environment environment)
        {
            //Arrange
            await using var application = new TodoItemsApiApplication(environment);
            using (var scope = application.Services.CreateScope())
            {
                var provider = scope.ServiceProvider;
                using var todoDbContext = provider.GetRequiredService<TodoDb>();
                await todoDbContext.Database.EnsureCreatedAsync();

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
    }
}