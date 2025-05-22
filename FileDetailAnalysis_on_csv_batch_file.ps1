param (
    [string]$vserver_name,
    [string]$CSVPath,  # CSV file containing paths
    [string]$OutputFolder,
    [int]$MaxFileSizeMB = 500  # Maximum file size before splitting (default: 500MB)
)

$StartTime = Get-Date  # Start time tracking

# Validate Output Folder
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
$OutputCSV = "$OutputFolder\File_Discovery_$DateTimeStamp.csv"
$LogFile = "$OutputFolder\File_Discovery_Log_$DateTimeStamp.txt"
$ErrorLogFile = "$OutputFolder\File_Discovery_ErrorLog_$DateTimeStamp.txt"
$SessionLogFile = "$OutputFolder\File_Discovery_Session_$DateTimeStamp.txt"

# Start full transcript logging
Start-Transcript -Path $SessionLogFile -Append

# Function to log messages
function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

# Function to log errors
function Write-ErrorLog {
    param ([string]$UNCPath, [string]$ProblemPath, [string]$ErrorMessage)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp - UNC Path: $UNCPath | Problem Path: |$ProblemPath | Message: $ErrorMessage"
    $LogEntry | Tee-Object -FilePath $ErrorLogFile -Append
    Write-Host $LogEntry -ForegroundColor Red
}

# Initialize CSV with headers
"ServerName|FullName|Date Created|Date Modified|Owner|Authors|Last Saved By|Length|Extension|Attributes|DirectoryName|Name" | Out-File -FilePath $OutputCSV -Encoding utf8

# Validate CSV Path
if (-not (Test-Path -LiteralPath $CSVPath)) {
    Write-Host "CSV file not found: $CSVPath" -ForegroundColor Red | Tee-Object -FilePath $LogFile -Append
    Stop-Transcript
    exit
}

# Read Paths from CSV with UTF-8 Encoding
$PathList = Import-Csv -LiteralPath $CSVPath -Encoding utf8 | Select-Object -ExpandProperty path

# Function to recursively scan folders
function Scan-Folder {
    param ([string]$FolderPath)

    Write-Host "Scanning Folder: $FolderPath" -ForegroundColor Cyan | Tee-Object -FilePath $LogFile -Append

    try {
        $Items = Get-ChildItem -LiteralPath $FolderPath -ErrorAction Stop

        foreach ($Item in $Items) {
            if ($Item.PSIsContainer) {
                # If it's a folder, attempt to scan it
                try {
                    Scan-Folder -FolderPath $Item.FullName  # Recursive call
                }
                catch {
                    Write-ErrorLog -UNCPath $FolderPath -ProblemPath $Item.FullName -ErrorMessage "Skipping inaccessible folder"
                    Write-Log "Skipping Folder: $Item.FullName (ACCESS DENIED)"
                    continue  # Skip to next folder
                }
            }
            else {
                # If it's a file, process it
                Write-Host "Processing File: $Item.FullName" -ForegroundColor Yellow | Tee-Object -FilePath $LogFile -Append

                try {
                    $Owner = "Unknown_Owner"  # Default value

                    try {
                        $Metadata = $Item.GetAccessControl()
                        if ($Metadata) { 
                            $Owner = $Metadata.Owner 
                        }
                    }
                    catch {
                        # Write-ErrorLog -UNCPath $FolderPath -ProblemPath $Item.FullName -ErrorMessage "Failed to retrieve file owner"
                        Write-Log "File: $Item.FullName - Owner retrieval failed, continuing with other fields"
                    }

                    $Data = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}" -f 
                        $vserver_name, $Item.FullName, $Item.CreationTime, $Item.LastWriteTime, $Owner, "", "", 
                        $Item.Length, $Item.Extension, $Item.Attributes, $Item.DirectoryName, $Item.Name

                    $Data | Out-File -FilePath $OutputCSV -Append -Encoding utf8
                }
                catch {
                    Write-ErrorLog -UNCPath $FolderPath -ProblemPath $Item.FullName -ErrorMessage $_
                    Write-Log "Skipping File: $Item.FullName (ACCESS DENIED)"
                    continue  # Skip to next file
                }
            }
        }
    }
    catch {
        Write-ErrorLog -UNCPath $FolderPath -ProblemPath $FolderPath -ErrorMessage "Skipping inaccessible folder"
        Write-Log "Skipping Folder: $FolderPath (ACCESS DENIED)"
    }
}

