defmodule DatabaseMission.SqlCheckTest do
  use ExUnit.Case, async: true

  alias DatabaseMission.SqlCheck

  describe "find_fullwidth/1（'…' の外の全角の記号）" do
    test "全角スペース・カンマ・読点・括弧・セミコロン・イコール・クォートを見つける" do
      for {sql, char} <- [
            {"SELECT * FROM 商品　WHERE id = 1;", "　"},
            {"SELECT 名前，価格 FROM 商品;", "，"},
            {"SELECT 名前、価格 FROM 商品;", "、"},
            {"INSERT INTO 商品 VALUES （4, 'a', 1, 1);", "（"},
            {"INSERT INTO 商品 VALUES (4, 'a', 1, 1）;", "）"},
            {"SELECT * FROM 商品；", "；"},
            {"SELECT * FROM 商品 WHERE id ＝ 1;", "＝"},
            {"SELECT * FROM 商品 WHERE 名前 = ’付箋’;", "’"},
            {"SELECT * FROM 商品 WHERE 名前 = ‘付箋’;", "‘"},
            {"SELECT * FROM 商品 WHERE 名前 = ”付箋”;", "”"},
            {"SELECT * FROM 商品 WHERE 名前 = “付箋“;", "“"},
            {"SELECT * FROM 商品 WHERE 名前 = ＇付箋＇;", "＇"},
            {"SELECT * FROM 商品 WHERE 名前 = ＂付箋＂;", "＂"}
          ] do
        assert %{char: ^char} = SqlCheck.find_fullwidth(sql), "見つからない: #{sql}"
      end
    end

    test "'…' の中の全角文字は対象外。正しいSQLは nil" do
      assert SqlCheck.find_fullwidth("SELECT * FROM 商品 WHERE 名前 = '付箋';") == nil
      assert SqlCheck.find_fullwidth("SELECT * FROM 会員 WHERE 名前 = '田中　はると';") == nil
      assert SqlCheck.find_fullwidth("SELECT * FROM 会員 WHERE 名前 = '（株）、；＝';") == nil

      # '' (クォートの中のクォート) のあとも、正しく '…' の中と外を数える
      assert SqlCheck.find_fullwidth("SELECT 'it''s　ok';") == nil
      assert %{char: "　"} = SqlCheck.find_fullwidth("SELECT 'it''s'　;")
    end

    test "位置は1から数える。2行目以降は、行と、その行の中の位置" do
      assert %{index: 17, line: 1, col: 17, name: "全角スペース"} =
               SqlCheck.find_fullwidth("SELECT * FROM 商品　WHERE id = 1;")

      sql = "SELECT *\nFROM 商品（"
      found = SqlCheck.find_fullwidth(sql)
      assert %{line: 2, col: 8, name: "全角の括弧「（」"} = found
      assert SqlCheck.fullwidth_message(sql, found) == "2行目の8文字目に全角の括弧「（」があります"

      sql = "SELECT * FROM 商品　WHERE id = 1;"

      assert SqlCheck.fullwidth_message(sql, SqlCheck.find_fullwidth(sql)) ==
               "17文字目に全角スペースがあります"
    end
  end

  describe "error_hint/1（エラーの日本語の手がかり）" do
    test "near \"X\": syntax error には、Xの手前を見直す手がかりと、印を付ける語" do
      assert SqlCheck.error_hint(~s(near "FROM": syntax error)) ==
               {"FROMの手前を見直してください（, の抜けや全角文字がないか）", "FROM"}
    end

    test "no such column と、列と値の数の違い" do
      assert SqlCheck.error_hint("no such column: 値段") == {"値段という列はありません", nil}

      assert SqlCheck.error_hint("table 商品 has 4 columns but 3 values were supplied") ==
               {"列は4個、値は3個です", nil}
    end

    test "UNIQUE・NOT NULL・CHECK の制約のエラーには付けない" do
      for message <- [
            "UNIQUE constraint failed: 会員.メールアドレス",
            "NOT NULL constraint failed: 会員.名前",
            "CHECK constraint failed: 退会 IN (0, 1)",
            "no such table: 果物"
          ] do
        assert SqlCheck.error_hint(message) == nil, "付いてしまう: #{message}"
      end
    end

    test "locate/2 は、語が最初に出てくる行と、その行の中の位置を返す" do
      assert SqlCheck.locate("SELECT 名前 価格\nFROM 商品 FROM", "FROM") == {"FROM 商品 FROM", 1}
      assert SqlCheck.locate("SELECT * 商品 WHERE", "WHERE") == {"SELECT * 商品 WHERE", 13}
      assert SqlCheck.locate("SELECT 1;", "missing") == nil
    end
  end
end
