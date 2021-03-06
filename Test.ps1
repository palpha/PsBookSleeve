# Random tests that will run against:

$configuration = @{
    Host = 'localhost'
    Port = 6379
    Database = 0
}

Import-Module PsBookSleeve -Force

$ErrorActionPreference = 'Stop'

function assert {
    param (
        [ScriptBlock] $Assertion,
        [string] $Message = "${Assertion}: 👍"
    )
    
    if (-not (& $Assertion)) {
        throw "${Assertion}: 👎"
    } else {
        Write-Host $Message
    }
}

$conn = Get-RedisConnection @configuration

$trans = $conn.CreateTransaction()
Invoke-RedisCommand Strings Set testing, '1' -T $trans | Out-Null
$task = Invoke-RedisCommand Strings GetString testing -T $trans
$trans.Execute() | Out-Null
$x = Wait-RedisResult $task ([string]) $trans
assert { $x -eq '1' }

$trans = $conn.CreateTransaction()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
1..($iters = 1000) | % {
    Invoke-RedisCommand Strings Set testing:$_, $_.ToString() | Out-Null
}
$time = $sw.ElapsedMilliseconds
Write-Host "Time: $time; Avg: $($time / $iters)"
assert { $time / $iters -lt 2 }
# So, yeah, this wrapper is not a blazingly fast way to use Redis...

$topKeyVal = Invoke-RedisCommand Strings GetString testing:$iters
assert { $topKeyVal -eq $iters }

$keys = Invoke-RedisCommand Keys Find testing:100*
assert { $keys.Count -eq 2 }

Invoke-RedisCommand Strings Set mykey, myvalue | Out-Null
Invoke-RedisCommand Strings Set myotherkey, myothervalue | Out-Null
$x = Invoke-RedisCommand Strings GetString mykey
assert { $x -eq 'myvalue' }

$x = @(Invoke-RedisCommand Keys Find my*).Count
assert { $x -ge 2 }

Close-RedisConnection