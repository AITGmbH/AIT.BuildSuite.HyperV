[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

function Get-HyperVCmdletsAvailable
{
	Write-Host "Check if Hyper-V PowerShell management commandlets are installed."

	$hyperVCommands = (
		('GET-VM'),
		('Get-VMSnapshot'),
		('Restore-VMSnapshot'),
		('Start-VM'),
		('Stop-VM'),
		('Checkpoint-VM'),
		('Remove-VMSnapshot'),
		('Disable-VMEventing'),
		('Enable-VMEventing')
	)

	foreach ($cmdName in $hyperVCommands)
		{
			if  (!(Get-Command $cmdName -errorAction SilentlyContinue))
				{
					write-host -ForegroundColor Yellow "Windows feature ""Microsoft-Hyper-V-Management-PowerShell"" is not installed on the build agent."
					write-host -ForegroundColor Yellow "Please install ""Microsoft-Hyper-V-Management-PowerShell"" by using an Administrator account"
					write-host -ForegroundColor Yellow "You can use PowerShell with the following command to install the missing components:"
					write-host -ForegroundColor Green "Enable-WindowsOptionalFeature –FeatureName Microsoft-Hyper-V-Management-PowerShell,Microsoft-Hyper-V-Management-Clients –Online -All"

					throw "Microsoft-Hyper-V-Management-PowerShell are not installed."
					return
				}
		}

	Write-Host "Microsoft-Hyper-V-Management-PowerShell are installed."

}

# Too many Hyper-V powershell actions in a short period can lead to wrong data in PS-HyperV-cache
# We disable the cache before doing any actions to avoid invalid data
# Disable the cache leads to increased workfload
# At the end of our actions we re-enable the cache again
function Set-HyperVCmdletCacheDisabled
{
	<#
	.Notes
	Disable hyper-v commandlet cache because this causes some trouble in cases of high workloads / number of hyper-v changes/actions
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
	Param(
        [Parameter()]
        [switch]
        $Force
    )

	Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

	process
	{
		<# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			write-host "Disable Hyper-V cmdlet caching."
			Disable-VMEventing -ComputerName $Computername -force
		}
	}

	End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Set-HyperVCmdletCacheEnabled
{
	<#
	.Notes
	(re-)enable hyper-v commandlet cache again so that other scripts are not affected.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
        [Parameter()]
        [switch]
        $Force
    )

    Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			write-host "(Re-)Enable Hyper-V cmdlet caching."
			Enable-VMEventing -ComputerName $Computername -force
		}

	}

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Get-ParameterOverview
{
	write-host "Action is $Action.";
	write-host "Assigned VM name(s) are $VMName.";
	write-host "Assigned Hyper-V server host is $Computername.";

	if ($Action -eq "StartVM")
	{
		write-host "Status check type: $statusCheckType";
		if ($statusCheckType -eq "WaitingTime")
		{
			write-host "Waiting time interval (in sec): $timeBasedStatusWaitInterval"
		}
	}

	if ($SnapshotName) {
		write-host "Assigned snapshot/checkpoint name is $SnapshotName.";
	}
}


function Get-VMExists
{
	[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Scope="Function", Target="*")]
	param([System.Collections.ArrayList]$vmnames, [string]$hostname)

	write-host "Checking if all configured VMs are found on host $hostname";

	$nonExistingVMs;
	for ($i=0; $i -lt $vmnames.Count; $i++)
	{
		$vmname = $vmnames[$i];

		$vm = Get-VM -Name $vmname -Computername $hostname
		if ($null -eq $vm)
		{
			Write-Error "VM $vmname doesn't exist on Hyper-V server $hostname"
			$notExistingVM += " $vmname"
		}
	}
	$notExistingVM = $notExistingVM.Trim;

	if ($notExistingVM.Count -gt 0)
	{
		Write-Error "The task found some non existing VM names. Please check VMs $notExistingVM on host $hostname.";
		throw "The task found some non existing VM names. Please check VMs $notExistingVM on host $hostname.";
	}

	Write-Host "All configured VMs are found on host $hostname";
}

