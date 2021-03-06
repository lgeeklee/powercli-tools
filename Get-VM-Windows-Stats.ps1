<# 
.SYNOPSIS
	This script will show a subset of statistics for a Virtual Machine

.DESCRIPTION
	This script shows CPU, memory, datastore and network statistics from the hypervisor and within the Windows guest
	operating system (when the OS is Windows), allowing a glimpse into the current Virtual Machine usage.
	
.NOTES 
    Author	: geeklee
	Version	: 1.2
	
	Requirements: 
	 - You are running the script from a PowerCLI enabled PowerShell session.
	 - You are already connected to the vCenter instance with your VM
	 - You are checking a Windows based server (for OS stats to return values)

	Disclaimer: This script is provided as-is without any support.
	
.LINK 
    http://www.geeklee.co.uk
	
.PARAMETER VM
Use this parameter to supply one or more virtual machine names.

.PARAMETER StatType
Use this parameter to select the required statistics you want:
	basic - just the Virtual MAchine information and Host information
	memory - include memory statistics
	cpu - iunclude cpu statistics
	datastore - include VM datastore statistics
	net - network usage Tx and Rx statistics
	os - include guest OS statistics
	all - include all statistics (all of the above)
This can be a comma separated list if you only want a sub-set of statistics returned.  The default is basic.

.PARAMETER StatInt
Use this parameter to set the interval to average the vSphere stats over.  The statistics are all realtime so the value should be
an integer between 1 and 60.  Only relevant if you're returning more than the default (basic) statistics.

.PARAMETER View
Use this parameter to set the output type - default is to screen, enter csv for csv export (Export-CSV).

.EXAMPLE
Get-VM-Windows-Stats.ps1 VMDC01 -StatInt 5
This will display to screen the statistics for the virtual machine VMDC01 with VM statistics taken over 5 minutes.

.EXAMPLE
Get-VM-Windows-Stats.ps1 VMDC01,VMDC02 -StatType all
This will display to screen the statistics for both virtual machines VMDC01 and VMDC02.  All VM statistics will be returned 
and taken over the default 15 minutes.

.EXAMPLE
Get-VM-Windows-Stats.ps1 VMDC01,VMDC02,VMDC03 -StatType memory -StatInt 5 -View csv
This will export to CSV the statistics for all three virtual machines - VMDC01, VMDC02 and VMDC03 with VM statistics taken over 5 minutes.
This will return the basic information about a VM and the memory statistics.

#> 

[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True,Position=1)]
  [ValidateNotNullOrEmpty()]
  $VM = @(),
  [Parameter(Mandatory=$False,Position=2)]
  [ValidateNotNullOrEmpty()]
  $StatType="basic",
  [Parameter(Mandatory=$False,Position=3)]
  [ValidateNotNullOrEmpty()]
  [int]$StatInt=15,
  [Parameter(Mandatory=$False,Position=4)]
  [ValidateNotNullOrEmpty()]
  [string]$View
)

Function vmcheck ($VMIND) {
	Write-Host "Checking DNS lookup and WMI connection for $VMIND...`n"
	$DNSCHECK = $null ; $DNSCHECK=[net.dns]::GetHostEntry($VMIND)
	if ($DNSCHECK -eq $null) {Write-Host "$VMIND not found in DNS, exiting`n" -ForegroundColor red ; continue}
		elseif (!(Get-WmiObject win32_operatingsystem -ComputerName $VMIND)) {Write-Host "$VMIND found in DNS but WMI connection error ([OS] stats will be empty)`n" -ForegroundColor red ; $WMICHECK = $FALSE ; Return $WMICHECK}
	}


$ErrorActionPreference = "SilentlyContinue"
Set-PowerCLIConfiguration -DisplayDeprecationWarnings $false -Scope Session -confirm:$false | Out-Null
$STATFINAL = @()


Write-Host "`n`nRetrieving Virtual Machine Statistics..." -ForegroundColor Green
Write-Host "NOTE: Any VM statistics are averages of the last $STATINT minutes" -ForegroundColor Green


if ($StatType -contains "memory" -or $StatType -contains "all") {
	$VMVMEM = get-stat -realtime -stat mem.active.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMVMEMSWAP = get-stat -realtime -stat mem.swapped.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMVMEMSHARE = get-stat -realtime -stat mem.shared.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMVMEMBALL = get-stat -realtime -stat mem.vmmemctl.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	}
	
if ($StatType -contains "cpu" -or $StatType -contains "all") {
	$VMVCPU = get-stat -realtime -stat cpu.usage.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMVCPUREADY = get-stat -realtime -stat cpu.ready.summation -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0) | Where {$_.Instance -eq ""}
	}

if ($StatType -contains "datastore" -or $StatType -contains "all") {
	$VMDSIORD = get-stat -realtime -stat datastore.numberreadaveraged.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMDSIOWR = get-stat -realtime -stat datastore.numberwriteaveraged.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMDSLATRD = get-stat -realtime -stat datastore.totalReadLatency.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	$VMDSLATWR = get-stat -realtime -stat datastore.totalWriteLatency.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0)
	}

