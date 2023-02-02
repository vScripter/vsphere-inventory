function Get-VIVMHostNetworkConfiguration {

    <#
.SYNOPSIS
    This script/function will return VMHost physical and virtual network configuration details
.DESCRIPTION
    This script/function will return VMHost physical and virtual network configuration details. It was written to take an in-depth audit of what is configured
    on the host, as well as what the configuration is on a vSphere Standard Switch and/or vSphere Distributed Switch.

    If you are querying multiple hosts that are managed by the same vCenter server, speed will greatly increase if you supply the vCenter server name in the -Server parameter
.PARAMETER VMHost
    Name of VMHost (FQDN)
.PARAMETER Server
    Name of vCenter server, if desired
.OUTPUTS
    System.Management.Automation.PSCustomObject
.EXAMPLE
    Get-VMHostNetworkConfiguration -VMHost ESXI01.corp.com | Out-GridView
.EXAMPLE
    Get-Cluster 'Prod Cluster' | Get-VMHost | Get-VMHostNetworkConfiguration | Export-Csv C:\VMHostNICReport.csv -NoTypeInformation
.NOTES
    Author: Kevin Kirkpatrick
    Email: See About_MCPoshTools for contact information
    Version: 2.1
    Last Updated: 20180501
    Last Updated By: K. Kirkpatrick
    Last Update Notes:
    - Added 7 new properties to show which vmk interfaces are being tagged for a specific traffic/service type

#>

    [cmdletbinding(DefaultParameterSetName = 'default')]
    param (
        [parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [alias('Name')]
        $VMHost,

        [parameter(Mandatory = $false,
            Position = 1)]
        [alias('VIServer', 'vCenter')]
        [ValidateScript( { Test-Connection -ComputerName $_ -Count 1 -Quiet })]
        [System.String]$Server
    )

    BEGIN {

        if ($Server) {

            <# grabbing the VDS PortGroup data here, IF a vCenter server name is specified, which will greatly speed up processing time if running a query
        on multiple VMHosts (as long as they are managed by the same vCenter server). If $server is not specified, this value is set below, on each
        host iteration, using the ServiceUri as the search base #>

            Write-Verbose -Message "[Get-VMHostNetworkConfiguration] Gathering VDS PortGroup Data from vCenter {$Server}"
            try {

                $dvPortGroupView = Get-View -Server $Server -ViewType DistributedVirtualPortgroup -Property Key, Config -ErrorAction 'Stop'

            } catch {

                Write-Warning -Message "[Get-VMHostNetworkConfiguration][$Server][ERROR] Could not gather VDS PortGroup Data. $_ "
                break

            } # end try/catch

        } # end if $Server

    } # end BEGIN block

    PROCESS {

        foreach ($vhost in $VMHost) {

            $vmHostView = $null
            $vmhostServerServiceURL = $null
            $pNics = $null
            $vNics = $null
            $dvData = $null
            $vsData = $null
            $dvPortGroup = $null
            $vsPortGroup = $null
            $finalResult = @()

            Write-Verbose -Message "[Get-VMHostNetworkConfiguration] Gathering NIC Detail from VMHost {$vhost}"
            try {

                <# Use Get-View to filter and only pull in the properties that we need to work with, on the host name in question and then assign sub-property values to variables so it will be easier to call
        in the PSCustomObject #>
                if ($Server) {

                    $vmHostView = Get-View -Server $Server -ViewType HostSystem -Property Name, Config -Filter @{ "Name" = "$vhost" }

                } else {

                    $vmHostView = Get-View -ViewType HostSystem -Property Name, Config -Filter @{ "Name" = "$vhost" }

                } # end if/else $Server

            } catch {

                Write-Warning -Message "[Get-VMHostNetworkConfiguration][$vhost][ERROR] Could not gather NIC detail. $_"
                break

            } # end try/catch

            $vmhostServerServiceURL = $vmHostView.Client.ServiceUrl

            try {

                if (-not ($Server)) {

                    Write-Verbose -Message '[Get-VMHostNetworkConfiguration] Gathering VDS PortGroup Data'
                    <# After testing, in large environments, I found that the PortGroup 'Key' value is not necessarily a unique ID. If connected to multiple vCenter servers,
            you could end up returning multiple values for vmk interface mappings to a VDS PortGroup, which is not desired and inaccurate. If a vCenter server name is
            provided in the -Server parameter, speed will be greatly increased. #>
                    $dvPortGroupView = Get-View -ViewType DistributedVirtualPortgroup -Property Key, Config |
                        Where-Object { $_.Client.ServiceUrl -eq "$vmhostServerServiceURL" }

                } # end if -not $Server

            } catch {

                Write-Warning -Message "[Get-VMHostNetworkConfiguration][$vhost][ERROR] Could not gather VDS PortGroup Data. $_"
                break

            } # end try/catch

            $pNics = $vmHostView.Config.Network.Pnic
            $vNics = $vmHostView.Config.Network.Vnic
            $dvData = $vmHostView.Config.Network.ProxySwitch
            $vsData = $vmHostView.Config.Network.Vswitch
            $dvPortGroup = $dvPortGroupView.Config
            $vsPortGroup = $vmHostView.Config.Network.PortGroup.Spec
            $vnicManagerInfo = $vmHostView.Config.VirtualNicManagerInfo.NetConfig

            # Pull in detail for physical interface details
            foreach ($pnic in $pNics) {

                $objNic = $null
                <# At the time this script was written, the easiest way for me to pull in details about the DVS/VSS was to match the interface details found in one sub-property tree,
            with the details found in a different sub-property tree, and then return the desired property value. This methodology was the primary reason the $dvData and $vsData
            variables were created. This is also true for the virtual interface details, this I will not include a comment for that section    #>
                $objNic = [PSCustomObject] @{
                    vCenterServer                = ([uri]$vmhostServerServiceURL).Host
                    VMHost                       = $vmHostView.Name
                    NICType                      = 'Physical'
                    Name                         = $pnic.Device
                    PciID                        = $pnic.Pci
                    MACAddress                   = $pnic.Mac
                    Driver                       = $pnic.Driver
                    LinkSpeedMB                  = $pnic.LinkSpeed.SpeedMB
                    DVSwitch                     = ($dvData | Select-Object DVSName, pNic, MTU | Where-Object { $_.pnic -like "*-$($pnic.device)" }).DvsName
                    DVSMTU                       = [System.String]($dvData | Select-Object DVSName, pNic, MTU | Where-Object { $_.pnic -like "*-$($pnic.device)" }).MTU
                    VSSSwitch                    = ($vsData | Select-Object Name, pNic, MTU | Where-Object { $_.pnic -like "*-$($pnic.device)" }).Name
                    VSSMTU                       = [System.String]($vsData | Select-Object Name, pNic, MTU | Where-Object { $_.pnic -like "*-$($pnic.device)" }).MTU
                    VMKMTU                       = $null
                    DHCPEnabled                  = $null
                    IPAddress                    = $null
                    SubnetMask                   = $null
                    DVSPortGroup                 = $null
                    DVSPortGroupVLAN             = $null
                    VSSPortGroup                 = $null
                    VSSPortGroupVLAN             = $null
                    ManagementTraffic            = $null
                    vMotionTraffic               = $null
                    VsanTraffic                  = $null
                    vSphereProvisioningTraffic   = $null
                    vSphereReplicationTraffic    = $null
                    vSphereReplicationNfcTraffic = $null
                    FaultToleranceTraffic        = $null
                } # end obj

                $finalResult += $objNic

            } # end foreach $pnic

            # pull in info for virtual interface details
            foreach ($vnic in $vNics) {

                $objNic = $null
                $ManagementTrafficQuery = $null
                $vMotionTrafficQuery = $null
                $VsanTrafficQuery = $null
                $vSphereProvisioningTrafficQuery = $null
                $vSphereReplicationTrafficQuery = $null
                $vSphereReplicationNfcTrafficQuery = $null
                $FaultToleranceTrafficQuery = $null

                $ManagementTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'management').SelectedVnic -Like "*$($vnic.Key)" }).Device
                $vMotionTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'vmotion').SelectedVnic -Like "*$($vnic.Key)" }).Device
                $VsanTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'vsan').SelectedVnic -Like "*$($vnic.Key)" }).Device
                $vSphereProvisioningTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'vSphereProvisioning').SelectedVnic -Like "*$($vnic.Key)" }).Device
                $vSphereReplicationTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'vSphereReplication').SelectedVnic -Like "*$($vnic.Key)" }).Device
                $vSphereReplicationNfcTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'vSphereReplicationNFC').SelectedVnic -Like "*$($vnic.Key)" }).Device
                $FaultToleranceTrafficQuery = ($vnic | Where-Object { ($vnicManagerInfo | Where-Object NicType -eq 'faultToleranceLogging').SelectedVnic -Like "*$($vnic.Key)" }).Device

                $objNic = [PSCustomObject] @{
                    vCenterServer                = ([uri]$vmhostServerServiceURL).Host
                    VMHost                       = $vmHostView.Name
                    NICType                      = 'Virtual'
                    Name                         = $vnic.Device
                    PciID                        = $null
                    MACAddress                   = $vnic.Spec.Mac
                    Driver                       = $null
                    LinkSpeedMB                  = $null
                    DVSwitch                     = $null
                    DVSMTU                       = $null
                    VSSSwitch                    = $null
                    VSSMTU                       = $null
                    VMKMTU                       = $vnic.Spec.Mtu
                    DHCPEnabled                  = $vnic.Spec.Ip.Dhcp
                    IPAddress                    = $vnic.Spec.Ip.IpAddress
                    SubnetMask                   = $vnic.Spec.Ip.SubnetMask
                    DVSPortGroup                 = ($dvPortGroup | Select-Object Key, Name, DefaultPortConfig | Where-Object { $_.Key -eq "$($vnic.Spec.DistributedVirtualPort.PortGroupKey)" }).Name
                    DVSPortGroupVLAN             = ($dvPortGroup | Select-Object Key, Name, DefaultPortConfig | Where-Object { $_.Key -eq "$($vnic.Spec.DistributedVirtualPort.PortGroupKey)" }).defaultportconfig.Vlan.VlanID
                    VSSPortGroup                 = $vnic.Portgroup
                    VSSPortGroupVLAN             = ($vsPortGroup | Where-Object { $_.Name -eq "$($vnic.Portgroup)" }).VlanID
                    ManagementTraffic            = if ($ManagementTrafficQuery -Contains $vnic.Device ) {$true} else {$null}
                    vMotionTraffic               = if ($vMotionTrafficQuery -Contains $vnic.Device ) {$true} else {$null}
                    VsanTraffic                  = if ($VsanTrafficQuery -Contains $vnic.Device ) {$true} else {$null}
                    vSphereProvisioningTraffic   = if ($vSphereProvisioningTrafficQuery -Contains $vnic.Device ) {$true} else {$null}
                    vSphereReplicationTraffic    = if ($vSphereReplicationTrafficQuery -Contains $vnic.Device ) {$true} else {$null}
                    vSphereReplicationNfcTraffic = if ($vSphereReplicationNfcTrafficQuery -Contains $vnic.Device ) {$true} else {$null}
                    FaultToleranceTraffic        = if ($FaultToleranceTrafficQuery -Contains $vnic.Device ) {$true} else {$null}

                } # end $objNic

                $finalResult += $objNic

            } # end roeach $vnic

            $finalResult

        } # end foreach $vhost

    } # end PROCESS block

    END {

        Write-Verbose -Message '[Get-VMHostNetworkConfiguration] Processing Complete.'

    } # end END block

} # end function Get-VIVMHostNetworkConfiguration

