defmodule CodebreakingMission.Ciphers do
  @moduledoc """
  暗号解読ミッション（ミッション1〜4）で使う暗号ロジック。

  すべて純粋関数で、Python実行やOllamaとは無関係。`MissionLive`から
  呼ばれる想定だが、単体テスト（`ciphers_test.exs`）で暗号ロジックだけを
  独立して検証できるようにこのモジュールに切り出している。
  """

  @hiragana "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
  @alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

  def hiragana, do: @hiragana
  def alphabet, do: @alphabet

  @doc """
  任意の文字集合（既定はひらがな五十音）上でのシーザー復号。
  集合にない文字（濁点・記号・空白など）はそのまま通す。
  """
  def caesar_decode(text, shift, alphabet \\ @hiragana), do: caesar_shift(text, -shift, alphabet)

  @doc "任意の文字集合上でのシーザー暗号化（`caesar_decode/3`の鏡像）。"
  def caesar_encode(text, shift, alphabet \\ @hiragana), do: caesar_shift(text, shift, alphabet)

  defp caesar_shift(text, shift, alphabet) do
    chars = String.graphemes(alphabet)
    n = length(chars)
    index_of = chars |> Enum.with_index() |> Map.new()

    text
    |> String.graphemes()
    |> Enum.map(fn c ->
      case Map.fetch(index_of, c) do
        {:ok, i} -> Enum.at(chars, Integer.mod(i + shift, n))
        :error -> c
      end
    end)
    |> Enum.join()
  end

  @doc "アルファベット専用のシーザー復号。大文字・小文字を保持し、非アルファベットはそのまま。"
  def caesar_decode_alpha(text, shift), do: caesar_shift_alpha(text, -shift)

  @doc "アルファベット専用のシーザー暗号化（`caesar_decode_alpha/2`の鏡像）。"
  def caesar_encode_alpha(text, shift), do: caesar_shift_alpha(text, shift)

  defp caesar_shift_alpha(text, shift) do
    text
    |> String.to_charlist()
    |> Enum.map(fn c ->
      cond do
        c in ?A..?Z -> Integer.mod(c - ?A + shift, 26) + ?A
        c in ?a..?z -> Integer.mod(c - ?a + shift, 26) + ?a
        true -> c
      end
    end)
    |> List.to_string()
  end

  @doc "鍵0からlimit-1までを総当たりし、`{k, decoded}`のリストを返す。"
  def brute_force(text, limit) do
    upper = max(limit, 1) - 1
    for k <- 0..upper, do: {k, caesar_decode_alpha(text, k)}
  end

  @doc """
  出現回数を多い順に返す（A〜Zのみ集計、大文字小文字は区別しない）。

      iex> letter_frequency("ZIT")
      [{"T", 1}, {"I", 1}, {"Z", 1}]
  """
  def letter_frequency(text) do
    text
    |> String.upcase()
    |> String.graphemes()
    |> Enum.filter(&(&1 =~ ~r/^[A-Z]$/))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_char, count} -> -count end)
  end

  @doc """
  換字式暗号の対応表適用プレビュー。`mapping`は`%{"T" => "E", ...}`
  （暗号文字→平文字、いずれも大文字1文字）。

  元の文字の大文字・小文字は保持する（暗号文が小文字なら平文も小文字で返す）。
  文字ごとに`{元の文字, 平文字またはnil（未確定）}`のタプルのリストを返す。
  改行・空白・記号はそのまま`{c, c}`として通す。
  """
  def substitution_preview(text, mapping) do
    text
    |> String.graphemes()
    |> Enum.map(fn c ->
      up = String.upcase(c)

      case Map.get(mapping, up) do
        nil -> if up =~ ~r/^[A-Z]$/, do: {c, nil}, else: {c, c}
        plain -> if up == c, do: {c, plain}, else: {c, String.downcase(plain)}
      end
    end)
  end

  @doc "ヴィジュネル復号。鍵はアルファベット以外を除去して正規化する。"
  def vigenere_decode(text, key), do: vigenere_shift(text, key, -1)

  @doc "ヴィジュネル暗号化（`vigenere_decode/2`の鏡像）。"
  def vigenere_encode(text, key), do: vigenere_shift(text, key, 1)

  defp vigenere_shift(_text, key, _dir) when is_binary(key) and byte_size(key) == 0, do: ""

  defp vigenere_shift(text, key, dir) do
    normalized_key = key |> String.upcase() |> String.replace(~r/[^A-Z]/, "")

    if normalized_key == "" do
      ""
    else
      key_chars = String.to_charlist(normalized_key)
      key_len = length(key_chars)

      text
      |> String.to_charlist()
      |> Enum.map_reduce(0, fn c, key_index ->
        shift_for = fn -> Enum.at(key_chars, rem(key_index, key_len)) - ?A end

        cond do
          c in ?A..?Z -> {Integer.mod(c - ?A + dir * shift_for.(), 26) + ?A, key_index + 1}
          c in ?a..?z -> {Integer.mod(c - ?a + dir * shift_for.(), 26) + ?a, key_index + 1}
          true -> {c, key_index}
        end
      end)
      |> elem(0)
      |> List.to_string()
    end
  end
end
