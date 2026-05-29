using Microsoft.Extensions.DependencyInjection;

namespace Northwind.Maui.Client
{
  public partial class App : Application
  {
    public App()
    {
      try
      {
        InitializeComponent();
      }
      catch (Exception ex)
      {
        System.Diagnostics.Debug.WriteLine($"STARTUP CRASH: {ex}");
        throw;
      }
      
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
      return new Window(new AppShell());
    }
  }
}