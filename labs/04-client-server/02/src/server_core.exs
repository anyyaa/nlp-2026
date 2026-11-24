defmodule BullsCows.Server do
  alias BullsCows.Game

  def start(port \\ 5051, secret_factory \\ fn _ -> Game.new_secret() end) do
    options = [:binary, packet: :line, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]

    case :gen_tcp.listen(port, options) do
      {:ok, listener} ->
        {:ok, {_address, actual_port}} = :inet.sockname(listener)
        acceptor = spawn(fn -> accept_loop(listener, secret_factory, 0) end)
        {:ok, listener, actual_port, acceptor}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp accept_loop(listener, secret_factory, session_number) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        secret = secret_factory.(session_number)

        handler =
          spawn(fn ->
            receive do
              {:socket_ready, accepted_socket} ->
                serve_session(accepted_socket, secret, 0)
            end
          end)

        case :gen_tcp.controlling_process(socket, handler) do
          :ok -> send(handler, {:socket_ready, socket})
          {:error, _reason} ->
            :gen_tcp.close(socket)
            Process.exit(handler, :kill)
        end

        accept_loop(listener, secret_factory, session_number + 1)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        IO.puts("Accept error: #{inspect(reason)}")
    end
  end

  defp serve_session(socket, secret, attempts) do
    if attempts == 0 do
      :gen_tcp.send(socket, "WELCOME Bulls and Cows! Guess four different digits.\n")
    end

    receive_command(socket, secret, attempts)
  end

  defp receive_command(socket, secret, attempts) do
    case :gen_tcp.recv(socket, 0, :infinity) do
      {:ok, line} ->
        case Game.command(secret, attempts, line) do
          {:reply, answer, next_attempts} ->
            case :gen_tcp.send(socket, answer) do
              :ok -> receive_command(socket, secret, next_attempts)
              {:error, _} -> :gen_tcp.close(socket)
            end

          {:close, answer} ->
            :gen_tcp.send(socket, answer)
            :gen_tcp.close(socket)
        end

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end
end
