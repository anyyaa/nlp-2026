open System
open System.IO
open System.Net.Sockets
open System.Net.Security
open System.Text
open System.Globalization
open System.Text.RegularExpressions

type HttpResponse = {
    StatusCode: int
    ReasonPhrase: string
    Headers: Map<string, string>
    Body: byte[]
}

let maxBodyBytes = 2_000_000

let readLine (stream: Stream) =
    use buffer = new MemoryStream()
    let mutable doneReading = false
    while not doneReading do
        let current = stream.ReadByte()
        if current = -1 then
            failwith "Unexpected end of HTTP headers"
        elif current = 13 then
            if stream.ReadByte() <> 10 then
                failwith "Invalid HTTP line ending"
            doneReading <- true
        else
            if buffer.Length >= 16_384L then
                failwith "HTTP header line is too long"
            buffer.WriteByte(byte current)
    Encoding.ASCII.GetString(buffer.ToArray())

let readHeaders (stream: Stream) =
    let mutable headers = Map.empty<string, string>
    let mutable line = readLine stream
    let mutable count = 0
    while line <> "" do
        count <- count + 1
        if count > 100 then failwith "Too many HTTP headers"
        let separator = line.IndexOf(':')
        if separator <= 0 then failwith "Malformed HTTP header"
        let key = line.Substring(0, separator).Trim().ToLowerInvariant()
        let value = line.Substring(separator + 1).Trim()
        headers <- Map.add key value headers
        line <- readLine stream
    headers

let headerValue (headers: Map<string, string>) (name: string) =
    Map.tryFind (name.ToLowerInvariant()) headers

let readExactly (stream: Stream) (length: int) =
    if length < 0 || length > maxBodyBytes then
        failwith "HTTP response body exceeds the permitted size"
    let bytes = Array.zeroCreate<byte> length
    let mutable offset = 0
    while offset < length do
        let count = stream.Read(bytes, offset, length - offset)
        if count = 0 then failwith "HTTP message body ended too early"
        offset <- offset + count
    bytes

let readUntilClose (stream: Stream) =
    use output = new MemoryStream()
    let chunk = Array.zeroCreate<byte> 4096
    let mutable count = stream.Read(chunk, 0, chunk.Length)
    while count > 0 do
        if output.Length + int64 count > int64 maxBodyBytes then
            failwith "HTTP response body exceeds the permitted size"
        output.Write(chunk, 0, count)
        count <- stream.Read(chunk, 0, chunk.Length)
    output.ToArray()

let readChunked (stream: Stream) =
    use output = new MemoryStream()
    let mutable finished = false
    while not finished do
        let sizeLine = readLine stream
        let sizeText = sizeLine.Split([|';'|]).[0].Trim()
        let size = Int32.Parse(sizeText, NumberStyles.HexNumber, CultureInfo.InvariantCulture)
        if size = 0 then
            let mutable trailer = readLine stream
            while trailer <> "" do
                trailer <- readLine stream
            finished <- true
        else
            if output.Length + int64 size > int64 maxBodyBytes then
                failwith "HTTP response body exceeds the permitted size"
            let bytes = readExactly stream size
            output.Write(bytes, 0, bytes.Length)
            if readLine stream <> "" then
                failwith "Malformed chunked response"
    output.ToArray()

let request (httpMethod: string) (url: string) (body: string option) =
    let methodName = httpMethod.ToUpperInvariant()
    if not (List.contains methodName ["GET"; "HEAD"; "POST"]) then
        invalidArg "httpMethod" "Only GET, HEAD and POST are supported"

    let uri = Uri(url, UriKind.Absolute)
    if uri.Scheme <> "http" && uri.Scheme <> "https" then
        invalidArg "url" "Only http:// and https:// are supported"
    if uri.UserInfo <> "" then
        invalidArg "url" "Credentials in URL are not supported"
    if methodName <> "POST" && Option.isSome body then
        invalidArg "body" "A request body is supported only for POST"

    let payload =
        match body with
        | Some text -> Encoding.UTF8.GetBytes(text)
        | None -> Array.empty<byte>

    let target = if uri.PathAndQuery = "" then "/" else uri.PathAndQuery
    let payloadHeaders =
        if methodName = "POST" then
            sprintf "Content-Type: text/plain; charset=utf-8\r\nContent-Length: %d\r\n" payload.Length
        else ""
    let requestHead =
        sprintf "%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: ManualFSharpClient/1.0\r\nAccept: */*\r\nConnection: close\r\n%s\r\n"
            methodName target uri.Authority payloadHeaders

    use tcp = new TcpClient()
    tcp.ReceiveTimeout <- 5000
    tcp.SendTimeout <- 5000
    tcp.Connect(uri.Host, uri.Port)
    use transport: Stream =
        if uri.Scheme = "https" then
            let tls = new SslStream(tcp.GetStream(), false)
            tls.AuthenticateAsClient(uri.Host)
            tls :> Stream
        else
            tcp.GetStream() :> Stream

    let headBytes = Encoding.ASCII.GetBytes(requestHead)
    transport.Write(headBytes, 0, headBytes.Length)
    if payload.Length > 0 then
        transport.Write(payload, 0, payload.Length)
    transport.Flush()

    let statusLine = readLine transport
    let matched = Regex.Match(statusLine, @"^HTTP/1\.[01] ([0-9]{3})(?: (.*))?$")
    if not matched.Success then failwith "Malformed HTTP status line"
    let status = Int32.Parse(matched.Groups.[1].Value)
    let reason = matched.Groups.[2].Value
    let headers = readHeaders transport

    let responseBody =
        if methodName = "HEAD" || (status >= 100 && status < 200) || status = 204 || status = 304 then
            Array.empty<byte>
        else
            match headerValue headers "transfer-encoding" with
            | Some value when value.ToLowerInvariant().Contains("chunked") ->
                readChunked transport
            | _ ->
                match headerValue headers "content-length" with
                | Some lengthText ->
                    match Int32.TryParse(lengthText) with
                    | true, length -> readExactly transport length
                    | _ -> failwith "Invalid Content-Length header"
                | None -> readUntilClose transport

    { StatusCode = status
      ReasonPhrase = reason
      Headers = headers
      Body = responseBody }
