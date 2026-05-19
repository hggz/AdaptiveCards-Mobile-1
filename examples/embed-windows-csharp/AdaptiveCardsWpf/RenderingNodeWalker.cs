// RenderingNodeWalker.cs
//
// Walks the RenderingNode IR JSON (Codable form produced by
// AdaptiveCardsCABI.ac_host_render_json) and builds a WPF control
// tree. The `"type"` field is the discriminator; cases match the Swift
// Discriminator enum in
// ios/Sources/AdaptiveCardsCrossUI/Rendering/RenderingNode+Codable.swift.
//
// POC scope. This walker covers the visible majority of cases as real
// WPF controls (TextBlock, Image, StackPanel, Button, CheckBox,
// TextBox, ComboBox, ProgressBar, Expander, Grid, TabControl). Cases
// not handled fall through to a gray "[Unhandled in WPF POC: <kind>]"
// TextBlock so the user can see exactly what's missing without the UI
// crashing. The full set is gated by the IR + a11y baselines in
// AdaptiveCardsValidate, so this host doesn't need to be exhaustive.

using System;
using System.IO;
using System.Net;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AdaptiveCardsWpf;

internal sealed class RenderingNodeWalker
{
    private readonly Action<string>? _onActionLog;

    public RenderingNodeWalker(Action<string>? onActionLog = null)
    {
        _onActionLog = onActionLog;
    }

    public UIElement Build(string irJson)
    {
        using var doc = JsonDocument.Parse(irJson);
        return Build(doc.RootElement);
    }

    private UIElement Build(JsonElement node)
    {
        var type = node.GetProperty("type").GetString() ?? "";
        return type switch
        {
            "text"            => BuildText(node),
            "richRun"         => BuildRichRun(node),
            "image"           => BuildImage(node),
            "verticalStack"   => BuildStack(node, Orientation.Vertical),
            "horizontalStack" => BuildStack(node, Orientation.Horizontal),
            "facts"           => BuildFacts(node),
            "code"            => BuildCode(node),
            "textField"       => BuildTextField(node),
            "numberField"     => BuildTextField(node),
            "toggleField"     => BuildToggle(node),
            "choiceField"     => BuildChoice(node),
            "progressBar"     => BuildProgress(node),
            "spinner"         => BuildSpinner(node),
            "accordion"       => BuildAccordion(node),
            "table"           => BuildTable(node),
            "rating"          => BuildRating(node),
            "ratingField"     => BuildRatingField(node),
            "dateField"       => BuildDateField(node),
            "list"            => BuildList(node),
            "chart"           => BuildChart(node),
            "tabSet"          => BuildTabSet(node),
            "carousel"        => BuildCarousel(node),
            "compoundButton"  => BuildCompoundButton(node),
            "button"          => BuildButton(node),
            "unsupported"     => Stub("Unsupported by Swift renderer: "
                                       + node.GetPropertyOrDefault("typeString", "?")),
            _                 => Stub($"Unhandled in WPF POC: {type}"),
        };
    }

    // MARK: - Leaf nodes

    private TextBlock BuildText(JsonElement n)
    {
        var tb = new TextBlock
        {
            Text = n.GetPropertyOrDefault("string", ""),
            TextWrapping = n.GetPropertyOrFalse("wrap")
                ? TextWrapping.Wrap : TextWrapping.NoWrap,
            Margin = new Thickness(0, 2, 0, 2),
        };
        var size = n.GetPropertyOrDefault("size", "default");
        var weight = n.GetPropertyOrDefault("weight", "default");
        var isSubtle = n.GetPropertyOrFalse("isSubtle");
        tb.FontSize = size switch
        {
            "extraLarge" => 22,
            "large"      => 18,
            "medium"     => 15,
            "small"      => 11,
            _            => 13,
        };
        tb.FontWeight = weight switch
        {
            "bolder"  => FontWeights.Bold,
            "lighter" => FontWeights.Light,
            _         => FontWeights.Normal,
        };
        if (isSubtle)
        {
            tb.Opacity = 0.6;
        }
        return tb;
    }

