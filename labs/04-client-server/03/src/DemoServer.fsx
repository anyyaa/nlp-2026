#load "HttpCore.fsx"

open System
open System.IO
open System.Net
open System.Net.Sockets
open System.Text

let private writeText (stream: Stream) (text: string) =
    let bytes = Encoding.UTF8.GetBytes(text)
    stream.Write(bytes, 0, bytes.Length)

let serveClient (verbose: bool) (tcp: TcpClient) =
    use connection = tcp
    connection.ReceiveTimeout <- 5000
    connection.SendTimeout <- 5000
    use stream = connection.GetStream()

    let requestLine = HttpCore.readLine stream
    let parts = requestLine.Split([|' '|], 3)
    if parts.Length <> 3 then failwith "Malformed client request"
    let methodName, target = parts.[0], parts.[1]
    let headers = HttpCore.readHeaders stream
    let payload =
        match HttpCore.headerValue headers "content-length" with
        | Some size -> HttpCore.readExactly stream (Int32.Parse(size))
        | None -> Array.empty<byte>
    let textBody = Encoding.UTF8.GetString(payload)
    let path = target.Split([|'?'|]).[0]
    if verbose then printfn "<-- %s %s" methodName target

    let send (status: int) (reason: string) (contentType: string) (text: string) (headOnly: bool) =
        let bytes = Encoding.UTF8.GetBytes(text)
        writeText stream
            (sprintf "HTTP/1.1 %d %s\r\nContent-Type: %s; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
                status reason contentType bytes.Length)
        if not headOnly then
            stream.Write(bytes, 0, bytes.Length)

    match methodName, path with
    | "GET", "/hello" -> send 200 "OK" "text/plain" "Hello from F# server!\n" false
    | "HEAD", "/hello" -> send 200 "OK" "text/plain" "Hello from F# server!\n" true
    | "GET", "/items" ->
        send 200 "OK" "application/json" "{\"items\":[\"tea\",\"coffee\"],\"count\":2}\n" false
    | "GET", "/unicode" -> send 200 "OK" "text/plain" "Привет, F#!\n" false
    | "GET", "/target" -> send 200 "OK" "text/plain" (target + "\n") false
    | "POST", "/echo" -> send 200 "OK" "text/plain" textBody false
    | "GET", "/empty" -> send 204 "No Content" "text/plain" "" false
    | "GET", "/close" ->
        writeText stream "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\n"
        writeText stream "Body read until connection closes\n"
    | "GET", "/chunked" ->
        writeText stream "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n"
        for piece in ["Hello "; "chunked "; "world!\n"] do
            let bytes = Encoding.UTF8.GetBytes(piece)
            writeText stream (sprintf "%X\r\n" bytes.Length)
            stream.Write(bytes, 0, bytes.Length)
            writeText stream "\r\n"
        writeText stream "0\r\n\r\n"
    | _ -> send 404 "Not Found" "text/plain" "Not found\n" false

    stream.Flush()
    if verbose then printfn "--> Response sent"

let serveForever port =
    let listener = new TcpListener(IPAddress.Loopback, port)
    listener.Start()
    printfn "Demo server listening at http://127.0.0.1:%d" port
    printfn "Endpoints: /hello, /items, /unicode, /chunked, /empty, /close, /target, POST /echo"
    printfn "Press Ctrl+C to stop."
    try
        while true do
            let client = listener.AcceptTcpClient()
            try serveClient true client
            with error -> printfn "Server error: %s" error.Message
    finally
        listener.Stop()
