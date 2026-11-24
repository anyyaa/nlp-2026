import java.net.InetAddress
import java.net.Socket
import java.nio.charset.StandardCharsets

int port = 5050

if (args.length > 1) {
    System.err.println('Usage: groovy client.groovy [port]')
    System.exit(1)
}

if (args.length == 1) {
    try {
        port = Integer.parseInt(args[0])
    } catch (NumberFormatException ignored) {
        System.err.println('Port must be an integer')
        System.exit(1)
    }
}

def console = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))

def commands = [
    '1': 'UPPER',
    '2': 'LOWER',
    '3': 'REVERSE',
    '4': 'LENGTH'
]

try {
    new Socket(InetAddress.getByName('127.0.0.1'), port).withCloseable { socket ->
        def reader = new BufferedReader(new InputStreamReader(socket.inputStream, StandardCharsets.UTF_8))
        def writer = new BufferedWriter(new OutputStreamWriter(socket.outputStream, StandardCharsets.UTF_8))
        println "Connected to 127.0.0.1:${port}"

        while (true) {
            println '\n1 - Uppercase'
            println '2 - Lowercase'
            println '3 - Reverse'
            println '4 - Length'
            println '0 - Exit'
            print 'Choose: '
            System.out.flush()

            String choice = console.readLine()
            if (choice == null || choice == '0') {
                break
            }
            if (!commands.containsKey(choice)) {
                println 'Unknown option'
                continue
            }

            print 'Enter text: '
            System.out.flush()
            String value = console.readLine()
            if (value == null) {
                break
            }

            writer.write(commands[choice] + '\t' + value)
            writer.newLine()
            writer.flush()

            String response = reader.readLine()
            if (response == null) {
                println 'Server disconnected'
                break
            }
            if (response.startsWith('OK\t')) {
                println 'Result: ' + response.substring(3)
            } else if (response.startsWith('ERROR\t')) {
                println 'Error: ' + response.substring(6)
            } else {
                println 'Unexpected response: ' + response
            }
        }
    }
} catch (IOException ex) {
    System.err.println('Connection failed: ' + ex.message)
    System.err.println('Start the server first: groovy server.groovy')
    System.exit(1)
}
