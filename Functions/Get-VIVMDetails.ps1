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

