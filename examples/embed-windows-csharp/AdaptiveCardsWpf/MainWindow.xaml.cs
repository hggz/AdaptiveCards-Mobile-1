// MainWindow.xaml.cs
//
// Wires the sample picker → ac_host_render_json → IR walker → WPF
// content. Holds a single AdaptiveCardsCabi host for the lifetime of
// the window and tears it down on close.

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;

namespace AdaptiveCardsWpf;

public partial class MainWindow : Window
{
    private IntPtr _host = IntPtr.Zero;
    private readonly RenderingNodeWalker _walker;
    private string? _cardsDir;

    public MainWindow()
    {
        InitializeComponent();
        _walker = new RenderingNodeWalker(line => AppendTranscript(line));
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            _host = AdaptiveCardsCabi.CreateHost(null);
            if (_host == IntPtr.Zero)
            {
                ShowFatal("ac_host_create returned null. "
                          + (AdaptiveCardsCabi.PeekLastError() ?? "(no error)"));
                return;
            }

            var backendPtr = AdaptiveCardsCabi.BackendIdentifier(_host);
            var backend = AdaptiveCardsCabi.ReadAndFreeUtf8(backendPtr);
            BackendLabel.Text = $"Swift backend: {backend ?? "(unknown)"}    DLL: AdaptiveCardsCABIShared.dll";

            _cardsDir = LocateCardsDirectory();
            if (_cardsDir == null)
            {
                ShowFatal("Could not locate shared/test-cards/ — run from repo root.");
                return;
            }

            // Same curated reference set the Swift demo uses.
            foreach (var name in new[]
            {
                "simple-text.json",
                "containers.json",
                "input-form.json",
                "all-actions.json",
                "table.json",
                "rating.json",
                "edge-empty-card.json",
                "windows-extras.json",
            })
            {
                SampleCombo.Items.Add(name);
            }
            SampleCombo.SelectedItem = "windows-extras.json";
        }
        catch (DllNotFoundException ex)
        {
            ShowFatal("AdaptiveCardsCABIShared.dll could not be loaded: "
                      + ex.Message
                      + "\n\nBuild it first with:  cd ios && swift build --product AdaptiveCardsCABIShared");
        }
        catch (Exception ex)
        {
            ShowFatal($"{ex.GetType().Name}: {ex.Message}");
        }
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        if (_host != IntPtr.Zero)
        {
            AdaptiveCardsCabi.DestroyHost(_host);
            _host = IntPtr.Zero;
        }
    }

    private void SampleCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_host == IntPtr.Zero) { return; }
        if (SampleCombo.SelectedItem is not string name) { return; }
        if (_cardsDir == null) { return; }
        try
        {
            var cardJson = File.ReadAllText(Path.Combine(_cardsDir, name));
            var irPtr = AdaptiveCardsCabi.RenderJson(_host, cardJson);
            var irJson = AdaptiveCardsCabi.ReadAndFreeUtf8(irPtr);
            if (string.IsNullOrEmpty(irJson))
            {
                CardContainer.Content = new TextBlock
                {
                    Text = $"ac_host_render_json returned empty for {name}. "
                           + (AdaptiveCardsCabi.PeekLastError() ?? "(no error)"),
                    Foreground = System.Windows.Media.Brushes.Salmon,
                };
                return;
            }
            CardContainer.Content = _walker.Build(irJson);
            AppendTranscript($"loaded {name}  ({irJson.Length} bytes IR)");
        }
        catch (Exception ex)
        {
            CardContainer.Content = new TextBlock
            {
                Text = $"Render failed: {ex.GetType().Name} — {ex.Message}",
                Foreground = System.Windows.Media.Brushes.Salmon,
            };
        }
    }

    private string? LocateCardsDirectory()
    {
        var probe = Path.Combine(Environment.CurrentDirectory, "shared", "test-cards");
        if (Directory.Exists(probe)) { return probe; }
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 8; i++)
        {
            probe = Path.Combine(dir, "shared", "test-cards");
            if (Directory.Exists(probe)) { return probe; }
            var parent = Directory.GetParent(dir);
            if (parent == null) { break; }
            dir = parent.FullName;
        }
        return null;
    }

    private void AppendTranscript(string line)
    {
        TranscriptList.Items.Add(new TextBlock { Text = $"[{DateTime.Now:HH:mm:ss}] {line}" });
        if (TranscriptList.Items.Count > 50)
        {
            TranscriptList.Items.RemoveAt(0);
        }
    }

    private void ShowFatal(string message)
    {
        CardContainer.Content = new TextBlock
        {
            Text = message,
            Foreground = System.Windows.Media.Brushes.Salmon,
            TextWrapping = TextWrapping.Wrap,
        };
    }
}
