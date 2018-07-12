<#
.NOTES

    This file contains a manually populated list of functions that are used to gather common inventory
    details from a vSphere environment.

    -----------------------
    Author: Kevin M. Kirkpatrick
    Email:
    Last Update: 20171018
    Last Updated by: K. Kirkpatrick
    Last Update Notes:
    - Created
#>

function Get-VITimeStamp {

    $transcriptTimeStamp = $null

    <# Use the 's' DateTime specifier to append a 'sortable' datetime to the transcript file name.
    This guarantees a unique file name for each second. #>

    $transcriptTimeStamp = (Get-Date).ToString('s').Replace('T', '.')

    # grab the time zone and use a switch block to assign time zone code
    $timeZoneQuery = [System.TimeZoneInfo]::Local
    $timeZone = $null

    switch -wildcard ($timeZoneQuery) {

        '*Eastern*' { $timeZone = 'EST' }
        '*Central*' { $timeZone = 'CST' }
        '*Pacific*' { $timeZone = 'PST' }

    } # end switch

    $transcriptTimeStamp = "$($transcriptTimeStamp)-$timeZone" -Replace ':', ''
    $transcriptTimeStamp
} # end function Get-TimeStamp

function Get-VIVMMapping {

    <#
        .SYNOPSIS
            Returns basic location/environment information about where a virtual machine is located in the infrastructure
        .DESCRIPTION
            Returns basic location/environment information about where a virtual machine is located in the infrastructure

            This can be useful for generating a report of basic guest information and status.
        .PARAMETER Server
            VI (vCenter) server name
        .PARAMETER Credential
            PS Credential to pass to vCenter Server connection
        .PARAMETER ReadInCredential
            Use this switch parameter if you wish to read in credentials from a pre-saved file. The files need to exist in a/the same directory.
        .PARAMETER CredentialStorePath
            UNC path to a directory where encrypted credential files are stored. These files should be created using the Export-Credential cmdlet/function that is part of this module
        .INPUTS
            System.String
            System.Management.Automation.PSCredential
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        .EXAMPLE
            Get-VMMapping -Verbose | Export-Csv C:\VMGuestMappings.csv -NoTypeInformation -Force
        .EXAMPLE
            Get-VMMapping -Verbose | Out-GridView
        .NOTES
            Author: Kevin M. Kirkpatrick
            Email:
            Version: 1.5
            Last Update: 20161118
            Last Updated By: K. Kirkpatrick
            Last Update Notes:
            - Added support for multiple vCenter Servers that are either specified/alredy connected.
            - Removed 'VMHost' property from output, as well as associated code. (It's irrelevant, given HA/DRA/vMotion, and it greatly increased overall execution)
            - Now much faster due to the previous bullet point
        #>

    [cmdletbinding(DefaultParameterSetName = 'Default')]
    param (
        [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Default')]
        [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Cred')]
        [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'ReadInCred')]
        [alias('VIServer')]
        [System.String]$Server,

        [parameter(Mandatory = $false, Position = 1, ParameterSetName = 'Cred')]
        [System.Management.Automation.PSCredential]$Credential,

        [parameter(Mandatory = $false, Position = 1, ParameterSetName = 'ReadInCred')]
        [Switch]$ReadInCredential,

        [parameter(Mandatory = $false, Position = 2, ParameterSetName = 'ReadInCred', HelpMessage = 'Enther the UNC path to the directory where the credential files are stored ')]
        [ValidateScript( { Test-Path -LiteralPath $_ -PathType Container })]
        [System.String]$CredentialStorePath = 'I:\Input\Credentials'
    )

    BEGIN {

        #Requires -Version 3

        # if -Server was specified, try connecting, else make sure there is a valid connection
        if ($Server) {

            Write-Verbose -Message 'Connecting to vCenter Server'

            try {

                if ($Credential) {

                    $userName = $null
                    $userName = $Credential.UserName

                    Write-Verbose -Message "Alternative credentials provided. Attempting to connect with {$userName\*******}"
                    Connect-VIServer -Server $Server -Credential $Credential | Out-Null

                } elseif ($ReadInCredential) {

                    $credentialFile = $null
                    $importCredential = $null
                    $credentialUserName = $null
                    $computerShortName = $null

                    if (($Server).Contains('.') -eq $true) {

                        $computerShortName = ($Server).Split('.')[0].ToUpper()

                    } else {

                        $computerShortName = $Server.ToUpper()

                    } # end if/else

                    $credentialFile = (Get-ChildItem -LiteralPath $CredentialStorePath -Filter *.clixml -ErrorAction 'Stop' |
                            Where-Object { $_.Name -eq "$($computerShortName)_Cred.clixml" }).FullName

                    $importCredential = Import-Credential -Path $credentialFile -ErrorAction 'Stop'
                    $credentialUserName = $importCredential.UserName

                    Write-Verbose -Message "Alternative credentials imported from file {$credentialFile}. Attempting to connect with {$credentialUserName\*******}"
                    Connect-VIServer -Server $Server -Credential $importCredential | Out-Null

                } else {

                    # removed this; don't really like how connecting to vCenters is handled; need to figure out how better to handle things
                    #Connect-VIServer -Server $Server | Out-Null

                } # end if/elseif/else $Credential

            } catch {

                throw 'Error connecting to vCenter; Exiting script.'

            } # end try/catch

        } elseif (($global:defaultviserver).Name -eq $null) {

            throw 'No default vCenter connection. Connect to vCenter or specify a vCenter Server name and try again. Exiting script.'

        } # end if/elseif

        # catch all connected vCenter Servers
        $viServerList = $Global:defaultviservers | Where-Object {$_.IsConnected -eq $true}

    } # end BEGIN block

    PROCESS {

        foreach ($entry in $viServerList) {

            $viServer = $null
            $viServer = $entry.Name

            $viServerVersion = $null
            $viServerVersion = $entry.Version

            # while considered lazy, I only added a try/catch for this initial/parent query since other queries are part of child loops
            Write-Verbose -Message "[$viServer] Gathering List of Clusters"
            try {

                $datacenterQuery = Get-View -Server $viServer -ViewType Datacenter -Property Name -ErrorAction 'Stop'

            } catch {

                throw "[$viServer] Error Gathering List of Clusters. $_. Exiting."

            } # end try/catch

            $dcCount = ($datacenterQuery).Count
            $dcProgress = 0

            foreach ($datacenter in $datacenterQuery) {

                $dcProgress++

                #$dcProgressValue = $null
                #$dcProgressValue = ($dcProgress/$dcCount) * 100

                $dcProgressSplat = $null
                $dcProgressSplat = @{
                    Id               = 1
                    ParentID         = 0
                    Activity         = 'Generating VM Guest Mapping Detail'
                    Status           = 'Processing Data Center'
                    CurrentOperation = "$($datacenter.Name)"
                    PercentComplete  = ($dcProgress / $dcCount) * 100
                }

                Write-Progress @dcProgressSplat

                $datacenterName = $null
                $clusterQuery = $null

                [System.DateTime]$dateGenerated = Get-Date

                $datacenterName = $datacenter.Name

                $clusterQuery = Get-View -Server $viServer -ViewType ClusterComputeResource -Property Name -SearchRoot $datacenter.MoRef

                $clusterCount = ($clusterQuery).Count
                $clusterProgress = 0

                foreach ($cluster in $clusterQuery) {

                    $clusterProgress++

                    #$clusterProgressValue = $null
                    #$clusterProgressValue = ($clusterProgress/$clusterCount) * 100

                    $clusterProgressSplat = $null
                    $clusterProgressSplat = @{
                        Id               = 2
                        ParentID         = 1
                        Activity         = 'Gathering Cluster Inventory'
                        Status           = 'Processing Cluster'
                        CurrentOperation = "$($cluster.Name)"
                        PercentComplete  = ($clusterProgress / $clusterCount) * 100
                    }

                    Write-Progress @clusterProgressSplat

                    Write-Verbose -Message "[$viServer][$($cluster.Name)] Gathering list of VMHosts from cluster"

                    $clusterGuests = $null

                    $clusterGuests = Get-View -Server $viServer -ViewType VirtualMachine -Property Name, Guest, Runtime, Summary, Parent -SearchRoot $cluster.MoRef

                    foreach ($guest in $clusterGuests) {

                        Write-Verbose -Message "[$viServer][$($cluster.Name)] Gathering Guest Details"

                        [PSCustomObject] @{
                            Name           = $guest.Name
                            HostName       = $guest.guest.hostname
                            IPAddress      = $guest.Summary.Guest.IpAddress
                            vCenterServer  = $viServer
                            Datacenter     = $datacenterName
                            Cluster        = $cluster.Name
                            vCenterVersion = $viServerVersion
                            GuestOS        = $guest.Summary.Guest.GuestFullName
                            State          = $guest.Guest.GuestState
                            Status         = $guest.Runtime.PowerState
                            FTEnabled      = if ($guest.Runtime.FaultToleranceState -eq 'running') { [bool]$true } else { [bool]$false }
                            Folder         = (Get-VIVMFolderPath -VM $guest).FolderPath
                            Annotation     = $guest.Summary.Config.Annotation
                            Generated      = $dateGenerated
                        } # end obj

                    } # end forech ($guest in $clusterVMs)

                } # end foreach $cluster

            } # end foreach $datacenter

        } # end foreach $viServer

    } # end PROCESS block

    END {


    } # end END block

} # end function  Get-VMMapping

function Get-VIVMHostMapping {

    <#
        .SYNOPSIS
            Returns basic VMhost mapping from the VMHost all the way up to the vCenter Server
        .DESCRIPTION
            Returns basic VMhost mapping from the VMHost all the way up to the vCenter Server

            This information can be used to provide basic location information for VMHosts and where they are currently running
        .PARAMETER Server
            VI (vCenter) server name
        .PARAMETER Credential
            PS Credential to pass to connecting to the vCenter server
        .PARAMETER ReadInCredential
            Use this switch parameter if you wish to read in credentials from a pre-saved file. The files need to exist in a/the same directory.
        .PARAMETER CredentialStorePath
            UNC path to a directory where encrypted credential files are stored. These files should be created using the Export-Credential cmdlet/function that is part of this module
        .INPUTS
            System.String
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        .EXAMPLE
            Get-BVMHostMapping -Verbose | Export-Csv C:\VMHostMappings.csv -NoTypeInformation -Force
        .EXAMPLE
            Get-BVMHostMapping -Verbose | Out-GridView
        .NOTES
            Author: Kevin M. Kirkpatrick
            Email:
            Version: 1.2
            Last Update: 20150612
            Last Update Notes:
            - Added support for alternate credentials
        #>

    [cmdletbinding(DefaultParameterSetName = 'Default')]
    param (
        [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Default')]
        [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'Cred')]
        [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'ReadInCred')]
        [alias('VIServer')]
        [System.String]$Server,

        [parameter(Mandatory = $false, Position = 1, ParameterSetName = 'Cred')]
        [System.Management.Automation.PSCredential]$Credential,

        [parameter(Mandatory = $false, Position = 1, ParameterSetName = 'ReadInCred')]
        [Switch]$ReadInCredential,

        [parameter(Mandatory = $false, Position = 2, ParameterSetName = 'ReadInCred', HelpMessage = 'Enther the UNC path to the directory where the credential files are stored ')]
        [ValidateScript( { Test-Path -LiteralPath $_ -PathType Container })]
        [System.String]$CredentialStorePath = 'I:\Input\Credentials'

    )

    BEGIN {

        #Requires -Version 3

        # if -Server was specified, try connecting, else make sure there is a valid connection
        if ($Server) {

            Write-Verbose -Message 'Connecting to vCenter Server'

            try {

                if ($Credential) {

                    Connect-VIServer -Server $Server -Credential $Credential -ErrorAction 'Stop' | Out-Null

                } elseif ($ReadInCredential) {

                    $credentialFile = $null
                    $importCredential = $null
                    $credentialUserName = $null
                    $computerShortName = $null

                    if (($Server).Contains('.') -eq $true) {

                        $computerShortName = ($Server).Split('.')[0].ToUpper()

                    } else {

                        $computerShortName = $Server.ToUpper()

                    } # end if/else

                    $credentialFile = (Get-ChildItem -LiteralPath $CredentialStorePath -Filter *.clixml -ErrorAction 'Stop' | Where-Object { $_.Name -eq "$($computerShortName)_Cred.clixml" }).FullName
                    $importCredential = Import-Credential -Path $credentialFile -ErrorAction 'Stop'
                    $credentialUserName = $importCredential.UserName

                    Write-Verbose -Message "Alternative credentials imported from file {$credentialFile}. Attempting to connect with {$credentialUserName\*******}"
                    Connect-VIServer -Server $Server -Credential $importCredential | Out-Null

                } else {

                    Connect-VIServer -Server $Server -ErrorAction 'Stop' | Out-Null

                } # end if/else $Credential

            } catch {

                Write-Warning -Message 'Error connecting to vCenter'
                Write-Warning -Message 'Exiting script'
                break

            } # end try/catch

        } elseif (($global:defaultviserver).Name -eq $null) {

            throw 'No default vCenter connection. Connect to vCenter or specify a vCenter Server name and try again.'

        } # end if/elseif

        #$viServer = $global:defaultviserver.Name
        #$viServerVersion = $global:defaultviserver.Version

        # write selected VI server to the console
        #Write-Verbose -Message "Selected VI Server: $viServer"

        # catch all connected vCenter Servers
        $viServerList = $Global:defaultviservers | Where-Object {$_.IsConnected -eq $true}

    } # end BEGIN block

    PROCESS {

        foreach ($entry in $viServerList){

            $viServer = $null
            $viServer = $entry.Name

            $viServerVersion = $null
            $viServerVersion = $entry.Version

        Write-Verbose -Message "[$viServer] Gathering List of Clusters"
        try {

            $datacenterQuery = Get-View -Server $viServer -ViewType Datacenter -Property Name -ErrorAction 'Stop'

        } catch {

            Write-Warning -Message "[$viServer] Error Gathering List of Clusters"
            Write-Warning -Message "[$viServer] Exiting script"
            break

        } # end try/catch

        $dcCount = ($datacenterQuery).Count
        $dcProgress = 0

        foreach ($datacenter in $datacenterQuery) {

            $dcProgress++
            Write-Progress -Id 1 -ParentId 0 -Activity "Generating VM Host Mapping Detail" -Status "Processing Data Center" -CurrentOperation "$($datacenter.Name)" -PercentComplete (($dcProgress / $dcCount) * 100)

            $datacenterName = $null
            $clusterQuery = $null

            [System.DateTime]$dateGenerated = Get-Date

            $datacenterName = $datacenter.Name

            $clusterQuery = Get-View -Server $viServer -ViewType ClusterComputeResource -Property Name -SearchRoot $datacenter.MoRef

            $clusterCount = ($clusterQuery).Count
            $clusterProgress = 0

            foreach ($cluster in $clusterQuery) {

                $clusterProgress++
                Write-Progress -Id 2 -ParentId 1 -Activity "Gathering Cluster Inventory" -Status "Processing Cluster" -CurrentOperation "$($cluster.Name)" -PercentComplete (($clusterProgress / $clusterCount) * 100)

                Write-Verbose -Message "[$viServer][$($cluster.Name)] Gathering list of VMHosts from cluster"

                #$clusterVMs = $null
                #$clusterVMs = Get-View -Server $viServer -ViewType VirtualMachine -Property Name, Guest, Runtime, Summary -SearchRoot $cluster.MoRef

                $clusterVmHosts = $null

                $clusterVMHosts = Get-View -Server $viServer -ViewType HostSystem -Property Name, Hardware, Summary -SearchRoot $cluster.MoRef

                $vmHostCount = ($clusterVMHosts).Count
                $vmHostProgress = 0

                foreach ($vmHostSystem in $clusterVmHosts) {

                    $vmHostProgress++
                    Write-Progress -Id 3 -ParentId 2 -Activity "Gathering VM Host Inventory" -Status 'Processing Hypervisor' -CurrentOperation "$($vmHostSystem.Name)" -PercentComplete (($vmHostProgress / $vmHostCount) * 100)

                    Write-Verbose -Message "[$viServer][$($cluster.Name)][$($vmHostSystem.Name)] Gathering VMHost Information"

                    $colCustomInfo = @()
                    $objVmHostMapping = @()
                    [int]$hostUptime = $null
                    [int]$hostUptimeInDays = $null
                    [int]$hostCpuCoresPerSocket = $null
                    $memorySize = $null
                    $memorySizeGB = $null

                    $hostUptime = $vmHostSystem.summary.quickstats.uptime / 86400
                    $hostUptimeInDays = [System.Math]::Round($hostUptime)
                    $hostCpuCoresPerSocket = ($vmHostSystem.summary.hardware.NumCpuCores) / ($vmHostSystem.summary.hardware.NumCpuPkgs)
                    $memorySize = (($vmHostSystem.Summary.Hardware.MemorySize / 1024) / 1024) / 1024
                    $memorySizeGB = [System.Math]::Round($memorySize)

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
                        vCenterVersion    = $viServerVersion
                        Generated         = $dateGenerated
                    } # end $objVmHostMapping

                } # end foreach $vmHostSystem

            } # end foreach $cluster

        } # end foreach $datacenter

    } # end foreach $viServer

    } # end PROCESS block

    END {


    } # end END block

} # end function  Get-VMHostMapping

