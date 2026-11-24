#load "DemoServer.fsx"

open System
open System.Net
open System.Net.Sockets
open System.Text
open System.Threading

let withServer action =
    let listener = new TcpListener(IPAddress.Loopback, 0)
    listener.Start()
    let port = (listener.LocalEndpoint :?> IPEndPoint).Port
    let worker =
        Thread(ThreadStart(fun () ->
            try
                let client = listener.AcceptTcpClient()
                DemoServer.serveClient false client
            with _ -> ()))
    worker.IsBackground <- true
    worker.Start()
    try
        action (sprintf "http://127.0.0.1:%d" port)
    finally
        listener.Stop()
        worker.Join(2000) |> ignore

let textBody (response: HttpCore.HttpResponse) =
    Encoding.UTF8.GetString(response.Body)

let mustFail action =
    try
        action ()
        false
    with _ -> true

let mutable passed = 0
let mutable total = 0
let check name test =
    total <- total + 1
    try
        if test () then
            passed <- passed + 1
            printfn "%s: PASS" name
        else
            printfn "%s: FAIL" name
    with error ->
        printfn "%s: FAIL (%s)" name error.Message

check "GET status" (fun () ->
    withServer (fun url -> (HttpCore.request "GET" (url + "/hello") None).StatusCode = 200))

check "GET body" (fun () ->
    withServer (fun url -> textBody (HttpCore.request "GET" (url + "/hello") None) = "Hello from F# server!\n"))

check "Content-Type header" (fun () ->
    withServer (fun url ->
        let response = HttpCore.request "GET" (url + "/hello") None
        HttpCore.headerValue response.Headers "CONTENT-TYPE" = Some "text/plain; charset=utf-8"))

check "JSON body" (fun () ->
    withServer (fun url ->
        textBody (HttpCore.request "GET" (url + "/items") None)
            = "{\"items\":[\"tea\",\"coffee\"],\"count\":2}\n"))

check "UTF-8 body" (fun () ->
    withServer (fun url -> textBody (HttpCore.request "GET" (url + "/unicode") None) = "Привет, F#!\n"))

check "HEAD has no body" (fun () ->
    withServer (fun url ->
        let response = HttpCore.request "HEAD" (url + "/hello") None
        response.StatusCode = 200 && response.Body.Length = 0))

check "HEAD retains Content-Length" (fun () ->
    withServer (fun url ->
        let response = HttpCore.request "HEAD" (url + "/hello") None
        HttpCore.headerValue response.Headers "Content-Length" = Some "22"))

check "POST echoes payload" (fun () ->
    withServer (fun url ->
        textBody (HttpCore.request "POST" (url + "/echo") (Some "Hello F#")) = "Hello F#"))

check "Chunked response" (fun () ->
    withServer (fun url ->
        textBody (HttpCore.request "GET" (url + "/chunked") None) = "Hello chunked world!\n"))

check "Read body until close" (fun () ->
    withServer (fun url ->
        textBody (HttpCore.request "GET" (url + "/close") None) = "Body read until connection closes\n"))

check "204 without body" (fun () ->
    withServer (fun url ->
        let response = HttpCore.request "GET" (url + "/empty") None
        response.StatusCode = 204 && response.Body.Length = 0))

check "404 status" (fun () ->
    withServer (fun url -> (HttpCore.request "GET" (url + "/unknown") None).StatusCode = 404))

check "Query string is sent" (fun () ->
    withServer (fun url ->
        textBody (HttpCore.request "GET" (url + "/target?name=Anna") None) = "/target?name=Anna\n"))

check "Unsupported URL scheme" (fun () ->
    mustFail (fun () -> HttpCore.request "GET" "ftp://example.com/" None |> ignore))

check "Unsupported HTTP method" (fun () ->
    mustFail (fun () -> HttpCore.request "DELETE" "http://127.0.0.1/" None |> ignore))

check "GET with body rejected" (fun () ->
    mustFail (fun () -> HttpCore.request "GET" "http://127.0.0.1/" (Some "text") |> ignore))

printfn ""
printfn "Passed: %d/%d" passed total
if passed <> total then Environment.ExitCode <- 1
