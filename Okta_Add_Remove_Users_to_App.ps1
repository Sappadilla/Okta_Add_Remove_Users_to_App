Import-Module ActiveDirectory
$config = Get-Content "$PSScriptRoot\Okta_API_Config.ini"

$environment = "Prod"
#$environment = "QA"
#$environment = "Dev"

If($environment -eq "Prod"){
    $headers = @{}
    $baseUrl = $config[1].Substring($config[1].IndexOf("=")+2)
    $userAgent = ""
    $token = $config[2].Substring($config[2].IndexOf("=")+2)
}
Elseif($environment -eq "QA"){
    $headers = @{}
    $baseUrl = $config[5].Substring($config[5].IndexOf("=")+2)
    $userAgent = ""
    $token = $config[6].Substring($config[6].IndexOf("=")+2)
}
Elseif($environment -eq "Dev"){
    $headers = @{}
    $baseUrl = $config[9].Substring($config[9].IndexOf("=")+2)
    $userAgent = ""
    $token = $config[10].Substring($config[10].IndexOf("=")+2)
}


#region Okta API Functions

#credit to https://github.com/mbegan/Okta-PSModule
#downloaded from https://github.com/gabrielsroka/OktaAPI.psm1

#region Core functions

# Call Connect-Okta before calling Okta API functions.
function Connect-Okta($token, $baseUrl) {
    $script:headers = @{"Authorization" = "SSWS $token"; "Accept" = "application/json"; "Content-Type" = "application/json"}
    $script:baseUrl = $baseUrl

    #$module = Get-Module OktaAPI
    $modVer = '1.0.16' #$module.Version.ToString()
    $psVer = $PSVersionTable.PSVersion

    $osDesc = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    $osVer = [Environment]::OSVersion.Version.ToString()
    if ($osDesc -match "Windows") {
        $os = "Windows"
    } elseif ($osDesc -match "Linux") {
        $os = "Linux"
    } else { # "Darwin" ?
        $os = "MacOS"
    }

    $script:userAgent = "okta-api-powershell/$modVer powershell/$psVer $os/$osVer"
    # $script:userAgent = "OktaAPIWindowsPowerShell/0.1" # Old user agent.
    # default: "Mozilla/5.0 (Windows NT; Windows NT 6.3; en-US) WindowsPowerShell/5.1.14409.1012"

    # see https://www.codyhosterman.com/2016/06/force-the-invoke-restmethod-powershell-cmdlet-to-use-tls-1-2/
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Invoke-Method($method, $path, $body) {
    $url = $baseUrl + $path
    $url
    if ($body) {
        $jsonBody = $body | ConvertTo-Json -compress -depth 100 # max depth is 100. pipe works better than InputObject
        # from https://stackoverflow.com/questions/15290185/invoke-webrequest-issue-with-special-characters-in-json
        # $jsonBody = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    }
    Invoke-RestMethod $url -Method $method -Headers $headers -Body $jsonBody -UserAgent $userAgent
}

function Invoke-PagedMethod($url, $convert = $true) {
    if ($url -notMatch '^http') {$url = $baseUrl + $url}
    $response = Invoke-WebRequest $url -Method GET -Headers $headers -UserAgent $userAgent
    $links = @{}
    if ($response.Headers.Link) { # Some searches (eg List Users with Search) do not support pagination.
        foreach ($header in $response.Headers.Link.split(",")) {
            if ($header -match '<(.*)>; rel="(.*)"') {
                $links[$matches[2]] = $matches[1]
            }
        }
    }
    $objects = $null
    if ($convert) {
        $objects = ConvertFrom-Json $response.content
    }
    @{objects = $objects
      nextUrl = $links.next
      response = $response
      limitLimit = [int][string]$response.Headers.'X-Rate-Limit-Limit'
      limitRemaining = [int][string]$response.Headers.'X-Rate-Limit-Remaining' # how many calls are remaining
      limitReset = [int][string]$response.Headers.'X-Rate-Limit-Reset' # when limit will reset, see also [DateTimeOffset]::FromUnixTimeSeconds(limitReset)
    }
}

function Invoke-OktaWebRequest($method, $path, $body) {
    $url = $baseUrl + $path
    if ($body) {
        $jsonBody = $body | ConvertTo-Json -compress -depth 100
    }
    $response = Invoke-WebRequest $url -Method $method -Headers $headers -Body $jsonBody -UserAgent $userAgent
    @{objects = ConvertFrom-Json $response.content
      response = $response
      limitLimit = [int][string]$response.Headers.'X-Rate-Limit-Limit'
      limitRemaining = [int][string]$response.Headers.'X-Rate-Limit-Remaining' # how many calls are remaining
      limitReset = [int][string]$response.Headers.'X-Rate-Limit-Reset' # when limit will reset, see also [DateTimeOffset]::FromUnixTimeSeconds(limitReset)
    }
}

function Get-Error($_) {
    $responseStream = $_.Exception.Response.GetResponseStream()
    $responseReader = New-Object System.IO.StreamReader($responseStream)
    $responseContent = $responseReader.ReadToEnd()
    ConvertFrom-Json $responseContent
}
#endregion

#region Apps - https://developer.okta.com/docs/api/resources/apps

function Get-OktaApp($appid) {
    Invoke-Method GET "/api/v1/apps/$appid"
}

function Get-OktaApps($filter, $limit = 200,$after, $expand, $url = "/api/v1/apps?filter=$filter&limit=$limit&after=$after&expand=$expand&q=$q", $q) {
    Invoke-PagedMethod $url
}

function Add-OktaAppGroup($appid, $groupid, $group) {
    Invoke-Method PUT "/api/v1/apps/$appid/groups/$groupid" #$group
}

function Remove-OktaAppGroup($appid, $groupid) {
    $null = Invoke-Method DELETE "/api/v1/apps/$appid/groups/$groupid"
}

function Add-OktaAppUser($appid, $appuser) {
    Invoke-Method POST "/api/v1/apps/$appid/users" $appuser
}

function Get-OktaAppUsers($appid, $limit = 50, $url = "/api/v1/apps/$appid/users?limit=$limit&expand=$expand", $expand) {
    Invoke-PagedMethod $url
}

function Remove-OktaAppUser($appid, $userid) {
    $null = Invoke-Method DELETE "/api/v1/apps/$appid/users/$userid"
}

#endregion

#region Groups

function Get-OktaGroup($id) {
    Invoke-Method GET "/api/v1/groups/$id"
}

function Get-OktaGroups($q, $filter, $limit = 200, $url = "/api/v1/groups?q=$q&filter=$filter&limit=$limit", $paged = $false) {
    if ($paged) {
        Invoke-PagedMethod $url
    } else {
        Invoke-Method GET $url
    }
}

function Add-OktaGroupMember($groupid, $userid) {
    $null = Invoke-Method PUT "/api/v1/groups/$groupid/users/$userid"
}

function Remove-OktaGroupMember($groupid, $userid) {
    $null = Invoke-Method DELETE "/api/v1/groups/$groupid/users/$userid"
}

function Get-OktaGroupMember($id, $limit = 200, $url = "/api/v1/groups/$id/users?limit=$limit", $paged = $false) {
    if ($paged) {
        Invoke-PagedMethod $url
    } else {
        Invoke-Method GET $url
    }
}

#endregion

#endregion Okta API Functions

Connect-Okta $token $baseUrl

#get the group ID
$groupname = "PeopleViewReadOnly"
$groupID = (Get-OktaGroups $groupname).ID

#get the app ID
$appName = "PeopleView"
$appID = (Get-OktaApps $appID).ID

#region Main

#first, get all users in Okta
#create PSO for the list of users
$new_csv = $null
$new_csv = @()

#process: call Get-OktaUsers with filter of ""
#then loop through the objects returned in each page and add them to our PSO
$page_next = $null

Do{
    $page =  $null

    If($page_next -eq $null){
        $page = Get-OktaUsers -filter "" -limit 1000
    }
    Else{
        $page = Get-OktaUsers -url $page_next
    }

    Foreach($object in $page.objects){
        $new_csv += $object
    }

    $page_next = $page.nextUrl
    $page_next
}
Until($page_next -eq $null)



#iterate through list of users and add to group and app
Foreach($user in $new_csv){
        
    #if department -eq "HR" - add to group and app
    If($user.department -eq "HR"){
        Try{            
            Add-OktaAppUser -appid $app_ID -appuser $user.ID
            Add-OktaGroupMember -groupid $groupID -userid $user.ID
        }
        Catch{
            $error_data = $null
            $error_data = Get-Error $_
            #rate limit violation error code
            If($error_data.errorCode -eq "E0000047"){
                Start-Sleep -s 45
            
                Try{
                    Add-OktaAppUser -appid $app_ID -u
                    Add-OktaGroupMember -groupid $groupID -userid $user.ID         
                }
                Catch{
                    $error_data = Get-Error $_
                    $result = $error_data.errorCode +": " + $error_data.errorSummary
                    $result
                }
            }
            Else{
                $result = $error_data.errorCode +": " + $error_data.errorSummary
                $result    
            }
        }
    }
}


#pull the list of users in PeopleViewReadOnly
$page_next = $null
#create PSO for the list of users
$PV_Users_csv = $null
$PV_Users_csv = @()

Do{
    $page =  $null

    If($page_next -eq $null){
        $page = Get-OktaGroupMember -id $groupID -limit 1000
    }
    Else{
        $page = Get-OktaUsers -url $page_next
    }

    Foreach($object in $page.objects){
        $new_csv += $object
    }

    $page_next = $page.nextUrl
    $page_next
}
Until($page_next -eq $null)

#then iterate through the current members of the group and see if any have a department that doesn't match HR
Foreach($user in $PV_Users_csv){
    
    $result = $null
    
    If($user.department -ne "HR"){
        Try{            
            Remove-OktaAppUser -appid $app_ID -appuser $user.ID
            Remove-OktaGroupMember -groupid $groupID -userid $user.ID
        }
        Catch{
            $error_data = $null
            $error_data = Get-Error $_
            #rate limit violation error code
            If($error_data.errorCode -eq "E0000047"){
                Start-Sleep -s 45
            
                Try{
                    Remove-OktaAppUser -appid $app_ID -u
                    Remove-OktaGroupMember -groupid $groupID -userid $user.ID         
                }
                Catch{
                    $error_data = Get-Error $_
                    $result = $error_data.errorCode +": " + $error_data.errorSummary
                    $result
                }
            }
            Else{
                $result = $error_data.errorCode +": " + $error_data.errorSummary
                $result
            }
        }
    }
}

#endregion