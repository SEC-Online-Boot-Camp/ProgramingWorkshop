defmodule DatabaseMission.SqlCheck do
  @moduledoc """
  ターミナルに打ったSQLの、ミスを見つけやすくするための調べもの。

    * `find_fullwidth/1` ... 実行する前に、'…' の外にある全角の記号（空白・カンマ・括弧・
      セミコロン・イコール・クォート）を探す。SQLiteは、これらでミスと違う場所を指す
      エラーを出すことがあるので、SQLiteに渡さずに止めて、場所を示す。
      '…' の中（'付箋' など、値としての全角文字）は対象外。
    * `error_hints/1` ... SQLiteの英語のエラーに、日本語の手がかりを付ける。
      UNIQUE・NOT NULL・CHECK などの制約のエラーには付けない（受講者がエラーを読むのが狙いのため）。
  """

  # 文字 => 画面に出す名前。IMEの日本語入力で、半角の代わりに打ってしまいやすいもの
  @fullwidth %{
    "　" => "全角スペース",
    "，" => "全角のカンマ「，」",
    "、" => "読点「、」",
    "（" => "全角の括弧「（」",
    "）" => "全角の括弧「）」",
    "；" => "全角のセミコロン「；」",
    "＝" => "全角のイコール「＝」",
    "‘" => "全角のクォート「‘」",
    "’" => "全角のクォート「’」",
    "＇" => "全角のクォート「＇」",
    "“" => "全角のクォート「“」",
    "”" => "全角のクォート「”」",
    "＂" => "全角のクォート「＂」"
  }

  @doc """
  '…' の外にある最初の全角の記号を探す。なければ nil。

  位置は1から数える。`index` はSQL全体での文字の位置、`line`・`col` は行と、その行の中の位置。
  """
  def find_fullwidth(sql) do
    sql
    |> String.graphemes()
    |> Enum.reduce_while({false, 1, 1, 1}, fn ch, {quoted, index, line, col} ->
      cond do
        ch == "'" ->
          {:cont, {not quoted, index + 1, line, col + 1}}

        ch == "\n" ->
          {:cont, {quoted, index + 1, line + 1, 1}}

        not quoted and Map.has_key?(@fullwidth, ch) ->
          {:halt, %{char: ch, name: @fullwidth[ch], index: index, line: line, col: col}}

        true ->
          {:cont, {quoted, index + 1, line, col + 1}}
      end
    end)
    |> case do
      %{} = found -> found
      _ -> nil
    end
  end

  @doc "`find_fullwidth/1` で見つけた場所を、画面に出す文にする。"
  def fullwidth_message(sql, %{name: name, index: index, line: line, col: col}) do
    if String.contains?(String.trim(sql), "\n"),
      do: "#{line}行目の#{col}文字目に#{name}があります",
      else: "#{index}文字目に#{name}があります"
  end

  @doc """
  エラーの文に付ける、日本語の手がかり。`{手がかりの文, 印を付ける語 | nil}` か nil。
  """
  def error_hint(message) when is_binary(message) do
    cond do
      match = Regex.run(~r/near "(.+?)": syntax error/, message) ->
        token = Enum.at(match, 1)
        {"#{token}の手前を見直してください（, の抜けや全角文字がないか）", token}

      match = Regex.run(~r/no such column: (\S+)/, message) ->
        {"#{Enum.at(match, 1)}という列はありません", nil}

      match = Regex.run(~r/table \S+ has (\d+) columns but (\d+) values were supplied/, message) ->
        [_, columns, values] = match
        {"列は#{columns}個、値は#{values}個です", nil}

      true ->
        nil
    end
  end

  def error_hint(_), do: nil

  @doc """
  SQLの中で、`token` が最初に出てくる場所。`{行の文字列, その行の中の位置（1から）}` か nil。
  """
  def locate(sql, token) do
    sql
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case :binary.match(line, token) do
        {byte, _} -> {line, String.length(binary_part(line, 0, byte)) + 1}
        :nomatch -> nil
      end
    end)
  end
end
