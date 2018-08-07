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

