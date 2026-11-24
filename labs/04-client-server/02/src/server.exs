Code.require_file("game.exs", __DIR__)
Code.require_file("server_core.exs", __DIR__)

demo = Enum.member?(System.argv(), "--demo")

secret_factory =
  if demo do
    fn index -> if rem(index, 2) == 0, do: "1234", else: "5678" end
  else
    fn _index -> BullsCows.Game.new_secret() end
  end

case BullsCows.Server.start(5051, secret_factory) do
  {:ok, _listener, port, _acceptor} ->
    IO.puts("Bulls and Cows server: 127.0.0.1:#{port}")
    IO.puts("Open client.exs in another PowerShell window.")

    if demo do
      IO.puts("Demo mode: client 1 secret = 1234, client 2 secret = 5678.")
    end

    IO.puts("Press Ctrl+C to stop the server.")

    receive do
      :stop -> :ok
    end

  {:error, reason} ->
    IO.puts("Cannot start server: #{inspect(reason)}")
end
