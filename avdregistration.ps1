#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Re-registers an Azure Virtual Desktop (AVD) session host to a new host pool, verifies the result, and reboots.
.DESCRIPTION
    This script is designed to be run locally on an AVD session host via an RMM tool like NinjaOne.
    It handles multiple installed agent versions, uninstalls them, reinstalls with a new registration key, 
    pauses to check the event log for successful registration, logs the result, and then reboots the machine.

    MANUAL PREREQUISITE: You MUST remove the session host from the old host pool in the
    Azure Portal *before* running this script.

.EXAMPLE
    # 1. Edit this script file.
    # 2. Paste your AVD registration key into the $RegistrationKey variable below.
    # 3. Save the script and run it via NinjaOne on the target session hosts.
#>

# =====================================================================================
# === CONFIGURATION: PASTE YOUR REGISTRATION KEY HERE ===
# =====================================================================================
# Because the key can be too long for some RMM parameter fields, paste it directly below.
# The key should be enclosed in double quotes.
#
# EXAMPLE: $RegistrationKey = "eyJhbGciOiJSUzI1NiIsImtpZCI6IjE..."

$RegistrationKey = ""
# =====================================================================================
# === END OF CONFIGURATION ===
# =====================================================================================


# --- Script Configuration ---
$logDirectory = "C:\admin"
$tempPath = "C:\Temp\AVD" # Using Temp for downloads is still best practice
$agentDownloadUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
$agentInstallerName = "Microsoft.RDInfra.RDAgent.Installer.msi"
$installerPath = Join-Path $tempPath $agentInstallerName
$logFileBaseName = "AVD_Re-Registration"
$logFileTimestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logDirectory "$($logFileBaseName)_$($logFileTimestamp).log"
$maxLogsToKeep = 5
$eventLogName = "Microsoft-Windows-RemoteDesktopServices-RdaAgent/Admin"

