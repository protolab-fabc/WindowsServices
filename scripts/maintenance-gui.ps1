Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Minecraft Server - Maintenance en direct" 
        Height="560" Width="760" 
        WindowStartupLocation="CenterScreen" 
        Background="#18181b" 
        Foreground="#f4f4f5" 
        FontFamily="Segoe UI"
        WindowStyle="SingleBorderWindow"
        Topmost="True"
        ResizeMode="CanMinimize">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#e4e4e7"/>
        </Style>
    </Window.Resources>
    
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#27272a" CornerRadius="8" Padding="15" Margin="0,0,0,15">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="MINECRAFT SERVER MAINTENANCE" FontSize="18" FontWeight="Bold" Foreground="#38bdf8"/>
                    <TextBlock Name="TxtServerDir" Text="Dossier : C:\WindowsServices" FontSize="12" Foreground="#a1a1aa" Margin="0,4,0,0"/>
                </StackPanel>
                <Border Name="BadgeStatus" Grid.Column="1" Background="#0284c7" CornerRadius="12" Padding="12,5" VerticalAlignment="Center">
                    <TextBlock Name="TxtBadge" Text="EN COURS" FontSize="11" FontWeight="Bold" Foreground="White"/>
                </Border>
            </Grid>
        </Border>

        <!-- Current Step & Progress -->
        <StackPanel Grid.Row="1" Margin="0,0,0,15">
            <Grid Margin="0,0,0,6">
                <TextBlock Name="TxtCurrentStep" Text="Initialisation..." FontSize="13" FontWeight="SemiBold" Foreground="#f8fafc"/>
                <TextBlock Name="TxtPercent" Text="0%" FontSize="13" FontWeight="Bold" Foreground="#38bdf8" HorizontalAlignment="Right"/>
            </Grid>
            <ProgressBar Name="ProgBar" Height="10" Minimum="0" Maximum="100" Value="5" Background="#27272a" Foreground="#38bdf8" BorderThickness="0"/>
        </StackPanel>

        <!-- Console Header -->
        <TextBlock Grid.Row="2" Text="JOURNAL D'EXÉCUTION EN DIRECT" FontSize="11" FontWeight="Bold" Foreground="#71717a" Margin="0,0,0,6"/>

        <!-- Live Log Console -->
        <Border Grid.Row="3" Background="#09090b" BorderBrush="#27272a" BorderThickness="1" CornerRadius="6" Padding="12">
            <ScrollViewer Name="LogScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
                <TextBox Name="TxtLog" Background="Transparent" Foreground="#10b981" FontFamily="Consolas" FontSize="12" 
                         BorderThickness="0" IsReadOnly="True" TextWrapping="Wrap" 
                         CaretBrush="Transparent" SelectionBrush="#0284c7"/>
            </ScrollViewer>
        </Border>

        <!-- Footer / Countdown / Close Button -->
        <Grid Grid.Row="4" Margin="0,15,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Name="TxtFooterCountdown" Text="Maintenance en cours d'exécution..." VerticalAlignment="Center" FontSize="13" Foreground="#94a3b8" FontWeight="SemiBold"/>
            <Button Name="BtnClose" Grid.Column="1" Content="Fermer" Width="100" Height="32" Background="#3f3f46" Foreground="White" 
                    FontWeight="SemiBold" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$txtServerDir = $window.FindName("TxtServerDir")
$badgeStatus = $window.FindName("BadgeStatus")
$txtBadge = $window.FindName("TxtBadge")
$txtCurrentStep = $window.FindName("TxtCurrentStep")
$txtPercent = $window.FindName("TxtPercent")
$progBar = $window.FindName("ProgBar")
$txtLog = $window.FindName("TxtLog")
$logScroll = $window.FindName("LogScroll")
$txtFooterCountdown = $window.FindName("TxtFooterCountdown")
$btnClose = $window.FindName("BtnClose")

$logPath = "C:\WindowsServices\update-backup.log"
$script:isFinished = $false
$script:countdownSeconds = 40
$script:totalSecondsElapsed = 0

