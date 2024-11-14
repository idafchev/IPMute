$global:MonitoredProcesses = @('msedge', 'explorer', 'svchost') # process names without extension '.exe' !
$global:DiscoveredIPAddresses = @()
$global:Adapters = Get-NetAdapter -Physical | ? {$_.Status -eq "up"}
$global:BlockingAdapter = $null

# Continiously monitor for new TCP connections started from the monitored processes
# and block the destination IP address. Record it in a global array for cleanup.
function Monitor-NewIPAddresses {
	Write-Host "Started monitoring..."
	while($true) {
		foreach ($process in $global:MonitoredProcesses) {
			$proc = Get-Process $process -ErrorAction SilentlyContinue
			foreach($p in $proc){
				$ips = $(Get-NetTCPConnection -OwningProcess $p.Id -State Established -ErrorAction SilentlyContinue | ? {$_.RemoteAddress -ne "127.0.0.1"})
				foreach ($ip in $ips) {
					if (-not $global:DiscoveredIPAddresses.Contains($ip.RemoteAddress)) {
						$global:DiscoveredIPAddresses += @($ip.RemoteAddress)
						Write-Host "Discovered new IP '$($ip.RemoteAddress)' from process '$process'"
						Block-IPAddress $ip.RemoteAddress
					}
				}
			}
		}
	}
}

# Secondary UP addresses can be added only when the network adapter is using static configuration.
# Get the current IP and DNS settings and re-configure the adapter to use these values in a static configuration instead of DHCP.
# All enabled physical adapters are re-configured.
function Set-StaticIPConfiguration {
	Write-Host "Converting to static IP configuration..."
	$global:Adapters | ForEach-Object {
		$adapter_config_1 = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $_.ifAlias
		$adapter_config_2 = Get-NetIPConfiguration -InterfaceAlias $_.ifAlias -Detailed

		if($adapter_config_1.IPAddress){
			$global:BlockingAdapter = $_ # Use the first adapter which has IP Address configured
			Remove-NetIPAddress -Confirm:$false -InterfaceAlias $_.ifAlias -AddressFamily IPv4 | Out-Null

			if($adapter_config_2.IPv4DefaultGateway){
				Remove-NetRoute -Confirm:$false -InterfaceAlias $_.ifAlias -AddressFamily IPv4 | Out-Null
				New-NetIPAddress -Confirm:$false -InterfaceAlias $_.ifAlias -PrefixLength $adapter_config_1.PrefixLength -IPAddress $adapter_config_1.IPAddress -DefaultGateway $adapter_config_2.IPv4DefaultGateway.NextHop | Out-Null
			}
			else{
				New-NetIPAddress -Confirm:$false -InterfaceAlias $_.ifAlias -PrefixLength $adapter_config_1.PrefixLength -IPAddress $adapter_config_1.IPAddress | Out-Null
			}
			
			$ipv4DNS = $($adapter_config_2.DNSServer | ? {$_.AddressFamily -eq 2}).ServerAddresses
			if($ipv4DNS){
				Set-DnsClientServerAddress -Confirm:$false -InterfaceAlias $_.ifAlias -ServerAddresses $ipv4DNS | Out-Null
			}
			
			return # don't iterate through the rest of the adapters
		}
	}
}

# Blocking the destination IP address on each enabled physical adapter.
# Currently adding the IP with /24 prefix.
# Any packets destined to that IP will be sent to the directly attached adapter.
function Block-IPAddress {
	param ($ip)
	
	if($global:BlockingAdapter){
		# To be more accurate /32 may be used instead of /24 prefix
		New-NetIPAddress -Confirm:$false -SkipAsSource:$true -InterfaceAlias $global:BlockingAdapter.ifAlias -PrefixLength 24 -IPAddress $ip | Out-Null
		Write-Host "Blocked IP Net '$ip/24' on interface '$($global:Adapters[0].ifAlias)'"
	}
}

# Used for cleanup.
# Remove each discovered IP address from all enabled physical adapters.
function Remove-BlockedIPAddresses {
	if($global:BlockingAdapter){
		foreach ($ip in $global:DiscoveredIPAddresses) {
			Remove-NetIPAddress -Confirm:$false -InterfaceAlias $global:BlockingAdapter.ifAlias -IPAddress $ip | Out-Null
			Write-Host "Removed IP '$($ip)' from blocklist on interface '$($global:Adapters[0].ifAlias)'"
		}
	}
}

try {
	Set-StaticIPConfiguration
	Monitor-NewIPAddresses
}
finally {
	Write-Host "Cleanup..."
	Remove-BlockedIPAddresses
}