# --- Start Logging ---
# Create logging and temp directories if they don't exist
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -Path $tempPath)) {
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $logFile -Append

# --- Safety Check ---
if ($RegistrationKey -eq "PASTE_YOUR_LONG_REGISTRATION_KEY_HERE" -or [string]::IsNullOrWhiteSpace($RegistrationKey)) {
    Write-Error "SCRIPT STOPPED: The registration key has not been set in the script. Please edit the script file and paste the key into the `$RegistrationKey` variable."
    Stop-Transcript
    exit 1 # Exit with an error code to notify NinjaOne of failure
}


Write-Host "----------------------------------------------------"
Write-Host "Starting AVD Session Host Re-Registration Process..."
Write-Host "Time: $(Get-Date)"
Write-Host "----------------------------------------------------"

try {
    # --- Step 1: Uninstall Existing AVD Agent(s) ---
    Write-Host "Searching for existing AVD Agent installation(s)..."
    $agents = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "Remote Desktop Services Infrastructure Agent" }

    if ($agents) {
        # Loop through each found agent instance. This handles cases where one or more are installed.
        foreach ($agentInstance in $agents) {
            Write-Host "Found Agent: $($agentInstance.Name) (Version: $($agentInstance.Version))"
            Write-Host "Uninstalling instance with ID: $($agentInstance.IdentifyingNumber)..."
            $uninstallProcess = Start-Process "msiexec.exe" -ArgumentList "/x $($agentInstance.IdentifyingNumber) /qn /norestart" -Wait -PassThru
            
            if ($uninstallProcess.ExitCode -eq 0) {
                Write-Host "Instance uninstalled successfully."
            }
            else {
                # 1605 = Product is already uninstalled. Treat as success.
                if ($uninstallProcess.ExitCode -eq 1605){
                     Write-Host "Instance was already uninstalled. Continuing."
                }
                else{
                    # Don't throw a hard error, as the machine might be in a corrupted state.
                    # Warn and attempt to continue with the fresh installation.
                    Write-Warning "Failed to uninstall instance with ID $($agentInstance.IdentifyingNumber). MSIExec Exit Code: $($uninstallProcess.ExitCode). The script will attempt to continue."
                }
            }
        }
    }
    else {
        Write-Host "No existing AVD Agent found. Proceeding to installation."
    }

    # --- Step 2: Download the Latest AVD Agent ---
    Write-Host "Downloading the latest AVD agent from Microsoft..."
    Invoke-WebRequest -Uri $agentDownloadUrl -OutFile $installerPath
    Write-Host "Download complete. Installer saved to: $installerPath"

    # --- Step 3: Reinstall Agent with New Registration Key ---
    Write-Host "Installing the AVD agent and registering with the new host pool..."
    $installProcess = Start-Process "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn REGISTRATIONTOKEN=$RegistrationKey" -Wait -PassThru

    if ($installProcess.ExitCode -ne 0) {
        throw "Failed to install the new agent. MSIExec Exit Code: $($installProcess.ExitCode)"
    }
    
    Write-Host "SUCCESS: Agent re-installed successfully."

    # --- Step 4: Verification ---
    Write-Host "Pausing for 60 seconds to allow agent services to start and attempt registration..."
    Start-Sleep -Seconds 60

    Write-Host "Checking Event Viewer for registration status..."
    $recentEvents = Get-WinEvent -FilterHashtable @{LogName=$eventLogName; StartTime=(Get-Date).AddMinutes(-5)} -ErrorAction SilentlyContinue
    
    if (-not $recentEvents) {
        Write-Warning "Could not find any recent events in the '$eventLogName' log. Manual verification is required after reboot."
    }
    else {
        # Check for the specific success event
        $successEvent = $recentEvents | Where-Object { $_.Id -eq 3701 } # 3701 = Agent successfully connected to broker
        
        if ($successEvent) {
            Write-Host "VERIFICATION SUCCESS: Found Event ID 3701. Agent has successfully connected to the AVD infrastructure."
            $successEvent | Format-List TimeCreated, Message | Out-String | Write-Host
        }
        else {
            Write-Warning "VERIFICATION FAILED: Did not find success Event ID 3701."
            # If no success, check for errors
            $errorEvents = $recentEvents | Where-Object { $_.LevelDisplayName -eq 'Error' }
            if ($errorEvents) {
                Write-Error "Found recent error events in the AVD Agent log:"
                $errorEvents | Format-List TimeCreated, Id, Message | Out-String | Write-Error
            }
            else {
                Write-Warning "No specific success or error events found. The agent may still be trying to connect. Manual verification is recommended."
            }
        }
    }
}
catch {
    Write-Error "An error occurred during the process."
    Write-Error $_.Exception.Message
}
finally {
    # --- Step 5: Cleanup and Reboot ---
    if (Test-Path -Path $installerPath) {
        Write-Host "Cleaning up downloaded installer file..."
        Remove-Item -Path $installerPath -Force
    }

    Write-Host "Cleaning up old log files..."
    try {
        $logFiles = Get-ChildItem -Path $logDirectory -Filter "$($logFileBaseName)_*.log" | Sort-Object CreationTime -Descending
        if ($logFiles.Count -gt $maxLogsToKeep) {
            $logsToDelete = $logFiles | Select-Object -Skip $maxLogsToKeep
            Write-Host "Found $($logsToDelete.Count) old logs to delete."
            foreach ($log in $logsToDelete) {
                Write-Host "Deleting log: $($log.FullName)"
                Remove-Item $log.FullName -Force
            }
        }
        else {
            Write-Host "No old logs to delete."
        }
    }
    catch {
        Write-Warning "Could not perform log cleanup: $_"
    }

    Write-Host "----------------------------------------------------"
    Write-Host "Script finished. Rebooting machine to finalize changes."
    Write-Host "----------------------------------------------------"
    Stop-Transcript
    
    # Reboot is the very last command. The script will terminate here.
    Restart-Computer -Force
}