function Get-VMNamesFromVMNameParameter
{
	<#
	.Notes this function works supports one or more VMnames in VMName build process parameter
	#>

	$vmNames = New-Object System.Collections.ArrayList;

	if ($VMName.Contains(","))
	{
		$tempNames = New-Object System.Collections.ArrayList;
		$splittedNames = $VMName.Split(",");

		for ($i=0; $i -lt $splittedNames.Count; $i++)
		{
			$tempNames.Add($splittedNames[$i].Trim()) | Out-Null
		}

		$vmNames = $tempNames;
	}
	else {
		# https://stackoverflow.com/questions/28034605/arraylist-prints-numbers
		$VMName = $VMName.Trim();
		$vmNames.Add($VMName) | Out-Null;
	}

	Write-Debug "Found $($vmNames.Count) VM names in VMName parameter";

	# , is a workaround for powershell issues with arraylist -> otherwise this object is converted to string
	return ,$vmNames;
}

#region task core actions
function Start-HyperVVM
{
	<#
	.Notes
	Starts one or more VMs and waits for healthy signal from VM extensions.

	ToDo
	It is possible that not all OS or Extensions support health signals. Maybe add an alternative approach.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
        [Parameter()]
		$vmnames,
		[Parameter()]
		$hostname,
		[Parameter()]
        [switch]
        $Force
    )

    Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

	Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			for ($i=0; $i -lt $vmnames.Count; $i++ )
			{
				$vmname = $vmnames[$i];

				$vm = Get-VM -Name $vmname -Computername $hostname
				if ($vm.Heartbeat -ne "OkApplicationsHealthy")
				{
					Write-Host "Starting VM $vmname on host $hostname";
					Start-VM -VMName $vmname -Computername $hostname -ErrorAction Stop
				}
				else
				{
					Write-Host "VM $vmname on host $hostname is already started";
				}
			}
			<# Post-impact code #>
		}
	}

	End {
		Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
	}
}

function Get-ApplicationsHealthyStatusOfStartHyperVVM
{
	param($vmnames, $hostname)

	write-host "Waiting until all VM(s) have been started (using ApplicationHealthy status)."

	$finishedVMs = New-Object System.Collections.ArrayList;

	$workInProgress = $true;
	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$vmname = $vmnames[$i];

			$vm = Get-VM -Name $vmname -Computername $hostname

			if ($vm.Status -match "Starting")
			{
				Write-Host "VM $vmname on host $hostname is still in status Starting"
			}
			else
			{
				$finishedVMs.Add($vmname) | Out-Null
				write-host "VM $vmname is now ready."
			}

			# After we reached the last vm in the parameter list we need to decide about the next steps
			if ($vmnames.Count -ne $finishedVMs.Count)
			{
				$workInProgress = $true;
				Start-Sleep -Seconds 5
				write-host "Checking status again in 5 sec."
			}
			else
			{
				$workInProgress = $false;
			}
		}
	}

	$workInProgress = $true;
	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$circuitBreaker = $false;
			$vm = Get-VM -Name $vmname -Computername $hostname
			write-host "Waiting until VM $vmname heartbeat state is ""Application healthy""."

			# backup for future -and $vm.Heartbeat -ne "OkApplicationsUnknown"
			# hyper-v show unkown in case the hyper-v extensions are not uptodate
			while ($vm.Heartbeat -ne "OkApplicationsHealthy" -and !$circuitBreaker)
			{
				Start-Sleep -Seconds 5
				write-host "Checking status again in 5 sec."
				$vm = Get-VM -Name $vmname -Computername $hostname
				$heartbeatTimeout = $appHealthyHeartbeatTimeout;

				if ($null -eq $heartbeatTimeout -or $heartbeatTimeout -eq 0)
				{
					Write-Verbose "Assigning default value to heartbeat timeout because it is $heartbeatTimeout";
					# If the Heartbeat Timeout is set we stay at the default of 5 minutes.
					$heartbeatTimeout = 5*60;
					Write-Host "Default heartbeat timeout is $heartbeatTimeout";
				}	
				else 
				{
					Write-Host "Assigning custom value to heartbeat timeout $heartbeatTimeout"
				}


				if ($vm.State -eq "Running" -and $vm.Uptime.Seconds -gt $heartbeatTimeout)
				{
					$circuitBreaker = $true;
					Write-Warning "Starting VM $vmname reached $heartbeatTimeout minute timeout limit";
					Write-Warning "Hyper-V heartbeat has not reported healthy state."
					Write-Warning "VM $vmname is in running state and the task finishs execution";
					break;
				}

				if ($vm.State -ne "Running" -and $vm.Uptime.Seconds -gt $heartbeatTimeout)
				{
					$circuitBreaker = $true;
					Write-Warning "Starting VM $vmname reached $heartbeatTimeout minute timeout limit";
					Write-Warning "Hyper-V heartbeat has not reported healthy state."
					Write-Error "Abording starting VM $vmname because VM state is not running"
					Write-Error "Please check logs on Hyper-V server and Build agent to find the root cause and fix any issues."
					continue
				}
			}

			$workInProgress = $false;
			write-host "The VM $vmname has been started.";
		}
	}

	write-host "All VM(s) have been started."
}

