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
