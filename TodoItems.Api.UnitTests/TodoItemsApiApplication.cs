using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using System;
using System.IO;
using System.Linq;

namespace TodoItems.Api.UnitTests
{
    internal class TodoItemsApiApplication : WebApplicationFactory<Program>
    {
        private readonly Environment _environment;

        public IConfiguration Configuration { get; private set; } = default!;

        public TodoItemsApiApplication(Environment environment) : base() => _environment = environment;

        //Use CreateHost for overriding AppSettings: https://github.com/dotnet/AspNetCore.Docs/issues/25364
        protected override IHost CreateHost(IHostBuilder builder)
        {
            builder.ConfigureHostConfiguration(config =>
            {
                config.SetBasePath(Directory.GetCurrentDirectory());
                config.AddJsonFile("appsettings.integration.json");
                config.AddEnvironmentVariables(prefix: "integrationtests_");
            });

            return base.CreateHost(builder);
        }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            if (_environment == Environment.Development)
            {
                builder.ConfigureTestServices(services =>
                {
                    //First remove the serviceDescriptor added in the Program.cs if available
                    var descriptor = services.SingleOrDefault(
                        d => d.ServiceType ==
                            typeof(DbContextOptions<TodoDb>));

                    if (descriptor is not null)
                    {
                        services.Remove(descriptor);
                    }

                    //Add a new InMemoryDatabase each time this class is initialized.
                    //We give the database each time a new name in order to ensure that tests can be executed in parallel.
                    //Lifetime is singleton within this class. Since some tests might create multiple Scopes the Singleton is the safest.
                    services.AddDbContext<TodoDb>(options => options.UseInMemoryDatabase(Guid.NewGuid().ToString()), ServiceLifetime.Singleton);
                });
            }

            builder.UseEnvironment(_environment.ToString());
        }
    }
}
