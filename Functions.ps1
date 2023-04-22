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
    $resultAgents=Invoke-command -Session $session -ScriptBlock{
    $programs = Get-cimInstance -Classname Win32_Product | Select Name, Version
    $programs}
    $resultAgents|select Name, Version
}

#function to get Services
function getServices {
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
       [object]$fragment
    )
    $html=@"
    <!DOCTYPE html>
    <html>
    <head>
    <title>$test - $computername</title>
    <style>
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
    </style>
    </head>
    <body>
    <p>Report last ran at $(get-date) </p>
    $fragment
    </body>
    </html>
"@
    [System.Net.WebUtility]::HtmlDecode($HTML)

}



#main function
function All-ServerCheck{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$computerName
        )
    $global:computername=$computername
    $global:SourceFolder="$($pwd.Path)\References\"
    $global:OutputFolder="$($pwd.Path)\Output\"
    $global:Session=new-pssession -ComputerName $computername

    <#
    $global:csvColumns="Result","Status"
    $global:HTMLColumns="Result","HTML_Status","HTML_Verbose"
    $global:agentsColumns="Name","Version"
    $global:ServicesColumns="Name","StartType"
    $global:RolesColumns="Name","Installed"
    $global:RegistryColumns="Path","Key","Value"
    #>

    $global:Agents=GetAgents
    $global:RefAgents=Import-csv "$SourceFolder\Agents.csv"
    $agentsResult=result-object -reference $RefAgents -result $Agents -columns Name,Version|Sort-Object Name
    $agentsResult|select Name,Version,Result,status,verbose|export-csv -NoTypeInformation "$outputFolder\Agents.csv"
    $AgentsFragment = $AgentsResult|select Name,Version,Result,HTML_Status,HTML_Verbose|convertto-HTML -fragment
    HTMLMaker $AgentsFragment |out-file "$outputfolder\Agents.html"


    $global:Services=getServices
    $global:RefServices=Import-csv "$SourceFolder\Services.csv"
    $ServicesResult=result-object -reference $RefServices -result $services -columns Name,StartType|Sort-Object Name
    $ServicesResult|select Name,StartType,Result,status,verbose|export-csv -NoTypeInformation "$outputFolder\Services.csv"
    $ServicesFragment = $ServicesResult|select Name,StartType,Result,HTML_Status,HTML_Verbose|convertto-HTML -fragment
    HTMLMaker $ServicesFragment  |out-file "$outputfolder\Services.html"

    
    $global:Roles=getRoles
    $global:RefRoles=Import-csv "$SourceFolder\Roles.csv"
    $RolesResult=result-object -reference $RefRoles -result $roles -columns Name,Installed|Sort-Object Name
    $RolesResult|select Name,Installed,Result,status,verbose|export-csv -NoTypeInformation "$outputFolder\Roles.csv"
    $RolesFragment = $RolesResult|select Name,Installed,Result,HTML_Status,HTML_Verbose|convertto-HTML -fragment
    HTMLMaker $RolesFragment |out-file "$outputfolder\Roles.html"
    
    $global:Registry=getRegistry
    $global:RefRegistry=Import-csv "$SourceFolder\Registry.csv"
    $RegistryResult=result-object -reference $RefRegistry -result $Registry -columns Key,value|Sort-Object Path,Key
    $RegistryResult|select Path,Key, Value,Result,status,verbose|export-csv -NoTypeInformation "$outputFolder\Registry.csv"
    $registryFragment = $RegistryResult|select Path,Key,Value,Result,HTML_Status,HTML_Verbose|convertto-HTML -fragment
    HTMLMaker $RegistryFragment |out-file "$outputfolder\Registry.html"
    
    <#
    $agentsFragment=$agentsresult|convertto-html -Fragment
    $ServicesFragment=$Servicesresult|convertto-html -Fragment
    $RolesFragment=$Rolesresult|convertto-html -Fragment
    $RegistryFragment=$Registryresult|convertto-html -Fragment
    #>
}
