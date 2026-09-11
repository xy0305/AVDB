using System.Text;
using System.Windows;
using System.Windows.Threading;

namespace AVDB.Win;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += OnUiException;
        AppDomain.CurrentDomain.UnhandledException += OnDomainException;
        TaskScheduler.UnobservedTaskException += OnTaskException;
        base.OnStartup(e);
    }

    static void OnUiException(object sender, DispatcherUnhandledExceptionEventArgs args)
    {
        args.Handled = true;
        ShowError(args.Exception);
    }

    static void OnDomainException(object sender, UnhandledExceptionEventArgs args)
    {
        if (args.ExceptionObject is Exception ex)
            ShowError(ex);
    }

    static void OnTaskException(object? sender, UnobservedTaskExceptionEventArgs args)
    {
        args.SetObserved();
        ShowError(args.Exception);
    }

    static void ShowError(Exception ex)
    {
        try
        {
            var sb = new StringBuilder();
            for (var e = ex; e != null; e = e.InnerException)
            {
                sb.AppendLine(e.GetType().Name + ": " + e.Message);
            }
            MessageBox.Show(sb.ToString(), "AVDB", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch { }
    }
}
