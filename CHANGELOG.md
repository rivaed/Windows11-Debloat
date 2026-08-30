# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [2.1.0] — não lançado

### Adicionado
- Relatório antes/depois em JSON (`-CaminhoRelatorioJson`): cada item processado, com
  status e contagem agregada, `SchemaVersion` e timestamp na raiz. Para viabilizar isso,
  `Invoke-Selecao` passou a acumular o resultado detalhado de cada item (antes só
  retornava contagens agregadas e descartava o detalhe).
- Teste mecânico novo: garante que toda chamada a `ConvertTo-Json` especifica `-Depth`
  (o padrão do PS 5.1 é 2 e trunca aninhamento sem aviso).

## [2.0.0] — 2026-08-30

### Adicionado
- Menu interativo por categorias (Apps, Telemetria, Desempenho, Limpeza) com marcação
  item a item, perfis e confirmação antes de executar.
- Perfis `Minimo` / `Completo` / `Agressivo` sobre um catálogo único data-driven.
- Modo não interativo (`-NaoInterativo`) para automação/RMM, com códigos de saída definidos.
- Simulação (`-Simular` / `-WhatIf`): dry-run completo sem alterar o sistema.
- Log em arquivo (transcript) em `%ProgramData%\Windows11-Debloat\logs`.
- Apps modernos do W11 no catálogo: Clipchamp, Teams pessoal, novo Outlook, Copilot,
  Power Automate, Family, LinkedIn, Dev Home, BingWeather, BingSearch, GamingApp,
  CrossDevice, QuickAssist, Widgets (pacote) e OneDrive (desinstalador nativo).
- Telemetria além de serviços: política `AllowTelemetry`, tarefas agendadas CEIP,
  ContentDeliveryManager (impede apps promovidos de voltarem), Advertising ID,
  Bing fora do menu Iniciar, política do Copilot e Recall (Copilot+).
- Verificação real do ponto de restauração (contorna o limite de 1 ponto/24h do Windows
  e confere com `Get-ComputerRestorePoint` antes de anunciar sucesso).
- Guardas: `#Requires -Version 5.1`, checagem de Windows 11, detecção de sessão não
  interativa e aviso quando o usuário elevado difere do usuário logado.
- Testes estruturais (Pester) e CI no GitHub Actions (PSScriptAnalyzer + Pester + dry-run
  em Windows PowerShell 5.1).

### Corrigido
- Ordem das remoções Appx: agora desprovisiona **antes** de remover por usuário, cada
  operação com tratamento de erro próprio — antes, uma falha na remoção por usuário
  cancelava o desprovisionamento e o app voltava para novas contas.
- Efeitos visuais: `VisualFXSetting` sozinho não aplicava nada; agora grava
  `UserPreferencesMask` + valores individuais e notifica o sistema (`WM_SETTINGCHANGE`).
- Mensagens honestas: fim do "[OK] Removido" quando nada foi encontrado e do "[X] Falha"
  quando a remoção funcionou parcialmente; resumo final com contadores reais.
- Matching exato de pacotes (sem curingas `*app*`, que podiam remover pacotes a mais).
- Encoding UTF-8 **com BOM** (acentos quebravam no PowerShell 5.1 sem BOM).
- Cancelamento do UAC tratado (antes o script morria com código de saída 0).
- Relançamento correto quando executado no PowerShell 7 (módulo Appx exige 5.1).
- Limpeza de temporários com relatório real (o try/catch anterior era código morto) e
  `%SystemRoot%\Temp` em vez de `C:\Windows\Temp` hardcoded.
- `Get-AppxProvisionedPackage -Online` executado uma única vez (antes, uma chamada DISM
  por app da lista).

### Alterado
- `Microsoft.StorePurchaseApp`, `Microsoft.XboxIdentityProvider` e `Microsoft.Xbox.TCUI`
  saíram do padrão: agora são nível **Agressivo** (quebram compras da Store e login Xbox).
- `dmwappushservice` virou **Opcional** (necessário para MDM/Intune).
- Grupo Xbox e Phone Link viraram **Opcionais** (gamers e quem vincula celular mantêm).

### Removido
- Entradas mortas no Windows 11: 3DBuilder, Messaging, OneConnect, NetworkSpeedTest,
  Print3D, Microsoft3DViewer, SkypeApp, XboxApp, Getstarted e `Microsoft.News`
  (entrada que nunca casava — o pacote real é `Microsoft.BingNews`).

## [1.0.0] — 2026-02-21

- Versão original: script linear com lista fixa de ~25 apps, desativação de
  DiagTrack/dmwappushservice, ajuste de `VisualFXSetting` e limpeza de temporários.
