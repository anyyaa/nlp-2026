Code.require_file("game.exs", __DIR__)
Code.require_file("server_core.exs", __DIR__)

ExUnit.start()

defmodule BullsCowsTest do
  use ExUnit.Case, async: false

  alias BullsCows.Game
  alias BullsCows.Server

  test "secret has four different digits" do
    secret = Game.new_secret()
    assert Game.valid_guess?(secret)
  end

  test "secret does not start with zero" do
    assert String.first(Game.new_secret()) != "0"
  end

  test "four distinct digits are accepted" do
    assert Game.valid_guess?("0123")
    assert Game.valid_guess?("9876")
  end

  test "repeated digits are rejected" do
    refute Game.valid_guess?("1123")
  end

  test "letters and wrong lengths are rejected" do
    refute Game.valid_guess?("123")
    refute Game.valid_guess?("12345")
    refute Game.valid_guess?("12a4")
  end

  test "four bulls" do
    assert Game.score("1234", "1234") == {4, 0}
  end

  test "four cows" do
    assert Game.score("1234", "4321") == {0, 4}
  end

  test "mixed bulls and cows" do
    assert Game.score("1234", "1243") == {2, 2}
  end

  test "no matching digits" do
    assert Game.score("1234", "5678") == {0, 0}
  end

  test "invalid guess does not increase attempts" do
    assert Game.command("1234", 2, "GUESS 1123") ==
             {:reply, "ERROR Enter four different digits.\n", 2}
  end

  test "valid guess increases attempts" do
    assert Game.command("1234", 2, "GUESS 5678") ==
             {:reply, "RESULT 0 0 3\n", 3}
  end

  test "help returns instructions" do
    assert {:reply, message, 0} = Game.command("1234", 0, "HELP")
    assert String.starts_with?(message, "HELP ")
  end

  test "quit ends the session" do
    assert Game.command("1234", 0, "QUIT") == {:close, "BYE\n"}
  end

  test "correct guess ends the session" do
    assert Game.command("1234", 3, "GUESS 1234") == {:close, "WIN 4\n"}
  end

  test "each TCP client has an independent secret and attempt counter" do
    with_server(fn index -> if index == 0, do: "1234", else: "5678" end, fn port ->
      first = connect(port)
      second = connect(port)

      assert line(first) =~ "WELCOME"
      assert line(second) =~ "WELCOME"

      send_line(first, "GUESS 1234")
      assert line(first) == "WIN 1\n"

      send_line(second, "GUESS 1234")
      assert line(second) == "RESULT 0 0 1\n"

      send_line(second, "GUESS 5678")
      assert line(second) == "WIN 2\n"

      :gen_tcp.close(first)
      :gen_tcp.close(second)
    end)
  end

  test "clients can stay connected simultaneously" do
    with_server(fn _ -> "1234" end, fn port ->
      first = connect(port)
      second = connect(port)

      assert line(first) =~ "WELCOME"
      assert line(second) =~ "WELCOME"

      send_line(first, "GUESS 5678")
      send_line(second, "HELP")

      assert line(first) == "RESULT 0 0 1\n"
      assert line(second) =~ "HELP "

      send_line(first, "GUESS 4321")
      assert line(first) == "RESULT 0 4 2\n"

      send_line(second, "QUIT")
      assert line(second) == "BYE\n"

      :gen_tcp.close(first)
      :gen_tcp.close(second)
    end)
  end

  defp with_server(secret_factory, fun) do
    {:ok, listener, port, acceptor} = Server.start(0, secret_factory)

    try do
      fun.(port)
    after
      :gen_tcp.close(listener)
      Process.exit(acceptor, :kill)
    end
  end

  defp connect(port) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :line, active: false], 2_000)

    socket
  end

  defp send_line(socket, command) do
    :ok = :gen_tcp.send(socket, command <> "\n")
  end

  defp line(socket) do
    {:ok, result} = :gen_tcp.recv(socket, 0, 2_000)
    result
  end
end
