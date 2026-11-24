$ErrorActionPreference = 'Stop'
$modules = @('chat_protocol.erl', 'chat_server.erl', 'chat_client.erl', 'chat_tests.erl')
foreach ($file in $modules) {
    & erlc -Werror $file
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $file" }
}
Write-Host 'All Erlang modules compiled successfully.'
