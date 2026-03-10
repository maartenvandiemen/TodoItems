using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using TodoItems.Blazor;
using TodoItems.Blazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddHttpClient("TodoApi", c =>
    c.BaseAddress = new Uri(builder.Configuration["ApiBaseUrl"]!));

builder.Services.AddScoped<TodoApiService>();

await builder.Build().RunAsync();
