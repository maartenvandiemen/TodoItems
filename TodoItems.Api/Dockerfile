FROM mcr.microsoft.com/dotnet/aspnet:10.0.0-rc.2
COPY . /app
WORKDIR /app
ENTRYPOINT ["dotnet", "TodoItems.Api.dll"]
EXPOSE 8080
USER user