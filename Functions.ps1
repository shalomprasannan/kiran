function GetRemoteRegistry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RegistryPath,
        [Parameter(Mandatory=$true)]
        [string]$KeyName
    )
    $keyValue = Invoke-Command -Session $Session -ScriptBlock {
        param($path, $key)
        Get-ItemProperty -Path $path -Name $key | Select-Object -ExpandProperty $key
    } -ArgumentList $RegistryPath, $KeyName
    [PSCustomObject]@{
        RegistryPath = $RegistryPath
        KeyName = $KeyName
        Value = $keyValue
    }
}

#function to get result Registry object
function GetRegistry {
    write-host "Fetching Registries..."
    $folder=".\references\"
    $reference=import-csv "$folder\registry.csv"
    $resultregistry=@()
    foreach($registry in $reference){
        $resultregistry+=GetRemoteRegistry -RegistryPath $Registry.path -KeyName $Registry.key
    }

    $resultregistry
}

#function to get installed Agents
function GetAgents {
    write-host "Fetching Installed Agents..."
    $resultAgents=Invoke-command -Session $session -ScriptBlock{
    $programs = Get-cimInstance -Classname Win32_Product | Select Name, Version
    $programs}
    $resultAgents|select Name, Version
}

#function to get Services
function getServices {
    write-host "Fetching Installed Services..."
    $services=Invoke-command -Session $session -ScriptBlock{
        Get-Service | Select Name, @{Name='StartType';Expression={
        switch ($_.StartType) {'Automatic' { 'Automatic' }
                            'Disabled' { 'Disabled' }
                            'Manual' { 'Manual' }}}}
    }
    $services|select Name, StartType
}

#function to get Roles
function getRoles{
    write-host "Fetching Installed Roles..."
    $roles=Invoke-command -Session $session -ScriptBlock{
        Get-WindowsFeature | Select Name,Installed 
    }
    $roles|select Name,Installed
}


function Result-object{
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$Reference,
        [Parameter(Mandatory=$true)]
        [object[]]$result,
        [Parameter(Mandatory=$true)]
        [string[]]$columns
    )
    write-host "Comparing Reference $test with fetched $test"
    $Compared = Compare-Object $reference $result -Property $columns -IncludeEqual
    $compared = $compared|where {$_.sideindicator -ne "=>"}
    foreach($compObj in $compared){
        $resObj = $result | where { $_.($columns[0]) -eq $compObj.($columns[0]) }

        if($compObj.sideindicator -eq "=="){
            $compObj | Add-Member -MemberType NoteProperty -Name "Status" -Value "Passed"
            $compObj | Add-Member -MemberType NoteProperty -Name "HTML_Status" -Value "<span style=`"color:Green;`">Passed</span>"
        }
        else{
            $compObj | Add-Member -MemberType NoteProperty -Name "Status" -Value "Failed"
            $compObj | Add-Member -MemberType NoteProperty -Name "HTML_Status" -Value "<span style=`"color:Tomato;`">Failed</span>"
            if($($resObj.($columns[1]))){
                $compObj | Add-Member -MemberType NoteProperty -Name "Verbose" -Value "$($columns[1]) : expected $($compObj.($columns[1])) got $($resObj.($columns[1]))"
                $compObj | Add-Member -MemberType NoteProperty -Name "HTML_Verbose" -Value "$($columns[1]) : expected <b>$($compObj.($columns[1]))</b> got <b>$($resObj.($columns[1]))</b>"
            }else{
                $compObj | Add-Member -MemberType NoteProperty -Name "Verbose" -Value "$($columns[0]) : Doesn't exists"
                $compObj | Add-Member -MemberType NoteProperty -Name "HTML_Verbose" -Value "$($columns[0]) : <b>Doesn't exists</b>"
            }
        }
        $compObj | Add-Member -MemberType NoteProperty -Name "Result" -Value "$($resObj.($columns[1]))"
        $compObj | Add-Member -MemberType NoteProperty -Name "ComputerName" -Value "$computerName"
    }
    $compared
}

