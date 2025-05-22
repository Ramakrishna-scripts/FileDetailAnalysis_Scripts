param (
    [string]$netPath,
    [string]$CSVFilePath,
    [string]$OutputFolder,
    [int]$MaxFileSizeMB = 500  # Maximum file size before splitting (default: 500MB)
)

$StartTime = Get-Date  # Start time tracking

if (-not $CSVFilePath -or -not (Test-Path -LiteralPath $CSVFilePath)) {
    Write-Host "Please provide a valid CSV file path." -ForegroundColor Red
    exit
}

if (-not $OutputFolder) {
    Write-Host "Please provide an output folder path." -ForegroundColor Red
    exit
}

# Create Output Directory if not exists
if (!(Test-Path -LiteralPath $OutputFolder)) {
    New-Item -ItemType Directory -LiteralPath $OutputFolder -Force | Out-Null
}

# Generate timestamps
$DateTimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputCSV = "$OutputFolder\File_Discovery_${netPath}_$DateTimeStamp.csv"
$LogFile = "$OutputFolder\File_Discovery_Log_$DateTimeStamp.txt"
$ErrorLogFile = "$OutputFolder\File_Discovery_ErrorLog_$DateTimeStamp.txt"

# Function to log messages
function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

# Function to log errors
function Write-ErrorLog {
    param ([string]$CSVPath, [string]$UNCPath, [string]$ProblemPath, [string]$ErrorMessage)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - ERROR: CSV Path: $CSVPath | UNC Path: $UNCPath | Problem Path: $ProblemPath | Message: $ErrorMessage" | Out-File -FilePath $ErrorLogFile -Append
    Write-Host "ERROR: CSV Path: $CSVPath | UNC Path: $UNCPath | Problem Path: $ProblemPath | Message: $ErrorMessage" -ForegroundColor Red
}

# Initialize CSV with headers
"ServerName|FullName|Date Created|Date Modified|Owner|Authors|Last Saved By|Length|Extension|Attributes|DirectoryName|Name" | Out-File -FilePath $OutputCSV -Encoding utf8

# Read CSV and process paths
$CSVData = Import-Csv -Path $CSVFilePath -Delimiter ","   

foreach ($row in $CSVData) {
    $vserver = $row.'vserver'
    $path = $row.'path'

    # Skip processing if path contains "HomeDirs"
    if ($path -match "HomeDirs") {
        Write-Log "Skipping CSV entry as it contains 'HomeDirs': $path"
        continue  # Skip this row
    }

    $modifiedPath = if ($path -eq "/Audit_Logs") { 
        ($path -replace '^\/([^\/]+)', '$1') -replace '/', '\' 
    } else { 
        ($path -replace '^\/([^\/]+)', '$1_share') -replace '/', '\' 
    }
    
    
    
    $uncPath = "\\$netPath\$modifiedPath"

    Write-Log "Scanning: CSV Path: $path | UNC Path: $uncPath"

    try {
        # Get all directories first
        $Folders = Get-ChildItem -LiteralPath $uncPath -Directory -ErrorAction Stop

        foreach ($Folder in $Folders) {
            # Skip "HomeDirs" and all its subfolders
            if ($Folder.Name -eq "HomeDirs") {
                Write-Log "Skipping Folder: $Folder.FullName (HomeDirs detected)"
                continue  # Skip HomeDirs and do not recurse inside it
            }

            # Process valid subfolders
            Write-Log "Processing Folder: $Folder.FullName"

            # Get all files in the valid subfolder
            $Files = Get-ChildItem -LiteralPath $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue

            foreach ($File in $Files) {
                try {
                    $Metadata = $File.GetAccessControl()
                    $Owner = $Metadata.Owner
                    
                    $Data = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}" -f 
                        $vserver, $File.FullName, $File.CreationTime, $File.LastWriteTime, $Owner, "", "", 
                        $File.Length, $File.Extension, $File.Attributes, $File.DirectoryName, $File.Name
                    
                    $Data | Out-File -FilePath $OutputCSV -Append -Encoding utf8
                } catch {
                    Write-ErrorLog -CSVPath $path -UNCPath $uncPath -ProblemPath $File.FullName -ErrorMessage $_
                    continue  # Skip this file
                }
            }
        }
    } catch {
        Write-ErrorLog -CSVPath $path -UNCPath $uncPath -ProblemPath $uncPath -ErrorMessage $_
        Write-Log "Skipping path: CSV Path: $path | UNC Path: $uncPath due to errors."
        continue  # Skip to the next row in the CSV
    }
}

$EndTime = Get-Date  # End time tracking
$ExecutionTime = $EndTime - $StartTime  # Calculate execution time
$FormattedTime = "{0:D2}:{1:D2}:{2:D2}" -f $ExecutionTime.Hours, $ExecutionTime.Minutes, $ExecutionTime.Seconds

Write-Log "File discovery completed in $FormattedTime (hh:mm:ss). Output saved to: $OutputCSV"
Write-Host "File discovery completed in $FormattedTime (hh:mm:ss)." -ForegroundColor Green
