#region Create a new Task Sequence
$TS = New-CMTaskSequence -CustomTaskSequence -Name "Prepare In-Place Upgrade PoSH"
#endregion

#region Create the Root Group
$PrepareIPUGroup = New-CMTaskSequenceGroup -Name "Prepare IPU"
Add-CMTaskSequenceStep -InsertStepStartIndex 0 -TaskSequenceName $TS.Name -Step $PrepareIPUGroup
#endregion

#region Check Readiness Step
$CheckReadinessArgs = @{
    Name        = "Check Readiness"
    CheckMemory = $True
    Memory      = 2000
    CheckSpeed  = $True
    Speed       = 1000
    CheckSpace  = $True
    DiskSpace   = 20000
    CheckOS     = $True
    OS          = "Client"
}
$PrestartCheckStep = New-CMTSStepPrestartCheck @CheckReadinessArgs

Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $PrestartCheckStep -InsertStepStartIndex 0
#endregion

#region LanguageDetection Step
$LanguageDetectionScript = @"
# Script OSDDetectInstalledLP.ps1 - Version 170810
# 161008 - Added OSArchitecture and OSVersion detection
# 161009 - Added OSSKU detection
# 170118 - Added LTSB to SKU List and fixed architecture detection for spanish installations which return 64-Bits
# 170810 - Changed UILanguage detection (feedback from blog post - Kudos to Dan)
# ----------------------------------------------------------------------------------------------------------------------------------------
# ***** Disclaimer *****
# This file is provided "AS IS" with no warranties, confers no 
# rights, and is not supported by the authors or Microsoft 
# Corporation. Its use is subject to the terms specified in the 
# Terms of Use (http://www.microsoft.com/info/cpyright.mspx).
# ----------------------------------------------------------------------------------------------------------------------------------------
# Purpose of this script is to easily detect all languages installed on the current OS
# Additional information like OS Version, Architecture and OSSKU will be enumerated as well
# After running this Script inside a Task Sequence zou will have folloging variables accessable
# OSVersion - Sample Value: 6.3.9600
# OSArchitecture - Sample Value: 64-Bit
# OSSKU - Sample Value: ENTERPRISE
# CurrentOSLanguage - Sample Value: de-de
# MUILanguageCount - Sample Value: 2
# OSDDefaultUILanguage - Sample Value: de-de (is only applicable if OSDRegionalSettings.ps1 was used to install device)
# Dynamic Variable where Name matches the detected Language for example de-de - Sample Value: True
# ----------------------------------------------------------------------------------------------------------------------------------------
# Declare Variables
# ----------------------------------------------------------------------------------------------------------------------------------------

[String]$LogFile = "$env:WinDir\CCM\Logs\" + $($((Split-Path $MyInvocation.MyCommand.Definition -leaf)).replace("ps1","log"))
[String]$ScriptPath = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent
[String]$CurrentOSLanguage

# ----------------------------------------------------------------------------------------------------------------------------------------
# Function Section
# ----------------------------------------------------------------------------------------------------------------------------------------

Function Write-ToLog([string]$message, [string]$file) {
    <#
    .SYNOPSIS
        Writing log to the logfile
    .DESCRIPTION
        Function to write logging to a logfile. This should be done in the End phase of the script.
    #>
    If(-not($file)){$file=$LogFile}        
    $Date = $(get-date -uformat %Y-%m-%d-%H.%M.%S)
    $message = "$Date `t$message"
    Write-Verbose $message
    Write-Host $message
    #Write Log to log file Without ASCII not able to read with tracer.
    Out-File $file -encoding ASCII -input $message -append
}

Try
{
    $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    Write-ToLog "Script is running inside a Task Sequence"
    $RunningInTs = $True
}
Catch
{
    Write-ToLog "Script is running outside a Task Sequence"
}

$WMIResult = get-wmiobject -class "Win32_OperatingSystem" -namespace "root\CIMV2"

