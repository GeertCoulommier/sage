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
        Images       = @()
        Containers   = @()
        Dockerfile   = @()
        Compose      = @()
        CurlResults  = @()
        FileContents = @()
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

# ── Enrich containers with full mount data from docker inspect ────────────────
foreach ($Container in $Result.Data.Containers) {
    try {
        $InspectArgs = @(
            'inspect'
            '--format'
            '{{json .Mounts}}'
            $Container.Name
        )
        $InspectJson = docker @InspectArgs 2>&1
        if ($LASTEXITCODE -eq 0 -and $InspectJson) {
            $ParsedMounts = $InspectJson | ConvertFrom-Json
            $Container.VolumeMounts = @(
                $ParsedMounts |
                    Where-Object { $_.Type -eq 'bind' } |
                    ForEach-Object {
                        @{
                            Source      = $_.Source
                            Destination = $_.Destination
                        }
                    }
            )
        }
        else {
            $Container.VolumeMounts = @()
        }
    }
    catch {
        $Container.VolumeMounts = @()
        $Result.Errors += "Volume inspect for '$($Container.Name)': $($_.Exception.Message)"
    }
}

# ── Collect Dockerfiles ───────────────────────────────────────────────────────
# IMPORTANT: Do NOT use `$x = if/else { @() }` — empty array through the pipeline
# produces $null, not @(). Initialize explicitly to prevent string-concatenation on +=.
$DockerfilePaths = @()
if ($Variables.DockerfilePaths) {
    $DockerfilePaths = @($Variables.DockerfilePaths)
}

# Extract explicit paths from DockerfileTests (exam definition specifies exact paths)
if ($Variables.DockerfileTests) {
    foreach ($Test in $Variables.DockerfileTests) {
        if ($Test.Path -and ($Test.Path -notin $DockerfilePaths)) {
            $DockerfilePaths += $Test.Path
        }
    }
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
            $DfEntry        = @{
                Path    = $DfPath
                Content = ($Content -join "`n")
            }
            $InContinuation = $false
            foreach ($Line in $Content) {
                $Trimmed = $Line.Trim()
                if (-not $Trimmed -or $Trimmed.StartsWith('#')) { continue }
                # Skip lines that belong to a multi-line continuation
                if ($InContinuation) {
                    $InContinuation = $Trimmed.EndsWith('\')
                    continue
                }
                # Use -cmatch for case-sensitive matching (Dockerfile instructions are uppercase)
                if ($Trimmed -cmatch '^([A-Z][A-Z0-9_]*)\s+(.+)$') {
                    $Instr          = $Matches[1]
                    $Val            = $Matches[2].TrimEnd()
                    $InContinuation = $Val.EndsWith('\')
                    if ($InContinuation) { $Val = $Val.Substring(0, $Val.Length - 1).TrimEnd() }
                    if ($DfEntry.ContainsKey($Instr)) {
                        $Existing = $DfEntry[$Instr]
                        if ($Existing -is [array]) {
                            $DfEntry[$Instr] = $Existing + @($Val)
                        } else {
                            $DfEntry[$Instr] = @($Existing, $Val)
                        }
                    } else {
                        $DfEntry[$Instr] = $Val
                    }
                }
            }
            $Result.Data.Dockerfile += $DfEntry
        }
    }
    catch {
        $Result.Errors += "Dockerfile '$DfPath': $($_.Exception.Message)"
    }
}

# ── Collect docker-compose files ──────────────────────────────────────────────
# Same pattern: initialize explicitly to avoid $null from empty pipeline.
$ComposePaths = @()
if ($Variables.ComposePaths) {
    $ComposePaths = @($Variables.ComposePaths)
}