function HTMLMaker{
    param(
       [Parameter(Mandatory=$true)]
       [object]$object,
       [Parameter(Mandatory=$true)]
       [object]$columns,
       [Parameter(Mandatory=$true)]
       [object]$test
    )
    write-host "Exporting $test HTML`n"

    #aggregating the status
    $counts=$object|group-object status
    $passed=$counts[0].count
    $failed=$counts[1].count
    $total=$passed+$failed

    $fragment = $object|select $($columns+$HTMLColumns)|convertto-HTML -fragment
    $html=@"
    <!DOCTYPE html>
    <html>
    <head>
    <title>$test - $computername</title>
    <style>
    body {
			margin: 0;
			padding: 0;
			background-color: #f5f5f5;
		}

    table {
      font-family: Arial, Helvetica, sans-serif;
      border-collapse: collapse;
      width: 100%;
    }

    p {text-align: center;}
    
    td, th {
      border: 1px solid #ddd;
      padding: 8px;
    }
    
    tr:nth-child(even){background-color: #f2f2f2;}
    
    tr:hover {background-color: #ddd;}
    
    th {
      padding-top: 12px;
      padding-bottom: 12px;
      text-align: left;
      background-color: #04AA6D;
      color: white;
    }

    .status-bar {
			position: fixed;
			bottom: 0;
			left: 0;
			width: 100%;
			height: 40px;
			background-color: #333;
			color: #888;
			display: flex;
			justify-content: space-around;
			align-items: center;
			font-size: 14px;
			font-weight: bold;
			letter-spacing: 1px;
		}
    .white{
        color:white;
    }

    </style>
    </head>
        <body>
        $fragment
            <div class="status-bar">
                <div>
		            <p>Report last ran at <span class="white">$(get-date -Format "dd-mm-yyyy HH:mm")</span></p>
                </div>
                <div>
                    <p><span class="white">$failed </span> failed out of <span class="white"> $total</span></p>
                </div>
	        </div>
        </body>
    </html>
"@
    [System.Net.WebUtility]::HtmlDecode($HTML)

}



#main function
function All-ServerCheck{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$computerName,
        [Parameter(Mandatory=$true)]
        [string[]]$os,
        [Parameter(Mandatory=$true)]
        [string[]]$env,
        [Parameter(Mandatory=$true)]
        [string[]]$tests
        )
    $global:computername=$computername
    $global:SourceFolder="$($pwd.Path)\References\"#$os\$env"

    $global:OutputFolder="$($pwd.Path)\Output\$computername\"
    if (-not (test-path $outputfolder)){
        New-Item -ItemType Directory -Path $outputfolder
    }
    $global:Session=new-pssession -ComputerName $computername

    
    $global:csvColumns="Result","Status"
    $global:HTMLColumns="Result",@{Name='Status';Expression={$_.HTML_Status}},@{Name='Verbose';Expression={$_.HTML_Verbose}}
    $global:agentsColumns="Name","Version"
    $global:ServicesColumns="Name","StartType"
    $global:RolesColumns="Name","Installed"
    $global:RegistryColumns="Path","Key","Value"


    $agentsTest={
    $global:Agents=GetAgents
    $global:RefAgents=Import-csv "$SourceFolder\Agents.csv"
    $agentsResult=result-object -reference $RefAgents -result $Agents -columns Name,Version|Sort-Object Name
    $agentsResult|select @($AgentsColumns + $csvColumns)|export-csv -NoTypeInformation "$outputFolder\Agents.csv"
    HTMLMaker $AgentsResult $AgentsColumns $test |out-file "$outputfolder\Agents.html"
    }

    $ServicesTest={
    $global:Services=getServices
    $global:RefServices=Import-csv "$SourceFolder\Services.csv"
    $ServicesResult=result-object -reference $RefServices -result $services -columns Name,StartType|Sort-Object Name
    $ServicesResult|select @($ServicesColumns + $csvColumns)|export-csv -NoTypeInformation "$outputFolder\Services.csv"
    HTMLMaker $ServicesResult $ServicesColumns $test  |out-file "$outputfolder\Services.html"
    }
    
    $RolesTest={
    $global:Roles=getRoles
    $global:RefRoles=Import-csv "$SourceFolder\Roles.csv"
    $RolesResult=result-object -reference $RefRoles -result $roles -columns Name,Installed|Sort-Object Name
    $RolesResult|select @($RolesColumns + $csvColumns)|export-csv -NoTypeInformation "$outputFolder\Roles.csv"
    HTMLMaker $RolesResult $RolesColumns $test |out-file "$outputfolder\Roles.html"
    }

    $RegistryTest={
    $global:Registry=getRegistry
    $global:RefRegistry=Import-csv "$SourceFolder\Registry.csv"
    $RegistryResult=result-object -reference $RefRegistry -result $Registry -columns Key,value|Sort-Object Path,Key
    $RegistryResult|select @($RegistryColumns + $csvColumns)|export-csv -NoTypeInformation "$outputFolder\Registry.csv"
    HTMLMaker $RegistryResult $registryColumns $test |out-file "$outputfolder\Registry.html"
    }

    if($tests -eq "All"){
    $tests=@("Agents","Services","Roles","Registry")
    }

    foreach($test in $tests){
        switch ($test) {
            'Agents'   { &$agentsTest }
            'Services' { &$servicesTest }
            'Roles'    { &$rolesTest }
            'Registry' { &$registryTest }
            Default    { Write-Host "Invalid test name" }
        }
    }
}
