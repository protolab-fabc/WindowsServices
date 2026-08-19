using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace MinecraftMonitoring
{
    public class RconClient : IDisposable
    {
        private TcpClient _tcp;
        private NetworkStream _stream;
        private int _reqId = 1;
        private readonly object _lock = new object();

        public bool Connect(string host, int port, string password)
        {
            try
            {
                Disconnect();
                _tcp = new TcpClient();
                _tcp.SendTimeout = 2500;
                _tcp.ReceiveTimeout = 2500;
                _tcp.Connect(host, port);
                _stream = _tcp.GetStream();

                string authResp = SendPacket(3, password);
                return true;
            }
            catch
            {
                Disconnect();
                return false;
            }
        }

        public string SendCommand(string command)
        {
            lock (_lock)
            {
                try
                {
                    if (_tcp == null || !_tcp.Connected || _stream == null)
                        return null;
                    return SendPacket(2, command);
                }
                catch
                {
                    Disconnect();
                    return null;
                }
            }
        }

        private string SendPacket(int type, string payload)
        {
            byte[] payloadBytes = Encoding.UTF8.GetBytes(payload);
            int length = payloadBytes.Length + 10;
            int reqId = _reqId++;

            byte[] packet = new byte[length + 4];
            Buffer.BlockCopy(BitConverter.GetBytes(length), 0, packet, 0, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(reqId), 0, packet, 4, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(type), 0, packet, 8, 4);
            Buffer.BlockCopy(payloadBytes, 0, packet, 12, payloadBytes.Length);
            packet[packet.Length - 2] = 0;
            packet[packet.Length - 1] = 0;

            _stream.Write(packet, 0, packet.Length);
            _stream.Flush();

            byte[] lenBuf = new byte[4];
            int read = 0;
            while (read < 4)
            {
                int r = _stream.Read(lenBuf, read, 4 - read);
                if (r <= 0) return "";
                read += r;
            }
            int respLen = BitConverter.ToInt32(lenBuf, 0);
            if (respLen <= 0 || respLen > 65536) return "";

            byte[] respBuf = new byte[respLen];
            read = 0;
            while (read < respLen)
            {
                int r = _stream.Read(respBuf, read, respLen - read);
                if (r <= 0) break;
                read += r;
            }

            if (respBuf.Length >= 8)
            {
                int bodyLen = respLen - 10;
                if (bodyLen > 0)
                {
                    return Encoding.UTF8.GetString(respBuf, 8, bodyLen).Trim('\0', ' ', '\r', '\n');
                }
            }
            return "";
        }

        public void Disconnect()
        {
            try { if (_stream != null) _stream.Close(); } catch { }
            try { if (_tcp != null) _tcp.Close(); } catch { }
            _stream = null;
            _tcp = null;
        }

        public void Dispose()
        {
            Disconnect();
        }
    }

    public class CommandSuggestion
    {
        public string Command { get; set; }
        public string Description { get; set; }
        public string Category { get; set; }

        public CommandSuggestion(string cmd, string desc, string cat)
        {
            Command = cmd;
            Description = desc;
            Category = cat;
        }
    }

    public class PlayerConnectionLog
    {
        public DateTime Timestamp { get; set; }
        public string TimeString { get; set; }
        public string PlayerName { get; set; }
        public string EventType { get; set; } // "CONNEXION", "DÉCONNEXION", "EXPULSION"
        public string Details { get; set; }
        public string IpAddress { get; set; }
        public string Coordinates { get; set; }
        public string Reason { get; set; }
        public SolidColorBrush BadgeBg { get; set; }
        public SolidColorBrush BadgeFg { get; set; }
        public string Icon { get; set; }
    }

    public class MainWindow : Window
    {
        private DispatcherTimer _timer;
        private RconClient _rcon = new RconClient();
        private List<double> _ramHistory = new List<double>();
        private List<double> _cpuHistory = new List<double>();
        private const int MaxHistory = 50;

        // UI Controls - Header & Stats
        private Border _statusBadge;
        private TextBlock _statusText;
        private TextBlock _txtUptime;
        private TextBlock _txtRamStats;
        private TextBlock _txtCpuStats;
        private TextBlock _txtPlayerCount;
        private Canvas _chartCanvas;
        private ListBox _lstPlayers;
        private TextBlock _txtSelectedPlayer;
        private StackPanel _pnlPlayerActions;

        // Tab Navigation
        private Button _tabBtnConsole;
        private Button _tabBtnLogs;
        private Grid _panelConsole;
        private Grid _panelPlayerLogs;

        // Console Controls
        private TextBox _txtConsoleOutput;
        private TextBox _txtCommandInput;
        private TextBox _txtBroadcastInput;
        private Popup _suggestionsPopup;
        private ListBox _lstSuggestions;
        private bool _isUpdatingText = false;
        private List<string> _commandHistory = new List<string>();
        private int _historyIndex = -1;
        private List<CommandSuggestion> _baseCommands = new List<CommandSuggestion>();
        private List<string> _onlinePlayerNames = new List<string>();

        // Player Logs Controls
        private ListBox _lstConnectionLogs;
        private TextBlock _txtLogStatsConn;
        private TextBlock _txtLogStatsDeconn;
        private TextBlock _txtLogStatsUnique;
        private TextBox _txtSearchPlayer;
        private ComboBox _cmbFilterType;
        private List<PlayerConnectionLog> _allConnectionLogs = new List<PlayerConnectionLog>();
        private ObservableCollection<PlayerConnectionLog> _displayedLogs = new ObservableCollection<PlayerConnectionLog>();
        private long _lastLogFileOffset = 0;

        private string _serverDir = @"C:\WindowsServices";
        private string _rconPassword = "ton_mot_de_passe_rcon";
        private int _rconPort = 25575;
        private Process _serverProcess = null;
        private TimeSpan _lastCpuTime = TimeSpan.Zero;
        private DateTime _lastCpuCheck = DateTime.UtcNow;

        private static readonly Regex _loginRegex = new Regex(
            @"^\[(?<time>\d{2}:\d{2}:\d{2})\]\s+\[Server thread/INFO\]:\s+(?<player>[a-zA-Z0-9_]+)\[/(?<ip>[^:]+):(?<port>\d+)\]\s+logged in with entity id\s+(?<id>\d+)\s+at\s+\((?<coords>[^)]+)\)",
            RegexOptions.Compiled);

        private static readonly Regex _disconnectRegex = new Regex(
            @"^\[(?<time>\d{2}:\d{2}:\d{2})\]\s+\[Server thread/INFO\]:\s+(?<player>[a-zA-Z0-9_]+)\s+lost connection:\s*(?<reason>.*)$",
            RegexOptions.Compiled);

        [STAThread]
        public static void Main()
        {
            Application app = new Application();
            app.Run(new MainWindow());
        }

        public MainWindow()
        {
            this.Title = "Minecraft Server Dashboard & Monitoring";
            this.Width = 1120;
            this.Height = 780;
            this.MinWidth = 980;
            this.MinHeight = 660;
            this.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            this.Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)); // Slate 900
            this.Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249));
            this.FontFamily = new FontFamily("Segoe UI, sans-serif");

            InitCommandSuggestions();
            LoadProperties();
            BuildUI();
            InitialLoadLogs();

            _timer = new DispatcherTimer();
            _timer.Interval = TimeSpan.FromSeconds(1.5);
            _timer.Tick += OnTimerTick;
            _timer.Start();

            OnTimerTick(null, null);
        }

        private void InitCommandSuggestions()
        {
            _baseCommands = new List<CommandSuggestion>
            {
                new CommandSuggestion("help", "Affiche l'aide des commandes Minecraft", "Admin"),
                new CommandSuggestion("list", "Affiche la liste des joueurs connectés", "Serveur"),
                new CommandSuggestion("save-all", "Sauvegarde le monde et les données du serveur", "Serveur"),
                new CommandSuggestion("save-off", "Désactive la sauvegarde automatique", "Serveur"),
                new CommandSuggestion("save-on", "Active la sauvegarde automatique", "Serveur"),
                new CommandSuggestion("stop", "Arrête proprement le serveur", "Serveur"),
                new CommandSuggestion("reload", "Recharge tous les datapacks et fonctions", "Serveur"),
                new CommandSuggestion("say ", "Envoie un message broadcast à tous les joueurs", "Chat"),
                new CommandSuggestion("tellraw @a ", "Envoie un message JSON formaté à tous les joueurs", "Chat"),
                new CommandSuggestion("seed", "Affiche la graine (seed) du monde", "Monde"),
                new CommandSuggestion("op ", "Donne les privilèges opérateur à un joueur", "Modération"),
                new CommandSuggestion("deop ", "Retire les privilèges opérateur d'un joueur", "Modération"),
                new CommandSuggestion("kick ", "Expulse un joueur du serveur", "Modération"),
                new CommandSuggestion("ban ", "Bannit un joueur du serveur", "Modération"),
                new CommandSuggestion("pardon ", "Débannit un joueur du serveur", "Modération"),
                new CommandSuggestion("ban-ip ", "Bannit une adresse IP", "Modération"),
                new CommandSuggestion("pardon-ip ", "Débannit une adresse IP", "Modération"),
                new CommandSuggestion("whitelist add ", "Ajoute un joueur à la liste blanche", "Whitelist"),
                new CommandSuggestion("whitelist remove ", "Retire un joueur de la liste blanche", "Whitelist"),
                new CommandSuggestion("whitelist list", "Affiche les joueurs sur la liste blanche", "Whitelist"),
                new CommandSuggestion("whitelist on", "Active la liste blanche", "Whitelist"),
                new CommandSuggestion("whitelist off", "Désactive la liste blanche", "Whitelist"),
                new CommandSuggestion("whitelist reload", "Recharge la liste blanche", "Whitelist"),
                new CommandSuggestion("gamemode survival ", "Change le mode de jeu en Survie", "Gameplay"),
                new CommandSuggestion("gamemode creative ", "Change le mode de jeu en Créatif", "Gameplay"),
                new CommandSuggestion("gamemode adventure ", "Change le mode de jeu en Aventure", "Gameplay"),
                new CommandSuggestion("gamemode spectator ", "Change le mode de jeu en Spectateur", "Gameplay"),
                new CommandSuggestion("difficulty peaceful", "Change la difficulté en Paisible", "Monde"),
                new CommandSuggestion("difficulty easy", "Change la difficulté en Facile", "Monde"),
                new CommandSuggestion("difficulty normal", "Change la difficulté en Normale", "Monde"),
                new CommandSuggestion("difficulty hard", "Change la difficulté en Difficile", "Monde"),
                new CommandSuggestion("weather clear", "Met la météo au beau fixe / ciel dégagé", "Monde"),
                new CommandSuggestion("weather rain", "Déclenche la pluie", "Monde"),
                new CommandSuggestion("weather thunder", "Déclenche un orage", "Monde"),
                new CommandSuggestion("time set day", "Règle l'heure sur le jour (1000)", "Monde"),
                new CommandSuggestion("time set noon", "Règle l'heure sur midi (6000)", "Monde"),
                new CommandSuggestion("time set night", "Règle l'heure sur la nuit (13000)", "Monde"),
                new CommandSuggestion("time set midnight", "Règle l'heure sur minuit (18000)", "Monde"),
                new CommandSuggestion("time query daytime", "Affiche l'heure actuelle du monde", "Monde"),
                new CommandSuggestion("tp ", "Téléporte une entité vers une autre ou des coordonnées", "TP"),
                new CommandSuggestion("teleport ", "Téléporte une entité vers des coordonnées", "TP"),
                new CommandSuggestion("give ", "Donne un objet à un joueur", "Inventaire"),
                new CommandSuggestion("clear ", "Vide l'inventaire d'un joueur", "Inventaire"),
                new CommandSuggestion("effect give ", "Applique un effet de potion à un joueur", "Effets"),
                new CommandSuggestion("effect clear ", "Retire tous les effets de potion d'un joueur", "Effets"),
                new CommandSuggestion("experience add ", "Donne de l'expérience (XP) à un joueur", "XP"),
                new CommandSuggestion("kill ", "Élimine une entité ou un joueur", "Admin"),
                new CommandSuggestion("summon ", "Fait apparaître une entité à des coordonnées", "Monde"),
                new CommandSuggestion("setblock ", "Place un bloc spécifique à des coordonnées", "Monde"),
                new CommandSuggestion("fill ", "Remplit une zone avec un bloc spécifique", "Monde"),
                new CommandSuggestion("clone ", "Clone une zone de blocs vers une autre position", "Monde"),
                new CommandSuggestion("scoreboard objectives list", "Affiche la liste des objectifs de scoreboard", "Scoreboard"),
                new CommandSuggestion("scoreboard players list", "Affiche les joueurs suivis par le scoreboard", "Scoreboard"),
                new CommandSuggestion("scoreboard players get ", "Affiche le score d'un joueur", "Scoreboard"),
                new CommandSuggestion("scoreboard players set ", "Définit le score d'un joueur", "Scoreboard"),
                new CommandSuggestion("scoreboard players reset ", "Réinitialise le score d'un joueur", "Scoreboard"),
                new CommandSuggestion("gamerule keepInventory true", "Conserve l'inventaire après la mort", "Gamerule"),
                new CommandSuggestion("gamerule keepInventory false", "Perd l'inventaire après la mort", "Gamerule"),
                new CommandSuggestion("gamerule doDaylightCycle true", "Active le cycle jour/nuit", "Gamerule"),
                new CommandSuggestion("gamerule doDaylightCycle false", "Bloque l'heure actuelle", "Gamerule"),
                new CommandSuggestion("gamerule doMobSpawning true", "Active l'apparition des monstres", "Gamerule"),
                new CommandSuggestion("gamerule doMobSpawning false", "Désactive l'apparition des monstres", "Gamerule"),
                new CommandSuggestion("gamerule mobGriefing true", "Autorise les destructions par les monstres", "Gamerule"),
                new CommandSuggestion("gamerule mobGriefing false", "Empêche les destructions par les creepers/endermen", "Gamerule"),
                new CommandSuggestion("datapack list", "Affiche les datapacks installés et actifs", "Datapack"),
                new CommandSuggestion("function hub:setup_hub_portal", "Réinitialise et installe le portail du Hub", "Fonction"),
                new CommandSuggestion("function hub:portals", "Exécute la boucle de gestion des portails", "Fonction"),
                new CommandSuggestion("function hub:setup_holograms", "Recrée les écritures flottantes au-dessus des portails", "Fonction"),
                new CommandSuggestion("function deathcounter:update_format", "Rafraîchit l'affichage du compteur de morts", "Fonction"),
                new CommandSuggestion("function deathcounter:init", "Réinitialise le système de compteur de morts", "Fonction")
            };
        }

        private void LoadProperties()
        {
            try
            {
                string props = System.IO.Path.Combine(_serverDir, "server.properties");
                if (System.IO.File.Exists(props))
                {
                    string[] lines = System.IO.File.ReadAllLines(props);
                    foreach (string l in lines)
                    {
                        string line = l.Trim();
                        if (line.StartsWith("#") || !line.Contains("=")) continue;
                        int idx = line.IndexOf('=');
                        string k = line.Substring(0, idx).Trim().ToLowerInvariant();
                        string v = line.Substring(idx + 1).Trim();
                        if (k == "rcon.password") _rconPassword = v;
                        else if (k == "rcon.port") int.TryParse(v, out _rconPort);
                    }
                }
            }
            catch { }
        }

        private void BuildUI()
        {
            Grid mainGrid = new Grid();
            mainGrid.Margin = new Thickness(16);
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Header
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(200) }); // Stats & Graph
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // Players & Tabs (Console / Connection Logs)

            // ---------------- HEADER ----------------
            Border headerCard = CreateCard();
            headerCard.Margin = new Thickness(0, 0, 0, 12);
            Grid headerGrid = new Grid();
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            StackPanel titlePanel = new StackPanel();
            TextBlock titleText = new TextBlock
            {
                Text = "MINECRAFT SERVER MONITORING",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)) // Sky 400
            };
            TextBlock subTitle = new TextBlock
            {
                Text = "Dossier : " + _serverDir + "  •  Port : 25565  •  RCON : " + _rconPort,
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), // Slate 400
                Margin = new Thickness(0, 3, 0, 0)
            };
            titlePanel.Children.Add(titleText);
            titlePanel.Children.Add(subTitle);
            headerGrid.Children.Add(titlePanel);

            StackPanel headerControls = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(headerControls, 1);

            _statusBadge = new Border
            {
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(14, 6, 14, 6),
                Margin = new Thickness(0, 0, 10, 0),
                Background = new SolidColorBrush(Color.FromRgb(239, 68, 68))
            };
            _statusText = new TextBlock
            {
                Text = "HORS LIGNE",
                FontWeight = FontWeights.Bold,
                FontSize = 12,
                Foreground = Brushes.White
            };
            _statusBadge.Child = _statusText;
            headerControls.Children.Add(_statusBadge);

            Button btnStart = CreateButton("▶ Démarrer", Color.FromRgb(34, 197, 94), (s, e) => ActionStart());
            btnStart.Margin = new Thickness(0, 0, 8, 0);
            headerControls.Children.Add(btnStart);

            Button btnRestart = CreateButton("🔄 Redémarrer", Color.FromRgb(234, 88, 12), (s, e) => ActionRestart());
            btnRestart.Margin = new Thickness(0, 0, 8, 0);
            headerControls.Children.Add(btnRestart);

            Button btnStop = CreateButton("⏹ Arrêter", Color.FromRgb(239, 68, 68), (s, e) => ActionStop());
            btnStop.Margin = new Thickness(0, 0, 8, 0);
            headerControls.Children.Add(btnStop);

            Button btnBackup = CreateButton("📦 Backup Rapide", Color.FromRgb(14, 165, 233), (s, e) => ActionBackup());
            btnBackup.Margin = new Thickness(0, 0, 8, 0);
            headerControls.Children.Add(btnBackup);

            Button btnSave = CreateButton("💾 Save", Color.FromRgb(16, 185, 129), (s, e) => ExecuteRconCommand("save-all"));
            headerControls.Children.Add(btnSave);

            headerCard.Child = headerGrid;
            mainGrid.Children.Add(headerCard);

            // ---------------- ROW 1: STATS & GRAPH ----------------
            Grid statsGrid = new Grid();
            Grid.SetRow(statsGrid, 1);
            statsGrid.Margin = new Thickness(0, 0, 0, 12);
            statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
            statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            // Stat Cards Box
            StackPanel statCards = new StackPanel();
            statCards.Margin = new Thickness(0, 0, 12, 0);

            Border cardRam = CreateCard();
            cardRam.Margin = new Thickness(0, 0, 0, 8);
            StackPanel ramPanel = new StackPanel();
            ramPanel.Children.Add(new TextBlock { Text = "MÉMOIRE RAM", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)) });
            _txtRamStats = new TextBlock { Text = "-- / 49 Go", FontSize = 18, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)), Margin = new Thickness(0, 4, 0, 0) };
            ramPanel.Children.Add(_txtRamStats);
            cardRam.Child = ramPanel;
            statCards.Children.Add(cardRam);

            Border cardCpu = CreateCard();
            cardCpu.Margin = new Thickness(0, 0, 0, 8);
            StackPanel cpuPanel = new StackPanel();
            cpuPanel.Children.Add(new TextBlock { Text = "CHARGE PROCESSEUR / UPTIME", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)) });
            _txtCpuStats = new TextBlock { Text = "CPU: 0.0%", FontSize = 17, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(74, 222, 128)), Margin = new Thickness(0, 2, 0, 0) };
            _txtUptime = new TextBlock { Text = "Uptime : --", FontSize = 12, Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), Margin = new Thickness(0, 2, 0, 0) };
            cpuPanel.Children.Add(_txtCpuStats);
            cpuPanel.Children.Add(_txtUptime);
            cardCpu.Child = cpuPanel;
            statCards.Children.Add(cardCpu);

            statsGrid.Children.Add(statCards);

            // Chart Card
            Border chartCard = CreateCard();
            Grid.SetColumn(chartCard, 1);
            Grid chartInner = new Grid();
            chartInner.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            chartInner.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            Grid chartHead = new Grid();
            chartHead.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            chartHead.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            chartHead.Children.Add(new TextBlock { Text = "UTILISATION RAM EN TEMPS RÉEL (Go)", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)) });

            StackPanel legend = new StackPanel { Orientation = Orientation.Horizontal };
            Grid.SetColumn(legend, 1);
            Border dotBlue = new Border { Width = 8, Height = 8, CornerRadius = new CornerRadius(4), Background = new SolidColorBrush(Color.FromRgb(56, 189, 248)), Margin = new Thickness(0, 0, 4, 0) };
            legend.Children.Add(dotBlue);
            legend.Children.Add(new TextBlock { Text = "RAM", FontSize = 10, Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)), Margin = new Thickness(0, 0, 10, 0) });
            chartHead.Children.Add(legend);
            chartInner.Children.Add(chartHead);

            _chartCanvas = new Canvas { Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)), Margin = new Thickness(0, 8, 0, 0), ClipToBounds = true };
            Grid.SetRow(_chartCanvas, 1);
            chartInner.Children.Add(_chartCanvas);

            chartCard.Child = chartInner;
            statsGrid.Children.Add(chartCard);
            mainGrid.Children.Add(statsGrid);

            // ---------------- ROW 2: PLAYERS & TABS (CONSOLE / CONNECTION LOGS) ----------------
            Grid bottomGrid = new Grid();
            Grid.SetRow(bottomGrid, 2);
            bottomGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(350) });
            bottomGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            // PLAYERS PANEL (LEFT)
            Border playersCard = CreateCard();
            playersCard.Margin = new Thickness(0, 0, 12, 0);
            Grid playersGrid = new Grid();
            playersGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Header
            playersGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(130) }); // List
            playersGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Action Title
            playersGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // Actions

            Grid plHead = new Grid();
            plHead.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            plHead.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            plHead.Children.Add(new TextBlock { Text = "JOUEURS CONNECTÉS", FontSize = 12, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)) });
            _txtPlayerCount = new TextBlock { Text = "0 Joueur", FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)) };
            Grid.SetColumn(_txtPlayerCount, 1);
            plHead.Children.Add(_txtPlayerCount);
            playersGrid.Children.Add(plHead);

            _lstPlayers = new ListBox
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                Foreground = Brushes.White,
                Margin = new Thickness(0, 8, 0, 8),
                FontSize = 13
            };
            _lstPlayers.SelectionChanged += OnPlayerSelected;
            Grid.SetRow(_lstPlayers, 1);
            playersGrid.Children.Add(_lstPlayers);

            _txtSelectedPlayer = new TextBlock
            {
                Text = "Sélectionnez un joueur ci-dessus pour agir :",
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 6)
            };
            Grid.SetRow(_txtSelectedPlayer, 2);
            playersGrid.Children.Add(_txtSelectedPlayer);

            ScrollViewer scrollActions = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            Grid.SetRow(scrollActions, 3);
            _pnlPlayerActions = new StackPanel();

            WrapPanel gmWrap = new WrapPanel { Margin = new Thickness(0, 0, 0, 6) };
            gmWrap.Children.Add(CreateSmallButton("🎮 Créatif", Color.FromRgb(168, 85, 247), (s, e) => PlayerCmd("gamemode creative {0}")));
            gmWrap.Children.Add(CreateSmallButton("⚔️ Survie", Color.FromRgb(34, 197, 94), (s, e) => PlayerCmd("gamemode survival {0}")));
            gmWrap.Children.Add(CreateSmallButton("👁️ Spectateur", Color.FromRgb(59, 130, 246), (s, e) => PlayerCmd("gamemode spectator {0}")));
            gmWrap.Children.Add(CreateSmallButton("🛡️ Aventure", Color.FromRgb(245, 158, 11), (s, e) => PlayerCmd("gamemode adventure {0}")));
            _pnlPlayerActions.Children.Add(gmWrap);

            WrapPanel actWrap = new WrapPanel { Margin = new Thickness(0, 0, 0, 6) };
            actWrap.Children.Add(CreateSmallButton("📍 TP Hub", Color.FromRgb(14, 165, 233), (s, e) => PlayerCmd("execute in hub:lobby run tp {0} 171.5 63 -186")));
            actWrap.Children.Add(CreateSmallButton("🌲 TP Survie", Color.FromRgb(16, 185, 129), (s, e) => PlayerCmd("execute in minecraft:overworld run tp {0} -128 72 -204")));
            actWrap.Children.Add(CreateSmallButton("💖 Soigner", Color.FromRgb(236, 72, 153), (s, e) => PlayerCmd("effect give {0} instant_health 1 255")));
            actWrap.Children.Add(CreateSmallButton("💎 64 Diamants", Color.FromRgb(6, 182, 212), (s, e) => PlayerCmd("give {0} diamond 64")));
            _pnlPlayerActions.Children.Add(actWrap);

            WrapPanel admWrap = new WrapPanel();
            admWrap.Children.Add(CreateSmallButton("⭐ Donner OP", Color.FromRgb(234, 179, 8), (s, e) => PlayerCmd("op {0}")));
            admWrap.Children.Add(CreateSmallButton("❌ Retirer OP", Color.FromRgb(100, 116, 139), (s, e) => PlayerCmd("deop {0}")));
            admWrap.Children.Add(CreateSmallButton("🚪 Kick", Color.FromRgb(239, 68, 68), (s, e) => PlayerCmd("kick {0} Expulsion par l'administrateur")));
            admWrap.Children.Add(CreateSmallButton("🔨 Ban", Color.FromRgb(185, 28, 28), (s, e) => PlayerCmd("ban {0} Bannissement definitif")));
            _pnlPlayerActions.Children.Add(admWrap);

            scrollActions.Content = _pnlPlayerActions;
            playersGrid.Children.Add(scrollActions);

            playersCard.Child = playersGrid;
            bottomGrid.Children.Add(playersCard);

            // RIGHT PANEL WITH TABS (CONSOLE & PLAYER LOGS)
            Border rightCard = CreateCard();
            Grid.SetColumn(rightCard, 1);
            Grid rightGrid = new Grid();
            rightGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Tab header
            rightGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // Tab content

            // Tab Switcher Header
            StackPanel tabHeader = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };

            _tabBtnConsole = new Button
            {
                Content = "💻 Console & Commandes",
                Background = new SolidColorBrush(Color.FromRgb(2, 132, 199)),
                Foreground = Brushes.White,
                FontWeight = FontWeights.Bold,
                FontSize = 12,
                Padding = new Thickness(14, 7, 14, 7),
                BorderThickness = new Thickness(0),
                Margin = new Thickness(0, 0, 8, 0),
                Cursor = Cursors.Hand
            };
            _tabBtnConsole.Click += (s, e) => SwitchTab(true);

            _tabBtnLogs = new Button
            {
                Content = "👥 Logs de Connexions (0)",
                Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                FontWeight = FontWeights.SemiBold,
                FontSize = 12,
                Padding = new Thickness(14, 7, 14, 7),
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand
            };
            _tabBtnLogs.Click += (s, e) => SwitchTab(false);

            tabHeader.Children.Add(_tabBtnConsole);
            tabHeader.Children.Add(_tabBtnLogs);
            rightGrid.Children.Add(tabHeader);

            // ---------------- TAB 1: CONSOLE PANEL ----------------
            _panelConsole = new Grid();
            Grid.SetRow(_panelConsole, 1);
            _panelConsole.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Broadcast
            _panelConsole.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // Console Log
            _panelConsole.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Cmd Input

            // Broadcast
            Grid bcGrid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
            bcGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            bcGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            _txtBroadcastInput = new TextBox
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                Foreground = Brushes.White,
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                Padding = new Thickness(8, 6, 8, 6),
                FontSize = 13
            };
            _txtBroadcastInput.KeyDown += (s, e) => { if (e.Key == Key.Enter) ActionBroadcast(); };
            bcGrid.Children.Add(_txtBroadcastInput);
            Button btnBc = CreateButton("📢 Diffuser", Color.FromRgb(59, 130, 246), (s, e) => ActionBroadcast());
            btnBc.Margin = new Thickness(8, 0, 0, 0);
            Grid.SetColumn(btnBc, 1);
            bcGrid.Children.Add(btnBc);
            _panelConsole.Children.Add(bcGrid);

            // Console output
            _txtConsoleOutput = new TextBox
            {
                Background = new SolidColorBrush(Color.FromRgb(2, 6, 23)),
                Foreground = new SolidColorBrush(Color.FromRgb(226, 232, 240)),
                FontFamily = new FontFamily("Consolas, monospace"),
                FontSize = 12,
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                Margin = new Thickness(0, 0, 0, 8),
                Padding = new Thickness(8)
            };
            Grid.SetRow(_txtConsoleOutput, 1);
            _panelConsole.Children.Add(_txtConsoleOutput);

            // Command input container
            Grid cmdGrid = new Grid();
            Grid.SetRow(cmdGrid, 2);
            cmdGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            cmdGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            _txtCommandInput = new TextBox
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                Foreground = Brushes.White,
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                Padding = new Thickness(8, 6, 8, 6),
                FontSize = 13,
                FontFamily = new FontFamily("Consolas, Segoe UI, monospace")
            };
            _txtCommandInput.TextChanged += OnCommandInputTextChanged;
            _txtCommandInput.PreviewKeyDown += OnCommandInputPreviewKeyDown;
            cmdGrid.Children.Add(_txtCommandInput);

            _lstSuggestions = new ListBox
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                BorderThickness = new Thickness(1),
                Foreground = Brushes.White,
                MaxHeight = 220,
                FontSize = 12,
                FontFamily = new FontFamily("Consolas, Segoe UI, monospace")
            };
            _lstSuggestions.SelectionChanged += OnSuggestionSelected;
            _lstSuggestions.PreviewMouseLeftButtonUp += (s, e) => ApplySelectedSuggestion();

            Border popupBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(6),
                Child = _lstSuggestions,
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = Colors.Black,
                    BlurRadius = 15,
                    Opacity = 0.6,
                    ShadowDepth = 3
                }
            };

            _suggestionsPopup = new Popup
            {
                PlacementTarget = _txtCommandInput,
                Placement = PlacementMode.Top,
                VerticalOffset = -4,
                StaysOpen = false,
                AllowsTransparency = true,
                Child = popupBorder
            };
            cmdGrid.Children.Add(_suggestionsPopup);

            Button btnSendCmd = CreateButton("Envoyer", Color.FromRgb(34, 197, 94), (s, e) => ActionSendCustomCommand());
            btnSendCmd.Margin = new Thickness(8, 0, 0, 0);
            Grid.SetColumn(btnSendCmd, 1);
            cmdGrid.Children.Add(btnSendCmd);
            _panelConsole.Children.Add(cmdGrid);

            rightGrid.Children.Add(_panelConsole);

            // ---------------- TAB 2: PLAYER CONNECTION LOGS PANEL ----------------
            _panelPlayerLogs = new Grid();
            Grid.SetRow(_panelPlayerLogs, 1);
            _panelPlayerLogs.Visibility = Visibility.Collapsed;
            _panelPlayerLogs.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Stats Toolbar
            _panelPlayerLogs.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Search / Filter
            _panelPlayerLogs.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // Logs List

            // Row 0: Stats Toolbar
            Grid logStatsGrid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
            logStatsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            logStatsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            StackPanel statBadges = new StackPanel { Orientation = Orientation.Horizontal };
            
            // Badge Connexions
            Border bConn = new Border { Background = new SolidColorBrush(Color.FromArgb(40, 16, 185, 129)), BorderBrush = new SolidColorBrush(Color.FromRgb(16, 185, 129)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 4, 8, 4), Margin = new Thickness(0, 0, 8, 0) };
            _txtLogStatsConn = new TextBlock { Text = "🟢 Connexions : 0", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(52, 211, 153)) };
            bConn.Child = _txtLogStatsConn;
            statBadges.Children.Add(bConn);

            // Badge Déconnexions
            Border bDeconn = new Border { Background = new SolidColorBrush(Color.FromArgb(40, 249, 115, 22)), BorderBrush = new SolidColorBrush(Color.FromRgb(249, 115, 22)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 4, 8, 4), Margin = new Thickness(0, 0, 8, 0) };
            _txtLogStatsDeconn = new TextBlock { Text = "🔴 Déconnexions : 0", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(251, 146, 60)) };
            bDeconn.Child = _txtLogStatsDeconn;
            statBadges.Children.Add(bDeconn);

            // Badge Joueurs uniques
            Border bUniq = new Border { Background = new SolidColorBrush(Color.FromArgb(40, 56, 189, 248)), BorderBrush = new SolidColorBrush(Color.FromRgb(56, 189, 248)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 4, 8, 4) };
            _txtLogStatsUnique = new TextBlock { Text = "👤 Joueurs : 0", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)) };
            bUniq.Child = _txtLogStatsUnique;
            statBadges.Children.Add(bUniq);

            logStatsGrid.Children.Add(statBadges);

            StackPanel logActionBtns = new StackPanel { Orientation = Orientation.Horizontal };
            Grid.SetColumn(logActionBtns, 1);

            Button btnRefreshLogs = CreateButton("🔄 Rafraîchir", Color.FromRgb(51, 65, 85), (s, e) => ReloadAllLogs());
            btnRefreshLogs.Margin = new Thickness(0, 0, 6, 0);
            logActionBtns.Children.Add(btnRefreshLogs);

            Button btnExportCsv = CreateButton("📥 Export CSV", Color.FromRgb(14, 165, 233), (s, e) => ExportLogsCsv());
            btnExportCsv.Margin = new Thickness(0, 0, 6, 0);
            logActionBtns.Children.Add(btnExportCsv);

            Button btnClearView = CreateButton("🗑️ Vider", Color.FromRgb(225, 29, 72), (s, e) => ClearLogsView());
            logActionBtns.Children.Add(btnClearView);

            logStatsGrid.Children.Add(logActionBtns);
            _panelPlayerLogs.Children.Add(logStatsGrid);

            // Row 1: Search & Type Filter
            Grid filterGrid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
            filterGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            filterGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });

            _txtSearchPlayer = new TextBox
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                Foreground = Brushes.White,
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                Padding = new Thickness(8, 6, 8, 6),
                FontSize = 12,
                Margin = new Thickness(0, 0, 8, 0)
            };
            _txtSearchPlayer.TextChanged += (s, e) => ApplyLogFilters();
            filterGrid.Children.Add(_txtSearchPlayer);

            _cmbFilterType = new ComboBox
            {
                Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
                Foreground = Brushes.Black,
                FontSize = 12,
                Padding = new Thickness(6, 4, 6, 4)
            };
            _cmbFilterType.Items.Add("Tous les événements");
            _cmbFilterType.Items.Add("Connexions uniquement");
            _cmbFilterType.Items.Add("Déconnexions uniquement");
            _cmbFilterType.SelectedIndex = 0;
            _cmbFilterType.SelectionChanged += (s, e) => ApplyLogFilters();
            Grid.SetColumn(_cmbFilterType, 1);
            filterGrid.Children.Add(_cmbFilterType);

            Grid.SetRow(filterGrid, 1);
            _panelPlayerLogs.Children.Add(filterGrid);

            // Row 2: Logs List
            _lstConnectionLogs = new ListBox
            {
                Background = new SolidColorBrush(Color.FromRgb(2, 6, 23)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                Foreground = Brushes.White,
                Padding = new Thickness(6),
                ItemsSource = _displayedLogs
            };
            ScrollViewer.SetHorizontalScrollBarVisibility(_lstConnectionLogs, ScrollBarVisibility.Disabled);
            ScrollViewer.SetVerticalScrollBarVisibility(_lstConnectionLogs, ScrollBarVisibility.Auto);

            string templateXaml = @"
<DataTemplate xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"">
    <Border Background=""#1e293b"" BorderBrush=""#334155"" BorderThickness=""1"" CornerRadius=""6"" Padding=""10,8"" Margin=""0,0,0,6"">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width=""70""/>
                <ColumnDefinition Width=""110""/>
                <ColumnDefinition Width=""130""/>
                <ColumnDefinition Width=""*""/>
            </Grid.ColumnDefinitions>

            <!-- Time -->
            <TextBlock Text=""{Binding TimeString}"" FontFamily=""Consolas"" FontSize=""11"" FontWeight=""SemiBold"" Foreground=""#94a3b8"" VerticalAlignment=""Center""/>

            <!-- Badge -->
            <Border Grid.Column=""1"" Background=""{Binding BadgeBg}"" BorderBrush=""{Binding BadgeFg}"" BorderThickness=""1"" CornerRadius=""4"" Padding=""5,2"" Margin=""0,0,8,0"" VerticalAlignment=""Center"" HorizontalAlignment=""Left"">
                <StackPanel Orientation=""Horizontal"">
                    <TextBlock Text=""{Binding Icon}"" FontSize=""10"" Margin=""0,0,4,0"" VerticalAlignment=""Center""/>
                    <TextBlock Text=""{Binding EventType}"" FontSize=""10"" FontWeight=""Bold"" Foreground=""{Binding BadgeFg}"" VerticalAlignment=""Center""/>
                </StackPanel>
            </Border>

            <!-- Player -->
            <TextBlock Grid.Column=""2"" Text=""{Binding PlayerName}"" FontSize=""13"" FontWeight=""Bold"" Foreground=""#38bdf8"" VerticalAlignment=""Center"" TextTrimming=""CharacterEllipsis""/>

            <!-- Details -->
            <TextBlock Grid.Column=""3"" Text=""{Binding Details}"" FontSize=""12"" Foreground=""#cbd5e1"" VerticalAlignment=""Center"" TextTrimming=""CharacterEllipsis""/>
        </Grid>
    </Border>
</DataTemplate>";

            _lstConnectionLogs.ItemTemplate = (DataTemplate)System.Windows.Markup.XamlReader.Parse(templateXaml);

            Grid.SetRow(_lstConnectionLogs, 2);
            _panelPlayerLogs.Children.Add(_lstConnectionLogs);

            rightGrid.Children.Add(_panelPlayerLogs);

            rightCard.Child = rightGrid;
            bottomGrid.Children.Add(rightCard);

            mainGrid.Children.Add(bottomGrid);
            this.Content = mainGrid;
        }

        private void SwitchTab(bool showConsole)
        {
            if (showConsole)
            {
                _panelConsole.Visibility = Visibility.Visible;
                _panelPlayerLogs.Visibility = Visibility.Collapsed;
                _tabBtnConsole.Background = new SolidColorBrush(Color.FromRgb(2, 132, 199));
                _tabBtnConsole.Foreground = Brushes.White;
                _tabBtnConsole.FontWeight = FontWeights.Bold;

                _tabBtnLogs.Background = new SolidColorBrush(Color.FromRgb(30, 41, 59));
                _tabBtnLogs.Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184));
                _tabBtnLogs.FontWeight = FontWeights.SemiBold;
            }
            else
            {
                _panelConsole.Visibility = Visibility.Collapsed;
                _panelPlayerLogs.Visibility = Visibility.Visible;
                _tabBtnLogs.Background = new SolidColorBrush(Color.FromRgb(2, 132, 199));
                _tabBtnLogs.Foreground = Brushes.White;
                _tabBtnLogs.FontWeight = FontWeights.Bold;

                _tabBtnConsole.Background = new SolidColorBrush(Color.FromRgb(30, 41, 59));
                _tabBtnConsole.Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184));
                _tabBtnConsole.FontWeight = FontWeights.SemiBold;
            }
        }

        private void InitialLoadLogs()
        {
            _allConnectionLogs.Clear();

            // 1. Load recent archived logs if available
            try
            {
                string logsDir = System.IO.Path.Combine(_serverDir, "logs");
                if (System.IO.Directory.Exists(logsDir))
                {
                    var gzFiles = new DirectoryInfo(logsDir).GetFiles("*.log.gz");
                    Array.Sort(gzFiles, (a, b) => b.LastWriteTime.CompareTo(a.LastWriteTime));

                    int countToRead = Math.Min(3, gzFiles.Length);
                    for (int i = countToRead - 1; i >= 0; i--)
                    {
                        try
                        {
                            using (FileStream fs = gzFiles[i].OpenRead())
                            using (GZipStream gz = new GZipStream(fs, CompressionMode.Decompress))
                            using (StreamReader sr = new StreamReader(gz, Encoding.UTF8))
                            {
                                string l;
                                while ((l = sr.ReadLine()) != null)
                                {
                                    ProcessLogLine(l, false);
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }

            // 2. Load latest.log
            try
            {
                string latest = System.IO.Path.Combine(_serverDir, @"logs\latest.log");
                if (File.Exists(latest))
                {
                    using (FileStream fs = new FileStream(latest, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                    {
                        string l;
                        while ((l = sr.ReadLine()) != null)
                        {
                            ProcessLogLine(l, false);
                        }
                        _lastLogFileOffset = fs.Position;
                    }
                }
            }
            catch { }

            ApplyLogFilters();
        }

        private void ReloadAllLogs()
        {
            _lastLogFileOffset = 0;
            InitialLoadLogs();
            LogConsole("Logs de connexion rechargés (" + _allConnectionLogs.Count + " événements analysés).");
        }

        private void ClearLogsView()
        {
            _allConnectionLogs.Clear();
            ApplyLogFilters();
        }

        private void ExportLogsCsv()
        {
            try
            {
                string exportPath = System.IO.Path.Combine(_serverDir, "player-connections-export.csv");
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("Timestamp;Heure;Joueur;Type;Details;IP;Position;Raison");

                foreach (var log in _allConnectionLogs)
                {
                    sb.AppendLine(string.Format("{0:yyyy-MM-dd HH:mm:ss};{1};{2};{3};{4};{5};{6};{7}",
                        log.Timestamp,
                        log.TimeString,
                        log.PlayerName,
                        log.EventType,
                        (log.Details ?? "").Replace(";", ","),
                        log.IpAddress ?? "",
                        (log.Coordinates ?? "").Replace(";", ","),
                        (log.Reason ?? "").Replace(";", ",")
                    ));
                }

                File.WriteAllText(exportPath, sb.ToString(), Encoding.UTF8);
                MessageBox.Show("Export réussi dans :\n" + exportPath, "Export Logs Joueurs", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Erreur lors de l'export CSV : " + ex.Message, "Erreur", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void ReadNewLogLines()
        {
            try
            {
                string latest = System.IO.Path.Combine(_serverDir, @"logs\latest.log");
                if (!File.Exists(latest)) return;

                FileInfo fi = new FileInfo(latest);
                if (fi.Length < _lastLogFileOffset)
                {
                    _lastLogFileOffset = 0;
                }

                if (fi.Length == _lastLogFileOffset) return;

                using (FileStream fs = new FileStream(latest, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    fs.Seek(_lastLogFileOffset, SeekOrigin.Begin);
                    using (StreamReader sr = new StreamReader(fs, Encoding.UTF8))
                    {
                        string line;
                        bool hadNewLogs = false;
                        while ((line = sr.ReadLine()) != null)
                        {
                            if (ProcessLogLine(line, true))
                            {
                                hadNewLogs = true;
                            }
                        }
                        _lastLogFileOffset = fs.Position;
                        if (hadNewLogs)
                        {
                            ApplyLogFilters();
                        }
                    }
                }
            }
            catch { }
        }

        private bool ProcessLogLine(string line, bool isLive)
        {
            if (string.IsNullOrEmpty(line)) return false;

            Match mLogin = _loginRegex.Match(line);
            if (mLogin.Success)
            {
                string time = mLogin.Groups["time"].Value;
                string player = mLogin.Groups["player"].Value;
                string ip = mLogin.Groups["ip"].Value;
                string coords = mLogin.Groups["coords"].Value;

                var entry = new PlayerConnectionLog
                {
                    Timestamp = DateTime.Now,
                    TimeString = time,
                    PlayerName = player,
                    EventType = "CONNEXION",
                    IpAddress = ip,
                    Coordinates = coords,
                    Details = "IP : " + ip + "  •  Pos : (" + coords + ")",
                    Icon = "🟢",
                    BadgeBg = new SolidColorBrush(Color.FromArgb(40, 16, 185, 129)),
                    BadgeFg = new SolidColorBrush(Color.FromRgb(52, 211, 153))
                };

                _allConnectionLogs.Insert(0, entry);
                if (isLive)
                {
                    LogConsole(string.Format("🟢 [CONNEXION] {0} s'est connecté ({1})", player, ip));
                }
                return true;
            }

            Match mDisc = _disconnectRegex.Match(line);
            if (mDisc.Success)
            {
                string time = mDisc.Groups["time"].Value;
                string player = mDisc.Groups["player"].Value;
                string reason = mDisc.Groups["reason"].Value.Trim();
                if (string.IsNullOrEmpty(reason)) reason = "Déconnecté";

                bool isKickOrBan = reason.IndexOf("expulsion", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                  reason.IndexOf("ban", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                  reason.IndexOf("kick", StringComparison.OrdinalIgnoreCase) >= 0;

                var entry = new PlayerConnectionLog
                {
                    Timestamp = DateTime.Now,
                    TimeString = time,
                    PlayerName = player,
                    EventType = isKickOrBan ? "EXPULSION" : "DÉCONNEXION",
                    Reason = reason,
                    Details = "Raison : " + reason,
                    Icon = isKickOrBan ? "🔨" : "🔴",
                    BadgeBg = isKickOrBan
                        ? new SolidColorBrush(Color.FromArgb(40, 239, 68, 68))
                        : new SolidColorBrush(Color.FromArgb(40, 249, 115, 22)),
                    BadgeFg = isKickOrBan
                        ? new SolidColorBrush(Color.FromRgb(248, 113, 113))
                        : new SolidColorBrush(Color.FromRgb(251, 146, 60))
                };

                _allConnectionLogs.Insert(0, entry);
                if (isLive)
                {
                    LogConsole(string.Format("🔴 [DÉCONNEXION] {0} a quitté ({1})", player, reason));
                }
                return true;
            }

            return false;
        }

        private void ApplyLogFilters()
        {
            string filterText = _txtSearchPlayer != null ? _txtSearchPlayer.Text.Trim().ToLowerInvariant() : "";
            int filterTypeIndex = _cmbFilterType != null ? _cmbFilterType.SelectedIndex : 0;

            _displayedLogs.Clear();

            int connCount = 0;
            int deconnCount = 0;
            HashSet<string> uniquePlayers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var log in _allConnectionLogs)
            {
                if (log.EventType == "CONNEXION") connCount++;
                else deconnCount++;
                uniquePlayers.Add(log.PlayerName);

                // Filter by search query
                if (!string.IsNullOrEmpty(filterText))
                {
                    if (!log.PlayerName.ToLowerInvariant().Contains(filterText) &&
                        !(log.Details ?? "").ToLowerInvariant().Contains(filterText))
                    {
                        continue;
                    }
                }

                // Filter by type
                if (filterTypeIndex == 1 && log.EventType != "CONNEXION") continue;
                if (filterTypeIndex == 2 && log.EventType == "CONNEXION") continue;

                _displayedLogs.Add(log);
            }

            if (_txtLogStatsConn != null) _txtLogStatsConn.Text = "🟢 Connexions : " + connCount;
            if (_txtLogStatsDeconn != null) _txtLogStatsDeconn.Text = "🔴 Déconnexions : " + deconnCount;
            if (_txtLogStatsUnique != null) _txtLogStatsUnique.Text = "👤 Joueurs : " + uniquePlayers.Count;
            if (_tabBtnLogs != null) _tabBtnLogs.Content = "👥 Logs de Connexions (" + _allConnectionLogs.Count + ")";
        }

        private void OnCommandInputTextChanged(object sender, TextChangedEventArgs e)
        {
            if (_isUpdatingText) return;

            string query = _txtCommandInput.Text.TrimStart('/');
            if (string.IsNullOrWhiteSpace(query))
            {
                _suggestionsPopup.IsOpen = false;
                return;
            }

            List<CommandSuggestion> matches = new List<CommandSuggestion>();
            string lower = query.ToLowerInvariant();

            foreach (CommandSuggestion cs in _baseCommands)
            {
                if (cs.Command.ToLowerInvariant().StartsWith(lower))
                {
                    matches.Add(cs);
                }
            }

            foreach (string p in _onlinePlayerNames)
            {
                if (p.ToLowerInvariant().StartsWith(lower) && !query.Contains(" "))
                {
                    matches.Add(new CommandSuggestion("tp " + p, "Téléporter vers " + p, "Joueur"));
                    matches.Add(new CommandSuggestion("gamemode survival " + p, "Mettre " + p + " en survie", "Joueur"));
                    matches.Add(new CommandSuggestion("gamemode creative " + p, "Mettre " + p + " en créatif", "Joueur"));
                }
            }

            foreach (CommandSuggestion cs in _baseCommands)
            {
                if (!matches.Contains(cs) && cs.Command.ToLowerInvariant().Contains(lower))
                {
                    matches.Add(cs);
                }
            }

            if (matches.Count > 0)
            {
                _lstSuggestions.Items.Clear();
                foreach (CommandSuggestion m in matches)
                {
                    StackPanel itemPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 2, 4, 2) };

                    Border catBadge = new Border
                    {
                        Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                        BorderBrush = new SolidColorBrush(Color.FromRgb(71, 85, 105)),
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(3),
                        Padding = new Thickness(5, 1, 5, 1),
                        Margin = new Thickness(0, 0, 8, 0),
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    catBadge.Child = new TextBlock
                    {
                        Text = m.Category,
                        FontSize = 10,
                        Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184))
                    };
                    itemPanel.Children.Add(catBadge);

                    TextBlock cmdText = new TextBlock
                    {
                        Text = "/" + m.Command,
                        FontWeight = FontWeights.Bold,
                        Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                        Margin = new Thickness(0, 0, 8, 0),
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    itemPanel.Children.Add(cmdText);

                    TextBlock descText = new TextBlock
                    {
                        Text = "•  " + m.Description,
                        Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                        VerticalAlignment = VerticalAlignment.Center,
                        FontSize = 11
                    };
                    itemPanel.Children.Add(descText);

                    ListBoxItem lbi = new ListBoxItem
                    {
                        Content = itemPanel,
                        Tag = m.Command,
                        Background = Brushes.Transparent,
                        Foreground = Brushes.White,
                        Padding = new Thickness(4)
                    };
                    _lstSuggestions.Items.Add(lbi);
                }

                _suggestionsPopup.Width = Math.Max(300, _txtCommandInput.ActualWidth);
                _suggestionsPopup.IsOpen = true;
            }
            else
            {
                _suggestionsPopup.IsOpen = false;
            }
        }

        private void OnCommandInputPreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (_suggestionsPopup.IsOpen)
            {
                if (e.Key == Key.Down)
                {
                    int next = _lstSuggestions.SelectedIndex + 1;
                    if (next >= _lstSuggestions.Items.Count) next = 0;
                    _lstSuggestions.SelectedIndex = next;
                    _lstSuggestions.ScrollIntoView(_lstSuggestions.SelectedItem);
                    e.Handled = true;
                    return;
                }
                else if (e.Key == Key.Up)
                {
                    int prev = _lstSuggestions.SelectedIndex - 1;
                    if (prev < 0) prev = _lstSuggestions.Items.Count - 1;
                    _lstSuggestions.SelectedIndex = prev;
                    _lstSuggestions.ScrollIntoView(_lstSuggestions.SelectedItem);
                    e.Handled = true;
                    return;
                }
                else if (e.Key == Key.Tab || (e.Key == Key.Enter && _lstSuggestions.SelectedItem != null))
                {
                    ApplySelectedSuggestion();
                    e.Handled = true;
                    return;
                }
                else if (e.Key == Key.Escape)
                {
                    _suggestionsPopup.IsOpen = false;
                    e.Handled = true;
                    return;
                }
            }
            else
            {
                if (e.Key == Key.Up && _commandHistory.Count > 0)
                {
                    if (_historyIndex == -1) _historyIndex = _commandHistory.Count - 1;
                    else if (_historyIndex > 0) _historyIndex--;

                    _isUpdatingText = true;
                    _txtCommandInput.Text = _commandHistory[_historyIndex];
                    _txtCommandInput.CaretIndex = _txtCommandInput.Text.Length;
                    _isUpdatingText = false;
                    e.Handled = true;
                    return;
                }
                else if (e.Key == Key.Down && _historyIndex != -1)
                {
                    if (_historyIndex < _commandHistory.Count - 1)
                    {
                        _historyIndex++;
                        _isUpdatingText = true;
                        _txtCommandInput.Text = _commandHistory[_historyIndex];
                        _txtCommandInput.CaretIndex = _txtCommandInput.Text.Length;
                        _isUpdatingText = false;
                    }
                    else
                    {
                        _historyIndex = -1;
                        _isUpdatingText = true;
                        _txtCommandInput.Text = "";
                        _isUpdatingText = false;
                    }
                    e.Handled = true;
                    return;
                }
            }

            if (e.Key == Key.Enter)
            {
                ActionSendCustomCommand();
                e.Handled = true;
            }
        }

        private void OnSuggestionSelected(object sender, SelectionChangedEventArgs e)
        {
        }

        private void ApplySelectedSuggestion()
        {
            ListBoxItem selectedItem = _lstSuggestions.SelectedItem as ListBoxItem;
            if (selectedItem != null && selectedItem.Tag != null)
            {
                string cmd = selectedItem.Tag.ToString();
                _isUpdatingText = true;
                _txtCommandInput.Text = cmd;
                _txtCommandInput.CaretIndex = _txtCommandInput.Text.Length;
                _isUpdatingText = false;
                _suggestionsPopup.IsOpen = false;
                _txtCommandInput.Focus();
            }
        }

        private Border CreateCard()
        {
            return new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)), // Slate 800
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)), // Slate 700
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14)
            };
        }

        private Button CreateButton(string text, Color bg, RoutedEventHandler onClick)
        {
            Button btn = new Button
            {
                Content = text,
                Background = new SolidColorBrush(bg),
                Foreground = Brushes.White,
                FontWeight = FontWeights.SemiBold,
                FontSize = 12,
                Padding = new Thickness(12, 6, 12, 6),
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand
            };
            btn.Click += onClick;
            return btn;
        }

        private Button CreateSmallButton(string text, Color bg, RoutedEventHandler onClick)
        {
            Button btn = new Button
            {
                Content = text,
                Background = new SolidColorBrush(bg),
                Foreground = Brushes.White,
                FontWeight = FontWeights.SemiBold,
                FontSize = 11,
                Padding = new Thickness(8, 5, 8, 5),
                Margin = new Thickness(0, 0, 6, 6),
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand
            };
            btn.Click += onClick;
            return btn;
        }

        private void OnTimerTick(object sender, EventArgs e)
        {
            FindServerProcess();
            UpdateStats();
            QueryRconInfo();
            ReadNewLogLines();
            DrawChart();
        }

        private void FindServerProcess()
        {
            try
            {
                if (_serverProcess != null && !_serverProcess.HasExited)
                    return;

                _serverProcess = null;
                Process[] procs = Process.GetProcessesByName("java");
                foreach (Process p in procs)
                {
                    try
                    {
                        _serverProcess = p;
                        break;
                    }
                    catch { }
                }
            }
            catch { }
        }

        private void UpdateStats()
        {
            try
            {
                if (_serverProcess != null && !_serverProcess.HasExited)
                {
                    _serverProcess.Refresh();
                    long memBytes = _serverProcess.WorkingSet64;
                    double ramGb = memBytes / (1024.0 * 1024.0 * 1024.0);
                    _txtRamStats.Text = string.Format("{0:0.00} Go / 49 Go", ramGb);

                    DateTime now = DateTime.UtcNow;
                    TimeSpan totalTime = _serverProcess.TotalProcessorTime;
                    double elapsed = (now - _lastCpuCheck).TotalMilliseconds;
                    if (elapsed > 500 && _lastCpuTime > TimeSpan.Zero)
                    {
                        double cpuUsage = (totalTime - _lastCpuTime).TotalMilliseconds / (Environment.ProcessorCount * elapsed) * 100.0;
                        cpuUsage = Math.Max(0.0, Math.Min(100.0, cpuUsage));
                        _txtCpuStats.Text = string.Format("CPU: {0:0.0}%", cpuUsage);
                        _cpuHistory.Add(cpuUsage);
                        if (_cpuHistory.Count > MaxHistory) _cpuHistory.RemoveAt(0);
                    }
                    _lastCpuTime = totalTime;
                    _lastCpuCheck = now;

                    _ramHistory.Add(ramGb);
                    if (_ramHistory.Count > MaxHistory) _ramHistory.RemoveAt(0);

                    try
                    {
                        TimeSpan up = DateTime.Now - _serverProcess.StartTime;
                        _txtUptime.Text = string.Format("Uptime : {0}h {1:00}m {2:00}s", (int)up.TotalHours, up.Minutes, up.Seconds);
                    }
                    catch
                    {
                        _txtUptime.Text = "En cours d'exécution";
                    }

                    _statusBadge.Background = new SolidColorBrush(Color.FromRgb(34, 197, 94)); // Green
                    _statusText.Text = "EN LIGNE";
                }
                else
                {
                    _statusBadge.Background = new SolidColorBrush(Color.FromRgb(239, 68, 68)); // Red
                    _statusText.Text = "HORS LIGNE";
                    _txtRamStats.Text = "0.00 Go / 49 Go";
                    _txtCpuStats.Text = "CPU: 0.0%";
                    _txtUptime.Text = "Serveur arrêté";
                }
            }
            catch
            {
                _statusBadge.Background = new SolidColorBrush(Color.FromRgb(239, 68, 68));
                _statusText.Text = "HORS LIGNE";
            }
        }

        private void QueryRconInfo()
        {
            try
            {
                if (!_rcon.Connect("127.0.0.1", _rconPort, _rconPassword))
                    return;

                string listResp = _rcon.SendCommand("list");
                if (!string.IsNullOrEmpty(listResp))
                {
                    Match match = Regex.Match(listResp, @"(?:There are|Il y a)\s+(\d+)\s+(?:of a max of|sur un maximum de|\/)\s*(\d+)", RegexOptions.IgnoreCase);
                    string countStr = match.Success ? string.Format("{0} / {1} Joueurs", match.Groups[1].Value, match.Groups[2].Value) : listResp;
                    _txtPlayerCount.Text = countStr;

                    int colonIdx = listResp.IndexOf(':');
                    List<string> currentOnline = new List<string>();
                    if (colonIdx >= 0 && colonIdx < listResp.Length - 1)
                    {
                        string namesPart = listResp.Substring(colonIdx + 1);
                        string[] split = namesPart.Split(new char[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                        foreach (string n in split)
                        {
                            currentOnline.Add(n.Trim());
                        }
                    }

                    _onlinePlayerNames = currentOnline;

                    string selected = _lstPlayers.SelectedItem as string;
                    _lstPlayers.Items.Clear();
                    foreach (string p in currentOnline)
                    {
                        _lstPlayers.Items.Add(p);
                    }
                    if (selected != null && _lstPlayers.Items.Contains(selected))
                    {
                        _lstPlayers.SelectedItem = selected;
                    }
                }
            }
            catch { }
        }

        private void DrawChart()
        {
            if (_chartCanvas == null || _chartCanvas.ActualWidth < 10 || _chartCanvas.ActualHeight < 10)
                return;

            _chartCanvas.Children.Clear();
            double w = _chartCanvas.ActualWidth;
            double h = _chartCanvas.ActualHeight;

            for (int i = 1; i <= 4; i++)
            {
                double y = h * (i / 5.0);
                Line gridLine = new Line
                {
                    X1 = 0,
                    Y1 = y,
                    X2 = w,
                    Y2 = y,
                    Stroke = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                    StrokeThickness = 1,
                    StrokeDashArray = new DoubleCollection { 3, 3 }
                };
                _chartCanvas.Children.Add(gridLine);
            }

            if (_ramHistory.Count < 2) return;

            double maxRam = 49.0;
            PointCollection points = new PointCollection();
            PointCollection fillPoints = new PointCollection();
            fillPoints.Add(new Point(0, h));

            double step = w / (MaxHistory - 1);
            int startIdx = MaxHistory - _ramHistory.Count;

            for (int i = 0; i < _ramHistory.Count; i++)
            {
                double val = _ramHistory[i];
                double x = (startIdx + i) * step;
                double norm = Math.Min(1.0, Math.Max(0.0, val / maxRam));
                double y = h - (norm * (h - 10));

                points.Add(new Point(x, y));
                fillPoints.Add(new Point(x, y));
            }

            fillPoints.Add(new Point((startIdx + _ramHistory.Count - 1) * step, h));

            Polygon fillPoly = new Polygon
            {
                Points = fillPoints,
                Fill = new LinearGradientBrush(
                    Color.FromArgb(90, 56, 189, 248),
                    Color.FromArgb(5, 56, 189, 248),
                    new Point(0, 0),
                    new Point(0, 1)
                )
            };
            _chartCanvas.Children.Add(fillPoly);

            Polyline line = new Polyline
            {
                Points = points,
                Stroke = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                StrokeThickness = 2.5
            };
            _chartCanvas.Children.Add(line);
        }

        private void OnPlayerSelected(object sender, SelectionChangedEventArgs e)
        {
            string p = _lstPlayers.SelectedItem as string;
            if (!string.IsNullOrEmpty(p))
            {
                _txtSelectedPlayer.Text = "Action rapide pour " + p + " :";
                _txtSelectedPlayer.Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248));
            }
            else
            {
                _txtSelectedPlayer.Text = "Sélectionnez un joueur ci-dessus pour agir :";
                _txtSelectedPlayer.Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184));
            }
        }

        private void PlayerCmd(string format)
        {
            string player = _lstPlayers.SelectedItem as string;
            if (string.IsNullOrEmpty(player))
            {
                MessageBox.Show("Veuillez d'abord sélectionner un joueur dans la liste.", "Aucun joueur sélectionné", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            string cmd = string.Format(format, player);
            ExecuteRconCommand(cmd);
        }

        private void ActionBroadcast()
        {
            string msg = _txtBroadcastInput.Text.Trim();
            if (!string.IsNullOrEmpty(msg))
            {
                ExecuteRconCommand("say [ANNONCE] " + msg);
                _txtBroadcastInput.Text = "";
            }
        }

        private void ActionSendCustomCommand()
        {
            string cmd = _txtCommandInput.Text.Trim();
            if (!string.IsNullOrEmpty(cmd))
            {
                if (cmd.StartsWith("/")) cmd = cmd.Substring(1).Trim();
                _commandHistory.Add(cmd);
                _historyIndex = -1;
                _suggestionsPopup.IsOpen = false;

                ExecuteRconCommand(cmd);

                _isUpdatingText = true;
                _txtCommandInput.Text = "";
                _isUpdatingText = false;
            }
        }

        private void ExecuteRconCommand(string command)
        {
            LogConsole("> " + command);
            try
            {
                if (_rcon.Connect("127.0.0.1", _rconPort, _rconPassword))
                {
                    string resp = _rcon.SendCommand(command);
                    if (!string.IsNullOrEmpty(resp))
                    {
                        LogConsole(resp);
                    }
                    else
                    {
                        LogConsole("OK (Commande exécutée)");
                    }
                }
                else
                {
                    LogConsole("ERREUR : Impossible de joindre le RCON (serveur hors ligne ?)");
                }
            }
            catch (Exception ex)
            {
                LogConsole("ERREUR RCON : " + ex.Message);
            }
        }

        private void LogConsole(string msg)
        {
            string line = string.Format("[{0:HH:mm:ss}] {1}", DateTime.Now, msg);
            _txtConsoleOutput.AppendText(line + Environment.NewLine);
            _txtConsoleOutput.ScrollToEnd();
        }

        private void ActionStart()
        {
            LogConsole("Démarrage du serveur Minecraft...");
            Process.Start("wscript.exe", "//B \"" + System.IO.Path.Combine(_serverDir, @"scripts\start.vbs") + "\"");
        }

        private void ActionStop()
        {
            if (MessageBox.Show("Voulez-vous vraiment arrêter le serveur Minecraft ?", "Confirmation", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
            {
                LogConsole("Arrêt propre du serveur en cours...");
                Process.Start("wscript.exe", "//B \"" + System.IO.Path.Combine(_serverDir, @"scripts\kill.vbs") + "\"");
            }
        }

        private void ActionRestart()
        {
            if (MessageBox.Show("Voulez-vous vraiment redémarrer le serveur Minecraft ?", "Confirmation", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
            {
                LogConsole("Arrêt et redémarrage du serveur en cours...");
                Process killProc = Process.Start("wscript.exe", "//B \"" + System.IO.Path.Combine(_serverDir, @"scripts\kill.vbs") + "\"");
                if (killProc != null)
                {
                    System.Threading.Tasks.Task.Run(() =>
                    {
                        killProc.WaitForExit(30000);
                        System.Threading.Thread.Sleep(2000);
                        Process.Start("wscript.exe", "//B \"" + System.IO.Path.Combine(_serverDir, @"scripts\start.vbs") + "\"");
                        Dispatcher.Invoke(() => LogConsole("Signal de démarrage envoyé."));
                    });
                }
            }
        }

        private void ActionBackup()
        {
            LogConsole("Lancement de la sauvegarde manuelle...");
            Process.Start("wscript.exe", "//B \"" + System.IO.Path.Combine(_serverDir, @"scripts\update-backup.vbs") + "\" /silent");
        }
    }
}