function Get-VIVMDetails {

    <#
    .SYNOPSIS
        Returns more detailed statistics and configuration for a single or multiple VMs
    .DESCRIPTION
        Returns more detailed statistics and configuration for a single or multiple VMs

        This function assumes that you are already connected to one, or more, vCenter Servers.

        You can use the -Inventory switch which will ignore pipeline input and query all connected vCenter Servers.
    .PARAMETER Name
        VM object
    .PARAMETER Server
        Only used in conjunction with -Inventory parameter
    .PARAMETER Inventory
        Switch parameter which will pull a full inventory from the environment with no filtering
    .INPUTS
        System.String
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .EXAMPLE
        Get-VM | Get-VMDetails -Verbose | Export-Csv C:\VMGuestDetails.csv -NoTypeInformation -Force
    .EXAMPLE
        Get-Cluster -Name 'clus-01' | Get-VM | Get-VMDetails -Verbose | Out-GridView
    .EXAMPLE
        Get-VM | Where-Object {$psitem.Powerstate -eq 'PoweredOn'} | Out-GridView
    .EXAMPLE
        Get-VMDetails -Inventory -Verbose | Out-GridView
    .EXAMPLE
        Get-VMDetails -Server vcenter01.corp.com -Inventory -Verbose | Out-GridView
    .EXAMPLE
        Get-VMDetails -Server vcenter01.corp.com,vcenter02.corp.com -Inventory -Verbose | Out-GridView
    .NOTES
        Author: Kevin M. Kirkpatrick
        Email:
        Last Update: 20170408
        Last Updated by: K. Kirkpatrick
        Last Update Notes:
        - Added some changes that better handle output when an inventory file is not fully populated
    #>

    [OutputType([System.Management.Automation.PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'default')]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true,
            ValueFromPipeline = $true,
            ParameterSetName = 'default')]
        [ValidateNotNullOrEmpty()]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$Name,

        [Parameter(
            Mandatory = $false,
            Position = 0,
            ValueFromPipelineByPropertyName = $false,
            ValueFromPipeline = $false,
            ParameterSetName = 'inventory')]
        [System.String[]]$Server,

        [Parameter(
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromPipeline = $false,
            ParameterSetName = 'inventory')]
        [switch]$Inventory
    )

    BEGIN {

        #Requires -Version 3
        Set-StrictMode -Version Latest

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Started"

        # if not value was given to the -Server param, check to see if there are any connected vCenter servers, and attempt to run it against, all of those
        if (-not($PSCmdlet.MyInvocation.BoundParameters.Keys.Contains('Server'))) {

            # using Test-Path to check for variable; if we don't, we will get an error complaining about looking for a variable that hasn't been set
            if (Test-Path -Path Variable:\Global:defaultViServers) {

                $Server = ((Get-Variable -Scope Global -Name DefaultViServers).Value | Where-Object {$_.IsConnected -eq $true}).Name

                if ($Server -eq $null -or $Server -eq '') {

                    throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] No Value was provided to the '-Server' Parameter and no current connection could be found"

                } else {

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing connected vCenter servers discovered in variable { $Global:DefaultViServers }"

                } # end else/if

            } else {

                throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] No Value was provided to the -Server Parameter and no current connection could be found; variable { $Global:DefaultViServers } does not exist"

            } # end if/else Test-Path

        } # end if

        <# dropping support for the 'region' field
            # grab the file with vCenter servers & regions from the module root then import it here, so we can reference it on each guest interation
            try {

                $regionDbPath   = $null
                $regionDatabase = $null
                $regionDbPath   = (Get-Item -Path "$PSScriptRoot\..\Inputs\serverInventoryConfig.json" -ErrorAction 'Stop').FullName    # using Get-Item so we can return a full/proper UNC path
                $regionDatabase = (Get-Content $regionDbPath -Raw -ErrorAction 'Stop' | ConvertFrom-Json -ErrorAction 'Stop').vcenterServer

            } catch {

                Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not import vCenter Inventory file located at { $regionDbPath }"

            } # end try/catch
            #>

    } # end BEGIN block

    PROCESS {

        if ($PSCmdlet.MyInvocation.BoundParameters.Keys.Contains('Inventory')) {

            foreach ($viServer in $Server) {

                Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Gathering guest inventory report for vCenter  { $viServer }"

                $inventoryView = $null
                $inventoryView = Get-View -Server $viServer -ViewType VirtualMachine -Property Name, Guest, Summary, Runtime, Config

                foreach ($guestQuery in $inventoryView) {

                    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Gathering details for VM guest  { $($guestQuery.Name) }"

                    [System.DateTime]$dateGenerated = Get-Date

                    $guestRegion = $null
                    $guestVcenterServer = $null
                    $guestVcenterServer = ([uri]$guestQuery.Client.ServiceUrl).Host

                    <# dropping support for the 'Region' field
                        # match the vcenter server for the guest against the vCenter server DB and then return the region
                        if (Test-Path $regionDbPath -PathType Leaf) {

                            $guestRegion = ($regionDatabase | Where-Object {$PSItem.ComputerName -eq $guestVcenterServer}).region

                        } else {

                            Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Could not find 'Region' information for VM guest  { $($guestQuery.Name) }. vCenter Server { $guestVcenterServer } was not found or there was no 'Region' value assigned. Check the input file { $regionDbPath }"

                            $guestRegion = "Not found in DB file"

                        } # end if/else Test-Path
                        #>

                    # this object contains a few less properties; stick to only making native API calls for full inventory
                    [PSCustomObject] @{
                        Name                    = $guestQuery.Name
                        HostName                = $guestQuery.Guest.HostName
                        OS                      = $guestQuery.Summary.Guest.GuestFullName
                        IPAddress               = $guestQuery.Summary.Guest.IPAddress
                        NumCPU                  = $guestQuery.Summary.Config.NumCPU
                        NumCPUCoresPerSocket    = $guestQuery.Config.Hardware.NumCoresPerSocket
                        MemorySizeGB            = ($guestQuery.Summary.Config.MemorySizeMB) / 1024
                        NumEthernetCards        = $guestQuery.Summary.Config.NumEthernetCards
                        NumVirtualDisks         = $guestQuery.Summary.Config.NumVirtualDisks
                        ProvisionedStorageGB    = [math]::Round(((((($guestQuery.Summary.Storage.Committed) + ($guestQuery.Summary.Storage.Uncommitted)) / 1024) / 1024) / 1024))
                        CommittedStorageGB      = [math]::Round((((($guestQuery.Summary.Storage.Committed) / 1024) / 1024) / 1024))
                        FTEnabled               = if ($guestQuery.Runtime.FaultToleranceState -eq 'running') {
                            [bool]$true
                        } else {
                            [bool]$false
                        }
                        CPUHotAddEnabled        = $guestQuery.Config.CPUHotAddEnabled
                        RAMHotAddEnabled        = $guestQuery.Config.MemoryHotAddEnabled
                        VMToolsInstallerMounted = $guestQuery.Summary.Runtime.ToolsInstallerMounted
                        ToolsVersion            = $guestQuery.Guest.ToolsVersion
                        ToolsStatus             = $guestQuery.Guest.ToolsStatus
                        ToolsVersionStatus      = $guestQuery.Guest.ToolsVersionStatus2
                        ToolsRunningStatus      = $guestQuery.Guest.ToolsRunningStatus
                        ToolsUpgradePolicy      = $guestQuery.Config.Tools.ToolsUpgradePolicy
                        Annotation              = $guestQuery.Summary.Config.Annotation
                        State                   = $guestQuery.Guest.GuestState
                        Status                  = $guestQuery.Summary.Runtime.PowerState
                        vCenterServer           = $guestVcenterServer
                        #Region                  = $guestRegion
                        HardwareVersion         = $guestQuery.Config.Version
                        UUID                    = $guestQuery.Summary.Config.Uuid
                        InstanceUUID            = $guestQuery.Summary.Config.InstanceUUID
                        GuestID                 = $guestQuery.Summary.Config.GuestID
                        Template                = $guestQuery.Summary.Config.Template
                        Generated               = $dateGenerated
                    } # end [PSCustomObject]

                } # end foreach $guest

            } # end foreach

        } else {

            foreach ($guest in $Name) {

                Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Gathering details for VM guest  { $($guest.Name) }"

                [System.DateTime]$dateGenerated = Get-Date

                $guestQuery = $null
                $guestQuery = $guest.ExtensionData

                # capture the vCenter Server up here so that it can be used when performing external queries such as resolving the Cluster property
                $guestvCenterServer = $null
                $guestvCenterServer = ([uri]$guestQuery.Client.ServiceUrl).Host

                <# dropping support for the 'Region' field
                    # match the vcenter server for the guest against the vCenter server DB and then return the region
                    if (Test-Path $regionDbPath -PathType Leaf) {

                        $guestRegion = $null
                        $guestRegion = ($regionDatabase | Where-Object {$PSItem.ComputerName -eq $guestVcenterServer}).region

                    } else {

                        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Could not find 'Region' information for VM guest  { $($guestQuery.Name) }. vCenter Server { $guestVcenterServer } was not found or there was no 'Region' value assigned. Check the input file { $regionDbPath }"

                        $guestRegion = "Not found in DB file"

                    } # end if/else Test-Path
                    #>

                <# Commenting out detail about collecting owner info; it really need to be pulled out and added as it's own cmdlet, like, Get-VMOwner

                    # capture the desired tags for primary and secondary owners
                    $tagAssignment = $null
                    $tagAssignment = $guest | Get-TagAssignment -Server $guestvCenterServer -Category owner-primary-email,owner-secondary-email -ErrorAction 'SilentlyContinue' | Select-Object -Expand Tag -ErrorAction 'SilentlyContinue'


                    # I put this in a try/catch block so that we could capture and customize a warning message, instead of an error, and ensure execution continues
                    # otherwise you might get terminating errors if you encounter a guest that does not have a tag assignment
                    try {

                        $PrimaryOwnerName    = $null
                        $PrimaryOwnerEmail   = $null
                        $SecondaryOwnerName  = $null
                        $SecondaryOwnerEmail = $null

                        $PrimaryOwnerName    = $tagAssignment | Where-Object {$_.Category -like 'owner-primary-email'} | Select-Object -ExpandProperty Description -ErrorAction 'SilentlyContinue'
                        $PrimaryOwnerEmail   = $tagAssignment | Where-Object {$_.Category -like 'owner-primary-email'} | Select-Object -ExpandProperty Name -ErrorAction 'SilentlyContinue'
                        $SecondaryOwnerName  = $tagAssignment | Where-Object {$_.Category -like 'owner-secondary-email'} | Select-Object -ExpandProperty Description -ErrorAction 'SilentlyContinue'
                        $SecondaryOwnerEmail = $tagAssignment | Where-Object {$_.Category -like 'owner-secondary-email'} | Select-Object -ExpandProperty Name -ErrorAction 'SilentlyContinue'

                    } catch {

                        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][WARNING] $($guest.Name) May be missing assignments for Primary & Secondary Owner. $_"
                        continue

                    } # end try/catch



                    ### These are the properties that were assigned to the PSCustomObject

                    PrimaryOwnerName        = if($PrimaryOwnerName) {
                            $PrimaryOwnerName
                        } else {
                            $null
                        }
                        PrimaryOwnerEmail       = if($PrimaryOwnerEmail) {
                            $PrimaryOwnerEmail
                        } else {
                            $null
                        }
                        SecondaryOwnerName      = if($SecondaryOwnerName) {
                            $SecondaryOwnerName
                        } else {
                            $null
                        }
                        SecondaryOwnerEmail     = if($SecondaryOwnerEmail) {
                            $SecondaryOwnerEmail
                        } else {
                            $null
                        }

                    #>

                [PSCustomObject] @{
                    Name                    = $guestQuery.Name
                    HostName                = $guestQuery.Guest.HostName
                    OS                      = $guestQuery.Summary.Guest.GuestFullName
                    IPAddress               = $guestQuery.Summary.Guest.IPAddress
                    NumCPU                  = $guestQuery.Summary.Config.NumCPU
                    NumCPUCoresPerSocket    = $guestQuery.Config.Hardware.NumCoresPerSocket
                    MemorySizeGB            = ($guestQuery.Summary.Config.MemorySizeMB) / 1024
                    NumEthernetCards        = $guestQuery.Summary.Config.NumEthernetCards
                    NumVirtualDisks         = $guestQuery.Summary.Config.NumVirtualDisks
                    ProvisionedStorageGB    = [math]::Round(((((($guestQuery.Summary.Storage.Committed) + ($guestQuery.Summary.Storage.Uncommitted)) / 1024) / 1024) / 1024))
                    CommittedStorageGB      = [math]::Round((((($guestQuery.Summary.Storage.Committed) / 1024) / 1024) / 1024))
                    FTEnabled               = if ($guestQuery.Runtime.FaultToleranceState -eq 'running') {
                        [bool]$true
                    } else {
                        [bool]$false
                    }
                    CPUHotAddEnabled        = $guestQuery.Config.CPUHotAddEnabled
                    RAMHotAddEnabled        = $guestQuery.Config.MemoryHotAddEnabled
                    VMToolsInstallerMounted = $guestQuery.Summary.Runtime.ToolsInstallerMounted
                    ToolsVersion            = $guestQuery.Guest.ToolsVersion
                    ToolsStatus             = $guestQuery.Guest.ToolsStatus
                    ToolsVersionStatus      = $guestQuery.Guest.ToolsVersionStatus2
                    ToolsRunningStatus      = $guestQuery.Guest.ToolsRunningStatus
                    ToolsUpgradePolicy      = $guestQuery.Config.Tools.ToolsUpgradePolicy
                    Annotation              = $guestQuery.Summary.Config.Annotation
                    State                   = $guestQuery.Guest.GuestState
                    Status                  = $guestQuery.Summary.Runtime.PowerState
                    vCenterServer           = $guestvCenterServer
                    Cluster                 = (Get-VIObjectByVIView -Server $guestvCenterServer -MoRef (Get-VIObjectByVIView -Server $guestvCenterServer -MoRef $guestQuery.Runtime.Host).ExtensionData.Parent).Name
                    FolderPath              = (Get-VIVMFolderPath -VM $guest).FolderPath
                    #Region                  = $guestRegion
                    HardwareVersion         = $guestQuery.Config.Version
                    UUID                    = $guestQuery.Summary.Config.Uuid
                    InstanceUUID            = $guestQuery.Summary.Config.InstanceUUID
                    GuestID                 = $guestQuery.Summary.Config.GuestID
                    Generated               = $dateGenerated
                } # end [PSCustomObject]

            } # end foreach $guest

        } # end if/else

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete"

    } # end END block

} # end function Get-VMDetails

