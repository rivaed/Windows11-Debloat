
# Windows 11 Debloat Script

## Descrição

Este script em PowerShell remove aplicativos indesejados, desativa serviços desnecessários e ajusta configurações para melhorar a performance do Windows 11. Ele é ideal para usuários que desejam um sistema mais limpo, leve e rápido.

## Funcionalidades

- Remoção de bloatware (aplicativos pré-instalados).
- Desativação de telemetria e coleta de dados.
- Ajuste de configurações para melhorar o desempenho.
- Otimização de serviços e processos em segundo plano.

## Como Usar

### Método 1: Execução Direta via PowerShell

1. Baixe o script `debloat-windows11.ps1`.
2. Abra o **PowerShell como Administrador**.
3. Navegue até a pasta onde o script está salvo:
   ```powershell
   cd C:\caminho\para\o\script
   ```
4. Permita a execução de scripts:
   ```powershell
   Set-ExecutionPolicy Unrestricted -Scope CurrentUser
   ```
5. Execute o script:
   ```powershell
   .\debloat-windows11.ps1
   ```

### Método 2: Execução via Comando Único (Recomendado)

Abra o **PowerShell como Administrador** e execute:

```powershell
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/rivaed/Windows11-Debloat/main/debloat-windows11.ps1'))
```

## Aviso

Este script altera configurações do sistema e remove aplicativos. **Use por sua conta e risco.** Recomenda-se criar um ponto de restauração antes da execução.

## Contribuições

Contribuições são bem-vindas! Se quiser sugerir melhorias ou adicionar funcionalidades, basta abrir um Pull Request.

## Licença

Este projeto está licenciado sob a **MIT License** – sinta-se livre para modificar e compartilhar.