function Get-TimeBasedStatusOfStartHyperVVM
{
	param($vmnames, $hostname)

	write-host "Waiting until all VM(s) have been started (using TimeBased check)."
	$finishedVMs = New-Object System.Collections.ArrayList;

	$workInProgress = $true;
	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$vmname = $vmnames[$i];

			$vm = Get-VM -Name $vmname -Computername $hostname

			if ($vm.Status -match "Starting")
			{
				Write-Host "VM $vmname on host $hostname is still in status Starting"
			}
			else
			{
				$finishedVMs.Add($vmname) | Out-Null
				write-host "VM $vmname is now ready."
			}

			# After we reached the last vm in the parameter list we need to decide about the next steps
			if ($vmnames.Count -lt $finishedVMs.Count)
			{
				$workInProgress = $true;
				Start-Sleep -Seconds 5
				write-host "Checking status again in 5 sec."
			}
			else
			{
				$workInProgress = $false;
			}
		}
	}
	
	if ($null -eq $waitingTimeNumberOfStatusNotifications -or 0 -eq $waitingTimeNumberOfStatusNotifications)
	{
		Write-Verbose "Assigning default value to Waiting time status notifications $waitingTimeNumberOfStatusNotifications";
		$waitingTimeNumberOfStatusNotifications = 30;
	}
	else {
		Write-Host "Assigning custom value to Waiting time status notifications $waitingTimeNumberOfStatusNotifications";
	}

	[int]$waitingInterval = ($timeBasedStatusWaitInterval / 30);

	for ($i=1; $i -le $waitingTimeNumberOfStatusNotifications; $i++)
	{
		Start-Sleep -Seconds $waitingInterval
		$timeBasedStatusWaitIntervalLeft = $timeBasedStatusWaitInterval - $i * $waitingInterval;

		write-host "Waiting interval is reached in $timeBasedStatusWaitIntervalLeft sec."
	}
	write-host "Waiting interval $timeBasedStatusWaitInterval seconds reached. We go on ..."
}

function Get-StatusOfStartHyperVVM
{
	param($vmnames, $hostname)

	switch ($statusCheckType) {
		"WaitingTime" { Get-TimeBasedStatusOfStartHyperVVM -vmnames $vmNames -hostname $hostName }
		"HeartBeatApplicationsHealthy" {Get-ApplicationsHealthyStatusOfStartHyperVVM -vmnames $vmNames -hostname $hostName}
	}
}


