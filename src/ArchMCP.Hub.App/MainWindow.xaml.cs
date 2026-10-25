using ArchMCP.Hub.Core;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace ArchMCP.Hub.App;

public sealed class DetectedApplicationRow
{
    public string Id { get; init; } = string.Empty;
    public string DisplayName { get; init; } = string.Empty;
    public Version? DetectedVersion { get; init; }
    public string VersionText { get; init; } = "Unknown";
    public string InstallPath { get; init; } = "Path not reported by installer";
    public string DetectionSource { get; init; } = string.Empty;
    public CompatibilityStatus SupportStatus { get; init; } = CompatibilityStatus.Untested;
    public string SupportText { get; init; } = "Untested";
    public string SupportNote { get; init; } = string.Empty;
}

public partial class MainWindow : Window
{
    public ObservableCollection<DetectedApplicationRow> Applications { get; } = new();
    private bool _isLightTheme;
    private bool _isArabic;
    private bool _isInitialized;
    private string _currentSection = "Overview";
    private DateTime? _lastScanAt;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;
        _isInitialized = true;
        Loaded += (_, _) =>
        {
            ApplyLanguage();
            NavigateTo("Overview");
            CheckEnvironment_Click(this, new RoutedEventArgs());
        };
    }

    private void CheckEnvironment_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var selectedKey = ApplicationsList.SelectedItem is DetectedApplicationRow old
                ? $"{old.Id}|{old.VersionText}|{old.InstallPath}" : null;
            var detected = EnvironmentScanner.Scan();
            Applications.Clear();
            var verifiedCount = 0;
            var installedCount = 0;
            foreach (var app in detected)
            {
                if (app.SupportStatus == CompatibilityStatus.Verified) verifiedCount++;
                if (app.SupportStatus == CompatibilityStatus.InstalledAwaitingHost || app.SupportStatus == CompatibilityStatus.Verified) installedCount++;

                Applications.Add(new DetectedApplicationRow
                {
                    Id = app.Id,
                    DisplayName = app.DisplayName,
                    DetectedVersion = app.DetectedVersion,
                    VersionText = app.DetectedVersion?.ToString() ?? "Version unknown",
                    InstallPath = app.InstallPath,
                    DetectionSource = app.DetectionSource,
                    SupportStatus = app.SupportStatus,
                    SupportText = FormatStatusText(app.SupportStatus),
                    SupportNote = app.SupportNote
                });
            }
            _lastScanAt = DateTime.Now;
            DetectedAppsCountText.Text = _isArabic ? $"{detected.Count} إصدارًا مثبتًا" : $"{detected.Count} unique host versions";
            McpConnectionsValue.Text = _isArabic
                ? $"{verifiedCount} متصل / {installedCount} مثبت"
                : $"{verifiedCount} Live / {installedCount} Installed";
            McpStatusSubtitleText.Text = _isArabic
                ? "يدعم Revit 2022+, Rhino 7/8, 3ds Max 2021+, AutoCAD 2021+, SketchUp 2021+"
                : "Supports Revit 2022+, Rhino 7/8, 3ds Max 2021+, AutoCAD 2021+, SketchUp 2021+";

            LastScanText.Text = _isArabic
                ? $"آخر فحص: {_lastScanAt:yyyy-MM-dd HH:mm:ss}\nتم اكتشاف {detected.Count} إصدارًا فريدًا ({installedCount} مثبت، {verifiedCount} متصل فعليًا)."
                : $"Last scan: {_lastScanAt:yyyy-MM-dd HH:mm:ss}\nDetected {detected.Count} unique host version(s) ({installedCount} installed, {verifiedCount} live-verified).";
            OverviewSummaryText.Text = _isArabic
                ? $"تم العثور على {detected.Count} إصدارًا فريدًا من برامج التصميم ({installedCount} تكامل مثبت، {verifiedCount} متصل حاليًا). انتقل إلى «التكاملات» للتثبيت أو التعطيل/الإزالة أو الإصلاح أو فحص الاتصال."
                : $"Found {detected.Count} unique host versions ({installedCount} installed, {verifiedCount} live-verified). Open Integrations to install, disable/uninstall, repair, or verify connections.";

            if (selectedKey is not null)
                ApplicationsList.SelectedItem = Applications.FirstOrDefault(x => $"{x.Id}|{x.VersionText}|{x.InstallPath}" == selectedKey);

            PageSubtitleText.Text = detected.Count == 0
                ? (_isArabic ? "لم يتم العثور على ملفات تشغيل للبرامج المستهدفة. تم تجاهل سجلات الإضافات القديمة." : "No supported host executables found. Stale registry entries and add-ins are ignored.")
                : (_isArabic ? $"تم العثور على {detected.Count} إصدارًا مثبتًا. اختر إصدارًا محددًا ووكيل AI أدناه." : $"Found {detected.Count} unique installed host version(s). Select one version and an AI Agent below.");
        }
        catch (Exception ex)
        {
            PageSubtitleText.Text = (_isArabic ? "فشل فحص البيئة: " : "Environment scan failed: ") + ex.Message;
        }
    }

    private string FormatStatusText(CompatibilityStatus status) => status switch
    {
        CompatibilityStatus.Verified => _isArabic ? "Verified (متصل)" : "Verified (Live)",
        CompatibilityStatus.InstalledAwaitingHost => _isArabic ? "Installed (بانتظار البرنامج)" : "Installed (Awaiting Host)",
        CompatibilityStatus.Unsupported => _isArabic ? "Unsupported (غير مدعوم)" : "Unsupported",
        _ => _isArabic ? "Untested (جاهز للتثبيت)" : "Untested (Ready to install)"
    };

    private void ApplicationsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isInitialized || !IsLoaded || SelectedHostText is null) return;
        UpdateActionButtonsState();
    }

    private void AgentCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isInitialized || !IsLoaded || PrepareConnectionButton is null || ApplicationsList is null || AgentCombo is null) return;
        UpdateActionButtonsState();
    }

    private void UpdateActionButtonsState()
    {
        if (ApplicationsList.SelectedItem is DetectedApplicationRow app)
        {
            SelectedHostText.Text = $"{app.DisplayName} · {app.VersionText}";
            var descriptor = CompatibilityResolver.GetDescriptorForHost(app.Id);
            if (descriptor is not null)
            {
                SelectedHostHintText.Text = _isArabic ? descriptor.HostActivationHintAr : descriptor.HostActivationHintEn;
            }
            var canRun = AgentCombo.SelectedItem is not null && app.SupportStatus != CompatibilityStatus.Unsupported;
            PrepareConnectionButton.IsEnabled = canRun;
            if (UninstallConnectionButton is not null) UninstallConnectionButton.IsEnabled = canRun;
            if (RepairConnectionButton is not null) RepairConnectionButton.IsEnabled = canRun;
            if (VerifyConnectionButton is not null) VerifyConnectionButton.IsEnabled = canRun;
        }
        else
        {
            SelectedHostText.Text = _isArabic ? "اختر البرنامج والإصدار من القائمة" : "Select a detected application above";
            if (SelectedHostHintText is not null)
                SelectedHostHintText.Text = _isArabic
                    ? "يدعم Revit 2022+, Rhino 7/8, 3ds Max 2021+, AutoCAD 2021+, SketchUp 2021+"
                    : "Supports Revit 2022+, Rhino 7/8, 3ds Max 2021+, AutoCAD 2021+, SketchUp 2021+";
            PrepareConnectionButton.IsEnabled = false;
            if (UninstallConnectionButton is not null) UninstallConnectionButton.IsEnabled = false;
            if (RepairConnectionButton is not null) RepairConnectionButton.IsEnabled = false;
            if (VerifyConnectionButton is not null) VerifyConnectionButton.IsEnabled = false;
        }
    }

    private void PrepareConnection_Click(object sender, RoutedEventArgs e) => ExecuteIntegrationAction("Install");
    private void UninstallConnection_Click(object sender, RoutedEventArgs e) => ExecuteIntegrationAction("Uninstall");
    private void RepairConnection_Click(object sender, RoutedEventArgs e) => ExecuteIntegrationAction("Repair");
    private void VerifyConnection_Click(object sender, RoutedEventArgs e) => ExecuteIntegrationAction("Verify");

    private void ExecuteIntegrationAction(string action)
    {
        if (ApplicationsList.SelectedItem is not DetectedApplicationRow app || AgentCombo.SelectedItem is not ComboBoxItem agentItem)
        {
            PageSubtitleText.Text = _isArabic ? "اختر إصدار البرنامج ووكيل الذكاء الاصطناعي أولاً." : "Select a host version and an AI Agent first.";
            return;
        }

        var agent = agentItem.Content?.ToString() ?? "OpenCode";
        var eval = CompatibilityResolver.EvaluateHostVersionSupport(app.Id, app.DetectedVersion);
        if (eval.Status == CompatibilityStatus.Unsupported)
        {
            MessageBox.Show(
                _isArabic ? eval.NoteAr : eval.NoteEn,
                "ArchMCP Hub — Unsupported Version",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var descriptor = CompatibilityResolver.GetDescriptorForHost(app.Id);
        if (descriptor is null)
        {
            MessageBox.Show(
                _isArabic ? "لا يوجد واصف تكامل لهذا البرنامج." : "No integration descriptor found for this host.",
                "ArchMCP Hub",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var dispatcherScript = Path.Combine(AppContext.BaseDirectory, "scripts", "Install-Integration.ps1");
        var specificScript = Path.Combine(AppContext.BaseDirectory, "scripts", descriptor.ScriptFileName);
        var scriptToRun = File.Exists(dispatcherScript) ? dispatcherScript : specificScript;

        if (!File.Exists(scriptToRun))
        {
            MessageBox.Show(
                _isArabic
                    ? "ملف التثبيت غير موجود بجانب التطبيق. أعد تشغيل Run-ArchMCP-Hub.bat لإنشاء الحزمة كاملة."
                    : "Installer script is missing. Run Run-ArchMCP-Hub.bat again to create the complete package.",
                "ArchMCP Hub",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            return;
        }

        try
        {
            // Escape single quotes for PowerShell -Command invocation and guarantee the window stays open even if a script error occurs
            static string EscPs(string s) => (s ?? string.Empty).Replace("'", "''");
            var psCall = scriptToRun.EndsWith("Install-Integration.ps1", StringComparison.OrdinalIgnoreCase)
                ? $"& '{EscPs(scriptToRun)}' -HostId '{EscPs(app.Id)}' -HostVersion '{EscPs(app.VersionText)}' -InstallPath '{EscPs(app.InstallPath)}' -AgentName '{EscPs(agent)}' -Action '{EscPs(action)}'"
                : $"& '{EscPs(scriptToRun)}' -HostVersion '{EscPs(app.VersionText)}' -AgentName '{EscPs(agent)}' -Action '{EscPs(action)}'";

            var wrappedCommand = $"try {{ {psCall} }} catch {{ Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red; Read-Host 'Press Enter to close this window' }}";

            var start = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = true,
                Arguments = $"-NoLogo -NoProfile -ExecutionPolicy Bypass -Command \"{wrappedCommand}\"",
                WorkingDirectory = AppContext.BaseDirectory
            };
            var proc = Process.Start(start);
            if (proc is not null)
            {
                try
                {
                    proc.EnableRaisingEvents = true;
                    proc.Exited += (_, _) =>
                    {
                        try { Dispatcher.InvokeAsync(() => CheckEnvironment_Click(this, new RoutedEventArgs())); }
                        catch { }
                    };
                }
                catch { }
            }
            PageSubtitleText.Text = _isArabic
                ? $"بدأ تنفيذ الإجراء ({action}) لـ {app.DisplayName} ({app.VersionText}) مع {agent} في نافذة PowerShell. سيتم تحديث الحالة تلقائيًا بعد إغلاق النافذة."
                : $"Started {action} for {app.DisplayName} ({app.VersionText}) with {agent} in PowerShell. Status will refresh automatically when the window closes.";
        }
        catch (Exception ex)
        {
            MessageBox.Show((_isArabic ? "تعذر تشغيل معالج التكامل: " : "Could not launch integration script: ") + ex.Message, "ArchMCP Hub", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Theme_Click(object sender, RoutedEventArgs e)
    {
        _isLightTheme = !_isLightTheme;
        SetThemeColor("CanvasColor", "CanvasBrush", _isLightTheme ? "#F3F5F8" : "#101318");
        SetThemeColor("PanelColor", "PanelBrush", _isLightTheme ? "#FFFFFF" : "#191E26");
        SetThemeColor("PanelRaisedColor", "PanelRaisedBrush", _isLightTheme ? "#E9EDF2" : "#202733");
        SetThemeColor("LineColor", "LineBrush", _isLightTheme ? "#D4DAE3" : "#303846");
        SetThemeColor("TextColor", "PrimaryTextBrush", _isLightTheme ? "#17202B" : "#F3F5F8");
        SetThemeColor("MutedColor", "MutedTextBrush", _isLightTheme ? "#596777" : "#9BA7B7");
        SetThemeColor("AccentColor", "AccentBrush", _isLightTheme ? "#087F70" : "#83D6C4");
        Background = GetBrush("CanvasBrush");
        Foreground = GetBrush("PrimaryTextBrush");
        ThemeButton.Content = _isArabic
            ? (_isLightTheme ? "◐ الوضع الداكن" : "☼ الوضع الفاتح")
            : (_isLightTheme ? "◐ Dark mode" : "☼ Light mode");
        SettingsThemeButton.Content = _isArabic ? "تغيير الوضع" : "Toggle light/dark theme";
        RefreshNavigationStyles();
    }

    private static void SetThemeColor(string colorKey, string brushKey, string hex)
    {
        var color = (Color)ColorConverter.ConvertFromString(hex)!;
        Application.Current.Resources[colorKey] = color;
        Application.Current.Resources[brushKey] = new SolidColorBrush(color);
    }

    private static SolidColorBrush GetBrush(string key) => (SolidColorBrush)Application.Current.Resources[key];

    private void Language_Click(object sender, RoutedEventArgs e)
    {
        _isArabic = !_isArabic;
        ApplyLanguage();
        NavigateTo(_currentSection);
        CheckEnvironment_Click(this, new RoutedEventArgs());
    }

    private void ApplyLanguage()
    {
        if (!_isInitialized) return;
        WorkspaceLabel.Text = _isArabic ? "مساحة العمل" : "WORKSPACE";
        PreferencesLabel.Text = _isArabic ? "التفضيلات" : "PREFERENCES";
        OverviewNavButton.Content = _isArabic ? "نظرة عامة" : "Overview";
        IntegrationsNavButton.Content = _isArabic ? "التكاملات" : "Integrations";
        AgentsNavButton.Content = _isArabic ? "وكلاء الذكاء الاصطناعي" : "AI Agents";
        CompatibilityNavButton.Content = _isArabic ? "التوافق" : "Compatibility";
        LogsNavButton.Content = _isArabic ? "النشاط والسجلات" : "Activity & Logs";
        SettingsNavButton.Content = _isArabic ? "الإعدادات" : "Settings";
        PortableLabel.Text = _isArabic ? "مساحة عمل محمولة" : "PORTABLE WORKSPACE";
        PortableTitle.Text = _isArabic ? "إعداد محلي أولًا" : "Local-first setup";
        PortableSubtitle.Text = _isArabic ? "لا حاجة إلى حساب سحابي" : "No cloud account required";
        LanguageButton.Content = _isArabic ? "العربية / EN" : "EN / عربي";
        CheckEnvironmentButton.Content = _isArabic ? "فحص البيئة" : "Check environment";
        DesignAppsLabel.Text = _isArabic ? "برامج التصميم" : "DESIGN APPLICATIONS";
        InstalledAppsSubtitle.Text = _isArabic ? "البرامج المثبتة التي تم العثور عليها" : "Installed host applications";
        McpConnectionsLabel.Text = _isArabic ? "اتصالات MCP" : "MCP CONNECTIONS";
        SecurityStatusLabel.Text = _isArabic ? "حالة الأمان" : "SECURITY STATUS";
        SecurityStatusValue.Text = _isArabic ? "نسخ احتياطي واستعادة" : "Backup & Rollback";
        SecurityStatusSubtitle.Text = _isArabic ? "تثبيت على مستوى المستخدم · الوضع الآمن" : "User-level install · Safe Mode defaults";
        CoverageTitleText.Text = _isArabic ? "تغطية التكاملات" : "Integration coverage";
        CoverageSubtitleText.Text = _isArabic ? "البرامج المكتشفة وحالة التثبيت والاتصال الفعلي" : "Target hosts and their verified / installed status";
        BuildBadgeText.Text = _isArabic ? "الإصدار v1.0.0" : "Release v1.0.0";
        ColumnApplicationLabel.Text = _isArabic ? "البرنامج" : "APPLICATION";
        ColumnVersionLabel.Text = _isArabic ? "الإصدار" : "VERSION";
        ColumnIntegrationLabel.Text = _isArabic ? "مصدر الاكتشاف" : "DETECTION SOURCE";
        ColumnStatusLabel.Text = _isArabic ? "الحالة" : "STATUS";
        SelectedHostLabel.Text = _isArabic ? "البرنامج / الإصدار المحدد" : "SELECTED HOST / VERSION";
        AgentLabel.Text = _isArabic ? "وكيل الذكاء الاصطناعي" : "AI AGENT";
        PrepareConnectionButton.Content = _isArabic ? "تثبيت وربط" : "Install & connect";
        if (UninstallConnectionButton is not null) UninstallConnectionButton.Content = _isArabic ? "تعطيل / إلغاء تثبيت" : "Disable / Uninstall";
        if (RepairConnectionButton is not null) RepairConnectionButton.Content = _isArabic ? "إصلاح (Repair)" : "Repair";
        if (VerifyConnectionButton is not null) VerifyConnectionButton.Content = _isArabic ? "فحص (Verify)" : "Verify";
        OverviewPanelTitle.Text = _isArabic ? "نظرة عامة على البيئة" : "Environment overview";
        OverviewPanelDescription.Text = _isArabic
            ? "افحص برامج التصميم المثبتة، ثم افتح التكاملات لتثبيت أو تعطيل/إزالة أو إصلاح أو فحص جسور MCP لبرامج Revit (2022+) وRhino (7/8) و3ds Max (2021+) وAutoCAD (2021+) وSketchUp (2021+)."
            : "Scan your installed modeling applications, then open Integrations to install, disable/uninstall, repair, or verify MCP bridges for Revit (2022+), Rhino (7/8), 3ds Max (2021+), AutoCAD (2021+), and SketchUp (2021+).";
        GoToIntegrationsButton.Content = _isArabic ? "فتح التكاملات" : "Open integrations";
        CompatibilityPanelTitle.Text = _isArabic ? "سياسة التوافق والإصدارات المدعومة" : "Compatibility policy & Supported Ranges";
        CompatibilityPanelDescription.Text = _isArabic ? "اكتشاف البرنامج وحده لا يعني أن تكامل MCP تم التحقق منه؛ يلزم نجاح فحص الاتصال المباشر." : "Detection alone does not mean an MCP integration is verified. Live endpoint verification is required.";
        CompatibilityVerifiedText.Text = _isArabic ? "• Verified (متصل) — تم تثبيت الملفات وتسجيل الوكيل ونجح فحص الاتصال الحي داخل البرنامج." : "• Verified — Files installed, agent registered, and live in-host health check responded.";
        if (CompatibilityInstalledText is not null)
            CompatibilityInstalledText.Text = _isArabic ? "• Installed (بانتظار البرنامج) — تم تثبيت خادم MCP والإضافة بنجاح؛ افتح برنامج التصميم للتحقق من الاتصال الحي." : "• InstalledAwaitingHost — MCP server and plugin files installed on disk; open the CAD host to verify live connection.";
        CompatibilityUntestedText.Text = _isArabic ? "• Untested (غير مختبر) — تم اكتشاف إصدار متوافق من البرنامج، لكن لم يتم تثبيت أو فحص التكامل بعد." : "• Untested — Compatible host executable detected, but integration has not been installed/verified yet.";
        CompatibilityUnsupportedText.Text = _isArabic ? "• Unsupported (غير مدعوم) — إصدار أقدم من الحد الأدنى المدعوم (أقدم من Revit 2022 أو Rhino 7 أو 3ds Max 2021 أو AutoCAD 2021)." : "• Unsupported — Host version is older than minimum supported (older than Revit 2022, Rhino 7, 3ds Max 2021, AutoCAD 2021).";
        CompatibilityOpenIntegrationsButton.Content = _isArabic ? "عرض الإصدارات المكتشفة" : "View detected versions";
        AgentsPanelTitle.Text = _isArabic ? "وكلاء الذكاء الاصطناعي المدعومون" : "Supported AI Agents";
        AgentsPanelDescription.Text = _isArabic ? "يحافظ ArchMCP Hub على إعداداتك الحالية وينشئ نسخة احتياطية مؤرخة قبل تسجيل خوادم MCP." : "ArchMCP Hub preserves existing user configurations and creates timestamped backups before registering MCP servers.";
        LogsPanelTitle.Text = _isArabic ? "النشاط والتشخيص" : "Activity & Diagnostics";
        LogsPanelDescription.Text = _isArabic ? "نتائج فحص البيئة وسجلات التثبيت والتشخيص." : "Environment scan results, installer transcripts, and startup diagnostics.";
        OpenLogsButton.Content = _isArabic ? "فتح مجلد السجلات" : "Open diagnostic log folder";
        SettingsPanelTitle.Text = _isArabic ? "التفضيلات" : "Preferences";
        SettingsPanelDescription.Text = _isArabic ? "إعدادات المظهر واللغة." : "Appearance and language preferences.";
        SettingsThemeButton.Content = _isArabic ? "تغيير الوضع" : "Toggle light/dark theme";
        SettingsLanguageButton.Content = _isArabic ? "تغيير اللغة" : "Switch English / Arabic";
        ThemeButton.Content = _isArabic ? (_isLightTheme ? "◐ الوضع الداكن" : "☼ الوضع الفاتح") : (_isLightTheme ? "◐ Dark mode" : "☼ Light mode");
        UpdateActionButtonsState();
    }

    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo("https://www.facebook.com/profile.php?id=100078064892942") { UseShellExecute = true }); }
        catch (Exception ex) { PageSubtitleText.Text = "Could not open Connect link: " + ex.Message; }
    }

    private void Overview_Click(object sender, RoutedEventArgs e) => NavigateTo("Overview");
    private void Integrations_Click(object sender, RoutedEventArgs e) => NavigateTo("Integrations");
    private void Agents_Click(object sender, RoutedEventArgs e) => NavigateTo("Agents");
    private void Compatibility_Click(object sender, RoutedEventArgs e) => NavigateTo("Compatibility");
    private void Logs_Click(object sender, RoutedEventArgs e) => NavigateTo("Logs");
    private void Settings_Click(object sender, RoutedEventArgs e) => NavigateTo("Settings");

    private void NavigateTo(string section)
    {
        _currentSection = section;
        HostsPanel.Visibility = section == "Integrations" ? Visibility.Visible : Visibility.Collapsed;
        OverviewPanel.Visibility = section == "Overview" ? Visibility.Visible : Visibility.Collapsed;
        CompatibilityPanel.Visibility = section == "Compatibility" ? Visibility.Visible : Visibility.Collapsed;
        AgentsPanel.Visibility = section == "Agents" ? Visibility.Visible : Visibility.Collapsed;
        LogsPanel.Visibility = section == "Logs" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = section == "Settings" ? Visibility.Visible : Visibility.Collapsed;

        var content = section switch
        {
            "Integrations" => (_isArabic ? "التكاملات" : "INTEGRATIONS", _isArabic ? "اختر البرنامج والإجراء" : "Manage host integrations", _isArabic ? "حدد إصدارًا مثبتًا ووكيل AI للتثبيت أو التعطيل/الإزالة أو الإصلاح أو فحص الاتصال." : "Select an installed version and AI Agent to Install, Disable/Uninstall, Repair, or Verify."),
            "Agents" => (_isArabic ? "وكلاء الذكاء الاصطناعي" : "AI AGENTS", _isArabic ? "ملفات تعريف الوكلاء" : "Agent profiles", _isArabic ? "إدارة عملاء MCP المدعومين مع الحفاظ على الإعدادات." : "Manage supported MCP clients with automatic backup & merge."),
            "Compatibility" => (_isArabic ? "التوافق" : "COMPATIBILITY", _isArabic ? "مصفوفة التوافق" : "Compatibility matrix", _isArabic ? "لا تُمنح حالة Verified إلا بعد نجاح فحص الاتصال الحي." : "A host reaches Verified only when live health checks pass."),
            "Logs" => (_isArabic ? "النشاط والسجلات" : "ACTIVITY & LOGS", _isArabic ? "النشاط والتشخيص" : "Activity and diagnostics", _isArabic ? "راجع وقت آخر فحص وافتح مجلد السجلات." : "Review the last scan and open the diagnostics folder."),
            "Settings" => (_isArabic ? "الإعدادات" : "PREFERENCES", _isArabic ? "تفضيلات التطبيق" : "Application preferences", _isArabic ? "غيّر المظهر واللغة من هنا." : "Change appearance and language here."),
            _ => (_isArabic ? "مركز التحكم" : "CONTROL CENTER", _isArabic ? "أدوات التصميم، في مكان واحد." : "Your design tools, connected.", _isArabic ? "إدارة تكاملات MCP ضمن سير عملك المعماري." : "Manage MCP integrations across your architectural workflow.")
        };
        SectionEyebrow.Text = content.Item1;
        PageTitleText.Text = content.Item2;
        PageSubtitleText.Text = content.Item3;
        RefreshNavigationStyles();
    }

    private void RefreshNavigationStyles()
    {
        if (!_isInitialized) return;
        var nav = new (Button Button, string Section)[]
        {
            (OverviewNavButton, "Overview"), (IntegrationsNavButton, "Integrations"), (AgentsNavButton, "Agents"),
            (CompatibilityNavButton, "Compatibility"), (LogsNavButton, "Logs"), (SettingsNavButton, "Settings")
        };
        foreach (var item in nav)
        {
            var active = item.Section == _currentSection;
            item.Button.Background = active ? GetBrush("PanelRaisedBrush") : Brushes.Transparent;
            item.Button.BorderBrush = active ? GetBrush("AccentBrush") : Brushes.Transparent;
            item.Button.Foreground = GetBrush("PrimaryTextBrush");
            item.Button.BorderThickness = new Thickness(active ? 1 : 0);
        }
    }

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ArchMCP Hub", "Logs");
        try
        {
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "ArchMCP Hub", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }
}
