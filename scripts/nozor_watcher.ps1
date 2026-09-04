# nozor_watcher.ps1
# Daemon qui surveille le chat Minecraft en temps reel
# Detecte les messages "dis nozor" et met les requetes en queue
# Usage : powershell -ExecutionPolicy Bypass -File scripts\nozor_watcher.ps1

$serverDir = "C:\WindowsServices"
$logFile = "$serverDir\logs\latest.log"
$queueFile = "$serverDir\scripts\nozor_queue.json"
$propsFile = "$serverDir\server.properties"

# --- Configuration RCON ---
function Get-ServerProperty([string]$name, [string]$default) {
    if (-not (Test-Path $propsFile)) { return $default }
    foreach ($line in (Get-Content $propsFile)) {
        $line = $line.Trim()
        if ($line -match "^$name=(.*)$") { return $Matches[1].Trim() }
    }
    return $default
}

$rconHost = "127.0.0.1"
$rconPort = [int](Get-ServerProperty "rcon.port" "25575")
$rconPassword = Get-ServerProperty "rcon.password" "ton_mot_de_passe_rcon"

# --- Fonctions RCON ---
function Send-Rcon([string]$command) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($rconHost, $rconPort)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000

        function Send-Pkt([int]$id, [int]$t, [string]$b) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($b)
            $ms = New-Object System.IO.MemoryStream
            $bw = New-Object System.IO.BinaryWriter($ms)
            $bw.Write([int32](10 + $bytes.Length))
            $bw.Write([int32]$id)
            $bw.Write([int32]$t)
            if ($bytes.Length -gt 0) { $bw.Write($bytes) }
            $bw.Write([byte]0); $bw.Write([byte]0)
            $pkt = $ms.ToArray()
            $stream.Write($pkt, 0, $pkt.Length)
            $stream.Flush()
        }

        function Read-Pkt() {
            $lenBytes = New-Object byte[] 4
            $read = 0
            while ($read -lt 4) {
                $r = $stream.Read($lenBytes, $read, 4 - $read)
                if ($r -le 0) { throw "Socket closed" }
                $read += $r
            }
            $len = [System.BitConverter]::ToInt32($lenBytes, 0)
            $data = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) {
                $r = $stream.Read($data, $read, $len - $read)
                if ($r -le 0) { throw "Socket closed" }
                $read += $r
            }
            $body = ""
            if ($len -gt 10) {
                $body = [System.Text.Encoding]::UTF8.GetString($data, 8, $len - 10)
            }
            return $body
        }

        # Auth
        Send-Pkt 1 3 $rconPassword
        $auth = Read-Pkt
        if ($auth -eq $null) { throw "Auth failed" }

        # Commande
        Send-Pkt 2 2 $command
        $resp = Read-Pkt

        $stream.Close()
        $client.Close()
        return $resp
    } catch {
        Write-Host "[RCON ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# --- Fonctions de position/rotation ---
function Get-PlayerPosition([string]$player) {
    $result = Send-Rcon "data get entity $player Pos"
    if ($result -and $result -match "\[(-?[\d.]+)d,\s*(-?[\d.]+)d,\s*(-?[\d.]+)d\]") {
        return @([double]$Matches[1], [double]$Matches[2], [double]$Matches[3])
    }
    return $null
}

function Get-PlayerRotation([string]$player) {
    $result = Send-Rcon "data get entity $player Rotation"
    if ($result -and $result -match "\[(-?[\d.]+)f,\s*(-?[\d.]+)f\]") {
        return @([double]$Matches[1], [double]$Matches[2])
    }
    return $null
}

# --- Gestion de la queue ---
function Add-ToQueue([string]$player, [string]$instruction, $position, $rotation) {
    # Lire la queue existante
    $queue = @{ requests = @() }
    if (Test-Path $queueFile) {
        try {
            $content = Get-Content $queueFile -Raw -ErrorAction Stop
            if ($content -and $content.Trim() -ne "") {
                $queue = $content | ConvertFrom-Json
                # S'assurer que requests est un tableau mutable
                if ($queue.requests -eq $null) {
                    $queue = @{ requests = @() }
                } else {
                    $queue.requests = @($queue.requests)
                }
            }
        } catch {
            $queue = @{ requests = @() }
        }
    }

    # Creer la nouvelle requete
    $request = @{
        id          = [guid]::NewGuid().ToString()
        player      = $player
        instruction = $instruction
        position    = $position
        rotation    = $rotation
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $queue.requests += $request

    # Ecrire le fichier queue
    $queue | ConvertTo-Json -Depth 5 | Out-File -FilePath $queueFile -Encoding UTF8 -Force

    Write-Host "[QUEUE] Requete ajoutee: $player -> '$instruction'" -ForegroundColor Cyan
    return $request.id
}

# --- Notification au joueur ---
function Send-PlayerNotification([string]$player, [string]$message, [string]$color = "gold") {
    $jsonMsg = "{`"text`":`"$message`",`"color`":`"$color`",`"italic`":true}"
    Send-Rcon "tellraw $player $jsonMsg" | Out-Null
}

# --- Pattern de detection ---
# Formats supportes :
#   [Not Secure] [Joueur] dis nozor ...
#   <Joueur> dis nozor ...
$patternNotSecure = '^\[\d{2}:\d{2}:\d{2}\] \[Server thread/INFO\]: \[Not Secure\] \[(\w+)\] dis nozor (.+)$'
$patternClassic   = '^\[\d{2}:\d{2}:\d{2}\] \[Server thread/INFO\]: <(\w+)> dis nozor (.+)$'

# --- Boucle principale ---
Write-Host "========================================" -ForegroundColor Green
Write-Host "  NOZOR WATCHER - Demarrage" -ForegroundColor Green
Write-Host "  Surveillance de: $logFile" -ForegroundColor Green
Write-Host "  Queue: $queueFile" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Initialiser la queue si elle n'existe pas
if (-not (Test-Path $queueFile)) {
    @{ requests = @() } | ConvertTo-Json | Out-File -FilePath $queueFile -Encoding UTF8
    Write-Host "[INIT] Queue initialisee" -ForegroundColor Yellow
}

# Surveiller le fichier de log en temps reel
# On lit avec un FileStream en mode partage pour ne pas bloquer le serveur MC
Write-Host "[WATCH] Surveillance en cours... (Ctrl+C pour arreter)" -ForegroundColor Yellow
Write-Host ""

# Position de lecture du fichier journal
$lastPos = 0

while ($true) {
    try {
        if (-not (Test-Path $logFile)) {
            Start-Sleep -Seconds 2
            continue
        }

        # Détecter rotation ou recréation du fichier de log
        $fi = New-Object System.IO.FileInfo($logFile)
        if ($fi.Length -lt $lastPos) {
            Write-Host "[LOG ROTATION] Fichier journal recréé ou tronqué ($($fi.Length) < $lastPos). Reprise à 0." -ForegroundColor Yellow
            $lastPos = 0
        }

        $fs = [System.IO.File]::Open($logFile, "Open", "Read", "ReadWrite")
        $fs.Position = $lastPos
        $sr = New-Object System.IO.StreamReader($fs)

        while (($line = $sr.ReadLine()) -ne $null) {
            # Tester les deux patterns
            $matched = $false
            $player = ""
            $instruction = ""

            if ($line -match $patternNotSecure) {
                $matched = $true
                $player = $Matches[1]
                $instruction = $Matches[2].Trim()
            } elseif ($line -match $patternClassic) {
                $matched = $true
                $player = $Matches[1]
                $instruction = $Matches[2].Trim()
            }

            if ($matched -and $instruction -ne "") {
                Write-Host "[DETECT] $player dit: 'dis nozor $instruction'" -ForegroundColor Magenta

                # Recuperer la position et la rotation du joueur
                $pos = Get-PlayerPosition $player
                $rot = Get-PlayerRotation $player

                if ($pos) {
                    Write-Host "[POS] $player est en ($($pos[0]), $($pos[1]), $($pos[2]))" -ForegroundColor DarkCyan
                } else {
                    Write-Host "[POS] Impossible de recuperer la position de $player" -ForegroundColor Red
                    $pos = @(0, 64, 0)
                }

                if ($rot) {
                    Write-Host "[ROT] $player regarde vers ($($rot[0]), $($rot[1]))" -ForegroundColor DarkCyan
                } else {
                    $rot = @(0, 0)
                }

                # Ajouter a la queue
                $reqId = Add-ToQueue $player $instruction $pos $rot

                # Notifier le joueur
                Send-PlayerNotification $player "Nozor a recu ta demande... Laisse-moi reflechir." "gold"
            }
        }

        $lastPos = $fs.Position
        $sr.Close()
        $fs.Close()

    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 500
}
