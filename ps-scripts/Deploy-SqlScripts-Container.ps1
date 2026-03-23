param(
  [string]$ContainerName = "nw-container",
  [string]$DatabaseName,
  [string]$SqlFolderPath,
  [string]$SqlScriptPath,
  [int]$SqlStartupTimeoutSeconds = 60,
  [switch]$DryRun
)
# --- Determine script directory and create timestamped log file ---
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$LogFile = Join-Path $ScriptDirectory "deploy_log_$Timestamp.txt"

# --- Helper: Write to log and console ---
function Write-Log {
  param([string]$Message)
  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $entry = "$timestamp $Message"
  Write-Host $entry
  Add-Content -Path $LogFile -Value $entry
}

# --- Helper: Securely save or fetch $SaPassword
function Get-SaPassword {
  param(
    [string]$SecretName = "SqlSaPassword",
    [string]$VaultName = "LocalSecrets" 
  )
  # --- Ensure SecretManagement modules are installed ---
  $requiredModules = @(
    "Microsoft.PowerShell.SecretManagement",
    "Microsoft.PowerShell.SecretStore"
  )
  foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
      Write-Log "Installing missing module: $module"
      try {
        Install-Module $module -Force -Scope CurrentUser -ErrorAction Stop
        Write-Log "Module '$module' installed successfully."
      } catch {
        Write-Log "ERROR: Failed to install module '$module'. $_"
        exit 1
      }
    }
  }
  # --- Ensure vault is registered ---
  try {
    Get-SecretVault -Name $VaultName -ErrorAction Stop
  }
  catch {
    Write-Log "Registering secret vault: $VaultName ..."
    try {
      Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault -ErrorAction Stop
      Write-Log "Vault '$VaultName' registered successfully."
    }
    catch {
      Write-Log "ERROR: Failed to register vault '$VaultName'. $_"
      exit 1
    }
  }
  # --- Try to retrieve existing secret ---
  try {
    $existing = Get-Secret -Name $SecretName -ErrorAction Stop
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($existing)
    )
    Write-Log "SA password retrieved from vault."
    return $plain
  }
  catch {
    Write-Log "No cached SA password found in vault. Prompting user ..."
  }
  # --- Prompt user for password ---
  try {
    $secure = Read-Host "Enter SA Password" -AsSecureString
    if (-not $secure -or $secure.Length -eq 0) {
      Write-Log "ERROR: No password entered."
      exit 1
    }
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )
  }
  catch {
    Write-Log "ERROR: Failed to read password from input. $_"
    exit 1
  } 
  # --- Ask whether to save it ---
  $save = Read-Host "Save this password for future runs? (y/n)"
  if ($save -eq "y") {
    try {
      Set-Secret -Name $SecretName -Secret $plain -ErrorAction Stop
      Write-Log "Password saved securely in vault '$VaultName'."
    }
    catch {
      Write-Log "ERROR: Failed to save password to vault '$VaultName'. $_"
      exit 1
    }
  }
  return $plain
}

Write-Log "=== Starting SQL deployment ==="
Write-Log "Container: $ContainerName"
Write-Log "Dry Run Mode: $DryRun"
Write-Log "Log File: $LogFile"
if ($DatabaseName) { Write-Log "Database: $DatabaseName" }


# ---------------------------------------------------------
# Validate input: must provide either folder OR single file
# ---------------------------------------------------------
if (-not $SqlFolderPath -and -not $SqlScriptPath) {
  Write-Log "ERROR: you must provide either -SqlFolderPath OR -SqlScriptPath"
  exit 1
}
if ($SqlFolderPath -and $SqlScriptPath) {
  Write-Log "ERROR: Provide only one: -SqlFolderPath OR -SqlScriptPath, not both"
  exit 1
}

# ---------------------------------------------------------
# Fetching the $SaPassword or Setting up the $SaPassword
# ---------------------------------------------------------
$SaPassword = Get-SaPassword

# ---------------------------------------------------------
# HEALTH CHECK 1: Verify container is running
# ---------------------------------------------------------
Write-Log "Checking if container is running ..."
$containerStatus = docker inspect -f "{{.State.Running}}" $ContainerName 2>$null
if ($containerStatus -ne "true") {
  Write-Log "ERROR: Container '$ContainerName' is not running."
  exit 1
}
Write-Log "Container is running."

