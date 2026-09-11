FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Rover.sln ./
COPY Rover.Api/Rover.Api.csproj Rover.Api/
COPY Rover.Application/Rover.Application.csproj Rover.Application/
COPY Rover.Domain/Rover.Domain.csproj Rover.Domain/
COPY Rover.Infrastructure/Rover.Infrastructure.csproj Rover.Infrastructure/
COPY Rover.Tests/Rover.Tests.csproj Rover.Tests/
RUN dotnet restore Rover.sln
COPY . .
RUN dotnet publish Rover.Api/Rover.Api.csproj -c Release -o /app/publish --no-restore

FROM runtime AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "Rover.Api.dll"]
