defmodule DatabaseMissionWeb.MissionLiveTest do
  use DatabaseMissionWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DatabaseMissionWeb.TestHelpers

  @moduletag :capture_log

  defp start_mission(view, tab) do
    render_click(view, "switch_tab", %{"tab" => tab})
    render_click(view, "start", %{"mission" => tab})
  end

  # ヒントの枠の「💡 ヒントを見る」を押して、中身を出す。押したあとの画面を返す
  defp open_hint(view, mission) do
    view |> element("##{mission}-hint-open") |> render_click()
  end

  defp run_sql(view, mission, sql) do
    view
    |> form("##{mission}-form", %{"sql" => sql})
    |> render_submit()

    render_async(view, 5_000)
  end

  # ターミナルの、一番新しい入出力（最後に実行したSQLと、その結果）
  defp last_entry(view, m) do
    html = render(element(view, "##{m}-history"))
    ids = for [_, n] <- Regex.scan(~r/id="#{m}-entry-(\d+)"/, html), do: String.to_integer(n)
    render(element(view, "##{m}-entry-#{Enum.max(ids)}"))
  end

  # 通販サイト（別ページ）を、同じ受講者のセッションで開き、商品のデータ（m2 / m3）を
  # 切り替えて、表示内容を返す
  defp shop(conn, source) do
    {:ok, view, _html} = live(conn, ~p"/shop")
    view |> form("#shop-source-form", %{"source" => source}) |> render_change()
    render(element(view, "#shop-products"))
  end

  # ミッション１のターミナルに、SQLを入力して実行し、実行後の画面を返す
  defp run_m2(view, sql), do: run_sql(view, "m2", sql)

  # ミッション１のターミナルの、入出力の履歴の部分
  defp m2_history(view), do: render(element(view, "#m2-history"))

  # 履歴の中での、文字列の位置(積み重なる順序の確認用)
  defp at(html, text) do
    {pos, _} = :binary.match(html, text)
    pos
  end

  test "最初に開くのはミッション１(開始ボタン)で、練習タブはない", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "システムトラブルを解決せよ！"
    assert has_element?(view, "#m2-start", "🚀 開始")
    refute has_element?(view, "#free-terminal")
    refute has_element?(view, "[role=tablist]", "練習")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#m2-start", "🚀 開始")
  end

  test "ミッションのタブを選ぶとそれぞれ開始ボタンが表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    for tab <- ~w(m2 m3 m4) do
      assert render_click(view, "switch_tab", %{"tab" => tab}) =~ "🚀 開始"
    end
  end

  test "タブは ミッション１〜４ の順で並ぶ(練習タブ・データ削除のタブはない)", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    tabs = render(element(view, "[role=tablist]"))

    assert tabs =~ ~r{ミッション１.*ミッション２.*ミッション３.*ミッション４}s

    refute tabs =~ "練習"
    refute tabs =~ ~r{ミッション４.*ミッション３}s
    refute tabs =~ "ミッション５"
    refute tabs =~ "SQLインジェクション"
    refute tabs =~ "データ削除"
    refute tabs =~ "データを消す"

    # 追加指令はタブにしない(各ミッションの画面の中に出る)。通販サイトは別ページ(/shop)
    refute tabs =~ "追加指令"
    refute tabs =~ "通販サイト"
    refute tabs =~ "考えてみよう"
  end

  test "再読み込みすると、ミッションの変更も画面の履歴も、初期状態に戻る", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m2")
    run_m2(view, "DELETE FROM 商品 WHERE id = 1;")
    run_m2(view, "SELECT * FROM 商品;")
    refute m2_history(view) =~ "コピー用紙"
    assert m2_history(view) =~ "&gt; DELETE FROM 商品 WHERE id = 1;"

    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m2")
    refute m2_history(view) =~ "&gt; DELETE"
    run_m2(view, "SELECT * FROM 商品;")
    assert m2_history(view) =~ "コピー用紙"
  end

  defp task_done?(html, text) do
    html =~ ~r{✅</span><span>\s*\d\. #{Regex.escape(text)}}
  end

  @m2_insert "新商品「付箋」（価格200円、在庫12個）を登録する"
  @m2_search "在庫が10個未満の商品を検索する"
  @m2_update "コピー用紙の在庫を30個に更新する"
  @m2_delete "「付箋」を削除する"

  describe "ミッション2の課題" do
    setup %{conn: conn} do
      conn = participant_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")
      %{view: view, conn: conn}
    end

    test "右側の通販サイト(商品の画面)は、SQLを実行すると、更新ボタンを押さなくても自動で最新になる", %{view: view} do
      shop = fn -> render(element(view, "#m2-shop")) end

      assert shop.() =~ "商品一覧"
      assert shop.() =~ "オフィスいちば"
      refute shop.() =~ "付箋"

      run_sql(view, "m2", "INSERT INTO 商品 VALUES (4, '付箋', 200, 12);")
      assert shop.() =~ "付箋"
      assert shop.() =~ "200円"

      run_sql(view, "m2", "DELETE FROM 商品 WHERE 名前 = '付箋';")
      refute shop.() =~ "付箋"
    end

    test "4つの課題を1つずつ達成すると完了になる(検索は登録の前でもよい)", %{view: view, conn: conn} do
      html = render(view)

      # 商品テーブルは画面に出さない(SELECTで調べる課題の答えが見えてしまうため)
      refute has_element?(view, "#m2-table")
      refute html =~ "通販サイトの画面"
      refute html =~ "すべての商品を表示せよ"
      refute task_done?(html, @m2_insert)

      html = run_sql(view, "m2", "SELECT * FROM 商品 WHERE 在庫 < 10;")
      assert task_done?(html, @m2_search)
      refute task_done?(html, @m2_insert)

      html = run_sql(view, "m2", "INSERT INTO 商品 VALUES (4, '付箋', 200, 12);")
      assert html =~ "1行を変更しました"
      assert task_done?(html, @m2_insert)
      refute task_done?(html, @m2_delete)
      refute html =~ "ミッション完了"

      html = run_sql(view, "m2", "UPDATE 商品 SET 在庫 = 30 WHERE id = 1;")
      assert task_done?(html, @m2_update)
      refute html =~ "ミッション完了"

      html = run_sql(view, "m2", "DELETE FROM 商品 WHERE 名前 = '付箋';")
      assert task_done?(html, @m2_delete)
      assert html =~ "ミッション完了"
      refute shop(conn, "m2") =~ "付箋"
    end

    test "削除は、付箋を登録する前では達成しない。登録は削除のあとも達成のまま", %{view: view} do
      html = run_sql(view, "m2", "DELETE FROM 商品 WHERE 名前 = '付箋';")
      refute task_done?(html, @m2_delete)

      html = run_sql(view, "m2", "INSERT INTO 商品 VALUES (4, '付箋', 200, 12);")
      assert task_done?(html, @m2_insert)
      # 付箋がまだ表にあるので、削除は未達成
      refute task_done?(html, @m2_delete)

      html = run_sql(view, "m2", "DELETE FROM 商品 WHERE id = 4;")
      assert task_done?(html, @m2_delete)
      assert task_done?(html, @m2_insert)
    end

    test "更新は、コピー用紙の在庫が30で、ほかの行が初期データのままのときだけ達成する", %{view: view} do
      html = run_sql(view, "m2", "UPDATE 商品 SET 在庫 = 31 WHERE id = 1;")
      refute task_done?(html, @m2_update)

      # 全行の在庫を30にすると、ほかの行が変わるので達成しない
      html = run_sql(view, "m2", "UPDATE 商品 SET 在庫 = 30;")
      refute task_done?(html, @m2_update)

      render_click(view, "reset", %{"mission" => "m2"})
      html = run_sql(view, "m2", "UPDATE 商品 SET 在庫 = 30 WHERE id = 1;")
      assert task_done?(html, @m2_update)
    end

    test "4つの答えを1回でまとめて実行しても、すべて達成になる", %{view: view} do
      html =
        run_sql(view, "m2", """
        INSERT INTO 商品 VALUES (4, '付箋', 200, 12);
        SELECT * FROM 商品 WHERE 在庫 < 10;
        UPDATE 商品 SET 在庫 = 30 WHERE id = 1;
        DELETE FROM 商品 WHERE 名前 = '付箋';
        """)

      for task <- [@m2_insert, @m2_search, @m2_update, @m2_delete] do
        assert task_done?(html, task), "達成になっていない: #{task}"
      end

      assert html =~ "ミッション完了"
    end

    test "まとめて実行しても、付箋を登録する前の削除では達成しない", %{view: view} do
      html =
        run_sql(view, "m2", """
        DELETE FROM 商品 WHERE 名前 = '付箋';
        INSERT INTO 商品 VALUES (4, '付箋', 200, 12);
        """)

      assert task_done?(html, @m2_insert)
      refute task_done?(html, @m2_delete)
    end

    test "最初のデータに戻すと、課題は未達成に戻る", %{view: view} do
      run_sql(view, "m2", """
      INSERT INTO 商品 VALUES (4, '付箋', 200, 12);
      DELETE FROM 商品 WHERE id = 4;
      """)

      html = render_click(view, "reset", %{"mission" => "m2"})
      refute task_done?(html, @m2_insert)
      refute task_done?(html, @m2_delete)
      refute html =~ "ミッション完了"
    end
  end

  test "ミッション2: SQLのエラーは画面に表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m2")

    html = run_sql(view, "m2", "SELECT * FROM しょうひん;")
    assert html =~ "no such table: しょうひん"
  end

  test "ミッション3: WHEREを付けて価格を戻すと復旧完了になる", %{conn: conn} do
    conn = participant_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m3")
    refute render(view) =~ "復旧完了"

    html =
      run_sql(view, "m3", """
      UPDATE 商品 SET 価格 = 480 WHERE id = 1;
      UPDATE 商品 SET 価格 = 250 WHERE id = 3;
      """)

    assert html =~ "復旧完了"
    refute has_element?(view, "#m3-table")
    assert shop(conn, "m3") =~ "250円"
  end

  test "ミッション3(画面の番号は2): 復旧したあとで追加指令の値上げをしても、✅と復旧完了は残る", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m3")

    run_sql(view, "m3", """
    UPDATE 商品 SET 価格 = 480 WHERE id = 1;
    UPDATE 商品 SET 価格 = 250 WHERE id = 3;
    """)

    # 追加指令の答え。ボールペン(在庫8)が160円になり、復旧の判定の条件からは外れる
    run_sql(view, "m3", "UPDATE 商品 SET 価格 = 価格 + 10 WHERE 在庫 < 10;")
    assert run_sql(view, "m3", "SELECT 価格 FROM 商品 WHERE id = 2;") =~ "160"

    html = render(view)
    assert html =~ "復旧完了"
    assert has_element?(view, "#m3-brief-area li.text-success", "コピー用紙480円")
    refute html =~ "⬜"
  end

  test "ミッション3: 最初のデータに戻すと、壊れた状態からやり直せる", %{conn: conn} do
    conn = participant_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m3")

    run_sql(
      view,
      "m3",
      "UPDATE 商品 SET 価格 = 480 WHERE id = 1; UPDATE 商品 SET 価格 = 250 WHERE id = 3;"
    )

    html = render_click(view, "reset", %{"mission" => "m3"})
    refute html =~ "復旧完了"
    refute shop(conn, "m3") =~ "250円"
  end

  @m4_reproduce "通販サイトの会員登録画面で、エラーを再現する"
  @m4_find "SQLで会員テーブルを調べ、原因になっている行を見つける"
  @m4_register "お客さんが登録できるようにする"

  describe "ミッション4" do
    setup %{conn: conn} do
      conn = participant_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m4")
      %{view: view, conn: conn}
    end

    # 通販サイト（別ページ）の会員登録画面で、登録ボタンを押す
    defp signup(conn, attrs \\ %{}) do
      {:ok, shop_view, _html} = live(conn, ~p"/shop")
      shop_view |> form("#signup-form", attrs) |> render_submit()
    end

    test "課題は3つ。選択式の解答欄も、画面の中の旧会員登録フォームも出ず、埋め込みの会員登録と通販サイトを開くリンクはない", %{view: view} do
      html = render(view)

      for text <- [@m4_reproduce, @m4_find, @m4_register] do
        assert html =~ text
        refute task_done?(html, text)
      end

      refute has_element?(view, "#m4-answer-form")
      refute has_element?(view, "#m4-register-form")
      refute html =~ "解答：登録できない原因は？"
      refute html =~ "会員登録画面（Web画面）"
      # 「通販サイトを開く（別ウィンドウ）」ボタンは削除した
      refute html =~ "通販サイトを開く"
      assert has_element?(view, "#m4-shop-form")
      assert has_element?(view, "#m4-server-log")
    end

    test "ミッション4の配置は、ミッション2・3と同じ左右2列(左がターミナル、右が通販サイト)。別ウィンドウのリンクはない", %{view: view} do
      html = render(view)

      assert html =~ "grid-cols-1 lg:grid-cols-2"
      refute html =~ "通販サイトを開く"

      # [ターミナル、通販サイトの会員登録画面、サーバーのログ]、の順
      {terminal_pos, _} = :binary.match(html, ~s(id="m4-terminal"))
      {signup_pos, _} = :binary.match(html, ~s(id="m4-shop-form"))
      {log_pos, _} = :binary.match(html, ~s(id="m4-server-log"))

      assert terminal_pos < signup_pos
      assert signup_pos < log_pos
    end

    test "埋め込みの会員登録画面(右側の通販サイト)で登録すると、サーバーの記録と課題の判定に反映する", %{view: view} do
      refute task_done?(render(view), @m4_reproduce)

      view
      |> form("#m4-shop-form", %{"name" => "佐藤 さくら", "email" => "sakura@example.com"})
      |> render_submit()

      # PubSub経由の自己送信を、このLiveViewが処理するのを待つ(別ページの/shopから登録する
      # 場合と同じ仕組み。登録は同じ処理(Participant.register_member)を共有している)
      html = render(view)

      # UNIQUE制約のエラーが、サーバーの記録に出て、課題1(エラー再現)が達成になる
      assert render(element(view, "#m4-server-log")) =~ "UNIQUE constraint failed: 会員.メールアドレス"
      assert task_done?(html, @m4_reproduce)
      refute task_done?(html, @m4_register)

      # 違うメールアドレスなら、課題3(登録できた)が達成になる
      view
      |> form("#m4-shop-form", %{"name" => "高橋 みお", "email" => "mio@example.com"})
      |> render_submit()

      html = render(view)
      assert task_done?(html, @m4_register)
      assert render(element(view, "#m4-server-log")) =~ "→ OK"

      # 登録の結果が出るたびに、ログの欄までスクロールする合図を送る(2回押したので2回)
      assert_push_event(view, "m4:show-server-log", %{})
      assert_push_event(view, "m4:show-server-log", %{})
      assert has_element?(view, "#m4-server-log[phx-hook]")

      # 押していないとき(タイマーが進んで描き直すとき)は、合図を送らない
      Enum.each(1..5, fn _ -> send(view.pid, {:timer_tick, "m4"}) end)
      render(view)
      refute_push_event(view, "m4:show-server-log", %{})

      # 登録した会員は、ターミナルのSQLでも確認できる
      sql = run_sql(view, "m4", "SELECT * FROM 会員 WHERE メールアドレス = 'mio@example.com';")
      assert sql =~ "高橋 みお"
    end

    test "指令書の文面(制限時間の記述はない)と、タイマーは15分(ヒントは開始直後から見られる)", %{view: view} do
      html = render(view)

      assert html =~ "原因を突き止めて、お客さんが登録できるようにせよ。"
      refute html =~ "制限時間15分"

      # 会員登録画面は同じ画面の右側にあるので、別ウィンドウの案内はない
      assert html =~ "「会員登録ができません」という声が、お客さんから届いた。"
      assert html =~ "通販サイトの会員登録画面で登録し、何が起きているか確かめよ。"
      refute html =~ "お客さんと同じように登録ボタンを押して"
      refute html =~ "別ウィンドウで開きます"
      refute html =~ "通販サイトの会員登録画面でエラーを再現し、原因を突き止めて"
      refute html =~ "制限時間10分"
      assert html =~ "15:00"

      # ヒントは待ち時間なしで、開始直後から「ヒントを見る」で開ける
      open_hint(view, "m4")
      assert has_element?(view, "#m4-hint-body", "原因がそのまま書いてある")
    end

    test "会員テーブルには退会列があり、会員2（佐藤 さくら）だけ退会済み", %{view: view} do
      run_sql(view, "m4", "SELECT id, 名前, 退会 FROM 会員 WHERE 退会 = 1;")
      result = last_entry(view, "m4")
      assert result =~ "佐藤 さくら"
      refute result =~ "田中 はると"
      refute result =~ "鈴木 ゆい"
    end

    test "通販サイトで登録するとUNIQUE制約のエラーになり、サーバーの記録に出て、課題1が達成になる", %{view: view, conn: conn} do
      html = signup(conn)
      assert html =~ "登録できませんでした。しばらくしてからお試しください。"

      html = render(view)
      assert task_done?(html, @m4_reproduce)
      refute task_done?(html, @m4_register)

      record = render(element(view, "#m4-server-log"))
      assert record =~ "UNIQUE constraint failed: 会員.メールアドレス"
    end

    test "SELECTで会員テーブルを調べて、原因になっている行を見つけると課題2が達成になる", %{view: view} do
      html = run_sql(view, "m4", "SELECT * FROM 会員 WHERE メールアドレス = 'sakura@example.com';")
      assert task_done?(html, @m4_find)
    end

    test "削除しただけでは課題3は達成せず、通販サイトで登録に成功すると達成して、3つ達成で完了になる", %{view: view, conn: conn} do
      signup(conn)
      run_sql(view, "m4", "SELECT * FROM 会員;")
      refute render(view) =~ "ミッション完了"

      # 古い会員データを消しただけでは、課題3は達成しない
      html = run_sql(view, "m4", "DELETE FROM 会員 WHERE id = 2;")
      refute task_done?(html, @m4_register)
      refute html =~ "ミッション完了"

      # 通販サイトで、お客さんと同じ登録をすると、成功する
      assert signup(conn) =~ "登録できました"
      html = render(view)
      assert task_done?(html, @m4_register)
      assert task_done?(html, @m4_reproduce)
      assert task_done?(html, @m4_find)
      assert html =~ "ミッション完了"
      assert html =~ "UNIQUE制約"
    end

    test "解答例: 退会した人の個人情報を消す(行は残す)と、通販サイトで登録できて、3つ達成で完了になる", %{view: view, conn: conn} do
      signup(conn)
      run_sql(view, "m4", "SELECT * FROM 会員;")

      html =
        run_sql(view, "m4", "UPDATE 会員 SET 名前 = '退会済み', メールアドレス = '' WHERE 退会 = 1;")

      assert html =~ "1行を変更しました"
      refute task_done?(html, @m4_register)

      assert signup(conn) =~ "登録できました"
      html = render(view)

      for task <- [@m4_reproduce, @m4_find, @m4_register] do
        assert task_done?(html, task), "未達成: #{task}"
      end

      refute html =~ "⬜"
      assert html =~ "ミッション完了"

      # 退会した人の行は残り、個人情報だけが消えている。お客さんは新しい行として登録された
      run_sql(view, "m4", "SELECT id, 名前, メールアドレス, 退会 FROM 会員 ORDER BY id;")
      result = last_entry(view, "m4")
      assert result =~ ~r/2\s+退会済み\s+1/
      assert result =~ ~r/4\s+佐藤 さくら\s+sakura@example.com\s+0/
    end

    test "古い会員のメールアドレスを書き換えても、通販サイトで登録できる", %{view: view, conn: conn} do
      run_sql(view, "m4", "UPDATE 会員 SET メールアドレス = 'old@example.com' WHERE id = 2;")
      assert signup(conn) =~ "登録できました"
      assert task_done?(render(view), @m4_register)
    end

    test "登録の成功は、課題1・2が未達成でも、課題3だけが達成になる(完了にはならない)", %{view: view, conn: conn} do
      assert signup(conn, %{"email" => "new@example.com"}) =~ "登録できました"

      html = render(view)
      assert task_done?(html, @m4_register)
      refute task_done?(html, @m4_reproduce)
      refute task_done?(html, @m4_find)
      refute html =~ "ミッション完了"
    end

    test "最初のデータに戻すと、会員テーブルも課題も初期状態に戻る(退会列つき)", %{view: view, conn: conn} do
      signup(conn)
      run_sql(view, "m4", "SELECT * FROM 会員 WHERE メールアドレス = 'sakura@example.com';")
      run_sql(view, "m4", "DELETE FROM 会員 WHERE id = 2;")
      assert signup(conn) =~ "登録できました"
      assert render(view) =~ "ミッション完了"

      html = render_click(view, "reset", %{"mission" => "m4"})
      for text <- [@m4_reproduce, @m4_find, @m4_register], do: refute(task_done?(html, text))
      refute html =~ "ミッション完了"
      refute render(element(view, "#m4-server-log")) =~ "INSERT INTO"

      # 会員2（退会済み）も戻っていて、同じ登録は、また失敗する
      html = run_sql(view, "m4", "SELECT 名前, 退会 FROM 会員 WHERE id = 2;")
      assert html =~ "佐藤 さくら"
      assert signup(conn) =~ "登録できませんでした"
    end
  end

  describe "ターミナル(ミッション１の画面で確かめる。ミッション１〜３で共通)" do
    defp open_m2_terminal(conn) do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")
      view
    end

    test "黒地・等幅のターミナルで、実行ボタンと下の操作説明・使い方の案内文はない", %{conn: conn} do
      view = open_m2_terminal(conn)
      html = render(view)

      assert has_element?(view, "#m2-terminal.bg-black.terminal-font")
      assert html =~ "&gt;"

      # 「▶ 実行」ボタンと、ターミナルの下の操作説明はない(実行はEnter・Ctrl+Enterのみ)
      refute has_element?(view, "#m2-help")
      refute html =~ "▶ 実行"
      refute html =~ "最後に ; を付けて Enter で実行"

      assert has_element?(view, "button", "最初のデータに戻す")
      assert has_element?(view, "button", "画面を消去")

      refute has_element?(view, "#m2-intro")
      refute html =~ "SQLを入力して、最後に「;」を付けて Enter を押すと実行します。"
    end

    test "ミッションのターミナルには、使い方の案内文は出ない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m2 m3 m4) do
        start_mission(view, m)
        refute has_element?(view, "##{m}-intro")
        refute render(view) =~ "最後に「;」を付けて Enter を押すと実行します"
      end
    end

    test "入力欄は、最後に実行した結果のすぐ下、一番下の履歴として表示される(普通のターミナルと同じ流れ)", %{conn: conn} do
      view = open_m2_terminal(conn)

      # 入力フォームは履歴の中(スクロール領域の内側)にあり、外の別領域ではない
      assert has_element?(view, "#m2-history #m2-form")

      run_m2(view, "SELECT * FROM 商品;")
      run_m2(view, "SELECT 1 AS n;")

      html = m2_history(view)

      # 最後に実行した結果(n=1)より下に、次の入力欄(空のフォーム)が続く
      assert at(html, "n\n-\n1") < at(html, ~s(id="m2-form"))
    end

    test "SELECT・INSERT・エラーになるSQLを順に実行すると、3つとも上から順に積み重なる", %{conn: conn} do
      view = open_m2_terminal(conn)

      run_m2(view, "SELECT * FROM 商品;")
      run_m2(view, "INSERT INTO 商品 VALUES (4, 'ホッチキス', 600, 6);")
      run_m2(view, "SELECT * FROM 果物;")

      html = m2_history(view)

      # 打ったSQL(プロンプトつき)が、順に残っている(古い入出力も残る)
      assert at(html, "&gt; SELECT * FROM 商品;") <
               at(html, "&gt; INSERT INTO 商品 VALUES")

      assert at(html, "&gt; INSERT INTO 商品 VALUES") <
               at(html, "&gt; SELECT * FROM 果物;")

      # それぞれの結果: 表、変更の行数、エラー
      assert at(html, "コピー用紙") < at(html, "1行を変更しました")
      assert at(html, "1行を変更しました") < at(html, "エラー: no such table: 果物")
      assert at(html, "&gt; SELECT * FROM 商品;") < at(html, "コピー用紙")

      # エラーは赤字
      assert has_element?(view, "#m2-history pre.text-red-400", "no such table: 果物")
      refute has_element?(view, "#m2-history pre.text-red-400", "コピー用紙")
    end

    test "結果の表は、見出し・区切り・行のテキストの表で、全角も揃う", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "SELECT * FROM 商品 ORDER BY id;")
      html = m2_history(view)

      assert html =~ "id  名前        価格  在庫"
      assert html =~ "--  ----------  ----  ----"
      assert html =~ "1   コピー用紙  480   24"
      assert html =~ "2   ボールペン  120   8"
      assert html =~ "3   ファイル    250   5"
    end

    test "複数行の入力は、2行目以降に継続のプロンプトが付く。複数の文は、順に結果が出る", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "SELECT 1 AS a;\nSELECT 2 AS b;")
      html = m2_history(view)

      assert html =~ "&gt; SELECT 1 AS a;\n&gt; SELECT 2 AS b;"
      assert at(html, "a\n-\n1") < at(html, "b\n-\n2")
    end

    test "エラーの前の文までは実行され、エラーは赤字で出る", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "UPDATE 商品 SET 在庫 = 20 WHERE id = 1; SELECT * FROM missing;")

      html = m2_history(view)
      assert at(html, "1行を変更しました") < at(html, "エラー: no such table: missing")

      run_m2(view, "SELECT 在庫 FROM 商品 WHERE id = 1;")
      assert m2_history(view) =~ "在庫\n----\n20"
    end

    test "実行すると入力欄は空になる。空のまま実行しても、何も積まれない", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "SELECT * FROM 商品;")
      assert render(element(view, "#m2-sql")) =~ "></textarea>"

      before = m2_history(view)
      run_m2(view, "   ")
      assert m2_history(view) == before
    end

    test "実行した命令が、↑キーの履歴の元データに入る", %{conn: conn} do
      view = open_m2_terminal(conn)
      assert render(element(view, "#m2-sql")) =~ "data-history=\"[]\""

      run_m2(view, "SELECT * FROM 商品;")
      run_m2(view, "SELECT 1;")

      history = render(element(view, "#m2-sql"))
      assert at(history, "SELECT * FROM 商品;") < at(history, "SELECT 1;")
    end

    test "最初のデータに戻すと、データベースは初期に戻り、画面の履歴は残る", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "INSERT INTO 商品 VALUES (4, 'ホッチキス', 600, 6);")
      run_m2(view, "SELECT COUNT(*) AS n FROM 商品;")
      assert m2_history(view) =~ "n\n-\n4"

      render_click(view, "reset", %{"mission" => "m2"})
      html = m2_history(view)
      assert html =~ "データベースを最初の状態に戻しました"
      # 戻す前の入出力は残っている
      assert html =~ "&gt; INSERT INTO 商品 VALUES"

      run_m2(view, "SELECT COUNT(*) AS m FROM 商品;")
      assert m2_history(view) =~ "m\n-\n3"
    end

    test "画面を消去すると、履歴だけが消え、データベースは変わらない", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "INSERT INTO 商品 VALUES (4, 'ホッチキス', 600, 6);")
      assert m2_history(view) =~ "&gt; INSERT"

      view |> element("button", "画面を消去") |> render_click()
      html = m2_history(view)
      refute html =~ "&gt; INSERT"
      refute html =~ "1行を変更しました"

      run_m2(view, "SELECT COUNT(*) AS n FROM 商品;")
      assert m2_history(view) =~ "n\n-\n4"
    end

    test "INSERT・UPDATE・DELETEができる", %{conn: conn} do
      view = open_m2_terminal(conn)

      run_m2(view, "INSERT INTO 商品 VALUES (4, 'ホッチキス', 600, 6);")
      run_m2(view, "UPDATE 商品 SET 在庫 = 20 WHERE id = 1;")
      run_m2(view, "DELETE FROM 商品 WHERE id = 2;")
      run_m2(view, "SELECT * FROM 商品 ORDER BY id;")

      html = m2_history(view)
      assert html =~ "4   ホッチキス  600   6"
      assert html =~ "1   コピー用紙  480   20"
      refute html =~ "2   ボールペン"
    end

    test "'…' の外に全角スペースがあると、実行せずに止めて、場所を「^」で示す", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "DELETE FROM 商品　WHERE id = 1;")
      entry = last_entry(view, "m2")

      assert entry =~ "エラー: 15文字目に全角スペースがあります（実行していません）"

      # コマンドの行を出し直し、その下の全角スペースの位置に「^」。
      # 「> DELETE FROM 商品」の幅は18(「> 」の2と、全角の幅2を数える)なので、19桁目に「^」
      assert entry =~ "WHERE id = 1;\n#{String.duplicate(" ", 18)}^"
      # 実行していないので、SQLiteのエラーは出ず、データも消えていない
      refute entry =~ "syntax error"
      run_m2(view, "SELECT COUNT(*) AS n FROM 商品;")
      assert last_entry(view, "m2") =~ "n\n-\n3"
    end

    test "全角のクォートや括弧も、実行前に止める。'…' の中の全角文字は、そのまま実行する", %{conn: conn} do
      view = open_m2_terminal(conn)

      run_m2(view, "INSERT INTO 商品 VALUES (4, ’付箋’, 200, 12);")
      assert last_entry(view, "m2") =~ "27文字目に全角のクォート「’」があります"

      run_m2(view, "INSERT INTO 商品 VALUES （4, '付箋', 200, 12);")
      assert last_entry(view, "m2") =~ "全角の括弧「（」があります"

      run_m2(view, "SELECT * FROM 商品\nWHERE 価格 ＝ 480;")
      assert last_entry(view, "m2") =~ "2行目の10文字目に全角のイコール「＝」があります"

      # '…' の中なら全角でもよい(値としての文字)
      run_m2(view, "INSERT INTO 商品 VALUES (4, '付箋　（大）', 200, 12);")
      assert last_entry(view, "m2") =~ "1行を変更しました"
    end

    test "打ったコマンドの全角スペースは、色付きの枠で見えるようにする", %{conn: conn} do
      view = open_m2_terminal(conn)
      run_m2(view, "SELECT '全角　スペース' AS s;")

      command = render(element(view, "#m2-entry-0 pre.text-green-300"))

      # 全角スペースの1文字だけを枠で囲む(文字は残すので、コピーしても同じ)
      assert command =~ ~r{全角<span class="wide-space [^"]*outline[^"]*"[^>]*>　</span>スペース}
      # 半角スペースには付けない
      assert length(Regex.scan(~r/wide-space/, command)) == 1
    end

    test "英語のエラーはそのまま残し、その下に日本語の手がかりを出す", %{conn: conn} do
      view = open_m2_terminal(conn)

      # near "X": syntax error … Xの手前を見直す。コマンドの中のXに「^」
      run_m2(view, "SELECT 名前 価格 在庫 FROM 商品;")
      entry = last_entry(view, "m2")
      assert entry =~ "エラー: near &quot;在庫&quot;: syntax error"
      assert entry =~ "→ 在庫の手前を見直してください（, の抜けや全角文字がないか）"
      # 「> SELECT 名前 価格 」の幅は19(全角は2)なので、20桁目に「^」
      assert entry =~ "&gt; SELECT 名前 価格 在庫 FROM 商品;\n#{String.duplicate(" ", 19)}^"

      # no such column
      run_m2(view, "SELECT 値段 FROM 商品;")
      entry = last_entry(view, "m2")
      assert entry =~ "エラー: no such column: 値段"
      assert entry =~ "→ 値段という列はありません"

      # 列と値の数の違い
      run_m2(view, "INSERT INTO 商品 VALUES (4, 'ホッチキス', 600);")
      entry = last_entry(view, "m2")
      assert entry =~ "table 商品 has 4 columns but 3 values were supplied"
      assert entry =~ "→ 列は4個、値は3個です"

      # 当てはまらないエラーには、手がかりを付けない
      run_m2(view, "SELECT * FROM 果物;")
      refute last_entry(view, "m2") =~ "→"
    end
  end

  describe "SQLインジェクション" do
    defp open_inject(conn) do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "inject"})
      render_click(view, "start", %{"mission" => "inject"})
      view
    end

    # 検索して、ターミナルに積まれた最後の1回分(実行したSQL・件数かエラー)の文字を返す
    defp search(view, mode, input) do
      view
      |> form("#inject-form", %{"mode" => mode, "input" => input})
      |> render_submit()

      render_async(view, 5_000)

      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("[id^=inject-entry-]")
      |> Enum.map(&LazyHTML.text/1)
      |> List.last()
    end

    @injection "' OR '1'='1"

    test "ほかのミッションと同じく開始ボタンで始める。最初に開くタブではなく、上の説明カードはない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#inject-form")

      # 開始前: 開始ボタンだけ。指令書・検索の画面はまだ出ない
      render_click(view, "switch_tab", %{"tab" => "inject"})
      assert has_element?(view, "button[phx-click=start][phx-value-mission=inject]", "🚀 開始")
      refute has_element?(view, "#inject-brief-area")
      refute has_element?(view, "#inject-form")

      html = render_click(view, "start", %{"mission" => "inject"})
      # 上の説明カードは消えている
      refute html =~ "🔍 SQLインジェクション"
      refute html =~ "入力された文字をSQLに入れるとどうなるかを試します"
      refute html =~ "タイマーも採点もありません"

      # 安全性の注意は、指令書の中に「注意」の見出しと、「・」の2項目で書く
      assert has_element?(view, "#inject-brief-area #inject-caution > p", "注意")

      items =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#inject-caution li")
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.map(&String.trim/1)

      assert items == [
               "・ここは練習用の環境です。自分のPCの中だけの、安全な体験です。",
               "・実際のサービスで試すと、不正アクセスなどの犯罪になります。"
             ]

      # テーブルは選ばない(会員テーブルに固定)。作り方の既定は①
      refute has_element?(view, "input[name=table]")
      assert has_element?(view, "input[name=mode][value=unsafe][checked]")

      refute html =~ "🚀 開始"
      refute html =~ "ヒント解放"
      assert has_element?(view, "#inject-form")

      # 会員テーブルなどの区画はない
      refute has_element?(view, "#free-form")
      refute html =~ "考えてみよう"
    end

    test "作り方①②と入力の4つの組み合わせの件数", %{conn: conn} do
      view = open_inject(conn)

      assert search(view, "unsafe", "鈴木 ゆい") =~ "→ 1件"
      assert search(view, "unsafe", @injection) =~ "→ 3件"
      assert search(view, "placeholder", "鈴木 ゆい") =~ "→ 1件"
      assert search(view, "placeholder", @injection) =~ "→ 0件"
    end

    test "検索するのは会員テーブルだけ(商品テーブルは検索できない)", %{conn: conn} do
      view = open_inject(conn)
      assert render(element(view, "#inject-sql")) =~ "SELECT * FROM 会員"

      assert search(view, "unsafe", "鈴木 ゆい") =~ "→ 1件"
      result = render(element(view, "#inject-result"))
      assert result =~ "鈴木 ゆい"
      refute result =~ "田中"

      # 商品の名前で探しても、会員テーブルを探すので見つからない
      assert search(view, "unsafe", "ボールペン") =~ "→ 0件"
      # 検索用のデータベースに、商品テーブルは無い
      assert search(view, "unsafe", "x' UNION SELECT 1, 2, 3 FROM 商品; --") =~
               "no such table: 商品"
    end

    test "①は危険な入力で全会員が返り、②は同じ入力でも返らない(結果の中身)", %{conn: conn} do
      view = open_inject(conn)

      search(view, "unsafe", @injection)
      result = render(element(view, "#inject-result"))
      for name <- ["田中 はると", "佐藤 さくら", "鈴木 ゆい"], do: assert(result =~ name)

      search(view, "placeholder", @injection)
      result = render(element(view, "#inject-result"))
      for name <- ["田中 はると", "佐藤 さくら", "鈴木 ゆい"], do: refute(result =~ name)
    end

    test "検索するたびに、実行したSQL・?に渡した値・件数を、ターミナルに積む", %{conn: conn} do
      view = open_inject(conn)
      refute has_element?(view, "#inject-entry-0")

      search(view, "unsafe", @injection)
      first = render(element(view, "#inject-entry-0"))
      assert first =~ "&gt; SELECT * FROM 会員 WHERE 名前 = &#39;&#39; OR &#39;1&#39;=&#39;1&#39;;"
      assert first =~ "→ 3件"
      refute first =~ "?に渡した値"

      search(view, "placeholder", @injection)
      second = render(element(view, "#inject-entry-1"))
      assert second =~ "&gt; SELECT * FROM 会員 WHERE 名前 = ?;"
      assert second =~ "?に渡した値: &#39; OR &#39;1&#39;=&#39;1"
      assert second =~ "→ 0件"

      # 1回目は消えずに残る
      assert render(element(view, "#inject-entry-0")) =~ "→ 3件"

      # エラーもターミナルに出る
      search(view, "unsafe", "'")
      assert render(element(view, "#inject-entry-2")) =~ "エラー: "
    end

    test "ターミナルの下の「画面を消去」は、履歴だけを消す(予定のSQL・Web画面の結果・設定はそのまま)", %{conn: conn} do
      view = open_inject(conn)

      view
      |> form("#inject-form", %{"mode" => "placeholder", "input" => "鈴木 ゆい"})
      |> render_change()

      search(view, "placeholder", "鈴木 ゆい")
      search(view, "placeholder", @injection)
      assert has_element?(view, "#inject-entry-1")

      # ミッション1〜3と同じく、ターミナルの下のボタンの行にある
      assert has_element?(view, "#inject-terminal + div #inject-clear", "🧹 画面を消去")
      view |> element("#inject-clear") |> render_click()

      refute has_element?(view, "#inject-entry-0")
      refute has_element?(view, "#inject-entry-1")
      assert render(element(view, "#inject-sql")) =~ "&gt; SELECT * FROM 会員 WHERE 名前 = ?;"
      assert render(element(view, "#inject-result")) =~ "（該当する行はありません）"
      assert has_element?(view, "input[name=mode][value=placeholder][checked]")

      # 消したあとも、検索すればまた積まれる
      search(view, "placeholder", "鈴木 ゆい")
      assert render(element(view, "#inject-entry-0")) =~ "→ 1件"
      refute has_element?(view, "#inject-entry-1")
    end

    test "ターミナルの最後の行に、いま検索すると実行するSQLを出し続ける(入力欄はない)", %{conn: conn} do
      view = open_inject(conn)

      # ターミナルには、入力欄を付けない(受講者はWeb画面から入力する)
      refute has_element?(view, "#inject-terminal textarea")
      refute has_element?(view, "#inject-terminal input")

      view
      |> form("#inject-form", %{"mode" => "unsafe", "input" => "鈴木"})
      |> render_change()

      assert has_element?(view, "#inject-history > #inject-sql:last-child")

      assert render(element(view, "#inject-sql")) =~
               "&gt; SELECT * FROM 会員 WHERE 名前 = &#39;鈴木&#39;;"

      # 検索して履歴が積まれても、予定のSQLはいちばん下にある
      search(view, "unsafe", "鈴木 ゆい")
      assert has_element?(view, "#inject-entry-0 + pre + #inject-sql:last-child")
    end

    test "検索する前から、できあがるSQLが入力と作り方に合わせて変わる", %{conn: conn} do
      view = open_inject(conn)

      view |> form("#inject-form", %{"mode" => "unsafe", "input" => "ボールペン"}) |> render_change()
      assert render(element(view, "#inject-sql")) =~ "名前 = &#39;ボールペン&#39;;"

      view
      |> form("#inject-form", %{"mode" => "placeholder", "input" => "ボールペン"})
      |> render_change()

      sql = render(element(view, "#inject-sql"))
      assert sql =~ "名前 = ?;"

      # 「できあがるSQL」の下に、?に渡す値の行は出さない(スライドで説明していないため)
      refute sql =~ "?に渡す値"
      refute sql =~ "ボールペン"

      view
      |> form("#inject-form", %{"mode" => "placeholder", "input" => @injection})
      |> render_change()

      refute render(element(view, "#inject-sql")) =~ "?に渡す値"
      # 検索の実行では、入力を値として渡すので、0件のまま
      assert search(view, "placeholder", @injection) =~ "→ 0件"
    end

    test "①で構文エラーになる入力は、エラー文をそのまま表示する。②はエラーにならない", %{conn: conn} do
      view = open_inject(conn)

      entry = search(view, "unsafe", "'")
      assert entry =~ "エラー:"
      refute entry =~ "件"

      # Web画面: 空白をそのまま見せる枠なので、1行目の左端から「エラー:」が始まる(前に改行・字下げがない)
      [text] =
        view
        |> element("#inject-result")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#inject-error")
        |> Enum.map(&LazyHTML.text/1)

      assert String.starts_with?(text, "エラー: ")
      refute text =~ ~r/\n\s*$/

      entry = search(view, "placeholder", "'")
      refute entry =~ "エラー:"
      assert entry =~ "→ 0件"
      result = render(element(view, "#inject-result"))
      refute result =~ "エラー:"
      assert result =~ "（該当する行はありません）"
    end

    test "Web画面の検索結果には、件数の行を出さない(件数はターミナルの「→ N件」で見る)", %{conn: conn} do
      view = open_inject(conn)

      assert search(view, "unsafe", @injection) =~ "→ 3件"
      result = render(element(view, "#inject-result"))
      assert has_element?(view, "#inject-result table")
      refute result =~ "該当:"
      refute result =~ "3件"
    end

    test "複数の文は実行できず、データは変更されない", %{conn: conn} do
      view = open_inject(conn)

      assert search(view, "unsafe", "x'; DELETE FROM 会員; --") =~ "エラー:"

      # 全部の会員が残っている
      assert search(view, "unsafe", @injection) =~ "→ 3件"
    end

    test "Web画面には入力例のボタンを置かない(空いた分は検索結果に使う)", %{conn: conn} do
      view = open_inject(conn)

      shop = render(element(view, "#inject-shop"))
      refute shop =~ "入力例"
      refute has_element?(view, "button[phx-click=inject_example]")

      # 検索欄の次は、すぐ検索結果
      assert has_element?(view, "#inject-shop div:has(> #inject-input) + #inject-result")
    end

    test "画面は、ほかのミッションと同じ並び(上: 指令書とヒント、左下: ターミナル、右下: Web画面とサーバー側の設定)",
         %{conn: conn} do
      view = open_inject(conn)
      html = render(view)

      # 開始したあとは、開始ボタンは消えてタイマーが出る(スライドのスケジュールに合わせて5分)。ヒントは待たずに見られる
      refute has_element?(view, "button[phx-click=start][phx-value-mission=inject]")
      refute html =~ "ヒント解放"

      # タイマーは、ほかのミッションと同じく指令書の見出しの行にある(「ヒント解放まで」の表示はない)
      assert has_element?(view, "#inject-brief-area summary #inject-timer", "05:00")
      refute has_element?(view, "#inject-timer", "15:00")
      refute has_element?(view, "#inject-hint-timer")

      # 「ヒント解放まで」の表示が無くなったので、幅揃え用の空きもない
      refute has_element?(view, "#inject-hint-space")

      # 指令書(スライドと同じ文面)。判定・攻撃の課題はない。安全性の注意は、指令書の注意文にまとめてある
      brief = render(element(view, "#inject-brief-area"))
      assert brief =~ "セキュリティ監査で、全員の会員情報が見えてしまう操作が見つかった。"
      refute brief =~ "点検で"
      assert brief =~ "会員を名前で探す画面で、何が起きているのか調査せよ。"
      refute brief =~ "画面がある。"
      # やり方(何を入れて比べるか)は、指令書ではなくヒントに書く
      refute brief =~ "アプリで会員テーブルを選び"
      refute brief =~ "鈴木 ゆい"
      refute brief =~ "&#39; OR &#39;1&#39;=&#39;1"
      assert brief =~ "自分のPCの中だけの、安全な体験です。"
      refute brief =~ "ヒント解放"
      # 注意文は、指令書の外には(目立たない形では)出てこない
      refute html =~ ~s(<p class="text-xs opacity-70 mb-2">)

      refute html =~ "✅"
      refute html =~ "⬜"
      refute html =~ "ミッション完了"

      # 上の段: 左に指令書、右にヒント(ミッション1〜3と同じ)
      top = "#inject-top.grid.lg\\:grid-cols-2.lg\\:h-72"
      assert has_element?(view, "#{top} > #inject-brief-area + #inject-hint")
      refute has_element?(view, "#inject-brief-area.mb-4")

      # 左下: ミッション1〜3と同じ黒いターミナル(できあがるSQLがここに出る)。灰色のサーバー側の枠はなくした
      assert has_element?(
               view,
               "#inject-form.grid > #inject-terminal-area > #inject-terminal.terminal-font.bg-black"
             )

      assert has_element?(view, "#inject-terminal #inject-sql")
      refute has_element?(view, "#inject-server")

      # 右下: 通販サイト(店構え。検索欄と結果)と、その下にサーバー側の設定(作り方)
      assert has_element?(
               view,
               "#inject-terminal-area + #inject-right > #inject-shop + #inject-settings"
             )

      shop = render(element(view, "#inject-shop"))
      assert shop =~ "オフィスいちば"
      # 見出し(会員を名前で探す)は置かない。検索欄から始まる
      refute has_element?(view, "#inject-shop h3")
      refute shop =~ "会員を名前で探す"
      assert has_element?(view, "#inject-shop #inject-input")
      assert has_element?(view, "#inject-shop #inject-result")

      # 設定は作り方の①・②だけを、横1行に並べる(テーブルは会員に固定)。ラベルに（）の説明は付けない
      settings = render(element(view, "#inject-settings"))
      # 帯に見出し(legend)は付けない。①・②のラジオボタンだけ
      refute has_element?(view, "#inject-settings legend")
      refute settings =~ "サーバー側の設定"
      assert has_element?(view, "#inject-settings.py-2")
      refute settings =~ "商品テーブル"
      refute settings =~ "会員テーブル"
      assert has_element?(view, "#inject-settings.flex.flex-wrap")
      refute has_element?(view, "#inject-settings.grid")

      labels =
        settings
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("label")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert labels == ["① 入力をそのままSQLに入れる", "② プレースホルダ"]
      assert has_element?(view, "#inject-settings.bg-neutral-500")
    end

    test "ヒントは「調べ方」(番号付きの手順)と「SQLの読み方」(箇条書き)の2段。プロンプト例はない", %{conn: conn} do
      view = open_inject(conn)
      assert has_element?(view, "#inject-hint #inject-hint-open", "💡 ヒントを見る")

      open_hint(view, "inject")
      body = "#inject-hint-body"

      assert has_element?(view, "#{body} p.font-bold#inject-hint-steps-title", "調べ方")

      steps =
        view
        |> element("#inject-hint-steps")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("li")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert steps == [
               "①で、ふつうの名前（例：鈴木 ゆい）を検索する。",
               "同じ①で、' OR '1'='1 を検索する。",
               "②に切り替えて、同じように検索する。"
             ]

      assert has_element?(view, "#{body} ol.list-decimal#inject-hint-steps")
      assert has_element?(view, "#inject-hint-steps code.font-mono", "' OR '1'='1")

      assert has_element?(view, "#{body} p.font-bold#inject-hint-reading-title", "SQLの読み方")
      assert has_element?(view, body, "ターミナルに出るSQLを、①と②で見比べてみましょう。")

      reading =
        view
        |> element("#inject-hint-reading")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("li")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()))

      assert reading == [
               "' は、文字の始まりと終わりの印です。入力した最初の ' で、名前が閉じます。",
               "OR は「または」です。どちらか片方が正しければ、その行を表示します。",
               "'1'='1' が正しくなるのは、どんなときでしょうか？"
             ]

      assert has_element?(view, "#{body} ul.list-disc#inject-hint-reading")
      assert has_element?(view, "#inject-hint-reading code.font-mono", "OR")
      assert has_element?(view, body, "②では、入力は「?に渡した値」として、まるごと名前として扱われます。")

      # 調べ方 → 読み方 の順
      html = render(element(view, body))
      assert at(html, "調べ方") < at(html, "SQLの読み方")

      # プロンプト例(コピーボタン)は置かない
      refute has_element?(view, "#inject-prompt")
      refute has_element?(view, "#inject-prompt-copy")
      refute html =~ "プロンプト例"
    end

    test "作り方のラジオボタンは、白い丸の中に、選んだ方だけ黒い点が付く", %{conn: conn} do
      view = open_inject(conn)
      server = render(element(view, "#inject-settings"))

      # テーマ依存で黒くなりうる daisyUI の radio クラスは使わない
      refute server =~ ~s(class="radio radio-sm")

      # 選んでいない方は白い丸。選んだ方は、白い縁(内側の影)を残して中心を黒く塗る
      radio = "#inject-settings input[type=radio]"
      assert has_element?(view, "#{radio}.bg-white.checked\\:bg-black")
      assert has_element?(view, "#{radio}.checked\\:shadow-\\[inset_0_0_0_3px_white\\]")
      # 選んだ方をオレンジ(primary)で塗る形には戻さない
      refute server =~ "checked:bg-primary"

      # ラベルの文字は白にしてある
      assert server =~ ~s(class="flex items-center gap-2 cursor-pointer text-white")
    end
  end

  describe "ミッション2・3・4の画面" do
    test "商品テーブルは出さず、SQL入力欄と結果があり、右側に埋め込みの通販サイトがある(どのタブにも別ウィンドウのリンクはない)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for tab <- ~w(m2 m3 m4) do
        start_mission(view, tab)
        html = render(view)

        refute html =~ "データベース（商品テーブル）"
        refute has_element?(view, "##{tab}-table")
        assert has_element?(view, "##{tab}-form")
        assert has_element?(view, "##{tab}-history")
        assert has_element?(view, "##{tab}-shop")
      end
    end

    test "通販サイトを開く（別ウィンドウ）」のリンクは、どのタブにも無い(/shopのページ自体は残る)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for tab <- ~w(m2 m3 m4 inject) do
        render_click(view, "switch_tab", %{"tab" => tab})
        refute has_element?(view, ~s(a[href="/shop"]))
        refute render(view) =~ "通販サイトを開く"
      end
    end

    test "開始後は、残り時間のタイマーを「📜 指令書」の右に出す(ヒント解放までの表示はない)。指令書の高さは固定(スクロール)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "m2"})

      # 開始前: 開始ボタンの欄だけ。指令書はまだ出ない
      assert has_element?(view, "#m2-start.card", "🚀 開始")
      refute has_element?(view, "#m2-brief-area")

      start_mission(view, "m2")

      # 開始後: 開始ボタンの欄は消え、独立したタイマーの欄もない(縦幅を詰める)
      refute has_element?(view, "#m2-start")
      refute has_element?(view, ".card.bg-base-100.border.border-base-300.shadow-sm.p-4")

      # 見出しの行に、「📜 指令書」→ 残り時間 の順に並ぶ。ヒントは待たずに見られるので、
      # 「ヒント解放まで」の表示はない
      summary = render(element(view, "#m2-brief-area summary"))
      assert has_element?(view, "#m2-brief-area summary #m2-timer", "15:00")
      refute has_element?(view, "#m2-hint-timer")
      refute summary =~ "ヒント解放"
      {title_pos, _} = :binary.match(summary, "📜 指令書")
      {timer_pos, _} = :binary.match(summary, ~s(id="m2-timer"))
      assert title_pos < timer_pos

      # 「📜 指令書」の文字は大きく、タイマーだけを右寄せ(ml-auto)にする
      assert has_element?(view, "#m2-brief-title.text-xl", "📜 指令書")
      refute has_element?(view, "#m2-brief-title.ml-auto")
      assert has_element?(view, "#m2-brief-timers.ml-auto > #m2-timer")

      # 指令書の中身(collapse-content)は、固定の高さでスクロールする
      assert has_element?(view, "#m2-brief-area .collapse-content.h-56.overflow-y-auto")

      # daisyUIの min-height: fit-content で、中身の長い指令書だけ伸びないように打ち消してある。
      # すべてのミッションで同じ部品(同じ高さ)を使う
      start_mission(view, "m3")
      start_mission(view, "m4")
      render_click(view, "switch_tab", %{"tab" => "inject"})
      render_click(view, "start", %{"mission" => "inject"})

      for m <- ~w(m2 m3 m4 inject) do
        render_click(view, "switch_tab", %{"tab" => m})

        assert has_element?(
                 view,
                 "##{m}-brief-area .collapse-content.h-56.\\!min-h-0.overflow-y-auto"
               )
      end
    end

    test "タイマーは分:秒で減っていく", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")

      Enum.each(1..61, fn _ -> send(view.pid, {:timer_tick, "m2"}) end)
      assert has_element?(view, "#m2-timer", "13:59")
    end

    test "ヒントの枠は、どのミッションも開始直後から指令書の右にあり、閉じている間は「ヒントを見る」ボタンだけ", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m2 m3 m4 inject) do
        refute has_element?(view, "##{m}-hint")
        start_mission(view, m)

        # 上の段: 左に指令書、右にヒント(lg以上で2列、段の高さは h-72 に固定)
        top = "##{m}-top.grid.lg\\:grid-cols-2.lg\\:h-72"
        assert has_element?(view, "#{top} > ##{m}-brief-area")
        assert has_element?(view, "#{top} > ##{m}-brief-area + ##{m}-hint")

        # 1秒も経っていなくても、ヒントの枠がある。閉じている間はボタンだけで、中身はない
        assert has_element?(view, "##{m}-hint.h-72 ##{m}-hint-open", "💡 ヒントを見る")
        refute has_element?(view, "##{m}-hint-body")
        refute has_element?(view, "##{m}-hint-close")
      end
    end

    test "指令書とヒントの枠の高さは、ミッション1〜4で同じ(段・指令書の中身・ヒントの枠を固定)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m2 m3 m4 inject) do
        start_mission(view, m)
        assert has_element?(view, "##{m}-top.lg\\:h-72")

        # 指令書は、段の中では下の余白(mb-4)を付けない(付けると段の高さからはみ出す)
        refute has_element?(view, "##{m}-brief-area.mb-4")
        assert has_element?(view, "##{m}-brief-area .collapse-content.h-56")
        assert has_element?(view, "##{m}-hint.h-72")
      end
    end

    test "プロンプト例の無いヒント(ミッション１・４)は、余白を詰めて枠に収める。ミッション２・３は今のまま", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m2 inject) do
        start_mission(view, m)
        open_hint(view, m)
        assert has_element?(view, "##{m}-hint-body.gap-1.pb-2")
        refute has_element?(view, "##{m}-hint-body.gap-2")
        assert has_element?(view, "##{m}-hint div.pt-2:has(> ##{m}-hint-close)")
      end

      # ミッション４の「SQLの読み方」の前の空きも詰める(文言はそのまま)
      render_click(view, "switch_tab", %{"tab" => "inject"})
      assert has_element?(view, "#inject-hint-reading-title.mt-1", "SQLの読み方")
      refute has_element?(view, "#inject-hint-reading-title.mt-2")

      for m <- ~w(m3 m4) do
        start_mission(view, m)
        open_hint(view, m)
        assert has_element?(view, "##{m}-hint-body.gap-2.pb-3")
        assert has_element?(view, "##{m}-hint div.pt-3:has(> ##{m}-hint-close)")
      end
    end

    test "「ヒントを見る」で同じ枠の中に中身が出て、「閉じる」で戻る。タイマーが進んでも開いたまま", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m3")

      open_hint(view, "m3")

      # 枠(h-72)はそのままで、その中に中身が出る(入りきらない分は枠の中でスクロール)
      assert has_element?(view, "#m3-hint.h-72 #m3-hint-body.overflow-y-auto", "生成AI")
      refute has_element?(view, "#m3-hint-open")
      assert has_element?(view, "#m3-hint-close", "閉じる")

      # タイマーが毎秒画面を描き直しても、サーバーが開閉を覚えているので閉じない
      Enum.each(1..3, fn _ -> send(view.pid, {:timer_tick, "m3"}) end)
      assert has_element?(view, "#m3-timer", "14:57")
      assert has_element?(view, "#m3-hint-body")

      # 「閉じる」で、ボタンだけの状態に戻る
      view |> element("#m3-hint-close") |> render_click()
      refute has_element?(view, "#m3-hint-body")
      assert has_element?(view, "#m3-hint.h-72 #m3-hint-open")
    end

    test "ミッション１のヒントに、CRUDの順のSQL例がある。クリックすると入力欄に入る", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")
      open_hint(view, "m2")
      examples = render(element(view, "#m2-hint-examples"))

      for text <- [
            "INSERT INTO 商品 VALUES (4, &#39;ホッチキス&#39;, 600, 6);",
            "SELECT * FROM 商品 WHERE 価格 &gt;= 200;",
            "UPDATE 商品 SET 在庫 = 20 WHERE id = 1;",
            "DELETE FROM 商品 WHERE id = 4;"
          ] do
        assert examples =~ text, "SQL例に無い: #{text}"
      end

      # CRUDの順(作成→検索→更新→削除)
      assert at(examples, "作成（C）") < at(examples, "検索（R）")
      assert at(examples, "検索（R）") < at(examples, "更新（U）")
      assert at(examples, "更新（U）") < at(examples, "削除（D）")

      # ミッション１の答え(在庫10個未満の検索、付箋の登録)は入っていない
      refute examples =~ "在庫 &lt; 10"
      refute examples =~ "付箋"

      view |> element("#m2-hint-examples button", "作成（C）") |> render_click()

      assert render(element(view, "#m2-sql")) =~
               "INSERT INTO 商品 VALUES (4, &#39;ホッチキス&#39;, 600, 6);"
    end

    test "ミッション２のプロンプト例に「コピー」ボタンがある", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m3")
      open_hint(view, "m3")

      assert has_element?(view, "#m3-prompt", "【実行したSQL】")

      assert has_element?(
               view,
               ~s(button#m3-prompt-copy[data-target="#m3-prompt"][phx-hook]),
               "コピー"
             )
    end

    test "タイトル(text-3xl)とタブを1行に並べる(狭いときは折り返す)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      header = "#page-header.flex.flex-wrap.items-center"
      assert has_element?(view, "#{header} > h1.text-3xl", "システムトラブルを解決せよ！")
      assert has_element?(view, "#{header} > h1 + [role=tablist]")
      refute has_element?(view, "h1.text-4xl")
    end

    test "ミッション4の指令書も、ミッション1〜3の上の段と同じ高さ(lg:h-72)。指令書の行間は詰めてある", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "inject"})
      render_click(view, "start", %{"mission" => "inject"})

      assert has_element?(view, "#inject-top.lg\\:h-72 > #inject-brief-area")
      assert has_element?(view, "#inject-brief-area .collapse-content.h-56.gap-1")

      # daisyUIの開いたときの下の余白(1rem)を、半分(!pb-2)にして、中身が224pxに収まるようにする
      assert has_element?(view, "#inject-brief-area .collapse-content.\\!pb-2")
      refute has_element?(view, "#inject-brief-area .collapse-content.gap-2")
    end

    test "ターミナルの黒い部分は h-80。右のWeb画面も同じ高さ", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m2 m3) do
        start_mission(view, m)
        assert has_element?(view, "##{m}-terminal.h-80")
        refute has_element?(view, "##{m}-history.h-80")
        assert has_element?(view, "##{m}-shop.h-80")
      end

      # ミッション3(内部名m4)の右は、会員登録画面(ターミナルと同じ高さ)と、その下のサーバーのログ
      start_mission(view, "m4")
      assert has_element?(view, "#m4-terminal.h-80")
      assert has_element?(view, "#m4-shop.h-80 + #m4-server-log")
      refute has_element?(view, ".h-80 > #m4-server-log")

      # ミッション４(内部名inject)は、右のWeb画面とその下の設定の帯を合わせて、左のターミナルと同じ高さにする。
      # Web画面は帯の分だけ低くなり(flex-1)、入りきらない検索結果はWeb画面の枠の中でスクロールする
      render_click(view, "switch_tab", %{"tab" => "inject"})
      render_click(view, "start", %{"mission" => "inject"})
      assert has_element?(view, "#inject-terminal.h-80")
      refute has_element?(view, "#inject-history.h-80")
      assert has_element?(view, "#inject-right.h-80.flex.flex-col")
      assert has_element?(view, "#inject-right > #inject-shop.flex-1.min-h-0")
      refute has_element?(view, "#inject-shop.h-80")
      assert has_element?(view, "#inject-shop > .flex-1.overflow-y-auto #inject-result")
      assert has_element?(view, "#inject-right > #inject-settings")
      assert has_element?(view, "#inject-history.flex-1.min-h-0.overflow-y-auto")
      refute has_element?(view, "#inject-form.items-start")
    end

    test "ミッション４の検索結果の表は、黒い画面の文字色(薄いグレー)を継がない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "inject"})
      render_click(view, "start", %{"mission" => "inject"})

      view
      |> form("#inject-form", %{"mode" => "unsafe", "input" => "鈴木 ゆい"})
      |> render_submit()

      render_async(view, 5_000)
      assert has_element?(view, "#inject-result .bg-base-100.text-base-content table")
    end

    test "右側の通販サイトは、店名入りのヘッダーとフッターが付いた見た目(メニューは飾り)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")
      shop = render(element(view, "#m2-shop"))

      assert shop =~ "オフィスいちば"
      assert shop =~ "商品一覧"
      assert shop =~ "会員登録"
      assert shop =~ "🛒"
      # フッターらしき著作権表記がある
      assert shop =~ "©"
    end

    test "ミッション3(内部名m4)の「サーバーのログ」の見出し", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m4")
      html = render(view)

      assert html =~ "サーバーのログ"
      refute html =~ "サーバーの記録（通販サイトの会員登録）"
    end

    test "「待機中」は出さない。実行中だけ「実行中...」が出る", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      refute html =~ "待機中"

      start_mission(view, "m2")
      refute render(view) =~ "待機中"
      refute render(view) =~ "実行中..."
      html = view |> form("#m2-form", %{"sql" => "SELECT 1;"}) |> render_submit()
      assert html =~ "実行中..."
      html = render_async(view, 5_000)
      refute html =~ "実行中..."
      refute html =~ "待機中"
    end

    test "ミッション1〜3の入力欄は、同じターミナルで、実行ボタンと操作説明の行はない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m2 m3 m4) do
        start_mission(view, m)

        refute has_element?(view, "##{m}-help")
        refute has_element?(view, "button[form=#{m}-form]")

        assert has_element?(view, "##{m}-terminal.terminal-font.bg-black")
        assert has_element?(view, "##{m}-form textarea[phx-hook]")
        assert has_element?(view, "button[phx-click=reset][phx-value-mission=#{m}]", "最初のデータに戻す")

        assert has_element?(
                 view,
                 "button[phx-click=clear_history][phx-value-mission=#{m}]",
                 "画面を消去"
               )
      end

      # 古い説明(ターミナルとの違いの断り書き、下の操作説明)は出ない
      html = render(view)
      refute html =~ "練習のターミナルとは違い"
      refute html =~ "Enter だけでは実行されません"
      refute html =~ "セミコロン"
      refute html =~ "最後に ; を付けて Enter で実行"
    end

    test "ミッション2の入力欄: 打ったSQLと結果が積み重なり、エラーは赤字、リセットと画面の消去ができる", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")

      run_sql(view, "m2", "SELECT * FROM 商品;")
      run_sql(view, "m2", "SELECT COUNT(*) AS n FROM 商品;")
      run_sql(view, "m2", "SELECT * FROM しょうひん;")

      html = render(element(view, "#m2-history"))
      assert at(html, "&gt; SELECT * FROM 商品;") < at(html, "&gt; SELECT COUNT(*)")
      assert at(html, "&gt; SELECT COUNT(*)") < at(html, "&gt; SELECT * FROM しょうひん;")

      # 古い入出力も残る
      assert html =~ "コピー用紙"
      assert html =~ "n\n-\n3"

      assert has_element?(view, "#m2-history pre.text-red-400", "no such table: しょうひん")

      # 実行すると、入力欄は空になる
      assert render(element(view, "#m2-sql")) =~ "></textarea>"

      # 実行した命令が、↑キーの履歴の元データに入る
      assert render(element(view, "#m2-sql")) =~ "SELECT * FROM 商品;"

      # 空のまま実行しても、何も積まれない
      before = render(element(view, "#m2-history"))
      run_sql(view, "m2", "   ")
      assert render(element(view, "#m2-history")) == before

      # リセット: 戻したことが1行積まれ、履歴は残る
      render_click(view, "reset", %{"mission" => "m2"})
      html = render(element(view, "#m2-history"))
      assert html =~ "データベースを最初の状態に戻しました"
      assert html =~ "&gt; SELECT * FROM 商品;"

      # 画面の消去: 履歴だけが消える
      view |> element("button[phx-click=clear_history][phx-value-mission=m2]") |> render_click()
      refute render(element(view, "#m2-history")) =~ "&gt; SELECT"
    end

    test "追加指令は、チャレンジという名前では出ない。見出しは「追加指令」、例の見出しは「SQL例」", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m3")

      run_sql(view, "m3", """
      UPDATE 商品 SET 価格 = 480 WHERE id = 1;
      UPDATE 商品 SET 価格 = 250 WHERE id = 3;
      """)

      html = render(view)
      assert has_element?(view, "#m3-challenge")
      assert html =~ "追加指令"
      assert render(element(view, "#m3-examples summary")) =~ "💡 SQL例"
      refute html =~ "チャレンジ"
      refute html =~ "書き方の例"
    end

    test "ミッション3(画面の番号は2)の入力欄は最初は空欄で、プレースホルダーも出ない", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m3")

      sql = render(element(view, "#m3-sql"))
      assert sql =~ "></textarea>"
      refute sql =~ "placeholder="
      refute sql =~ "ここにSQLを書きます"
      refute sql =~ "元に戻そう"

      # 空のまま実行しても、エラーにならず、何も積まれない
      before = render(element(view, "#m3-history"))
      html = run_sql(view, "m3", "")
      refute html =~ "実行する命令がありませんでした。"
      refute html =~ "エラー"
      assert render(element(view, "#m3-history")) == before

      # リセットしても空欄に戻る
      render_click(view, "reset", %{"mission" => "m3"})
      assert render(element(view, "#m3-sql")) =~ "></textarea>"
    end

    test "ミッション1・ミッション3の入力欄は、最初から空欄(ミッション2のように初期SQLが入っていない)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      start_mission(view, "m2")
      assert render(element(view, "#m2-sql")) =~ "></textarea>"
      refute render(element(view, "#m2-sql")) =~ "SELECT * FROM 商品;"

      start_mission(view, "m4")
      assert render(element(view, "#m4-sql")) =~ "></textarea>"
      refute render(element(view, "#m4-sql")) =~ "ここにSQLを書いて、原因を調べよう"
    end
  end

  describe "ミッションの追加指令" do
    setup %{conn: conn} do
      conn = participant_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/")
      %{view: view, conn: conn}
    end

    # 必須の課題をすべて✅にする
    defp complete_m2(view) do
      start_mission(view, "m2")

      run_sql(view, "m2", """
      INSERT INTO 商品 VALUES (4, '付箋', 200, 12);
      SELECT * FROM 商品 WHERE 在庫 < 10;
      UPDATE 商品 SET 在庫 = 30 WHERE id = 1;
      DELETE FROM 商品 WHERE 名前 = '付箋';
      """)
    end

    defp complete_m3(view) do
      start_mission(view, "m3")

      run_sql(view, "m3", """
      UPDATE 商品 SET 価格 = 480 WHERE id = 1;
      UPDATE 商品 SET 価格 = 250 WHERE id = 3;
      """)
    end

    # 解答例: 退会した人の行は消さずに、個人情報（名前・メールアドレス）を消す
    defp complete_m4(view, conn) do
      start_mission(view, "m4")
      signup(conn)
      run_sql(view, "m4", "SELECT * FROM 会員 WHERE メールアドレス = 'sakura@example.com';")
      run_sql(view, "m4", "UPDATE 会員 SET 名前 = '退会済み', メールアドレス = '' WHERE 退会 = 1;")
      signup(conn)
      render(view)
    end

    defp challenge_pos(html, text) do
      {pos, _} = :binary.match(html, text)
      pos
    end

    test "必須の課題が未達成のうちは、どのミッションにも追加指令が出ない", %{view: view, conn: conn} do
      for m <- ~w(m2 m3 m4) do
        start_mission(view, m)
        refute has_element?(view, "##{m}-challenge")
        refute render(view) =~ "📌 追加指令"
      end

      # ミッション2: 4つのうち3つ(削除が未達成)では、まだ出ない
      render_click(view, "switch_tab", %{"tab" => "m2"})

      html =
        run_sql(view, "m2", """
        INSERT INTO 商品 VALUES (4, '付箋', 200, 12);
        SELECT * FROM 商品 WHERE 在庫 < 10;
        UPDATE 商品 SET 在庫 = 30 WHERE id = 1;
        """)

      assert length(Regex.scan(~r/✅/, html)) == 3
      refute has_element?(view, "#m2-challenge")

      # ミッション3: 一部だけ直しても、まだ出ない
      render_click(view, "switch_tab", %{"tab" => "m3"})
      run_sql(view, "m3", "UPDATE 商品 SET 価格 = 480 WHERE id = 1;")
      refute has_element?(view, "#m3-challenge")

      # ミッション4: 課題3(登録できた)だけでは、まだ出ない
      render_click(view, "switch_tab", %{"tab" => "m4"})
      run_sql(view, "m4", "DELETE FROM 会員 WHERE id = 2;")
      assert signup(conn) =~ "登録できました"
      refute has_element?(view, "#m4-challenge")
    end

    test "ミッション2: 4課題がすべて✅になると、課題欄の下に追加指令が出る(追加指令に✅/⬜はない)", %{view: view} do
      html = complete_m2(view)

      assert has_element?(view, "#m2-challenge")
      assert html =~ "ミッション完了"
      assert html =~ "📌 追加指令"

      for q <- [
            "商品を価格が高い順に並べて表示せよ",
            "価格が200円以上で、在庫が10個未満の商品を探し出せ",
            "名前に「ペン」を含む商品を、あいまい検索で探し出せ"
          ] do
        assert html =~ q
      end

      # 課題欄の下にあり、追加指令に✅/⬜は付かない(✅は必須の4課題だけ)
      assert challenge_pos(html, "4. 「付箋」を削除する") < challenge_pos(html, "📌 追加指令")
      assert length(Regex.scan(~r/✅/, html)) == 4
      refute html =~ "⬜"
    end

    test "ミッション2: SQL例は最初は閉じていて、開くと内容が出る", %{view: view} do
      complete_m2(view)

      assert has_element?(view, "#m2-examples")
      refute has_element?(view, "#m2-examples[open]")

      view |> element("#m2-examples summary") |> render_click()
      assert has_element?(view, "#m2-examples[open]")

      examples = render(element(view, "#m2-examples"))
      assert examples =~ "ORDER BY 価格 DESC"
      assert examples =~ "AND"
      assert examples =~ "名前 LIKE &#39;%ペン%&#39;"
    end

    test "ミッション2: 同じデータベース(完了した状態)で、追加指令のSQLの結果が確かめられる", %{view: view} do
      complete_m2(view)

      # ① 価格が高い順(コピー用紙480 > ファイル250 > ボールペン120)
      run_sql(view, "m2", "SELECT * FROM 商品 ORDER BY 価格 DESC;")
      html = last_entry(view, "m2")
      assert challenge_pos(html, "コピー用紙") < challenge_pos(html, "ファイル")
      assert challenge_pos(html, "ファイル") < challenge_pos(html, "ボールペン")

      # ② 価格が200円以上で、在庫が10個未満: ファイルだけ
      run_sql(view, "m2", "SELECT * FROM 商品 WHERE 価格 >= 200 AND 在庫 < 10;")
      html = last_entry(view, "m2")
      assert html =~ "ファイル"
      refute html =~ "ボールペン"
      refute html =~ "コピー用紙"

      # ③ 名前に「ペン」を含む: ボールペンだけ
      run_sql(view, "m2", "SELECT * FROM 商品 WHERE 名前 LIKE '%ペン%';")
      html = last_entry(view, "m2")
      assert html =~ "ボールペン"
      refute html =~ "ファイル"
      refute html =~ "コピー用紙"
    end

    test "ミッション2: 「最初のデータに戻す」を押しても、追加指令は表示されたまま", %{view: view} do
      complete_m2(view)
      assert has_element?(view, "#m2-challenge")

      html = render_click(view, "reset", %{"mission" => "m2"})
      # 課題は未達成に戻るが、追加指令は消えない
      refute html =~ "ミッション完了"
      refute html =~ ~r{✅</span><span>\s*\d\. }
      assert has_element?(view, "#m2-challenge")
      assert html =~ "📌 追加指令"

      # リセットのあとに、SQLを実行して判定が走っても、消えない
      html = run_sql(view, "m2", "SELECT * FROM 商品;")
      refute html =~ "ミッション完了"
      assert has_element?(view, "#m2-challenge")
    end

    test "ミッション3: 復旧の課題が✅になると追加指令が出て、リセットしても出たまま", %{view: view} do
      refute has_element?(view, "#m3-challenge")
      html = complete_m3(view)

      assert html =~ "復旧完了"
      assert has_element?(view, "#m3-challenge")

      assert has_element?(
               view,
               "#m3-challenge-lead",
               "在庫が少ない商品は、値上げして、品切れを防ぎたい。先ほどの事故があったので、慎重に進めたい。"
             )

      assert html =~ "在庫が10個未満の商品だけ、価格を10円値上げせよ。ただし、変更する前にSELECTを実行して確認すること。"
      refute html =~ "同じ条件でSELECTして、対象の行を確かめること。"

      refute has_element?(view, "#m3-examples[open]")
      view |> element("#m3-examples summary") |> render_click()
      assert render(element(view, "#m3-examples")) =~ "UPDATE 商品 SET 価格 = 価格 + 10 WHERE 条件;"

      html = render_click(view, "reset", %{"mission" => "m3"})
      refute html =~ "復旧完了"
      assert has_element?(view, "#m3-challenge")

      # リセットのあとに、SQLを実行して判定が走っても、消えない
      html = run_sql(view, "m3", "SELECT * FROM 商品;")
      refute html =~ "復旧完了"
      assert has_element?(view, "#m3-challenge")
    end

    test "ミッション3: 同じデータベース(復旧した状態)で、先にSELECTで確かめてから10円値上げする", %{view: view} do
      complete_m3(view)

      # 在庫が10個未満の商品: ボールペンとファイル(コピー用紙は含まない)
      run_sql(view, "m3", "SELECT * FROM 商品 WHERE 在庫 < 10;")
      html = last_entry(view, "m3")
      assert html =~ "ボールペン" and html =~ "ファイル"
      refute html =~ "コピー用紙"

      html = run_sql(view, "m3", "UPDATE 商品 SET 価格 = 価格 + 10 WHERE 在庫 < 10;")
      assert html =~ "2行を変更しました"

      # ボールペン 150→160、ファイル 250→260、コピー用紙は480のまま
      run_sql(view, "m3", "SELECT 名前, 価格 FROM 商品 ORDER BY id;")
      html = last_entry(view, "m3")
      assert html =~ "480"
      assert html =~ "160"
      assert html =~ "260"
      refute html =~ ">150<"
      refute html =~ ">250<"
    end

    test "ミッション4: 必須の3課題がすべて✅になると追加指令が出て、リセットしても出たまま", %{view: view, conn: conn} do
      html = complete_m4(view, conn)

      assert html =~ "ミッション完了"
      assert has_element?(view, "#m4-challenge")

      assert has_element?(
               view,
               "#m4-challenge-lead",
               "データベースは、UNIQUE制約のほかにも、ルールでデータを守っている。次のSQLを実行して、どんなルールに守られているか確かめよ。"
             )

      questions =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#m4-challenge ol li")
        |> Enum.map(&String.trim(LazyHTML.text(&1)))

      assert questions == ["名前を入れずに、会員を登録すると？", "「退会」の列を、2にすると？"]
      refute html =~ "同じメールアドレスで、INSERTするとどうなる？"

      refute has_element?(view, "#m4-examples[open]")
      view |> element("#m4-examples summary") |> render_click()
      examples = render(element(view, "#m4-examples"))
      assert examples =~ "INSERT INTO 会員 (メールアドレス) VALUES (&#39;メール&#39;);"
      assert examples =~ "UPDATE 会員 SET 退会 = 2 WHERE id = 3;"
      refute examples =~ "UPDATE 会員 SET メールアドレス"

      html = render_click(view, "reset", %{"mission" => "m4"})
      refute html =~ "ミッション完了"
      assert has_element?(view, "#m4-challenge")

      # リセットのあとに、SQLを実行して判定が走っても、消えない
      run_sql(view, "m4", "SELECT * FROM 会員;")
      assert has_element?(view, "#m4-challenge")
    end

    test "ミッション4: 追加指令のSQLで、NOT NULL・CHECKのルールのエラーが出る(日本語の補足は付けない)", %{view: view, conn: conn} do
      complete_m4(view, conn)

      # 画面全体には、通販サイトの登録失敗のサーバーの記録(UNIQUE...)が残っているので、
      # SQLの実行結果の欄だけを見る
      result = fn -> last_entry(view, "m4") end

      # 1. 名前を入れずに登録すると、NOT NULL のエラー
      run_sql(view, "m4", "INSERT INTO 会員 (メールアドレス) VALUES ('メール');")
      assert result.() =~ "NOT NULL constraint failed: 会員.名前"
      refute result.() =~ "→"

      # 2. 「退会」の列を2にすると、CHECK のエラー
      run_sql(view, "m4", "UPDATE 会員 SET 退会 = 2 WHERE id = 3;")
      assert result.() =~ "CHECK constraint failed: 退会 IN (0, 1)"
      refute result.() =~ "→"

      # どちらも、データは変わっていない
      run_sql(view, "m4", "SELECT COUNT(*) AS n FROM 会員 WHERE 退会 = 2 OR メールアドレス = 'メール';")
      assert result.() =~ "n\n-\n0"
    end

    test "追加指令は、そのミッションと同じデータベースで試す。ほかのミッションには影響しない", %{view: view, conn: conn} do
      start_mission(view, "m3")
      complete_m2(view)

      # ミッション2の追加指令で、データを壊しても、ミッション3のデータは変わらない
      run_sql(view, "m2", "DELETE FROM 商品;")
      render_click(view, "switch_tab", %{"tab" => "m3"})
      run_sql(view, "m3", "SELECT COUNT(*) AS 件数 FROM 商品;")
      # テキストの表: 見出し「件数」、区切り、行の「3」
      assert last_entry(view, "m3") =~ "件数
