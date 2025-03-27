
# 🧹 Debloat Windows 11 – Remoção de Bloatware e Otimização

Script PowerShell para remover aplicativos desnecessários (bloatware), desativar serviços de telemetria, limpar arquivos temporários e aplicar ajustes de desempenho no Windows 11.

---

## ⚠️ AVISO LEGAL

Este script é fornecido com fins técnicos e educacionais.  
**Execute por sua própria conta e risco.**  
Recomendado apenas para técnicos, analistas e usuários com conhecimento prévio.

---

## 🎯 O que este script faz

- Remove aplicativos pré-instalados indesejados
- Desativa serviços de telemetria (DiagTrack, DMWAPPushService)
- Ajusta efeitos visuais para melhorar performance
- Limpa arquivos temporários do usuário e do sistema

---

## 🛠️ Como usar

1. **Baixe o script para sua máquina**, exemplo:

   ```
   C:\debloat-windows11.ps1
   ```

2. **Abra o PowerShell como Administrador**

3. **Desbloqueie o script (obrigatório):**

   ```powershell
   Unblock-File -Path C:\debloat-windows11.ps1
   ```

4. **(Se necessário) Altere temporariamente a política de execução:**

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

5. **Execute o script:**

   ```powershell
   .\debloat-windows11.ps1
   ```

---

## ✅ Após a execução: Restaurar restrições de segurança

Por padrão, o PowerShell bloqueia a execução de scripts por segurança. Para manter seu sistema protegido, **reaplique a política original (Restricted)**:

```powershell
Set-ExecutionPolicy Restricted -Scope Process
```

> Se você usou o parâmetro `-Scope Process`, isso é feito automaticamente ao fechar o terminal.  
> Para alterar globalmente (não recomendado), use `-Scope LocalMachine`.

---

## 📝 Requisitos

- Windows 11
- Acesso de Administrador
- PowerShell

---

## 🛡️ Ética e Responsabilidade

Não utilize este script em equipamentos de terceiros sem autorização.  
Testado em builds recentes do Windows 11. Recomendado testar em ambiente controlado antes de aplicar em produção.

---

## 📄 Licença

Distribuído sob a licença [MIT](LICENSE).  
Conteúdo livre para uso, adaptação e redistribuição com os devidos créditos.

---

**Feito por [rivaed](https://github.com/rivaed) – scripts que aliviam o sistema, não a responsabilidade.**