foreach ($objItem in $WMIResult) {
    $MUILanguageCount = $objItem.MUILanguages.count
    $OSArchitecture  = $objItem.OSArchitecture
    If($OSArchitecture -match "32"){$OSArchitecture = "32-Bit"}
    If($OSArchitecture -match "64"){$OSArchitecture = "64-Bit"}
    $OSVersion = $objItem.Version
    $OperatingSystemSKU = $objItem.OperatingSystemSKU
    Write-ToLog "OSVersion detected: $OSVersion"
    If($RunningInTs){$tsenv.Value("OSVersion") = $OSVersion}
    Write-ToLog "OSArchitecture detected: $OSArchitecture"
    If($RunningInTs){$tsenv.Value("OSArchitecture") = $OSArchitecture}
    $OSSKU = switch ($OperatingSystemSKU) 
    { 
        1 {"ULTIMATE"} 
        4 {"ENTERPRISE"} 
        5 {"BUSINESS"}
        7 {"STANDARD_SERVER"}
        10 {"ENTERPRISE_SERVER"}
        27 {"ENTERPRISE_N"} 
        28 {"ULTIMATE_N"}
        48 {"PROFESSIONAL"} 
        125 {"ENTERPRISE_LTSB"} 
        default {"UNKNOWN"}
    }
    Write-ToLog "OSSKU $OperatingSystemSKU detected: $OSSKU"
    If($RunningInTs){$tsenv.Value("OSSKU") = $OSSKU}

    ForEach($Mui in $objItem.MUILanguages)
    {
      Write-ToLog "MUILanguage: $Mui"
      If($RunningInTs){$tsenv.Value($Mui) = $True}
    }
    $LCID = $objItem.OSLanguage
    Write-ToLog "Current LCID detected: $LCID"
} 

Write-ToLog "MUILanguage Count: $MUILanguageCount"

If($MUILanguageCount -gt 1)
{
    Write-ToLog "MUIdetected: True"
    If($RunningInTs)
    {
        $tsenv.Value("MUIdetected") = $True
    }
} 
<#
# Translate LCID information to locale information sample 1031 to en-us
# Convert $LCID to HEX
$LCID = [Convert]::ToString($LCID, 16)
# ensure $LCID is 4 digits
If($LCID.Length -eq 3){$LCID = "0"+$LCID} 

$CurrentOSLanguageLCID = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Classes\MIME\Database\Rfc1766' -Name $LCID).$LCID -split ";"
If($CurrentOSLanguageLCID[0].Length -eq 2)
    {
        $CurrentOSLanguage = ($CurrentOSLanguageLCID[0]+"-"+$CurrentOSLanguageLCID[0])
    }
    Else
    {
        $CurrentOSLanguage = $CurrentOSLanguageLCID[0]
    }
#>

# Using PowerShell to detect OS Language - Feedback from Dan blog post (http://aka.ms/osdsupportteam
$CurrentOSLanguage = (Get-UICulture).Name


Write-ToLog "Detected current OS Language: $CurrentOSLanguage"
If($RunningInTs){$tsenv.Value("CurrentOSLanguage") = $CurrentOSLanguage}

# Just in case OSDRegionalSettings.ps1 has been used for bare metal install check for Get-WinUILanguageOverride
Try
{
    $OSDDefaultUILanguage = Get-WinUILanguageOverride
    If($OSDDefaultUILanguage -eq $Null)
    {
        Write-ToLog "No UI Language Override detected"
    }
    Else
    {
        Write-ToLog "WinUILanguageOverride detected variable OSDDefaultUILanguage set to value: $OSDDefaultUILanguage"
        If($RunningInTs){$tsenv.Value("OSDDefaultUILanguage") = $OSDDefaultUILanguage}
    }
}
catch
{
    Write-ToLog "No UI Language Override detected"
}

"@
$LanguageDetectionArgs = @{
    Name            = "Detect Language Packs"
    SourceScript    = $LanguageDetectionScript
    ExecutionPolicy = "Bypass"

}
$LanguageDetectionStep = New-CMTSStepRunPowerShellScript @LanguageDetectionArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $LanguageDetectionStep -InsertStepStartIndex 1
#endregion

#region Create the Multi Language System Group
$MultiLanguageGroup = New-CMTaskSequenceGroup -Name "Multi Language System Group"
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $MultiLanguageGroup -InsertStepStartIndex 2
#endregion

# TODO Condition on group


