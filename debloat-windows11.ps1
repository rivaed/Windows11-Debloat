# Debloat Windows 11
# update 21-02-2026

# 1. Forçar execução como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Solicitando privilégios de Administrador..."
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 2. Criar Ponto de Restauração (Opcional, mas recomendado)
Write-Host "Criando ponto de restauração do sistema..." -ForegroundColor Cyan
try {
    Checkpoint-Computer -Description "Antes do Debloat W11" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
    Write-Host "Ponto de restauração criado com sucesso." -ForegroundColor Green
} catch {
    Write-Warning "Não foi possível criar o ponto de restauração (Pode estar desativado no sistema)."
}

# 3. Lista de apps a remover
$apps = @(
    "Microsoft.3DBuilder", "Microsoft.BingNews", "Microsoft.GetHelp",
    "Microsoft.Getstarted", "Microsoft.Messaging", "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.NetworkSpeedTest", "Microsoft.News", "Microsoft.OneConnect",
    "Microsoft.People", "Microsoft.Print3D", "Microsoft.SkypeApp",
    "Microsoft.StorePurchaseApp", "Microsoft.Todos", "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.YourPhone", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo"
)

# 4. Remoção de apps
Write-Host "`nIniciando a remoção de bloatware..." -ForegroundColor Cyan
foreach ($app in $apps) {
    try {
        # Usando -ErrorAction Stop para que o Catch funcione se algo falhar
        Get-AppxPackage -AllUsers "*$app*" | Remove-AppxPackage -AllUsers -ErrorAction Stop
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$app*" | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
        Write-Host "[OK] Removido ou já inexistente: $app" -ForegroundColor Green
    } catch {
        Write-Host "[X] Falha/Aviso ao remover ${app}: $_" -ForegroundColor Yellow
    }
}

# 5. Desativar serviços de telemetria
Write-Host "`nDesativando serviços de telemetria..." -ForegroundColor Cyan
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($svc in $telemetryServices) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
        Write-Host "[OK] Serviço desativado: $svc" -ForegroundColor Green
    } catch {
        Write-Host "[X] Erro ao desativar o serviço ${svc} (Pode já estar desativado)" -ForegroundColor Yellow
    }
}

# 6. Desativar efeitos visuais
Write-Host "`nDesativando efeitos visuais para melhorar performance..." -ForegroundColor Cyan
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction Stop
    Write-Host "[OK] Efeitos visuais ajustados." -ForegroundColor Green
} catch {
    Write-Host "[X] Falha ao ajustar efeitos visuais." -ForegroundColor Yellow
}

# 7. Limpeza de arquivos temporários
Write-Host "`nLimpando arquivos temporários..." -ForegroundColor Cyan
try {
    # Arquivos em uso vão gerar erro, SilentlyContinue resolve isso sem poluir o console
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Limpeza de temporários concluída." -ForegroundColor Green
} catch {
    Write-Host "[X] Erro crítico durante a limpeza de arquivos temporários." -ForegroundColor Yellow
}

Write-Host "`n✅ Otimização concluída! Reinicie o PC para aplicar todas as mudanças de interface." -ForegroundColor Cyan
Pause