function Get-VIVMFolderPath {
    <#
        .SYNOPSIS
            Returns the entire folder path for a given VM
        .DESCRIPTION
            Returns the entire folder path for a given VM.

            VMs can be provided in two different types:
            'VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine' - Which is usually the result of running 'Get-VM'
            'VMware.Vim.VirtualMachine' - Which is usually the result of using 'Get-View' on a Virtual Machine object/s
        .PARAMETER VM
            VM Input
        .INPUTS
            VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine
            VMware.Vim.VirtualMachine
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        .EXAMPLE
            Get-VM -Name 'vm1','vm2' | Get-VMFolderPath
        .NOTES
            Author: Kevin Kirkpatrick
            Email:
            Last Updated: 20161207
            Last Updated By: K. Kirkpatrick
            Last Update Notes:
            - Updated type name for virtual machines to support PowerCLI 6.5
            - Only accepts input from Get-VM; supporting two input types was a little redundant
    #>

    [OutputType([System.Management.Automation.PSCustomObject])]
    [cmdletbinding(DefaultParameterSetName = 'default')]
    param (
        [parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0,
            ParameterSetName = 'default')]
        [alias('VM')]
        #[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]
        $Name
    )

    BEGIN {

    } # end BEGIN block

    PROCESS {

        foreach ($vmGuest in $Name) {

            $folder = $null
            $folderVcenter = $null

            Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Resolving folder for virtual machine { $($vmGuest.Name) }"

            # run a check on the type and assign the folder value. Doing thing so we can support different input types
            if (($vmGuest.GetType().FullName) -eq 'VMware.Vim.VirtualMachine') {

                $vmParent = $null
                $vmParent = $vmGuest.Parent

                $folderVcenter = ([uri]$vmGuest.Client.ServiceUrl).Host
                $folder        = Get-ViObjectByViView -Server $folderVcenter -MoRef $vmParent


            } else {

                $folder = $vmGuest.Folder
                $folderVcenter = ($vmGuest.uid.split('@')[1]).split(':')[0]

            } # end if/else

            if ($folder -eq '' -or $folder -eq $null) {

                [PSCustomObject] @{
                    VM            = $vmGuest.Name
                    FolderPath    = '\'
                    vCenterServer = $folderVcenter
                } # end [PSCustomObject]

            } else {

                $path = $folder.Name

                if ($folder.Name -eq 'vm') {

                    [PSCustomObject] @{
                        VM            = $vmGuest.Name
                        FolderPath    = '\'
                        vCenterServer = $folderVcenter
                    } # end [PSCustomObject]

                } else {

                    while ($folder.Parent.Name -ne 'vm') {

                        $folder = $folder.Parent
                        $path = $folder.Name + "\" + $path

                    } # end while

                    [PSCustomObject] @{
                        VM            = $vmGuest.Name
                        FolderPath    = "\$path"
                        vCenterServer = $folderVcenter
                    } # end [PSCustomObject]

                } # end if/else

            } # end if/else

        } # end foreach

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete"

    } # end END block

} # end function Get-VMFolderPath

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

