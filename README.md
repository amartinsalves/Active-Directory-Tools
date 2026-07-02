# GPO Assessment Tool

Script PowerShell para avaliação de Objetos de Política de Grupo (GPOs) em um domínio Active Directory. Ele produz um relatório HTML consolidado com achados classificados por severidade e exporta o relatório nativo (GPMC) de cada GPO.

- **Arquivo:** `GPO.ps1`
- **Versão:** `1.0`
- **Idioma de saída:** Português (pt-BR)
- **Natureza:** Somente leitura em relação a GPOs, AD e SYSVOL; grava apenas no diretório de saída.

## Requisitos

| Requisito | Obrigatório | Se ausente |
|---|---|---|
| Executar como Administrador (`#Requires -RunAsAdministrator`) | Sim | O script não inicia (bloqueado pelo PowerShell). |
| Máquina ingressada no domínio | Sim | Encerra na detecção do domínio (`exit 1`). |
| Módulo `GroupPolicy` (RSAT/GPMC) | Sim | Encerra na importação do módulo (`exit 1`). |
| Módulo `ActiveDirectory` (RSAT) | Não | Links de OU, análise A16 e verificações de OU entre domínios ficam incompletos ou vazios. |
| Acesso de leitura ao SYSVOL (`\\<domain>\SYSVOL\<domain>\Policies`) | Sim, para A10/A11 | As análises de GPO órfão não são executadas. |
| Acesso de leitura à delegação de GPO (`Get-GPPermission`) | Sim, para A9 | A análise de SIDs não resolvidos fica incompleta. |
| Credenciais recomendadas | Domain Admin | Coleta parcial com privilégios menores. |

**Fato:** os módulos são carregados via `Import-Module`. O RSAT pode ser instalado com `Add-WindowsCapability -Online -Name 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'` e `Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'` (Windows 10/11), ou via `Install-WindowsFeature GPMC, RSAT-AD-PowerShell` (Windows Server).

## Execução

```powershell name=README-run.ps1
# PowerShell elevado, em uma máquina ingressada no domínio
.\GPO.ps1
```

Não há parâmetros de entrada. O domínio de destino é detectado automaticamente por:

```powershell name=README-domain-detection.ps1
[System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
```

## Saída

