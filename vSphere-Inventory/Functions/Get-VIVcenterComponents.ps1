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