# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# enable-bde.ps1 - Enable BitLocker drive encryption
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description - Intended to be used with as a Syncro policy setup script, determine if BDE is enabled, and if not,
#               confirm TPM is present and ready and enable BDE.  Ticket as appropriate.  The only drive to be
#               encrypted is C:.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Date     Notes
# -------- ------------------------------------------------------------------------------------------------------------
# 20200305 Initial Version (software@tsmidwest.com)
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #


###
### Definitions
###
$ASSETFIELD = "BitLocker Recovery Password (C:)" ### Syncro custom asset field to store BDE recovery password
$ISSUETYPE  = "xxxxxxxxxxx"                      ### Sycnro ticket issue type
$SUBDOMAIN  = "xxxxxxxxx"                        ### Syncro subdomain


###
### PowerShell runtime options
###
$ErrorActionPreference = "SilentlyContinue"
$WarningPreference     = "SilentlyContinue"


###
### Modules
###
Import-Module $env:SyncroModule


###
### Determine if BDE is already enabled for C: by looking at VolumeStatus element of the $BitLockerVolume object. If
### status is "FullyDecrypted" then assume BDE needs to be enabled; otherwise encryption of some sort is already in
### use and we can check for a RecoveryPassword protector.
###
$BitLockerVolume = Get-BitLockerVolume -MountPoint C:
if($BitLockerVolume.VolumeStatus -ne "FullyDecrypted") {
    Write-Host "C: volume status is not `"FullyDecrypted`" ($(BitLockerVolume.VolumeStatus)), checking for RecoveryPassword protector..."
    ###
    ### Ensure a RecoveryPassword key protector is present
    ###
    $RecoveryPassword = ""
    foreach($KeyProtector in $BitLockerVolume.KeyProtector) {
        if($KeyProtector.KeyProtectorType -eq "RecoveryPassword") {
            $RecoveryPassword = $KeyProtector.RecoveryPassword
        }
    }
    ###
    ### If no RecoveryPassword protector, add one
    ###
    if($RecoveryPassowrd -eq "") {
        Write-Host "Add RecoveryKey protector..."
        $BitLockerVolume = Add-BitLockerKeyProtector -MountPoint C: -RecoveryPasswordProtector
    }
    ###
    ### Update Syncro with recovery password
    ###
    Set-Asset-Field -Subdomain $SUBDOMAIN -Name $ASSETFIELD -Value $BitLockerVolume.KeyProtector.RecoveryPassword
    Write-Host "Exiting"
    Exit 0
}


###
### Ensure we're running Windows 10
###
if($([System.Environment]::OSVersion.Version.Major) -ne "10") {
    $SyncroTicket = Create-Syncro-Ticket -Subdomain $SUBDOMAIN -Subject "BitLocker Drive Encryption on $($env:computername)" -IssueType $ISSUETYPE -Status "New"
    Create-Syncro-Ticket-Comment -Subdomain $SUBDOMAIN -TicketIdOrNumber $SyncroTicket.ticket.id -Subject "Windows Version Check Failed" -Body "System is not running Windows 10, enable-bde.ps1 requires Windows 10."
    Exit 1
}


###
### Confirm TPM is present/ready
###
$GetTPM = Get-TPM
if($GetTPM.TpmPresent -ne $True -Or $GetTPM.TpmReady -ne $True) {
    $SyncroTicket = Create-Syncro-Ticket -Subdomain $SUBDOMAIN -Subject "BitLocker Drive Encryption on $($env:computername)" -IssueType $ISSUETYPE -Status "New"
    Create-Syncro-Ticket-Comment -Subdomain $SUBDOMAIN -TicketIdOrNumber $SyncroTicket.ticket.id -Subject "TPM Check Failed" -Body "TPM is not present and ready; enable-bde.ps1 requires functioning TPM."
    Exit 1
}


###
### Enable BDE with RecoveryPassword protector
###
try {
    $BitLockerVolume = Enable-BitLocker -MountPoint C: -EncryptionMethod Aes128 -RecoveryPasswordProtector
} catch {
    $SyncroTicket = Create-Syncro-Ticket -Subdomain $SUBDOMAIN -Subject "BitLocker Drive Encryption on $($env:computername)" -IssueType $ISSUETYPE -Status "New"
    Create-Syncro-Ticket-Comment -Subdomain $SUBDOMAIN -TicketIdOrNumber $SyncroTicket.ticket.id -Subject "Enable BDE Failed" -Body "Attempt to enable BitLocker drive encryption failed."
    Exit 1
}    


###
### Add BitLocker auto generated recovery password to Syncro asset
###
Set-Asset-Field -Subdomain $SUBDOMAIN -Name $ASSETFIELD -Value $BitLockerVolume.KeyProtector.RecoveryPassword


###
### Add TPM password protector to ensure drive cannot be used outside of current system (motherboard)
###
try {
    $BitLockerVolume = Add-BitLockerKeyProtector -MountPoint C: -TpmProtector
} catch {
    $SyncroTicket = Create-Syncro-Ticket -Subdomain $SUBDOMAIN -Subject "BitLocker Drive Encryption on $($env:computername)" -IssueType $ISSUETYPE -Status "New"
    Create-Syncro-Ticket-Comment -Subdomain $SUBDOMAIN -TicketIdOrNumber $SyncroTicket.ticket.id -Subject "Add TPM Protector Failed" -Body "Attempt to add BitLocker TPM protector failed."
    Exit 1
}


###
### End script
###
$SyncroTicket = Create-Syncro-Ticket -Subdomain $SUBDOMAIN -Subject "BitLocker Drive Encryption on $($env:computername)" -IssueType $ISSUETYPE -Status "Resolved"
Create-Syncro-Ticket-Comment -Subdomain $SUBDOMAIN -TicketIdOrNumber $SyncroTicket.ticket.id -Subject "Encryption In Progress" -Body "BitLocker drive encryption enabled; encryption of C: will start after next reboot."
Exit 0
