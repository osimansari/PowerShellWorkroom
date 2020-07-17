#
# This is the One Gross One Net score script
#
# [CmdletBinding()]
# param (
#     [Parameter(Mandatory)]
#     [System.Int32]
#     $hl
# )


#--- Setup ----------------------------------------------------------------------------

$Script:scriptRoot = Split-Path -Path $PSCommandPath -Parent
$Script:modulePath = $Script:scriptRoot + "\module\JhcGolfScore"
$Script:csvPath = $Script:scriptRoot + "\scores\score.csv"
$Script:jsonDepth = 20

Import-Module -FullyQualifiedName $Script:modulePath -Force

#--- Functions ------------------------------------------------------------------------
function getBlindDraw {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object]
        $gRecord,
        [Parameter(Mandatory=$true)]
        [System.String]
        $team
    )

    $drawSet = $gRecord | Where-Object -Property Team -NE $team | ConvertTo-Json -Depth $Script:jsonDepth | ConvertFrom-Json
    $i = Get-Random -Minimum 0 -Maximum ($drawSet.length)
    # $drawSet[$i].FirstName += '_bd'
    # $drawSet[$i].LastName += '_bd'
    $drawSet[$i].Team = $team
    return $drawSet[$i]
}

function getBestScore {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object]
        $sTable,
        [Parameter(Mandatory=$true)]
        [System.String]
        $team,
        [Parameter(Mandatory=$true)]
        [System.Int32]
        $hole
    )
    
    $testTable = $sTable | Where-Object -Property Team -EQ $team | Where-Object -Property holeNumber -EQ $hole
    $a = @()

    foreach ($i in $testTable) {
        $a += New-Object -TypeName psobject -Property @{'value' = $i.grossScore; 'obj' = $i}
        $a += New-Object -TypeName psobject -Property @{'value' = $i.netScore; 'obj' = $i}
    }

    $a = $a | Sort-Object -Property value

    #---grab first val
    $firstVal = $a[0]
    $nextVal = 0
    $firstScoreType
    $nextScoreType

    if($firstVal.obj.grossScore -eq $firstVal.obj.netScore) {
        $firstScoreType = 'either'

    }elseif($firstVal.value -eq $firstVal.obj.grossScore) {
        $firstScoreType = 'grossScore'
    }
    else {
        $firstScoreType = 'netScore'
    }

    for($i = 1; $i -lt $a.length; $i++) {
        
        if(($a[$i].obj.FirstName -eq $firstVal.obj.FirstName) -and ($a[$i].obj.LastName -eq $firstVal.obj.LastName)) {
            continue
        }

        if($a[$i].obj.grossScore -eq $a[$i].obj.netScore) {
            $nextScoreType = 'either'
        }
        elseif($a[$i].value -eq $a[$i].obj.grossScore) {
            $nextScoreType = 'grossScore'
        }
        else {
            $nextScoreType = 'netScore'
        }

        if(($nextScoreType -eq 'either') -or ($firstScoreType -ne $nextScoreType)) {
            $nextVal = $a[$i]
            break
        }
    }

    if($nextVal -eq 0) {
        $errMsg = "Could not calulate next best score for team $team on hole $hole"
        throw $errMsg
        exit
    }

    $firstVal.obj.lowScore = $firstScoreType
    $nextVal.obj.lowScore = $nextScoreType

    return $firstVal.obj, $nextVal.obj
    #return $a
}

#--- Main -----------------------------------------------------------------------------

$scoreRecord = Get-ScoreRecord -CsvFilePath $Script:csvPath

$golferRecord = $scoreRecord | New-Golfer | Get-GolferCourseHc | Get-GolferPops

foreach( $grp in ($golferRecord | Group-Object -Property Team)) {
    if($grp.Count -lt 4){
        $golferRecord += getBlindDraw -gRecord $golferRecord -team $grp.Name
    }
}

