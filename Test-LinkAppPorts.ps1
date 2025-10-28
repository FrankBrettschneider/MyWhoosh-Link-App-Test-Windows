<#
Test-LinkAppPorts.ps1
Checks local and remote port availability for the Link App (PowerShell 5+ / 7+)
#>

# === Configuration ===
$remoteHost = Read-Host "Enter the IP address or hostname of the remote device (e.g. 192.168.1.50)"
$tcpPortsLocal = @(21587, 21588)
$tcpPortsRemote = @(443, 3023, 3025)
$udpPortsRemote = @(3022, 3024)
$results = @()

Write-Host "====================================="
Write-Host "🔍 Starting Link App port diagnostics..."
Write-Host "====================================="

# === 1. Local listening ports ===
Write-Host "`n[1] Checking local listening ports..." -ForegroundColor Cyan
foreach ($port in $tcpPortsLocal) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $pid = $conn.OwningProcess
        $procName = (Get-Process -Id $pid -ErrorAction SilentlyContinue).ProcessName
        if (-not $procName) { $procName = "Unknown" }

        Write-Host ("✅ Port {0} is listening locally (Process: {1}, PID: {2})" -f $port, $procName, $pid) -ForegroundColor Green
        $results += [pscustomobject]@{
            Type      = 'Local'
            Protocol  = 'TCP'
            Port      = $port
            Status    = 'Listening'
            Process   = "$procName (PID $pid)"
        }
    } else {
        Write-Host "❌ Port $port is NOT listening locally" -ForegroundColor Red
        $results += [pscustomobject]@{
            Type      = 'Local'
            Protocol  = 'TCP'
            Port      = $port
            Status    = 'Not Listening'
            Process   = '—'
        }
    }
}

# === 2. Remote TCP connectivity ===
Write-Host "`n[2] Testing remote TCP connectivity ($remoteHost)..." -ForegroundColor Cyan
foreach ($port in $tcpPortsRemote) {
    $result = Test-NetConnection -ComputerName $remoteHost -Port $port -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host "✅ TCP port $port reachable" -ForegroundColor Green
        $results += [pscustomobject]@{
            Type      = 'Remote'
            Protocol  = 'TCP'
            Port      = $port
            Status    = 'Reachable'
            Process   = '—'
        }
    } else {
        Write-Host "❌ TCP port $port NOT reachable" -ForegroundColor Red
        $results += [pscustomobject]@{
            Type      = 'Remote'
            Protocol  = 'TCP'
            Port      = $port
            Status    = 'Not Reachable'
            Process   = '—'
        }
    }
}

# === 3. Remote UDP connectivity ===
Write-Host "`n[3] Testing remote UDP connectivity ($remoteHost)..." -ForegroundColor Cyan
$udpParamSupported = (Get-Command Test-NetConnection).Parameters.ContainsKey('Udp')

foreach ($port in $udpPortsRemote) {
    if ($udpParamSupported) {
        $result = Test-NetConnection -ComputerName $remoteHost -Port $port -Udp -WarningAction SilentlyContinue
        if ($result.UdpTestSucceeded) {
            Write-Host "✅ UDP port $port reachable (packet sent successfully)" -ForegroundColor Green
            $status = 'Reachable'
        } else {
            Write-Host "⚠️ Could not confirm UDP port $port (UDP is connectionless)" -ForegroundColor Yellow
            $status = 'Unconfirmed'
        }
    } else {
        try {
            $udpClient = New-Object System.Net.Sockets.UdpClient
            $udpClient.Connect($remoteHost, $port)
            $data = [Text.Encoding]::ASCII.GetBytes("test")
            [void]$udpClient.Send($data, $data.Length)
            $udpClient.Close()
            Write-Host "✅ UDP packet sent to port $port (cannot confirm response)" -ForegroundColor Green
            $status = 'Sent (Unconfirmed)'
        } catch {
            Write-Host "❌ Failed to send UDP packet to port $port" -ForegroundColor Red
            $status = 'Send Failed'
        }
    }

    $results += [pscustomobject]@{
        Type      = 'Remote'
        Protocol  = 'UDP'
        Port      = $port
        Status    = $status
        Process   = '—'
    }
}

# === 4. Firewall rules ===
Write-Host "`n[4] Checking active inbound firewall rules..." -ForegroundColor Cyan
$fwRules = Get-NetFirewallRule | Where-Object { $_.Enabled -eq "True" -and $_.Direction -eq "Inbound" }
Write-Host "ℹ️ $($fwRules.Count) active inbound firewall rules found."

# === 5. Summary ===
Write-Host "`n[5] Summary of results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

# === 6. Save report ===
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
# $outputFile = "$env:USERPROFILE\Desktop\LinkApp_PortCheck_$timestamp.txt"
$outputFile = "LinkApp_PortCheck_$timestamp.txt"
$results | Out-File -FilePath $outputFile -Encoding utf8

Write-Host "`n📄 Results saved to: $outputFile" -ForegroundColor Gray
Write-Host "`n✅ Port diagnostics completed."
Write-Host "====================================="
