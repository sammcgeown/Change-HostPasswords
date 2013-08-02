Param (	[String] $vCenter 					= (Read-Host "Enter Virtual Center"),
		[String] $Location 					= (Read-Host "Enter VMHost Location (can be a vCenter, DataCenter, Cluster or * for all)"),
		[SecureString] $RootPassword 		= (Read-Host "Enter current root password" -AsSecureString),
		[SecureString] $NewPassword 		= (Read-Host "Enter new root password" -AsSecureString),
		[SecureString] $NewPasswordVerify 	= (Read-Host "Re-enter new root password" -AsSecureString)
)

# Test that the new password and verified one match, if not abort!
if($NewPassword -ne $NewPasswordVerify) {
	Throw "Entered passwords do not match"
}

# Define a log file
$LogFile = "Change-HostPasswords.csv"
# Rename the old log file, if it exists
if(Test-Path $LogFile) {
	$DateString = Get-Date((Get-Item $LogFile).LastWriteTIme) -format MMddyyyy
	Move-Item $LogFile "$LogFile.$DateString.csv" -Force -Confirm:$false
}
# Add some CSV headers to the log file
Add-Content $Logfile "Date,Location,Host,Result"

# Hide the warnings for certificates (or better, install valid ones!)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Create credential objects using the supplied passwords
$RootCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist "root",$RootPassword
$NewRootCredential = new-object -typename System.Management.Automation.PSCredential -argumentlist "root",$NewPassword
$NewRootCredentialVerify = new-object -typename System.Management.Automation.PSCredential -argumentlist "root",$NewPasswordVerify

# Connect to the vCenter server
Connect-VIServer $vCenter

# Create an object for the root account with the new pasword
$RootAccount = New-Object VMware.Vim.HostPosixAccountSpec
$RootAccount.id = "root"
$RootAccount.password = ($NewRootCredential.GetNetworkCredential().Password)
$RootAccount.shellAccess = "/bin/bash"

# Get the hosts from the Location
$VMHosts = Get-VMHost -Location $Location

# For each host
$VMHosts | % {
	# Disconnect any connected sessions - prevents errors getting multiple ServiceInstances
	$global:DefaultVIServers | Disconnect-VIServer -Confirm:$false
	Write-Debug ($_.Name + " - attempting to connect")
	# Create a direct connection to the host
	$VIServer = Connect-VIServer $_.Name -User "root" -Password ($RootCredential.GetNetworkCredential().Password) -ErrorAction SilentlyContinue
	# If it's connected
	if($VIServer.IsConnected -eq $True) {
		Write-Debug ($_.Name + " - connected")
		$VMHost = $_
		# Attempt to update the Root user object using the account object we created before
		# Catch any errors in a try/catch block to log any failures.
		try {
			$ServiceInstance = Get-View ServiceInstance
			$AccountManager = Get-View -Id $ServiceInstance.content.accountManager 
			$AccountManager.UpdateUser($RootAccount)
			Write-Debug ($VMHost.Name + " - password changed")
			Add-Content $Logfile ((get-date -Format "dd/MM/yy HH:mm")+","+$VMHost.Parent+","+$VMHost.Name+",Success")
		}
		catch {
			Write-Debug ($VMHost.Name + " - password change failed")
			Write-Debug $_
			Add-Content $Logfile ((get-date -Format "dd/MM/yy HH:mm")+","+$VMHost.Parent+","+$VMHost.Name+",Failed (Password Change)")
		}
		# Disconnect from the server
		Disconnect-VIServer -Server $VMHost.Name -Confirm:$false -ErrorAction SilentlyContinue
		Write-Debug ($VMHost.Name + " - disconnected")
	} else {
		# Log any connection failures
		Write-Debug ($_.Name+" - unable to connect")
		Add-Content $Logfile ((get-date -Format "dd/MM/yy HH:mm")+","+$_.Parent+","+$_.Name+",Failed (Connection)")
	}
}