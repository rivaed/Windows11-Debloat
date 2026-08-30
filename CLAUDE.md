# Windows11-Debloat

Script PowerShell de debloat do Windows 11 para técnicos: menu interativo, perfis,
simulação e log. Arquivo único, zero dependências.

## Regras do projeto

- **Alvo: Windows PowerShell 5.1** (o padrão do Windows 11). Nada de sintaxe exclusiva do
  PowerShell 7 (`??`, ternário, `-AsHashtable` etc.). O script se auto-relança no 5.1.
- **`debloat-windows11.ps1` é UTF-8 COM BOM** — nunca salvar sem BOM (o 5.1 lê sem BOM como
  ANSI e os acentos pt-BR quebram). Ao editar com ferramentas que reescrevem o arquivo,
  conferir/repor os 3 bytes `EF BB BF`.
- Saída de console: mensagens em pt-BR sem acento nas molduras do menu (ASCII puro);
  marcadores `[OK]/[X]/[!]/[SIMULACAO]` — sem emoji.
- **Arquivo único**: não dividir em módulos/JSON — o fluxo real de uso é baixar 1 arquivo.
- Todo item novo entra no `$script:Catalogo` (data-driven), nunca como código solto.
  Campos: `Id` (único), `Categoria`, `Tipo`, `Nivel` (`Seguro|Opcional|Agressivo`), alvo.
  Item que quebra funcionalidade = `Agressivo`, com a quebra documentada no README.
- Toda ação destrutiva passa por `Invoke-DebloatItem` (é lá que o `-Simular` é honrado —
  não criar caminhos que executem sem passar por ele).
- Mensagens honestas: nunca reportar `[OK]` sem verificar o efeito real.
- Ao mexer no catálogo: atualizar a tabela do README e o CHANGELOG na mesma mudança
  (o CI e o CONTRIBUTING cobram isso).

## Verificação

- Testes estruturais: `Invoke-Pester -Path ./tests` (rodam em qualquer SO, inclusive
  via Docker: `docker run --rm -v "$PWD:/src" -w /src mcr.microsoft.com/powershell pwsh -c "Invoke-Pester -Path ./tests"`).
- Lint: `Invoke-ScriptAnalyzer -Path ./debloat-windows11.ps1`.
- CI (GitHub Actions, windows-latest): lint + Pester + dry-run
  `-NaoInterativo -Simular -Perfil Agressivo` no PowerShell 5.1 real.
- Comportamento de verdade: VM Windows 11 (primeiro com `-Simular`, depois perfil Minimo).

## Commits

Conventional Commits em pt-BR (`feat`, `fix`, `docs`, `test`, `chore`…), sem menção a IA.
