defmodule DatabaseMission.ParticipantTest do
  use ExUnit.Case, async: true

  alias DatabaseMission.{Missions, Participant, Sql}

  test "新しい識別子は、識別子として正しく、毎回違う" do
    ids = for _ <- 1..20, do: Participant.new_id()
    assert Enum.all?(ids, &Participant.valid?/1)
    assert length(Enum.uniq(ids)) == 20
  end

  test "ファイル名に使えない識別子は、正しくない" do
    for bad <- [
          nil,
          "",
          "short",
          "../evil_path_x",
          "a/b/c/d/e/f/g/h",
          "with space 123",
          "日本語の識別子です",
          123
        ] do
      refute Participant.valid?(bad), "正しいと判定された: #{inspect(bad)}"
    end
  end

  test "データベースのパスは、ワークスペースの中の決まった名前。正しくない識別子や、ミッションでは作れない" do
    id = Participant.new_id()
    path = Participant.db_path(id, "m2")
    assert Path.expand(Path.dirname(path)) == Path.expand(Sql.workspace())
    assert Path.basename(path) == "#{id}_m2.db"

    assert_raise ArgumentError, fn -> Participant.db_path("../evil_path_x", "m2") end
    assert_raise FunctionClauseError, fn -> Participant.db_path(id, "../m2") end
    assert_raise FunctionClauseError, fn -> Participant.db_path(id, "free") end
  end

  test "受講者のデータベースだけを消す(ほかの受講者のものは残る)" do
    mine = Participant.new_id()
    other = Participant.new_id()

    for id <- [mine, other], m <- Participant.missions() do
      {:ok, _} = Sql.new_database(Missions.m2_seed(), Participant.db_path(id, m))
    end

    assert Participant.db_exists?(mine, "m3")
    assert :ok = Participant.delete_databases(mine)

    for m <- Participant.missions() do
      refute Participant.db_exists?(mine, m)
      assert Participant.db_exists?(other, m)
    end

    Participant.delete_databases(other)
  end

  test "識別子が正しくなければ、消す処理は何もしない" do
    assert :ok = Participant.delete_databases("../evil_path_x")
    assert :ok = Participant.delete_databases(nil)
  end

  test "トピックは、受講者ごとに違う" do
    assert Participant.topic("a") != Participant.topic("b")
  end

  describe "register_member/3" do
    setup do
      id = Participant.new_id()
      {:ok, _} = Sql.new_database(Missions.m4_seed(), Participant.db_path(id, "m4"))
      on_exit(fn -> Participant.delete_databases(id) end)
      %{id: id}
    end

    test "会員を登録し、結果をPubSubで(:m4_register)として流す", %{id: id} do
      Phoenix.PubSub.subscribe(DatabaseMission.PubSub, Participant.topic(id))

      record = Participant.register_member(id, "高橋 みお", "mio@example.com")
      assert record.error == nil
      assert record.sql =~ "INSERT INTO 会員"
      assert_receive {:m4_register, ^record}

      assert {:ok, %{rows: [_]}} =
               Sql.query(
                 Participant.db_path(id, "m4"),
                 "SELECT * FROM 会員 WHERE メールアドレス = 'mio@example.com';"
               )
    end

    test "同じメールアドレスでは、UNIQUE制約のエラーになる(行は増えない)", %{id: id} do
      {:ok, before} = Sql.query(Participant.db_path(id, "m4"), "SELECT COUNT(*) FROM 会員;")

      record = Participant.register_member(id, "佐藤 さくら", "sakura@example.com")
      assert record.error =~ "UNIQUE constraint failed: 会員.メールアドレス"

      assert {:ok, ^before} = Sql.query(Participant.db_path(id, "m4"), "SELECT COUNT(*) FROM 会員;")
    end

    test "名前やメールアドレスに ' が入っていても、SQLとして壊れない" do
      id = Participant.new_id()
      {:ok, _} = Sql.new_database(Missions.m4_seed(), Participant.db_path(id, "m4"))

      record = Participant.register_member(id, "O'Reilly", "o'reilly@example.com")
      assert record.error == nil

      assert {:ok, %{rows: [["O'Reilly"]]}} =
               Sql.query(
                 Participant.db_path(id, "m4"),
                 "SELECT 名前 FROM 会員 WHERE メールアドレス = ?;",
                 ["o'reilly@example.com"]
               )

      Participant.delete_databases(id)
    end
  end
end
