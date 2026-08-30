# 🧹 Debloat Windows 11

[![CI](https://github.com/rivaed/Windows11-Debloat/actions/workflows/ci.yml/badge.svg)](https://github.com/rivaed/Windows11-Debloat/actions/workflows/ci.yml)

Script PowerShell para Windows 11 (23H2/24H2/25H2) que remove bloatware, desativa telemetria
(serviços, registro e tarefas agendadas), aplica ajustes de desempenho e limpa arquivos
temporários — com **menu interativo por categorias**, **perfis**, **simulação (dry-run)** e
**log em arquivo**.

Feito para técnicos e analistas. Arquivo único, zero dependências, alvo Windows PowerShell 5.1
(o padrão do Windows 11).

<!-- TODO: screenshot/GIF da execucao (docs/screenshot.png) -->

---

## ⚠️ Aviso legal

Este script é fornecido com fins técnicos e educacionais. **Execute por sua própria conta e
risco.** Não utilize em equipamentos de terceiros sem autorização. Teste em ambiente
controlado (VM) antes de usar em produção.

---

## 🚀 Como usar

1. Baixe o script (clone do repositório ou download do arquivo `debloat-windows11.ps1`).

2. Se baixou **pelo navegador**, desbloqueie o arquivo (não é necessário para `git clone`):

   ```powershell
   Unblock-File -Path .\debloat-windows11.ps1
   ```

3. Abra o **PowerShell como Administrador** (o script também sabe se auto-elevar via UAC) e,
   se a política de execução bloquear, libere **apenas para esta sessão**:

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

   > Com `-Scope Process` a política volta ao normal sozinha quando o terminal fecha —
   > não há nada para "reverter" depois.

4. Execute:

   ```powershell
   .\debloat-windows11.ps1
   ```

   Abre o menu interativo. Navegue pelas categorias, marque/desmarque itens e confirme.

### Modo não interativo (automação / RMM)

```powershell
# Simula (nada é alterado) o que o perfil Minimo faria:
.\debloat-windows11.ps1 -NaoInterativo -Perfil Minimo -Simular

# Executa o perfil Completo sem menu, sem pausas:
.\debloat-windows11.ps1 -NaoInterativo -Perfil Completo
```

Em execução remota (RMM/Intune/PsExec), rode **já elevado** (admin/SYSTEM): no modo
`-NaoInterativo` o script não tenta abrir prompt de UAC — se não for admin, aborta com
código de saída 2.

### Parâmetros

| Parâmetro | Descrição |
|---|---|
| `-Perfil Minimo\|Completo\|Agressivo` | Conjunto de itens (padrão: `Completo`). No menu, define só a pré-seleção. |
| `-NaoInterativo` | Sem menu e sem pausas; executa o perfil direto. |
| `-Simular` | Dry-run: mostra o que seria feito sem alterar nada. |
| `-SemPontoRestauracao` | Não cria ponto de restauração. |
| `-CaminhoLog <arquivo>` | Log em caminho customizado. |
| `-CaminhoRelatorioJson <arquivo>` | Exporta um relatório antes/depois em JSON (item a item, com status) — útil para anexar a um laudo de atendimento ou alimentar um RMM/dashboard. |

**Perfis:** `Minimo` = só itens Seguros · `Completo` = Seguros + Opcionais ·
`Agressivo` = tudo, incluindo itens que quebram funcionalidades (tabelas abaixo).

**Códigos de saída:** `0` sucesso · `1` elevação cancelada/falhou · `2` não interativo sem
admin · `3` SO não suportado · `4` cancelado pelo usuário · `5` concluído com falhas.

**Log:** `%ProgramData%\Windows11-Debloat\logs\debloat_<data>.log` (transcript completo da
execução — o caminho é exibido no início e no fim).

### Relatório antes/depois em JSON

Com `-CaminhoRelatorioJson <arquivo>`, o script exporta um relatório estruturado da
execução (funciona em modo real e em `-Simular`):

```json
{
  "SchemaVersion": 1,
  "Ferramenta": "Windows11-Debloat",
  "Versao": "2.1.0",
  "DataHora": "2026-08-30T10:00:00.0000000-04:00",
  "Simulacao": false,
  "Contagem": { "Ok": 30, "Parcial": 0, "NaoEncontrado": 5, "Falha": 0, "Simulado": 0 },
  "Itens": [
    { "Id": "bing-news", "Categoria": "Apps", "Tipo": "Appx", "Nivel": "Seguro", "Descricao": "...", "Status": "Ok", "Detalhe": "removido" }
  ]
}
```

---

## 📋 O que cada item faz

### Apps (remoção de pacotes Appx)

| Item | Pacote | Nível | Observações |
|---|---|---|---|
| Notícias (Bing News) | `Microsoft.BingNews` | Seguro | |
| Clima (Bing Weather) | `Microsoft.BingWeather` | Seguro | |
| Bing Search | `Microsoft.BingSearch` | Seguro | Novo no 24H2 |
| Obter Ajuda | `Microsoft.GetHelp` | Seguro | |
| Microsoft 365 (Office Hub) | `Microsoft.MicrosoftOfficeHub` | Seguro | Não afeta o Office instalado |
| Solitaire Collection | `Microsoft.MicrosoftSolitaireCollection` | Seguro | |
| Pessoas | `Microsoft.People` | Seguro | |
| Microsoft To Do | `Microsoft.Todos` | Seguro | |
| Media Player | `Microsoft.ZuneMusic` | Seguro | Player padrão de música — remova só se usa outro |
| Filmes e TV | `Microsoft.ZuneVideo` | Seguro | |
| Clipchamp | `Clipchamp.Clipchamp` | Seguro | |
| Teams (pessoal) | `MSTeams` | Seguro | Não afeta o Teams corporativo (work/school) |
| Novo Outlook | `Microsoft.OutlookForWindows` | Seguro | Remova só se usa outro cliente de e-mail |
| Power Automate | `Microsoft.PowerAutomateDesktop` | Seguro | |
| Microsoft Family | `MicrosoftCorporationII.MicrosoftFamily` | Seguro | |
| LinkedIn | `7EE7776C.LinkedInforWindows` | Seguro | |
| Dev Home | `Microsoft.Windows.DevHome` | Seguro | Descontinuado pela própria Microsoft |
| Copilot (app) | `Microsoft.Copilot` | Seguro | Há também a política, na categoria Telemetria |
| Xbox (app atual) | `Microsoft.GamingApp` | Opcional | **Gamers devem manter** |
| Xbox Game Overlay / Game Bar / Speech | `Microsoft.XboxGameOverlay` / `XboxGamingOverlay` / `XboxSpeechToTextOverlay` | Opcional | **Gamers devem manter** |
| Phone Link + Cross Device | `Microsoft.YourPhone` / `MicrosoftWindows.CrossDevice` | Opcional | Quem vincula o celular deve manter os dois |
| Assistência Rápida | `MicrosoftCorporationII.QuickAssist` | Opcional | Útil para suporte remoto |
| Compras da Store | `Microsoft.StorePurchaseApp` | **Agressivo** | ⚠️ Pode quebrar compras/licenças da Microsoft Store |
| Login Xbox | `Microsoft.XboxIdentityProvider` / `Microsoft.Xbox.TCUI` | **Agressivo** | ⚠️ Quebra login do Minecraft/Game Pass |
| Widgets (pacote) | `MicrosoftWindows.Client.WebExperience` | **Agressivo** | ⚠️ Remove Widgets por completo; prefira ocultar o botão (Desempenho) |
| OneDrive | desinstalador nativo | **Agressivo** | ⚠️ Confirme que nada do cliente depende do OneDrive antes |

### Telemetria e privacidade

| Item | Alvo | Nível | Observações |
|---|---|---|---|
| Serviço DiagTrack | serviço `DiagTrack` | Seguro | Connected User Experiences and Telemetry |
| Telemetria no mínimo | `HKLM\...\Policies\...\DataCollection` → `AllowTelemetry=1` etc. | Seguro | Em Home/Pro o mínimo real é 1 (Básico); 0 só vale em Enterprise/Education |
| Tarefas agendadas CEIP | Compatibility Appraiser, Consolidator, UsbCeip etc. | Seguro | |
| Content Delivery | `HKCU\...\ContentDeliveryManager` (10 valores) | Seguro | **Impede apps promovidos de voltarem sozinhos** |
| ID de publicidade | `HKCU\...\AdvertisingInfo\Enabled=0` | Seguro | |
| Bing fora do Iniciar | `DisableSearchBoxSuggestions=1` | Seguro | Requer logoff para valer |
| Política do Copilot | `TurnOffWindowsCopilot=1` | Seguro | Complementa a remoção do app |
| Serviço WAP Push | serviço `dmwappushservice` | Opcional | ⚠️ Necessário para gerenciamento MDM/Intune |
| Recall | política `DisableAIDataAnalysis=1` + recurso opcional | Opcional | Só existe em PCs Copilot+ (24H2+) |

### Desempenho e interface

| Item | Alvo | Nível | Observações |
|---|---|---|---|
| Efeitos visuais: desempenho | `UserPreferencesMask` + valores individuais | Seguro | Aplica de verdade (mantém suavização de fontes); efeito completo no próximo logon |
| Ocultar botão de Widgets | `TaskbarDa=0` | Seguro | Reversível; não remove o pacote |
| Mostrar extensões de arquivo | `HideFileExt=0` | Opcional | |
| Menu de contexto clássico | CLSID `{86ca1aa0-...}` | **Agressivo** | Muda a UX padrão do Windows 11 |

### Limpeza

| Item | Alvo | Nível |
|---|---|---|
| Temporários do usuário | `%TEMP%\*` | Seguro |
| Temporários do sistema | `%SystemRoot%\Temp\*` | Seguro |

---

## ♻️ Como reverter

- **Ponto de restauração:** o script cria (e **verifica de verdade**) um ponto antes de
  executar — `rstrui.exe` restaura o sistema inteiro.
- **App removido (para o usuário atual):** reinstale pela Microsoft Store, ou:

  ```powershell
  Get-AppxPackage -AllUsers Microsoft.BingWeather | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" }
  ```

  Se o pacote foi **desprovisionado**, a Store é o caminho (baixa de novo).
- **Serviço:** `Set-Service -Name DiagTrack -StartupType Automatic; Start-Service DiagTrack`
- **Chave de registro:** os valores aplicados estão na tabela acima; para desfazer, apague o
  valor (`Remove-ItemProperty`) ou restaure o dado original.
- **OneDrive:** reinstale com `winget install Microsoft.OneDrive` ou pelo instalador oficial.
- **Menu de contexto clássico:** apague a chave
  `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}` e reinicie o Explorer.

---

## 📌 Limitações conhecidas

- **Feature updates desfazem parte do trabalho:** upgrades de versão (ex.: 23H2 → 24H2)
  reinstalam apps de fábrica e podem reativar serviços. Reexecute o script após upgrades.
- **Cenário técnico com UAC:** se um usuário padrão está logado e o técnico digita a senha de
  admin no UAC, o processo elevado roda **como a conta do admin** — os ajustes por usuário
  (HKCU) e a limpeza de `%TEMP%` valem para o perfil do admin, não do usuário atendido.
  O script detecta e avisa quando isso acontece. Para atingir o usuário certo, rode numa
  sessão do próprio usuário com privilégios de admin.
- **Telemetria em Home/Pro:** o nível mínimo honrado é "Básico" (`AllowTelemetry=1`);
  desligar por completo (0) só funciona em Enterprise/Education.
- **PowerShell 7:** o script detecta e reabre no Windows PowerShell 5.1 automaticamente
  (o módulo Appx não é confiável no PowerShell Core).

---

## 📝 Requisitos

- Windows 11 (build 22000+) — em outros sistemas o script avisa e pede confirmação
- Acesso de Administrador
- Windows PowerShell 5.1 (padrão do sistema)

---

## 🤝 Contribuindo

Veja o [CONTRIBUTING.md](CONTRIBUTING.md) — em especial os critérios para incluir um app na
lista e a obrigação de atualizar a tabela deste README junto.

## 📄 Licença

[MIT](LICENSE). Conteúdo livre para uso, adaptação e redistribuição com os devidos créditos.

---

**Feito por [rivaed](https://github.com/rivaed) – scripts que aliviam o sistema, não a responsabilidade.**
