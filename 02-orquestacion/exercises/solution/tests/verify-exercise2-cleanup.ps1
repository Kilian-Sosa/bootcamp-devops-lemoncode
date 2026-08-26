[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$solutionDirectory = Split-Path -Parent $PSScriptRoot
$expectedProfile = 'lemoncode-orchestration'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $script:failures.Add($Message)
}

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        Add-Failure $Message
    }
}

function Get-ShellFunctionBody {
    param(
        [string]$Source,
        [string]$Name,
        [string]$ScriptName
    )

    $pattern = '(?ms)^\s*' + [regex]::Escape($Name) + '\(\)\s*\{(?<body>.*?)^\}'
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        Add-Failure "$ScriptName must define $Name()."
        return ''
    }

    return $match.Groups['body'].Value
}

foreach ($scriptName in @('ejercicio1.sh', 'ejercicio2.sh', 'ejercicio3.sh')) {
    $scriptPath = Join-Path $solutionDirectory $scriptName
    Assert-Condition (Test-Path -LiteralPath $scriptPath) "$scriptName must exist."
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        continue
    }

    $source = Get-Content -LiteralPath $scriptPath -Raw

    Assert-Condition (
        $source -cmatch '(?m)^MINIKUBE_PROFILE="lemoncode-orchestration"\s*$'
    ) "$scriptName must set MINIKUBE_PROFILE to $expectedProfile."

    Assert-Condition (
        $source -cmatch 'if\s+\[\[\s+"\$CURRENT_CTX"\s+!=\s+"\$MINIKUBE_PROFILE"\s+\]\]'
    ) "$scriptName must require the kubectl context matching MINIKUBE_PROFILE."

    $minikubeCommandLines = @(
        $source -split "`r?`n" |
            Where-Object {
                $line = $_.Trim()
                $line -cmatch '\bminikube\b' -and
                $line -cnotmatch '^(#|for\s+tool\s+in|log\s|ok\s|warn\s|err\s|echo\s|if\s+\[\[)'
            }
    )

    Assert-Condition (
        $minikubeCommandLines.Count -gt 0
    ) "$scriptName must invoke Minikube through the approved profile."

    foreach ($line in $minikubeCommandLines) {
        Assert-Condition (
            $line -cmatch 'minikube\s+--profile\s+"\$MINIKUBE_PROFILE"'
        ) "$scriptName has an unscoped Minikube command: $line"
    }

    $mutatingKubectlLines = @(
        $source -split "`r?`n" |
            Where-Object {
                $line = $_.Trim()
                $line -cmatch '\bkubectl\b' -and
                $line -cmatch '\b(apply|delete)\b' -and
                $line -cnotmatch '^(#|for\s+tool\s+in|log\s|ok\s|warn\s|err\s|echo\s)'
            }
    )

    Assert-Condition (
        $mutatingKubectlLines.Count -gt 0
    ) "$scriptName must contain profile-pinned mutating kubectl commands."

    foreach ($line in $mutatingKubectlLines) {
        Assert-Condition (
            $line -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+(apply|delete)\b'
        ) "$scriptName has an unpinned mutating kubectl command: $line"
    }
}

$exercise2Path = Join-Path $solutionDirectory 'ejercicio2.sh'
if (Test-Path -LiteralPath $exercise2Path) {
    $exercise2 = Get-Content -LiteralPath $exercise2Path -Raw
    $normalCleanup = Get-ShellFunctionBody -Source $exercise2 -Name 'cleanup_resources' -ScriptName 'ejercicio2.sh'
    $dataCleanup = Get-ShellFunctionBody -Source $exercise2 -Name 'cleanup_data' -ScriptName 'ejercicio2.sh'

    Assert-Condition (
        $normalCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+statefulset\s+"\$PG_STATEFULSET"'
    ) 'Normal Exercise 2 cleanup must delete the PostgreSQL StatefulSet.'
    Assert-Condition (
        $normalCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+deployment\s+"\$APP_DEPLOYMENT"'
    ) 'Normal Exercise 2 cleanup must delete the application Deployment.'
    Assert-Condition (
        $normalCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+service\s+"\$PG_SERVICE"\s+"\$APP_SERVICE"'
    ) 'Normal Exercise 2 cleanup must delete only its database and application Services.'
    Assert-Condition (
        $normalCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+configmap\s+postgres-config\s+todo-app-config'
    ) 'Normal Exercise 2 cleanup must delete only its database and application ConfigMaps.'
    Assert-Condition (
        $normalCleanup -cnotmatch 'kubectl\s+(?:--context\s+"\$MINIKUBE_PROFILE"\s+)?delete\s+(namespace|pvc|pv|storageclass)\b'
    ) 'Normal Exercise 2 cleanup must preserve its namespace and storage objects.'
    Assert-Condition (
        $normalCleanup -cnotmatch '/mnt/data/lemoncode-postgres'
    ) 'Normal Exercise 2 cleanup must preserve the hostPath data.'

    Assert-Condition (
        $dataCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+pvc\s+"\$PVC_NAME"\s+-n\s+"\$NAMESPACE"'
    ) 'cleanup-data must delete the exercise PVC.'
    Assert-Condition (
        $dataCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+pv\s+"\$PV_NAME"'
    ) 'cleanup-data must delete the exercise PV.'
    Assert-Condition (
        $dataCleanup -cmatch 'kubectl\s+--context\s+"\$MINIKUBE_PROFILE"\s+delete\s+storageclass\s+"\$STORAGE_CLASS"'
    ) 'cleanup-data must delete the exercise StorageClass.'
    Assert-Condition (
        $dataCleanup -cmatch 'minikube\s+--profile\s+"\$MINIKUBE_PROFILE"\s+ssh\s+"sudo rm -rf -- /mnt/data/lemoncode-postgres"'
    ) 'cleanup-data must remove only the fixed hostPath through the approved profile.'
    Assert-Condition (
        $dataCleanup -cnotmatch 'kubectl\s+(?:--context\s+"\$MINIKUBE_PROFILE"\s+)?delete\s+(?!pvc\b|pv\b|storageclass\b)'
    ) 'cleanup-data may delete only the exercise-owned Kubernetes storage objects.'
    Assert-Condition (
        $exercise2 -cnotmatch 'kubectl\s+(?:--context\s+"\$MINIKUBE_PROFILE"\s+)?delete\s+namespace\s+"\$NAMESPACE"'
    ) 'Exercise 2 cleanup must never delete its namespace.'
    Assert-Condition (
        $exercise2 -cmatch 'if\s+\[\[\s+"\$ACTION"\s+==\s+"cleanup"\s+\]\];\s+then\s+cleanup_resources'
    ) 'cleanup must run the data-preserving cleanup path.'
    Assert-Condition (
        $exercise2 -cmatch 'if\s+\[\[\s+"\$ACTION"\s+==\s+"cleanup-data"\s+\]\];\s+then\s+cleanup_resources\s+cleanup_data'
    ) 'cleanup-data must clean workloads before deleting the exercise storage data.'
}

if ($failures.Count -gt 0) {
    Write-Host 'FAIL: Exercise 2 cleanup/profile regression check' -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS: Exercise 2 cleanup/profile regression check' -ForegroundColor Green