# Process each path in the CSV
# foreach ($uncPath in $PathList) {
#     if (-not (Test-Path -LiteralPath $uncPath)) {
#         Write-ErrorLog -UNCPath $uncPath -ProblemPath $uncPath -ErrorMessage "UNC path not accessible"
#         Write-Log "Skipping path: UNC Path: $uncPath is not accessible."
#     } 
#     else {
#         Write-Host "Starting scan for: $uncPath" -ForegroundColor Cyan | Tee-Object -FilePath $LogFile -Append

#         # Start recursive scan
#         Scan-Folder -FolderPath $uncPath

#         Write-Host "Scan completed for: $uncPath" -ForegroundColor Green | Tee-Object -FilePath $LogFile -Append
#     }
# }

foreach ($uncPath in $PathList) {
    if (-not (Test-Path -LiteralPath $uncPath)) {
        Write-ErrorLog -UNCPath $uncPath -ProblemPath $uncPath -ErrorMessage "UNC path not accessible"
        Write-Log "Skipping path: UNC Path: $uncPath is not accessible."
    } 
    else {
        $item = Get-Item -LiteralPath $uncPath -ErrorAction Continue
        if ($null -eq $item) {
            Write-ErrorLog -UNCPath $uncPath -ProblemPath $uncPath -ErrorMessage "Unable to resolve path"
            continue
        }

        if ($item.PSIsContainer) {
            Write-Host "Starting scan for: $uncPath" -ForegroundColor Cyan | Tee-Object -FilePath $LogFile -Append
            Scan-Folder -FolderPath $uncPath
            Write-Host "Scan completed for: $uncPath" -ForegroundColor Green | Tee-Object -FilePath $LogFile -Append
        }
        else {
            Write-Host "Processing single file path: $uncPath" -ForegroundColor Yellow | Tee-Object -FilePath $LogFile -Append

            try {
                $Owner = "Unknown_Owner"
                try {
                    $Metadata = $item.GetAccessControl()
                    if ($Metadata) {
                        $Owner = $Metadata.Owner
                    }
                }
                catch {
                    Write-Log "File: $uncPath - Owner retrieval failed, continuing with other fields"
                }

                $Data = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}" -f 
                    $vserver_name, $item.FullName, $item.CreationTime, $item.LastWriteTime, $Owner, "", "", 
                    $item.Length, $item.Extension, $item.Attributes, $item.DirectoryName, $item.Name

                $Data | Out-File -FilePath $OutputCSV -Append -Encoding utf8
            }
            catch {
                Write-ErrorLog -UNCPath $uncPath -ProblemPath $uncPath -ErrorMessage $_
                Write-Log "Skipping File: $uncPath (ACCESS DENIED)"
            }
        }
    }
}



# End time tracking
$EndTime = Get-Date  
$ExecutionTime = $EndTime - $StartTime  
$FormattedTime = "{0:D2}:{1:D2}:{2:D2}" -f $ExecutionTime.Hours, $ExecutionTime.Minutes, $ExecutionTime.Seconds

Write-Log "File discovery completed in $FormattedTime (hh:mm:ss). Output saved to: $OutputCSV"
Write-Host "File discovery completed in $FormattedTime (hh:mm:ss)." -ForegroundColor Green | Tee-Object -FilePath $LogFile -Append

# Stop logging transcript
Stop-Transcript
