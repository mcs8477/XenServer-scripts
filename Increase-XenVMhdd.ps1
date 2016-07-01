#  Purpose: Increase the hard drive size of Virtual machines running on XenServer
#
#  REQUIREMENTS:  Due to "fun" with Citrix Powershell modules / Snap-ins, this script can 
#		only run ON a Xen Controller, that also has the XenServer powershell snap-in
#		installed.  Run from Citrix XenServer PowerShell SnapIn Powershell Shortcut
#
#  Author : mcs8477
#  Version: 1.1 
#  Release: 07/1/2016                                                         
#
# ============================================================================================

# ======================================================================
# -- C O N S T A I N T S
# ======================================================================
$MaxHDDsize = 120
$BytesInGBytes = 1024 * 1024 * 1024
#$MinimumHDDsizeGB = 60  # ** Could prompt for this value
#$MinimumHDDsizeBytes = $MinimumHDDsizeGB * $BytesInGBytes

$ReportName = ".\XenVMlist.csv"		
# ** Reporting object properties
$VMproperties = @{
	Name=$null
	PowerState=$null
	VBDdevice=$null
	VBDtype=$null
	VDIname=$null
	VDIPrevVSizeGB=$null
	VDIPrevUtilizationGB=$null
	VDICurrentVSizeGB=$null
	VDICurrentUtilizationGB=$null
	DiskStatus=$null	
	}
	
# ** Create the empty Report Collection (array)
$colVMs=@()

# ======================================================================
# -- F U N C T I O N S
# ======================================================================
Function Get-MinHddSize {
	cls
	write-host "************************************************************" -BackgroundColor Blue -ForegroundColor White
	write-host "This script will look for XenServer VMs with hard drive     " -BackgroundColor Blue -ForegroundColor White
	write-host "sizes below a specified value, and attempt to increase      " -BackgroundColor Blue -ForegroundColor White
	write-host "the allocation in XenServer and Extend the volume in        " -BackgroundColor Blue -ForegroundColor White
	write-host "Windows.  It will query XenDesktop to determine if the VM   " -BackgroundColor Blue -ForegroundColor White
	write-host "is in use and can be shutdown to perform the operation.     " -BackgroundColor Blue -ForegroundColor White
	Write-Host "                                                            " -BackgroundColor Blue -ForegroundColor White
	write-host "************************************************************" -BackgroundColor Blue -ForegroundColor White
	write-host "Type the Minimum hard drive size in GB Followed by [ENTER]  " -BackgroundColor Blue -ForegroundColor Yellow
	Write-Host "                                                            " -BackgroundColor Blue -ForegroundColor White
	[int]$MinSize = Read-Host 
	if ($MinSize -gt $MaxHDDsize ) {
		Write-Host " "
		Write-Host "WARNING:  Hard drive size selected it larger than $MaxHDDsize" -BackgroundColor White -ForegroundColor Red
		Write-Host "          Resetting to $MaxHDDsize  !!!                      " -BackgroundColor White -ForegroundColor Red
		$MinSize = $MaxHDDsize
	} # END if $MinSize
	return $MinSize
	
} # END Get-MinHddSize

Function Get-PoolMasters {
# ============================================================================================
# -- Get-PoolMasters
# ============================================================================================
#	Parameters:
#		None
#		
#	Example Use:
#		Get-PoolMasters
# ============================================================================================
	$PoolMasters = @()
	$Done = $false
	do {
		cls
		write-host "Currently Entered Pool Master(s):              " -BackgroundColor Blue -ForegroundColor White
		write-host $PoolMasters | Format-List -BackgroundColor Blue -ForegroundColor White
		write-host "                                               " -BackgroundColor Blue -ForegroundColor White
		write-host "===============================================" -BackgroundColor Blue -ForegroundColor White
		write-host "                                               " -BackgroundColor Blue -ForegroundColor White
		write-host "Enter any additional XenServer Pool Master FQDN" -BackgroundColor Blue -ForegroundColor White
		write-host "OR leave blank if done, Followed by [ENTER]    " -BackgroundColor Blue -ForegroundColor White
		Write-Host "                                               " -BackgroundColor Blue -ForegroundColor White
		$XenServer = Read-Host 
		if ($XenServer) {
			$PoolMasters += $XenServer
			$XenServer = ""
		} # END if $XenServer
		else {
			$Done = $true
			}
	} # End do
	Until ($Done)
	return $PoolMasters
} # END Get-PoolMasters

