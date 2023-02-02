function Get-VIVcenterSummary {

    <#
        .SYNOPSIS
            Returns summary counts for Datacenter, clusters, hosts and VMs, for a given vCenter Server
        .DESCRIPTION
            Returns summary counts for Datacenter, clusters, hosts and VMs, for a given vCenter Server.

            There are 4 summary report types: vCenter, DataCenter, Cluster and TotalCount. The default report is vCenter.

        .PARAMETER Server
            vCenter server FQDN
        .PARAMETER SummaryType
            The type of summary report you would like to generate.
        .INPUTS
            System.String
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        .EXAMPLE
            Get-VcenterSummary -Server 'vcenter01.domain.corp' -SummaryType vCenter -Verbose
        .EXAMPLE
            Get-VcenterSummary -Server 'vcenter01.domain.corp' -SummaryType Cluster -Verbose | Format-Table -AutoSize
        .NOTES
            Author: Kevin Kirkpatrick
            Email:
            Last Updated: 20171018
            Last Update By: K. Kirkpatrick
            Last Update Notes:
            - Added vCenter Unique ID output
        #>

    [OutputType([System.Management.Automation.PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'default')]
    param (
        [parameter(
            Mandatory = $false,
            Position = 0)]
        [alias('VIServer')]
        $Server,

        [parameter(
            Mandatory = $false,
            Position = 1)]
        [ValidateSet('vCenter', 'DataCenter', 'Cluster', 'TotalCount')]
        [System.String]$SummaryType = 'vCenter'
    )

    BEGIN {

        #Requires -Version 3

        # if not value was given to the -Server param, check to see if there are any connected vCenter servers, and attempt to run it against, all of those
        if (-not($PSCmdlet.MyInvocation.BoundParameters.Keys.Contains('Server'))) {

            # using Test-Path to check for variable; if we don't, we will get an error complaining about looking for a variable that hasn't been set
            if (Test-Path -Path Variable:\Global:defaultViServers) {

                $Server = (Get-Variable -Scope Global -Name DefaultViServers).Value | Select-Object * | Where-Object {$_.IsConnected -eq $true}

                if ($Server -eq $null -or $Server -eq '') {

                    throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] No Value was provided to the '-Server' Parameter and no current connection could be found"

                } else {

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing connected vCenter servers discovered in variable { Global:DefaultViServers }"

                } # end else/if

            } else {

                throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] No Value was provided to the -Server Parameter and no current connection could be found; variable { Global:DefaultViServers } does not exist"

            } # end if/else Test-Path

        } else {

            # run a match on the value that was provided to the -Server parameter and only return connections for specified servers
            $Server = foreach ($serverValue in $Server) {

                (Get-Variable -Scope Global -Name DefaultViServers).Value | Select-Object * | Where-Object { $PSItem.Name -eq $serverValue }

            } # end $Server

        } # end if/else

    } # end BEGIN block

    PROCESS {


        switch ($SummaryType) {

            'vCenter' {

                [System.DateTime]$dateGenerated = Get-Date

                foreach ($vcenter in $Server) {

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$($vcenter.Name)] Gathering vCenter Summary Detail"
                    try {

                        $siView = $null
                        $siView = Get-View -Server $vcenter.Name ServiceInstance -ErrorAction 'Stop'
                        $endpointType = $siView.Content.About.FullName

                        if ($endpointType -like '*esx*') {

                            Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Skipping directly connected ESXi host { $($vcenter.Name) }"

                        } else {

                            $dcView             = $null
                            $clusView           = $null
                            $vmHostView         = $null
                            $guestView          = $null
                            $settingView        = $null
                            $uniqueId           = $null
                            $endpointType       = $null

                            $dcView = Get-View -Server $vcenter.Name -ViewType Datacenter -Property Name -ErrorAction 'Stop'
                            $clusView = Get-View -Server $vcenter.Name -ViewType ClusterComputeResource -Property Name -ErrorAction 'Stop'
                            $vmHostView = Get-View -Server $vcenter.Name -ViewType HostSystem -Property Name -ErrorAction 'Stop'
                            $guestView = Get-View -Server $vcenter.Name -ViewType VirtualMachine -Property Name, Config -ErrorAction 'Stop' | Where-Object { $PSItem.Config.Template -eq $false }

                            $settingView = Get-View -Server $vcenter.Name $siView.Content.Setting -ErrorAction 'Stop'
                            $uniqueId = ($settingView.QueryOptions("instance.id")).Value

                            [PSCustomObject] @{
                                vCenter              = $vcenter.Name
                                vCenterServerVersion = $vcenter.Version
                                vCenterID            = $uniqueId
                                DataCenters          = $dcView.Name.Count
                                Clusters             = $clusView.Name.Count
                                Hosts                = $vmHostView.Name.Count
                                Guests               = $guestView.Name.Count
                                DateGenerated        = $dateGenerated
                            } # end obj

                        } # end if/else

                    } catch {

                        throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$($vcenter.Name)][ERROR] Failed to gather vCenter Summary Detail. $_"
                        continue

                    } # end try/catch

                } # end foreach $vcenter

            } # end 'vCenter'

            'Datacenter' {

                foreach ($vcenter in $Server) {

                    Write-Verbose -Message "[$($vcenter.Name)] Gathering Data Center Summary Details"

                    # only doing a single try/catch for the first Get-View query since it's safe to assume that querying the rest of the vSphere API will work, if the first query passes
                    try {

                        $dcView = $null
                        $dcView = Get-View -Server $vcenter.Name -ViewType Datacenter -Property Name -ErrorAction 'Stop'

                    } catch {

                        throw "[$($vcenter.Name)][$($datacenter.Name)][ERROR] Failed to gather Data Center Summary Detail. $_"
                        continue

                    } # end try/catch

                    foreach ($datacenter in $dcView) {

                        $clusterQuery = $null
                        $hostQuery = $null
                        $guestQuery = $null
                        $objResults = @()

                        [System.DateTime]$dateGenerated = Get-Date

                        Write-Verbose -Message "[$($vcenter.Name)][$($datacenter.Name)] Gathering Datacenter summary details"

                        $clusterQuery = Get-View -Server $vcenter.Name -ViewType ClusterComputeResource -Property Name -SearchRoot $datacenter.MoRef
                        $hostQuery = Get-View -Server $vcenter.Name -ViewType HostSystem -Property Name -SearchRoot $datacenter.MoRef
                        $guestQuery = Get-View -Server $vcenter.Name -ViewType VirtualMachine -Property Name, Config -SearchRoot $datacenter.MoRef | Where-Object {$PSItem.Config.Template -eq $false }

                        [PSCustomObject] @{
                            vCenter              = $vcenter.Name
                            vCenterServerVersion = $vcenter.Version
                            DataCenter           = $datacenter.Name
                            ClusterCount         = $clusterQuery.Name.Count
                            HostCount            = $hostQuery.Name.Count
                            VMCount              = $guestQuery.Name.Count
                            DateGenerated        = $dateGenerated
                        } # end obj

                    } # foreach $datacenter

                } # end foreach $vcenter

            } # end 'Datacenter'

            'Cluster' {

                foreach ($vcenter in $Server) {

                    Write-Verbose -Message "[$($vCenter.Name)] Collecting Cluster Summary Detail"
                    try {

                        $datacenterQuery = $null
                        $datacenterQuery = Get-View -Server $vcenter.Name -ViewType Datacenter -Property Name -ErrorAction 'Stop'

                    } catch {

                        throw "[$($vcenter.Name)] Error Collecting Summary Detail"
                        continue

                    } # end try/catch

                    foreach ($datacenter in $datacenterQuery) {

                        [System.DateTime]$dateGenerated = Get-Date

                        $clusterQuery = $null
                        $clusterQuery = Get-View -Server $vcenter.Name -ViewType ClusterComputeResource -Property Name, Configuration, Summary, ConfigurationEx -SearchRoot $datacenter.MoRef

                        foreach ($cluster in $clusterQuery) {

                            Write-Verbose -Message "['$($cluster.Name)' Cluster] Working"

                            $clusterMoRef = $null
                            $clusterVMs = $null
                            $clusterHosts = $null

                            $clusterMoRef = $cluster.MoRef

                            $clusterVMs = Get-View -Server $vcenter.Name -ViewType VirtualMachine -Property Name, Config -SearchRoot $cluster.moref | Where-Object {$PSItem.Config.Template -eq $false }

                            [PSCustomObject] @{
                                vCenter                    = $vcenter.Name
                                vCenterServerVersion       = $vcenter.Version
                                Datacenter                 = $datacenter.Name
                                Name                       = $cluster.Name
                                Status                     = $cluster.Summary.OverallStatus
                                HAEnabled                  = $cluster.Configuration.DasConfig.Enabled
                                HAAdmissionControlEnabled  = $cluster.Configuration.DasConfig.AdmissionControlEnabled
                                DRSEnabled                 = $cluster.Configuration.DrsConfig.Enabled
                                DRSAutomationLevel         = $cluster.Configuration.DrsConfig.DefaultVmBehavior
                                VSANEnabled                = $cluster.ConfigurationEx.VsanConfigInfo.Enabled
                                VSANDiskClaimMode          = if ($cluster.ConfigurationEx.VsanConfigInfo.DefaultConfig.AutoClaimStorage -eq $false) { 'manual' } else { 'automatic' }
                                EVCMode                    = $cluster.Summary.CurrentEVCModeKey
                                HostCount                  = $cluster.Summary.NumHosts
                                EffectiveHostCount         = $cluster.Summary.NumEffectiveHosts
                                VMCount                    = $clusterVMs.Name.Count
                                NumVmotions                = $cluster.Summary.NumVmotions
                                CPUFailoverResourcePercent = $cluster.Summary.AdmissionControlInfo.CurrentCpuFailoverResourcesPercent
                                RAMFailoverResourcePercent = $cluster.Summary.AdmissionControlInfo.CurrentMemoryFailoverResourcesPercent
                                DateGenerated              = $dateGenerated
                            } # end $objVISummary

                        } # end foreach $cluster

                    } # end foreach $datacenter

                } # end 'Cluster'

            } # end foreach vCenter

            'TotalCount' {

                $colTotalCount = @()
                [System.DateTime]$dateGenerated = Get-Date

                foreach ($vcenter in $Server) {

                    Write-Verbose -Message "[$($vcenter.Name)] Gathering vCenter Summary Detail"
                    try {

                        $dcView = $null
                        $clusView = $null
                        $vmHostView = $null
                        $guestView = $null

                        $dcView = Get-View -Server $vcenter.Name -ViewType Datacenter -Property Name -ErrorAction 'Stop'
                        $clusView = Get-View -Server $vcenter.Name -ViewType ClusterComputeResource -Property Name -ErrorAction 'Stop'
                        $vmHostView = Get-View -Server $vcenter.Name -ViewType HostSystem -Property Name -ErrorAction 'Stop'
                        $guestView = Get-View -Server $vcenter.Name -ViewType VirtualMachine -Property Name, Config | Where-Object {$PSItem.Config.Template -eq $false }

                    } catch {

                        throw "[$($vcenter.Name)][ERROR] Failed to gather vCenter Summary Detail. $_"
                        continue

                    } # end try/catch

                    # save each object iteration to a collection so that total numbers can be calcualted
                    $obj = @()
                    $obj = [PSCustomObject] @{
                        vCenter     = $vcenter.Name
                        DataCenters = $dcView.Name.Count
                        Clusters    = $clusView.Name.Count
                        Hosts       = $vmHostView.Name.Count
                        Guests      = $guestView.Name.Count
                    }
                    $colTotalCount += $obj

                } # end foreach $vcenter

                [PSCustomObject] @{
                    vCenterServers = $colTotalCount.vCenter.Count
                    DataCenters    = ($colTotalCount.DataCenters | Measure-Object -Sum).Sum
                    Clusters       = ($colTotalCount.Clusters | Measure-Object -Sum).Sum
                    Hosts          = ($colTotalCount.Hosts | Measure-Object -Sum).Sum
                    Guests         = ($colTotalCount.Guests | Measure-Object -Sum).Sum
                    DateGenerated  = $dateGenerated
                } # end obj

            } # end 'TotalCount'

        } # end switch

    } # end PROCESS block

    END {

        # clean up work goes here

    } # end END block

} # end function Get-VcenterSummary

