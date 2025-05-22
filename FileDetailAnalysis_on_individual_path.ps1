param (
    [string]$vserver_name,
    [string]$path,
    [string]$OutputFolder,
    [int]$MaxFileSizeMB = 300  # Maximum file size before splitting (default: 300MB)
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
$OutputCSVBase = "$OutputFolder\File_Discovery_$DateTimeStamp"
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
    param ( [string]$UNCPath, [string]$ProblemPath, [string]$ErrorMessage)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - UNC Path: $UNCPath | Problem Path: $ProblemPath | Message: $ErrorMessage" | Out-File -FilePath $ErrorLogFile -Append
    Write-Host "UNC Path: $UNCPath | Problem Path: $ProblemPath | Message: $ErrorMessage" -ForegroundColor Red
}

# Initialize CSV with headers
$FileIndex = 1
$CurrentCSV = "${OutputCSVBase}_Part${FileIndex}.csv"
"ServerName|FullName|Date Created|Date Modified|Owner|Authors|Last Saved By|Length|Extension|Attributes|DirectoryName|Name" | Out-File -FilePath $CurrentCSV -Encoding utf8

# Assign Variables
$vserver = $vserver_name
$uncPath = $path
$uncPath = $uncPath -replace '[\r\n]+', ' '  # Remove unwanted line breaks

# Validate Path
if (-not (Test-Path -LiteralPath $uncPath)) {
    Write-ErrorLog -UNCPath $uncPath -ProblemPath $uncPath -ErrorMessage "UNC path not accessible"
    Write-Log "Skipping path: UNC Path: $uncPath is not accessible."
} 
else {
    Write-Log "Starting scan for: $uncPath"
    
    # Function to check and rotate CSV file if needed
    function Check-And-Rotate-CSV {
        $CurrentSizeMB = (Get-Item $CurrentCSV).Length / 1MB
        if ($CurrentSizeMB -ge $MaxFileSizeMB) {
            $script:FileIndex++
            $script:CurrentCSV = "${OutputCSVBase}_Part${script:FileIndex}.csv"
            "ServerName|FullName|Date Created|Date Modified|Owner|Authors|Last Saved By|Length|Extension|Attributes|DirectoryName|Name" | Out-File -FilePath $CurrentCSV -Encoding utf8
        }
    }
    
    # Function to recursively scan folders
    function Scan-Folder {
        param ([string]$FolderPath)

        Write-Host "Scanning Folder: $FolderPath" -ForegroundColor Cyan
        # Write-Log "Scanning Folder: $FolderPath"

        try {
            $Items = Get-ChildItem -LiteralPath $FolderPath -ErrorAction Stop

            foreach ($Item in $Items) {
                if ($Item.PSIsContainer) {
                    # If it's a folder, attempt to scan it
                    try {
                        Scan-Folder -FolderPath $Item.FullName  # Recursive call
                    }
                    catch {
                        Write-ErrorLog -UNCPath $uncPath -ProblemPath $Item.FullName -ErrorMessage "Skipping inaccessible folder"
                        Write-Log "Skipping Folder: $Item.FullName (ACCESS DENIED)"
                        continue  # Skip to next folder
                    }
                }
                else {
                    # If it's a file, process it
                    Write-Host "Processing File: $Item.FullName" -ForegroundColor Yellow
                    try {
                        $Owner = "Unknown_Owner"  # Default value
                        try {
                            $Metadata = $Item.GetAccessControl()
                            if ($Metadata) { 
                                $Owner = $Metadata.Owner 
                            }
                        }
                        catch {
                            Write-Log "File: $Item.FullName - Owner retrieval failed, continuing with other fields"
                        }
                    
                        $Data = ('"{0}"|"{1}"|"{2}"|"{3}"|"{4}"|"{5}"|"{6}"|"{7}"|"{8}"|"{9}"|"{10}"|"{11}"' -f 
                            $vserver, $Item.FullName, $Item.CreationTime, $Item.LastWriteTime, $Owner, "", "", 
                            $Item.Length, $Item.Extension, $Item.Attributes, $Item.DirectoryName, $Item.Name) -replace '[\r\n]+', ' '
                    
                        Check-And-Rotate-CSV  # Check if we need a new file
                        $Data | Out-File -FilePath $CurrentCSV -Append -Encoding utf8
                    }
                    catch {
                        Write-ErrorLog -UNCPath $uncPath -ProblemPath $Item.FullName -ErrorMessage $_
                        Write-Log "Skipping File: $Item.FullName (ACCESS DENIED)"
                        continue  # Skip to next file
                    }
                }
            }
        }
        catch {
            Write-ErrorLog -UNCPath $uncPath -ProblemPath $FolderPath -ErrorMessage "Skipping inaccessible folder"
            Write-Log "Skipping Folder: $FolderPath (ACCESS DENIED)"
        }
    }

    # Start recursive scan
    Scan-Folder -FolderPath $uncPath

    Write-Host "Scan completed for: $uncPath" -ForegroundColor Green
}

# End time tracking
$EndTime = Get-Date  
$ExecutionTime = $EndTime - $StartTime  
$FormattedTime = "{0:D2}:{1:D2}:{2:D2}" -f $ExecutionTime.Hours, $ExecutionTime.Minutes, $ExecutionTime.Seconds

Write-Log "File discovery completed in $FormattedTime (hh:mm:ss). Output saved to: ${OutputCSVBase}_Part*.csv"
Write-Host "File discovery completed in $FormattedTime (hh:mm:ss)." -ForegroundColor Green
