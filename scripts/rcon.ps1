param(
    [string]$Command = "data get entity Vibrions"
)

$client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 25575)
$stream = $client.GetStream()

function Send-Packet($id, $type, $payload) {
    $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $len = 4 + 4 + $payloadBytes.Length + 2
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([int32]$len)
    $bw.Write([int32]$id)
    $bw.Write([int32]$type)
    $bw.Write($payloadBytes)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bytes = $ms.ToArray()
    $stream.Write($bytes, 0, $bytes.Length)
}

function Receive-Packet {
    $br = New-Object System.IO.BinaryReader($stream)
    $len = $br.ReadInt32()
    $id = $br.ReadInt32()
    $type = $br.ReadInt32()
    $payloadBytes = $br.ReadBytes($len - 10)
    $pad = $br.ReadBytes(2)
    $payload = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
    return @{ Id = $id; Type = $type; Payload = $payload }
}

try {
    # Auth (Type 3)
    Send-Packet 1 3 "ton_mot_de_passe_rcon"
    $authResp = Receive-Packet
    if ($authResp.Id -lt 0) {
        throw "RCON Auth failed"
    }

    # Command (Type 2)
    Send-Packet 2 2 $Command
    $cmdResp = Receive-Packet
    Write-Output $cmdResp.Payload
}
finally {
    $client.Close()
}
