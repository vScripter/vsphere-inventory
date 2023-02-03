<#
.SYNOPSIS
    Perform vSphere discovery and generate multiple reports from a single script.
.DESCRIPTION
    Perform vSphere discovery and generate multiple reports from a single script.

    There are 9 reports that get generated from this discovery/inventory script:
    Cluster Summary Report
    vCenter Component Report
    vCenter License Report
    vCenter Summary Report
    VM Inventory Report
    VM Mapping Report
    VM Network Adapter Report
    VMHost Mapping Report
    VMHost Network Configuration Report
    VMHost Services Report

    Please see the README for more information about what data is part of these reports.

    Each report is meant to be self contained, in that, relevent information to maintain context is included in each report so that a single report could be shared without the need of any other report.

.PARAMETER ProjectName
    Optional name of project which will be prepended to the name of the report folder. This can be an actual project, customer, environment, etc.
.INPUTS
    System.String
.OUTPUTS
    System.Management.Automation.PSCustomObject
.EXAMPLE
    .\Invoke-VsphereInventory.ps1 -Verbose

    You will need to connect to one, or more, vCenter Servers before running the inventory.

    Example:
    C:\PS>Import-Module VMware.PowerCLI
    C:\PS>Connect-ViServer -Server 'vcenter01.corp.com' -Credential (Get-Credential)
    C:\PS>Connect-ViServer -Server 'vcenter02.corp.com' -Credential (Get-Credential)
    C:\vSphere-Inventory\ .\Invoke-Inventory.ps1 -Verbose
.EXAMPLE
    .\Invoke-VsphereInventory.ps1 -ProjectName Dev -Verbose

.NOTES
    Author: Kevin M. Kirkpatrick
    Email:
    Last Update: 20230202
    Last Updated by: K. Kirkpatrick
    Last Update Notes:
    - Added VMHost Services Report
    - Added ProjectName parameter
#>

[CmdletBinding(DefaultParameterSetName = 'default',
    SupportsShouldProcess = $true,
    PositionalBinding     = $false)]

param (
    # Module file path
    [Parameter(Mandatory = $false,
        Position         = 0,
        ParameterSetName = 'default')]
    [System.String]
    $FunctionsPath = "$PSScriptRoot\Functions",

    [Parameter(Mandatory = $false,
        Position         = 1,
        ParameterSetName = 'default')]
    [System.String]
    $ProjectName

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

        if ($ProjectName) {

            $outputDirectory = "$PSScriptRoot\$($ProjectName)_$(Get-VITimeStamp)"

        } else {

            $outputDirectory = "$PSScriptRoot\$(Get-VITimeStamp)"

        } # end if/else $ProjectName

        [void](New-Item -Path $outputDirectory -ItemType Directory -ErrorAction Stop)

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


    # VMHost Services Report
    Write-Verbose -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)] Generating VMHost Services Report"
    try {

        Get-VIVMHostServices -ErrorAction Stop |
        Export-Csv -Path "$outputDirectory\VMHost-Services-Report.csv" -NoTypeInformation -Force -ErrorAction Stop

    } catch {

        Write-Warning -Message "[$($PSCmdlet.MyInvocation.MyCommand.Name)][ERROR] Could not generate the VMHost Services Report. $_"

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