function Get-VIVMGuestNetworkAdapter {

    <#
            .SYNOPSIS
                Returns VM Guest network adapter information, including detail about the virtual & IP interfaces
            .DESCRIPTION
                Returns VM Guest network adapter information, including detail about the virtual & IP interfaces.

                This function aims to combine information that would typically take combining the output from more than one command to achieve. I also wrote it with scale in mind, thus, I focused on
                gathering information from the vSphere API and not native properties found as part of other PowerCLI cmdlet output.

                Running this assumes that you:
                1. Have PowerCLI installed
                2. You are already connected to at least one (or more) ESXi Hosts or vCenter Servers
            .PARAMETER Name
                Virtual machine object
            .INPUTS
                VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine
            .OUTPUTS
                System.Management.Automation.PSCustomObject
            .EXAMPLE
                Get-VM | Get-VMGuestNetworkAdapter
            .EXAMPLE
                Get-VM | Get-VMGuestNetworkAdapter | Out-GridView
            .EXAMPLE
                Get-VMGuestNetworkAdapter -Name (Get-VM)
            .EXAMPLE
                Get-VMGuestNetworkAdapter -Name (Get-VM -Name SERVER1,SERVER2)
            .NOTES
                Author: Kevin Kirkpatrick
                Email:
                Last Updated: 20170323
                Last Updated By: K. Kirkpatrick
                Last Update Notes:
                - Fixed an issue which would return a VDS switch name for a VSS portgroup
                - Minor spacing and format cleanup
                - Added vCenterServer property
            #>

    [OutputType([System.Management.Automation.PSCustomObject])]
    [cmdletbinding(DefaultParameterSetName = 'defaut')]
    param (
        [parameter(
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'default')]
        [alias('VM')]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]
        $Name,

        [parameter(
            Mandatory = $false,
            Position = 1)]
        [alias('VIServer')]
        $Server
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

        # Leave this commented out; it will not process $guestNicAdapterQuery b/c 'Where-Object MacAddress' does not map to a property on the east side of the pipeline
        #Set-StrictMode -Version Latest

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Started"

        # query the API for network information; by default results are typically only dvPortGroups; store in mem for quick access, later on
        $dvPortGroupApi = Get-View -ViewType Network

        # query the API for all dvSwitches and store for later lookup
        $dvSwitchApi = $null
        $dvSwitchApi = Get-View -ViewType DistributedVirtualSwitch

    } # end BEGIN block

    PROCESS {

        foreach ($vcenter in $server) {

        foreach ($guest in $Name) {

            # access raw vSphere API
            $guestView = $null
            $guestView = $guest.ExtensionData

            # grab/parse the vCenter name to be used with future Get-View/API call filtering
            $guestClient = $null
            $guestClient = ([uri]$guestView.Client.ServiceUrl).Host

            # query hardware devices and then filter based on an object containing a 'MacAddress' property (which indicates that it's a network interface)
            $guestNicAdapterQuery = $null
            $guestNicAdapterQuery = $guestView.Config.Hardware.Device | Where-Object MacAddress

            foreach ($vNic in $guestNicAdapterQuery) {

                # use the mac address to compare/match so we can correlate/combine data from two separate APIs
                $ipInterface = $null
                $ipInterface = ($guestView.Guest.Net | Where-Object { $_.MacAddress -eq $vNic.MacAddress }).IpConfig

                # get the .NET type name of the vNIC backing object and resolve the type
                $portGroupType = $null
                $portGroupType = if (($vNic.backing).GetType().FullName -like '*distributed*') {

                    'Distributed'

                } elseif ($vNic.DeviceInfo.Summary -eq 'None') {

                    # adding this logical so that 'Standard' is not returned for an adapter that exists but it not assigned to anything
                    'NotAssigned'

                } elseif ($vNic.DeviceInfo.Summary -ne $null) {

                    'Standard'

                }# end if/elseif

                # resolve/query the portGroupName, depending on the portGroupType
                $portGroupName = $null
                switch ($portGroupType) {

                    'Standard' {

                        $portGroupName = $vNic.DeviceInfo.Summary
                        $dvSwitchName = $null

                    } # end 'Standard'

                    'NotAssigned' {

                        $portGroupName = $vNic.DeviceInfo.Summary
                        $dvSwitchName = $null

                    } # end 'Standard'

                    'Distributed' {

                        # grab the dvPortGroup Key to use as a filter, below
                        $dvPortGroupKey = $null
                        $dvPortGroupKey = $vNic.Backing.Port.PortGroupKey

                        # select the proper dvPortGroup, based on a lookup of the dvPortGroup, based on the 'Key' value, and then return the 'friendly' Name
                        $portGroupName = ($dvPortGroupApi | Where-Object { $_.Key -eq $dvPortGroupKey }).Name

                        <# look up the dvSwitch Name by using the same filtering used to resolve the dvPortGroup Name;
                                   then, unroll the MoRef key value for the dvSwitch associated with the dvPortGroup;
                                   then, cross-reference that, with the stored dictionary of dvSwitch information to resolve the name #>
                        $dvSwitchName = $null
                        $dvSwitchName = ($dvPortGroupApi | Where-Object { $_.Key -eq $dvPortGroupKey }).Config.DistributedVirtualSwitch.Value
                        # just re-use/overwrite the variable with new information
                        $dvSwitchName = ($dvSwitchApi | Where-Object {$_.MoRef.Value -eq $dvSwitchName}).Name

                    } # end 'Distributed'

                } # end switch

                [PSCustomObject] @{
                    Name              = $guestView.Name
                    AdapterType       = $vNic.GetType().FullName.SubString(18).ToLower()
                    Label             = $vNic.DeviceInfo.Label
                    MacAddress        = $vNic.MacAddress
                    MacAddressType    = $vNic.AddressType
                    PortGroupName     = $portGroupName
                    PortGroupType     = $portGroupType
                    DVSwitchName      = $dvSwitchName
                    IPAddress         = $ipInterface.IpAddress.IpAddress -join '|'
                    PrefixLength      = $ipInterface.IpAddress.PrefixLength -join '|'
                    DHCP              = $ipInterface.Dhcp.Ipv4.Enable -join '|'
                    Connected         = $vNic.Connectable.Connected
                    StartConnected    = $vNic.Connectable.StartConnected
                    AllowGuestControl = $vNic.Connectable.AllowGuestControl
                    Shares            = $vNic.ResourceAllocation.Share.Shares
                    ShareLevel        = $vNic.ResourceAllocation.Share.Level
                    Status            = $vNic.Connectable.Status
                    vCenterServer     = $guestClient
                } # end obj

            } # end foreach $vNic

        } # end foreach $guest

        } # end foreach $vcenter

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete"

    } # end END block

} # end function Get-VMGuestNetworkAdapter