# Extract explicit paths from ComposeTests and ComposeContentTests
if ($Variables.ComposeTests) {
    foreach ($Test in $Variables.ComposeTests) {
        if ($Test.Path -and ($Test.Path -notin $ComposePaths)) {
            $ComposePaths += $Test.Path
        }
    }
}
if ($Variables.ComposeContentTests) {
    foreach ($Test in $Variables.ComposeContentTests) {
        if ($Test.Path -and ($Test.Path -notin $ComposePaths)) {
            $ComposePaths += $Test.Path
        }
    }
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
            $RawText = $Content -join "`n"
            $CpEntry = @{
                Path    = $CpPath
                Content = $RawText
            }
            # Parse docker-compose YAML structure natively (no external dependencies).
            # Handles top-level keys, services (indent-2), service properties (indent-4),
            # and list items under a service property (indent-6).
            $CurrSection    = $null
            $CurrService    = $null
            $CurrServiceKey = $null
            $NativeParsed   = @{}
            foreach ($CpLine in $Content) {
                $Raw = $CpLine.TrimEnd()
                if (-not $Raw.Trim() -or $Raw -match '^\s*#') { continue }
                $Indent  = $Raw.Length - $Raw.TrimStart().Length
                $Trimmed = $Raw.TrimStart()
                if ($Indent -eq 0) {
                    $CurrServiceKey = $null
                    if ($Trimmed -match '^([a-zA-Z][a-zA-Z0-9_]*):\s*$') {
                        $CurrSection = $Matches[1]
                        $CurrService = $null
                        $NativeParsed[$CurrSection] = @{}
                    } elseif ($Trimmed -match '^([a-zA-Z][a-zA-Z0-9_]*):\s+(.+)$') {
                        $CurrSection = $null
                        $CurrService = $null
                        $NativeParsed[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
                    }
                } elseif ($Indent -eq 2 -and $CurrSection -and $NativeParsed[$CurrSection] -is [hashtable]) {
                    $CurrServiceKey = $null
                    if ($Trimmed -match '^([a-zA-Z0-9][a-zA-Z0-9_-]*):\s*$') {
                        $CurrService = $Matches[1]
                        $NativeParsed[$CurrSection][$CurrService] = @{}
                    } elseif ($Trimmed -match '^([a-zA-Z0-9][a-zA-Z0-9_-]*):\s+(.+)$') {
                        $CurrService = $Matches[1]
                        $NativeParsed[$CurrSection][$CurrService] = $Matches[2].Trim().Trim('"').Trim("'")
                    }
                } elseif ($Indent -eq 4 -and $CurrSection -and $CurrService) {
                    $SvcData = $NativeParsed[$CurrSection][$CurrService]
                    if ($SvcData -is [hashtable]) {
                        if ($Trimmed -match '^([a-zA-Z][a-zA-Z0-9_]*):\s+(.+)$') {
                            $CurrServiceKey = $Matches[1]
                            $SvcData[$CurrServiceKey] = $Matches[2].Trim().Trim('"').Trim("'")
                        } elseif ($Trimmed -match '^([a-zA-Z][a-zA-Z0-9_]*):\s*$') {
                            # Start of a list or sub-section (e.g. ports:, volumes:)
                            $CurrServiceKey = $Matches[1]
                            $SvcData[$CurrServiceKey] = @()
                        }
                    }
                } elseif ($Indent -eq 6 -and $CurrSection -and $CurrService -and $CurrServiceKey) {
                    # List item under a service property (e.g. - "8082:80")
                    $SvcData = $NativeParsed[$CurrSection][$CurrService]
                    if ($SvcData -is [hashtable] -and $SvcData[$CurrServiceKey] -is [array]) {
                        if ($Trimmed -match '^-\s+(.+)$') {
                            $SvcData[$CurrServiceKey] += $Matches[1].Trim().Trim('"').Trim("'")
                        }
                    }
                }
            }
            foreach ($K in @($NativeParsed.Keys)) {
                if ($K -notin @('Path', 'Content')) { $CpEntry[$K] = $NativeParsed[$K] }
            }
            $Result.Data.Compose += $CpEntry
        }
    }
    catch {
        $Result.Errors += "Compose '$CpPath': $($_.Exception.Message)"
    }
}

# ── Live curl tests ───────────────────────────────────────────────────────────
if ($Variables.CurlTests) {
    foreach ($Test in $Variables.CurlTests) {
        $CurlArgs = @('--silent', '--max-time', '5', '--output', '-')
        if ($Test.ResolveHost -and $Test.ResolvePort -and $Test.ResolveAddress) {
            $CurlArgs += '--resolve'
            $CurlArgs += "$($Test.ResolveHost):$($Test.ResolvePort):$($Test.ResolveAddress)"
        }
        $CurlArgs += $Test.Url

        $CurlOutput = ''
        $CurlSuccess = $false
        try {
            $CurlOutput = curl @CurlArgs 2>/dev/null
            $CurlSuccess = $true
        }
        catch {
            $CurlOutput = ''
        }

        $CurlContent = if ($CurlOutput -is [System.Array]) {
            $CurlOutput -join [Environment]::NewLine
        }
        else {
            [string]$CurlOutput
        }

        $Result.Data.CurlResults += @{
            Url             = $Test.Url
            Success         = $CurlSuccess
            Content         = $CurlContent
            ExpectedContent = $Test.ExpectedContent
        }
    }
}

# ── File content tests ────────────────────────────────────────────────────────
if ($Variables.FileContentTests) {
    foreach ($Test in $Variables.FileContentTests) {
        $PathsToTry = if ($Test.AllowedPaths) {
            @($Test.AllowedPaths)
        }
        elseif ($Test.Path) {
            @($Test.Path)
        }
        else {
            @()
        }
        $PrimaryPath = if ($Test.Path) { $Test.Path } else { $PathsToTry | Select-Object -First 1 }
        $Found = $false
        foreach ($TryPath in $PathsToTry) {
            try {
                if (Test-Path $TryPath) {
                    $Content = Get-Content $TryPath -Raw -ErrorAction Stop
                    $Result.Data.FileContents += @{
                        Path    = $PrimaryPath
                        Content = $Content
                    }
                    $Found = $true
                    break
                }
            }
            catch {
                $Result.Errors += "FileContent '$TryPath': $($_.Exception.Message)"
            }
        }
        if (-not $Found) {
            $Result.Data.FileContents += @{
                Path    = $PrimaryPath
                Content = ''
            }
        }
    }
}

return $Result
