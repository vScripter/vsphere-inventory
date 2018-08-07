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