$scoreTable = @()
foreach($g in $golferRecord) {
    $ggs = Get-GolferGrossScore -ScoreRecord $scoreRecord -FirstName $g.FirstName -LastName $g.LastName

    Get-GolferScore -GolferPops $g -GolferGrossScore $ggs | Out-Null

    foreach($h in $g.Holes) {
        $scoreTable += $h | Select-Object -Property @{name = 'FirstName'; Expression = {$g.FirstName}}, @{name = 'LastName'; Expression = {$g.LastName}}, @{name = 'Team'; Expression = {$g.Team}}, *, @{name = 'lowScore'; expression = {$null}}, @{name = 'netBirdie'; expression = {$null}}, @{name = 'grossBirdie'; expression = {$null}} 
    }
}

$resultsTable = @()
$sum = 0

foreach($t in ($scoreTable | Group-Object -Property Team | ForEach-Object{$_.Name})) {
    foreach($h in (1..18)) {
        foreach ($r in (getBestScore -sTable $scoreTable -team $t -hole $h)) {
            if($r.lowScore -eq 'either') {
                $sum += $r.grossScore
            }
            else {
                $sum += $r.($r.lowScore)
            }
        }

        $resultsTable += New-Object -TypeName psobject -Property @{'Team' = $t; 'Hole' = $h; 'combinedScore' = $sum; 'Winner' = $null}
        $sum = 0
    }
}

$tie = $false
$ct = 0
$finalResults = @()

foreach($h in ($resultsTable | Group-Object -Property Hole)) {
    
    if(($h.group | Group-Object -Property combinedScore | Measure-Object).count -eq 1) {
        $tie = $true
    }
    
    foreach($g in ($h.group | Sort-Object -Property combinedScore)) {
        if($tie) {
            $g.winner = 'Tie'
        }elseif ($ct -eq 0) {
            $g.winner = $g.Team
        }
        
        $finalResults += $g | Select-Object -Property Hole, Team, combinedScore, Winner, @{name = 'grossBirdies'; expression = {$null}}, @{name = 'netBirdies'; expression = {$null}}
        $ct++
    }

    if($tie) {
        $tie = $false
    }
    $ct = 0
}

foreach($s in $scoreTable) {
    if($s.grossScore -lt $s.par) {
        $s.grossBirdie = '*'
    }

    if($s.netScore -lt $s.par) {
        $s.netBirdie = '*'
    }
}

#$scoreTable | Sort-Object -Property Team, holeNumber | Select-Object -Property *Name, Team, holeNumber, par, popCount, grossScore, netScore, netBirdie, grossBirdie, lowScore
#$finalResults | Sort-Object -Property Hole, Team

$grossBirdieTable = $scoreTable | Where-Object {$_.grossBirdie} | Group-Object -Property holeNumber, Team -NoElement | Select-Object -Property @{name = 'Hole'; expression = {($_.name -split ',')[0].trim()}}, @{name = 'Team'; expression = {($_.name -split ',')[-1].trim()}}, Count
$netBirdieTable = $scoreTable | Where-Object {$_.netBirdie} | Group-Object -Property holeNumber, Team -NoElement | Select-Object -Property @{name = 'Hole'; expression = {($_.name -split ',')[0].trim()}}, @{name = 'Team'; expression = {($_.name -split ',')[-1].trim()}}, Count

#$grossBirdieTable
#$netBirdieTable
foreach($r in $finalResults){
    $c = $null
    $c = ($grossBirdieTable | Where-Object -Property Hole -EQ $r.Hole | Where-Object -Property Team -EQ $r.Team).Count
    if($c) {
        $r.grossBirdies = $c    
    }
    else {
        $r.grossBirdies = $null
    }

    $c = $null
    $c = ($netBirdieTable | Where-Object -Property Hole -EQ $r.Hole | Where-Object -Property Team -EQ $r.Team).Count
    if($c) {
        $r.netBirdies = $c    
    }
    else {
        $r.netBirdies = $null
    }
}

$finalResults
