
# Windows 11 Debloat Script
# Remoção de bloatware, desativação de telemetria, ajuste de efeitos visuais e limpeza de arquivos temporários.
# Execute este script como Administrador no PowerShell.

# Função para checar privilégios de administrador
function Test-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "Este script precisa ser executado como Administrador."
        exit 1
    }
}

# Função para remover pacotes de aplicativos
function Remove-AppPackages {
    param(
        [string[]]$Apps
    )
    foreach ($app in $Apps) {
        try {
            Write-Host "Removendo pacote: $app"
            # Remove pacote para usuários existentes
            Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
            # Remove pacote provisionado para novas instalações
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $app } | ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Falha ao remover $app: $_"
        }
    }
}

# Função para desativar serviços de telemetria
function Disable-Telemetry {
    $services = @("DiagTrack", "dmwappushservice")
    foreach ($svc in $services) {
        try {
            if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
                Write-Host "Desativando serviço: $svc"
                Stop-Service $svc -Force -ErrorAction SilentlyContinue
                Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            }
            else {
                Write-Host "Serviço $svc não encontrado."
            }
        }
        catch {
            Write-Warning "Erro ao desativar o serviço $svc: $_"
        }
    }
}

# Função para ajustar os efeitos visuais para melhor performance
function Adjust-VisualEffects {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    try {
        if (-not (Test-Path $regPath)) {
            Write-Host "Caminho de registro inexistente. Criando $regPath"
            New-Item -Path $regPath -Force | Out-Null
        }
        Write-Host "Ajustando efeitos visuais para melhor desempenho..."
        Set-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Erro ao ajustar efeitos visuais: $_"
    }
}

# Função para limpar arquivos temporários
function Clean-TempFiles {
    try {
        Write-Host "Limpando arquivos temporários..."
        Remove-Item -Path "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Erro ao limpar arquivos temporários: $_"
    }
}

# Execução principal do script
Test-Admin

# Lista de aplicativos a serem removidos
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

Remove-AppPackages -Apps $apps
Disable-Telemetry
Adjust-VisualEffects
Clean-TempFiles

Write-Host "Otimização concluída! Reinicie o PC para aplicar todas as mudanças."
