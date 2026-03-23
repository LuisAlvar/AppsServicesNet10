using Microsoft.Data.SqlClient;                 // To use SqlConnectionStringBuilder
using Microsoft.EntityFrameworkCore;            // To use UseSqlServer
using Microsoft.Extensions.DependencyInjection; // To use IServiceCollection

namespace Northwind.EntityModels;

public static class NorthwindContextExtensions
{
    public static IServiceCollection AddNorthwindContext(
        this IServiceCollection services, // The type to extend.
        string? connectionString = null)
    {
        if (connectionString is null)
        {
            SqlConnectionStringBuilder builder = new();

            builder.DataSource = "tcp:127.0.0.1,1433";
            builder.InitialCatalog = "Northwind";
            builder.TrustServerCertificate = true;
            builder.MultipleActiveResultSets = true;
            // Because we want to fail faster. Default is 15 seconds
            builder.ConnectTimeout = 3;

            // SQL Server authentication
            builder.UserID = Environment.GetEnvironmentVariable("MY_SQL_USR");
            builder.Password = Environment.GetEnvironmentVariable("MY_SQL_PWD");

            connectionString = builder.ConnectionString;
        }

        services.AddDbContext<NorthwindContext>(options => { 
            options.UseSqlServer(connectionString);
            options.LogTo(NorthwindContextLogger.WriteLine,
                new[] { Microsoft.EntityFrameworkCore.Diagnostics.RelationalEventId.CommandExecuting });
        }, 
            // Register with a transient lifetime to avoid
            // concurrent issues with Blazor Server projects.
            contextLifetime: ServiceLifetime.Transient, 
            optionsLifetime: ServiceLifetime.Transient
        );

        return services;
    }
}
