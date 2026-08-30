# Testes estruturais do debloat-windows11.ps1 (Pester 5).
# Rodam em qualquer SO (validam sintaxe, encoding e consistencia do catalogo);
# o comportamento real e validado no CI (windows-latest) e em VM.

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'debloat-windows11.ps1'

    $tokens = $null
    $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)
    $script:ErrosParse = $erros

    # Extrai o catalogo avaliando apenas o literal atribuido a $script:Catalogo,
    # sem executar o restante do script.
    $atribuicao = $script:Ast.FindAll({
            param($no)
            $no -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $no.Left.Extent.Text -eq '$script:Catalogo'
        }, $true) | Select-Object -First 1
    $script:Catalogo = @()
    if ($atribuicao) {
        $script:Catalogo = @([scriptblock]::Create($atribuicao.Right.Extent.Text).Invoke())
    }
}

Describe 'Sintaxe e encoding' {
    It 'faz parse sem erros de sintaxe' {
        $script:ErrosParse | Should -BeNullOrEmpty
    }

    It 'esta salvo como UTF-8 com BOM (obrigatorio para acentos no PowerShell 5.1)' {
        $bytes = [System.IO.File]::ReadAllBytes($script:CaminhoScript)[0..2]
        $bytes | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'declara #Requires -Version 5.1' {
        (Get-Content -Path $script:CaminhoScript -TotalCount 5) -join "`n" |
            Should -Match '#Requires -Version 5\.1'
    }

    It 'nao usa Pause (bloqueia execucao nao interativa)' {
        $comandos = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.CommandAst] -and
                $no.GetCommandName() -eq 'Pause'
            }, $true)
        $comandos | Should -BeNullOrEmpty
    }
}

Describe 'Catalogo' {
    It 'foi extraido do script' {
        $script:Catalogo.Count | Should -BeGreaterThan 30
    }

    It 'tem Ids unicos' {
        $ids = $script:Catalogo | ForEach-Object { $_.Id }
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'tem os campos obrigatorios em todos os itens' {
        foreach ($item in $script:Catalogo) {
            $item.Id | Should -Not -BeNullOrEmpty
            $item.Categoria | Should -Not -BeNullOrEmpty
            $item.Tipo | Should -Not -BeNullOrEmpty
            $item.Descricao | Should -Not -BeNullOrEmpty
            $item.Nivel | Should -Not -BeNullOrEmpty
        }
    }

    It 'usa apenas Categorias conhecidas' {
        $validas = @('Apps', 'Telemetria', 'Desempenho', 'Limpeza')
        foreach ($item in $script:Catalogo) {
            $validas | Should -Contain $item.Categoria
        }
    }

    It 'usa apenas Tipos conhecidos' {
        $validos = @('Appx', 'Servico', 'Registro', 'TarefaAgendada', 'LimpezaPasta', 'Especial')
        foreach ($item in $script:Catalogo) {
            $validos | Should -Contain $item.Tipo
        }
    }

    It 'usa apenas Niveis conhecidos (Seguro/Opcional/Agressivo)' {
        $validos = @('Seguro', 'Opcional', 'Agressivo')
        foreach ($item in $script:Catalogo) {
            $validos | Should -Contain $item.Nivel
        }
    }

    It 'itens Appx tem Alvo exato, sem curingas' {
        foreach ($item in ($script:Catalogo | Where-Object { $_.Tipo -eq 'Appx' })) {
            $item.Alvo | Should -Not -BeNullOrEmpty
            $item.Alvo | Should -Not -Match '[\*\?]'
        }
    }

    It 'itens Registro tem a lista Valores com Caminho/Nome/Valor/Tipo' {
        foreach ($item in ($script:Catalogo | Where-Object { $_.Tipo -eq 'Registro' })) {
            @($item.Valores).Count | Should -BeGreaterThan 0
            foreach ($valor in $item.Valores) {
                $valor.Caminho | Should -Not -BeNullOrEmpty
                $valor.Nome | Should -Not -BeNullOrEmpty
                $valor.Tipo | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'itens TarefaAgendada tem a lista Alvos com Caminho/Nome' {
        foreach ($item in ($script:Catalogo | Where-Object { $_.Tipo -eq 'TarefaAgendada' })) {
            @($item.Alvos).Count | Should -BeGreaterThan 0
            foreach ($alvo in $item.Alvos) {
                $alvo.Caminho | Should -Match '^\\.*\\$'
                $alvo.Nome | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'itens Servico e LimpezaPasta tem Alvo' {
        foreach ($item in ($script:Catalogo | Where-Object { $_.Tipo -in @('Servico', 'LimpezaPasta') })) {
            $item.Alvo | Should -Not -BeNullOrEmpty
        }
    }

    It 'nao contem pacotes mortos do Windows 10' {
        $mortos = @(
            'Microsoft.3DBuilder', 'Microsoft.Messaging', 'Microsoft.OneConnect',
            'Microsoft.NetworkSpeedTest', 'Microsoft.Print3D', 'Microsoft.Microsoft3DViewer',
            'Microsoft.SkypeApp', 'Microsoft.XboxApp', 'Microsoft.Getstarted', 'Microsoft.News'
        )
        foreach ($item in ($script:Catalogo | Where-Object { $_.Tipo -eq 'Appx' })) {
            $mortos | Should -Not -Contain $item.Alvo
        }
    }

    It 'mantem itens perigosos fora do nivel padrao (Seguro)' {
        $perigosos = @('Microsoft.StorePurchaseApp', 'Microsoft.XboxIdentityProvider', 'Microsoft.Xbox.TCUI')
        foreach ($item in ($script:Catalogo | Where-Object { $perigosos -contains $_.Alvo })) {
            $item.Nivel | Should -Be 'Agressivo'
        }
    }

    It 'dmwappushservice (quebra MDM/Intune) nao e nivel Seguro' {
        $item = $script:Catalogo | Where-Object { $_.Alvo -eq 'dmwappushservice' }
        $item | Should -Not -BeNullOrEmpty
        $item.Nivel | Should -Not -Be 'Seguro'
    }

    It 'perfis formam uma cadeia: ha itens em todos os niveis' {
        @($script:Catalogo | Where-Object { $_.Nivel -eq 'Seguro' }).Count | Should -BeGreaterThan 0
        @($script:Catalogo | Where-Object { $_.Nivel -eq 'Opcional' }).Count | Should -BeGreaterThan 0
        @($script:Catalogo | Where-Object { $_.Nivel -eq 'Agressivo' }).Count | Should -BeGreaterThan 0
    }
}