#region Set TSVar LanguagePack Download Path
$LangPackDownloadPathTSVarArgs = @{
    Name                      = "Set TSVar LanguagePack Download Path"
    TaskSequenceVariable      = "OSD_LPPATH"
    TaskSequenceVariableValue = "c:\Windows\Temp\IPU\LP"
   
}
$LangPackDownloadPathTSVarStep = New-CMTSStepSetVariable @LangPackDownloadPathTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $MultiLanguageGroup.Name -AddStep $LangPackDownloadPathTSVarStep -InsertStepStartIndex 1
#endregion

#region Create Dummy LangPack Package
$DummyPackagePath = New-Item -Path c:\temp\dummy -ItemType directory -Force
$DummyLangPackPkg = New-CMPackage -Name "Dummy Lang Pack Package" -Path $DummyPackagePath
#endregion

#region Download Language Pack Steps
$Languages = "DE-DE", "FR-FR", "IT-IT"

Foreach ($Language in $Languages) { 
    $DownloadLanguagePackArgs = @{
        Name                = "Download Language Pack & FOD $Language"
        Path                = "%OSD_LPPATH%"
        DestinationVariable = "LanguagePacksExist"
        LocationOption      = "CustomPath"
        AddPackage          = $DummyLangPackPkg
    }
    $DownloadLanguagePackStep = New-CMTSStepDownloadPackageContent @DownloadLanguagePackArgs
    # TODO Condition for Language Pack Step
    Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $MultiLanguageGroup.Name -AddStep $DownloadLanguagePackStep -InsertStepStartIndex 2
}

#endregion

#region Create the Drivers Group
$DriversGroup = New-CMTaskSequenceGroup -Name "Drivers"
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $DriversGroup -InsertStepStartIndex 3
#endregion

#region Set TSVar Drivers Download Path
$DriversDownloadPathTSVarArgs = @{
    Name                      = "Set TSVar Drivers Download Path"
    TaskSequenceVariable      = "OSD_DRVPATH"
    TaskSequenceVariableValue = "c:\Windows\Temp\IPU\Drivers"
   
}
$DriversDownloadPathTSVarStep = New-CMTSStepSetVariable @DriversDownloadPathTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $DriversGroup.Name -AddStep $DriversDownloadPathTSVarStep -InsertStepStartIndex 0
#endregion


#region Create Dummy LangPack Package
New-Item -Path c:\temp\dummydrivers -ItemType directory -Force | Out-Null
$DummyDriversPkg = New-CMDriverPackage -Name "Dummy Drivers Package" -Path "\\localhost\c$\temp\dummydrivers"
#endregion

#region Download Drivers Step
$DownloadDriversArgs = @{
    Name                = "Download HP EliteDesk 800 G2 Drivers"
    LocationOption      = "CustomPath"
    Path                = "%OSD_DRVPATH%"
    DestinationVariable = "DriversExist"
    AddPackage          = $DummyDriversPkg
}
$DownloadDriversStep = New-CMTSStepDownloadPackageContent @DownloadDriversArgs
# TODO Condition for Drivers Pack Step
# TODO Disable Step
# TODO Comments on why drivers here
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $DriversGroup.Name -AddStep $DownloadDriversStep -InsertStepStartIndex 2
#endregion

#region Create the 3rd Party Disk Encryption Group
$3rdPartyEncGroup = New-CMTaskSequenceGroup -Name "3rd Party Disk Encryption"
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $3rdPartyEncGroup -InsertStepStartIndex 4
#endregion

#region Set TSVar Drivers Download Path
$3rdPartyEncTSVarArgs = @{
    Name                      = "Set TSVar Disk Encryption Download Path"
    TaskSequenceVariable      = "OSD_DISKENCPATH"
    TaskSequenceVariableValue = "c:\Windows\Temp\IPU\Disk"
   
}
$3rdPartyEncTSVarStep = New-CMTSStepSetVariable @3rdPartyEncTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $3rdPartyEncGroup.Name -AddStep $3rdPartyEncTSVarStep -InsertStepStartIndex 0
#endregion

#region Download 3rd Party Encryption Step
$Download3rdPartyEncArgs = @{
    Name                = "Download 3rd Party Disk Encryption"
    LocationOption      = "CustomPath"
    Path                = "%OSD_DISKENCPATH%"
    DestinationVariable = "DiskEncryptionExist"
    AddPackage          = $DummyDriversPkg
}
$Download3rdPartyEncStep = New-CMTSStepDownloadPackageContent @Download3rdPartyEncArgs
# TODO Condition for Drivers Pack Step
# TODO Disable Step

Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $3rdPartyEncGroup.Name -AddStep $Download3rdPartyEncStep -InsertStepStartIndex 2
#endregion

