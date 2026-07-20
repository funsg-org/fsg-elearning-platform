[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositories = @($repositoryRoot)
$repositories += Get-ChildItem -Directory (Join-Path $repositoryRoot 'services'), (Join-Path $repositoryRoot 'frontends') |
    Select-Object -ExpandProperty FullName

$rules = @(
    @{ Name = 'AWS Access Key ID'; Pattern = '(?<![A-Z0-9])AKIA[0-9A-Z]{16}(?![A-Z0-9])' },
    @{ Name = 'Private key'; Pattern = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' },
    @{ Name = 'AWS secret assignment'; Pattern = '(?i)AWS_[A-Z0-9_]*SECRET_ACCESS_KEY\s*=\s*["'']?[A-Za-z0-9/+=]{16,}' },
    @{ Name = 'Cognito Client Secret assignment'; Pattern = '(?i)COGNITO_CLIENT_SECRET(?!_ID)\s*=\s*["'']?[A-Za-z0-9/+=]{16,}' }
)

$findings = [System.Collections.Generic.List[object]]::new()

foreach ($repository in $repositories) {
    if (-not (Test-Path -LiteralPath (Join-Path $repository '.git'))) {
        continue
    }

    $trackedFiles = git -C $repository -c core.quotepath=false ls-files
    foreach ($relativePath in $trackedFiles) {
        $absolutePath = Join-Path $repository $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            continue
        }
        if ($relativePath -match '(?i)\.(css|scss|png|jpe?g|gif|webp|svg|ico|woff2?|ttf|zip|pdf)$') {
            continue
        }

        try {
            $lineNumber = 0
            foreach ($line in Get-Content -LiteralPath $absolutePath -ErrorAction Stop) {
                $lineNumber++
                foreach ($rule in $rules) {
                    if ($line -match $rule.Pattern) {
                        $findings.Add([pscustomobject]@{
                            Repository = Split-Path $repository -Leaf
                            File = $relativePath
                            Line = $lineNumber
                            Rule = $rule.Name
                        })
                    }
                }
            }
        } catch {
            # Los binarios rastreados no son candidatos para esta inspección textual.
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object Repository, File, Line | Format-Table -AutoSize
    Write-Error "Se encontraron $($findings.Count) posibles secretos en archivos rastreados."
    exit 1
}

Write-Host 'No se encontraron secretos con los patrones bloqueados en los archivos rastreados.' -ForegroundColor Green
