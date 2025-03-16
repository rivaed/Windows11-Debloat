# Windows 11 Debloat Script
# Desenvolvido para otimizar e remover bloatware do Windows 11
# Execute este script como Administrador no PowerShell

# Remover aplicativos pré-instalados desnecessários
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

foreach ($app in $apps) {
    Get-AppxPackage -AllUsers $app | Remove-AppxPackage
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "$app" | Remove-AppxProvisionedPackage -Online
}

# Desativar telemetria
Write-Host "Desativando serviços de telemetria..."
Stop-Service "DiagTrack" -Force
Set-Service "DiagTrack" -StartupType Disabled
Stop-Service "dmwappushservice" -Force
Set-Service "dmwappushservice" -StartupType Disabled

# Ajustar configurações para melhorar desempenho
Write-Host "Desativando efeitos visuais para melhorar performance..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2

# Limpeza de arquivos temporários
Write-Host "Limpando arquivos temporários..."
Remove-Item -Path "$env:TEMP\*" -Force -Recurse

Write-Host "Otimização concluída! Reinicie o PC para aplicar todas as mudanças."
