using System;
using System.Windows.Forms;
using System.IO;
using System.Runtime.InteropServices;

namespace ZertoComplianceLauncher
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (sender, e) => LogAndShow(e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (sender, e) =>
            {
                if (e.ExceptionObject is Exception ex)
                {
                    LogAndShow(ex);
                }
            };

            Log($"Launcher starting... Framework: {RuntimeInformation.FrameworkDescription}, OS: {RuntimeInformation.OSDescription}");
            try
            {
                Log("Constructing MainForm...");
                Application.Run(new MainForm());
                Log("Application.Run returned (normal exit)");
            }
            catch (Exception ex)
            {
                LogAndShow(ex);
            }
        }

        private static void LogAndShow(Exception ex)
        {
            try
            {
                var logPath = GetLogPath();
                File.AppendAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] EXCEPTION: {ex}\n\n");
                MessageBox.Show(
                    $"An unexpected error occurred.\n\n{ex.Message}\n\nDetails logged to: {logPath}",
                    "Zerto Compliance Launcher",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            catch
            {
                // Swallow any logging errors to avoid recursive crashes
            }
        }

        private static void Log(string message)
        {
            try
            {
                var logPath = GetLogPath();
                File.AppendAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}\n");
            }
            catch
            {
                // ignore
            }
        }

        private static string GetLogPath()
        {
            try
            {
                return Path.Combine(Path.GetTempPath(), "ZertoComplianceLauncher.log");
            }
            catch
            {
                // Fallback to Program Files folder
                var installDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ZertoCompliance");
                Directory.CreateDirectory(installDir);
                return Path.Combine(installDir, "ZertoComplianceLauncher.log");
            }
        }
    }
}
