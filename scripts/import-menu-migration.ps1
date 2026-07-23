[CmdletBinding()]
param(
    [string]$CsvFile,
    [ValidateSet('develop','qa','production')][string]$Environment,
    [string]$TableName,
    [string]$CoursesTableName,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1',
    [string]$ExpectedAccountId,
    [switch]$Execute,
    [switch]$ReplaceExisting
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
. (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentName $Environment -Quiet | Out-Null

if (-not $CsvFile) { $CsvFile = Join-Path $repositoryRoot 'migrations\menu\menu-migration.csv' }
$CsvFile = [System.IO.Path]::GetFullPath($CsvFile)
if (-not (Test-Path -LiteralPath $CsvFile -PathType Leaf)) { throw "No existe el CSV de menú: $CsvFile" }
if ($Region -ne 'us-east-1') { throw 'La migración solo admite us-east-1.' }
if (-not $TableName) { $TableName = "$($env:RESOURCE_PREFIX)-menu-$Environment" }
if (-not $CoursesTableName) { $CoursesTableName = "$($env:RESOURCE_PREFIX)-courses-$Environment" }
if ($TableName -ne "$($env:RESOURCE_PREFIX)-menu-$Environment") { throw "TableName no corresponde al cliente y ambiente activos." }
if ($CoursesTableName -ne "$($env:RESOURCE_PREFIX)-courses-$Environment") { throw "CoursesTableName no corresponde al cliente y ambiente activos." }

$requiredColumns = @(
    'idMenu','createdAt','createdBy','description','icon','idCurso','idPadre',
    'name','nombreCurso','nombrePadre','order','state','updatedAt','updatedBy','url'
)
$nullableColumns = @('idCurso','nombreCurso','nombrePadre')
$numericColumns = @('createdAt','order','updatedAt')

$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
try {
    $csvText = [System.IO.File]::ReadAllText($CsvFile, $utf8)
} catch {
    throw "El CSV debe estar codificado en UTF-8 válido: $($_.Exception.Message)"
}
$rows = @($csvText | ConvertFrom-Csv)
if (-not $rows.Count) { throw 'El CSV de menú no contiene registros.' }
$actualColumns = @($rows[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $_ -notin $actualColumns })
$extraColumns = @($actualColumns | Where-Object { $_ -notin $requiredColumns })
if ($missingColumns.Count -or $extraColumns.Count) {
    throw "Contrato CSV inválido. Faltan: $($missingColumns -join ', '); sobran: $($extraColumns -join ', ')."
}

function Test-NullLiteral([object]$Value) {
    return $null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -eq 'null'
}

function Test-Guid([object]$Value) {
    $parsed = [guid]::Empty
    return [guid]::TryParse([string]$Value, [ref]$parsed)
}

function New-DynamoAttribute([string]$Column,[object]$Value) {
    if (Test-NullLiteral $Value) {
        if ($Column -notin $nullableColumns) { throw "La columna obligatoria '$Column' contiene null." }
        return [ordered]@{ NULL = $true }
    }
    if ($Column -in $numericColumns) {
        $number = 0L
        if (-not [long]::TryParse([string]$Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            throw "La columna '$Column' debe ser un entero: '$Value'."
        }
        if ($number -lt 0 -or ($Column -eq 'order' -and $number -lt 1)) { throw "Valor fuera de rango en '$Column': $number." }
        return [ordered]@{ N = $number.ToString([Globalization.CultureInfo]::InvariantCulture) }
    }
    return [ordered]@{ S = [string]$Value }
}

function Get-AttributeSignature([object]$Attribute) {
    if ($null -eq $Attribute) { return '<missing>' }
    if ($null -ne $Attribute.S) { return "S:$($Attribute.S)" }
    if ($null -ne $Attribute.N) { return "N:$($Attribute.N)" }
    if ($Attribute.NULL -eq $true) { return 'NULL:true' }
    return ($Attribute | ConvertTo-Json -Compress -Depth 5)
}

function Test-ItemsEqual([object]$Existing,[System.Collections.IDictionary]$Desired) {
    $existingNames = @($Existing.PSObject.Properties.Name)
    if (@($existingNames | Where-Object { $_ -notin $requiredColumns }).Count) { return $false }
    foreach ($column in $requiredColumns) {
        $existingAttribute = $Existing.PSObject.Properties[$column].Value
        if ((Get-AttributeSignature $existingAttribute) -cne (Get-AttributeSignature $Desired[$column])) { return $false }
    }
    return $true
}

$ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$items = [System.Collections.Generic.List[object]]::new()
$orderKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($row in $rows) {
    if (-not (Test-Guid $row.idMenu)) { throw "idMenu inválido: '$($row.idMenu)'." }
    if (-not $ids.Add([string]$row.idMenu)) { throw "idMenu duplicado: '$($row.idMenu)'." }
    if ($row.idPadre -ne 'ROOT' -and -not (Test-Guid $row.idPadre)) { throw "idPadre inválido para '$($row.idMenu)'." }
    if (-not (Test-NullLiteral $row.idCurso) -and -not (Test-Guid $row.idCurso)) { throw "idCurso inválido para '$($row.idMenu)'." }
    $orderKey = "$($row.idPadre)|$($row.order)"
    if (-not $orderKeys.Add($orderKey)) { throw "Orden duplicado para padre '$($row.idPadre)': $($row.order)." }
    $item = [ordered]@{}
    foreach ($column in $requiredColumns) { $item[$column] = New-DynamoAttribute $column $row.$column }
    $items.Add([pscustomobject]@{ Row=$row; Item=$item })
}

foreach ($entry in $items) {
    $parentId = [string]$entry.Row.idPadre
    if ($parentId -ne 'ROOT' -and -not $ids.Contains($parentId)) {
        throw "El padre '$parentId' de '$($entry.Row.idMenu)' no existe en el mismo CSV."
    }
    if ($parentId -eq 'ROOT' -and -not (Test-NullLiteral $entry.Row.nombrePadre)) {
        throw "El menú raíz '$($entry.Row.idMenu)' debe tener nombrePadre=null."
    }
    if ($parentId -ne 'ROOT') {
        $parent = $items | Where-Object { $_.Row.idMenu -eq $parentId } | Select-Object -First 1
        if ($entry.Row.nombrePadre -ne $parent.Row.name) { throw "nombrePadre no coincide para '$($entry.Row.idMenu)'." }
    }
}

Write-Host "CSV válido: $($items.Count) menús; tabla destino: $TableName; ambiente: $Environment."
if (-not $Execute) {
    Write-Warning 'Vista previa local: no se consultó ni modificó AWS. Repita con -Execute y ExpectedAccountId para migrar.'
    return
}

if ($ExpectedAccountId -notmatch '^\d{12}$') { throw 'ExpectedAccountId debe contener 12 dígitos.' }
$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }

function Invoke-Aws([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & aws @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
        Text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }
}

$identityCall = Invoke-Aws (@('sts','get-caller-identity','--output','json') + $awsBase)
if ($identityCall.ExitCode -ne 0) { throw "No se pudo consultar la identidad AWS: $($identityCall.Text)" }
$identity = ($identityCall.Output -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw "Cuenta activa $($identity.Account); se esperaba $ExpectedAccountId." }
$expectedRoleName = "$($env:RESOURCE_PREFIX)-deployment-$Environment"
if ($identity.Arn -notmatch "^arn:aws:sts::$ExpectedAccountId`:assumed-role/$([regex]::Escape($expectedRoleName))/") {
    throw "La identidad activa no es una sesión del rol '$expectedRoleName'."
}

foreach ($targetTable in @($TableName,$CoursesTableName)) {
    $tableCall = Invoke-Aws (@('dynamodb','describe-table','--table-name',$targetTable,'--output','json') + $awsBase)
    if ($tableCall.ExitCode -ne 0) { throw "No se pudo consultar la tabla '$targetTable': $($tableCall.Text)" }
    $table = ($tableCall.Output -join [Environment]::NewLine) | ConvertFrom-Json
    if ($table.Table.TableStatus -ne 'ACTIVE') { throw "La tabla '$targetTable' no está ACTIVE." }
}

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("menu-migration-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDirectory | Out-Null
try {
    $courseIds = @($items | Where-Object { -not (Test-NullLiteral $_.Row.idCurso) } | ForEach-Object { [string]$_.Row.idCurso } | Sort-Object -Unique)
    foreach ($courseId in $courseIds) {
        $courseKeyFile = Join-Path $tempDirectory "course-$courseId.json"
        [System.IO.File]::WriteAllText($courseKeyFile,(@{ idCourse=@{ S=$courseId } } | ConvertTo-Json -Compress -Depth 4),[Text.UTF8Encoding]::new($false))
        $courseCall = Invoke-Aws (@('dynamodb','get-item','--table-name',$CoursesTableName,'--key',"file://$($courseKeyFile.Replace('\','/'))",'--consistent-read','--output','json') + $awsBase)
        if ($courseCall.ExitCode -ne 0) { throw "No se pudo validar el curso '$courseId': $($courseCall.Text)" }
        $courseResult = ($courseCall.Output -join [Environment]::NewLine) | ConvertFrom-Json
        if (-not $courseResult.Item) { throw "El curso '$courseId' referenciado por el menú no existe en '$CoursesTableName'. Migre cursos antes del menú." }
    }

    $plan = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $items) {
        $id = [string]$entry.Row.idMenu
        $keyFile = Join-Path $tempDirectory "key-$id.json"
        [System.IO.File]::WriteAllText($keyFile,(@{ idMenu=@{ S=$id } } | ConvertTo-Json -Compress -Depth 4),[Text.UTF8Encoding]::new($false))
        $getCall = Invoke-Aws (@('dynamodb','get-item','--table-name',$TableName,'--key',"file://$($keyFile.Replace('\','/'))",'--consistent-read','--output','json') + $awsBase)
        if ($getCall.ExitCode -ne 0) { throw "No se pudo consultar el menú '$id': $($getCall.Text)" }
        $result = ($getCall.Output -join [Environment]::NewLine) | ConvertFrom-Json
        if (-not $result.Item) {
            $action = 'Insert'
        } elseif (Test-ItemsEqual $result.Item $entry.Item) {
            $action = 'Skip'
        } elseif ($ReplaceExisting) {
            $action = 'Replace'
        } else {
            throw "El menú '$id' ya existe con datos diferentes. Revise el ambiente o use -ReplaceExisting con autorización explícita."
        }
        $plan.Add([pscustomobject]@{ Id=$id; Name=$entry.Row.name; Action=$action; Item=$entry.Item })
    }

    $plan | Select-Object Action,Id,Name | Format-Table -AutoSize | Out-Host
    $inserted = 0
    $replaced = 0
    $skipped = @($plan | Where-Object Action -eq 'Skip').Count
    foreach ($operation in $plan | Where-Object Action -ne 'Skip') {
        $itemFile = Join-Path $tempDirectory "item-$($operation.Id).json"
        [System.IO.File]::WriteAllText($itemFile,($operation.Item | ConvertTo-Json -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
        $arguments = @('dynamodb','put-item','--table-name',$TableName,'--item',"file://$($itemFile.Replace('\','/'))")
        if ($operation.Action -eq 'Insert') { $arguments += @('--condition-expression','attribute_not_exists(idMenu)') }
        $putCall = Invoke-Aws ($arguments + $awsBase)
        if ($putCall.ExitCode -ne 0) { throw "No se pudo escribir '$($operation.Id)': $($putCall.Text)" }
        if ($operation.Action -eq 'Insert') { $inserted++ } else { $replaced++ }
    }
    Write-Host "Migración de menú completa: insertados=$inserted reemplazados=$replaced omitidos-idénticos=$skipped." -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
