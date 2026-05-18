# Collectors/Invoke-DockerCollector.ps1
# Runs ON the remote Linux VM. Returns structured Docker data for evaluation.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Variables consumed for Dockerfile/compose paths and password.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        Images     = @()
        Containers = @()
        Dockerfile = @()
        Compose    = @()
    }
    Errors    = @()
}

$Password = if ($Variables.Password) { $Variables.Password } else { $null }

# ── Check Docker availability ─────────────────────────────────────────────────
try {
    $DockerVersion = docker version --format '{{.Server.Version}}' 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Try starting docker service with sudo
        if ($Password) {
            Write-Output $Password | sudo -S systemctl start docker.service 2>/dev/null
            $DockerVersion = docker version --format '{{.Server.Version}}' 2>&1
        }
    }
    if ($LASTEXITCODE -ne 0) {
        $Result.Reason = "Docker not available: $DockerVersion"
        return $Result
    }
}
catch {
    $Result.Reason = "Docker check failed: $($_.Exception.Message)"
    return $Result
}
$Result.Available = $true

# ── Collect Docker images ─────────────────────────────────────────────────────
try {
    $RawImages = docker image ls --no-trunc --format '{{json .}}' 2>&1
    if ($RawImages) {
        $Result.Data.Images = @($RawImages | ForEach-Object {
                $Img = $_ | ConvertFrom-Json
                @{
                    Repository = $Img.Repository
                    Tag        = $Img.Tag
                    ImageId    = $Img.ID
                    CreatedAt  = $Img.CreatedAt
                    Size       = $Img.Size
                }
            })
    }
}
catch {
    $Result.Errors += "Image enumeration failed: $($_.Exception.Message)"
}

# ── Collect Docker containers ─────────────────────────────────────────────────
try {
    $RawContainers = docker container ls -a --no-trunc --format '{{json .}}' 2>&1
    if ($RawContainers) {
        $Result.Data.Containers = @($RawContainers | ForEach-Object {
                $Ctr = $_ | ConvertFrom-Json
                @{
                    Name         = $Ctr.Names
                    Image        = $Ctr.Image
                    State        = $Ctr.State
                    Status       = $Ctr.Status
                    Ports        = $Ctr.Ports
                    Mounts       = $Ctr.Mounts
                    LocalVolumes = $Ctr.LocalVolumes
                }
            })
    }
}
catch {
    $Result.Errors += "Container enumeration failed: $($_.Exception.Message)"
}

# ── Collect Dockerfiles ───────────────────────────────────────────────────────
$DockerfilePaths = if ($Variables.DockerfilePaths) {
    @($Variables.DockerfilePaths)
}
else {
    @()
}

# Also search common locations
$SearchPaths = @('/home/student')
foreach ($SearchPath in $SearchPaths) {
    if (Test-Path $SearchPath) {
        $Found = Get-ChildItem -Recurse -Path $SearchPath -Include 'Dockerfile' -ErrorAction SilentlyContinue
        foreach ($F in $Found) {
            if ($F.FullName -notin $DockerfilePaths) {
                $DockerfilePaths += $F.FullName
            }
        }
    }
}

foreach ($DfPath in $DockerfilePaths) {
    try {
        if (Test-Path $DfPath) {
            $Content = Get-Content $DfPath -ErrorAction Stop
            $Result.Data.Dockerfile += @{
                Path    = $DfPath
                Content = ($Content -join "`n")
            }
        }
    }
    catch {
        $Result.Errors += "Dockerfile '$DfPath': $($_.Exception.Message)"
    }
}

# ── Collect docker-compose files ──────────────────────────────────────────────
$ComposePaths = if ($Variables.ComposePaths) {
    @($Variables.ComposePaths)
}
else {
    @()
}

foreach ($SearchPath in $SearchPaths) {
    if (Test-Path $SearchPath) {
        $Found = Get-ChildItem -Recurse -Path $SearchPath -Include 'docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml' -ErrorAction SilentlyContinue
        foreach ($F in $Found) {
            if ($F.FullName -notin $ComposePaths) {
                $ComposePaths += $F.FullName
            }
        }
    }
}

foreach ($CpPath in $ComposePaths) {
    try {
        if (Test-Path $CpPath) {
            $Content = Get-Content $CpPath -ErrorAction Stop
            $Result.Data.Compose += @{
                Path    = $CpPath
                Content = ($Content -join "`n")
            }
        }
    }
    catch {
        $Result.Errors += "Compose '$CpPath': $($_.Exception.Message)"
    }
}

return $Result