Function Get-YesOrNo {
# ============================================================================================
# -- Get-YesOrNo
# ============================================================================================
#	Parameters:
#		$PromptStr - Yes or No question in string format
#		
#	Example Use:
#		Get-YesOrNo "Create Virtual Machine ???"
# ============================================================================================
	Param (
		[Parameter(Mandatory=$true)]
		[String] $PromptStr
	) # END Param block
	
	Write-Host " "
	Write-Host $PromptStr -BackgroundColor Blue -ForegroundColor White
	Write-Host "  -- Please type (" -BackgroundColor Blue -ForegroundColor White -NoNewline
	Write-Host "Y" -BackgroundColor Blue -ForegroundColor Green -NoNewline
	Write-Host "es/" -BackgroundColor Blue -ForegroundColor White -NoNewline
	Write-Host "N" -BackgroundColor Blue -ForegroundColor Red -NoNewline
	Write-Host "o), Followed by [ENTER] " -BackgroundColor Blue -ForegroundColor White 
	$Continue = Read-Host

	if ($Continue -like "Y*") {
		$true
		}
	else {
		$false
	}	# End IF
} # END Get-YesOrNo

Function Test-ADPassword {
# ============================================================================================
# -- Test-ADPassword
# ============================================================================================
#	Parameters:
#		$Cred - PSCredential Object
#
#	Example Use:  
#		Simple - 
#			Test-ADPassword $MyCred
#
# 		Typical - Continue prompting for Credentials until valid
#			do {
#				$MyCred = Get-Credential -Message "Please provide credentials"
#			}
#			until (Test-ADPassword $MyCred)
# ============================================================================================
	Param (
		[Parameter(Mandatory=$true)]
		[PSCredential] $Cred
	) # END Param block

	# **** User must be in the same domain as the currently logged on user for the authentication test to work ***
	Write-Host "Validating user: " $Cred.Username " ..."

	# Get current domain using logged-on user's credentials
	$CurrentDomain = "LDAP://" + ([ADSI]"").distinguishedName
	$Domain = New-Object System.DirectoryServices.DirectoryEntry($CurrentDomain,$($Cred.Username),$($Cred.GetNetworkCredential().password))
	  
	if ($Domain.name -eq $null){
	 	write-host "Authentication failed for " $Cred.Username -BackgroundColor Red -ForegroundColor White
		Write-Host "Enter a valid username and password"
		$false
	}
	else {
	  write-host "Authentication success for " $Cred.Username -BackgroundColor Black -ForegroundColor Green
	  $true
	}
	$Password = $null

}  # END Test-ADPassword
# ======================================================================
# -- M A I N
# ======================================================================

# ** Add the required PowerShell modules
try {
	Import-Module "Citrix.XenDesktop.Admin" -Force -ErrorAction Stop
	Import-Module "ActiveDirectory" -Force -ErrorAction Stop
	Add-PSSnapin Citrix.* -ErrorAction Stop
	} # End try
catch {
		Write-Host " "
		Write-Host "=========================================================================================" -BackgroundColor Red -ForegroundColor White
		Write-Host "W A R N I N G:  Unable to load the required modules for provided PowerShell CMDLETS !!   " -BackgroundColor Red -ForegroundColor White
		Write-Host "=========================================================================================" -BackgroundColor Red -ForegroundColor White
		Write-Host " "
	} # End catch

$MinimumHDDsizeGB = Get-MinHddSize 
$MinimumHDDsizeBytes = $MinimumHDDsizeGB * $BytesInGBytes

# ** Provide Domain Credentials
do {
	$MyCred = Get-Credential -Message "Please provide DOMAIN credentials" -UserName "$ENV:USERDOMAIN\$ENV:USERNAME"
}
until (Test-ADPassword $MyCred)

$XenServer_PoolMasters = Get-PoolMasters

