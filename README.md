What is PsBookSleeve?
---------------------
A PowerShell wrapper around Marc Gravell's excellent BookSleeve library.
See http://code.google.com/p/booksleeve/.

PsBookSleeve was hacked together during the course of a day,
to get some Redis action going in PowerShell. It will probably
break in unexpected ways.

License
-------
See LICENSE.

Usage
-----
In its most simple form, it's very easy:

    Import-Module PsBookSleeve
    Get-RedisConnection
    Invoke-RedisCommand Strings Set mykey, myvalue
    $str = Invoke-RedisCommand Strings GetString 'mykey'
    Invoke-RedisCommand Keys Find *

For more information, see Test.ps1.