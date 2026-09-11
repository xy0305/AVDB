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
        try
        {
            MessageBox.Show(args.Exception.Message, "AVDB", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch { }
    }

    static void OnDomainException(object sender, UnhandledExceptionEventArgs args)
    {
        // 避免未处理异常直接闪退到桌面且无提示。
    }

    static void OnTaskException(object? sender, UnobservedTaskExceptionEventArgs args)
    {
        args.SetObserved();
    }
}
