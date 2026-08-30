# Contribuindo

## Critérios para um item entrar no catálogo

Um app/serviço/ajuste só entra se:

1. **É bloatware inequívoco** ou telemetria — não um app que parte relevante dos usuários usa.
2. **Existe no Windows 11 atual** (23H2/24H2/25H2) — nomes de pacote conferidos com
   `Get-AppxPackage -AllUsers` / `Get-AppxProvisionedPackage -Online` numa instalação real.
3. **Nível correto:**
   - `Seguro` — remoção sem efeito colateral perceptível para o usuário comum;
   - `Opcional` — depende do uso (Xbox, Phone Link, Quick Assist…);
   - `Agressivo` — quebra alguma funcionalidade ou muda a UX padrão (documente O QUE quebra).
4. **Alvo exato**, sem curingas.

## Checklist do PR

- [ ] Item adicionado ao `$script:Catalogo` com `Id` único e `Descricao` clara em pt-BR.
- [ ] Tabela do README atualizada (mesma PR).
- [ ] CHANGELOG atualizado (mesma PR).
- [ ] Testado em Windows 11 real ou VM (diga o build no PR).
- [ ] CI verde (PSScriptAnalyzer + Pester + dry-run).

## Convenções

- **Commits:** Conventional Commits em pt-BR — `tipo(escopo): descrição` no imperativo
  (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`), explicando o *porquê* quando não
  for óbvio.
- **Encoding:** o `.ps1` é UTF-8 **com BOM** — não salve sem BOM (quebra os acentos no
  PowerShell 5.1). Saída de console usa apenas ASCII nas molduras do menu.
- **Compatibilidade:** todo código deve rodar no Windows PowerShell 5.1 (sem sintaxe
  exclusiva do PowerShell 7: `??`, ternário etc.).

## Releases (mantenedor)

1. Atualizar `$script:VERSAO` e o CHANGELOG.
2. Criar tag `vX.Y.Z` e release no GitHub com o `.ps1` anexado.
3. Publicar o hash na descrição do release: `Get-FileHash .\debloat-windows11.ps1 -Algorithm SHA256`.
