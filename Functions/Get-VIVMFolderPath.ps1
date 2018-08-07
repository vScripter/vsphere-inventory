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

