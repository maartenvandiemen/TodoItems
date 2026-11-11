using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System;
using Testcontainers.MsSql;

namespace TodoItems.Api.IntegrationTests
{
    internal class TodoItemsApiApplication : WebApplicationFactory<Program>
    {
        private readonly MsSqlContainer? _container;

        private readonly Environment _environment;

        public TodoItemsApiApplication(Environment environment, MsSqlContainer? container) : base()
        {
            _environment = environment;

            if (_environment == Environment.TestContainers)
            {
                _container = container ?? throw new ArgumentNullException(nameof(environment));
            }
        }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddLogging(c => c.AddConsole());

                //First remove the DbContext registration added in the Program.cs if available
                services.RemoveDbContext<TodoDb>();

                if (_environment == Environment.InMemory)
                {
                    //Add a new InMemoryDatabase each time this class is initialized.
                    //We give the database each time a new name in order to ensure that tests can be executed in parallel.
                    //The context is scoped, but the options are singleton so all scopes share the same database name.
                    services.AddDbContext<TodoDb>(options => options.UseInMemoryDatabase(Guid.NewGuid().ToString()), ServiceLifetime.Scoped, ServiceLifetime.Singleton);
                }
                if (_environment == Environment.TestContainers)
                {
                    services.AddDbContext<TodoDb>(options => options.UseSqlServer(_container!.GetConnectionString()), ServiceLifetime.Scoped, ServiceLifetime.Singleton);
                }
            });

            builder.UseEnvironment(_environment.ToString());
        }
    }
}
