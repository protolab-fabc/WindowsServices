# death-stats-log.ps1
# Interroge le serveur via RCON pour sauvegarder les scores de morts dans un fichier CSV
# Usage : powershell -ExecutionPolicy Bypass -File scripts\death-stats-log.ps1

$serverDir = "C:\WindowsServices"
$propsFile = "$serverDir\server.properties"
$logFile = "$serverDir\death-stats.csv"

# Lecture des parametres RCON depuis server.properties
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

function Send-Rcon([string]$command) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($rconHost, $rconPort)
        $stream = $client.GetStream()

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
        return $null
    }
}

# Creer le fichier CSV avec en-tete s'il n'existe pas
if (-not (Test-Path $logFile)) {
    "Date,Joueur,Morts" | Out-File -FilePath $logFile -Encoding UTF8
}

# Recuperer la liste des scores
$result = Send-Rcon "scoreboard players list"
if (-not $result) {
    Write-Host "Impossible de contacter le serveur RCON."
    exit 1
}

# Recuperer les scores individuels - interroger chaque joueur connu
$playerList = Send-Rcon "list"
if ($playerList -and $playerList -match ":\s*(.+)$") {
    $players = $Matches[1] -split ",\s*" | Where-Object { $_ -ne "" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    foreach ($player in $players) {
        $player = $player.Trim()
        if ($player -eq "") { continue }
        
        $scoreResult = Send-Rcon "scoreboard players get $player deaths"
        $deaths = 0
        if ($scoreResult -match "(\d+)") {
            $deaths = [int]$Matches[1]
        }
        
        "$timestamp,$player,$deaths" | Out-File -FilePath $logFile -Append -Encoding UTF8
        Write-Host "  $player : $deaths mort(s)"
    }
    Write-Host "Stats sauvegardees dans $logFile"
} else {
    Write-Host "Aucun joueur connecte."
}
