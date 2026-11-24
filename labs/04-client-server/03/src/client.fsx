#load "HttpCore.fsx"

open System
open System.Text

let args = fsi.CommandLineArgs |> Array.skip 1 |> Array.toList

try
    let methodName, url, body =
        match args with
        | [methodName; url] when methodName = "GET" || methodName = "HEAD" ->
            methodName, url, None
        | ["POST"; url; text] -> "POST", url, Some text
        | _ ->
            failwith "Usage: dotnet fsi client.fsx GET|HEAD URL  OR  dotnet fsi client.fsx POST URL TEXT"

    let response = HttpCore.request methodName url body
    printfn "HTTP/1.1 %d %s" response.StatusCode response.ReasonPhrase
    for KeyValue(name, value) in response.Headers do
        printfn "%s: %s" name value
    printfn ""
    printfn "Body (%d bytes):" response.Body.Length
    if response.Body.Length > 0 then
        printfn "%s" (Encoding.UTF8.GetString(response.Body))
    else
        printfn "(empty)"
with error ->
    eprintfn "ERROR: %s" error.Message
    Environment.ExitCode <- 1
