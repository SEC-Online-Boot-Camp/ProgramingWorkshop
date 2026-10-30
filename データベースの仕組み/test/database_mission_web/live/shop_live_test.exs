defmodule DatabaseMissionWeb.ShopLiveTest do
  use DatabaseMissionWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DatabaseMissionWeb.TestHelpers

  @moduletag :capture_log

  defp start_mission(view, tab) do
    render_click(view, "switch_tab", %{"tab" => tab})
    render_click(view, "start", %{"mission" => tab})
  end

  defp run_sql(view, mission, sql) do
    view |> form("##{mission}-form", %{"sql" => sql}) |> render_submit()
    render_async(view, 5_000)
  end

  # 通販サイト（別ページ）を開き、商品のデータ（m2 / m3）を切り替えて、表示内容を返す
  defp products(conn, source) do
    {:ok, view, _html} = live(conn, ~p"/shop")
    view |> form("#shop-source-form", %{"source" => source}) |> render_change()
    render(element(view, "#shop-products"))
  end

  setup %{conn: conn} do
    conn = participant_conn(conn)
    {:ok, mission, _html} = live(conn, ~p"/")
    %{conn: conn, mission: mission}
  end

  describe "別ページ" do
    test "ミッションの画面とは別のページで、ミッションのタブには含まれない", %{conn: conn, mission: mission} do
      {:ok, _view, html} = live(conn, ~p"/shop")
      assert html =~ "通販サイト"
      assert html =~ "商品の画面"
      assert html =~ "会員登録画面"

      tabs = render(element(mission, "[role=tablist]"))
      refute tabs =~ "通販サイト"
    end

    test "ミッションを始める前は、どちらの画面も案内が出る", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/shop")
      assert length(Regex.scan(~r/ミッションを始めると、表示されます/, html)) == 2
      refute has_element?(view, "#signup-form")
      refute html =~ "コピー用紙"

      for source <- ~w(m2 m3) do
        view |> form("#shop-source-form", %{"source" => source}) |> render_change()
        assert render(element(view, "#shop-products")) =~ "ミッションを始めると、表示されます"
      end
    end

    test "見るだけで、SQLの入力欄や操作ボタンはない", %{conn: conn, mission: mission} do
      start_mission(mission, "m2")
      {:ok, view, _html} = live(conn, ~p"/shop")

      refute has_element?(view, "#shop-products textarea")
      refute has_element?(view, "#shop-products form")
      refute has_element?(view, "#shop-products button")
    end

    test "別の受講者（別のブラウザ）のデータは見えない", %{conn: conn, mission: mission} do
      start_mission(mission, "m2")
      assert products(conn, "m2") =~ "コピー用紙"

      other = participant_conn(build_conn())
      assert products(other, "m2") =~ "ミッションを始めると、表示されます"
    end

    test "画面を再読み込みすると、ミッションのデータと一緒に、通販サイトの表示も初期に戻る", %{conn: conn, mission: mission} do
      start_mission(mission, "m2")
      assert products(conn, "m2") =~ "コピー用紙"

      # 同じ受講者が、ミッションの画面を開き直す（再読み込み）
      {:ok, _reloaded, _html} = live(conn, ~p"/")
      assert products(conn, "m2") =~ "ミッションを始めると、表示されます"
    end

    test "識別子が正しくないセッションは、正しい識別子に作り直される", _context do
      conn = Plug.Test.init_test_session(build_conn(), %{"participant_id" => "../evil"})
      conn = get(conn, ~p"/shop")
      id = Plug.Conn.get_session(conn, "participant_id")
      assert DatabaseMission.Participant.valid?(id)
      refute id =~ "evil"
      assert html_response(conn, 200) =~ "通販サイト"
    end
  end

  describe "商品の画面" do
    test "ミッション2のデータを、通販サイトの画面として表示する(在庫が少ないときは残りわずか)", %{conn: conn, mission: mission} do
      start_mission(mission, "m2")
      html = products(conn, "m2")

      for text <- ["コピー用紙", "480円", "在庫 24個", "残りわずか（8個）", "残りわずか（5個）", "📄", "🖊️", "📁"] do
        assert html =~ text, "表示されていない: #{text}"
      end

      refute html =~ "ミッションを始めると"
    end

    test "SQLでデータを変えたあと、「更新」を押すと最新になる", %{conn: conn, mission: mission} do
      start_mission(mission, "m2")
      {:ok, view, _html} = live(conn, ~p"/shop")
      refute render(element(view, "#shop-products")) =~ "付箋"

      run_sql(mission, "m2", "INSERT INTO 商品 VALUES (4, '付箋', 200, 12);")

      # 更新するまでは、開いた時点の内容のまま
      refute render(element(view, "#shop-products")) =~ "付箋"

      view |> element("button", "更新") |> render_click()
      html = render(element(view, "#shop-products"))
      assert html =~ "付箋"
      assert html =~ "200円"
    end

    test "ミッション2とミッション3は別のデータで、切り替えて表示する", %{conn: conn, mission: mission} do
      start_mission(mission, "m2")
      start_mission(mission, "m3")

      # ミッション3は、全商品150円に壊れた状態
      html = products(conn, "m3")
      assert length(Regex.scan(~r/150円/, html)) == 3
      refute html =~ "480円"

      # ミッション2は、正常なデータ
      html = products(conn, "m2")
      assert html =~ "480円"
      refute html =~ "150円"

      # ミッション3を直しても、ミッション2は変わらない
      run_sql(mission, "m3", """
      UPDATE 商品 SET 価格 = 480 WHERE id = 1;
      UPDATE 商品 SET 価格 = 250 WHERE id = 3;
      """)

      html = products(conn, "m3")
      assert html =~ "480円"
      assert html =~ "250円"
      assert length(Regex.scan(~r/150円/, html)) == 1

      assert products(conn, "m2") =~ "120円"
    end
  end

  describe "会員登録画面" do
    setup %{mission: mission} do
      start_mission(mission, "m4")
      :ok
    end

    defp signup(conn, attrs \\ %{}) do
      {:ok, view, _html} = live(conn, ~p"/shop")
      html = view |> form("#signup-form", attrs) |> render_submit()
      {view, html}
    end

    test "ミッション4を始めると、名前とメールアドレスの入力欄と登録ボタンが出る(初期値はお客さん)", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/shop")
      assert has_element?(view, "#signup-form")
      assert html =~ ~s(value="佐藤 さくら")
      assert html =~ ~s(value="sakura@example.com")
      assert has_element?(view, "#signup-form button", "登録する")
      refute has_element?(view, "#signup-guide")
    end

    test "同じメールアドレスの会員が残っていると、登録できない。お客さんには原因を見せない", %{conn: conn, mission: mission} do
      {_view, html} = signup(conn)

      assert html =~ "登録できませんでした。しばらくしてからお試しください。"
      refute html =~ "登録できました"
      refute html =~ "UNIQUE"

      # 原因は、ミッション4の画面の「サーバーの記録」に出る
      record = render(element(mission, "#m4-server-log"))
      assert record =~ "UNIQUE constraint failed: 会員.メールアドレス"
      assert record =~ "INSERT INTO 会員"
    end

    test "別のメールアドレスなら登録でき、ミッション4のデータに反映される", %{conn: conn, mission: mission} do
      {_view, html} = signup(conn, %{"email" => "sakura2@example.com"})

      assert html =~ "登録できました"
      refute html =~ "登録できませんでした"

      result = run_sql(mission, "m4", "SELECT * FROM 会員 WHERE メールアドレス = 'sakura2@example.com';")
      assert result =~ "sakura2@example.com"
      assert render(element(mission, "#m4-server-log")) =~ "→ OK"
    end

    test "名前やメールアドレスに ' が入っていても、SQLとして壊れない", %{conn: conn, mission: mission} do
      {_view, html} = signup(conn, %{"name" => "O'Reilly", "email" => "o'reilly@example.com"})
      assert html =~ "登録できました"

      result = run_sql(mission, "m4", "SELECT 名前 FROM 会員 WHERE id = 4;")
      assert result =~ "O&#39;Reilly"
    end
  end
end