----
3"

      # ミッション2の通販サイトの表示には、そのミッション2の変更が反映される
      refute shop(conn, "m2") =~ "ミッションを始めると"
      refute shop(conn, "m2") =~ "コピー用紙"

      # ミッション2を完了しても、ほかのミッションの追加指令は出ない
      refute has_element?(view, "#m3-challenge")
    end
  end

  describe "スライドに合わせた文言" do
    test "ミッション2: 指令書と、課題の文末が「〜する」", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = start_mission(view, "m2")

      assert html =~ "SQLを使って、データベースへ<strong>直接</strong>指示を出せ。"
      refute html =~ "制限時間15分"
      refute html =~ "画面を使わずに"
      refute html =~ "直接</strong>命令"

      for task <- [
            "1. 新商品「付箋」（価格200円、在庫12個）を登録する",
            "2. 在庫が10個未満の商品を検索する",
            "3. コピー用紙の在庫を30個に更新する",
            "4. 「付箋」を削除する"
          ] do
        assert html =~ task, "課題の文言が違う: #{task}"
      end

      for old <- ["を登録せよ", "商品を探し出せ", "に更新せよ", "を削除せよ"] do
        refute html =~ old
      end
    end

    test "ミッション2: 追加指令のSQL例のラベル", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      complete_m2(view)

      examples = render(element(view, "#m2-examples"))
      assert examples =~ "あいまい検索（%は「何文字でもよい」という意味）"
      refute examples =~ "任意の文字列"
    end

    test "ミッション3: 指令書の1文目と、ヒントの注意書き・プロンプト例", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = start_mission(view, "m3")

      assert html =~ "「ボールペンの価格が古いまま」という問題を直すために、次のSQLを実行したところ、"
      refute html =~ "先輩が"
      refute html =~ "ボールペンの値段が古いまま"
      assert html =~ "<strong>コピー用紙とファイルの価格も</strong>150円になってしまった。"
      refute html =~ "すると、"
      assert html =~ "原因を突き止めて、正しい価格に戻せ。"
      refute html =~ "正しい価格（コピー用紙480円・ファイル250円）に戻せ"

      # 達成前に指令書の枠に収まるよう、価格は1行に並べ、SQLの枠の上下の余白は詰める
      assert has_element?(view, "p#m3-brief-prices", "・コピー用紙：480円　・ファイル：250円")
      refute has_element?(view, "#m3-brief-prices li")
      assert has_element?(view, "#m3-brief-area pre.px-3.py-1", "UPDATE 商品 SET 価格 = 150;")
      refute has_element?(view, "#m3-brief-area pre.p-3")

      # 指令書の文の順: 実行したところ → SQL → 価格も150円 → 戻せ → 価格の箇条書き → 課題
      brief = render(element(view, "#m3-brief-area"))
      assert at(brief, "実行したところ、") < at(brief, "UPDATE 商品 SET 価格 = 150;")
      assert at(brief, "UPDATE 商品 SET 価格 = 150;") < at(brief, "150円になってしまった。")
      assert at(brief, "150円になってしまった。") < at(brief, "正しい価格に戻せ。")
      assert at(brief, "正しい価格に戻せ。") < at(brief, "・コピー用紙：480円")
      assert at(brief, "・ファイル：250円") < at(brief, "コピー用紙480円・ボールペン150円・ファイル250円に戻す")

      # ヒントは開始直後から見られる(待ち時間なし)
      html = open_hint(view, "m3")
      body = render(element(view, "#m3-hint-body"))

      for text <- [
            "困ったときは、<strong>生成AI</strong>に相談してみましょう。使う生成AIは、講師が案内します。",
            "※今日は架空のデータを使っています。業務では、個人情報やお客さんのデータは生成AIに入れません。",
            "聞き方によって、返ってくる答えの質が大きく変わります。どちらが役に立つ答えになるか、試してみてください。",
            "<li>何が起きたかだけを伝える。</li>",
            "<li>実行したSQLとテーブルの中身も一緒に伝える。</li>"
          ] do
        assert body =~ text, "ヒントの文言が違う: #{text}"
      end

      refute body =~ "※今日のデータは架空です。"
      assert at(body, "講師が案内します。") < at(body, "※今日は架空のデータ")
      assert at(body, "※今日は架空のデータ") < at(body, "聞き方によって")
      assert at(body, "聞き方によって") < at(body, "何が起きたかだけを伝える。")
      assert at(body, "一緒に伝える。") < at(body, "プロンプト例")

      # プロンプト例: 列が揃っていて、本来の価格が箇条書き
      assert html =~ "id | 名前       | 価格 | 在庫"
      assert html =~ "1  | コピー用紙 | 150  | 24"
      assert html =~ "【本来の価格】\n- コピー用紙 480円\n- ファイル 250円"
      refute html =~ "コピー用紙 480円、ファイル 250円"
    end

    test "ミッション4: ヒントは、会員テーブルをSELECTで確かめるよう促す(SQLのブロックは出さない)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m4")
      html = open_hint(view, "m4")
      assert html =~ "原因がそのまま書いてある"
      assert html =~ "会員テーブルの中身も、SELECTで確かめてみましょう。"
      refute html =~ "次のSQLで確かめられます"
      refute html =~ "SELECT * FROM 会員;"
    end

    test "ミッション３(内部名m4): ヒントの最後に、SQLとエラーメッセージを伝えるプロンプト例(コピーボタン付き)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m4")
      open_hint(view, "m4")
      body = render(element(view, "#m4-hint-body"))

      assert has_element?(view, "#m4-hint-body p.font-bold", "プロンプト例")
      assert body =~ "次のように、SQLとエラーメッセージを一緒に伝えます。"
      assert at(body, "SELECTで確かめてみましょう。") < at(body, "プロンプト例")
      assert at(body, "プロンプト例") < at(body, "次のように、SQLとエラーメッセージ")
      assert at(body, "次のように、SQLとエラーメッセージ") < at(body, ~s(id="m4-prompt"))

      [prompt] =
        body
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#m4-prompt")
        |> Enum.map(&LazyHTML.text/1)

      assert prompt ==
               """
               会員登録のデータをデータベースに追加しようとしたら、次のエラーが出ました。
               原因として考えられることをあげてください。

               【実行したSQL】
               INSERT INTO 会員 (名前, メールアドレス) VALUES ('佐藤 さくら', 'sakura@example.com');

               【エラーメッセージ】
               UNIQUE constraint failed: 会員.メールアドレス\
               """

      assert has_element?(
               view,
               ~s(button#m4-prompt-copy[data-target="#m4-prompt"][phx-hook]),
               "コピー"
             )
    end

    test "ミッション１(内部名m2): ヒントのWHEREの説明は、条件・比較の記号・つなぎ方の3行(スライドの表と同じ記号)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      start_mission(view, "m2")
      open_hint(view, "m2")

      # SQL例の前置きの行はない(SQL例のボタンはそのまま)
      refute render(element(view, "#m2-hint-body")) =~ "SQL例（CRUDの順"
      assert has_element?(view, "#m2-hint-body #m2-hint-examples button", "作成（C）")

      # (テストの描画では、隣り合う code の間の空白が落ちるので、記号の並びと文を分けて見る)
      lines =
        view
        |> element("#m2-hint-where")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("p")
        |> Enum.to_list()

      assert length(lines) == 3

      codes =
        Enum.map(lines, fn line ->
          line |> LazyHTML.query("code") |> Enum.map(&LazyHTML.text/1)
        end)

      assert codes == [
               ["WHERE"],
               ["=", "<>", "!=", "<", ">", "<=", ">="],
               ["AND", "OR"]
             ]

      texts = Enum.map(lines, &(&1 |> LazyHTML.text() |> String.replace(~r/\s+/, "")))

      assert texts == [
               "WHEREは「どの行に対して」を指定する条件です。",
               "比較の記号：=（等しい）、<>!=（等しくない）、<>（より小さい・より大きい）、<=>=（以下・以上）",
               "条件をつなぐ：AND（かつ）、OR（または）"
             ]

      # SQL例のボタンのあとに置く
      body = render(element(view, "#m2-hint-body"))
      assert at(body, ~s(id="m2-hint-examples")) < at(body, ~s(id="m2-hint-where"))
    end

    test "プロンプト例の「コピー」ボタンは、見出しと同じ行の右端にある(ミッション２・３)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for m <- ~w(m3 m4) do
        start_mission(view, m)
        open_hint(view, m)
        header = "##{m}-prompt-header.flex.justify-between"

        # 見出しとボタンが同じ行。ボタンだけの行はない
        assert has_element?(view, "#{header} > p.font-bold:first-child", "プロンプト例")

        assert has_element?(
                 view,
                 ~s(#{header} > button##{m}-prompt-copy[data-target="##{m}-prompt"][phx-hook]:last-child),
                 "コピー"
               )

        refute has_element?(view, "##{m}-hint-body div.justify-end > ##{m}-prompt-copy")
        # 見出しは1つだけ(別の段落に重ねて出さない)
        assert render(element(view, "##{m}-hint-body")) |> String.split("プロンプト例") |> length() == 2
      end

      # ミッション３の説明の文は、見出しの行の下・プロンプトの枠の上に残す
      assert has_element?(
               view,
               "#m4-prompt-header + p",
               "次のように、SQLとエラーメッセージを一緒に伝えます。"
             )

      assert has_element?(view, "#m4-prompt-header + p + pre#m4-prompt")

      # ミッション２は、見出しの行のすぐ下がプロンプトの枠
      render_click(view, "switch_tab", %{"tab" => "m3"})
      assert has_element?(view, "#m3-prompt-header + pre#m3-prompt")
    end

    test "ミッション１(内部名m2): 追加指令の3つの問いは、末尾に「。」が付く", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      complete_m2(view)

      questions =
        view
        |> element("#m2-challenge")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("ol > li")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert questions == [
               "商品を価格が高い順に並べて表示せよ。",
               "価格が200円以上で、在庫が10個未満の商品を探し出せ。",
               "名前に「ペン」を含む商品を、あいまい検索で探し出せ。"
             ]
    end
  end
end
