function Get-VIVMHostServices {

    <#
    .SYNOPSIS
        Return service and configuration information from the provided ESXi Host Systems
    .DESCRIPTION
        Return service and configuration information from the provided ESXi Host Systems for various critical services such as NTP and Syslog.

        This function accepts pipeline input from the 'Get-VMHost' cmdlet, which is part of PowerCLI.

        Queries against host system IP addresses will not work.

        This function also already assumes that you are connected to one or most ESXi Hosts or vCenter Servers. If connected to multiple hosts/vCenters, filter
        what you wish to run the function against, using 'Get-VMHost'.
    .PARAMETER VMHost
        VMHost system/s you wish to run the command against
    .INPUTS
        VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .EXAMPLE
        Get-VMHost | Get-VIVMHostServices -Verbose
    .EXAMPLE
        Get-Get-VIVMHostServices -VMHost (Get-VMHost) -Verbose
    .NOTES
        Author: Kevin Kirkpatrick
        Last Updated: 20230202
        Last Updated By: K. Kirkpatrick
        Last Update Notes:
        - Created
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

        $VMHost = Get-VMHost -Server $viServerList

        foreach ($esx in $VMHost) {

            try {

                Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Gathering service configuration data from host {$($esx.Name)}"

                $esxApi      = $null
                $esxHostName = $null
                $ntpConfig   = $null
                $ntpSvc      = $null

                $esxApi         = $esx.ExtensionData
                $esxHostName    = $esxApi.Name
                $ntpConfig      = ($esxApi.Config.DateTimeInfo.NtpConfig.Server) -Join '|'
                $ntpSvc         = $esxApi.Config.Service.Service | Where-Object { $_.Key -eq 'ntpd' }
                $syslogSvc      = $esxApi.Config.Service.Service | Where-Object { $_.Key -eq 'vmsyslogd' }

                [PSCustomObject] @{
                    VMHost                = $esxHostName
                    NTPServiceRunning     = $ntpSvc.Running
                    NTPPolicy             = $ntpSvc.Policy
                    NTPServers            = $ntpConfig
                    NTPTimeZone           = $esxApi.Config.DateTimeInfo.TimeZone.Name
                    SyslogServiceRunning  = $syslogSvc.Running
                    SyslogLogHosts        = ($esxApi.Config.Option | Where-Object { $_.Key -eq 'Syslog.global.logHost' }).Value -join '|'

                } # end [PSCustomObject]


            } catch {

                Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not process {$($esx.Nam)}. $_ "

            } # end try/catch

        } # end foreach $system

    } # end PROCESS block

    END {

        Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete"

    } # end END block

} # end function Get-VMHostNtpStatus