cls
# ** Loop thru XenServer Pools
Foreach	($XenServer_PoolMaster in $XenServer_PoolMasters) {
	Connect-XenServer -Server $XenServer_PoolMaster -SetDefaultSession -creds $MyCred
	$VMs = Get-XenVM
	Write-Host "Checking VMs, this may take some time..."
	foreach ($VM in $VMs) {
		# ** Follow Xenserver's convoluted path to get to the hard drive details
		foreach ($VMvbd in $VM.vbds) {
			$VBD = Get-XenVBD $VMvbd
			if ($VBD.type -eq "Disk") {
				$VDI = Get-XenVDI $VBD.VDI
				# $VDI is actually the virtual hard drive...whoo hoo and OMG
				# Check for HDD under 60GB (C: Drive should be only HDD)
				if ($VDI.virtual_size -lt $MinimumHDDsizeBytes) {
					Write-Host "========================================================"
					Write-Host $VM.name_label " has less than" $MinimumHDDsizeGB "GB"					
					$VMobj = New-Object PSObject -Property $VMProperties
					$VMobj.Name = $VM.name_label
					$VMobj.PowerState = $VM.power_state
					$VMobj.VBDdevice = $VBD.device
					$VMobj.VBDtype = $VBD.type
					$VMobj.VDIname = $VDI.name_label
					$VMobj.VDIPrevVSizeGB = ($VDI.virtual_size / $BytesInGBytes)
					$VMobj.VDIPrevUtilizationGB = ($VDI.physical_utilisation / $BytesInGBytes)
					$VMobj.DiskStatus="Needs to be Resized"
					
					# ** Running from Controllers and use get-brokerdesktop to determine if VM is in use
					# ** Assuming computer accounts are in the same domain as the user
					$MachineName = "$ENV:USERDOMAIN\" + $VM.name_label
					# ** if it exists, then it is a Windows VM registered with XenDesktop
					$BD = get-brokerdesktop -machinename $MachineName -ErrorAction SilentlyContinue
					if ($BD){
					 	if ($BD.SessionState -eq $null) {
					 		Write-Host "VM currently does not have any sessions logged in"
							#** If prefer to prompt to perform disk resize, uncomment following line
							#$ResizeHDD = get-YesOrNo "Resize the hard drive of this VM??"
							$ResizeHDD = $true
							} # END if $BD.SessionState
						else {
							$VMobj.DiskStatus = "User logged in, Needs to be Resized"
							Write-Host "VM has a user session, bypassing disk resize"
							$ResizeHDD = $false
							} # END else $BD.SessionState 
						} # END if $BD (BrokerDesktop configured)	
					else {
						Write-host "VM not found in XenDesktop"
						$ResizeHDD = $false
						$VMobj.DiskStatus = "VM Not in XenDesktop, Hard drive resize needed"
						} # END else $BD 		
					
					if ($ResizeHDD) {
					# ** Issue shutdown of VM
						if ($VM.power_state -eq "Running") {
							Invoke-XenVM -VM $VM -XenAction CleanShutdown -Async 
							Write-Host "--Waiting for vm to shutdown [" -NoNewline
							$cnt = 1
							do {
								Start-Sleep -Seconds 2
								Write-Host "." -NoNewline -BackgroundColor Yellow
								$RefreshVMState = Get-XenVM $VM
								$cnt ++ 
								if ($cnt -eq 480) { 
									# ** If shutdown has taken (480 * 2) seconds or 16 minutes
									# ** Try force power off but continue loop.  Used -eq comparison
									# ** so that the hard shutdown is only issued once.
									Invoke-XenVM -VM $VM -XenAction HardShutdown -Async 
								} # END if $cnt
							} until ($RefreshVMState.power_state -eq "Halted")
						} # END if $VM.power_state
						Write-Host "] "
						# ** Resize the hard drive
						#set-XenVDI -VDI $VDI -VirtualSize $MinimumHDDsizeBytes
						Write-Host "--Resizing hard drive to" $MinimumHDDsizeGB "GB"
						Invoke-XenVDI -VDI $VDI -XenAction Resize -size $MinimumHDDsizeBytes
						
						Write-Host "--Powering on vm"
						Invoke-XenVM -VM $VM -XenAction Start -Async
						
						# ** Get new size of VM
						$VDI = Get-XenVDI $VBD.VDI
						$VMobj.VDICurrentVSizeGB = ($VDI.virtual_size / $BytesInGBytes)
						$VMobj.VDICurrentUtilizationGB = ($VDI.physical_utilisation / $BytesInGBytes)
						$VMobj.DiskStatus="Resized"
						
						# ** Waiting for VM to power on.  MachineInternalState indicates that it has re-registered
						# ** with Xen Controllers, so it is largely available.
						Write-Host "--Waiting for vm to startup [" -NoNewline
							$StartUpCnt = 1
							$MoveOn = $false
							do {
								Start-Sleep -Seconds 5
								Write-Host "." -NoNewline -BackgroundColor Green
								$CheckVMState = Get-BrokerDesktop $MachineName
								
								if ($CheckVMState.MachineInternalState -eq "Available") {$MoveOn = $true}
								# ** OR **
								if ($StartUpCnt -gt 20) {$MoveOn = $true;Write-Host "@" -BackgroundColor Green -ForegroundColor DarkRed -NoNewline}
								$StartUpCnt ++
							} until ($MoveOn)
						# ** Giving just a little more delay	
						Start-Sleep -Seconds 10
						Write-Host "." -NoNewline -BackgroundColor Green
						Start-Sleep -Seconds 10
						Write-Host "." -NoNewline -BackgroundColor Green
						Write-Host "] " 
						
						# ** Extend the Volume in Windows
						Write-Host "Extending the Volume in Windows"
						Invoke-Command -ComputerName $VM.name_label -Credential $MyCred -ScriptBlock {
							"rescan","select volume C","extend" | diskpart }
						
					} # END if $ResizeHDD
					$colVMs += $VMobj
				} # END if less than 60GB
				
			} # END if type is DISK
		} # END foreach VBD
	} # END foreach VM
	Disconnect-XenServer 
} # END foreach PoolMaster

# ** Export results to .CSV 
$colVMs | Export-Csv $ReportName 
		
# ======================================================================
# -- E N D
# ======================================================================
