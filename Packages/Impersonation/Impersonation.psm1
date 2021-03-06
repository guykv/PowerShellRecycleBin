#requires -version 2.0

$script:LOGON32_PROVIDER_DEFAULT = 0

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
	while ($script:ImpContextStack.Count)
	{
		Pop-ImpersonationContext
	}
}

$script:ImpContextStack = New-Object System.Collections.Generic.Stack[System.Security.Principal.WindowsImpersonationContext]
$script:IdStack = New-Object System.Collections.Generic.Stack[System.Security.Principal.WindowsIdentity]

Function Push-ImpersonationContext
{
	<#
		.SYNOPSIS
		Start new impersonation context
		.DESCRIPTION
		This function pushes a new impersonation context on the stack.
		Subsequent calls to this function will result in new contexts
		being superimposed on this one. Use Pop-ImpersonationContext
		to revert to the one in effect before calling.
		.PARAMETER Credential
		Logon credentials (normally gotten using the Get-Credential cmdlet)
		.PARAMETER Identity
		An already logged on Windows identity
		.PARAMETER Name
		User name
		.PARAMETER Password
		User password in cleartext. If not specified, the password will be
		read from the console.
		.PARAMETER Domain
		User domain name
		.PARAMETER LogonType
		The type of logon to perform, as defined by the LogonUser() function
		in the Windows API. Valid types are Interactive, Network, Batch,
		Service, Unlock, Cleartext and NewCredentials. Default value is
		Interactive.
		.PARAMETER PassThru
		Whether to output the logged on Windows Identity object to the pipeline
	#>
	
	[CmdletBinding(DefaultParameterSetName="Credential")]
	Param
	(
		[Parameter(Mandatory=$true, ParameterSetName="Credential")]
		[System.Management.Automation.PSCredential]$Credential,
		
		[Parameter(Mandatory=$true, ParameterSetName="Identity")]
		[System.Security.Principal.WindowsIdentity]$Identity,
		
		[Parameter(Mandatory=$true, ParameterSetName="Password")]
		[string]$Name,
		
		[Parameter(Mandatory=$true, ParameterSetName="Password")]
		[Object]$Password = $(Read-Host -Prompt Password -AsSecureString),
		
		[Parameter(ParameterSetName="Password")]
		[string]$Domain,
		
		[Parameter(ParameterSetName="Password")]
		[Parameter(ParameterSetName="Credential")]
		[Impersonation.LogonType]$LogonType = [Impersonation.LogonType]::Interactive,
		
		[Parameter()]
		[switch]$PassThru
	)

	Write-Verbose ([Security.Principal.WindowsIdentity]::GetCurrent() | Format-Table Name, Token, User, Groups -AutoSize | Out-String)
	
	switch ($PSCmdlet.ParameterSetName)
	{
		"Password"
		{
			if ($Password -is [string])
			{
				$secure = New-Object System.Security.SecureString
				foreach ($c in $Password.GetEnumerator())
				{
					$secure.AppendChar($c)
				}
				
				$Password = $secure
			}
			
			if ($Domain)
			{
				$User = $Name, $Domain -join "@"
			}
			
			Write-Verbose "Creating credential object for $User"
			$Credential = New-Object System.Management.Automation.PSCredential($User, $Password)
		}
		
		{ "Password" -or "Credential" }
		{
			Write-Verbose "Logging on as $($Credential.GetNetworkCredential().UserName)"
			$safeHandle = New-Object Impersonation.SafeTokenHandle
			if (-not [Impersonation.Impersonation]::LogonUser($Credential.GetNetworkCredential().UserName, $Credential.GetNetworkCredential().Domain, $Credential.GetNetworkCredential().Password, $LogonType, $script:LOGON32_PROVIDER_DEFAULT, [ref]$safeHandle))
			{
				throw (New-Object System.ComponentModel.Win32Exception([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))
			}
			
			$Identity = New-Object Security.Principal.WindowsIdentity($safeHandle.DangerousGetHandle())
			$safeHandle.Dispose()
		}
	}
	
	$script:IdStack.Push($Identity)
	
	Write-Verbose "Impersonating $($Identity.Name)"
	$context = $Identity.Impersonate()
	[Void]$script:ImpContextStack.Push($context)
	
	Write-Verbose ([Security.Principal.WindowsIdentity]::GetCurrent() | Format-Table Name, Token, User, Groups -AutoSize | Out-String)
	
	if ($PassThru)
	{
		Write-Output $script:IdStack.Peek()
	}
}

Function Pop-ImpersonationContext
{
	<#
		.SYNOPSIS
		End impersonation context
		.DESCRIPTION
		This function pops an impersonation context from the stack,
		reverting to the identity in effect before the last call
		to Push-ImpersonationContext.
		.PARAMETER PassThru
		Whether to output the Windows Identity object to the pipeline
	#>
		[CmdletBinding()]
	Param
	(
		[Parameter()]
		[switch]$PassThru
	)
	
	if ($PassThru)
	{
		Write-Output $script.IdStack.Peek()
	}
	
	$context = $script:ImpContextStack.Pop()
	[Void]$script:IdStack.Pop()
	
	$context.Undo()
	$context.Dispose()
}
