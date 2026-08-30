#Requires -Version 5.1
<#
.SYNOPSIS
    Debloat Windows 11 — remocao de bloatware, telemetria e ajustes de desempenho.

.DESCRIPTION
    Remove aplicativos pre-instalados (Appx), desativa telemetria (servicos, registro e
    tarefas agendadas), aplica ajustes de desempenho e limpa arquivos temporarios do
    Windows 11 (23H2/24H2/25H2). Pode rodar em modo interativo (menu por categorias)
    ou nao interativo (perfis), com simulacao (dry-run) e log em arquivo.

    Alvo: Windows PowerShell 5.1 (o padrao do Windows 11). Zero dependencias.

.PARAMETER Perfil
    Perfil de itens a aplicar: Minimo (so itens seguros), Completo (seguros + opcionais,
    padrao) ou Agressivo (tudo, incluindo itens que quebram funcionalidades — leia o README).
    No modo interativo define apenas a pre-selecao inicial do menu.

.PARAMETER NaoInterativo
    Executa direto o perfil escolhido, sem menu e sem pausas. Para automacao/RMM
    (a sessao ja deve estar elevada; nao ha prompt de UAC nesse modo).

.PARAMETER Simular
    Dry-run: mostra tudo o que seria feito sem alterar nada no sistema.

.PARAMETER SemPontoRestauracao
    Nao cria ponto de restauracao antes de executar.

.PARAMETER CaminhoLog
    Caminho do arquivo de log. Padrao: %ProgramData%\Windows11-Debloat\logs\debloat_<data>.log

.PARAMETER CaminhoRelatorioJson
    Exporta um relatorio estruturado (item a item, com status) em JSON para o caminho
    informado — util para anexar a um laudo de atendimento ou alimentar um RMM/dashboard.

.EXAMPLE
    .\debloat-windows11.ps1
    Abre o menu interativo com o perfil Completo pre-selecionado.

.EXAMPLE
    .\debloat-windows11.ps1 -NaoInterativo -Perfil Minimo -Simular
    Simula (sem alterar nada) o que o perfil Minimo faria, sem menu.

.EXAMPLE
    .\debloat-windows11.ps1 -NaoInterativo -Perfil Completo -CaminhoRelatorioJson C:\Laudos\debloat.json
    Executa o perfil Completo e exporta o relatorio item a item em JSON.

.NOTES
    Reversao: veja a secao "Como reverter" no README.
    Feature updates do Windows (ex.: 23H2 -> 24H2) podem reinstalar apps — reexecute apos upgrades.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de console interativo: cores e menu fazem parte da UX; transcript captura tudo.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Dry-run proprio via -Simular, aplicado num unico ponto (Invoke-DebloatItem).')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Write-Log so existe no PowerShell 6.1+; o alvo deste script e o Windows PowerShell 5.1, onde nao ha colisao.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Minimo', 'Completo', 'Agressivo')]
    [string]$Perfil = 'Completo',

    [switch]$NaoInterativo,

    [switch]$Simular,

    [switch]$SemPontoRestauracao,

    [ValidateNotNullOrEmpty()]
    [string]$CaminhoLog,

    [ValidateNotNullOrEmpty()]
    [string]$CaminhoRelatorioJson
)

$script:VERSAO = '2.1.0'
$script:Simular = [bool]$Simular -or [bool]$WhatIfPreference
$script:TranscriptAtivo = $false
$script:ArquivoLog = $null

#region Utilitarios -----------------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Mensagem,
        [ValidateSet('Info', 'Ok', 'Aviso', 'Erro', 'Simulacao', 'Titulo')]
        [string]$Nivel = 'Info'
    )
    switch ($Nivel) {
        'Ok'        { Write-Host "[OK] $Mensagem" -ForegroundColor Green }
        'Aviso'     { Write-Host "[!] $Mensagem" -ForegroundColor Yellow }
        'Erro'      { Write-Host "[X] $Mensagem" -ForegroundColor Red }
        'Simulacao' { Write-Host "[SIMULACAO] $Mensagem" -ForegroundColor Cyan }
        'Titulo'    { Write-Host "`n$Mensagem" -ForegroundColor Cyan }
        default     { Write-Host $Mensagem }
    }
}

function Test-Admin {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identidade).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    # Relanca em powershell.exe 5.1 quando falta elevacao ou quando esta no pwsh 7+
    # (o modulo Appx nao funciona de forma confiavel no PowerShell Core).
    param([Parameter(Mandatory)][System.Collections.IDictionary]$ParametrosOriginais)

    $precisaElevar = -not (Test-Admin)
    $precisaEngine = $PSVersionTable.PSEdition -eq 'Core'
    if (-not $precisaElevar -and -not $precisaEngine) { return }

    if ($NaoInterativo -and $precisaElevar) {
        Write-Log 'Sessao nao interativa sem privilegios de administrador. Execute ja elevado (RMM/SYSTEM/terminal admin).' 'Erro'
        exit 2
    }

    if ($precisaEngine -and -not $precisaElevar) {
        Write-Log 'Detectado PowerShell 7+. Reabrindo no Windows PowerShell 5.1 (necessario para o modulo Appx)...' 'Aviso'
    }
    else {
        Write-Log 'Solicitando privilegios de Administrador...' 'Aviso'
    }

    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    foreach ($p in $ParametrosOriginais.GetEnumerator()) {
        if ($p.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($p.Value) { $argumentos += ('-{0}' -f $p.Key) }
        }
        else {
            $argumentos += @(('-{0}' -f $p.Key), ('"{0}"' -f $p.Value))
        }
    }

    try {
        if ($precisaElevar) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ($argumentos -join ' ') -Verb RunAs -ErrorAction Stop
        }
        else {
            # Ja elevado: o processo filho herda o token elevado.
            Start-Process -FilePath 'powershell.exe' -ArgumentList ($argumentos -join ' ') -ErrorAction Stop
        }
    }
    catch {
        Write-Log ('Elevacao cancelada ou falhou: {0}' -f $_.Exception.Message) 'Erro'
        exit 1
    }
    exit 0
}

