#Requires -RunAsAdministrator
<#
.SYNOPSIS
    
    Avaliação Completa de GPOs do Active Directory

.DESCRIPTION

    Script for the comprehensive analysis of Group Policy Objects (GPOs) in an Active Directory domain.

    Generates a complete HTML report in C:\GPO-Assessment\.

.DISCLAIMER
    
    This sample script is not supported by its creator or by any Microsoft support program or service.

    The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

    The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.

.NOTES

    Author: Ándré Martins
    Version: 1.0
    Requirement: Run as Domain Administrator

##################################################################################################
#>

# ============================================================
#  CONFIGURAÇÃO INICIAL
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

# ── Cores para console ──────────────────────────────────────

function Write-Info    ($m) { Write-Host "  [INFO]  $m" -ForegroundColor Cyan }
function Write-OK      ($m) { Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Write-Warn    ($m) { Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Write-Fail    ($m) { Write-Host "  [ERRO]  $m" -ForegroundColor Red }
function Write-Section ($m) { Write-Host "`n══════════════════════════════════════════" -ForegroundColor DarkCyan
                               Write-Host "  $m" -ForegroundColor White
                               Write-Host "══════════════════════════════════════════" -ForegroundColor DarkCyan }

Write-Host @"

  ╔═══════════════════════════════════════════════════════╗
  ║        GPO ASSESSMENT - Active Directory              ║
  ║                                                       ║
  ╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ── 1. Detectar domínio ──────────────────────────────────────

Write-Section "PRÉ-REQUISITOS"
try {
    $DomainObj  = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    $DomainFQDN = $DomainObj.Name
    $DomainDN   = "DC=" + ($DomainFQDN -replace "\.", ",DC=")
    Write-OK "Domínio detectado: $DomainFQDN"
    Write-OK "Distinguished Name: $DomainDN"
} catch {
    Write-Fail "Não foi possível detectar o domínio. Certifique-se de executar em uma máquina ingressada no domínio."
    exit 1
}

# ── 2. Diretório de saída ────────────────────────────────────

$OutputDir    = "C:\GPO-Assessment"
$GPOExportDir = "$OutputDir\GPO-Exports"
$ReportFile   = "$OutputDir\GPO-Assessment-Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
$Timestamp    = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

foreach ($dir in @($OutputDir, $GPOExportDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Diretório criado: $dir"
    } else {
        Write-Info "Diretório já existe: $dir"
    }
}

# ── 3. Módulo GroupPolicy ────────────────────────────────────

if (-not (Get-Module -Name GroupPolicy -ErrorAction SilentlyContinue)) {
    try {
        Import-Module GroupPolicy -Force -ErrorAction Stop
        Write-OK "Módulo GroupPolicy importado com sucesso."
    } catch {
        Write-Fail "Falha ao importar o módulo GroupPolicy: $_"
        Write-Warn "Instale o RSAT: Add-WindowsFeature GPMC  -or-  RSAT via Configurações do Windows."
        exit 1
    }
} else {
    Write-OK "Módulo GroupPolicy já está importado."
}

# Verificar módulo ActiveDirectory

if (-not (Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
    try {
        Import-Module ActiveDirectory -Force -ErrorAction Stop
        Write-OK "Módulo ActiveDirectory importado com sucesso."
    } catch {
        Write-Warn "Módulo ActiveDirectory não disponível. Algumas verificações serão limitadas."
    }
}

# ============================================================
#  COLETA DE DADOS                                           
# ============================================================

Write-Section "COLETANDO DADOS DE GPOs"

Write-Info "Obtendo lista de todas as GPOs..."
try {
    $AllGPOs = Get-GPO -All -Domain $DomainFQDN -ErrorAction Stop
    Write-OK "Total de GPOs encontradas: $($AllGPOs.Count)"
} catch {
    Write-Fail "Erro ao obter GPOs: $_"
    exit 1
}

# ── Exportar relatório XML de cada GPO (para análise interna) ──

Write-Info "Gerando relatório XML de cada GPO (para análise)..."
$GPOReports = @{}
foreach ($gpo in $AllGPOs) {
    try {
        $xmlContent = Get-GPOReport -Guid $gpo.Id -ReportType Xml -Domain $DomainFQDN -ErrorAction Stop
        $GPOReports[$gpo.Id.ToString()] = [xml]$xmlContent
    } catch {
        Write-Warn "Não foi possível obter relatório XML da GPO: $($gpo.DisplayName)"
    }
}

# ── ATIVIDADE 1 – Exportar HTML individual de cada GPO ────────

Write-Section "ATIVIDADE 1 – Exportando HTML individual de cada GPO"
$ExportCount = 0
foreach ($gpo in $AllGPOs) {
    $safeName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'
    $htmlPath = "$GPOExportDir\$safeName.html"
    try {
        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $htmlPath -Domain $DomainFQDN -ErrorAction Stop
        $ExportCount++
    } catch {
        Write-Warn "Falha ao exportar HTML da GPO '$($gpo.DisplayName)': $_"
    }
}
Write-OK "GPOs exportadas em HTML: $ExportCount de $($AllGPOs.Count)"

# ── Obter todos os links via Get-ADOrganizationalUnit / GPInheritance ──

Write-Info "Mapeando links de GPOs (OUs, Domínio, Sites)..."
$GPOLinks = @{}   # GUID → lista de locais linkados

# Links no nível do Domínio

try {
    $DomainLinks = Get-GPInheritance -Target $DomainDN -Domain $DomainFQDN -ErrorAction Stop
    foreach ($link in $DomainLinks.GpoLinks) {
        $guid = $link.GpoId.ToString().ToUpper()
        if (-not $GPOLinks.ContainsKey($guid)) { $GPOLinks[$guid] = @() }
        $GPOLinks[$guid] += [PSCustomObject]@{
            Location    = $DomainFQDN
            Type        = "Domain"
            Enabled     = $link.Enabled
            Enforced    = $link.Enforced
            Order       = $link.Order
        }
    }
} catch { Write-Warn "Não foi possível ler links do nível de Domínio." }

# Links em OUs

try {
    $AllOUs = Get-ADOrganizationalUnit -Filter * -Server $DomainFQDN -ErrorAction Stop
    foreach ($ou in $AllOUs) {
        try {
            $ouLinks = Get-GPInheritance -Target $ou.DistinguishedName -Domain $DomainFQDN -ErrorAction Stop
            foreach ($link in $ouLinks.GpoLinks) {
                $guid = $link.GpoId.ToString().ToUpper()
                if (-not $GPOLinks.ContainsKey($guid)) { $GPOLinks[$guid] = @() }
                $GPOLinks[$guid] += [PSCustomObject]@{
                    Location    = $ou.DistinguishedName
                    Type        = "OU"
                    Enabled     = $link.Enabled
                    Enforced    = $link.Enforced
                    Order       = $link.Order
                }
            }
        } catch {}
    }
    Write-OK "OUs processadas: $($AllOUs.Count)"
} catch { Write-Warn "Módulo ActiveDirectory indisponível; links de OU podem estar incompletos." }

# Links em Sites

try {
    $Sites = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites
    foreach ($site in $Sites) {
        $siteDN = "CN=$($site.Name),CN=Sites,CN=Configuration,$DomainDN"
        try {
            $siteLinks = Get-GPInheritance -Target $siteDN -Domain $DomainFQDN -ErrorAction Stop
            foreach ($link in $siteLinks.GpoLinks) {
                $guid = $link.GpoId.ToString().ToUpper()
                if (-not $GPOLinks.ContainsKey($guid)) { $GPOLinks[$guid] = @() }
                $GPOLinks[$guid] += [PSCustomObject]@{
                    Location = $site.Name
                    Type     = "Site"
                    Enabled  = $link.Enabled
                    Enforced = $link.Enforced
                    Order    = $link.Order
                }
            }
        } catch {}
    }
} catch {}

# ── Dados do SYSVOL e AD (para GPOs órfãs) ───────────────────

Write-Info "Verificando integridade SYSVOL vs Active Directory..."

# GPCs no AD

$GPCGuids = @()
try {
    $GPCContainer = [ADSI]"LDAP://CN=Policies,CN=System,$DomainDN"
    foreach ($child in $GPCContainer.Children) {
        $cn = $child.Properties["cn"][0]
        if ($cn -match '^\{[0-9A-Fa-f\-]{36}\}$') {
            $GPCGuids += $cn.Trim('{}').ToUpper()
        }
    }
    Write-OK "GPCs no Active Directory: $($GPCGuids.Count)"
} catch { Write-Warn "Não foi possível ler GPCs do Active Directory." }

# GPTs no SYSVOL

$SysvolPath = "\\$DomainFQDN\SYSVOL\$DomainFQDN\Policies"
$GPTGuids   = @()
if (Test-Path $SysvolPath) {
    $GPTGuids = (Get-ChildItem -Path $SysvolPath -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '^\{[0-9A-Fa-f\-]{36}\}$' } |
                 ForEach-Object { $_.Name.Trim('{}').ToUpper() })
    Write-OK "GPTs no SYSVOL: $($GPTGuids.Count)"
} else {
    Write-Warn "Caminho SYSVOL não acessível: $SysvolPath"
}

$KnownGUIDs = $AllGPOs | ForEach-Object { $_.Id.ToString().ToUpper() }

# ============================================================
#  ANÁLISES ESPECÍFICAS
# ============================================================

Write-Section "EXECUTANDO ANÁLISES"

# ── A2 – Links de cada GPO ───────────────────────────────────

$A2_GPOLinks = foreach ($gpo in $AllGPOs) {
    $guid  = $gpo.Id.ToString().ToUpper()
    $links = if ($GPOLinks.ContainsKey($guid)) { $GPOLinks[$guid] } else { @() }
    [PSCustomObject]@{
        GPOName    = $gpo.DisplayName
        GUID       = $gpo.Id
        LinkCount  = $links.Count
        Links      = $links
    }
}

# ── A3 – GPOs Vazias ─────────────────────────────────────────

Write-Info "A3 – Detectando GPOs vazias..."
$A3_EmptyGPOs = foreach ($gpo in $AllGPOs) {
    $xml = $GPOReports[$gpo.Id.ToString()]
    $hasComputer = $false
    $hasUser     = $false
    if ($xml) {
        $compSettings = $xml.GPO.Computer.ExtensionData
        $userSettings = $xml.GPO.User.ExtensionData
        $hasComputer  = ($null -ne $compSettings -and $compSettings.Count -gt 0)
        $hasUser      = ($null -ne $userSettings -and $userSettings.Count -gt 0)
    }
    if (-not $hasComputer -and -not $hasUser) {
        [PSCustomObject]@{ GPOName = $gpo.DisplayName; GUID = $gpo.Id; Status = $gpo.GpoStatus; Created = $gpo.CreationTime; Modified = $gpo.ModificationTime }
    }
}
Write-OK "GPOs vazias encontradas: $(@($A3_EmptyGPOs).Count)"

# ── A4 – GPOs sem links (sem uso) ───────────────────────────

Write-Info "A4 – Detectando GPOs sem links (sem uso)..."
$A4_UnlinkedGPOs = foreach ($gpo in $AllGPOs) {
    $guid = $gpo.Id.ToString().ToUpper()
    if (-not $GPOLinks.ContainsKey($guid) -or $GPOLinks[$guid].Count -eq 0) {
        $xml = $GPOReports[$gpo.Id.ToString()]
        $hasComputer = $false
        $hasUser     = $false
        if ($xml) {
            $hasComputer = ($null -ne $xml.GPO.Computer.ExtensionData -and $xml.GPO.Computer.ExtensionData.Count -gt 0)
            $hasUser     = ($null -ne $xml.GPO.User.ExtensionData     -and $xml.GPO.User.ExtensionData.Count     -gt 0)
        }
        if ($hasComputer -or $hasUser) {
            [PSCustomObject]@{ GPOName = $gpo.DisplayName; GUID = $gpo.Id; Status = $gpo.GpoStatus; Created = $gpo.CreationTime; Modified = $gpo.ModificationTime }
        }
    }
}
Write-OK "GPOs sem links encontradas: $(@($A4_UnlinkedGPOs).Count)"

# ── A5 – Somente User Config, Computer habilitado ─────────────

Write-Info "A5 – GPOs somente com User Config mas Computer Session Enable..."
$A5_UserOnlyGPOs = foreach ($gpo in $AllGPOs) {
    # GpoStatus: AllSettingsEnabled | ComputerSettingsDisabled | UserSettingsDisabled | AllSettingsDisabled
    if ($gpo.GpoStatus -eq "AllSettingsEnabled" -or $gpo.GpoStatus -eq "UserSettingsDisabled") {
        $xml = $GPOReports[$gpo.Id.ToString()]
        if ($xml) {
            $hasComputer = ($null -ne $xml.GPO.Computer.ExtensionData -and $xml.GPO.Computer.ExtensionData.Count -gt 0)
            $hasUser     = ($null -ne $xml.GPO.User.ExtensionData     -and $xml.GPO.User.ExtensionData.Count     -gt 0)
            if ($hasUser -and -not $hasComputer -and $gpo.GpoStatus -ne "ComputerSettingsDisabled") {
                [PSCustomObject]@{
                    GPOName  = $gpo.DisplayName
                    GUID     = $gpo.Id
                    Status   = $gpo.GpoStatus
                    Recomend = "Desabilitar 'Computer Configuration' (Computer Settings Disabled)"
                }
            }
        }
    }
}
Write-OK "GPOs com somente User Config e Computer habilitado: $(@($A5_UserOnlyGPOs).Count)"

# ── A6 – Somente Computer Config, User Enable ─────────────

Write-Info "A6 – GPOs somente com Computer Config mas User Session Enable..."
$A6_ComputerOnlyGPOs = foreach ($gpo in $AllGPOs) {
    if ($gpo.GpoStatus -eq "AllSettingsEnabled" -or $gpo.GpoStatus -eq "ComputerSettingsDisabled") {
        $xml = $GPOReports[$gpo.Id.ToString()]
        if ($xml) {
            $hasComputer = ($null -ne $xml.GPO.Computer.ExtensionData -and $xml.GPO.Computer.ExtensionData.Count -gt 0)
            $hasUser     = ($null -ne $xml.GPO.User.ExtensionData     -and $xml.GPO.User.ExtensionData.Count     -gt 0)
            if ($hasComputer -and -not $hasUser -and $gpo.GpoStatus -ne "UserSettingsDisabled") {
                [PSCustomObject]@{
                    GPOName  = $gpo.DisplayName
                    GUID     = $gpo.Id
                    Status   = $gpo.GpoStatus
                    Recomend = "Desabilitar 'User Configuration' (User Settings Disabled)"
                }
            }
        }
    }
}
Write-OK "GPOs com somente Computer Config e User habilitado: $(@($A6_ComputerOnlyGPOs).Count)"

# ── A7 – GPOs com "All Settings Disabled" ─────────────────────

Write-Info "A7 – GPOs com status 'All Settings Disabled'..."
$A7_AllDisabledGPOs = $AllGPOs | Where-Object { $_.GpoStatus -eq "AllSettingsDisabled" } |
    Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime
Write-OK "GPOs com All Settings Disabled: $(@($A7_AllDisabledGPOs).Count)"

# ── A8 – GPOs com Filtro WMI ──────────────────────────────────

Write-Info "A8 – Detectando GPOs com filtros WMI..."
$A8_WMIFilterGPOs = foreach ($gpo in $AllGPOs) {
    if ($null -ne $gpo.WmiFilter -and $gpo.WmiFilter.Name -ne "") {
        [PSCustomObject]@{
            GPOName         = $gpo.DisplayName
            GUID            = $gpo.Id
            WMIFilterName   = $gpo.WmiFilter.Name
            WMIFilterDesc   = $gpo.WmiFilter.Description
        }
    }
}
Write-OK "GPOs com filtros WMI: $(@($A8_WMIFilterGPOs).Count)"

# ── A9 – GPOs com SIDs não resolvidos na Delegação ───────────

Write-Info "A9 – Verificando entradas de delegação com SIDs não resolvidos..."
$A9_UnresolvedSIDGPOs = foreach ($gpo in $AllGPOs) {
    try {
        $acl = Get-GPPermission -Guid $gpo.Id -All -Domain $DomainFQDN -ErrorAction Stop
        $unresolvedEntries = @()
        foreach ($entry in $acl) {
            $trustee = $entry.Trustee
            # SID puro: começa com S- e não tem nome legível resolvido
            if ($trustee.Sid -and
                ($trustee.Name -match '^S-\d+-\d+' -or
                 [string]::IsNullOrWhiteSpace($trustee.Name) -or
                 $trustee.Name -eq $trustee.Sid.ToString())) {
                $unresolvedEntries += "$($trustee.Sid) [$($entry.Permission)]"
            }
        }
        if ($unresolvedEntries.Count -gt 0) {
            [PSCustomObject]@{
                GPOName    = $gpo.DisplayName
                GUID       = $gpo.Id
                Unresolved = ($unresolvedEntries -join "; ")
            }
        }
    } catch {}
}
Write-OK "GPOs com SIDs não resolvidos: $(@($A9_UnresolvedSIDGPOs).Count)"

# ── A10 – GPOs Órfãs: GPC no AD sem GPT no SYSVOL ─────────────

Write-Info "A10 – GPOs órfãs: GPC no AD sem GPT no SYSVOL..."
$A10_OrphanGPC = foreach ($gpcGuid in $GPCGuids) {
    if ($gpcGuid -notin $GPTGuids) {
        $gpoName = ($AllGPOs | Where-Object { $_.Id.ToString().ToUpper() -eq $gpcGuid } | Select-Object -First 1).DisplayName
        [PSCustomObject]@{
            GUID    = $gpcGuid
            GPOName = if ($gpoName) { $gpoName } else { "(não encontrada nas GPOs)" }
            Issue   = "GPC existe no AD mas não há pasta correspondente no SYSVOL"
        }
    }
}
Write-OK "GPOs órfãs (GPC sem GPT): $(@($A10_OrphanGPC).Count)"

# ── A11 – GPOs Órfãs: GPT no SYSVOL sem GPC no AD ─────────────

Write-Info "A11 – GPOs órfãs: GPT no SYSVOL sem GPC no AD..."
$A11_OrphanGPT = foreach ($gptGuid in $GPTGuids) {
    if ($gptGuid -notin $GPCGuids) {
        [PSCustomObject]@{
            GUID    = $gptGuid
            GPOName = "(sem registro no AD)"
            Path    = "$SysvolPath\{$gptGuid}"
            Issue   = "Pasta existe no SYSVOL mas não há GPC correspondente no AD"
        }
    }
}
Write-OK "GPOs órfãs (GPT sem GPC): $(@($A11_OrphanGPT).Count)"

# ── A12/A14 – GPOs linkadas entre domínios diferentes ─────────

Write-Info "A12/A14 – Verificando links entre domínios..."
$A12_CrossDomainLinks = foreach ($gpo in $AllGPOs) {
    $guid = $gpo.Id.ToString().ToUpper()
    if ($GPOLinks.ContainsKey($guid)) {
        foreach ($link in $GPOLinks[$guid]) {
            # Link fora do domínio atual
            if ($link.Type -eq "Domain" -and $link.Location -ne $DomainFQDN) {
                [PSCustomObject]@{
                    GPOName       = $gpo.DisplayName
                    GUID          = $gpo.Id
                    GPODomain     = $DomainFQDN
                    LinkedTo      = $link.Location
                    Type          = $link.Type
                    LinkEnabled   = $link.Enabled
                    Enforced      = $link.Enforced
                }
            }
            
            # Verifica se o Distinguished Name do link contém DC diferente do domínio atual

            if ($link.Type -eq "OU" -and $link.Location -notmatch ($DomainDN -replace ',', ',?')) {
                [PSCustomObject]@{
                    GPOName       = $gpo.DisplayName
                    GUID          = $gpo.Id
                    GPODomain     = $DomainFQDN
                    LinkedTo      = $link.Location
                    Type          = "Cross-Domain OU Link"
                    LinkEnabled   = $link.Enabled
                    Enforced      = $link.Enforced
                }
            }
        }
    }
}
Write-OK "Links entre domínios detectados: $(@($A12_CrossDomainLinks).Count)"

# ── A13 – GPOs com "Enforced" ativado ─────────────────────────

Write-Info "A13 – Detectando GPOs com Enforced ativado..."
$A13_EnforcedGPOs = foreach ($gpo in $AllGPOs) {
    $guid = $gpo.Id.ToString().ToUpper()
    if ($GPOLinks.ContainsKey($guid)) {
        $enforcedLinks = $GPOLinks[$guid] | Where-Object { $_.Enforced -eq $true }
        if ($enforcedLinks) {
            foreach ($eLink in $enforcedLinks) {
                [PSCustomObject]@{
                    GPOName   = $gpo.DisplayName
                    GUID      = $gpo.Id
                    Location  = $eLink.Location
                    Type      = $eLink.Type
                    Enforced  = $eLink.Enforced
                    Enabled   = $eLink.Enabled
                }
            }
        }
    }
}
Write-OK "Links com Enforced ativado: $(@($A13_EnforcedGPOs).Count)"

# ── A15 – GPOs com Link Enabled = No ──────────────────────────

Write-Info "A15 – Detectando links com 'Link Enabled' = No..."
$A15_DisabledLinks = foreach ($gpo in $AllGPOs) {
    $guid = $gpo.Id.ToString().ToUpper()
    if ($GPOLinks.ContainsKey($guid)) {
        $disabledLinks = $GPOLinks[$guid] | Where-Object { $_.Enabled -eq $false }
        foreach ($dLink in $disabledLinks) {
            [PSCustomObject]@{
                GPOName  = $gpo.DisplayName
                GUID     = $gpo.Id
                Location = $dLink.Location
                Type     = $dLink.Type
                Enforced = $dLink.Enforced
                Enabled  = "Não"
            }
        }
    }
}
Write-OK "Links desabilitados encontrados: $(@($A15_DisabledLinks).Count)"

# ── A16 – Membros do grupo "Group Policy Creator Owners" ──────

Write-Info "A16 – Obtendo membros de 'Group Policy Creator Owners'..."
$A16_GPCOMembers = @()
try {
    $gpcGroup  = Get-ADGroup -Filter { Name -eq "Group Policy Creator Owners" } -Server $DomainFQDN -ErrorAction Stop
    $gpcMembers = Get-ADGroupMember -Identity $gpcGroup -Recursive -Server $DomainFQDN -ErrorAction Stop
    $A16_GPCOMembers = foreach ($member in $gpcMembers) {
        [PSCustomObject]@{
            Name           = $member.Name
            SamAccountName = $member.SamAccountName
            ObjectClass    = $member.objectClass
            DistinguishedName = $member.DistinguishedName
        }
    }
    Write-OK "Membros encontrados: $($A16_GPCOMembers.Count)"
} catch {
    Write-Warn "Não foi possível obter membros do grupo 'Group Policy Creator Owners': $_"
}

# ============================================================
#  GERAÇÃO DO RELATÓRIO HTML
# ============================================================

Write-Section "GERANDO RELATÓRIO HTML"

# ── Funções auxiliares de HTML ───────────────────────────────

Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

# Colunas técnicas renderizadas em fonte monoespaçada (GUIDs, DNs, SIDs)

$MonoColumns = @('GUID','Id','DistinguishedName','SID','Sid','Unresolved','Path')

function Get-Sev {
    param([int]$Count, [string]$Class = 'risk')
    if ($Class -eq 'info') { return 'info' }
    if ($Count -eq 0)      { return 'ok' }
    if ($Class -eq 'risk') { return 'crit' } else { return 'warn' }
}

function Get-Chip {
    # Chip de severidade exibido no cabeçalho de cada seção
    param([int]$Count, [string]$Class = 'risk')
    $sev  = Get-Sev $Count $Class
    $word = if ($Count -eq 1) { 'achado' } else { 'achados' }
    switch ($sev) {
        'info' { "<span class='chip chip-info'>$Count</span>" }
        'ok'   { "<span class='chip chip-ok'>0 achados</span>" }
        default { "<span class='chip chip-$sev'>$Count $word</span>" }
    }
}

function Format-Cell {
    param($name, $value)
    if ($null -eq $value) { $value = "" }
    $enc = [System.Web.HttpUtility]::HtmlEncode([string]$value)
    if ($MonoColumns -contains $name) { return "<code class='mono'>$enc</code>" }
    return $enc
}

function ConvertTo-HtmlTable {
    param(
        [array]$Data,
        [string]$EmptyMessage = "Nenhum item encontrado."
    )
    if (-not $Data -or @($Data).Count -eq 0) {
        return "<p class='ok-note'>$EmptyMessage</p>"
    }
    $props  = $Data[0].PSObject.Properties.Name
    $header = ($props | ForEach-Object { "<th>$([System.Web.HttpUtility]::HtmlEncode($_))</th>" }) -join ''
    $rows   = foreach ($row in $Data) {
        $cells = ($props | ForEach-Object { "<td>$(Format-Cell $_ $row.$_)</td>" }) -join ''
        "<tr>$cells</tr>"
    }
    return "<div class='table-wrap'><table><thead><tr>$header</tr></thead><tbody>$($rows -join '')</tbody></table></div>"
}

# ── Tabela de Links (renderização dedicada) ──────────────────
$LinkRows = foreach ($item in $A2_GPOLinks) {
    $destinos = if ($item.Links.Count -eq 0) {
        "<span class='muted-txt'>Sem links</span>"
    } else {
        ($item.Links | ForEach-Object {
            $enf  = if ($_.Enforced)     { " <span class='tag tag-enf'>ENFORCED</span>" } else { "" }
            $dis  = if (-not $_.Enabled) { " <span class='tag tag-dis'>DISABLED</span>" } else { "" }
            "<div><span class='loc-type'>$($_.Type)</span>$([System.Web.HttpUtility]::HtmlEncode($_.Location))$enf$dis</div>"
        }) -join ""
    }
    $badge = if ($item.LinkCount -eq 0) { "<span class='chip chip-warn'>0</span>" } else { "<span class='chip chip-info'>$($item.LinkCount)</span>" }
    "<tr>
      <td>$([System.Web.HttpUtility]::HtmlEncode($item.GPOName))</td>
      <td><code class='mono'>$($item.GUID)</code></td>
      <td style='text-align:center'>$badge</td>
      <td class='loc-list'>$destinos</td>
    </tr>"
}
$LinksTableHtml = "<div class='table-wrap'><table><thead><tr><th>Nome da GPO</th><th>GUID</th><th>Links</th><th>Destinos</th></tr></thead><tbody>$($LinkRows -join '')</tbody></table></div>"

# ── Painel de postura (agregação de severidade) ──────────────

$RiskCount = @($A9_UnresolvedSIDGPOs).Count + @($A10_OrphanGPC).Count + @($A11_OrphanGPT).Count + @($A12_CrossDomainLinks).Count
$HygCount  = @($A3_EmptyGPOs).Count + @($A4_UnlinkedGPOs).Count + @($A5_UserOnlyGPOs).Count + @($A6_ComputerOnlyGPOs).Count + @($A7_AllDisabledGPOs).Count + @($A13_EnforcedGPOs).Count

if     ($RiskCount -gt 0) { $PostureSev = 'crit'; $PostureLabel = 'Requer atenção - Achados de integridade / segurança' }
elseif ($HygCount  -gt 0) { $PostureSev = 'warn'; $PostureLabel = 'Higiene pendente' }
else                      { $PostureSev = 'ok';   $PostureLabel = 'Sem achados de risco' }

# ── Métricas do sumário (cor = severidade, não decoração) ────

$Tiles = @(
    @{ L='Total de GPOs';            V=@($AllGPOs).Count;             C='info'    }
    @{ L='GPOs vazias';              V=@($A3_EmptyGPOs).Count;        C='hygiene' }
    @{ L='Sem links (com config)';   V=@($A4_UnlinkedGPOs).Count;     C='hygiene' }
    @{ L='Só User (Computer ON)';    V=@($A5_UserOnlyGPOs).Count;     C='hygiene' }
    @{ L='Só Computer (User ON)';    V=@($A6_ComputerOnlyGPOs).Count; C='hygiene' }
    @{ L='All Settings Disabled';    V=@($A7_AllDisabledGPOs).Count;  C='hygiene' }
    @{ L='Links Enforced';           V=@($A13_EnforcedGPOs).Count;    C='hygiene' }
    @{ L='SIDs não resolvidos';      V=@($A9_UnresolvedSIDGPOs).Count;C='risk'    }
    @{ L='Órfãs (GPC sem GPT)';      V=@($A10_OrphanGPC).Count;       C='risk'    }
    @{ L='Órfãs (GPT sem GPC)';      V=@($A11_OrphanGPT).Count;       C='risk'    }
    @{ L='Links cross-domain';       V=@($A12_CrossDomainLinks).Count;C='risk'    }
    @{ L='Filtros WMI';              V=@($A8_WMIFilterGPOs).Count;    C='info'    }
    @{ L='Links desabilitados';      V=@($A15_DisabledLinks).Count;   C='info'    }
    @{ L='Membros GPCO';             V=@($A16_GPCOMembers).Count;     C='info'    }
)
$TilesHtml = foreach ($t in $Tiles) {
    $sev = Get-Sev $t.V $t.C
    "<div class='tile sev-$sev'><div class='num'>$($t.V)</div><div class='lbl'>$($t.L)</div></div>"
}

# ── Montar HTML Final ─────────────────────────────────────────

$HtmlContent = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GPO Assessment — $DomainFQDN</title>
<style>
  :root{
    --ink:#10151c; --slate:#43505f; --muted:#6b7885;
    --paper:#f5f6f8; --surface:#ffffff; --line:#e4e8ed; --line-strong:#cfd6de;
    --accent:#235e7a; --accent-soft:#eaf1f5;
    --crit:#b4232a; --crit-soft:#fbeaea;
    --warn:#8a5a08; --warn-soft:#fbf1de;
    --ok:#256d45;   --ok-soft:#e7f2ec;
    --info:#48566a; --info-soft:#eef1f4;
    --mono:"Cascadia Code","Cascadia Mono",Consolas,ui-monospace,monospace;
    --sans:"Segoe UI Variable","Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif;
  }
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
  html{scroll-behavior:smooth}
  body{font-family:var(--sans);font-size:13px;line-height:1.5;color:var(--ink);background:var(--paper);-webkit-font-smoothing:antialiased}
  code.mono,.mono{font-family:var(--mono);font-size:.82em;color:var(--slate);word-break:break-all}
  .muted-txt{color:var(--muted)}
  a:focus-visible,summary:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px}

  /* Masthead */
  .masthead{background:var(--ink);color:#fff;padding:34px 40px 28px}
  .masthead .kicker{font-size:11px;letter-spacing:.24em;text-transform:uppercase;color:#8697a6;font-weight:600}
  .masthead h1{font-size:27px;font-weight:700;letter-spacing:-.01em;margin-top:9px}
  .masthead .meta{margin-top:16px;display:flex;flex-wrap:wrap;gap:6px 28px;font-size:12.5px;color:#c3cdd6}
  .masthead .meta b{color:#fff;font-weight:600}

  /* Posture strip */
  .posture{display:flex;flex-wrap:wrap;align-items:center;gap:16px 24px;padding:15px 40px;background:var(--surface);border-bottom:1px solid var(--line)}
  .verdict{display:flex;align-items:center;gap:10px;font-weight:700;font-size:14px}
  .verdict .dot{width:11px;height:11px;border-radius:50%;flex:none}
  .verdict.sev-crit{color:var(--crit)} .verdict.sev-crit .dot{background:var(--crit)}
  .verdict.sev-warn{color:var(--warn)} .verdict.sev-warn .dot{background:var(--warn)}
  .verdict.sev-ok{color:var(--ok)}     .verdict.sev-ok .dot{background:var(--ok)}
  .legend{display:flex;gap:16px;margin-left:auto;font-size:11.5px;color:var(--muted)}
  .legend span{display:flex;align-items:center;gap:6px}
  .legend i{width:9px;height:9px;border-radius:50%;display:inline-block}
  .lg-risk{background:var(--crit)} .lg-hyg{background:var(--warn)} .lg-info{background:var(--line-strong)}

  /* Nav */
  .nav{position:sticky;top:0;z-index:30;background:rgba(255,255,255,.93);backdrop-filter:blur(6px);border-bottom:1px solid var(--line);padding:9px 40px;display:flex;flex-wrap:wrap;gap:6px}
  .nav a{font-size:11.5px;color:var(--slate);padding:4px 10px;border-radius:5px;border:1px solid transparent;text-decoration:none}
  .nav a:hover{color:var(--accent);border-color:var(--line-strong);background:var(--surface)}

  .wrap{max-width:1180px;margin:0 auto;padding:30px 40px 20px}
  .block-title{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);font-weight:600;margin:6px 0 14px}

  /* Summary tiles */
  .tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(158px,1fr));gap:12px;margin-bottom:14px}
  .tile{position:relative;background:var(--surface);border:1px solid var(--line);border-radius:9px;padding:15px 16px 14px}
  .tile::before{content:"";position:absolute;left:0;top:14px;bottom:14px;width:3px;border-radius:3px;background:var(--line-strong)}
  .tile.sev-crit::before{background:var(--crit)} .tile.sev-warn::before{background:var(--warn)}
  .tile.sev-ok::before{background:var(--ok)}     .tile.sev-info::before{background:var(--line-strong)}
  .tile .num{font-size:29px;font-weight:700;line-height:1;padding-left:11px;font-variant-numeric:tabular-nums;color:var(--ink)}
  .tile.sev-crit .num{color:var(--crit)} .tile.sev-warn .num{color:var(--warn)} .tile.sev-ok .num{color:var(--ok)}
  .tile .lbl{font-size:11px;color:var(--muted);margin-top:7px;padding-left:11px;line-height:1.35}

  .note{font-size:11.5px;color:var(--muted);border-left:2px solid var(--line-strong);padding-left:11px;margin-top:4px}

  /* Findings */
  .finding{background:var(--surface);border:1px solid var(--line);border-left:3px solid var(--line-strong);border-radius:9px;margin-bottom:15px;overflow:hidden}
  .finding.sev-crit{border-left-color:var(--crit)} .finding.sev-warn{border-left-color:var(--warn)}
  .finding.sev-ok{border-left-color:var(--ok)}     .finding.sev-info{border-left-color:var(--line-strong)}
  .finding>summary{list-style:none;cursor:pointer;display:flex;align-items:center;gap:13px;padding:15px 20px;user-select:none}
  .finding>summary::-webkit-details-marker{display:none}
  .finding>summary::after{content:"";margin-left:auto;width:7px;height:7px;border-right:2px solid var(--muted);border-bottom:2px solid var(--muted);transform:rotate(45deg);transition:transform .2s;flex:none}
  .finding[open]>summary::after{transform:rotate(-135deg)}
  .finding .ref{font-family:var(--mono);font-size:11px;color:var(--muted);font-weight:700;min-width:30px}
  .finding h2{font-size:15px;font-weight:600;flex:1}
  .finding .body{padding:0 20px 20px;border-top:1px solid var(--line)}
  .desc{font-size:12.5px;color:var(--slate);margin:15px 0;padding-left:12px;border-left:2px solid var(--accent-soft)}
  .desc strong{color:var(--ink)} .desc em{font-style:normal;color:var(--accent);font-weight:600}

  /* Chips & tags */
  .chip{font-size:11px;font-weight:600;padding:3px 11px;border-radius:20px;white-space:nowrap;font-variant-numeric:tabular-nums}
  .chip-crit{background:var(--crit-soft);color:var(--crit)}
  .chip-warn{background:var(--warn-soft);color:var(--warn)}
  .chip-ok{background:var(--ok-soft);color:var(--ok)}
  .chip-info{background:var(--info-soft);color:var(--info)}
  .tag{font-size:10px;font-weight:700;letter-spacing:.03em;padding:1px 6px;border-radius:4px}
  .tag-enf{background:var(--crit-soft);color:var(--crit)}
  .tag-dis{background:var(--warn-soft);color:var(--warn)}

  /* Tables */
  .table-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:8px}
  table{width:100%;border-collapse:collapse;font-size:12.5px}
  thead th{background:#eef1f4;color:var(--slate);text-align:left;font-weight:600;font-size:10.5px;letter-spacing:.04em;text-transform:uppercase;padding:9px 13px;border-bottom:1px solid var(--line-strong);white-space:nowrap}
  tbody td{padding:9px 13px;border-bottom:1px solid var(--line);vertical-align:top}
  tbody tr:last-child td{border-bottom:none}
  tbody tr:hover{background:var(--accent-soft)}
  .loc-list>div{padding:2px 0}
  .loc-type{font-family:var(--mono);font-size:10px;color:var(--accent);font-weight:700;margin-right:7px;text-transform:uppercase}

  .ok-note{font-size:12.5px;color:var(--ok);background:var(--ok-soft);border:1px solid #cfe6d9;border-radius:7px;padding:11px 14px;display:flex;gap:9px;align-items:center}
  .ok-note::before{content:"\2713";font-weight:700}

  .foot{border-top:1px solid var(--line);padding:22px 40px;font-size:11.5px;color:var(--muted);text-align:center;line-height:1.7}
  .foot strong{color:var(--slate)}

  @media (max-width:640px){
    .masthead,.posture,.nav,.wrap,.foot{padding-left:18px;padding-right:18px}
    .masthead h1{font-size:22px} .legend{margin-left:0}
  }
  @media (prefers-reduced-motion:reduce){*{transition:none!important;scroll-behavior:auto!important}}
  @media print{
    body{background:#fff;font-size:10.5px}
    .nav{display:none}
    .masthead{-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .tile,.chip,.tag,thead th,.finding{-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .finding{break-inside:avoid;box-shadow:none}
    .finding>summary::after{display:none}
    .finding .body{display:block!important}
  }
</style>
</head>
<body>

<div class="masthead">
  <div class="kicker">Avaliação de Group Policy · Active Directory - Criado por Ándré Martins</div>
  <h1>GPO Assessment Report</h1>
  <div class="meta">
    <span>Domínio&nbsp;&nbsp;<b>$DomainFQDN</b></span>
    <span>Gerado em&nbsp;&nbsp;<b>$Timestamp</b></span>
    <span>Total de GPOs&nbsp;&nbsp;<b>$($AllGPOs.Count)</b></span>
  </div>
</div>

<div class="posture">
  <div class="verdict sev-$PostureSev"><span class="dot"></span>$PostureLabel</div>
  <div class="legend">
    <span><i class="lg-risk"></i>Risco / integridade</span>
    <span><i class="lg-hyg"></i>Higiene / precedência</span>
    <span><i class="lg-info"></i>Inventário</span>
  </div>
</div>

<div class="nav">
  <a href="#sumario">Sumário</a>
  <a href="#links">Links</a>
  <a href="#vazias">Vazias</a>
  <a href="#sem-links">Sem links</a>
  <a href="#useronly">Só User</a>
  <a href="#componly">Só Computer</a>
  <a href="#alldisabled">All Disabled</a>
  <a href="#wmi">Filtros WMI</a>
  <a href="#sids">SIDs órfãos</a>
  <a href="#orfas-gpc">GPC sem GPT</a>
  <a href="#orfas-gpt">GPT sem GPC</a>
  <a href="#crossdomain">Cross-domain</a>
  <a href="#enforced">Enforced</a>
  <a href="#disabled-links">Links off</a>
  <a href="#gpco">GPCO</a>
</div>

<div class="wrap">

<!-- SUMÁRIO -->
<div id="sumario">
  <div class="block-title">Sumário executivo</div>
  <div class="tiles">$($TilesHtml -join "`n")</div>
  <p class="note">A classificação de severidade (risco / higiene / inventário) é uma convenção editorial deste relatório para priorização; não corresponde a uma severidade formal definida pela Microsoft. Ajuste conforme o contexto do ambiente.</p>
</div>

<div class="block-title" style="margin-top:26px">Achados detalhados</div>

<!-- A2 – LINKS -->
<details id="links" class="finding sev-info" open>
  <summary><span class="ref">A2</span><h2>Links de GPOs</h2><span class="chip chip-info">$($AllGPOs.Count) GPOs</span></summary>
  <div class="body">
    <p class="desc">Mapeamento de onde cada GPO é aplicada (OUs, Domínio, Sites), com status de link (<em>habilitado</em>) e <em>enforced</em>.</p>
    $LinksTableHtml
  </div>
</details>

<!-- A3 – VAZIAS -->
<details id="vazias" class="finding sev-$(Get-Sev @($A3_EmptyGPOs).Count 'hygiene')" open>
  <summary><span class="ref">A3</span><h2>GPOs vazias</h2>$(Get-Chip @($A3_EmptyGPOs).Count 'hygiene')</summary>
  <div class="body">
    <p class="desc">GPOs sem nenhuma configuração definida (nem em <em>Computer</em>, nem em <em>User Configuration</em>). Candidatas a remoção.</p>
    $(ConvertTo-HtmlTable -Data $A3_EmptyGPOs -EmptyMessage "Nenhuma GPO vazia encontrada.")
  </div>
</details>

<!-- A4 – SEM LINKS -->
<details id="sem-links" class="finding sev-$(Get-Sev @($A4_UnlinkedGPOs).Count 'hygiene')" open>
  <summary><span class="ref">A4</span><h2>GPOs com configurações mas sem links</h2>$(Get-Chip @($A4_UnlinkedGPOs).Count 'hygiene')</summary>
  <div class="body">
    <p class="desc">GPOs com configurações definidas, porém não vinculadas a nenhuma OU, domínio ou site. Não impactam o ambiente, mas indicam configuração inacabada ou obsoleta.</p>
    $(ConvertTo-HtmlTable -Data $A4_UnlinkedGPOs -EmptyMessage "Nenhuma GPO sem links encontrada.")
  </div>
</details>

<!-- A5 – USER ONLY -->
<details id="useronly" class="finding sev-$(Get-Sev @($A5_UserOnlyGPOs).Count 'hygiene')" open>
  <summary><span class="ref">A5</span><h2>Só User Config (nó Computer habilitado)</h2>$(Get-Chip @($A5_UserOnlyGPOs).Count 'hygiene')</summary>
  <div class="body">
    <p class="desc">GPOs com configurações apenas em <em>User Configuration</em>, mas com a seção <em>Computer Configuration</em> ainda habilitada. Recomenda-se definir o GPO Status como <strong>Computer Settings Disabled</strong> para otimizar o processamento.</p>
    $(ConvertTo-HtmlTable -Data $A5_UserOnlyGPOs -EmptyMessage "Nenhuma GPO com essa condição encontrada.")
  </div>
</details>

<!-- A6 – COMPUTER ONLY -->
<details id="componly" class="finding sev-$(Get-Sev @($A6_ComputerOnlyGPOs).Count 'hygiene')" open>
  <summary><span class="ref">A6</span><h2>Só Computer Config (nó User habilitado)</h2>$(Get-Chip @($A6_ComputerOnlyGPOs).Count 'hygiene')</summary>
  <div class="body">
    <p class="desc">GPOs com configurações apenas em <em>Computer Configuration</em>, mas com a seção <em>User Configuration</em> ainda habilitada. Recomenda-se definir o GPO Status como <strong>User Settings Disabled</strong>.</p>
    $(ConvertTo-HtmlTable -Data $A6_ComputerOnlyGPOs -EmptyMessage "Nenhuma GPO com essa condição encontrada.")
  </div>
</details>

<!-- A7 – ALL DISABLED -->
<details id="alldisabled" class="finding sev-$(Get-Sev @($A7_AllDisabledGPOs).Count 'hygiene')" open>
  <summary><span class="ref">A7</span><h2>GPOs com "All Settings Disabled"</h2>$(Get-Chip @($A7_AllDisabledGPOs).Count 'hygiene')</summary>
  <div class="body">
    <p class="desc">GPOs com <strong>GPO Status</strong> = <em>All Settings Disabled</em>. Completamente inativas mesmo quando vinculadas. Verifique se a inativação é intencional antes de remover.</p>
    $(ConvertTo-HtmlTable -Data ($A7_AllDisabledGPOs | Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime) -EmptyMessage "Nenhuma GPO com All Settings Disabled.")
  </div>
</details>

<!-- A8 – WMI FILTERS -->
<details id="wmi" class="finding sev-info" open>
  <summary><span class="ref">A8</span><h2>GPOs com filtros WMI</h2>$(Get-Chip @($A8_WMIFilterGPOs).Count 'info')</summary>
  <div class="body">
    <p class="desc">GPOs com filtros WMI associados. Filtros WMI impactam o desempenho do processamento de política e devem ser documentados e revisados periodicamente.</p>
    $(ConvertTo-HtmlTable -Data $A8_WMIFilterGPOs -EmptyMessage "Nenhuma GPO com filtro WMI encontrada.")
  </div>
</details>

<!-- A9 – SIDs NÃO RESOLVIDOS -->
<details id="sids" class="finding sev-$(Get-Sev @($A9_UnresolvedSIDGPOs).Count 'risk')" open>
  <summary><span class="ref">A9</span><h2>SIDs não resolvidos na delegação</h2>$(Get-Chip @($A9_UnresolvedSIDGPOs).Count 'risk')</summary>
  <div class="body">
    <p class="desc">GPOs cuja guia <strong>Delegation</strong> contém entradas cujo nome não pôde ser resolvido — exibindo apenas o SID. Indica objetos deletados ou problemas de confiança entre domínios.</p>
    $(ConvertTo-HtmlTable -Data $A9_UnresolvedSIDGPOs -EmptyMessage "Nenhuma GPO com SIDs não resolvidos encontrada.")
  </div>
</details>

<!-- A10 – ÓRFÃS GPC SEM GPT -->
<details id="orfas-gpc" class="finding sev-$(Get-Sev @($A10_OrphanGPC).Count 'risk')" open>
  <summary><span class="ref">A10</span><h2>Órfãs — GPC no AD sem GPT no SYSVOL</h2>$(Get-Chip @($A10_OrphanGPC).Count 'risk')</summary>
  <div class="body">
    <p class="desc">Objeto GPC (Group Policy Container) registrado em <strong>System/Policies</strong> no AD sem a pasta GPT correspondente no <strong>SYSVOL</strong>. Indica corrupção ou deleção parcial.</p>
    $(ConvertTo-HtmlTable -Data $A10_OrphanGPC -EmptyMessage "Nenhuma GPO órfã do tipo GPC sem GPT encontrada.")
  </div>
</details>

<!-- A11 – ÓRFÃS GPT SEM GPC -->
<details id="orfas-gpt" class="finding sev-$(Get-Sev @($A11_OrphanGPT).Count 'risk')" open>
  <summary><span class="ref">A11</span><h2>Órfãs — GPT no SYSVOL sem GPC no AD</h2>$(Get-Chip @($A11_OrphanGPT).Count 'risk')</summary>
  <div class="body">
    <p class="desc">Pastas no <strong>SYSVOL</strong> com formato de GUID de GPO sem o objeto GPC correspondente no AD. Candidatas a limpeza manual do SYSVOL.</p>
    $(ConvertTo-HtmlTable -Data $A11_OrphanGPT -EmptyMessage "Nenhuma GPO órfã do tipo GPT sem GPC encontrada.")
  </div>
</details>

<!-- A12 – CROSS-DOMAIN -->
<details id="crossdomain" class="finding sev-$(Get-Sev @($A12_CrossDomainLinks).Count 'risk')" open>
  <summary><span class="ref">A12</span><h2>GPOs linkadas entre domínios diferentes</h2>$(Get-Chip @($A12_CrossDomainLinks).Count 'risk')</summary>
  <div class="body">
    <p class="desc">Links que apontam para locais em domínios diferentes daquele onde a GPO foi criada. Pode causar latência e problemas de replicação, além de exigir relações de confiança explícitas.</p>
    $(ConvertTo-HtmlTable -Data $A12_CrossDomainLinks -EmptyMessage "Nenhum link cross-domain encontrado.")
  </div>
</details>

<!-- A13 – ENFORCED -->
<details id="enforced" class="finding sev-$(Get-Sev @($A13_EnforcedGPOs).Count 'hygiene')" open>
  <summary><span class="ref">A13</span><h2>Links com "Enforced" ativado</h2>$(Get-Chip @($A13_EnforcedGPOs).Count 'hygiene')</summary>
  <div class="body">
    <p class="desc">Links configurados com <strong>Enforced (No Override)</strong>. Têm precedência sobre bloqueios de herança e podem gerar comportamento inesperado se não documentados.</p>
    $(ConvertTo-HtmlTable -Data $A13_EnforcedGPOs -EmptyMessage "Nenhum link com Enforced ativado encontrado.")
  </div>
</details>

<!-- A15 – LINKS DESABILITADOS -->
<details id="disabled-links" class="finding sev-info" open>
  <summary><span class="ref">A15</span><h2>Links com "Link Enabled" = Não</h2>$(Get-Chip @($A15_DisabledLinks).Count 'info')</summary>
  <div class="body">
    <p class="desc">Links em que <strong>Link Enabled</strong> está como <em>Não</em>: a GPO está vinculada, mas não é processada. Confirme se a desativação é intencional.</p>
    $(ConvertTo-HtmlTable -Data $A15_DisabledLinks -EmptyMessage "Nenhum link desabilitado encontrado.")
  </div>
</details>

<!-- A16 – GRUPO GPCO -->
<details id="gpco" class="finding sev-info" open>
  <summary><span class="ref">A16</span><h2>Membros de "Group Policy Creator Owners"</h2>$(Get-Chip @($A16_GPCOMembers).Count 'info')</summary>
  <div class="body">
    <p class="desc">Membros do grupo privilegiado <strong>Group Policy Creator Owners</strong>, que podem criar GPOs no domínio. Mantenha apenas os estritamente necessários.</p>
    $(ConvertTo-HtmlTable -Data $A16_GPCOMembers -EmptyMessage "Nenhum membro encontrado ou módulo ActiveDirectory indisponível.")
  </div>
</details>

</div><!-- /wrap -->

<div class="foot">
  <strong>GPO Assessment Report</strong> &nbsp;·&nbsp; Domínio: $DomainFQDN &nbsp;·&nbsp; Gerado em: $Timestamp<br>
  Relatórios HTML individuais de cada GPO disponíveis em: <strong>$GPOExportDir</strong>
</div>

</body>
</html>
"@

# ── Salvar relatório ──────────────────────────────────────────
try {
    $HtmlContent | Out-File -FilePath $ReportFile -Encoding UTF8 -Force
    Write-OK "Relatório HTML salvo em: $ReportFile"
} catch {
    Write-Fail "Erro ao salvar relatório: $_"
}

# ============================================================
#  RESUMO FINAL
# ============================================================
Write-Section "RESUMO FINAL"

$Summary = [ordered]@{
    "Domínio analisado"                    = $DomainFQDN
    "Total de GPOs"                        = $AllGPOs.Count
    "GPOs exportadas (HTML individual)"    = $ExportCount
    "GPOs Vazias"                          = @($A3_EmptyGPOs).Count
    "GPOs Sem Links (com config)"          = @($A4_UnlinkedGPOs).Count
    "GPOs Só User Config (Comp ON)"        = @($A5_UserOnlyGPOs).Count
    "GPOs Só Computer Config (User ON)"    = @($A6_ComputerOnlyGPOs).Count
    "GPOs All Settings Disabled"           = @($A7_AllDisabledGPOs).Count
    "GPOs com Filtro WMI"                  = @($A8_WMIFilterGPOs).Count
    "GPOs com SIDs Não Resolvidos"         = @($A9_UnresolvedSIDGPOs).Count
    "GPOs Órfãs (GPC sem GPT)"            = @($A10_OrphanGPC).Count
    "GPOs Órfãs (GPT sem GPC)"            = @($A11_OrphanGPT).Count
    "Links Cross-Domain"                   = @($A12_CrossDomainLinks).Count
    "Links com Enforced"                   = @($A13_EnforcedGPOs).Count
    "Links Desabilitados"                  = @($A15_DisabledLinks).Count
    "Membros do grupo GPCO"                = @($A16_GPCOMembers).Count
}

foreach ($key in $Summary.Keys) {
    $val = $Summary[$key]
    $color = if ($val -is [int] -and $val -gt 0 -and $key -notmatch "Total|exportadas|Filtro|Enforced|Desabilitados|GPCO|Membros") {
        "Yellow"
    } else { "Cyan" }
    Write-Host ("  {0,-45} : {1}" -f $key, $val) -ForegroundColor $color
}

Write-Host "`n"
Write-Host "  📄 Relatório principal : $ReportFile" -ForegroundColor Green
Write-Host "  📁 HTMLs individuais   : $GPOExportDir" -ForegroundColor Green
Write-Host "`n  Avaliação concluída com sucesso!`n" -ForegroundColor Green