#region Create the Setupconfig.ini Group
$SetupConfigINIGroup = New-CMTaskSequenceGroup -Name "Setupconfig.ini"
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $SetupConfigINIGroup -InsertStepStartIndex 5
#endregion


#region Setupconfig.ini PowerShell Step
# TODO Script Refactoring
$CreateSetupConfigIniScript = @"
# THIS SAMPLE CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# WHETHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
# IF THIS CODE AND INFORMATION IS MODIFIED, THE ENTIRE RISK OF USE OR RESULTS IN
# CONNECTION WITH THE USE OF THIS CODE AND INFORMATION REMAINS WITH THE USER.
<#
.SYNOPSIS
    .
.DESCRIPTION
    Creates the SetupConfig.ini file that is being used for an Windows 10 In-Place Upgrade.
    SetupConfig.ini is honered while doing an Feature Update via Windows Update for Business or 
    deploying an Feature update via SCCM's Windows 10 Services Feature. It allows you to pass 
    additional parameters to the setup.exe, such as ReflectDrivers.

    Use this script as a preperation for your upcomming Windows 10 Feature Update, for example, 
    if you need to have additional language packs and FOD installed (InstallLangPacks).

    Make sure you deploy the required bits as well, such as the cab files for the Language Packs.
.NOTES  
    File Name   : Create-SetupConfigINIFile.ps1
    Author      : marius.wyss@microsoft.com
    Version     : 1
    ChangeLog   : initial version
#>


param (
    [Parameter(Mandatory=$true)] [hashtable]$SetupConfigOptions
    # Pass your setup.exe options in a hashtable like: 
    # @{"InstallLangPacks"="C:\Temp\LP"} or @{"InstallLangPacks"="C:\Temp\LP"; "ReflectDrivers"="c:\Temp\Drivers"}
    # Find the available options here https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options")
    # Using the SCCM Tasksequence Step Run Powershell command, in the parameter filed add -> -SetupConfigOptions @{"InstallLangPacks"='%OSD_LPPATH%'; "ReflectDrivers"='%OSD_DRVPATH%'}
    # %OSD_LPPATH% and %OSD_DRVPATH% can be TS Vars.
)

$SetupConfigPath = $env:SystemDrive + "\Users\Default\AppData\Local\Microsoft\Windows\WSUS\SetupConfig.ini"



$SetupConfig = @{"SetupConfig"=$SetupConfigOptions}



function Out-IniFile($InputObject, $FilePath)
{
    $outFile = New-Item -ItemType file -Path $Filepath -Force
    foreach ($i in $InputObject.keys)
    {
        if (!($($InputObject[$i].GetType().Name) -eq "Hashtable"))
        {
            #No Sections
            Add-Content -Path $outFile -Value "$i=$($InputObject[$i])"
        } else {
            #Sections
            Add-Content -Path $outFile -Value "[$i]"
            Foreach ($j in ($InputObject[$i].keys | Sort-Object))
            {
                if ($j -match "^Comment[\d]+") {
                    Add-Content -Path $outFile -Value "$($InputObject[$i][$j])"
                } else {
                    Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])" 
                }
            }
            Add-Content -Path $outFile -Value ""
        }
    }
}

Out-IniFile -InputObject $SetupConfig -FilePath $SetupConfigPath


"@
# TODO Test Params
$Parm = @"
-SetupConfigOptions @{"InstallLangPacks"='%OSD_LPPATH%'; "ReflectDrivers"='%OSD_DRVPATH%'}
"@
$SetupConfigPoshArgs = @{
    Name            = "Create Setupconfig.ini"
    SourceScript    = $CreateSetupConfigIniScript
    ExecutionPolicy = "Bypass"
    Parameter       = $Parm
}
$SetupConfigPoshStep = New-CMTSStepRunPowerShellScript @SetupConfigPoshArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $SetupConfigINIGroup.Name -AddStep $SetupConfigPoshStep -InsertStepStartIndex 0
#endregion
