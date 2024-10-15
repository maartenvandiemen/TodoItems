using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System;
using System.IO;
using System.Linq;
using Testcontainers.MsSql;

namespace TodoItems.Api.IntegrationTests
{
    internal class TodoItemsApiApplication : WebApplicationFactory<Program>
    {
        private readonly MsSqlContainer? _container;

        private readonly Environment _environment;

        public IConfiguration Configuration { get; private set; } = default!;

        public TodoItemsApiApplication(Environment environment, MsSqlContainer? container) : base()
        {
            _environment = environment;

            if (_environment == Environment.TestContainers)
            {
                _container = container ?? throw new ArgumentNullException(nameof(environment));
            }
        }

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
            if (_environment == Environment.InMemory || _environment == Environment.TestContainers)
            {
                builder.ConfigureTestServices(services =>
                {
                    services.AddLogging(c => c.AddConsole());

                    //First remove the serviceDescriptor added in the Program.cs if available
                    RemoveServiceDescriptor(services, typeof(DbContextOptions<TodoDb>));
                    RemoveServiceDescriptor(services, typeof(IDbContextOptionsConfiguration<TodoDb>));

                    if (_environment == Environment.InMemory)
                    {
                        //Add a new InMemoryDatabase each time this class is initialized.
                        //We give the database each time a new name in order to ensure that tests can be executed in parallel.
                        //Lifetime is singleton within this class. Since some tests might create multiple Scopes the Singleton is the safest.
                        services.AddDbContext<TodoDb>(options => options.UseInMemoryDatabase(Guid.NewGuid().ToString()), ServiceLifetime.Singleton);
                    }
                    if (_environment == Environment.TestContainers)
                    {
                        services.AddDbContext<TodoDb>(options => options.UseSqlServer(_container!.GetConnectionString()), ServiceLifetime.Singleton);
                    }
                });
            }

            builder.UseEnvironment(_environment.ToString());
        }

        private static void RemoveServiceDescriptor(IServiceCollection services, Type serviceType)
        {
            var descriptor = services.SingleOrDefault(d => d.ServiceType == serviceType);
            if (descriptor is not null)
            {
                services.Remove(descriptor);
            }
        }
    }
}
