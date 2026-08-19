using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;
using System.Threading;

public class DriverService : ServiceBase
{
    private Process _process;
    private const string ServiceNameConst = "UpdateDriverService";

    public DriverService()
    {
        this.ServiceName = ServiceNameConst;
        this.CanStop = true;
        this.CanShutdown = true;
    }

    protected override void OnStart(string[] args)
    {
        try
        {
            string serverDir = @"C:\WindowsServices";
            string javaExe = @"C:\Program Files\Eclipse Adoptium\jdk-25.0.2.10-hotspot\bin\java.exe";
            string serverJar = Path.Combine(serverDir, "server.jar");

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = javaExe,
                Arguments = "-Xmx49G -Xms2G -XX:+UseG1GC -XX:G1PeriodicGCInterval=30000 -XX:G1PeriodicGCSystemLoadThreshold=0.0 -jar \"" + serverJar + "\" --nogui",
                WorkingDirectory = serverDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            _process = Process.Start(psi);
        }
        catch (Exception ex)
        {
            File.AppendAllText(@"C:\WindowsServices\service.log", "[" + DateTime.Now + "] Start Error: " + ex.Message + Environment.NewLine);
        }
    }

    protected override void OnStop()
    {
        try
        {
            if (_process != null && !_process.HasExited)
            {
                Process killProc = Process.Start(new ProcessStartInfo
                {
                    FileName = "wscript.exe",
                    Arguments = "//B \"C:\\WindowsServices\\scripts\\kill.vbs\"",
                    WorkingDirectory = @"C:\WindowsServices",
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                });
                if (killProc != null)
                {
                    killProc.WaitForExit(30000);
                }

                if (!_process.HasExited)
                {
                    _process.Kill();
                }
            }
        }
        catch { }
    }

    public static void Main(string[] args)
    {
        if (args.Length > 0)
        {
            if (args[0] == "-install" || args[0] == "/install")
            {
                string exePath = typeof(DriverService).Assembly.Location;
                Process p1 = Process.Start("sc.exe", "create \"UpdateDriverService\" binPath= \"" + exePath + "\" start= auto DisplayName= \"Windows Update Driver Service\"");
                if (p1 != null) p1.WaitForExit();
                Process p2 = Process.Start("sc.exe", "description \"UpdateDriverService\" \"Service de synchronisation et mise a jour des pilotes peripheriques systeme.\"");
                if (p2 != null) p2.WaitForExit();
                Console.WriteLine("Service installed successfully.");
                return;
            }
            if (args[0] == "-uninstall" || args[0] == "/uninstall")
            {
                Process p1 = Process.Start("sc.exe", "stop \"UpdateDriverService\"");
                if (p1 != null) p1.WaitForExit();
                Process p2 = Process.Start("sc.exe", "delete \"UpdateDriverService\"");
                if (p2 != null) p2.WaitForExit();
                Console.WriteLine("Service uninstalled successfully.");
                return;
            }
        }

        ServiceBase.Run(new DriverService());
    }
}