    private TextBlock BuildRichRun(JsonElement n)
    {
        // Same as text + italic/underline/strikethrough.
        var tb = BuildText(n);
        if (n.GetPropertyOrFalse("italic"))
        {
            tb.FontStyle = FontStyles.Italic;
        }
        if (n.GetPropertyOrFalse("underline"))
        {
            tb.TextDecorations = TextDecorations.Underline;
        }
        if (n.GetPropertyOrFalse("strikethrough"))
        {
            tb.TextDecorations = TextDecorations.Strikethrough;
        }
        return tb;
    }

    private UIElement BuildImage(JsonElement n)
    {
        var url = n.GetPropertyOrDefault("url", "");
        var alt = n.GetPropertyOrDefault("alt", "");
        var hint = n.GetPropertyOrDefault("displayHint", "medium");
        var (w, h) = hint switch
        {
            "small"   => (40.0, 40.0),
            "medium"  => (80.0, 80.0),
            "large"   => (160.0, 160.0),
            "stretch" => (double.NaN, double.NaN),
            _         => (80.0, 80.0),
        };
        var panel = new StackPanel { Orientation = Orientation.Vertical };
        try
        {
            var img = new Image { Stretch = Stretch.Uniform };
            if (!double.IsNaN(w)) { img.Width = w; }
            if (!double.IsNaN(h)) { img.Height = h; }
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(url, UriKind.Absolute);
            bmp.EndInit();
            img.Source = bmp;
            panel.Children.Add(img);
        }
        catch
        {
            panel.Children.Add(new TextBlock
            {
                Text = $"[Image: {(string.IsNullOrEmpty(alt) ? url : alt)}]",
                Opacity = 0.6,
            });
        }
        if (!string.IsNullOrEmpty(alt))
        {
            panel.Children.Add(new TextBlock { Text = alt, FontSize = 11, Opacity = 0.8 });
        }
        return panel;
    }

    private StackPanel BuildStack(JsonElement n, Orientation orient)
    {
        var panel = new StackPanel
        {
            Orientation = orient,
            Margin = new Thickness(0, 2, 0, 2),
        };
        foreach (var child in n.GetProperty("children").EnumerateArray())
        {
            panel.Children.Add(Build(child));
        }
        return panel;
    }

    private Grid BuildFacts(JsonElement n)
    {
        var grid = new Grid { Margin = new Thickness(0, 2, 0, 2) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var pairs = n.GetProperty("pairs");
        for (var i = 0; i < pairs.GetArrayLength(); i++)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }
        var idx = 0;
        foreach (var pair in pairs.EnumerateArray())
        {
            var title = new TextBlock
            {
                Text = pair.GetPropertyOrDefault("title", "") + ":",
                Margin = new Thickness(0, 1, 8, 1),
                FontWeight = FontWeights.Bold,
            };
            var value = new TextBlock
            {
                Text = pair.GetPropertyOrDefault("value", ""),
                Margin = new Thickness(0, 1, 0, 1),
            };
            Grid.SetRow(title, idx);
            Grid.SetColumn(title, 0);
            Grid.SetRow(value, idx);
            Grid.SetColumn(value, 1);
            grid.Children.Add(title);
            grid.Children.Add(value);
            idx++;
        }
        return grid;
    }

    private TextBlock BuildCode(JsonElement n)
    {
        return new TextBlock
        {
            Text = n.GetPropertyOrDefault("text", ""),
            FontFamily = new FontFamily("Consolas"),
            Background = new SolidColorBrush(Color.FromRgb(0x1e, 0x1e, 0x1e)),
            Foreground = new SolidColorBrush(Color.FromRgb(0xd4, 0xd4, 0xd4)),
            Padding = new Thickness(8),
            Margin = new Thickness(0, 2, 0, 2),
        };
    }

