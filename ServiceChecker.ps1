function ServiceCheck {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )

    #reference CSV file
    $reference = Import-Csv .\References\services.csv

    # Get the columns from the reference CSV file
    $columns = $reference[0].PSObject.Properties.Name

    # Get the services from the remote computer
    $services = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $services=Get-Service | Select-Object $columns
    }

    # Compare the reference and services
    $result = Compare-Object $reference $services -Property $columns

    # Generate the output objects
    $differences = $result | Where-Object { $_.SideIndicator -eq "<=" }
    $output = foreach ($diff in $differences) {
        $referenceObj = $reference | Where-Object { $_.Name -eq $diff.Name }
        $servicesObj = $services | Where-Object { $_.Name -eq $diff.Name }
        if ($servicesobj) {
            $changedProperty = foreach ($prop in $referenceObj.psobject.properties.name) {
                if ($referenceObj.$prop -ne $servicesObj.$prop) {
                    $prop
                }
            }
        } else {
            $changedProperty = "Name"
        }

        # Add the columns from the reference CSV file to the output object
        $props = @{}
        foreach ($column in $columns) {
            $props[$column] = $diff.$column
        }
        $props.ChangedProperty = $changedProperty
        [PSCustomObject]$props
    }

    $output|select Name, startType, DisplayName, ChangedProperty
}