$btnClose.Add_Click({
    $window.Close()
    [System.Environment]::Exit(0)
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)

$timer.Add_Tick({
    $script:totalSecondsElapsed += 0.3

    if (Test-Path $logPath) {
        try {
            $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $streamReader = New-Object System.IO.StreamReader($stream)
            $content = $streamReader.ReadToEnd()
            $streamReader.Close()
            $stream.Close()

            if ($txtLog.Text -ne $content) {
                $txtLog.Text = $content
                $logScroll.ScrollToEnd()
            }

            # Find the most recent session in log
            $allLines = $content -split "`r?`n" | Where-Object { $_ -ne "" }
            $sessionStartIndex = 0
            for ($i = $allLines.Count - 1; $i -ge 0; $i--) {
                if ($allLines[$i] -match "Demarrage maintenance Minecraft") {
                    $sessionStartIndex = [Math]::Max(0, $i - 1)
                    break
                }
            }

            $currentSessionLines = @()
            if ($sessionStartIndex -lt $allLines.Count) {
                $currentSessionLines = $allLines[$sessionStartIndex..($allLines.Count - 1)]
            } else {
                $currentSessionLines = $allLines
            }

            $currentSessionText = $currentSessionLines -join "`n"

            # Parse steps and progress
            $latestStep = "Initialisation..."
            $pct = 5
            foreach ($l in $currentSessionLines) {
                if ($l -match "\[1/7\]") { $latestStep = "[1/7] Vérification dernière version Mojang"; $pct = 15 }
                elseif ($l -match "\[2/7\]") { $latestStep = "[2/7] Vérification état serveur"; $pct = 30 }
                elseif ($l -match "\[3/7\]") { $latestStep = "[3/7] Avertissement des joueurs"; $pct = 45 }
                elseif ($l -match "\[4/7\]") { $latestStep = "[4/7] Sauvegarde Minecraft & Arrêt propre"; $pct = 60 }
                elseif ($l -match "\[5/7\]") { $latestStep = "[5/7] Compression sauvegarde 7-Zip"; $pct = 75 }
                elseif ($l -match "\[6/7\]") { $latestStep = "[6/7] Téléchargement & Mise à jour JAR"; $pct = 88 }
                elseif ($l -match "\[7/7\]") { $latestStep = "[7/7] Redémarrage du serveur"; $pct = 95 }
                elseif ($l -match "RESULTAT :" -or $l -match "FIN DE LA MAINTENANCE" -or $l -match "ERREUR CRITIQUE") { 
                    $pct = 100 
                    if ($l -match "ERREUR") {
                        $latestStep = "Erreur durant la maintenance"
                    } else {
                        $latestStep = "Maintenance terminée avec succès !"
                    }
                }
            }

            $txtCurrentStep.Text = $latestStep
            $progBar.Value = $pct
            $txtPercent.Text = "$pct%"

            # Check if this session completed
            if (-not $script:isFinished -and ($currentSessionText -match "RESULTAT :" -or $currentSessionText -match "FIN DE LA MAINTENANCE" -or $currentSessionText -match "ERREUR CRITIQUE")) {
                $script:isFinished = $true
                $timer.Interval = [TimeSpan]::FromSeconds(1)

                if ($currentSessionText -match "ERREUR CRITIQUE") {
                    $badgeStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#dc2626")
                    $txtBadge.Text = "ERREUR"
                    $progBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#dc2626")
                    $txtFooterCountdown.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f87171")
                } else {
                    $badgeStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16a34a")
                    $txtBadge.Text = "TERMINÉ"
                    $progBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16a34a")
                    $txtFooterCountdown.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
                }
            }
        } catch {}
    }

    if ($script:isFinished) {
        $txtFooterCountdown.Text = "Fermeture automatique dans $($script:countdownSeconds) seconde(s)..."
        $script:countdownSeconds--
        if ($script:countdownSeconds -lt 0) {
            $timer.Stop()
            $window.Close()
            [System.Environment]::Exit(0)
        }
    }
    
    # Safety hard timeout (15 minutes max)
    if ($script:totalSecondsElapsed -gt 900) {
        $timer.Stop()
        $window.Close()
        [System.Environment]::Exit(0)
    }
})

$timer.Start()
$window.ShowDialog() | Out-Null