function Get-VIvSphereLicense {

    <#
        .SYNOPSIS
            Return vSphere license deatils from the connected vCenter Server(s)
        .DESCRIPTION
            Return vSphere license deatils from the connected vCenter Server(s).

            There is currently no option to specify an individual vCenter Server or ESXi host, the command will attempt run against any connected vCenter or ESXi host.
        .EXAMPLE
            Get-vSphereLicense -Verbose

            This assumes that you already have a connection to one or more vCenter Servers and/or ESXi Hosts, before running the command.
        .EXAMPLE
            Connect-VIServer -Server 'vcenter1.corp.com' -Credential (Get-Credential)
            Get-vSphereLicense -Verbose

            This shows the connection to a vCenter Server and subsequently running the command.
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        .NOTES

        --------------------------------
        Author: Kevin Kirkpatrick
        Email:
        Last Updated: 20171006
        Last Updated By: K. Kirkpatrick
        Last Update Notes:
        - Added to module

        #>


    [cmdletbinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param (
        [parameter(Position = 0, Mandatory = $false)]
        [System.String[]]
        $Server
    )

    BEGIN {
        #Requires -Version 3

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Started"

        if (-not $Server) {
            Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] No default value was passed to the '-Server' parameter. Attempting to use all connected endpoints."
            $Server = ((Get-Variable -Scope Global -Name defaultViServers -ErrorAction 'Stop').Value).Name
        }

    } # end BEGIN block

    PROCESS {

        foreach ($endpoint in $server) {

            Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Working on Server { $endpoint }"

            try {

                Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Gathering vSphere license details"

                $ServiceInstance = $null
                $ServiceInstance = Get-View ServiceInstance -Server $endpoint

                $endpointInfo = $null
                $endpointInfo = $ServiceInstance.Content.About

                Foreach ($licenseMan in Get-View ($ServiceInstance | Select-Object -First 1).Content.LicenseManager) {

                    $licencedEditionUri = $null
                    $licencedEditionUri = $licenseMan.LicensedEdition

                    Foreach ($license in $LicenseMan.Licenses) {

                        [PSCustomObject]@{
                            Endpoint               = ([Uri]$LicenseMan.Client.ServiceUrl).Host
                            EndpointType           = $endpointInfo.FullName
                            Name                   = $License.Name
                            ProductVersion         = ($License.Properties | Where-Object { $_.key -eq "ProductVersion" }).Value
                            Key                    = $License.LicenseKey
                            CostUnit               = $License.CostUnit
                            Total                  = $License.Total
                            Used                   = $License.Used
                            LicensedEditionUriHost = ([uri]$licencedEditionUri).Host
                            #Information    = $License.Labels.Value
                            #ExpirationDate = ($License.Properties | Where-Object { $_.key -eq "expirationDate" }).Value
                        } # end obj

                    } # end foreach $license

                } # end foreach $licenseMan

            } catch {

                Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] $_"

            } # end try/catch

        } # end foreach $endpoint

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete"

    } # end END block

} # end Get-vSphereLicense

