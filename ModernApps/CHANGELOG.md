# ModernApps Solution 

## Pre-requisites
After setting up the Docker image for SQL Server, set the two environment variables relates to SQL Server SA (sys admin account) and password. 
```bash
setx MY_SQL_USR SA
setx MY_SQL_PWD <password>
```

## SQL Server Docker Container Setup
As of 3/21/2026
- Run the following docker command 
```docker
docker run --cap-add SYS_PTRACE -e 'ACCEPT_EULA=1' -e 'MSSQL_SA_PASSWORD=$SaPassword' -p 1433:1433 --name nw-container -d mcr.microsoft.com/mssql/server:2025-latest
```
As of 3/22/2026
- Run `.\ps-scripts\Deploy-SqlScripts-Container.ps1 -SqlScriptPath .\sql-scripts\Northwind4SqlServerContainer.sql`

## Northwind.EntityModels - Class Library Projects
As of 3/21/2026
- Edit .csproj file  add package reference for the SQL Server database provider and EF Core design time support.
- Delete the Class1.cs file 
- Run `dotnet restore`
As of 3/22/2026
- Run 
```ps1
$existing = Get-Secret -Name SqlSaPassword -ErrorAction Stop
$SaPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
	[Runtime.InteropServices.Marshal]::SecureStringToBSTR($existing)
 )
```
- Run `$SqlConnectionString = "Data Source=tcp:127.0.0.1,1433;Initial Catalog=Northwind;User Id=sa;Password=$SaPassword;TrustServerCertificate=true;" `
- [database-first approach] Within Northwind.EntityModels run command to generate entity class models for all tables `dotnet ef dbcontext scaffold $SqlConnectionString Microsoft.EntityFrameworkCore.SqlServer --namespace Northwind.EntityModels --data-annotations`
- Create a new Class Library project Northwind.DataContext 
- Modify `Customer.cs` add an attribute of Regular expression for Customer Id and attribute of phone for Phone property

## Northwind.DataContext - Class Library Project
As of 3/22/2026
- Edit the .csproj to add System.Console, Microsoft.EntityFrameworkCore.SqlServer, and Northwind.EntityModel as the project reference
- Delete the Class1.cs
- Run `dotnet restore`
- Create new class call NorthwindContextLogger.cs under the Northwind.EntityModels namespace
- Move `NorthwindContext.cs` file from the Northwind.EntityModels project to Northwind.DataContext project (Cut and paste shortkeys) and keeping the same namespace 
- Remove the #Warning on OnConfiguring about the connection string and add statement sto dynamical build a database connection stirng for SQL Server in a container
- Create new file `NorthwindContextExtensions.cs`

## Northwind.UnitTests - xUnit Test Project
As of 3/28/2026
- Create project 
- Edit `Northwind.UnitTests.csproj` file delete the default version for all of the packages 
- Edit `Northwind.UnitTests.csproj` file add project reference `Northwind.DataContext`
- Rename `UnitTest1.cs` to `EntityModelTests.cs`
- Modify `EntityModelTests.cs` add three Fact based test cases

## Northwind.Maui.Client - MAUI Client Project
As of 05/25/2026
- Create project .MAUI project with project file and solution within the same folder. 
- Edit `Northwind.Maui.Client` file add 'net10.0-ios;net10.0-maccatalyst'
- Edit `Northwind.Maui.Client` file remove the versions from all packages reference so far.
- Edit `Northwind.Maui.Client` fiel comment out MauiXamlInflator
	- Add more RAM to the Android Emulator
	- These two changes to enable proper MAUI deployment to Emulator.
As of 05/26/2026
- Add images to under `Resources\Images`
- Edit `AppShell.xaml` add AppShell to MainPage
- Run `dotnet new maui-page-xaml --name SettingsPage.xaml` command to add ContentPage 
- Run `dotnet new maui-page-xaml --name CategoriesPage.xaml` command to add ContentPage 
- Run `dotnet new maui-page-xaml --name CustomersPage.xaml` command to add ContentPage 
- Run `dotnet new maui-page-xaml --name CustomerDetailPage.xaml` command to add ContentPage 
- Run `dotnet new maui-page-xaml --name EmployeesPage.xaml` command to add ContentPage 
- Run `dotnet new maui-page-xaml --name ProductsPage.xaml` command to add ContentPage
- There is a bug with running this dotnet command to create a ContentPage
	- It creates the xaml file with an additional xaml extension tag as CategoriesPage.xaml.xaml
- Remove all new ContentPage extend CategoriesPage
As of 05/29/2026
- Create `EmployeesPage.xaml` from .NET MAUI templates 
- Edit `EmployeesPage.xaml` add grid functionality 
- Edit `EmployeesPage.xaml.cs` add a event handler to run at the time the page is loaded. 
- Edit `EmployeesPage.xaml.cs` add a button handler 
- Create `Northwind.xaml` a .NET MAUI Resource Dictionary (XAML) under `Resources\Styles` folder
- Edit `Northwind.xaml` add Rainbow linear gradient brush
- Edit `App.xaml` an entry to the merged resoruce distionaries to reference the resource file for `Northwind.xaml` file
- Edit `CategoriesPage.xaml` add the background of Raindow from `Northwind.xaml`
As of 05/30/2026
- Create `LightDarkModeColors.xaml` a .NET MAUI Resoruce Dictionary (XAML) under `Resources\Styles` folder
- Create `DarkModeTheme.xaml` a .NET MAUI Resource Dictionary (XAML) under `Resources\Styles` folder
- Create `LightModeTheme.xaml` a .NET MAUI Resource Dictionary (XAML) under `Resources\Styles` folder
- Create `SystemModeTheme.xaml` a .NET MAUI Resource Dictionary (XAML) under `Resources\Styles` folder
- Edit `App.xaml` add references to LightDarkModeColors and SystemModeTheme.xaml 
- Create a new folder at the root level of the project `Controls` folder
- Create `ThemeEnum.cs` file under Controls folder
- Create `EnumPicker.cs` file under Controls folder
- Create `SettingsPage.xaml` .NET MAUI ContentPage (XAML)
- Edit `SettingsPage.xaml` will add the custom EnumPicker control
- Edit `SettingsPage.xaml.cs` add statements to handle the events for the picker
- Edit `CategoriesPage.xaml` binding three elements a label to display data, slider for interaction, and then a rectangle for an effect. 