Todo o output é gravado em `C:\GPO-Assessment\`:

| Item | Caminho |
|---|---|
| Relatório consolidado | `C:\GPO-Assessment\GPO-Assessment-Report_<yyyyMMdd_HHmmss>.html` |
| Relatório nativo (GPMC) por GPO | `C:\GPO-Assessment\GPO-Exports\<GPOName>.html` |

O relatório consolidado é gravado em UTF-8. Os relatórios individuais são gerados por `Get-GPOReport -ReportType Html`.

## Análises realizadas

| Ref. | Análise | Detecção |
|---|---|---|
| A1 | Exportação individual | Relatório HTML nativo de cada GPO. |
| A2 | Mapa de links | Links por GPO (Domínio, OU, Site) com status Enabled/Enforced, via `Get-GPInheritance`. |
| A3 | GPOs vazias | Sem `ExtensionData` em Computer e User (com base no relatório XML). |
| A4 | GPOs sem link (com configuração) | Possuem configuração, mas não têm link. |
| A5 | Somente User (Computer habilitado) | Configurações apenas em User, com o nó Computer ainda habilitado. |
| A6 | Somente Computer (User habilitado) | Configurações apenas em Computer, com o nó User ainda habilitado. |
| A7 | Todas as configurações desabilitadas | `GpoStatus = AllSettingsDisabled`. |
| A8 | Filtros WMI | GPOs com filtro WMI associado. |
| A9 | SIDs não resolvidos | Entradas de delegação cujo trustee resolve apenas para SID. |
| A10 | GPC órfão sem GPT | Objeto GPC em `CN=Policies,CN=System` sem pasta correspondente no SYSVOL. |
| A11 | GPT órfão sem GPC | Pasta GUID no SYSVOL sem objeto GPC correspondente no AD. |
| A12 | Links entre domínios | Links apontando para um domínio diferente do domínio de origem da GPO. |
| A13 | Links enforced | Links com Enforced (No Override) ativo. |
| A15 | Links desabilitados | Links com `Link Enabled = No`. |
| A16 | Membros de GPCO | Membros de `Group Policy Creator Owners` (recursivo), via módulo `ActiveDirectory`. |

As referências A1-A16 preservam a numeração interna do script (`A14` foi incorporada à `A12`; não há seções `A0` ou `A14` independentes).

## Comportamento e escopo

### Fatos (comportamento do código)

- O script é somente leitura sobre o ambiente: usa apenas cmdlets `Get-*` e exportações; a única gravação ocorre em `C:\GPO-Assessment\`.
- Ele não executa `Set-GPO`, `Set-GPPermission` ou `Remove-GPO`, e não modifica SYSVOL/AD.
- O escopo de coleta das GPOs é o domínio atual (`Get-GPO -All -Domain <domain>`).
- Ele não enumera GPOs de outros domínios na floresta. Os sites são lidos no escopo da floresta.
- `$ErrorActionPreference = "SilentlyContinue"` é definido globalmente.
- Falhas em coletas individuais são suprimidas e podem resultar em dados incompletos sem erro visível no console.

### Inferências (classificação e heurísticas, não fatos da plataforma)

- A classificação de severidade (risco/integridade, higiene/precedência, inventário) é uma convenção editorial deste relatório para priorização.
- Ela **não** corresponde a nenhuma severidade formal definida pela Microsoft.
- A detecção de links de OU entre domínios (A12) usa comparação por expressão regular sobre o Distinguished Name.
- Trata-se de uma heurística e pode produzir falsos positivos/negativos em topologias com nomes de domínio semelhantes.

## Fora de escopo (complementos recomendados)

A versão `1.0` **não** avalia os itens abaixo, que exigem tratamento separado:

- Adequação do security filtering após MS16-072 (presença de `Authenticated Users` / `Domain Computers` com permissão de leitura).  
  Ref.: Microsoft, *Can't apply user Group Policy settings if computer objects don't have GPO Read permissions*.
- Presença de credenciais em Group Policy Preferences (`cpassword` em arquivos XML no SYSVOL).  
  Ref.: Microsoft Security Bulletin `MS14-025`.
- Comparação de conteúdo com security baselines (Microsoft Security Compliance Toolkit, CIS Benchmarks, DISA STIG).  
  Ref.: Microsoft Security Compliance Toolkit.
- Análise em nível de configuração (settings individuais), ADMX Central Store e consistência de versão entre AD/SYSVOL.

## Aviso legal e suporte

**SEM SUPORTE.** Este script é fornecido **"NO ESTADO EM QUE SE ENCONTRA"**, sem garantia de qualquer tipo, expressa ou implícita, incluindo — sem limitação — garantias de adequação a uma finalidade específica, exatidão ou ausência de erros.

O criador **não fornece** suporte, manutenção, correções ou atualizações de qualquer tipo. Não há canal de contato, SLA ou compromisso de resposta.

A execução é de inteira responsabilidade do usuário. Valide o script em ambiente de laboratório antes de qualquer uso em produção. O criador não se responsabiliza por danos, perda de dados ou impacto operacional decorrente do uso.

## Referências

- Microsoft Learn — módulo `GroupPolicy` (`Get-GPO`, `Get-GPOReport`, `Get-GPInheritance`, `Get-GPPermission`).
- Microsoft Learn — módulo `ActiveDirectory` (`Get-ADOrganizationalUnit`, `Get-ADGroup`, `Get-ADGroupMember`).
- Microsoft — MS16-072 e Security Compliance Toolkit (URLs citadas na seção **Fora de escopo**).
