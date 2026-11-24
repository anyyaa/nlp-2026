defmodule BullsCows.Game do
  def new_secret do
    first = Enum.random(1..9)

    rest =
      0..9
      |> Enum.reject(&(&1 == first))
      |> Enum.take_random(3)

    [first | rest]
    |> Enum.map(&Integer.to_string/1)
    |> Enum.join()
  end

  def valid_guess?(guess) when is_binary(guess) do
    String.match?(guess, ~r/\A[0-9]{4}\z/) and
      (guess |> String.graphemes() |> Enum.uniq() |> length()) == 4
  end

  def valid_guess?(_), do: false

  def score(secret, guess) do
    secret_digits = String.graphemes(secret)
    guess_digits = String.graphemes(guess)

    bulls =
      Enum.zip(secret_digits, guess_digits)
      |> Enum.count(fn {a, b} -> a == b end)

    common =
      secret_digits
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(guess_digits))
      |> MapSet.size()

    {bulls, common - bulls}
  end

  def command(secret, attempts, raw_line) do
    case String.trim(raw_line) do
      "HELP" ->
        {:reply, "HELP Send GUESS 1234, HELP or QUIT. Digits must be distinct.\n", attempts}

      "QUIT" ->
        {:close, "BYE\n"}

      "GUESS " <> guess ->
        if valid_guess?(guess) do
          new_attempts = attempts + 1
          {bulls, cows} = score(secret, guess)

          if bulls == 4 do
            {:close, "WIN #{new_attempts}\n"}
          else
            {:reply, "RESULT #{bulls} #{cows} #{new_attempts}\n", new_attempts}
          end
        else
          {:reply, "ERROR Enter four different digits.\n", attempts}
        end

      _ ->
        {:reply, "ERROR Unknown command. Try HELP.\n", attempts}
    end
  end
end
