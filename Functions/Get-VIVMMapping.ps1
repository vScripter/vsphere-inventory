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