if ($StatType -contains "net" -or $StatType -contains "all") {
	$VMNETTX = get-stat -realtime -stat net.transmitted.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0) | Where {$_.Instance -eq ""}
	$VMNETRX = get-stat -realtime -stat net.received.average -entity $VM -start (get-date).addminutes(-$STATINT) -finish (get-date).addminutes(-0) | Where {$_.Instance -eq ""}
	}

Write-Host "Virtual Machine Statistics retrieved.`n" -ForegroundColor Green


Foreach ($VMIND in $VM) {
	$WMICHECK = vmcheck $VMIND
	$i++
	$VMINFO = Get-VM $VMIND
	$HOSTINFO = Get-VMHost $VMINFO.Vmhost
	$VMRESOURCE = Get-VMResourceConfiguration $VMIND
	if ($VMRESOURCE.CpuLimitMhz -eq -1) {$VMCPULIM = "None"} else {$VMCPULIM = "$($VMRESOURCE.CpuLimitMhz) Mhz"}
	if ($VMRESOURCE.MemLimitMB -eq -1) {$VMMEMLIM = "None"} else {$VMMEMLIM = "$($VMRESOURCE.MemLimitMB) MB"}
	if ($VMRESOURCE.CpuReservationMhz -eq 0) {$VMCPURES = "None"} else {$VMCPURES = "$($VMRESOURCE.CpuReservationMhz) Mhz"}
	if ($VMRESOURCE.MemReservationMB -eq 0) {$VMMEMRES = "None"} else {$VMMEMRES = "$($VMRESOURCE.MemReservationMB) MB"}
	if (($WMICHECK -ne $FALSE) -and ($StatType -eq "os" -or $StatType -eq "all")) {$VMWINMEM = Get-WmiObject win32_OperatingSystem -ComputerName $VMIND}
	if (($WMICHECK -ne $FALSE) -and ($StatType -eq "os" -or $StatType -eq "all"))  {$PROCMEM = Invoke-Command -ComputerName $VMIND -ScriptBlock {Get-Process | Sort -Property WorkingSet64 -Descending | Select ProcessName,WorkingSet64 -First 3}}	
	$STATINFO = New-Object Object
	$STATINFO | Add-Member -MemberType Noteproperty -name "Server Name" -value $VMIND
	$STATINFO | Add-Member -MemberType Noteproperty -name "Description" -value $VMINFO.Description
	$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Limits" -value "CPU: $($VMCPULIM), Memory: $($VMMEMLIM)"
	$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Reservations" -value "CPU: $($VMCPURES), Memory: $($VMMEMRES)"
	$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Number of vCPUs" -value $VMINFO.NumCpu
	
	if ($StatType -contains "cpu" -or $StatType -contains "all") {
		$VMVCPUIND = $VMVCPU | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average
		$VMCPUREADYAVG = $VMVCPUREADY | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average
		$VMCPUREADYMAX = $VMVCPUREADY | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Maximum | Select -ExpandProperty Maximum
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] CPU Ready" -value "Average: $("{0:N1}" -f ($VMCPUREADYAVG/20000*100)) %, Maximum: $("{0:N1}" -f ($VMCPUREADYMAX/20000*100)) %"
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] CPU (%)" -value ("{0:N0}" -f ($VMVCPUIND))
		}
	$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Memory" -value "$("{0:N0}" -f ($VMINFO.MemoryMB/1KB)) GB"
	
	if ($StatType -contains "memory" -or $StatType -contains "all") {
		$VMVMEMIND = ($VMVMEM | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average)/1KB
		$VMVMEMSWAPIND = ($VMVMEMSWAP | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average)/1KB	
		$VMVMEMSHAREIND = ($VMVMEMSHARE | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average)/1KB
		$VMVMEMBALLIND = ($VMVMEMBALL | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average)/1KB
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Memory Shared" -value "$("{0:N0}" -f (($VMVMEMSHAREIND/($VMINFO.MemoryMB))*100)) %, $("{0:N0}" -f ($VMVMEMSHAREIND)) MB"
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Memory Balloon" -value "$("{0:N0}" -f (($VMVMEMBALLIND/($VMINFO.MemoryMB))*100)) %, $("{0:N0}" -f ($VMVMEMBALLIND)) MB"
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Memory Swapped" -value "$("{0:N0}" -f (($VMVMEMSWAPIND/($VMINFO.MemoryMB))*100)) %, $("{0:N0}" -f ($VMVMEMSWAPIND)) MB"
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Memory Active" -value "$("{0:N0}" -f (($VMVMEMIND/($VMINFO.MemoryMB))*100)) %, $("{0:N0}" -f ($VMVMEMIND)) MB"
		}
	
	if ($StatType -contains "datastore" -or $StatType -contains "all") {
		$VMDSIORDAVG = $VMDSIORD | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average
		$VMDSIOWRAVG = $VMDSIOWR | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average
		$VMDSLATRDAVG = $VMDSLATRD | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average
		$VMDSLATWRAVG = $VMDSLATWR | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Datastore Average IO" -value "Read: $("{0:N0}" -f ($VMDSIORDAVG)) IOPS, Write: $("{0:N0}" -f ($VMDSIOWRAVG)) IOPS"
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Datastore Average Latency" -value "Read: $("{0:N0}" -f ($VMDSLATRDAVG)) ms, Write: $("{0:N0}" -f ($VMDSLATWRAVG)) ms"
		}

	if ($StatType -contains "net" -or $StatType -contains "all") {
		$VMNETTXAVG = ($VMNETTX | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average)* 8 / 1024
		$VMNETRXAVG = ($VMNETRX | Where {$_.Entity.Name -eq $VMIND} | Measure-Object -Property Value -Average | Select -ExpandProperty Average)* 8 / 1024
		$STATINFO | Add-Member -MemberType Noteproperty -name "[VM] Network Usage" -value "Transmit: $("{0:N3}" -f ($VMNETTXAVG)) Mbps, Receive: $("{0:N3}" -f ($VMNETRXAVG)) Mbps"
		}
		
	$STATINFO | Add-Member -MemberType Noteproperty -name "[Host] Name" -value $HOSTINFO.Name
	$STATINFO | Add-Member -MemberType Noteproperty -name "[Host] CPU Detail" -value `
		"Processor Sockets: $($HOSTINFO.ExtensionData.Hardware.CpuInfo.NumCpuPackages), Cores per Socket: $(($HOSTINFO.ExtensionData.Hardware.CpuInfo.NumCpuCores/$HOSTINFO.ExtensionData.Hardware.CpuInfo.NumCpuPackages))"
	$STATINFO | Add-Member -MemberType Noteproperty -name "[Host] CPU Type" -value $HOSTINFO.ProcessorType
	$STATINFO | Add-Member -MemberType Noteproperty -name "[Host] CPU Usage" -value "Used: $($HOSTINFO.CpuUsageMhz) Mhz, Total: $($HOSTINFO.CpuTotalMhz) Mhz"	
	$STATINFO | Add-Member -MemberType Noteproperty -name "[Host] Memory Usage" -value "Used: $("{0:N0}" -f ($HOSTINFO.MemoryUsageMB/1KB)) GB, Total: $("{0:N0}" -f ($HOSTINFO.MemoryTotalMB/1KB)) GB"
	
	if (($WMICHECK -ne $FALSE) -and ($StatType -contains "os" -or $StatType -contains "all")) {
		$STATINFO | Add-Member -MemberType Noteproperty -name "[OS] CPU (%)" -value (Get-WmiObject win32_Processor -ComputerName $VMIND `
			| Measure-Object -property LoadPercentage -Sum | Select -ExpandProperty Sum)
		$STATINFO | Add-Member -MemberType Noteproperty -name "[OS] Memory Used" -value `
			"$("{0:N0}" -f (100 - (($VMWINMEM.FreePhysicalMemory/$VMWINMEM.TotalVisibleMemorySize)*100))) %, $("{0:N0}" -f (($VMWINMEM.TotalVisibleMemorySize - $VMWINMEM.FreePhysicalMemory)/1KB)) MB"
		$STATINFO | Add-Member -MemberType Noteproperty -name "[OS] Top 3 Memory Processes" -value `
			"$($PROCMEM[0].ProcessName) ($("{0:N0}" -f ($PROCMEM[0].WorkingSet64/1MB)) MB), $($PROCMEM[1].ProcessName) ($("{0:N0}" -f ($PROCMEM[1].WorkingSet64/1MB)) MB), $($PROCMEM[2].ProcessName) ($("{0:N0}" -f ($PROCMEM[2].WorkingSet64/1MB)) MB)"
		}
		elseif ($WMICHECK -eq $FALSE) {
			$STATINFO | Add-Member -MemberType Noteproperty -name "[OS] CPU (%)" -value "WMI connection failure"
			$STATINFO | Add-Member -MemberType Noteproperty -name "[OS] Memory Used" -value "WMI connection failure"
			$STATINFO | Add-Member -MemberType Noteproperty -name "[OS] Top 3 Memory Processes" -value "WMI connection failure"
		}

	$STATFINAL += $STATINFO
	if ($VIEW -ne "csv") {$STATFINAL[$i-1]}
	Write-Progress -activity "Checking Servers" -status "$VMIND" -PercentComplete (($i / $VM.length)  * 100)
	}

if ($VIEW -eq "csv") {$STATFINAL | Export-Csv C:\Users\$([Environment]::UserName)\Desktop\VM-Stats-$(Get-Date -format dd-MM-yyyy).csv -NoTypeInformation}