    // MARK: - Inputs

    private StackPanel BuildTextField(JsonElement n)
    {
        var label = n.GetPropertyOrNull("label");
        var placeholder = n.GetPropertyOrDefault("placeholder", "");
        var value = n.GetPropertyOrNull("value");
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.Bold });
        }
        var box = new TextBox
        {
            Text = value ?? "",
            Padding = new Thickness(4),
            Tag = placeholder,  // POC: WPF doesn't have a placeholder API
        };
        stack.Children.Add(box);
        return stack;
    }

    private StackPanel BuildToggle(JsonElement n)
    {
        var title = n.GetPropertyOrDefault("title", "");
        var label = n.GetPropertyOrNull("label");
        var value = n.GetPropertyOrFalse("value");
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.Bold });
        }
        stack.Children.Add(new CheckBox { Content = title, IsChecked = value });
        return stack;
    }

    private StackPanel BuildChoice(JsonElement n)
    {
        var label = n.GetPropertyOrNull("label");
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.Bold });
        }
        var combo = new ComboBox();
        if (n.TryGetProperty("choices", out var choices))
        {
            foreach (var c in choices.EnumerateArray())
            {
                combo.Items.Add(c.GetPropertyOrDefault("title", c.GetPropertyOrDefault("value", "")));
            }
        }
        var selected = n.GetPropertyOrNull("selected");
        if (selected != null) { combo.SelectedItem = selected; }
        stack.Children.Add(combo);
        return stack;
    }

    private StackPanel BuildProgress(JsonElement n)
    {
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        var label = n.GetPropertyOrNull("label");
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label });
        }
        var value = n.GetPropertyOrDouble("value", 0);
        stack.Children.Add(new ProgressBar
        {
            Minimum = 0,
            Maximum = 1,
            Value = value,
            Height = 14,
            Margin = new Thickness(0, 2, 0, 0),
        });
        return stack;
    }

    private StackPanel BuildSpinner(JsonElement n)
    {
        var stack = new StackPanel { Orientation = Orientation.Horizontal };
        stack.Children.Add(new ProgressBar
        {
            IsIndeterminate = true,
            Width = 80,
            Height = 14,
        });
        var label = n.GetPropertyOrNull("label");
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label, Margin = new Thickness(8, 0, 0, 0) });
        }
        return stack;
    }

    private StackPanel BuildAccordion(JsonElement n)
    {
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        foreach (var panel in n.GetProperty("panels").EnumerateArray())
        {
            var exp = new Expander
            {
                Header = panel.GetPropertyOrDefault("title", "(untitled)"),
                IsExpanded = panel.GetPropertyOrFalse("isExpanded"),
                Margin = new Thickness(0, 2, 0, 2),
            };
            var body = new StackPanel { Orientation = Orientation.Vertical };
            if (panel.TryGetProperty("content", out var content))
            {
                foreach (var child in content.EnumerateArray())
                {
                    body.Children.Add(Build(child));
                }
            }
            exp.Content = body;
            stack.Children.Add(exp);
        }
        return stack;
    }

    private Grid BuildTable(JsonElement n)
    {
        var grid = new Grid { Margin = new Thickness(0, 4, 0, 4) };
        var rows = new System.Collections.Generic.List<JsonElement>();
        if (n.TryGetProperty("headers", out var headers) && headers.ValueKind == JsonValueKind.Array)
        {
            rows.Add(headers);
        }
        if (n.TryGetProperty("rows", out var bodyRows))
        {
            foreach (var r in bodyRows.EnumerateArray())
            {
                rows.Add(r);
            }
        }
        var maxCols = 0;
        foreach (var r in rows)
        {
            maxCols = Math.Max(maxCols, r.GetArrayLength());
        }
        for (var c = 0; c < maxCols; c++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        }
        for (var i = 0; i < rows.Count; i++)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }
        var isFirstHeader = headers.ValueKind == JsonValueKind.Array;
        for (var rIdx = 0; rIdx < rows.Count; rIdx++)
        {
            var row = rows[rIdx];
            var cIdx = 0;
            foreach (var cell in row.EnumerateArray())
            {
                var cellPanel = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(8, 4, 8, 4) };
                if (isFirstHeader && rIdx == 0) { cellPanel.Background = new SolidColorBrush(Color.FromRgb(0x2d, 0x2d, 0x30)); }
                foreach (var child in cell.EnumerateArray())
                {
                    cellPanel.Children.Add(Build(child));
                }
                Grid.SetRow(cellPanel, rIdx);
                Grid.SetColumn(cellPanel, cIdx);
                grid.Children.Add(cellPanel);
                cIdx++;
            }
        }
        return grid;
    }

    private TextBlock BuildRating(JsonElement n)
    {
        var value = n.GetPropertyOrDouble("value", 0);
        var max = n.GetPropertyOrInt("max", 5);
        var count = n.TryGetProperty("count", out var c) && c.ValueKind == JsonValueKind.Number ? c.GetInt32() : (int?)null;
        var filled = (int)Math.Round(value);
        var stars = new string('★', filled) + new string('☆', Math.Max(0, max - filled));
        var text = count.HasValue ? $"{stars}  ({count})" : stars;
        return new TextBlock { Text = text, FontSize = 16 };
    }

    private StackPanel BuildRatingField(JsonElement n)
    {
        var label = n.GetPropertyOrNull("label");
        var value = (int)Math.Round(n.GetPropertyOrDouble("value", 0));
        var max = n.GetPropertyOrInt("max", 5);
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.Bold });
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 1; i <= Math.Max(max, 1); i++)
        {
            var star = i;
            var btn = new Button
            {
                Content = star <= value ? "★" : "☆",
                FontSize = 18,
                Margin = new Thickness(0, 0, 4, 0),
                Padding = new Thickness(4, 0, 4, 0),
            };
            btn.Click += (_, _) =>
            {
                // Mutate the row in-place for the POC.
                for (var k = 0; k < row.Children.Count; k++)
                {
                    if (row.Children[k] is Button b)
                    {
                        b.Content = (k + 1) <= star ? "★" : "☆";
                    }
                }
                _onActionLog?.Invoke($"rating set to {star}");
            };
            row.Children.Add(btn);
        }
        stack.Children.Add(row);
        return stack;
    }

    private StackPanel BuildDateField(JsonElement n)
    {
        var label = n.GetPropertyOrNull("label");
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        if (!string.IsNullOrEmpty(label))
        {
            stack.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.Bold });
        }
        stack.Children.Add(new DatePicker());
        return stack;
    }

    private StackPanel BuildList(JsonElement n)
    {
        var style = n.GetPropertyOrDefault("style", "default");
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        var idx = 1;
        foreach (var item in n.GetProperty("items").EnumerateArray())
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            string marker = style switch
            {
                "bulleted" => "•",
                "numbered" => $"{idx}.",
                _ => "",
            };
            if (!string.IsNullOrEmpty(marker))
            {
                row.Children.Add(new TextBlock
                {
                    Text = marker,
                    Margin = new Thickness(0, 0, 6, 0),
                    MinWidth = 20,
                });
            }
            row.Children.Add(Build(item));
            stack.Children.Add(row);
            idx++;
        }
        return stack;
    }

    private StackPanel BuildChart(JsonElement n)
    {
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 6, 0, 6) };
        var title = n.GetPropertyOrNull("title");
        if (!string.IsNullOrEmpty(title))
        {
            stack.Children.Add(new TextBlock
            {
                Text = title,
                FontWeight = FontWeights.Bold,
                Margin = new Thickness(0, 0, 0, 4),
            });
        }
        var data = n.GetProperty("data");
        double max = 1;
        foreach (var d in data.EnumerateArray())
        {
            max = Math.Max(max, Math.Abs(d.GetPropertyOrDouble("value", 0)));
        }
        foreach (var d in data.EnumerateArray())
        {
            var row = new Grid { Margin = new Thickness(0, 1, 0, 1) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
            var label = new TextBlock { Text = d.GetPropertyOrDefault("label", "") };
            Grid.SetColumn(label, 0);
            row.Children.Add(label);
            var bar = new ProgressBar
            {
                Minimum = 0,
                Maximum = max,
                Value = Math.Abs(d.GetPropertyOrDouble("value", 0)),
                Height = 16,
                Margin = new Thickness(4, 0, 4, 0),
            };
            var color = d.GetPropertyOrNull("color");
            if (!string.IsNullOrEmpty(color) && TryParseHex(color, out var brush))
            {
                bar.Foreground = brush;
            }
            Grid.SetColumn(bar, 1);
            row.Children.Add(bar);
            var value = new TextBlock { Text = d.GetPropertyOrDouble("value", 0).ToString("0.##") };
            Grid.SetColumn(value, 2);
            row.Children.Add(value);
            stack.Children.Add(row);
        }
        return stack;
    }

    private TabControl BuildTabSet(JsonElement n)
    {
        var tabs = new TabControl { Margin = new Thickness(0, 4, 0, 4) };
        var selectedIdx = n.GetPropertyOrInt("selectedTabIndex", 0);
        foreach (var t in n.GetProperty("tabs").EnumerateArray())
        {
            var item = new TabItem { Header = t.GetPropertyOrDefault("title", "Tab") };
            var body = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(8) };
            foreach (var child in t.GetProperty("content").EnumerateArray())
            {
                body.Children.Add(Build(child));
            }
            item.Content = body;
            tabs.Items.Add(item);
        }
        if (selectedIdx >= 0 && selectedIdx < tabs.Items.Count) { tabs.SelectedIndex = selectedIdx; }
        return tabs;
    }

    private StackPanel BuildCarousel(JsonElement n)
    {
        var pages = n.GetProperty("pages");
        var pageList = new System.Collections.Generic.List<JsonElement>();
        foreach (var p in pages.EnumerateArray()) { pageList.Add(p); }
        var current = n.GetPropertyOrInt("selectedPageIndex", 0);
        if (current < 0 || current >= pageList.Count) { current = 0; }

        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        var header = new TextBlock { Text = $"Page {current + 1} of {pageList.Count}", FontWeight = FontWeights.Bold };
        stack.Children.Add(header);

        var nav = new StackPanel { Orientation = Orientation.Horizontal };
        var prev = new Button { Content = "◀ Prev", Margin = new Thickness(0, 0, 6, 0) };
        var next = new Button { Content = "Next ▶" };
        nav.Children.Add(prev);
        nav.Children.Add(next);
        stack.Children.Add(nav);

        var body = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 6, 0, 0) };
        void RenderPage()
        {
            body.Children.Clear();
            if (current < 0 || current >= pageList.Count) { return; }
            header.Text = $"Page {current + 1} of {pageList.Count}";
            foreach (var child in pageList[current].GetProperty("content").EnumerateArray())
            {
                body.Children.Add(Build(child));
            }
        }
        prev.Click += (_, _) => { if (current > 0) { current--; RenderPage(); } };
        next.Click += (_, _) => { if (current < pageList.Count - 1) { current++; RenderPage(); } };
        RenderPage();
        stack.Children.Add(body);
        return stack;
    }

    private StackPanel BuildCompoundButton(JsonElement n)
    {
        var title = n.GetPropertyOrDefault("title", "");
        var subtitle = n.GetPropertyOrNull("subtitle");
        var stack = new StackPanel { Orientation = Orientation.Vertical, Margin = new Thickness(0, 4, 0, 4) };
        var btn = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8),
        };
        var inner = new StackPanel { Orientation = Orientation.Vertical };
        inner.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.Bold });
        if (!string.IsNullOrEmpty(subtitle))
        {
            inner.Children.Add(new TextBlock { Text = subtitle, FontSize = 11, Opacity = 0.75 });
        }
        btn.Content = inner;
        if (n.TryGetProperty("action", out var action))
        {
            HookActionClick(btn, action);
        }
        stack.Children.Add(btn);
        return stack;
    }

    private Button BuildButton(JsonElement n)
    {
        var title = n.GetPropertyOrDefault("title", "");
        var btn = new Button
        {
            Content = title,
            Padding = new Thickness(10, 4, 10, 4),
            Margin = new Thickness(0, 2, 6, 2),
        };
        if (n.TryGetProperty("kind", out var kind))
        {
            HookActionClick(btn, kind);
        }
        return btn;
    }

    private void HookActionClick(Button btn, JsonElement actionKind)
    {
        var kindType = actionKind.GetPropertyOrDefault("type", "");
        btn.Click += (_, _) =>
        {
            switch (kindType)
            {
                case "openUrl":
                    var url = actionKind.GetPropertyOrDefault("url", "");
                    if (!string.IsNullOrEmpty(url))
                    {
                        try
                        {
                            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                            {
                                FileName = url,
                                UseShellExecute = true,
                            });
                            _onActionLog?.Invoke($"✓ openUrl -> {url}");
                        }
                        catch (Exception ex)
                        {
                            _onActionLog?.Invoke($"× openUrl failed: {ex.Message}");
                        }
                    }
                    break;
                case "submit":
                    var data = actionKind.GetPropertyOrNull("data");
                    _onActionLog?.Invoke($"• submit data={data ?? "(null)"}");
                    break;
                default:
                    _onActionLog?.Invoke($"• action kind={kindType}");
                    break;
            }
        };
    }

    private TextBlock Stub(string text) =>
        new()
        {
            Text = $"[{text}]",
            Opacity = 0.6,
            Margin = new Thickness(0, 2, 0, 2),
        };

    private static bool TryParseHex(string hex, out SolidColorBrush brush)
    {
        brush = new SolidColorBrush(Colors.Gray);
        if (string.IsNullOrEmpty(hex)) { return false; }
        var s = hex.TrimStart('#');
        if (s.Length != 6 && s.Length != 8) { return false; }
        if (!uint.TryParse(s, System.Globalization.NumberStyles.HexNumber, null, out var raw))
        {
            return false;
        }
        byte r, g, b, a = 255;
        if (s.Length == 8)
        {
            r = (byte)((raw >> 24) & 0xff);
            g = (byte)((raw >> 16) & 0xff);
            b = (byte)((raw >> 8) & 0xff);
            a = (byte)(raw & 0xff);
        }
        else
        {
            r = (byte)((raw >> 16) & 0xff);
            g = (byte)((raw >> 8) & 0xff);
            b = (byte)(raw & 0xff);
        }
        brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
        return true;
    }
}

// MARK: - JsonElement helpers
internal static class JsonElementExtensions
{
    public static string GetPropertyOrDefault(this JsonElement el, string name, string fallback)
    {
        if (el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String)
        {
            return v.GetString() ?? fallback;
        }
        return fallback;
    }

    public static string? GetPropertyOrNull(this JsonElement el, string name)
    {
        if (el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String)
        {
            return v.GetString();
        }
        return null;
    }

    public static bool GetPropertyOrFalse(this JsonElement el, string name)
    {
        if (el.TryGetProperty(name, out var v))
        {
            if (v.ValueKind == JsonValueKind.True) { return true; }
            if (v.ValueKind == JsonValueKind.False) { return false; }
        }
        return false;
    }

    public static double GetPropertyOrDouble(this JsonElement el, string name, double fallback)
    {
        if (el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number)
        {
            return v.GetDouble();
        }
        return fallback;
    }

    public static int GetPropertyOrInt(this JsonElement el, string name, int fallback)
    {
        if (el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number)
        {
            return v.GetInt32();
        }
        return fallback;
    }
}
