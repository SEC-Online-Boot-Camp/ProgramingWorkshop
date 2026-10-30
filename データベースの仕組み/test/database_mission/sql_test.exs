defmodule DatabaseMission.SqlTest do
  use ExUnit.Case, async: true

  alias DatabaseMission.{Missions, Sql}

  setup do
    {:ok, db} = Sql.new_database(Missions.m2_seed())
    on_exit(fn -> Sql.delete_database(db) end)
    %{db: db}
  end

  test "SELECT の結果を列名と行で返す", %{db: db} do
    assert {:ok, %{results: [result], error: nil}} =
             Sql.run(db, "SELECT 名前, 価格 FROM 商品 WHERE id = 2;")

    assert result.type == :rows
    assert result.columns == ["名前", "価格"]
    assert result.rows == [["ボールペン", 120]]
  end

  test "複数の命令を順に実行し、変更した行数を返す", %{db: db} do
    sql = """
    UPDATE 商品 SET 価格 = 150;
    SELECT 価格 FROM 商品 ORDER BY id;
    """

    assert {:ok, %{results: [update, select]}} = Sql.run(db, sql)
    assert update == %{sql: "UPDATE 商品 SET 価格 = 150;", type: :change, count: 3}
    assert select.rows == [[150], [150], [150]]
  end

  test "文字列の中のセミコロンでは区切らない", %{db: db} do
    assert {:ok, %{results: [_insert, select], error: nil}} =
             Sql.run(
               db,
               "INSERT INTO 商品 VALUES (4, '付;箋', 200, 12); SELECT 名前 FROM 商品 WHERE id = 4;"
             )

    assert select.rows == [["付;箋"]]
  end

  test "エラーが出た命令で止まり、エラーメッセージを返す", %{db: db} do
    assert {:ok, %{results: [_], error: error}} =
             Sql.run(db, "SELECT 1; SELECT * FROM 商品s; SELECT 2;")

    assert error.sql == "SELECT * FROM 商品s;"
    assert error.message =~ "no such table"
  end

  test "UNIQUE 制約に違反すると SQLite のエラーメッセージがそのまま返る" do
    {:ok, db} = Sql.new_database(Missions.m4_seed())

    sql = "INSERT INTO 会員 (名前, メールアドレス) VALUES ('佐藤 さくら', 'sakura@example.com');"
    assert {:ok, %{error: %{message: message}}} = Sql.run(db, sql)
    assert message == "UNIQUE constraint failed: 会員.メールアドレス"

    Sql.delete_database(db)
  end

  test "track は1文ごとに調べ、途中で一度でも行が返れば true になる", %{db: db} do
    track = ["SELECT 1 FROM 商品 WHERE 名前 = '付箋'"]

    # INSERTしてすぐDELETEしても、途中の状態から true になる(最後の状態には付箋がない)
    sql = "INSERT INTO 商品 VALUES (4, '付箋', 200, 12); DELETE FROM 商品 WHERE id = 4;"

    assert {:ok, %{tracked: [true], extras: [last]}} =
             Sql.run(db, sql, [Missions.products_snapshot_sql()], track)

    assert length(last.rows) == 3

    # 付箋が一度もできなければ false
    {:ok, db2} = Sql.new_database(Missions.m2_seed())
    assert {:ok, %{tracked: [false]}} = Sql.run(db2, "SELECT * FROM 商品;", [], track)
    Sql.delete_database(db2)

    # 指定しなければ空
    assert {:ok, %{tracked: []}} = Sql.run(db, "SELECT 1;")
  end

  test "extras は受講者のSQLのあとに実行され、エラーの行は nil になる", %{db: db} do
    assert {:ok, %{extras: [count, nil]}} =
             Sql.run(db, "DELETE FROM 商品 WHERE id = 1;", [
               "SELECT COUNT(*) FROM 商品",
               "SELECT * FROM なし"
             ])

    assert count.rows == [[2]]
  end

  test "終わらないSQLは中断する", %{db: db} do
    sql =
      "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c) SELECT COUNT(*) FROM c;"

    assert {:ok, %{error: %{message: message}}} = Sql.run(db, sql)
    assert message =~ "interrupted"
  end

  describe "new_database/2（場所の指定）" do
    test "場所を指定すると、そこに作り、同じ名前があれば作り直す" do
      path = Path.join(Sql.workspace(), "sql_test_fixed_#{System.unique_integer([:positive])}.db")
      on_exit(fn -> Sql.delete_database(path) end)

      assert {:ok, ^path} = Sql.new_database(Missions.m2_seed(), path)
      assert {:ok, _} = Sql.run(path, "INSERT INTO 商品 VALUES (4, '付箋', 200, 12);")
      assert {:ok, %{rows: [[4]]}} = Sql.query(path, "SELECT COUNT(*) FROM 商品;")

      # 作り直すと、初期データに戻る
      assert {:ok, ^path} = Sql.new_database(Missions.m2_seed(), path)
      assert {:ok, %{rows: [[3]]}} = Sql.query(path, "SELECT COUNT(*) FROM 商品;")
    end
  end

  describe "query/3（読み取り専用で1文のSELECTを実行）" do
    test "SELECTの結果を返し、? には値として渡せる", %{db: db} do
      assert {:ok, %{columns: ["id", "名前", "価格", "在庫"], rows: [[2, "ボールペン", 120, 8]]}} =
               Sql.query(db, "SELECT * FROM 商品 WHERE 名前 = ?;", ["ボールペン"])

      # 値として渡した文字列は、SQLの一部にならない
      assert {:ok, %{rows: []}} =
               Sql.query(db, "SELECT * FROM 商品 WHERE 名前 = ?;", ["' OR '1'='1"])

      # 文字列に入れた場合は、SQLの一部になる(SQLインジェクション)
      assert {:ok, %{rows: rows}} =
               Sql.query(db, "SELECT * FROM 商品 WHERE 名前 = '' OR '1'='1';")

      assert length(rows) == 3
    end

    test "INSERT・UPDATE・DELETE・DROP・ATTACH などは拒否され、データは変わらない", %{db: db} do
      for sql <- [
            "INSERT INTO 商品 VALUES (4, '付箋', 200, 12);",
            "UPDATE 商品 SET 価格 = 1;",
            "DELETE FROM 商品;",
            "DROP TABLE 商品;",
            "ATTACH DATABASE 'other.db' AS other;",
            "PRAGMA query_only = OFF;"
          ] do
        assert {:error, message} = Sql.query(db, sql)

        assert message =~ "not authorized" or message =~ "readonly",
               "拒否されていない: #{sql} → #{message}"
      end

      assert {:ok, %{rows: [[3]]}} = Sql.query(db, "SELECT COUNT(*) FROM 商品;")

      assert {:ok, %{results: [%{rows: [[480]]}]}} =
               Sql.run(db, "SELECT 価格 FROM 商品 WHERE id = 1;")
    end

    test "複数の文は実行できない", %{db: db} do
      assert {:error, message} = Sql.query(db, "SELECT 1; DELETE FROM 商品;")
      assert message =~ "one statement"
      assert {:ok, %{rows: [[3]]}} = Sql.query(db, "SELECT COUNT(*) FROM 商品;")
    end

    test "構文エラーは、SQLiteのエラー文をそのまま返す", %{db: db} do
      assert {:error, message} = Sql.query(db, "SELECT * FROM 商品 WHERE 名前 = '")
      assert message =~ "unrecognized token" or message =~ "incomplete input"
    end

    test "結果は200行までで、終わらないSQLは中断する", %{db: db} do
      sql =
        "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c LIMIT 500) SELECT x FROM c;"

      assert {:ok, %{rows: rows, truncated: true}} = Sql.query(db, sql)
      assert length(rows) == 200

      sql =
        "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c) SELECT COUNT(*) FROM c;"

      assert {:error, message} = Sql.query(db, sql)
      assert message =~ "interrupted"
    end
  end

  test "quote_string/1 はシングルクォートを重ねる" do
    assert Sql.quote_string("O'Reilly") == "'O''Reilly'"
  end
end
