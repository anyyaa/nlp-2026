import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.charset.StandardCharsets

class StringServer implements Closeable {
    private final ServerSocket listener
    private volatile boolean running = true

    StringServer(int port) {
        if (port < 0 || port > 65535) {
            throw new IllegalArgumentException('Port must be between 0 and 65535')
        }
        listener = new ServerSocket(port, 50, InetAddress.getByName('127.0.0.1'))
    }

    int getPort() {
        listener.localPort
    }

    static String process(String request) {
        int separator = request.indexOf('\t')
        if (separator < 0) {
            return 'ERROR\tExpected COMMAND<TAB>TEXT'
        }

        String command = request.substring(0, separator).trim().toUpperCase(Locale.ROOT)
        String value = request.substring(separator + 1)

        switch (command) {
            case 'UPPER':
                return 'OK\t' + value.toUpperCase(Locale.ROOT)
            case 'LOWER':
                return 'OK\t' + value.toLowerCase(Locale.ROOT)
            case 'REVERSE':
                return 'OK\t' + new StringBuilder(value).reverse().toString()
            case 'LENGTH':
                return 'OK\t' + value.codePointCount(0, value.length())
            default:
                return 'ERROR\tUnknown command: ' + command
        }
    }

    private static void handleClient(Socket socket) {
        try {
            socket.withCloseable { connection ->
                def reader = new BufferedReader(
                    new InputStreamReader(connection.inputStream, StandardCharsets.UTF_8)
                )
                def writer = new BufferedWriter(
                    new OutputStreamWriter(connection.outputStream, StandardCharsets.UTF_8)
                )

                String request
                while ((request = reader.readLine()) != null) {
                    writer.write(process(request))
                    writer.newLine()
                    writer.flush()
                }
            }
        } catch (IOException ignored) {
        }
    }

    void serve() {
        while (running) {
            try {
                Socket client = listener.accept()
                Thread worker = new Thread({ handleClient(client) } as Runnable)
                worker.daemon = true
                worker.start()
            } catch (SocketException ex) {
                if (running) {
                    throw ex
                }
                break
            }
        }
    }

    @Override
    void close() {
        running = false
        listener.close()
    }
}
