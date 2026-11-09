FROM mcr.microsoft.com/dotnet/aspnet:11.0.0-rc.3
COPY . /app
WORKDIR /app
ENTRYPOINT ["dotnet", "TodoItems.Api.dll"]
EXPOSE 8080
USER user