function Stop-VMUnfriendly
{
	<#
	.Notes
	alternative approach to shutdown VMs in case regular shutdown is not possible.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
  	param(
		[Parameter()]
		$vmname,
		[Parameter()]
		$hostname,
	 	[Parameter()]
        [switch]
        $Force
	  )

	  Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
	}

	Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			$id = (
				get-vm -ComputerName $hostname| Where-Object {$_.name -eq "$vmname"} | Select-Object id).id.guid
			If ($id)
				{
					write-host "VM GUID found: $id"
				}
			Else
				{
					write-warning "VM or GUID not found for VM: $vmname.";
					break
				}

			$vm_pid = (Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'vmwp' -and $_.CommandLine -match $id}).ProcessId
			If ($vm_pid)
				{
					write-warning "Found VM worker process id: $vm_pid"
					Write-warning "Killing VM worker process of VM: $vmname"
					stop-process $vm_pid -Force
				}
			Else
				{
					write-host "No VM worker process found for VM: $vmname"
				}

		}

			<# Post-impact code #>
	}

	End {
		Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
	}
}

function Stop-VMByTurningOffVM
{
	<#
	.Notes
	helper method for stop vm. this one turns the vm off (instead of regular shutdown) -> dataloss is possible in some cases -> e.g. cache not flushed to disk
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
		[Parameter()]
		$vmnames,
		[Parameter()]
		$hostName,
        [Parameter()]
        [switch]
        $Force
    )

    Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'
			
			for ($i=0;$i -lt $vmnames.Count; $i++)
			{
				$vmname = $vmnames[$i];
				$vm = Get-VM -Name $vmname -Computername $hostname
				if ($vm.State -ne "Off")
				{
					write-host "Direct turning off the VM $vmname (no regular gracefull shutdown)."
					write-debug "Current VM $vmname state: $($vm.State)"
					write-debug "Current VM $vmname status: $($vm.Status)"

					Stop-VM -Name $vmname -ComputerName $hostname -TurnOff -Force -ErrorAction SilentlyContinue
					Start-Sleep -Seconds 5
					write-debug "Current VM $vmname state: $($vm.State)"
					write-debug "Current VM $vmname status: $($vm.Status)"
					Write-Host "VM $vmname on $hostname is now turned off."
				}
				else 
				{
					Write-Host "VM $($vm.Name) is already turned off."
				}
			}			
		}
        <# Post-impact code #>
    }

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Start-HyperVVMShutdown
{
	<#
	.Notes
	Stops one or more VMs. In conjunction with get-statusstopofvm the function starts with a friendly shutdown approach and after 5 min. does a hard or unfriendly shutdown.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
		[Parameter()]
		$vmnames,
		[Parameter()]
		$hostname,
        [Parameter()]
        [switch]
        $Force
    )

	Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			for($i=0; $i -lt $vmnames.Count; $i++)
			{
				$vmname = $vmnames[$i];

				#Stop-VMUnfriendly -vmname $vmname -hostname $hostname -Confirm:$false
				$vm = Get-VM -Name $vmname -Computername $hostname

				if ($vm.State -ne "Off")
				{
					Write-Host "Shutting down VM $vmname on $hostname started."
					$vm = Get-VM -Name $vmname -Computername $hostname

					Stop-VM -Name $vmname -ComputerName $hostname -Force -ErrorAction Stop
				}
				else
				{
					Write-Host "VM $vmname on $hostname is already turned off."
				}
			}
		}

        <# Post-impact code #>
    }

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Get-StatusOfShutdownVM
{
	write-host "Waiting until all VM(s) has been shutted down."

	$finishedVMs = New-Object System.Collections.ArrayList;

	$workInProgress = $true;
	$retryCounter = 0;

	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$vmname = $vmnames[$i];
			write-host "Waiting until VM $vmname state is ""Off""."
			$vm = Get-VM -Name $vmname -Computername $hostname

			if ($vm.State -eq 'Off')
			{
				$finishedVMs.Add($vmname) | Out-Null
				write-host "VM $vmname is turned off."
			}
		}

		if ($vmnames.Count -ne $finishedVMs.Count)
			{
			$workInProgress = $true;
			$retryCounter++;
			if ($retryCounter -gt 30)
			{
				# we reached a timeout of approx. 5 min
				# its now the time to stop VMs in a very unfriendly way
				Stop-VMByTurningOffVM -vmnames $vmnames -hostName $hostname
				return;
			}

			Start-Sleep -Seconds 10
			$finishedVMs.Clear();
			write-host "Checking status again in 10 sec."
		}
		else
		{
			write-host "All configured VMs have been shut down."
			$workInProgress = $false;
		}
	}

	write-host "All VM(s) have been shutted down."
}

