using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;

namespace ArchMCP.Hub.App;

public partial class App : Application
{
    private static readonly string LogDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ArchMCP Hub", "Logs");
    private static string LogFile => Path.Combine(LogDirectory, "startup.log");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            WriteLog("AppDomain unhandled exception", args.ExceptionObject?.ToString() ?? "Unknown exception");
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            WriteLog("Unobserved task exception", args.Exception.ToString());
            args.SetObserved();
        };

        try
        {
            WriteLog("Startup", $"Starting ArchMCP Hub. OS={Environment.OSVersion}; 64-bit={Environment.Is64BitProcess}");
            var window = new MainWindow();
            MainWindow = window;
            window.Show();
            WriteLog("Startup", "MainWindow displayed successfully.");
        }
        catch (Exception ex)
        {
            WriteLog("Startup failed", ex.ToString());
            MessageBox.Show(
                $"ArchMCP Hub could not open. A diagnostic log was saved here:\n{LogFile}\n\n{ex.Message}",
                "ArchMCP Hub — Startup error", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(-1);
        }
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        WriteLog("UI exception", e.Exception.ToString());
        MessageBox.Show(
            $"ArchMCP Hub encountered an error. Diagnostic log:\n{LogFile}\n\n{e.Exception.Message}",
            "ArchMCP Hub — Application error", MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }

    private static void WriteLog(string title, string details)
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            File.AppendAllText(LogFile,
                $"[{DateTimeOffset.Now:O}] {title}{Environment.NewLine}{details}{Environment.NewLine}{new string('-', 70)}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must never cause a second startup failure.
        }
    }
}
