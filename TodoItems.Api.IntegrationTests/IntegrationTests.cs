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
            _sqlContainer = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2025-latest")
                //Will remove the image automatically after all tests have been run.
                .WithCleanUp(true)
                .Build();            
        }

        [TestMethod]
        [DoNotParallelize]
        [DataRow(Environment.InMemory)]
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
                Assert.IsEmpty(todoItems);
            }
            finally
            {
                await Teardown(environment);
            }
        }

        [TestMethod]
        [DoNotParallelize]
        [DataRow(Environment.InMemory)]
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
                Assert.HasCount(2, todoItems);
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
            //The container is removed with its data, so there is no need to clean the tables.
            if (environment == Environment.TestContainers)
            {
                await _sqlContainer!.StopAsync();
            }
        }
    }
}
