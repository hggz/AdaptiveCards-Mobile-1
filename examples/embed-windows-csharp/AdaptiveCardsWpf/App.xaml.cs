// App.xaml.cs
//
// Application entry point. Sets up the native DLL search path BEFORE
// any P/Invoke happens so the AdaptiveCardsCABIShared.dll + its
// Swift-runtime transitive deps resolve at LoadLibrary time.

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;

namespace AdaptiveCardsWpf;

public partial class App : Application
{
    // Win32 SetDllDirectory. We could use AddDllDirectory + LOAD_LIBRARY_SEARCH_USER_DIRS
    // but SetDllDirectory is the simplest "prepend N to the loader path"
    // hook and works for our single-process scope.
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetDllDirectory(string lpPathName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr AddDllDirectory(string newDirectory);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetDefaultDllDirectories(uint directoryFlags);

    private const uint LOAD_LIBRARY_SEARCH_DEFAULT_DIRS = 0x00001000;
    private const uint LOAD_LIBRARY_SEARCH_USER_DIRS    = 0x00000400;

    protected override void OnStartup(StartupEventArgs e)
    {
        // Resolution order:
        //   1. ios/.build/x86_64-unknown-windows-msvc/debug/  (the Swift .dll)
        //   2. $HOME\AppData\Local\Programs\Swift\Runtimes\<ver>\usr\bin (Swift runtime)
        // If either is missing we surface a friendly error rather than
        // the cryptic 0x80131524 'Unable to load DLL' P/Invoke message.
        var repoBuild = FindRepoSwiftBuildDir();
        var swiftRuntime = FindSwiftRuntimeBinDir();

        // SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_USER_DIRS) lets us
        // use AddDllDirectory; falling back to SetDllDirectory if that
        // call fails (older Win10 without KB).
        try
        {
            SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
            if (repoBuild != null)    { AddDllDirectory(repoBuild); }
            if (swiftRuntime != null) { AddDllDirectory(swiftRuntime); }
        }
        catch (DllNotFoundException)
        {
            SetDllDirectory(repoBuild ?? swiftRuntime ?? Environment.CurrentDirectory);
        }

        // Also prepend to PATH so any child process / Marshal.LoadLibrary
        // call sees them.
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        var parts = new System.Collections.Generic.List<string>();
        if (repoBuild != null)    { parts.Add(repoBuild); }
        if (swiftRuntime != null) { parts.Add(swiftRuntime); }
        if (!string.IsNullOrEmpty(path)) { parts.Add(path); }
        Environment.SetEnvironmentVariable("PATH", string.Join(";", parts));

        base.OnStartup(e);
    }

    /// <summary>
    /// Walks up from the .NET app's working directory looking for the
    /// repo root (the folder that contains `ios/.build/`). Returns the
    /// resolved Swift .build/debug directory if found.
    /// </summary>
    private static string? FindRepoSwiftBuildDir()
    {
        // First try a known relative path from the typical
        // `dotnet run --project examples/embed-windows-csharp/AdaptiveCardsWpf`
        // invocation point (cwd = repo root).
        var candidate = Path.Combine(
            Environment.CurrentDirectory,
            "ios",
            ".build",
            "x86_64-unknown-windows-msvc",
            "debug");
        if (Directory.Exists(candidate) &&
            File.Exists(Path.Combine(candidate, "AdaptiveCardsCABIShared.dll")))
        {
            return candidate;
        }

        // Walk up from the .exe location.
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 8; i++)
        {
            var probe = Path.Combine(dir, "ios", ".build", "x86_64-unknown-windows-msvc", "debug");
            if (Directory.Exists(probe) &&
                File.Exists(Path.Combine(probe, "AdaptiveCardsCABIShared.dll")))
            {
                return probe;
            }
            var parent = Directory.GetParent(dir);
            if (parent == null) { break; }
            dir = parent.FullName;
        }
        return null;
    }

    /// <summary>
    /// Locate the Swift runtime bin directory the AdaptiveCardsCABIShared
    /// DLL transitively depends on (swiftCore.dll, swiftDispatch.dll,
    /// swiftFoundation.dll, ...). On a winget-installed Swift toolchain
    /// these live under
    /// `$HOME\AppData\Local\Programs\Swift\Runtimes\<ver>\usr\bin`.
    /// </summary>
    private static string? FindSwiftRuntimeBinDir()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var runtimes = Path.Combine(home, "AppData", "Local", "Programs", "Swift", "Runtimes");
        if (!Directory.Exists(runtimes)) { return null; }
        var versions = Directory.GetDirectories(runtimes);
        if (versions.Length == 0) { return null; }
        // Pick the highest-numbered version available.
        Array.Sort(versions);
        var bin = Path.Combine(versions[^1], "usr", "bin");
        return Directory.Exists(bin) ? bin : null;
    }
}
