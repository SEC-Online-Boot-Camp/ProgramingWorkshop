defmodule DatabaseMission.Missions do
  @moduledoc """
  各ミッションの初期データと、達成判定に使うSQL。

  スライド（resourceリポジトリ `4-短期講座/データベースの仕組み/データベースの仕組み.md`）の
  テーブル・値と一致させている。どちらかを変えるときは両方を直すこと。
  """

  @products_table """
  CREATE TABLE 商品 (
    id   INTEGER PRIMARY KEY,
    名前 TEXT    NOT NULL,
    価格 INTEGER NOT NULL,
    在庫 INTEGER NOT NULL
  );
  """

  @doc """
  SQLインジェクション: 会員テーブルの検索で実行するSQLと、`?` に渡す値を作る。
  検索するのは「名前」列（メールアドレスなど、ほかの列は検索しない）。

    * `:unsafe` ... 入力をそのままSQLの文字列に入れる。**わざと危険な作り**にしている
      （SQLインジェクションを目で見て体験するため）。実行は、読み取り専用で1文しか
      実行できない `Sql.query/3` だけで行うので、データは変更できない。
    * `:placeholder` ... 入力を `?` に値として渡す。入力はSQLの一部にならない。
  """
  def injection_query(:unsafe, input) do
    {"SELECT * FROM 会員 WHERE 名前 = '" <> input <> "';", []}
  end

  def injection_query(:placeholder, input) do
    {"SELECT * FROM 会員 WHERE 名前 = ?;", [input]}
  end

  @doc """
  SQLインジェクション: 検索の対象になる会員テーブル（読み取り専用）。
  """
  def injection_seed do
    """
    CREATE TABLE 会員 (
      id             INTEGER PRIMARY KEY,
      名前           TEXT NOT NULL,
      メールアドレス TEXT NOT NULL UNIQUE
    );
    INSERT INTO 会員 VALUES
      (1, '田中 はると', 'haruto@example.com'),
      (2, '佐藤 さくら', 'sakura@example.com'),
      (3, '鈴木 ゆい',   'yui@example.com');
    """
  end

  @doc "ミッション2: 正常な商品テーブル。"
  def m2_seed do
    @products_table <>
      "INSERT INTO 商品 VALUES (1, 'コピー用紙', 480, 24), (2, 'ボールペン', 120, 8), (3, 'ファイル', 250, 5);"
  end

  @doc "ミッション3: 先輩が `UPDATE 商品 SET 価格 = 150;` を実行してしまったあとの商品テーブル。"
  def m3_seed do
    @products_table <>
      "INSERT INTO 商品 VALUES (1, 'コピー用紙', 150, 24), (2, 'ボールペン', 150, 8), (3, 'ファイル', 150, 5);"
  end

  @doc """
  ミッション4: メールアドレスに UNIQUE 制約が付いた会員テーブル。

  会員2（佐藤 さくら）は、以前に退会した（退会=1）のに、データが残っている。
  お客さんが同じメールアドレスで登録しようとして、UNIQUE制約のエラーになる。
  """
  def m4_seed do
    """
    CREATE TABLE 会員 (
      id             INTEGER PRIMARY KEY,
      名前           TEXT NOT NULL,
      メールアドレス TEXT NOT NULL UNIQUE,
      退会           INTEGER NOT NULL DEFAULT 0 CHECK (退会 IN (0, 1))
    );
    INSERT INTO 会員 (id, 名前, メールアドレス, 退会) VALUES
      (1, '田中 はると', 'haruto@example.com', 0),
      (2, '佐藤 さくら', 'sakura@example.com', 1),
      (3, '鈴木 ゆい',   'yui@example.com',    0);
    """
  end

  @doc "ミッション3の先輩が実行したSQL。"
  def m3_mistake_sql, do: "UPDATE 商品 SET 価格 = 150;"

  @doc "ミッション4で登録しようとしているお客さん（会員2と同じメールアドレス）。"
  def m4_customer, do: %{name: "佐藤 さくら", email: "sakura@example.com"}

  @doc "テーブルの中身を表示するためのSELECT。"
  def products_snapshot_sql, do: "SELECT * FROM 商品 ORDER BY id"

  @doc "ミッション2の課題2の正解（在庫が10個未満の商品）。"
  def m2_low_stock_sql, do: "SELECT * FROM 商品 WHERE 在庫 < 10"

  @doc "ミッション2の課題1・4: 新商品「付箋」の行があるか。"
  def m2_inserted_sql, do: "SELECT 1 FROM 商品 WHERE 名前 = '付箋' AND 価格 = 200 AND 在庫 = 12"

  @doc """
  ミッション2の課題3: コピー用紙（id=1）の在庫が30になっていて、ほかの行の名前・価格・在庫が
  初期データのままか（付箋の行があってもなくてもよい）。
  """
  def m2_updated_sql do
    """
    SELECT 1
    WHERE (SELECT COUNT(*) FROM 商品
           WHERE id = 1 AND 名前 = 'コピー用紙' AND 価格 = 480 AND 在庫 = 30) = 1
      AND (SELECT COUNT(*) FROM 商品
           WHERE (id = 2 AND 名前 = 'ボールペン' AND 価格 = 120 AND 在庫 = 8)
              OR (id = 3 AND 名前 = 'ファイル' AND 価格 = 250 AND 在庫 = 5)) = 2
    """
  end

  @doc "ミッション3: 3つの商品が正しい価格に戻り、ほかの行が増減していないか。"
  def m3_fixed_sql do
    """
    SELECT 1
    WHERE (SELECT COUNT(*) FROM 商品) = 3
      AND (SELECT COUNT(*) FROM 商品
           WHERE (id = 1 AND 名前 = 'コピー用紙' AND 価格 = 480)
              OR (id = 2 AND 名前 = 'ボールペン' AND 価格 = 150)
              OR (id = 3 AND 名前 = 'ファイル' AND 価格 = 250)) = 3
    """
  end
end
