# Debloat Windows 11 - Script para remover bloatware e otimizar o sistema
# Execute este script como Administrador

# Lista de apps a remover
$apps = @(
    "Microsoft.3DBuilder",
    "Microsoft.BingNews",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.Messaging",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.NetworkSpeedTest",
    "Microsoft.News",
    "Microsoft.OneConnect",
    "Microsoft.People",
    "Microsoft.Print3D",
    "Microsoft.SkypeApp",
    "Microsoft.StorePurchaseApp",
    "Microsoft.Todos",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo"
)

# Remoção de apps
foreach ($app in $apps) {
    try {
        Get-AppxPackage -AllUsers $app | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "$app" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        Write-Host "Removido: $app"
    } catch {
        Write-Warning "Falha ao remover ${app}: $_"
    }
}

# Desativar serviços de telemetria
Write-Host "Desativando serviços de telemetria..."
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($svc in $telemetryServices) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled
        Write-Host "Desativado: $svc"
    } catch {
        Write-Warning "Erro ao desativar o serviço ${svc}: $_"
    }
}

# Desativar efeitos visuais
Write-Host "Desativando efeitos visuais para melhorar performance..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2

# Limpeza de arquivos temporários
Write-Host "Limpando arquivos temporários..."
try {
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Arquivos temporários removidos."
} catch {
    Write-Warning "Erro durante a limpeza de arquivos temporários: $_"
}

Write-Host "`n✅ Otimização concluída! Reinicie o PC para aplicar todas as mudanças."
