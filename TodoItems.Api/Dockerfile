FROM mcr.microsoft.com/dotnet/aspnet:9.0
COPY . /app
WORKDIR /app
ENTRYPOINT ["dotnet", "TodoItems.Api.dll"]
EXPOSE 8080
USER user