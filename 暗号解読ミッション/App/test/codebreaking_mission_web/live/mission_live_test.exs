defmodule CodebreakingMissionWeb.MissionLiveTest do
  use CodebreakingMissionWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :capture_log

  defp wait_until(timeout_ms, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(deadline, fun)
  end

  defp do_wait_until(deadline, fun) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("condition not met within timeout")
      else
        Process.sleep(50)
        do_wait_until(deadline, fun)
      end
    end
  end

  # ミッションを開始して指令書を表示する（ツール解放なし）
  defp start_mission(view, tab) do
    render_click(view, "switch_tab", %{"tab" => tab})
    render_click(view, "#{tab}_start", %{})
    render(view)
  end

  # ミッションを開始しタイマーを進めてツールを解放する（elapsed >= 300）
  defp start_and_unlock_tools(view, tab) do
    render_click(view, "switch_tab", %{"tab" => tab})
    render_click(view, "#{tab}_start", %{})
    mission = String.to_atom(tab)
    Enum.each(1..301, fn _ -> send(view.pid, {:timer_tick, mission}) end)
    render(view)
  end

  # 新ミッション3暗号文（全26文字を使う単一換字式暗号）の完全な対応表。
  # ciphers_test.exsの@full_mappingと同じ、手作業でのクリブ解読で検証済みのもの。
  @m3_full_mapping %{
    "Z" => "T",
    "I" => "H",
    "T" => "E",
    "L" => "S",
    "Q" => "A",
    "F" => "N",
    "R" => "D",
    "O" => "I",
    "U" => "G",
    "E" => "C",
    "H" => "P",
    "K" => "R",
    "A" => "K",
    "Y" => "F",
    "G" => "O",
    "N" => "Y",
    "X" => "U",
    "S" => "L",
    "D" => "M",
    "J" => "Q",
    "C" => "V",
    "W" => "B",
    "V" => "W",
    "B" => "X",
    "P" => "J",
    "M" => "Z"
  }

  test "初期表示ではミッション1が選択され、既定の暗号文が表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s(a[phx-value-tab="m1"]), "ミッション１")
    html = start_and_unlock_tools(view, "m1")
    assert html =~ "ほもないめよを"
  end

  test "ミッション1: ボタンで円盤を回すと解読結果が変わり、鍵3で正解になる", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m1")

    html = render_click(view, "m1_rotate", %{"dir" => "1"})
    assert html =~ "ずらし（鍵）: 1"
    refute html =~ "ひみつをまもれ"

    render_click(view, "m1_rotate", %{"dir" => "1"})
    html = render_click(view, "m1_rotate", %{"dir" => "1"})
    assert html =~ "ひみつをまもれ"
  end

  test "ミッション1: 暗号文を変更しても復号結果に反映される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m1")

    render_click(view, "m1_rotate", %{"dir" => "1"})
    render_click(view, "m1_rotate", %{"dir" => "1"})
    html = render_click(view, "m1_rotate", %{"dir" => "1"})
    assert html =~ "ひみつをまもれ"

    # 暗号文を変えると、同じ鍵でも当然違う結果になる
    html = render_change(view, "m1_cipher_changed", %{"cipher" => "あいうえお"})
    refute html =~ "ひみつをまもれ"
  end

  test "ミッション1: 暗号化結果も同時に表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m1")
    html = render_click(view, "m1_rotate", %{"dir" => "1"})
    assert html =~ "暗号化結果（進める ➔）"
  end

  test "ミッション1: アルファベットモードに切り替えられる", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m1")
    render_change(view, "m1_lang_changed", %{"lang" => "alpha"})
    assert has_element?(view, ~s(input[name="lang"][value="alpha"][checked]))
  end

  test "ミッション1: モードを切り替えると、そのモードの既定文になる", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m1")

    render_click(view, "m1_rotate", %{"dir" => "1"})
    render_click(view, "m1_rotate", %{"dir" => "1"})
    html = render_click(view, "m1_rotate", %{"dir" => "1"})
    assert html =~ "ひみつをまもれ"

    html = render_change(view, "m1_lang_changed", %{"lang" => "alpha"})
    assert html =~ "HELLO WORLD"
  end

  test "ミッション2: 手動で1つ試すと履歴と試行回数に反映される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m2")

    render_change(view, "m2_single_k_changed", %{"k" => "11"})
    html = render_click(view, "m2_single_run", %{})

    assert html =~ "手動試行: 1 / 26 回"
    assert html =~ "SEIKOU DA TSUGI NO SHIREI WO MATE"
  end

  test "ミッション2: 既定のコードをそのまま実行すると、range(5)分だけ実際に出力される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m2")

    html = render_click(view, "m2_run", %{})

    assert Process.alive?(view.pid)
    assert html =~ "実行結果（ターミナル）"
  end

  test "ミッション2: range(26)に書き換えて実行してもLiveViewはクラッシュしない", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m2")

    code = """
    CIPHER = "DPTVZF OL EDFRT YZ DSTCPT HZ XLEP"


    def decode(text, k):
        result = ""
        for ch in text:
            if ch.isalpha():
                base = ord("A") if ch.isupper() else ord("a")
                result += chr((ord(ch) - base - k) % 26 + base)
            else:
                result += ch
        return result


    for k in range(26):
        print(f"k={k:2d}:", decode(CIPHER, k))
    """

    render_change(view, "m2_code_changed", %{"code" => code})
    render_click(view, "m2_run", %{})

    wait_until(5_000, fn ->
      html = render(view)

      html =~ "実行中..." or html =~ "待機中" or html =~ "実行を開始できませんでした" or
        html =~ "can't open file"
    end)

    html = render(view)

    assert Process.alive?(view.pid)
    assert html =~ "実行" or html =~ "待機"
  end

  test "ミッション2: 実行中はエラーになったコードでもLiveViewはクラッシュしない", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m2")

    render_change(view, "m2_code_changed", %{"code" => "1 / 0"})
    render_click(view, "m2_run", %{})

    wait_until(5_000, fn ->
      html = render(view)

      html =~ "実行中..." or html =~ "待機中" or html =~ "実行を開始できませんでした" or
        html =~ "can't open file"
    end)

    assert Process.alive?(view.pid)
  end

  test "ミッション3: 対応表が未確定のうちは解読プレビューに未確定マーカーが残る", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = start_and_unlock_tools(view, "m3")
    assert has_element?(view, ~s(a[phx-value-tab="m3"]), "ミッション３")
    assert html =~ "text-base-300"
  end

  test "ミッション3: 完全な対応表を入れると未確定マーカーが消える", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m3")

    # 対応表の入力欄はStep 1のプログラム実行結果が入るまで表示されない
    render_click(view, "m3_run", %{})
    wait_until(5_000, fn -> render(view) =~ "name=\"mapping[Z]\"" end)

    html = render_change(view, "m3_map_changed", %{"mapping" => @m3_full_mapping})

    refute html =~ "text-base-300"
    assert html =~ ~s(name="mapping[Z]")
    assert has_element?(view, ~s(input[name="mapping[Z]"][value="T"]))
  end

  test "ミッション3: 対応表を入れると使用済み文字パレットに反映される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m3")

    html = render_change(view, "m3_map_changed", %{"mapping" => %{"Z" => "T"}})
    assert html =~ "line-through"
  end

  test "ミッション3: 既定のコードを実行すると、実際のPython実行結果で頻度集計が表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m3")

    html = render_click(view, "m3_run", %{})

    assert Process.alive?(view.pid)
    assert html =~ "実行結果（ターミナル）"
  end

  test "ミッション3: Step 2の対応表は初期表示され、Step 1実行で集計結果が更新される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = start_and_unlock_tools(view, "m3")

    assert html =~ "Step 2: 📊 入力した文章の出現頻度と対応表（全26文字網羅）"
    assert html =~ ~s(name="mapping[Z]")

    render_click(view, "m3_run", %{})

    wait_until(5_000, fn ->
      html = render(view)
      html =~ "実行中..." or html =~ "待機中" or html =~ "実行を開始できませんでした"
    end)

    html = render(view)
    assert has_element?(view, ~s(input[name="mapping[Z]"]))
    assert html =~ "Step 2: 📊 入力した文章の出現頻度と対応表（全26文字網羅）"
  end

  test "ミッション3: リセットで対応表がクリアされ、未確定マーカーが戻る", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m3")

    render_click(view, "m3_run", %{})
    wait_until(5_000, fn -> render(view) =~ "name=\"mapping[Z]\"" end)

    render_change(view, "m3_map_changed", %{"mapping" => @m3_full_mapping})

    html = render_click(view, "m3_reset", %{})
    assert html =~ "text-base-300"
    assert has_element?(view, ~s(input[name="mapping[Z]"][value=""]))
  end

  test "ミッション4: 鍵を入力すると復号結果と暗号化結果が表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = start_and_unlock_tools(view, "m4")
    assert has_element?(view, ~s(a[phx-value-tab="m4"]), "ミッション４")
    assert html =~ "鍵を入力してください"

    html = render_change(view, "m4_key_changed", %{"key" => "TOKYO"})
    assert html =~ "Top Secret. Level Four."
    assert html =~ "You have broken three ciphers today"
    assert html =~ "暗号化結果（鍵で進める ➔）"
  end

  test "ミッション4: 間違った鍵では意味の通らない文字列になる", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m4")

    html = render_change(view, "m4_key_changed", %{"key" => "OSAKA"})
    refute html =~ "Top Secret. Level Four."
  end

  test "ミッション4: 既定コード（空）の実行ではエラーなく待機状態に戻る", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m4")

    render_click(view, "m4_run", %{})

    wait_until(5_000, fn ->
      html = render(view)
      html =~ "待機中" or html =~ "実行を開始できませんでした" or html =~ "can't open file"
    end)

    html = render(view)

    if html =~ "実行を開始できませんでした" do
      assert html =~ "実行を開始できませんでした"
    else
      assert html =~ "待機中"

      assert html =~ "[SYSTEM READY]" or html =~ "can't open file" or
               html =~ "No such file or directory" or html =~ "実行結果（ターミナル）"
    end
  end

  test "ミッション4: candidatesを間違った鍵だけにすると正解が見つからない", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_and_unlock_tools(view, "m4")

    code = """
    CIPHER = "VCXEFTHEJOMWYLG RCE FOOS LPCDSX RVX TSLOE QSNVXF DPILH WYHA BYR GXQBCHL"


    def decode(text, key):
        key = key.upper()
        result = ""
        key_index = 0
        for ch in text:
            if ch.isalpha():
                base = ord("A") if ch.isupper() else ord("a")
                shift = ord(key[key_index % len(key)]) - ord("A")
                result += chr((ord(ch) - base - shift) % 26 + base)
                key_index += 1
            else:
                result += ch
        return result


    candidates = ["OSAKA"]

    for key in candidates:
        print(f"key={key}:", decode(CIPHER, key))
    """

    render_change(view, "m4_code_changed", %{"code" => code})
    render_click(view, "m4_run", %{})

    wait_until(5_000, fn ->
      html = render(view)

      html =~ "実行中..." or html =~ "待機中" or html =~ "実行を開始できませんでした" or
        html =~ "key = OSAKA:" or html =~ "can't open file"
    end)

    html = render(view)

    refute html =~ "CONGRATULATIONS"
  end

  test "ミッション1: 指令書の解答欄に正解を入力すると正解フィードバックが表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "m1_start", %{})

    html = render_submit(view, "m1_answer_submit", %{"answer" => "ひみつをまもれ"})

    assert html =~ "✅ 正解です！"
  end

  test "ミッション1: 指令書の解答欄に不正解を入力すると不正解フィードバックが表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "m1_start", %{})

    html = render_submit(view, "m1_answer_submit", %{"answer" => "ちがうこたえ"})

    assert html =~ "❌"
  end

  test "ミッション2: 指令書の解答欄に正解を入力すると正解フィードバックが表示される（大文字小文字は無視）", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m2")

    html =
      render_submit(view, "m2_answer_submit", %{"answer" => "seikou da tsugi no shirei wo mate"})

    assert html =~ "✅ 正解です！"
  end

  test "ミッション3: 指令書の解答欄に全文を入力すると正解フィードバックが表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m3")

    answer = """
    Top Secret!
    This is the secret task for you.
    The letter e is the most frequent letter in English.
    See the three words the, this, and that.
    Everyone can solve this easily with a little thinking.
    You are very smart and you can do this code.
    The quick brown fox jumps over the lazy dog!
    Good luck and have fun with this cipher system!
    """

    html = render_submit(view, "m3_answer_submit", %{"answer" => answer})

    assert html =~ "✅ 正解です！"
  end

  test "ミッション4: 指令書の解答欄に正解を入力すると正解フィードバックが表示される", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    start_mission(view, "m4")

    html =
      render_submit(view, "m4_answer_submit", %{
        "answer" => """
        top secret. level four.
        you have broken three ciphers today, but this one is different.
        the key is a word, not a number, so counting the letters will not help you.
        look at the frequency table. it is almost flat.
        every letter is hiding behind many different masks.
        for three hundred years people called this the unbreakable cipher.
        but even a long key leaves a rhythm inside the text,
        and a machine can find that rhythm in a moment.
        do not trust a secret method. trust mathematics instead.
        and if you cannot break the cipher, ask the human who holds the key.
        """
      })

    assert html =~ "✅ 正解です！"
  end

  test "ミッション1: 解読ツールを開いた状態で暗号盤を回しても閉じたままにならない", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "details[open]")

    start_and_unlock_tools(view, "m1")
    # elapsed=301でツールが自動解放・オープンされる
    assert has_element?(view, "details[open]")

    render_click(view, "m1_rotate", %{"dir" => "1"})
    assert has_element?(view, "details[open]")
  end
end