function Assert-Windows11 {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($os.ProductType -eq 1 -and $build -ge 22000) { return }

    Write-Log ('Sistema detectado: {0} (build {1}) — este script foi feito para Windows 11 (build 22000+).' -f $os.Caption, $build) 'Aviso'
    if ($script:Simular) {
        Write-Log 'Prosseguindo mesmo assim por estar em modo simulacao.' 'Aviso'
        return
    }
    if ($NaoInterativo) {
        Write-Log 'Abortando: modo nao interativo em sistema nao suportado.' 'Erro'
        exit 3
    }
    $resposta = Read-Host 'Continuar mesmo assim? (S/N)'
    if ($resposta -notmatch '^[sS]') { exit 3 }
}

function Start-Logging {
    $pasta = Join-Path $env:ProgramData 'Windows11-Debloat\logs'
    if ($CaminhoLog) {
        $script:ArquivoLog = $CaminhoLog
    }
    else {
        $script:ArquivoLog = Join-Path $pasta ('debloat_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    try {
        $pastaLog = Split-Path -Path $script:ArquivoLog -Parent
        if ($pastaLog -and -not (Test-Path $pastaLog)) {
            New-Item -Path $pastaLog -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Start-Transcript -Path $script:ArquivoLog -ErrorAction Stop | Out-Null
        $script:TranscriptAtivo = $true
    }
    catch {
        Write-Log ('Nao foi possivel iniciar o log em arquivo: {0}' -f $_.Exception.Message) 'Aviso'
    }
}

function Test-UsuarioDivergente {
    # Cenario classico de manutencao: usuario padrao logado + credencial de admin no UAC.
    # Nesse caso HKCU e %TEMP% deste processo pertencem ao ADMIN, nao ao usuario atendido.
    try {
        $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
            Select-Object -First 1
        if (-not $explorer) { return $false }
        $dono = (Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction Stop).User
        if ($dono -and $dono -ne $env:USERNAME) {
            Write-Log ('Atencao: a sessao interativa e do usuario "{0}", mas o script roda como "{1}".' -f $dono, $env:USERNAME) 'Aviso'
            Write-Log ('Ajustes por usuario (HKCU) e a limpeza de %TEMP% serao aplicados ao perfil de "{0}". Veja "Limitacoes" no README.' -f $env:USERNAME) 'Aviso'
            return $true
        }
    }
    catch {
        # Sem explorer.exe (sessao SYSTEM/RMM) ou sem WMI: segue sem o aviso.
        Write-Verbose ('Nao foi possivel determinar o usuario da sessao interativa: {0}' -f $_.Exception.Message)
    }
    return $false
}

function Invoke-BroadcastSettingChange {
    # Notifica o sistema (WM_SETTINGCHANGE) para aplicar ajustes de aparencia sem reiniciar.
    if (-not ('Win32.NativeMethods' -as [type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $resultado = [UIntPtr]::Zero
    # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x001A, SMTO_ABORTIFHUNG = 0x0002
    [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'WindowMetrics', 0x0002, 5000, [ref]$resultado)
    [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, $null, 0x0002, 5000, [ref]$resultado)
}

#endregion

#region Ponto de restauracao --------------------------------------------------

function New-RestorePoint {
    if ($script:Simular) {
        Write-Log 'Criaria ponto de restauracao "Antes do Debloat W11".' 'Simulacao'
        return $true
    }
    Write-Log 'Criando ponto de restauracao do sistema...' 'Titulo'

    $chaveSR = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqExistia = $false
    $freqOriginal = $null
    try {
        # Garante que a Restauracao do Sistema esta ativa na unidade do Windows.
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue

        # O Windows ignora silenciosamente a criacao se ja houve um ponto nas ultimas 24h.
        # Zeramos a frequencia temporariamente para garantir a criacao, restaurando depois.
        $prop = Get-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        if ($null -ne $prop) {
            $freqExistia = $true
            $freqOriginal = $prop.SystemRestorePointCreationFrequency
        }
        Set-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction Stop

        $antes = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        $seqAntes = 0
        if ($antes.Count -gt 0) { $seqAntes = ($antes | Select-Object -Last 1).SequenceNumber }

        Checkpoint-Computer -Description ('Antes do Debloat W11 v{0}' -f $script:VERSAO) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop

        # "Sucesso" do Checkpoint-Computer nao garante ponto criado: valida de verdade.
        $depois = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        $seqDepois = 0
        if ($depois.Count -gt 0) { $seqDepois = ($depois | Select-Object -Last 1).SequenceNumber }

        if ($seqDepois -gt $seqAntes) {
            Write-Log ('Ponto de restauracao criado e verificado (sequencia {0}).' -f $seqDepois) 'Ok'
            return $true
        }
        Write-Log 'O Windows nao criou o ponto de restauracao (Restauracao do Sistema pode estar desativada).' 'Aviso'
        return $false
    }
    catch {
        Write-Log ('Falha ao criar ponto de restauracao: {0}' -f $_.Exception.Message) 'Aviso'
        return $false
    }
    finally {
        try {
            if ($freqExistia) {
                Set-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -Value $freqOriginal -Type DWord -ErrorAction SilentlyContinue
            }
            else {
                Remove-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Verbose ('Nao foi possivel restaurar SystemRestorePointCreationFrequency: {0}' -f $_.Exception.Message)
        }
    }
}

#endregion

#region Catalogo --------------------------------------------------------------
# Cada item: Id unico, Categoria (Apps|Telemetria|Desempenho|Limpeza),
# Tipo (Appx|Servico|Registro|TarefaAgendada|LimpezaPasta|Especial),
# Nivel (Seguro|Opcional|Agressivo) e o alvo tecnico.
# Perfis: Minimo = Seguro | Completo = Seguro+Opcional | Agressivo = tudo.

$script:Catalogo = @(
    # --- Apps (Seguro) ---
    [pscustomobject]@{ Id = 'bing-news';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.BingNews';                    Descricao = 'Noticias (Bing News)';            Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'bing-weather';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.BingWeather';                 Descricao = 'Clima (Bing Weather)';            Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'bing-search';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.BingSearch';                  Descricao = 'Bing Search (24H2)';              Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'get-help';       Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.GetHelp';                     Descricao = 'Obter Ajuda';                     Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'office-hub';     Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.MicrosoftOfficeHub';          Descricao = 'Microsoft 365 (Office Hub)';      Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'solitaire';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.MicrosoftSolitaireCollection'; Descricao = 'Solitaire Collection';           Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'people';         Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.People';                      Descricao = 'Pessoas';                         Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'todos';          Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Todos';                       Descricao = 'Microsoft To Do';                 Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'media-player';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.ZuneMusic';                   Descricao = 'Media Player (musica)';           Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'filmes-tv';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.ZuneVideo';                   Descricao = 'Filmes e TV';                     Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'clipchamp';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Clipchamp.Clipchamp';                   Descricao = 'Clipchamp (editor de video)';     Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'teams';          Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MSTeams';                               Descricao = 'Microsoft Teams (pessoal)';       Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'outlook-novo';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.OutlookForWindows';           Descricao = 'Novo Outlook';                    Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'power-automate'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.PowerAutomateDesktop';        Descricao = 'Power Automate';                  Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'family';         Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftCorporationII.MicrosoftFamily'; Descricao = 'Microsoft Family';               Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'linkedin';       Categoria = 'Apps'; Tipo = 'Appx'; Alvo = '7EE7776C.LinkedInforWindows';           Descricao = 'LinkedIn';                        Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'dev-home';       Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Windows.DevHome';             Descricao = 'Dev Home (descontinuado)';        Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'copilot-app';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Copilot';                     Descricao = 'Copilot (app)';                   Nivel = 'Seguro' }

    # --- Apps (Opcional) ---
    [pscustomobject]@{ Id = 'xbox-gaming';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.GamingApp';                   Descricao = 'Xbox (app atual)';                Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'xbox-overlay';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxGameOverlay';             Descricao = 'Xbox Game Overlay';               Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'xbox-gamebar';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxGamingOverlay';           Descricao = 'Xbox Game Bar';                   Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'xbox-speech';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxSpeechToTextOverlay';     Descricao = 'Xbox Speech-to-Text';             Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'phone-link';     Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.YourPhone';                   Descricao = 'Phone Link (celular vinculado)';  Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'cross-device';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftWindows.CrossDevice';          Descricao = 'Cross Device (par do Phone Link)'; Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'quick-assist';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftCorporationII.QuickAssist';    Descricao = 'Assistencia Rapida';              Nivel = 'Opcional' }

    # --- Apps (Agressivo: podem quebrar funcionalidades — leia o README) ---
    [pscustomobject]@{ Id = 'store-purchase'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.StorePurchaseApp';            Descricao = 'Compras da Microsoft Store';      Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'xbox-identity';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxIdentityProvider';        Descricao = 'Login Xbox (Minecraft/Game Pass)'; Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'xbox-tcui';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Xbox.TCUI';                   Descricao = 'Xbox TCUI (UI de conta Xbox)';    Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'widgets-pacote'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftWindows.Client.WebExperience'; Descricao = 'Widgets (remocao do pacote)';     Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'onedrive';       Categoria = 'Apps'; Tipo = 'Especial'; Alvo = 'OneDrive';                          Descricao = 'OneDrive (desinstalacao)';        Nivel = 'Agressivo' }

    # --- Telemetria / Privacidade (Seguro) ---
    [pscustomobject]@{ Id = 'diagtrack';      Categoria = 'Telemetria'; Tipo = 'Servico'; Alvo = 'DiagTrack';                    Descricao = 'Servico de telemetria (DiagTrack)'; Nivel = 'Seguro' }
    [pscustomobject]@{
        Id = 'telemetria-registro'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'Telemetria no minimo (politica de registro)'; Nivel = 'Seguro'
        Valores = @(
            # AllowTelemetry=1 (Basico/Required): 0 so e honrado em Enterprise/Education.
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'AllowTelemetry';                 Valor = 1; Tipo = 'DWord' }
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'DoNotShowFeedbackNotifications'; Valor = 1; Tipo = 'DWord' }
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'LimitDiagnosticLogCollection';   Valor = 1; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'tarefas-telemetria'; Categoria = 'Telemetria'; Tipo = 'TarefaAgendada'
        Descricao = 'Tarefas agendadas de telemetria (CEIP)'; Nivel = 'Seguro'
        Alvos = @(
            @{ Caminho = '\Microsoft\Windows\Application Experience\';                   Nome = 'Microsoft Compatibility Appraiser' }
            @{ Caminho = '\Microsoft\Windows\Application Experience\';                   Nome = 'ProgramDataUpdater' }
            @{ Caminho = '\Microsoft\Windows\Customer Experience Improvement Program\';  Nome = 'Consolidator' }
            @{ Caminho = '\Microsoft\Windows\Customer Experience Improvement Program\';  Nome = 'UsbCeip' }
            @{ Caminho = '\Microsoft\Windows\Autochk\';                                  Nome = 'Proxy' }
            @{ Caminho = '\Microsoft\Windows\DiskDiagnostic\';                           Nome = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
        )
    }
    [pscustomobject]@{
        Id = 'cdm'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'Apps promovidos/sugestoes (Content Delivery)'; Nivel = 'Seguro'
        Valores = @(
            # Sem isso, o Windows reinstala apps promovidos e o debloat "se desfaz" sozinho.
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'ContentDeliveryAllowed';           Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SilentInstalledAppsEnabled';       Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'OemPreInstalledAppsEnabled';       Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'PreInstalledAppsEnabled';          Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SystemPaneSuggestionsEnabled';     Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'RotatingLockScreenOverlayEnabled'; Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-338388Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-338389Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-353694Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-353696Enabled';  Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'advertising-id'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'ID de publicidade (anuncios personalizados)'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Nome = 'Enabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'bing-iniciar'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'Bing/sugestoes web fora do menu Iniciar'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Nome = 'DisableSearchBoxSuggestions'; Valor = 1; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'copilot-politica'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'Politica: desativar integracao Copilot'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Nome = 'TurnOffWindowsCopilot'; Valor = 1; Tipo = 'DWord' }
        )
    }

    # --- Telemetria / Privacidade (Opcional) ---
    [pscustomobject]@{ Id = 'dmwappush'; Categoria = 'Telemetria'; Tipo = 'Servico'; Alvo = 'dmwappushservice'; Descricao = 'WAP Push (quebra MDM/Intune)'; Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'recall';    Categoria = 'Telemetria'; Tipo = 'Especial'; Alvo = 'Recall';          Descricao = 'Recall (snapshots de tela, Copilot+)'; Nivel = 'Opcional' }

    # --- Desempenho ---
    [pscustomobject]@{ Id = 'efeitos-visuais'; Categoria = 'Desempenho'; Tipo = 'Especial'; Alvo = 'EfeitosVisuais'; Descricao = 'Efeitos visuais: melhor desempenho'; Nivel = 'Seguro' }
    [pscustomobject]@{
        Id = 'widgets-botao'; Categoria = 'Desempenho'; Tipo = 'Registro'
        Descricao = 'Ocultar botao de Widgets da barra'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'TaskbarDa'; Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'extensoes-arquivo'; Categoria = 'Desempenho'; Tipo = 'Registro'
        Descricao = 'Mostrar extensoes de arquivo'; Nivel = 'Opcional'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'HideFileExt'; Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'menu-contexto'; Categoria = 'Desempenho'; Tipo = 'Registro'
        Descricao = 'Menu de contexto classico (muda a UX padrao)'; Nivel = 'Agressivo'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Nome = '(default)'; Valor = ''; Tipo = 'String' }
        )
    }

    # --- Limpeza ---
    [pscustomobject]@{ Id = 'temp-usuario'; Categoria = 'Limpeza'; Tipo = 'LimpezaPasta'; Alvo = "$env:TEMP\*";            Descricao = 'Temporarios do usuario (%TEMP%)'; Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'temp-sistema'; Categoria = 'Limpeza'; Tipo = 'LimpezaPasta'; Alvo = "$env:SystemRoot\Temp\*"; Descricao = 'Temporarios do sistema (Windows\Temp)'; Nivel = 'Seguro' }
)

$script:Categorias = @('Apps', 'Telemetria', 'Desempenho', 'Limpeza')

function Get-ItensDoPerfil {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Minimo', 'Completo', 'Agressivo')]
        [string]$NomePerfil
    )
    $niveis = switch ($NomePerfil) {
        'Minimo'    { @('Seguro') }
        'Completo'  { @('Seguro', 'Opcional') }
        'Agressivo' { @('Seguro', 'Opcional', 'Agressivo') }
    }
    $script:Catalogo | Where-Object { $niveis -contains $_.Nivel }
}

#endregion

#region Executores ------------------------------------------------------------

function Get-InventarioAppx {
    Write-Log 'Inventariando pacotes instalados e provisionados (pode levar alguns segundos)...' 'Info'
    # Enumeracoes feitas UMA vez (Get-AppxProvisionedPackage e uma operacao DISM lenta).
    $script:PacotesInstalados = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $script:PacotesProvisionados = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
}

function Remove-BloatApp {
    param([Parameter(Mandatory)]$Item)

    # Matching EXATO por nome de pacote (curingas removiam pacotes alem do pretendido).
    $provisionados = @($script:PacotesProvisionados | Where-Object { $_.DisplayName -eq $Item.Alvo })
    $instalados = @($script:PacotesInstalados | Where-Object { $_.Name -eq $Item.Alvo })

    if ($provisionados.Count -eq 0 -and $instalados.Count -eq 0) {
        return @{ Status = 'NaoEncontrado'; Detalhe = ('pacote "{0}" nao esta presente' -f $Item.Alvo) }
    }

    $okProv = 0; $okInst = 0
    $falhas = @()

    # Desprovisiona PRIMEIRO: se so a remocao por usuario falhar, o app nao volta
    # para novas contas criadas na maquina.
    foreach ($pacote in $provisionados) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pacote.PackageName -ErrorAction Stop | Out-Null
            $okProv++
        }
        catch {
            $falhas += ('desprovisionar {0}: {1}' -f $pacote.PackageName, $_.Exception.Message)
        }
    }
    foreach ($pacote in $instalados) {
        try {
            Remove-AppxPackage -Package $pacote.PackageFullName -AllUsers -ErrorAction Stop
            $okInst++
        }
        catch {
            $falhas += ('remover {0}: {1}' -f $pacote.PackageFullName, $_.Exception.Message)
        }
    }

    $partes = @()
    if ($okInst -gt 0) { $partes += ('{0} instalado(s) removido(s)' -f $okInst) }
    if ($okProv -gt 0) { $partes += ('{0} provisionado(s) removido(s)' -f $okProv) }
    $resumo = $partes -join ', '

    if ($falhas.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = $resumo }
    }
    if ($okInst -gt 0 -or $okProv -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('{0}; falhas: {1}' -f $resumo, ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Disable-BloatService {
    param([Parameter(Mandatory)]$Item)

    $servico = Get-Service -Name $Item.Alvo -ErrorAction SilentlyContinue
    if (-not $servico) {
        return @{ Status = 'NaoEncontrado'; Detalhe = ('servico "{0}" nao existe neste sistema' -f $Item.Alvo) }
    }
    try {
        Stop-Service -Name $Item.Alvo -Force -ErrorAction SilentlyContinue
        Set-Service -Name $Item.Alvo -StartupType Disabled -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = 'parado e desativado' }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = ('nao foi possivel desativar (servico protegido ou acesso negado): {0}' -f $_.Exception.Message) }
    }
}

function Set-RegistryTweak {
    param([Parameter(Mandatory)]$Item)

    $ok = 0
    $falhas = @()
    foreach ($valor in $Item.Valores) {
        try {
            if (-not (Test-Path -Path $valor.Caminho)) {
                New-Item -Path $valor.Caminho -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $valor.Caminho -Name $valor.Nome -Value $valor.Valor -Type $valor.Tipo -ErrorAction Stop
            $ok++
        }
        catch {
            $falhas += ('{0}\{1}: {2}' -f $valor.Caminho, $valor.Nome, $_.Exception.Message)
        }
    }

    if ($falhas.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('{0} valor(es) de registro aplicado(s)' -f $ok) }
    }
    if ($ok -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('{0} aplicado(s); falhas: {1}' -f $ok, ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Disable-BloatScheduledTask {
    param([Parameter(Mandatory)]$Item)

    $ok = 0; $ausentes = 0
    $falhas = @()
    foreach ($alvo in $Item.Alvos) {
        $tarefa = Get-ScheduledTask -TaskPath $alvo.Caminho -TaskName $alvo.Nome -ErrorAction SilentlyContinue
        if (-not $tarefa) {
            $ausentes++
            continue
        }
        try {
            $tarefa | Disable-ScheduledTask -ErrorAction Stop | Out-Null
            $ok++
        }
        catch {
            $falhas += ('{0}{1}: {2}' -f $alvo.Caminho, $alvo.Nome, $_.Exception.Message)
        }
    }

    $resumo = ('{0} desativada(s), {1} inexistente(s) neste build' -f $ok, $ausentes)
    if ($falhas.Count -eq 0) {
        if ($ok -eq 0 -and $ausentes -gt 0) {
            return @{ Status = 'NaoEncontrado'; Detalhe = $resumo }
        }
        return @{ Status = 'Ok'; Detalhe = $resumo }
    }
    if ($ok -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('{0}; falhas: {1}' -f $resumo, ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Clear-TempPath {
    param([Parameter(Mandatory)]$Item)

    $antes = @(Get-ChildItem -Path $Item.Alvo -Force -ErrorAction SilentlyContinue)
    if ($antes.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = 'pasta ja estava vazia' }
    }
    # Arquivos em uso nao podem ser apagados; o resultado real e medido a seguir.
    Remove-Item -Path $Item.Alvo -Recurse -Force -ErrorAction SilentlyContinue
    $depois = @(Get-ChildItem -Path $Item.Alvo -Force -ErrorAction SilentlyContinue)
    $removidos = $antes.Count - $depois.Count

    if ($depois.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('{0} item(ns) removido(s)' -f $removidos) }
    }
    return @{ Status = 'Parcial'; Detalhe = ('{0} item(ns) removido(s), {1} mantido(s) (em uso)' -f $removidos, $depois.Count) }
}

function Set-VisualEffectsPerformance {
    # Aplica de fato o perfil de desempenho: VisualFXSetting sozinho so muda o botao
    # de radio do dialogo "Opcoes de Desempenho", sem alterar nenhum efeito real.
    try {
        $fx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (-not (Test-Path $fx)) { New-Item -Path $fx -Force | Out-Null }
        # 3 = Personalizado: melhor desempenho mantendo a suavizacao de fontes (legibilidade).
        Set-ItemProperty -Path $fx -Name 'VisualFXSetting' -Value 3 -Type DWord -ErrorAction Stop

        # Mascara de "melhor desempenho" com o bit de suavizacao de fontes ligado (byte 5 = 0x12).
        $mascara = [byte[]](0x90, 0x12, 0x03, 0x80, 0x12, 0x00, 0x00, 0x00)
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value $mascara -Type Binary -ErrorAction Stop
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type String -ErrorAction Stop
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing' -Value '2' -Type String -ErrorAction Stop
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String -ErrorAction Stop

        $avancado = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-ItemProperty -Path $avancado -Name 'TaskbarAnimations' -Value 0 -Type DWord -ErrorAction Stop
        Set-ItemProperty -Path $avancado -Name 'ListviewAlphaSelect' -Value 0 -Type DWord -ErrorAction Stop
        Set-ItemProperty -Path $avancado -Name 'ListviewShadow' -Value 0 -Type DWord -ErrorAction Stop

        $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
        if (-not (Test-Path $dwm)) { New-Item -Path $dwm -Force | Out-Null }
        Set-ItemProperty -Path $dwm -Name 'EnableAeroPeek' -Value 0 -Type DWord -ErrorAction Stop

        Invoke-BroadcastSettingChange
        return @{ Status = 'Ok'; Detalhe = 'perfil de desempenho aplicado (efeito completo no proximo logon)' }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }
}

function Remove-OneDriveApp {
    # OneDrive nao e Appx: usa o desinstalador nativo.
    Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue

    $candidatos = @(
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\Update\OneDriveSetup.exe')
    )
    $instaladorMaquina = Join-Path $env:ProgramFiles 'Microsoft OneDrive'
    if (Test-Path $instaladorMaquina) {
        $achado = Get-ChildItem -Path $instaladorMaquina -Filter 'OneDriveSetup.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($achado) { $candidatos = @($achado.FullName) + $candidatos }
    }

    $setup = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $setup) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'instalador do OneDrive nao encontrado (ja removido?)' }
    }
    try {
        Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = ('desinstalador executado ({0})' -f $setup) }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }
}

function Disable-RecallFeature {
    $ok = 0
    $falhas = @()
    foreach ($raiz in @('HKCU:\Software\Policies\Microsoft\Windows\WindowsAI', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI')) {
        try {
            if (-not (Test-Path $raiz)) { New-Item -Path $raiz -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $raiz -Name 'DisableAIDataAnalysis' -Value 1 -Type DWord -ErrorAction Stop
            $ok++
        }
        catch {
            $falhas += ('{0}: {1}' -f $raiz, $_.Exception.Message)
        }
    }

    $detalheFeature = 'recurso opcional "Recall" nao existe neste hardware'
    try {
        $recurso = Get-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction SilentlyContinue
        if ($recurso -and $recurso.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -NoRestart -ErrorAction Stop | Out-Null
            $detalheFeature = 'recurso opcional "Recall" desabilitado (requer reinicio)'
        }
        elseif ($recurso) {
            $detalheFeature = 'recurso opcional "Recall" ja estava desabilitado'
        }
    }
    catch {
        $falhas += ('recurso Recall: {0}' -f $_.Exception.Message)
    }

    if ($falhas.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('politica aplicada; {0}' -f $detalheFeature) }
    }
    if ($ok -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('politica parcial; falhas: {0}' -f ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Get-AcaoDescricao {
    param([Parameter(Mandatory)]$Item)
    switch ($Item.Tipo) {
        'Appx'           { 'removeria o pacote {0} (instalado e provisionado)' -f $Item.Alvo }
        'Servico'        { 'pararia e desativaria o servico {0}' -f $Item.Alvo }
        'Registro'       { 'aplicaria {0} valor(es) de registro' -f @($Item.Valores).Count }
        'TarefaAgendada' { 'desativaria {0} tarefa(s) agendada(s)' -f @($Item.Alvos).Count }
        'LimpezaPasta'   { 'limparia {0}' -f $Item.Alvo }
        'Especial'       { 'executaria a acao "{0}"' -f $Item.Alvo }
    }
}

function Invoke-DebloatItem {
    param([Parameter(Mandatory)]$Item)

    if ($script:Simular) {
        return @{ Status = 'Simulado'; Detalhe = (Get-AcaoDescricao -Item $Item) }
    }
    switch ($Item.Tipo) {
        'Appx'           { return Remove-BloatApp -Item $Item }
        'Servico'        { return Disable-BloatService -Item $Item }
        'Registro'       { return Set-RegistryTweak -Item $Item }
        'TarefaAgendada' { return Disable-BloatScheduledTask -Item $Item }
        'LimpezaPasta'   { return Clear-TempPath -Item $Item }
        'Especial'       {
            switch ($Item.Alvo) {
                'EfeitosVisuais' { return Set-VisualEffectsPerformance }
                'OneDrive'       { return Remove-OneDriveApp }
                'Recall'         { return Disable-RecallFeature }
            }
        }
    }
    return @{ Status = 'Falha'; Detalhe = ('tipo de item desconhecido: {0}' -f $Item.Tipo) }
}

function Invoke-Selecao {
    param([Parameter(Mandatory)][object[]]$Itens)

    $temAppx = @($Itens | Where-Object { $_.Tipo -eq 'Appx' }).Count -gt 0
    if ($temAppx -and -not $script:Simular) {
        Get-InventarioAppx
    }

    if ($script:Simular) {
        Write-Log 'Iniciando SIMULACAO (nada sera alterado)...' 'Titulo'
    }
    else {
        Write-Log 'Iniciando execucao...' 'Titulo'
    }

    $contagem = @{ Ok = 0; Parcial = 0; NaoEncontrado = 0; Falha = 0; Simulado = 0 }
    $detalhes = [System.Collections.Generic.List[object]]::new()
    $total = $Itens.Count
    $indice = 0
    foreach ($item in $Itens) {
        $indice++
        $prefixo = '[{0,2}/{1}]' -f $indice, $total
        $resultado = Invoke-DebloatItem -Item $item
        $contagem[$resultado.Status]++
        $detalhes.Add([pscustomobject]@{
            Id = $item.Id; Categoria = $item.Categoria; Tipo = $item.Tipo
            Nivel = $item.Nivel; Descricao = $item.Descricao
            Status = $resultado.Status; Detalhe = $resultado.Detalhe
        })
        $linha = '{0} {1}: {2}' -f $prefixo, $item.Descricao, $resultado.Detalhe
        switch ($resultado.Status) {
            'Ok'            { Write-Log $linha 'Ok' }
            'Parcial'       { Write-Log $linha 'Aviso' }
            'NaoEncontrado' { Write-Log ('{0} {1}: nao encontrado neste sistema — nada a fazer' -f $prefixo, $item.Descricao) 'Info' }
            'Falha'         { Write-Log $linha 'Erro' }
            'Simulado'      { Write-Log $linha 'Simulacao' }
        }
    }

    Write-Log '--------------------------------------------------------------' 'Info'
    if ($script:Simular) {
        Write-Log ('Simulacao concluida: {0} acao(oes) seriam executadas.' -f $contagem.Simulado) 'Simulacao'
    }
    else {
        Write-Log ('Concluido: {0} ok, {1} parcial(is), {2} nao encontrado(s), {3} falha(s).' -f $contagem.Ok, $contagem.Parcial, $contagem.NaoEncontrado, $contagem.Falha) 'Titulo'
        Write-Log 'Reinicie o PC para concluir as mudancas de interface e de servicos.' 'Info'
    }
    return @{ Contagem = $contagem; Detalhes = $detalhes }
}

function Export-RelatorioJson {
    param(
        [Parameter(Mandatory)][string]$Caminho,
        [Parameter(Mandatory)][object[]]$Detalhes,
        [Parameter(Mandatory)][hashtable]$Contagem
    )
    $relatorio = [pscustomobject]@{
        SchemaVersion = 1
        Ferramenta    = 'Windows11-Debloat'
        Versao        = $script:VERSAO
        DataHora      = (Get-Date).ToString('o')
        Simulacao     = [bool]$script:Simular
        Contagem      = $Contagem
        Itens         = $Detalhes
    }
    try {
        $pasta = Split-Path -Path $Caminho -Parent
        if ($pasta -and -not (Test-Path $pasta)) {
            New-Item -Path $pasta -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        # -Depth explicito sempre: o padrao do PS 5.1 e 2, e trunca aninhamento sem
        # aviso (o "Itens" aqui e uma lista de objetos, ja passaria dos 2 niveis).
        $relatorio | ConvertTo-Json -Depth 5 | Set-Content -Path $Caminho -Encoding UTF8 -ErrorAction Stop
        Write-Log ('Relatorio JSON salvo em: {0}' -f $Caminho) 'Info'
    }
    catch {
        Write-Log ('Nao foi possivel salvar o relatorio JSON: {0}' -f $_.Exception.Message) 'Aviso'
    }
}

#endregion

#region Menu interativo -------------------------------------------------------

function Initialize-Selecao {
    param([Parameter(Mandatory)][string]$NomePerfil)
    $script:Selecionados = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in (Get-ItensDoPerfil -NomePerfil $NomePerfil)) {
        [void]$script:Selecionados.Add($item.Id)
    }
}

function Get-ContagemCategoria {
    param([Parameter(Mandatory)][string]$Categoria)
    $itens = @($script:Catalogo | Where-Object { $_.Categoria -eq $Categoria })
    $selecionados = @($itens | Where-Object { $script:Selecionados.Contains($_.Id) })
    @{ Selecionados = $selecionados.Count; Total = $itens.Count }
}

function Show-CategoryMenu {
    param([Parameter(Mandatory)][string]$Categoria)

    $itens = @($script:Catalogo | Where-Object { $_.Categoria -eq $Categoria })
    while ($true) {
        Clear-Host
        Write-Host '=============================================================='
        Write-Host (' CATEGORIA: {0}' -f $Categoria.ToUpper())
        Write-Host '=============================================================='
        for ($i = 0; $i -lt $itens.Count; $i++) {
            $item = $itens[$i]
            $marca = '[ ]'
            if ($script:Selecionados.Contains($item.Id)) { $marca = '[X]' }
            $alvoTecnico = $item.Alvo
            if (-not $alvoTecnico) { $alvoTecnico = $item.Id }
            $sufixo = ''
            if ($item.Nivel -eq 'Opcional') { $sufixo = '  *opcional' }
            elseif ($item.Nivel -eq 'Agressivo') { $sufixo = '  *AGRESSIVO' }
            $linha = ' {0} {1,2}) {2,-42} ({3}){4}' -f $marca, ($i + 1), $item.Descricao, $alvoTecnico, $sufixo
            if ($item.Nivel -eq 'Agressivo') { Write-Host $linha -ForegroundColor Yellow }
            else { Write-Host $linha }
        }
        Write-Host '--------------------------------------------------------------'
        Write-Host ' Digite o(s) numero(s) para marcar/desmarcar (ex.: 3 ou 1,4,7)'
        Write-Host ' T) Marcar todos    N) Desmarcar todos    V) Voltar'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()

        switch ($opcao) {
            'V' { return }
            'T' { foreach ($item in $itens) { [void]$script:Selecionados.Add($item.Id) } }
            'N' { foreach ($item in $itens) { [void]$script:Selecionados.Remove($item.Id) } }
            default {
                $numeros = $opcao -split '[,; ]+' | Where-Object { $_ -match '^\d+$' }
                foreach ($numero in $numeros) {
                    $posicao = [int]$numero - 1
                    if ($posicao -ge 0 -and $posicao -lt $itens.Count) {
                        $id = $itens[$posicao].Id
                        if ($script:Selecionados.Contains($id)) { [void]$script:Selecionados.Remove($id) }
                        else { [void]$script:Selecionados.Add($id) }
                    }
                }
            }
        }
    }
}

function Show-Confirmacao {
    param(
        [Parameter(Mandatory)][object[]]$Itens,
        [Parameter(Mandatory)][bool]$ComRestore
    )
    Clear-Host
    Write-Host '====================== RESUMO DA EXECUCAO ===================='
    Write-Host (' {0} item(ns) selecionado(s):' -f $Itens.Count)
    foreach ($categoria in $script:Categorias) {
        $porCategoria = @($Itens | Where-Object { $_.Categoria -eq $categoria })
        if ($porCategoria.Count -gt 0) {
            Write-Host ('   {0,-12} {1,2} item(ns)' -f ($categoria + ':'), $porCategoria.Count)
        }
    }
    $agressivos = @($Itens | Where-Object { $_.Nivel -eq 'Agressivo' })
    if ($agressivos.Count -gt 0) {
        Write-Host (' ATENCAO: {0} item(ns) AGRESSIVO(S) selecionado(s):' -f $agressivos.Count) -ForegroundColor Yellow
        foreach ($item in $agressivos) {
            Write-Host ('   - {0}' -f $item.Descricao) -ForegroundColor Yellow
        }
    }
    $textoRestore = 'NAO'
    if ($ComRestore) { $textoRestore = 'SIM' }
    $textoSimulacao = 'NAO'
    if ($script:Simular) { $textoSimulacao = 'SIM' }
    Write-Host (' Ponto de restauracao: {0}    Simulacao: {1}' -f $textoRestore, $textoSimulacao)
    if ($script:ArquivoLog) { Write-Host (' Log: {0}' -f $script:ArquivoLog) }
    Write-Host '--------------------------------------------------------------'
    Write-Host ' C) Confirmar e executar        V) Voltar ao menu'
    Write-Host '=============================================================='
    $opcao = (Read-Host 'Opcao').Trim().ToUpper()
    return ($opcao -eq 'C')
}

function Show-MainMenu {
    $perfilAtual = $Perfil
    Initialize-Selecao -NomePerfil $perfilAtual
    $comRestore = -not $SemPontoRestauracao

    while ($true) {
        Clear-Host
        $textoSimulacao = 'NAO'
        if ($script:Simular) { $textoSimulacao = 'SIM' }
        Write-Host '=============================================================='
        Write-Host (' DEBLOAT WINDOWS 11 v{0}                    [SIMULACAO: {1}]' -f $script:VERSAO, $textoSimulacao)
        Write-Host (' Perfil base: {0}   |   Selecionados: {1} de {2} itens' -f $perfilAtual, $script:Selecionados.Count, $script:Catalogo.Count)
        Write-Host '=============================================================='
        for ($i = 0; $i -lt $script:Categorias.Count; $i++) {
            $contagem = Get-ContagemCategoria -Categoria $script:Categorias[$i]
            Write-Host ('  {0}) {1,-12} ({2,2} de {3,2} selecionados)' -f ($i + 1), $script:Categorias[$i], $contagem.Selecionados, $contagem.Total)
        }
        $textoRestore = 'NAO'
        if ($comRestore) { $textoRestore = 'SIM' }
        Write-Host '--------------------------------------------------------------'
        Write-Host ' P) Trocar perfil base (Minimo / Completo / Agressivo)'
        Write-Host (' R) Ponto de restauracao antes de executar: {0}' -f $textoRestore)
        Write-Host ' E) EXECUTAR selecao'
        Write-Host ' S) Sair sem executar'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()

        switch ($opcao) {
            'S' { return $null }
            'P' {
                $perfilAtual = switch ($perfilAtual) {
                    'Minimo'    { 'Completo' }
                    'Completo'  { 'Agressivo' }
                    'Agressivo' { 'Minimo' }
                }
                Initialize-Selecao -NomePerfil $perfilAtual
            }
            'R' { $comRestore = -not $comRestore }
            'E' {
                $itens = @($script:Catalogo | Where-Object { $script:Selecionados.Contains($_.Id) })
                if ($itens.Count -eq 0) {
                    Write-Log 'Nenhum item selecionado.' 'Aviso'
                    Start-Sleep -Seconds 2
                    continue
                }
                if (Show-Confirmacao -Itens $itens -ComRestore $comRestore) {
                    return @{ Itens = $itens; ComRestore = $comRestore }
                }
            }
            default {
                if ($opcao -match '^\d$') {
                    $posicao = [int]$opcao - 1
                    if ($posicao -ge 0 -and $posicao -lt $script:Categorias.Count) {
                        Show-CategoryMenu -Categoria $script:Categorias[$posicao]
                    }
                }
            }
        }
    }
}

#endregion

#region Fluxo principal -------------------------------------------------------

Assert-Admin -ParametrosOriginais $PSBoundParameters
Assert-Windows11
Start-Logging

Write-Log ('Debloat Windows 11 v{0} — perfil "{1}"{2}' -f $script:VERSAO, $Perfil, $(if ($NaoInterativo) { ' (nao interativo)' } else { '' })) 'Titulo'
if ($script:ArquivoLog) { Write-Log ('Log: {0}' -f $script:ArquivoLog) 'Info' }
if ($script:Simular) { Write-Log 'MODO SIMULACAO: nenhuma alteracao sera feita no sistema.' 'Simulacao' }
[void](Test-UsuarioDivergente)

$codigoSaida = 0
try {
    if ($NaoInterativo) {
        $itensExecucao = @(Get-ItensDoPerfil -NomePerfil $Perfil)
        $fazRestore = -not $SemPontoRestauracao
    }
    else {
        $selecao = Show-MainMenu
        if (-not $selecao) {
            Write-Log 'Nenhuma acao executada.' 'Info'
            exit 0
        }
        $itensExecucao = @($selecao.Itens)
        $fazRestore = $selecao.ComRestore
    }

    if ($fazRestore) {
        $restoreOk = New-RestorePoint
        if (-not $restoreOk -and -not $script:Simular) {
            if ($NaoInterativo) {
                Write-Log 'Prosseguindo sem ponto de restauracao (modo nao interativo).' 'Aviso'
            }
            else {
                $resposta = Read-Host 'Continuar SEM ponto de restauracao? (S/N)'
                if ($resposta -notmatch '^[sS]') {
                    Write-Log 'Execucao cancelada pelo usuario.' 'Info'
                    exit 4
                }
            }
        }
    }
    elseif (-not $script:Simular) {
        Write-Log 'Ponto de restauracao desativado por opcao do usuario.' 'Aviso'
    }

    $resultado = Invoke-Selecao -Itens $itensExecucao
    if ($resultado.Contagem.Falha -gt 0) { $codigoSaida = 5 }
    if ($CaminhoRelatorioJson) {
        Export-RelatorioJson -Caminho $CaminhoRelatorioJson -Detalhes $resultado.Detalhes -Contagem $resultado.Contagem
    }
}
finally {
    if ($script:TranscriptAtivo) {
        try { Stop-Transcript | Out-Null }
        catch { Write-Verbose ('Falha ao encerrar o transcript: {0}' -f $_.Exception.Message) }
        $script:TranscriptAtivo = $false
        Write-Host ('Log salvo em: {0}' -f $script:ArquivoLog)
    }
}

if (-not $NaoInterativo) {
    Read-Host 'Pressione ENTER para sair' | Out-Null
}
exit $codigoSaida

#endregion