function Start-TurnOfVM {
	<#
	.Notes
	Stops one or more VMs. In conjunction with get-statusstopofvm the function starts with a friendly shutdown approach and after 5 min. does a hard or unfriendly shutdown.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
		[Parameter()]
		$vmnames,
		[Parameter()]
		$hostname,
        [Parameter()]
        [switch]
        $Force
    )

	Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			Stop-VMByTurningOffVM -vmnames $vmnames -hostname $hostname -Confirm:$false
		}
	
        <# Post-impact code #>
    }

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

}

function New-HyperVSnapshot
{
	<#
	.Notes
	Creates a new snapshot for one or more VMs. The snapshot name should be the same on all VMs because they are considered as a unit.
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
		[Parameter()]
		$vmnames,
		[Parameter()]
		$hostname,
        [Parameter()]
        [switch]
        $Force
    )

	Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			for ($i=0; $i -lt $vmnames.Count; $i++)
			{
				$vmname = $vmnames[$i]

				$snapshot = Get-VMsnapshot -VMname $vmname -ComputerName $hostname | Where-Object {$_.Name -eq "$SnapshotName"}
				if ($null -ne $snapshot)
				{
					Write-Error "Snapshot $SnapshotName on VM $vmname already exists. Please remove the old snapshot or choose a different name"
					throw "Duplicate snapshot name."
				}

				write-host "Creating snapshot $SnapshotName for VM $vmname on host $hostname"
				Checkpoint-VM -Name $vmname -ComputerName $hostname -SnapshotName $SnapshotName -ErrorAction Stop
			}

		}

        <# Post-impact code #>
    }

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Get-StatusOfNewHyperVSnapshot
{
	param($vmnames, $hostname)

	write-host "Waiting until snapshot for all VM(s) has been created."

	$finishedVMs = New-Object System.Collections.ArrayList;

	$workInProgress = $true;
	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$vmname = $vmnames[$i];
			write-host "Waiting until VM $vmname snapshot state is not ""Creating""."
			$vm = Get-VM -Name $vmname -Computername $hostname

			if ($vm.Status -match "Creating")
			{
				write-host "Creating a snapshot on VM $vmname on host $hostname is still in progress"
			}
			else
			{
				$finishedVMs.Add($vmname) | Out-Null
				write-host "Snapshot $SnapshotName for the VM $vmname on host $hostname has been created.";
			}

			if ($vmnames.Count -ne $finishedVMs.Count)
			{
				$workInProgress = $true;
				Start-Sleep -Seconds 5
				write-host "Checking status again in 5 sec."
			}
			else
			{
				$workInProgress = $false;
			}
		}
	}

	write-host "Snapshots for all VM(s) have been created."
}