# ---------------------------------------------------------
# HEALTH CHECK 2: Wait for SQL Server to accept connections
# ---------------------------------------------------------
Write-Log "Waiting for SQL Server to become ready ..."
# Detect sqlcmd inside container
$SqlCmdPath = $null
$possibleSqlCmdPaths = @(
  "/opt/mssql-tools/bin/sqlcmd",
  "/opt/mssql-tools18/bin/sqlcmd"
)
foreach ($path in $possibleSqlCmdPaths) {
  $exists = docker exec $ContainerName bash -c "test -f $path && echo yes"
  if ($exists -eq "yes") {
    $SqlCmdPath = $path
    break
  }
}
if (-not $SqlCmdPath) {
  Write-Log "ERROR: sqlcmd not found in container at any known path."
  exit 1
}
Write-Log "Using sqlcmd at $SqlCmdPath"
$startTime = Get-Date
$connected = $false
while (-not $connected) {
  $elapsed = (Get-Date) - $startTime
  if ($elapsed.TotalSeconds -ge $SqlStartupTimeoutSeconds) {
    Write-Log "ERROR: SQL Server did not become ready within timeout."
    exit 1
  }
  docker exec $ContainerName $SqlCmdPath `
    -S localhost -U sa -P $SaPassword -C `
    -Q "SELECT 1" 2>$null
  if ($LASTEXITCODE -eq 0) {
    $connected = $true
    Write-Log "SQL Server is accepting connections."
  } else {
    Start-Sleep -Seconds 2
  }
}

# ---------------------------------------------------------
# Validate input: If provided, check database exists
# ---------------------------------------------------------
if ($DatabaseName) {
  Write-Log "Checking if database '$DatabaseName' exists ..."
  # By using RAISERROR to force a non-zero exit when the DB is missing
  $checkQuery = "IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DatabaseName') RAISERROR('Database not found', 16, 1)"
  docker exec $ContainerName $SqlCmdPath -S localhost -U sa -P $SaPassword -C -Q $checkQuery 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: Database '$DatabaseName' does not exist."
    exit 1
  }
  Write-Log "Database '$DatabaseName' exists."
}

# ---------------------------------------------------------
# Determine execution mode: folder or single file
# ---------------------------------------------------------
$sqlFiles = @()
if ($SqlFolderPath) {
  Write-Log "Using SQL folder: $SqlFolderPath"
  if (-not (Test-Path $SqlFolderPath)) {
    Write-Log "ERROR: SQL folder not found: $SqlFolderPath"
    exit 1
  }
  $sqlFiles = Get-ChildItem -Path $SqlFolderPath -Filter *.sql | Sort-Object Name
  if ($sqlFiles.Count -eq 0) {
    Write-Log "ERROR: No SQL files found in folder."
    exit 1
  }
  Write-Log "Found $($sqlFiles.Count) SQL files to deploy."
}
elseif ($SqlScriptPath) {
  Write-Log "Using single SQL script: $SqlScriptPath"
  if (-not (Test-Path $SqlScriptPath)) {
    Write-Log "ERROR: SQL Script not found: $SqlScriptPath"
    exit 1
  }
  $sqlFiles = @(Get-Item $SqlScriptPath)
}

# ---------------------------------------------------------
# DRY RUN MODE: Show what would happen
# ---------------------------------------------------------
$promptUserDryRun = if (-not $DryRun) { Read-Host "Do you want to perform a dry run? (y/n)"}
if ($DryRun -or $promptUserDryRun -eq "y") {
  Write-Log "=== DRY RUN: No scripts will be executed ==="
  foreach ($file in $sqlFiles){
    Write-Log "[DRY RUN] Would execute: $($file.Name)"
  }
  Write-Log "=== DRY RUN COMPLETE ==="
  exit 0
}

# ---------------------------------------------------------
# Execute SQL files (REAL RUN)
# ---------------------------------------------------------
$dbArgs = if ($DatabaseName) { @("-d", $DatabaseName) } else { @() }
foreach ($file in $sqlFiles) {
  Write-Log "Processing file: $($file.Name)"
  $containerScriptPath = "/tmp/$($file.Name)"
  Write-Log "Copying $($file.Name) into container ..."
  docker cp $file.FullName "$($ContainerName):$containerScriptPath"
  if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: Failed to copy '$($file.Name)' into container"
    exit 1
  }
  Write-Log "Executing $($file.Name) ..."
  docker exec $ContainerName $SqlCmdPath `
    -S localhost -U sa -P $SaPassword -C `
    @dbArgs `
    -i $containerScriptPath
  if ($LASTEXITCODE -eq 0) {
    Write-Log "SUCCESS: $($file.Name) executed successfully."
    # Cleanup 
    docker exec $ContainerName rm -f $containerScriptPath | Out-Null
    Write-Log "Removed '$($file.Name)' from container"
  } else {
    Write-Log "ERROR: Execution failed for $($file.Name)."
    # Cleanup 
    docker exec $ContainerName rm -f $containerScriptPath | Out-Null
    Write-Log "Removed '$($file.Name)' from container"
    Write-Log "Stopping deployment."
    exit 1
  }
}
Write-Log "=== SQL deployment completed successfully ==="

