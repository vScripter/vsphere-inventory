function Get-VIVMHostMapping {

    <#
    .SYNOPSIS
        Returns basic VMhost mapping from the VMHost all the way up to the vCenter Server
    .DESCRIPTION
        Returns basic VMhost mapping from the VMHost all the way up to the vCenter Server

        This information can be used to provide basic inventory information for VMHosts.

        Example output:

Name              : esxi03.corp.local
vCenterServer     : vcenter01.corp.local
Datacenter        : lab
Cluster           : mgmt
Version           : 6.0.0
Build             : 9239799
APIVersion        : 6.0
HAStatus          : master
ConnectionState   : connected
PowerState        : poweredOn
InMaintenanceMode : False
UptimeInDays      : 1
Manufacturer      : HP
Model             : ProLiant DL980 G7
CPUModel          : Intel(R) Xeon(R) CPU E7- 4870  @ 2.40GHz
CPUSockets        : 4
CPUCores          : 40
CPUHyperCores     : 80
CPUCoresPerSocket : 10
MemorySizeGB      : 510
NumNICs           : 10
NumHBAs           : 5
RebootRequired    : False
CurrentEVCMode    : intel-nehalem
MaxEVCMode        : intel-westmere
vCenterVersion    : 6.5.0
Generated         : 8/7/2018 12:17:19 AM
    .PARAMETER Server
        VI (vCenter) server name
    .PARAMETER Credential
        PS Credential to pass to connecting to the vCenter server
    .INPUTS
        System.String
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .EXAMPLE
        Get-MHostMapping -Verbose | Export-Csv C:\VMHostMappings.csv -NoTypeInformation -Force
    .EXAMPLE
        Get-MHostMapping -Verbose | Out-GridView
    .EXAMPLE
        Get-MHostMapping -Server 'vcenter01.corp.com' -Credential (Get-Credential) -Verbose | Out-GridView

        This will connected to a specific vCenter Server and prompt for a different set of credentials during execution.
    .NOTES
        Author: Kevin Kirkpatrick, Rolta|AdvizeX
        Version: 1.3
        Last Update: 20180807
        Last Update Notes:
        - Streamlined execution when using -Server and -Credential parameters
        - Cleaned up some of the verbose messaging
    #>

    [OutputType([System.Management.Automation.PSCustomObject])]
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $false, Position = 0)]
        [alias('VIServer')]
        [System.String]$Server,

        [parameter(Mandatory = $false, Position = 1)]
        [System.Management.Automation.PSCredential]$Credential

    )

    BEGIN {

        #Requires -Version 3

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Started"

        # if -Server was specified, try connecting, else make sure there is a valid connection
        if ($Server) {

            Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] If -Server is used but no credential is specified, the currently logged in user account will be used to authenticate"

            try {

                if ($Credential) {

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Connecting to vCenter Server {$Server} with credential {$(($Credential).UserName)\******}"
                    Connect-VIServer -Server $Server -Credential $Credential -ErrorAction 'Stop' | Out-Null

                } else {

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Connecting to vCenter Server {$Server}"
                    Connect-VIServer -Server $Server -ErrorAction 'Stop' | Out-Null

                } # end if/else $Credential

            } catch {

                Write-Warning -Message 'Error connecting to vCenter'
                Write-Warning -Message 'Exiting script'
                break

            } # end try/catch

        } elseif (($global:defaultviserver).Name -eq $null) {

            Write-Warning -Message 'No default vCenter connection. Connect to vCenter or specify a vCenter Server name and try again.'
            Write-Warning -Message 'Exiting script'
            break

        } # end if/elseif

        # Don't think this is really valid: Removed on 20180726 -KK
        #$viServer = $global:defaultviserver.Name
        #$viServerVersion = $global:defaultviserver.Version

        # catch all connected vCenter Servers
        $viServerList = $Global:defaultviservers | Where-Object {$_.IsConnected -eq $true}

    } # end BEGIN block

    PROCESS {


        foreach ($entry in $viServerList) {

            $viServer = $null
            $viServer = $entry.Name

            $viServerVersion = $null
            $viServerVersion = $entry.Version

            Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$viServer] Gathering List of Datacenters"
            try {

                $datacenterQuery = Get-View -Server $viServer -ViewType Datacenter -Property Name -ErrorAction 'Stop'

            } catch {

                Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$viServer] Error Gathering List of Datacenters"
                Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$viServer] Exiting script"
                break

            } # end try/catch

            $dcCount = ($datacenterQuery).Count
            $dcProgress = 0

            foreach ($datacenter in $datacenterQuery) {

                $dcProgress++
                Write-Progress -Id 1 -ParentId 0 -Activity "Generating VM Host Mapping Detail" -Status "Processing Data Center" -CurrentOperation "$($datacenter.Name)" -PercentComplete (($dcProgress / $dcCount) * 100)

                [System.DateTime]$dateGenerated = Get-Date

                $datacenterName = $null
                $datacenterName = $datacenter.Name

                $clusterQuery = $null
                $clusterQuery = Get-View -Server $viServer -ViewType ClusterComputeResource -Property Name -SearchRoot $datacenter.MoRef

                $clusterCount    = ($clusterQuery).Count
                $clusterProgress = 0

                foreach ($cluster in $clusterQuery) {

                    $clusterProgress++
                    Write-Progress -Id 2 -ParentId 1 -Activity "Gathering Cluster Inventory" -Status "Processing Cluster" -CurrentOperation "$($cluster.Name)" -PercentComplete (($clusterProgress / $clusterCount) * 100)

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$viServer][$($cluster.Name)] Gathering list of VMHosts from cluster"

                    $clusterVmHosts = $null
                    $clusterVmHosts = Get-View -Server $viServer -ViewType HostSystem -Property Name, Config, Hardware, Summary -SearchRoot $cluster.MoRef

                    $vmHostCount = ($clusterVMHosts).Count
                    $vmHostProgress = 0

                    foreach ($vmHostSystem in $clusterVmHosts) {

                        $vmHostProgress++
                        Write-Progress -Id 3 -ParentId 2 -Activity "Gathering VM Host Inventory" -Status 'Processing Hypervisor' -CurrentOperation "$($vmHostSystem.Name)" -PercentComplete (($vmHostProgress / $vmHostCount) * 100)

                        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$viServer][$($cluster.Name)][$($vmHostSystem.Name)] Gathering VMHost Information"

                        [int]$hostUptime            = $null
                        [int]$hostUptimeInDays      = $null
                        [int]$hostCpuCoresPerSocket = $null
                        $memorySize                 = $null
                        $memorySizeGB               = $null

                        $hostUptime            = $vmHostSystem.summary.quickstats.uptime / 86400
                        $hostUptimeInDays      = [System.Math]::Round($hostUptime)
                        $hostCpuCoresPerSocket = ($vmHostSystem.summary.hardware.NumCpuCores) / ($vmHostSystem.summary.hardware.NumCpuPkgs)
                        $memorySize            = (($vmHostSystem.Summary.Hardware.MemorySize / 1024) / 1024) / 1024
                        $memorySizeGB          = [System.Math]::Round($memorySize)

                        [PSCustomObject] @{
                            Name              = $vmHostSystem.name
                            vCenterServer     = $viServer
                            Datacenter        = $datacenterName
                            Cluster           = $cluster.Name
                            Version           = $vmHostSystem.summary.config.product.version
                            Build             = $vmHostSystem.summary.config.product.build
                            APIVersion        = $vmHostSystem.summary.config.product.apiversion
                            HAStatus          = $vmHostSystem.summary.runtime.dashoststate.state
                            ConnectionState   = $vmHostSystem.summary.runtime.ConnectionState
                            PowerState        = $vmHostSystem.summary.runtime.powerstate
                            InMaintenanceMode = $vmHostSystem.summary.runtime.inmaintenancemode
                            UptimeInDays      = $hostUptimeInDays
                            Manufacturer      = $vmHostSystem.summary.hardware.vendor
                            Model             = $vmHostSystem.summary.hardware.model
                            SerialNumber      = $($vmHostSystem.Hardware.SystemInfo.OtherIdentifyingInfo | Where-Object {$_.IdentifierType.Key -eq 'ServiceTag' }).IdentifierValue
                            CPUModel          = $vmHostSystem.summary.hardware.cpumodel
                            CPUSockets        = $vmHostSystem.summary.hardware.NumCpuPkgs
                            CPUCores          = $vmHostSystem.summary.hardware.NumCpuCores
                            CPUHyperCores     = $vmHostSystem.summary.hardware.NumCpuThreads
                            CPUCoresPerSocket = $hostCpuCoresPerSocket
                            MemorySizeGB      = $memorySizeGB
                            NumNICs           = $vmHostSystem.summary.hardware.NumNics
                            NumHBAs           = $vmHostSystem.summary.hardware.NumHBAs
                            RebootRequired    = $vmHostSystem.summary.rebootrequired
                            CurrentEVCMode    = $vmHostSystem.Summary.CurrentEVCModeKey
                            MaxEVCMode        = $vmHostSystem.Summary.MaxEVCModeKey
                            NTPServers        = $vmHostSystem.Config.DateTimeInfo.NtpConfig.Server -join '|'
                            SyslogHost        = $($vmHostSystem.Config.Syslog.global.logHost | Where-Object {$_.Key -eq "Syslog.global.logHost"}).Value
                            vCenterVersion    = $viServerVersion
                            Generated         = $dateGenerated
                        } # end object

                    } # end foreach $vmHostSystem

                } # end foreach $cluster

            } # end foreach $datacenter

        } # end foreach $entry

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete"

    } # end END block

} # end function  Get-VIVMHostMapping

