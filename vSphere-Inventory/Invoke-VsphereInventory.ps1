<#
.EXAMPLE
    .\Invoke-VsphereInventory.ps1 -Verbose

    You will need to connect to one, or more, vCenter Servers before running the inventory.

    Example:
    C:\PS>Import-Module VMware.PowerCLI
    C:\PS>Connect-ViServer -Server 'vcenter01.corp.com' -Credential (Get-Credential)
    C:\PS>Connect-ViServer -Server 'vcenter02.corp.com' -Credential (Get-Credential)
    C:\PS>C:\vSphere-Inventory\Invoke-Inventory.ps1 -Verbose
.NOTES
    Author: Kevin M. Kirkpatrick
    Email:
    Last Update: 20171018
    Last Updated by: K. Kirkpatrick
    Last Update Notes:
    - Created
#>

[CmdletBinding(DefaultParameterSetName = 'default',
                SupportsShouldProcess  = $true,
                PositionalBinding      = $false)]

param (
    # Module file path
    [Parameter(Mandatory         = $false,
                Position         = 0,
                ParameterSetName = 'default')]
    [System.String]
    $FunctionsPath = "$PSScriptRoot\Functions"
)

BEGIN {

    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Started "

    $Functions = @( Get-ChildItem -Path $FunctionsPath\*.ps1 -ErrorAction SilentlyContinue )

    foreach ($import in @($Functions)) {

        try {
            # dot-source all functions

            . $import.FullName

        } catch {

            throw "Could not load function { $($import.Name) }. $_"
            break

        } # end t/c

    } # end foreach

    if (Test-Path -Path Variable:\Global:defaultViServers) {

        $serverList = $null
        $serverList = $Global:defaultViServers

        if ($serverList -eq $null -or $serverList -eq '') {

            throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] No current connection to a vCenter Server could be found"

        } else {

            Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing connected vCenter servers discovered in variable { `$Global:DefaultViServers }"

        } # end else/if

    } else {

        throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] No current connection to a vCenter Server could be found; variable { `$Global:DefaultViServers } does not exist, " +
        "which typically indicates that PowerCLI has not been loaded."

    } # end if/else Test-Path

    try {

        $outputDirectory = $null
        $outputDirectory = "$PSScriptRoot\$(Get-VITimeStamp)"

        [void](New-Item -Path "$PSScriptRoot\$(Get-VITimeStamp)" -ItemType Directory -ErrorAction Stop)

    } catch {

        throw "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not create output directory { $outputDirectory }. $_"

    } # end try/catch

} # BEGIN block

PROCESS {

# vCenter Summary Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating vCenter Summary Report"
    try {

        Get-VIvCenterSummary -SummaryType vCenter -ErrorAction Stop | Export-Csv -Path "$outputDirectory\vCenter-Summary-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the vCenter Summary Report. $_"

    } # end try/catch


# Cluster Summary Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating Cluster Summary Report"
    try {

        Get-VIvCenterSummary -SummaryType Cluster -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\Cluster-Summary-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the Cluster Summary Report. $_"

    } # end try/catch


# VM Inventory Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating VM Inventory Report"
    try {

        Get-VIVMDetails -Inventory -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\VM-Inventory-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the VM Inventory Report. $_"

    } # end try/catch


# VM Mapping Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating VM Mapping Report"
    try {

        Get-VIVMMapping -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\VM-Mapping-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] VM Mapping Report. $_"

    } # end try/catch


# VM Network Adapter Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating VM Network Adapter Report"
    try {

        Get-VM -ErrorAction Stop |
        Get-VIVMGuestNetworkAdapter -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\VM-Network-Adapter-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the VM Network Adapter Report. $_"

    } # end try/catch


# VMHost Mapping Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating VMHost Mapping Report"
    try {

        Get-VIVMHostMapping -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\VMHost-Mapping-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the VMHost Mapping Report. $_"

    } # end try/catch


# VMHost Network Configuration Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating VMHost Network Configuration Report"
    try {

        Get-VMHost -ErrorAction Stop |
        Get-VIVMHostNetworkConfiguration -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\VMHost-Network-Config-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the VMHost Network Configuration Report. $_"

    } # end try/catch


# vCenter License Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating vCenter License Report"
    try {

        Get-VIvSphereLicense -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\vCenter-License-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the vCenter License Report. $_"

    } # end try/catch


# vCenter Componenets Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating vCenter Componenets Report"
    try {

        Get-VIVcenterComponents -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\vCenter-Component-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the vCenter Componenets Report. $_"

    } # end try/catch


} # PROCESS block

END {

    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Processing Complete "

} # END block
