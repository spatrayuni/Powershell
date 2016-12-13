#PS Script to Download and Install HUK
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Confirm:$false
$sysArch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
$pkgVersion = ""
$tmpDir = "c:\temp\huk\"
#remove old directory if it exists
If (Test-Path $tmpDir){
    Remove-Item -Force -Recurse $tmpDir
}
#determine architecture and correct version to install

$OS = (Get-WmiObject Win32_OperatingSystem).Caption
If ($OS -match "2008")
{
    Write-Host "This is a " $OS " host"
    $salt_file = "software_2008.txt" 
}
ElseIf ($OS -match "2012")
{
    Write-Host "This is a " $OS " host"
    $salt_file = "software_2012.txt"
}

if($sysArch -eq "64-bit"){
    Write-Output "64 Bit Architecture Installed"
    #$pkgVersion = "netapp_windows_host_utilities_7.0_x64.msi"
}
Else{
    Write-Output "32 Bit Architecture Installed"
    $pkgVersion = "netapp_windows_host_utilities_7.0_x86.msi"
    Write-Output "Please install" + $pkgVersion " manually as this Scripts supports only 64bit machines"
}
Write-Output "Package To Be Downloaded And Installed: " $pkgVersion
#Create directory to download installer into
Write-Output "Create Temporary Directory For Download: " $tmpDir
new-item $tmpDir -force -itemtype directory
if($? -ne "true"){
    throw "Could Not Create Temp Directory for Download"
}
#attempt file download from Saltstore artifactory
#leave loop in place from repo version in case additional servers are added
$dlFlag = "false"
$repoServers =  @("saltstore.corp.intuit.net")

    #$file = "software.txt"
    $url = "http://" + $repoServers + "/cto-sd-idc/huk7/" + $salt_file
    Write-Output "Trying To Download From:" $url
    $output_file = $tmpDir + $salt_file
    (New-Object System.Net.WebClient).DownloadFile($url, $output_file)

Get-Content $output_file | %{
For ($i=0; $i -lt $repoServers.Length; $i++) {   
    $pkgVersion = $_
    $url = "http://" + $repoServers[$i] + "/cto-sd-idc/huk7/" + $pkgVersion
    Write-Output "Trying To Download From:" $url
    $output = $tmpDir + $pkgVersion
    (New-Object System.Net.WebClient).DownloadFile($url, $output)
    if($? -eq "true"){
        #Write-Output $pkgVersion + "Downloaded Successfully!"
        $dlFLAG = "true"
        break
    }
    Start-Sleep -Seconds 5
    }
}

$mpio_Flag= $false
$mpio_check = Invoke-Command -ScriptBlock { & cmd /c "mpclaim" -h } -ErrorAction SilentlyContinue
if ($mpio_check -eq $null)
{
    $mpio_Flag = "false"   
}
Elseif ($mpio_check -match "MSFT*" )
{
    $mpio_Flag = "true"    
}
Else
{
    $mpio = 'mpclaim -n -i -d "MSFT2005iSCSIBusType_0x9"' 
    Invoke-Command -ScriptBlock { & cmd /c $mpio }
    $mpio_check = Invoke-Command -ScriptBlock { & cmd /c "mpclaim" -h } -ErrorAction SilentlyContinue
    if ($mpio_check -match "MSFT*" )
    {
        $mpio_Flag = "true"    
    }
}

#check to see if file was downloaded and installed succesfully. Exits if its not the case.
if(($dlFlag -eq "true") -and ($mpio_Flag -eq "true"))
{
    Write-Host "All Packets downloaded successfully"
    Write-Host "Attempting Software Install"
    $Dimexec = "Dism /online /enable-feature:MultipathIo"
    Invoke-Command -ScriptBlock { & cmd /c $Dimexec }
    $mpio = 'mpclaim -n -i -d "MSFT2005iSCSIBusType_0x9"' 
    Invoke-Command -ScriptBlock { & cmd /c $mpio }
   
Get-Content $output_file | %{
        $file = $_.Trim()
        Write-Host $file "is getting executed"
        $FilePath = $tmpdir + $file
        if ($file -ne "netapp_windows_host_utilities_7.0_x64.msi")
        {
            Invoke-Command -ScriptBlock { & cmd /c $FilePath /quiet /norestart }
        }
        else
        {
            Invoke-Command -ScriptBlock { & cmd /c msiexec /i $FilePath MULTIPATHING=1 /quiet /norestart }
        }
        if($? -eq "true"){
            Write-Output "Software Installed Successfully!"
        }
        else{
            throw "Software Could Not Be Installed."
        }
    Start-Sleep -Seconds 20
    }
    Write-Host "HUK/MPIO remediation completed, please enable disk level multipath in Iscsi Initiator and reboot"
}
Elseif(($dlFlag -eq "true") -and ($mpio_Flag -eq "false"))
{
    Write-Host "All Packets downloaded successfully"
    Write-Host "Attempting Software Install"
    $Dimexec = "Dism /online /enable-feature:MultipathIo"
    Invoke-Command -ScriptBlock { & cmd /c $Dimexec }
    Write-Host "Please reboot and run this Script again, as we enabled Multipath first time"
}