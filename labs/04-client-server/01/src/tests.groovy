import java.net.InetAddress
import java.net.Socket
import java.nio.charset.StandardCharsets

int passed = 0
int total = 0

def check = { String name, boolean success ->
    total++
    if (success) {
        passed++
    }
    println "${name}: ${success ? 'PASS' : 'FAIL'}"
}

check('Uppercase', StringServer.process('UPPER\thello') == 'OK\tHELLO')
check('Lowercase', StringServer.process('LOWER\tHeLLo') == 'OK\thello')
check('Reverse', StringServer.process('REVERSE\tabcdef') == 'OK\tfedcba')
check('Length', StringServer.process('LENGTH\tHello') == 'OK\t5')
check('Empty string', StringServer.process('LENGTH\t') == 'OK\t0')
check('Spaces preserved', StringServer.process('REVERSE\ta b c') == 'OK\tc b a')
check('Unicode uppercase', StringServer.process('UPPER\tпривет') == 'OK\tПРИВЕТ')
check('Unicode length', StringServer.process('LENGTH\tA😀') == 'OK\t2')
check('Unicode reverse', StringServer.process('REVERSE\tA😀') == 'OK\t😀A')
check('Unknown command', StringServer.process('REMOVE\ttext').startsWith('ERROR\t'))
check('Invalid request', StringServer.process('LENGTH').startsWith('ERROR\t'))
check('Case-insensitive command', StringServer.process('lower\tABC') == 'OK\tabc')

def server = new StringServer(0)
Thread serverThread = new Thread({ server.serve() } as Runnable)
serverThread.start()

def send = { String command, String value ->
    new Socket(InetAddress.getByName('127.0.0.1'), server.port).withCloseable { socket ->
        def input = new BufferedReader(new InputStreamReader(socket.inputStream, StandardCharsets.UTF_8))
        def output = new BufferedWriter(new OutputStreamWriter(socket.outputStream, StandardCharsets.UTF_8))
        output.write(command + '\t' + value)
        output.newLine()
        output.flush()
        input.readLine()
    }
}

try {
    check('TCP uppercase', send('UPPER', 'hello server') == 'OK\tHELLO SERVER')
    check('TCP reverse', send('REVERSE', 'Groovy') == 'OK\tyvoorG')
    check('TCP length', send('LENGTH', '12345') == 'OK\t5')

    def responses = new String[4]
    def threads = (0..<4).collect { i ->
        new Thread({ responses[i] = send('UPPER', "client${i}") } as Runnable)
    }
    threads.each { it.start() }
    threads.each { it.join(5000) }
    check('Four simultaneous clients', (0..<4).every { i -> responses[i] == "OK\tCLIENT${i}" })
} finally {
    server.close()
    serverThread.join(5000)
}

println "\nPassed: ${passed}/${total}"
if (passed != total) {
    System.exit(1)
}
