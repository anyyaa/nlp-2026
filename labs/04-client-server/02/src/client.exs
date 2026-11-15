defmodule BullsCows.Client do
  def start do
    options = [:binary, packet: :line, active: false]

    case :gen_tcp.connect({127, 0, 0, 1}, 5051, options, 3_000) do
      {:ok, socket} ->
        case :gen_tcp.recv(socket, 0, 3_000) do
          {:ok, greeting} ->
            IO.puts(String.trim_trailing(greeting))
            IO.puts("Enter four digits, HELP or QUIT.")
            loop(socket)

          {:error, reason} ->
            IO.puts("Connection error: #{inspect(reason)}")
            :gen_tcp.close(socket)
        end

      {:error, reason} ->
        IO.puts("Cannot connect: #{inspect(reason)}")
        IO.puts("Start server.exs first.")
    end
  end

  defp loop(socket) do
    case IO.gets("Your guess: ") do
      nil ->
        :gen_tcp.close(socket)

      input ->
        value = String.trim(input)

        request =
          if String.match?(value, ~r/\A[0-9]{4}\z/) do
            "GUESS " <> value
          else
            String.upcase(value)
          end

        case :gen_tcp.send(socket, request <> "\n") do
          :ok ->
            case :gen_tcp.recv(socket, 0, 5_000) do
              {:ok, response} ->
                response = String.trim_trailing(response)
                IO.puts(response)

                if String.starts_with?(response, "WIN ") or response == "BYE" do
                  :gen_tcp.close(socket)
                else
                  loop(socket)
                end

              {:error, reason} ->
                IO.puts("Server disconnected: #{inspect(reason)}")
                :gen_tcp.close(socket)
            end

          {:error, reason} ->
            IO.puts("Send error: #{inspect(reason)}")
            :gen_tcp.close(socket)
        end
    end
  end
end

BullsCows.Client.start()
