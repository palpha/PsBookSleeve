[Reflection.Assembly]::LoadFrom("$(split-path -parent $MyInvocation.MyCommand.Definition)\BookSleeve.dll") > $null

$methodCache = @{}
$waitMethod =
    [BookSleeve.RedisConnection].GetMethods() `
        | ? { $_.Name -eq 'Wait' -and $_.IsPublic -and $_.IsGenericMethod } `
        | select -First 1
$waitMethodCache = @{}
$resultTypeCache = @{}

function Get-RedisConnection {
    param (
        [string] $Host = 'localhost',
        [int] $Port = 6379,
        [int] $IoTimeout = -1,
        [string] $Password = $null,
        [int] $MaxUnsent = [int]::MaxValue,
        [int] $SyncTimeout = 10000,
        [int] $Database = 0,
        [switch] $AllowAdmin
    )
    
    [BookSleeve.RedisConnection] $script:conn = New-Object BookSleeve.RedisConnection($Host, $Port, $IoTimeout, $Password, $MaxUnsent, $AllowAdmin.IsPresent, $SyncTimeout)
    $script:conn.Open().Wait()
    $script:implicitDatabase = $Database
    $script:conn
}

function Match-TypeArrays {
    param (
        [type[]] $Left,
        [type[]] $Right
    )
    
    $idx = 0
    foreach ($type in $Left) {
        $rType = $Right[$idx]
        if ($type -ne $rType -and -not ($rType -eq [long] -and $type -eq [int] -or $rType -eq [int] -and $type -eq [long])) { return $false }
        $idx++
    }
    
    $true
}

function Invoke-RedisCommand {
    [CmdletBinding()]
    param (
        [string] $Interface,
        [string] $Command,
        [object[]] $Arguments,
        [int] $Database = $script:implicitDatabase,
        [BookSleeve.RedisConnection] $Transaction,
        [switch] $Async,
        [switch] $Raw
    )
    
    if ($Transaction) {
        $Async = $true
    } else {
        $Transaction = $script:conn
    }
    
    $if = switch ($Interface) {
        Keys { [BookSleeve.IKeyCommands] }
        Strings { [BookSleeve.IStringCommands] }
        Lists { [BookSleeve.IListCommands] }
        SortedSets { [BookSleeve.ISortedSetCommands] }
        Sets { [BookSleeve.ISetCommands] }
        Hashes { [BookSleeve.IHashCommands] }
        Server { [BookSleeve.IServerCommands] }
    }

    try {
        $dbArg = @($Database)
        
        if ($Arguments.Count -gt 0) {
            $Arguments = $dbArg + $Arguments
        } else {
            $Arguments = $dbArg
        }
        
        if (-not $Raw) {
            $Arguments += $False
        }
        
        $argTypes = $Arguments | % { $_.GetType() }
        
        $methodKey = $if.Name, $Command, ($argTypes -join ':') -join '|'
        $method = $methodCache[$methodKey]
        if (-not $method) {        
            $method = $if.GetMethods() `
                | ? { $_.Name -eq $Command } `
                | ? { Match-TypeArrays ($_.GetParameters() | % { $_.ParameterType }) $argTypes } `
                | select -First 1
            $methodCache[$methodKey] = $method
        }
            
        if (-not $method) {
            throw "Could not find method $Command in $if`nArguments: $($Arguments -join ', ')`nArgument types: $($argTypes -join ', ')"
        }
        
        $idx = 0
        $methodParamTypes = $method.GetParameters() | % { $_.ParameterType }
        foreach ($arg in $Arguments) {
            if (($arg -is [int] -or $arg -is [long]) -and $methodParamTypes[$idx] -eq [long]) {
                $Arguments[$idx] = [long] $arg # it is weird that I have to cast long to long...
            }
            $idx++
        }

        # debugging help:
        #Write-Host "Interface: $if; Command: $Command;`nArguments: $($Arguments -join ', ')`nArgument types: $($argTypes -join ', ')"

        $task = $method.Invoke($Transaction, $Arguments)

        if ($Async) { $task }
        else {
            $resultType = $resultTypeCache[$methodKey]
            if (-not $resultType) {
                $resultType = $task.GetType().GetProperty('Result').PropertyType
                $resultTypeCache[$methodKey] = $resultType
            }
            
            Wait-RedisResult -Task $task -ResultType $resultType -Transaction $Transaction
        }
    } catch {
        Write-Error ("Interface: $if; Command: $Command; Arguments: $($Arguments -join ', ')`n" + $_)
    }
}

function Wait-RedisResult {
    param (
        $Task,
        [type] $ResultType,
        [BookSleeve.RedisConnection] $Transaction = $script:conn
    )
    
    $myWaitMethod = $waitMethodCache[$ResultType]
    if (-not $myWaitMethod) {
        $myWaitMethod = $waitMethod.MakeGenericMethod(@($ResultType))
        $waitMethodCache[$ResultType] = $myWaitMethod
    }
    
    $myWaitMethod.Invoke($Transaction, $task)
}

function Close-RedisConnection {
    param ([switch] $Abort)
    $abort = $Abort.IsPresent
    $script:conn.Close($abort)
    $script:conn.Dispose()
}

Export-ModuleMember Get-RedisConnection
Export-ModuleMember Invoke-RedisCommand
Export-ModuleMember Wait-RedisResult
Export-ModuleMember Close-RedisConnection