function Get-VIVcenterComponents {

    <#
        .SYNOPSIS
            Returns summary details about vCenter components, such as the Inventory Service, SSO & Lookup Service.
        .DESCRIPTION
           Returns summary details about vCenter components, such as the Inventory Service, SSO & Lookup Service

        .PARAMETER Server
            vCenter server FQDN
        .INPUTS
            System.String
        .OUTPUTS
            System.Management.Automation.PSCustomObject
        .EXAMPLE
            Get-VIVcenterComponents -Server 'vcenter01.domain.corp' -Verbose
        .EXAMPLE
            Get-VIVcenterComponents -Server 'vcenter01.domain.corp' -Verbose | Format-Table -AutoSize
        .NOTES
            Author: Kevin Kirkpatrick
            Email:
            Last Updated: 20180525
            Last Update By: K. Kirkpatrick
            Last Update Notes:
            - Created
        #>

    [OutputType([System.Management.Automation.PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'default')]
    param (
        [parameter(
            Mandatory = $false,
            Position = 0)]
        [alias('VIServer')]
        $Server
    )

    BEGIN {

        #Requires -Version 3

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Started."

        $Server = $global:defaultviservers

    } # end BEGIN block

    PROCESS {

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

                    $settingView        = $null
                    $uniqueId           = $null
                    $endpointType       = $null
                    $SsoAdminUri        = $null
                    $SsoStsUri          = $null
                    $SsoGroupcheckUri   = $null
                    $SsoLookupServiceId = $null

                    #$vcAdvancedSettings = Get-VIServer $vcenter.Name -ErrorAction Stop
                    $SsoAdminUri        = Get-AdvancedSetting -Entity $vcenter -Name 'config.vpxd.sso.admin.uri' -ErrorAction SilentlyContinue
                    $SsoStsUri          = Get-AdvancedSetting -Entity $vcenter -Name 'config.vpxd.sso.sts.uri' -ErrorAction SilentlyContinue
                    $SsoGroupcheckUri   = Get-AdvancedSetting -Entity $vcenter -Name 'config.vpxd.sso.groupcheck.uri' -ErrorAction SilentlyContinue
                    $SsoLookupServiceId = Get-AdvancedSetting -Entity $vcenter -Name 'config.vpxd.sso.lookupService.serviceId' -ErrorAction SilentlyContinue

                    $settingView = Get-View -Server $vcenter.Name $siView.Content.Setting -ErrorAction 'Stop'
                    $uniqueId    = ($settingView.QueryOptions("instance.id")).Value

                    [PSCustomObject] @{
                        vCenter              = $vcenter.Name
                        vCenterServerVersion = $vcenter.Version
                        vCenterID            = $uniqueId
                        SsoAdminUri          = $SsoAdminUri.Value
                        SsoStsUri            = $SsoStsUri.Value
                        SsoGroupcheckUri     = $SsoGroupcheckUri.Value
                        SsoLookupServiceId   = $SsoLookupServiceId.Value
                        DateGenerated        = $dateGenerated
                    } # end obj

                } # end if/else

            } catch {

                throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][$($vcenter.Name)][ERROR] Failed to gather vCenter Summary Detail. $_"
                continue

            } # end try/catch

        } # end foreach $vcenter

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete."

    } # end END block

} # end function Get-VIVcenterComponents