function Restore-HyperVSnapshot
{
	<#
	.Notes
	Restores the environment (all VMs) back to specified snapshot/checkpoint
	In case of an production snapshot you need to add start-vm in your build -> we try to keep the functions as simple as possible
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
		[Parameter()]
		$vmnames,
		[Parameter()]
		$hostname,
        [Parameter()]
        [switch]
        $Force
    )

	Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
			$ConfirmPreference = 'None'

			for ($i=0;$i -lt $vmnames.Count; $i++)
			{
				$vmname = $vmnames[$i];
				$snapshot = Get-VMsnapshot -VMname $vmname -ComputerName $hostname | Where-Object {$_.Name -eq "$SnapshotName"}

				if ($null -eq $snapshot)
				{
					write-error "Snapshot $SnapshotName of VM $vmname on host $hostname doesnt exist."
					throw "Snapshot $SnapshotName of VM $vmname on host $hostname doesnt exist."
				}

				write-host "Restoring snapshot $SnapshotName for VM $vmname on host $hostname have been started."
				Restore-VMSnapshot -VMName $vmname -ComputerName $hostname -Name $SnapshotName -Confirm:$false -ErrorAction Stop
			}
		}
        <# Post-impact code #>
    }

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Get-StatusOfRestoreHyperVSnapshot
{
	param($vmnames, $hostname)

	write-host "Waiting until restoring snapshot has been finished for all VM(s)."

	$finishedVMs = new-object System.collections.arraylist;

	$workInProgress = $true;
	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$vmname = $vmnames[$i];
			write-host "Waiting until VM $vmname state is not ""Applying""."
			$vm = Get-VM -Name $vmname -Computername $hostname

			if ($vm.Status -match "Applying")
			{
				write-host "Restoring snapshot for VM $vmname on host $hostname is still in progress.";
			}
			else
			{
				$finishedVMs.Add($vmname) | Out-Null
				write-host "Snapshot $SnapshotName for the VM $vmname has been restored.";
			}

			if ($vmnames.Count -ne $finishedVMs.Count)
			{
				$workInProgress = $true;
				Start-Sleep -Seconds 5
				write-host "Checking status again in 5 sec."
			}
			else
			{
				$workInProgress = $false;
			}
		}
	}

	write-host "Restoring snapshots has been finished for all VM(s)."
}

function Remove-HyperVSnapshot
{
	<#
	.Notes
	Remove snapshot on one or more VMs
	Function checks if snapshot exists -> makes it a little bit more robust
	#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    Param(
		[Parameter()]
		$vmnames,
		[Parameter()]
		$hostname,
        [Parameter()]
        [switch]
        $Force
    )

	Begin {
        if (-not $PSBoundParameters.ContainsKey('Verbose')) {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }

    Process {
        <# Pre-impact code #>

        # -Confirm --> $ConfirmPreference = 'Low'
        # ShouldProcess intercepts WhatIf* --> no need to pass it on
        if ($Force -or $PSCmdlet.ShouldProcess("ShouldProcess?")) {
            Write-Verbose ('[{0}] Reached command' -f $MyInvocation.MyCommand)
            # Variable scope ensures that parent session remains unchanged
            $ConfirmPreference = 'None'

			for ($i=0;$i -lt $vmnames.Count; $i++)
			{
				$vmname = $vmnames[$i];
				$snapshot = Get-VMsnapshot -VMname $vmname -ComputerName $hostname | Where-Object {$_.Name -eq "$SnapshotName"}

				if ($null -eq $snapshot)
				{
					Write-Warning "Snapshot $SnapshotName of VM $vmname on host $hostname doesnt exist."
					#throw "Snapshot $SnapshotName of VM $vmname on host $hostname doesnt exist."
				}

				write-host "Removing snapshot $SnapshotName for VM $vmname on host $hostname have been started."
				Remove-VMSnapshot -VMName $vmname -ComputerName $hostname -Name $SnapshotName -Confirm:$false -ErrorAction Stop
			}
		}

        <# Post-impact code #>
    }

    End {
        Write-Verbose ('[{0}] Confirm={1} ConfirmPreference={2} WhatIf={3} WhatIfPreference={4}' -f $MyInvocation.MyCommand, $Confirm, $ConfirmPreference, $WhatIf, $WhatIfPreference)
    }
}

