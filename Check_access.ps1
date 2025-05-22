param (
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# Generate log file name with current date and time
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = "$PSScriptRoot\inaccessible_folders_$timestamp.txt"

function Explore-Path {
    param (
        [string]$CurrentPath
    )

    try {
        $items = Get-ChildItem -LiteralPath $CurrentPath -ErrorAction Stop -Force
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                Explore-Path -CurrentPath $item.FullName
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message -replace "`r?`n", " "  # remove line breaks from error
        $logEntry = "`"$CurrentPath`" | $errorMessage"
        Write-Warning $logEntry
        Add-Content -Path $LogFile -Value $logEntry
    }
}

# Check if input path exists
if (Test-Path -LiteralPath $Path) {
    Explore-Path -CurrentPath $Path
    Write-Output "`nScan complete. Inaccessible folders logged to:`n$LogFile"
} else {
    $errorMsg = "`"$Path`" | The specified path is not accessible or does not exist."
    Write-Error $errorMsg
    Add-Content -Path $LogFile -Value $errorMsg
}
