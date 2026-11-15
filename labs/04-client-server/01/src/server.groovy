import java.net.BindException

int port = 5050

if (args.length > 1) {
    System.err.println('Usage: groovy server.groovy [port]')
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

try {
    def server = new StringServer(port)
    println "Server listening at 127.0.0.1:${server.port}"
    println 'Press Ctrl+C to stop'
    server.serve()
} catch (BindException ignored) {
    System.err.println("Cannot start server: port ${port} is already in use")
    System.exit(1)
} catch (IllegalArgumentException ex) {
    System.err.println(ex.message)
    System.exit(1)
}