function Get-StatusOfRemoveHyperVSnapshot
{
	param($vmnames, $hostname)

	write-host "Waiting until removing snapshot has been finished for all VM(s)."

	$finishedVMs = new-object System.collections.arraylist;

	$workInProgress = $true;
	while ($workInProgress)
	{
		for ($i=0; $i -lt $vmnames.Count; $i++)
		{
			$vmname = $vmnames[$i];
			write-host "Waiting until VM $vmname state is not ""Merging""."
			$vm = Get-VM -Name $vmname -Computername $hostname

			if ($vm.Status -match "Merge")
			{
				write-host "Removing snapshot $SnapshotName for VM $vmname on host $hostname is still in progress.";
			}
			else
			{
				$finishedVMs.Add($vmname) | Out-Null
				write-host "Snapshot $SnapshotName for the VM $vmname has been removed.";
			}

			if ($vmnames.Count -ne $finishedVMs.Count)
			{
				$workInProgress = $true;
				Start-Sleep -Seconds 5
				write-host "Checking status again in 5 sec."
			}
			else
			{
				$workInProgress = $false;
			}
		}
	}

	write-host "Removing snapshot has been finished for all VM(s)."
}
#endregion

#region Control hyper-v
Try
{
	#[bool]$debug = Get-VstsTaskVariable -Name System.Debug -AsBool
	[string]$Action = Get-VstsInput -Name Action
	[string]$VMName = Get-VstsInput -Name VMName
	[string]$Computername = Get-VstsInput -Name Computername
	[string]$SnapshotName = Get-VstsInput -Name SnapshotName
	[string]$statusCheckType = Get-VstsInput -Name StartVMStatusCheckType
	[int]$timeBasedStatusWaitInterval = Get-VstsInput -Name StartVMWaitTimeBasedCheckInterval
	[string]$ConfirmPreference="None"

	[int]$appHealthyHeartbeatTimeout = Get-VstsTaskVariable -Name HyperV.HyperV.StartVMAppHealthyHeartbeatTimeout
	[int]$waitingTimeNumberOfStatusNotifications = Get-VstsTaskVariable -Name HyperV.StartVMWaitingNumberOfStatusNotifications

	Get-HyperVCmdletsAvailable
	Get-ParameterOverview
	Set-HyperVCmdletCacheDisabled -Confirm:$false

	$vmNames= Get-VMNamesFromVMNameParameter
	$hostName = $Computername
	Get-VMExists -vmnames $vmNames -hostname $hostName

	switch ($Action)
	{
		"StartVM" {
			Start-HyperVVM -vmnames $vmNames -hostname $hostName -Confirm:$false
			Get-StatusOfStartHyperVVM -vmnames $vmNames -hostname $hostName
		}
		"ShutdownVM" {
			Start-HyperVVMShutdown -vmnames $vmNames -hostname $hostName -Confirm:$false
			Get-StatusOfShutdownVM -vmnames $vmNames -hostname $hostName
		}
		"TurnOffVM" {
			Start-TurnOfVM -vmnames $vmNames -hostname $hostName -Confirm:$false
		}
		"CreateSnapshot" {
			New-HyperVSnapshot -vmnames $vmNames -hostname $hostName -Confirm:$false
			Get-StatusOfNewHyperVSnapshot -vmnames $vmNames -hostname $hostName
		}
		"RestoreSnapshot" {
			Restore-HyperVSnapshot -vmnames $vmNames -hostname $hostName -Confirm:$false
			Get-StatusOfRestoreHyperVSnapshot -vmnames $vmNames -hostname $hostName
		}
		"RemoveSnapshot" {
			Remove-HyperVSnapshot -vmnames $vmNames -hostname $hostName -Confirm:$false
			Get-StatusOfRemoveHyperVSnapshot -vmnames $vmNames -hostname $hostName
		}
	}
}
Catch
{
	$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent();

	Write-Warning ('You have may not enough permission to use the hyper-v cmdlets, please check this:
	Add the ' + $currentUser.Name + ' user to the ""Hyper-V Administrator"" and ""Remote Management Users"" group on the target hyper-v host which the agent wants to access.
	You can authorize the build agent user using two commands: net localgroup "Hyper-V Administrators" ' + $currentUser.Name + ' /add and net localgroup "Remote Management Users" ' + $currentUser.Name + ' /add')
	Write-Error $_.Exception.Message;
}
finally
{
	Set-HyperVCmdletCacheEnabled -Confirm:$false
    Trace-VstsLeavingInvocation $MyInvocation
}
#endregion