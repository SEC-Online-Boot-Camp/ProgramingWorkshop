defmodule DatabaseMissionWeb.MissionLive do
  @moduledoc """
  「システムトラブルを解決せよ！」のミッションを1画面で提供する（画面の内部では
  m2・m3・m4・injectという名前のまま。画面に出す番号は、1・2・3・4と振り直している）。

    * ミッション1（内部名 m2）: SQLで商品テーブルを直接操作する
    * ミッション2（内部名 m3）: WHERE を付け忘れた UPDATE で壊れた価格を復旧する
    * ミッション3（内部名 m4）: 会員登録の UNIQUE 制約エラーの原因を突き止める

  これらは、受講者ごと・ミッションごとに別のSQLiteファイルを持つ。
  ファイルはミッションの開始時に作り、「最初のデータに戻す」で作り直す。
  状態は LiveView の assigns にしか持たないので、再読み込みすると最初からになる。
  """

  use DatabaseMissionWeb, :live_view

  import DatabaseMissionWeb.ShopComponents

  alias DatabaseMission.{Missions, Participant, Sql, SqlCheck}

  # SQLの入力欄（ターミナル。入出力が積み重なる）を持つミッション
  @sql_missions ~w(m2 m3 m4)
  # 折りたたみのSQL例を持つもの（追加指令の区画の中）
  @examples_missions ~w(m2 m3 m4)
  # ヒントを持つもの。ヒントは開始直後から見られる（待ち時間なし）
  @hint_missions ~w(m2 m3 m4 inject)

  # ターミナルの黒い部分の高さ。右隣の通販サイトの画面も、同じ高さにする
  @terminal_height "h-80"

  # 制限時間（秒）。スライドのスケジュールの時間と合わせる
  @timers %{"m2" => 900, "m3" => 900, "m4" => 900, "inject" => 300}

  @impl true
  def mount(_params, session, socket) do
    m4_customer = Missions.m4_customer()

    socket =
      socket
      |> assign(page_title: "システムトラブルを解決せよ！", tab: "m2")
      |> assign(m2_done: MapSet.new())
      |> assign(m3_fixed: false)
      |> assign(for m <- @examples_missions, into: %{}, do: {k(m, :examples_open), false})
      |> assign(for m <- @hint_missions, into: %{}, do: {k(m, :hint_open), false})
      |> assign(
        inject_input: "",
        inject_mode: "unsafe",
        inject_history: [],
        inject_db: nil,
        inject_outcome: nil
      )
      |> assign(inject_running: false, inject_brief_open: true)
      |> assign(inject_started: false, inject_elapsed: 0)
      |> assign(m4_register: nil, m4_found: false, m4_error_seen: false, m4_registered: false)
      |> assign(pid: session["participant_id"])
      |> assign(m4_shop_name: m4_customer.name, m4_shop_email: m4_customer.email)
      |> assign(m2_challenge: false, m3_challenge: false, m4_challenge: false)

    socket =
      Enum.reduce(~w(m2 m3 m4), socket, fn m, acc ->
        assign(acc, [{k(m, :started), false}, {k(m, :elapsed), 0}, {k(m, :brief_open), true}])
      end)

    socket =
      Enum.reduce(@sql_missions, socket, fn m, acc ->
        assign(acc, [
          {k(m, :db), nil},
          {k(m, :sql), default_sql(m)},
          {k(m, :running), false},
          {k(m, :outcome), nil},
          {k(m, :table), nil},
          {k(m, :history), []}
        ])
      end)

    # 画面を開いた（再読み込みした）ときは、ミッションのデータが最初に戻るので、
    # この受講者のミッションのデータベースも消す。通販サイト（別ページ）からの
    # 会員登録の結果を、PubSubで受け取る
    if connected?(socket) do
      Participant.delete_databases(socket.assigns.pid)
      Phoenix.PubSub.subscribe(DatabaseMission.PubSub, Participant.topic(socket.assigns.pid))
    end

    {:ok, socket}
  end

  # ── タブ・タイマー・折りたたみ ─────────────────────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when is_map_key(@timers, tab) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("start", %{"mission" => m}, socket) when is_map_key(@timers, m) do
    if timer_enabled?(), do: Process.send_after(self(), {:timer_tick, m}, 1000)
    socket = assign(socket, [{k(m, :started), true}, {k(m, :elapsed), 0}])

    socket =
      cond do
        m in @sql_missions -> prepare_database(socket, m)
        m == "inject" and is_nil(socket.assigns.inject_db) -> prepare_inject(socket)
        true -> socket
      end

    {:noreply, socket}
  end

  def handle_event("toggle_brief", %{"mission" => m}, socket)
      when is_map_key(@timers, m) or m == "inject" do
    {:noreply, update(socket, k(m, :brief_open), &(!&1))}
  end

  # ヒントの開閉は、サーバーで覚える。覚えないと、タイマーが毎秒画面を描き直すときに、
  # サーバーの描いた（open の付かない）<details> で上書きされて、開いたヒントが閉じてしまう
  def handle_event("toggle_hint", %{"mission" => m}, socket) when m in @hint_missions do
    {:noreply, update(socket, k(m, :hint_open), &(!&1))}
  end

  # ── ミッション2〜4: SQLコンソール ──────────────────────

  def handle_event("sql_changed", %{"mission" => m, "sql" => sql}, socket)
      when m in @sql_missions do
    {:noreply, assign(socket, k(m, :sql), sql)}
  end

  def handle_event("toggle_examples", %{"mission" => m}, socket) when m in @examples_missions do
    {:noreply, update(socket, k(m, :examples_open), &(!&1))}
  end

  def handle_event("use_example", %{"mission" => "m2", "sql" => sql}, socket) do
    {:noreply, assign(socket, :m2_sql, sql)}
  end

  # ── ミッション3（内部名m4）の、埋め込みの会員登録画面 ──────────

  def handle_event("m4_signup_changed", %{"name" => name, "email" => email}, socket) do
    {:noreply, assign(socket, m4_shop_name: name, m4_shop_email: email)}
  end

  def handle_event("m4_signup", %{"name" => name, "email" => email}, socket) do
    socket = assign(socket, m4_shop_name: name, m4_shop_email: email)

    if Participant.db_exists?(socket.assigns.pid, "m4") do
      # 結果は PubSub で知らせる。handle_info({:m4_register, ...}) が、
      # 「サーバーの記録」の表示と、課題の判定に反映する
      Participant.register_member(socket.assigns.pid, name, email)
    end

    {:noreply, socket}
  end

  # ── ターミナル（ミッション1〜3。内部名 m2〜m4） ─────────

  # ミッション4のターミナルは表示だけ。消すのは履歴だけで、予定のSQL・Web画面の結果・設定はそのまま
  def handle_event("clear_history", %{"mission" => "inject"}, socket) do
    {:noreply, assign(socket, :inject_history, [])}
  end

  def handle_event("clear_history", %{"mission" => m}, socket) when m in @sql_missions do
    {:noreply, assign(socket, k(m, :history), [])}
  end

  # ── SQLインジェクションの体験 ───────────

  def handle_event("inject_changed", %{"input" => input, "mode" => mode}, socket) do
    {:noreply, assign(socket, inject_input: input, inject_mode: normalize_mode(mode))}
  end

  def handle_event("inject_search", %{"input" => input, "mode" => mode}, socket) do
    mode = normalize_mode(mode)
    socket = assign(socket, inject_input: input, inject_mode: mode)
    db = socket.assigns.inject_db

    if socket.assigns.inject_running or is_nil(db) do
      {:noreply, socket}
    else
      {sql, params} = Missions.injection_query(injection_mode(mode), input)

      {:noreply,
       socket
       |> assign(:inject_running, true)
       |> start_async(:inject_search, fn -> {sql, params, Sql.query(db, sql, params)} end)}
    end
  end

  def handle_event("run", %{"mission" => m, "sql" => sql}, socket) when m in @sql_missions do
    db = socket.assigns[k(m, :db)]

    cond do
      String.trim(sql) == "" ->
        {:noreply, assign(socket, k(m, :sql), sql)}

      socket.assigns[k(m, :running)] or is_nil(db) ->
        {:noreply, assign(socket, k(m, :sql), sql)}

      found = SqlCheck.find_fullwidth(sql) ->
        # SQLiteに渡さずに止める（SQLiteは、ミスと違う場所を指すエラーを出すことがあるため）
        {:noreply,
         socket
         |> assign(k(m, :sql), "")
         |> append_history(m, {:query, sql, {:fullwidth, found}})}

      true ->
        extras = extras(m)

        # 実行したら、入力欄は空にする（打ったSQLと結果は、履歴に積む）
        {:noreply,
         socket
         |> assign([{k(m, :running), true}, {k(m, :sql), ""}])
         |> start_async(k(m, :run), fn -> {sql, Sql.run(db, sql, extras, track(m))} end)}
    end
  end

  def handle_event("reset", %{"mission" => m}, socket) when m in @sql_missions do
    Sql.delete_database(socket.assigns[k(m, :db)])

    socket =
      case m do
        "m2" ->
          assign(socket, m2_done: MapSet.new())

        "m3" ->
          assign(socket, m3_fixed: false)

        "m4" ->
          assign(socket,
            m4_register: nil,
            m4_found: false,
            m4_error_seen: false,
            m4_registered: false
          )
      end

    {:noreply,
     socket
     |> assign(k(m, :outcome), nil)
     |> append_history(m, {:note, "-- データベースを最初の状態に戻しました"})
     |> prepare_database(m)}
  end

  # ── 非同期実行の結果 ──────────────────────────────────

  @impl true
  def handle_async(:inject_search, {:ok, {sql, params, result}}, socket) do
    outcome = %{sql: sql, params: params, result: result}
    {:noreply, inject_finished(socket, outcome)}
  end

  def handle_async(:inject_search, {:exit, reason}, socket) do
    outcome = {:failed, "実行に失敗しました: #{inspect(reason)}"}
    {:noreply, inject_finished(socket, outcome)}
  end

  def handle_async(name, result, socket) do
    m = name |> Atom.to_string() |> String.replace_suffix("_run", "")
    socket = assign(socket, k(m, :running), false)

    case result do
      {:ok, {sql, {:ok, outcome}}} ->
        {:noreply,
         socket
         |> append_history(m, {:query, sql, {:ok, outcome}})
         |> apply_outcome(m, outcome)}

      {:ok, {sql, {:error, reason}}} ->
        {:noreply, append_history(socket, m, {:query, sql, {:error, reason}})}

      {:exit, reason} ->
        result = {:error, "実行に失敗しました: #{inspect(reason)}"}
        {:noreply, append_history(socket, m, {:query, "", result})}
    end
  end

  @impl true
  # 通販サイト（別ページ）の会員登録の結果。サーバーの記録として表示し、課題の判定に使う
  def handle_info({:m4_register, record}, socket) do
    socket =
      if record.error,
        do: assign(socket, :m4_error_seen, true),
        else: assign(socket, :m4_registered, true)

    # ログの欄は会員登録の画面の下にあり、画面の外に出ていることがあるので、見える位置までスクロールさせる。
    # 登録の結果を受け取ったときだけ送るので、タイマーの描き直しではスクロールしない
    {:noreply,
     socket
     |> assign(:m4_register, record)
     |> update_challenges()
     |> push_event("m4:show-server-log", %{})}
  end

  def handle_info({:timer_tick, m}, socket) do
    limit = @timers[m]
    elapsed = socket.assigns[k(m, :elapsed)] + 1

    if timer_enabled?() and elapsed < limit,
      do: Process.send_after(self(), {:timer_tick, m}, 1000)

    {:noreply, assign(socket, k(m, :elapsed), elapsed)}
  end

  # ── 内部処理 ──────────────────────────────────────────

  defp k(m, field), do: :"#{m}_#{field}"

  defp timer_enabled?, do: Application.get_env(:database_mission, :timer_ticks, true)

  defp seed("m2"), do: Missions.m2_seed()
  defp seed("m3"), do: Missions.m3_seed()
  defp seed("m4"), do: Missions.m4_seed()

  defp extras("m2"),
    do: [
      Missions.products_snapshot_sql(),
      Missions.m2_low_stock_sql(),
      Missions.m2_inserted_sql(),
      Missions.m2_updated_sql()
    ]

  defp extras("m3"), do: [Missions.products_snapshot_sql(), Missions.m3_fixed_sql()]
  defp extras("m4"), do: []

  # 受講者のSQLを1文実行するたびに調べる確認（途中の状態を知るため）。
  # ミッション2の課題4（付箋を一度登録して、今はない）の判定に使う
  defp track("m2"), do: [Missions.m2_inserted_sql()]
  defp track(_), do: []

  defp default_sql(_m), do: ""

  # 新しいデータベースを作り、テーブルの中身を表示用に読み込む
  # ミッションのデータベースは、通販サイト（別ページ）からも見えるように、
  # 受講者ごとの決まった名前にする
  defp db_path(socket, m), do: Participant.db_path(socket.assigns.pid, m)

  # ターミナルに、入出力を1つ積む（古いものは残る。多すぎるときは古い方から捨てる）
  defp append_history(socket, m, entry) do
    update(socket, k(m, :history), &Enum.take(&1 ++ [entry], -200))
  end

  defp prepare_database(socket, m) do
    with {:ok, db} <- Sql.new_database(seed(m), db_path(socket, m)),
         {:ok, outcome} <- Sql.run(db, "", extras(m)) do
      assign(socket, [{k(m, :db), db}, {k(m, :table), Enum.at(outcome.extras, 0)}])
    else
      {:error, reason} ->
        assign(socket, k(m, :outcome), {:failed, "データベースを準備できませんでした: #{reason}"})
    end
  end

  defp prepare_inject(socket) do
    case Sql.new_database(Missions.injection_seed()) do
      {:ok, db} ->
        assign(socket, :inject_db, db)

      {:error, reason} ->
        assign(socket, :inject_outcome, {:failed, "データベースを準備できませんでした: #{reason}"})
    end
  end

  defp normalize_mode("placeholder"), do: "placeholder"
  defp normalize_mode(_), do: "unsafe"

  defp injection_mode("placeholder"), do: :placeholder
  defp injection_mode(_), do: :unsafe

  # 検索の結果は、Web画面には最新の1回だけ、ターミナルには履歴として積む
  defp inject_finished(socket, outcome) do
    socket
    |> assign(inject_running: false, inject_outcome: outcome)
    |> update(:inject_history, &(&1 ++ [outcome]))
  end

  defp apply_outcome(socket, m, outcome) do
    socket =
      assign(socket, [{k(m, :outcome), outcome}, {k(m, :table), Enum.at(outcome.extras, 0)}])

    socket |> check(m, outcome) |> update_challenges()
  end

  # 必須の課題がすべて✅になったミッションの、追加指令の区画を表示する。
  # 一度表示したら、「最初のデータに戻す」で課題が未達成に戻っても、表示したままにする
  defp update_challenges(socket) do
    a = socket.assigns

    [
      {:m2_challenge, MapSet.size(a.m2_done) == 4},
      {:m3_challenge, a.m3_fixed},
      {:m4_challenge, a.m4_error_seen and a.m4_found and a.m4_registered}
    ]
    |> Enum.reduce(socket, fn
      {key, true}, acc -> assign(acc, key, true)
      {_key, false}, acc -> acc
    end)
  end

  # 課題の達成判定。一度達成した課題は、あとで表が変わっても達成のままにする

  # ミッション2は、CRUDに合わせた4つの課題。
  #   :insert    付箋の行を、一度でも作った（実行中の途中の状態も含む）
  #   :low_stock 実行結果の表が、在庫10個未満の商品の表と一致した
  #   :update    コピー用紙（id=1）の在庫が30で、ほかの行は初期データのまま
  #   :delete    付箋を一度作ったあとで、今は付箋の行がない（作る前の削除では達成しない）
  defp check(socket, "m2", outcome) do
    [_table, low_stock, inserted, updated] = outcome.extras
    inserted_now = match?(%{rows: [_ | _]}, inserted)
    inserted_ever = inserted_now or List.first(outcome.tracked, false)
    inserted_before = MapSet.member?(socket.assigns.m2_done, :insert)

    done =
      [
        {:insert, inserted_ever},
        {:low_stock, Enum.any?(outcome.results, &same_rows?(&1, low_stock))},
        {:update, match?(%{rows: [_ | _]}, updated)},
        {:delete, (inserted_before or inserted_ever) and not inserted_now}
      ]
      |> Enum.filter(fn {_, ok} -> ok end)
      |> Enum.map(fn {task, _} -> task end)

    update(socket, :m2_done, &MapSet.union(&1, MapSet.new(done)))
  end

  defp check(socket, "m3", outcome) do
    fixed = match?(%{rows: [_ | _]}, Enum.at(outcome.extras, 1))
    update(socket, :m3_fixed, &(&1 or fixed))
  end

  defp check(socket, "m4", outcome) do
    email = Missions.m4_customer().email

    found =
      Enum.any?(outcome.results, fn
        %{type: :rows, rows: rows} -> Enum.any?(rows, &(email in &1))
        _ -> false
      end)

    update(socket, :m4_found, &(&1 or found))
  end

  defp same_rows?(%{type: :rows, columns: c, rows: r}, %{columns: c, rows: r2}),
    do: Enum.sort(r) == Enum.sort(r2)

  defp same_rows?(_, _), do: false

  defp format_timer(sec),
    do: :io_lib.format("~2..0B:~2..0B", [div(sec, 60), rem(sec, 60)]) |> IO.iodata_to_binary()

  defp tab_class(current, this) do
    if current == this do
      "tab !bg-primary !text-primary-content font-bold rounded-t-lg shadow-sm border border-primary"
    else
      "tab !text-base-content/70 hover:!text-base-content hover:!bg-base-200 rounded-t-lg"
    end
  end

  defp change_message(-1), do: "実行しました"
  defp change_message(0), do: "0行を変更しました（条件に合う行がありませんでした）"
  defp change_message(n), do: "#{n}行を変更しました"

  defp cell(nil), do: "NULL"
  defp cell(value), do: to_string(value)

  # ── 共通コンポーネント ────────────────────────────────

  # 開始前の欄（開始ボタン）。開始したあとは、タイマーは指令書の見出しの行に出す
  attr :mission, :string, required: true
  attr :started, :boolean, required: true

  defp start_card(assigns) do
    ~H"""
    <div
      :if={not @started}
      id={"#{@mission}-start"}
      class="card bg-base-100 border border-base-300 shadow-sm p-4 mb-4 flex flex-row items-center gap-4"
    >
      <button class="btn btn-primary" phx-click="start" phx-value-mission={@mission}>🚀 開始</button>
      <span class="text-sm opacity-70">準備ができたら開始ボタンを押してください</span>
    </div>
    """
  end

  attr :mission, :string, required: true
  attr :open, :boolean, required: true
  attr :elapsed, :integer, required: true

  # ヒントと横に並べる段（高さ固定のgrid）の中では、下の余白を付けない
  attr :class, :string, default: "mb-4"
  slot :inner_block, required: true

  defp brief(assigns) do
    assigns = assign(assigns, :limit, @timers[assigns.mission])

    ~H"""
    <details
      id={"#{@mission}-brief-area"}
      class={["collapse collapse-arrow bg-base-100 border border-base-300 shadow-sm", @class]}
      open={@open}
    >
      <summary
        class="collapse-title font-bold text-primary flex flex-wrap items-center gap-x-4 gap-y-1"
        phx-click="toggle_brief"
        phx-value-mission={@mission}
      >
        <span id={"#{@mission}-brief-title"} class="text-xl">📜 指令書</span>
        <span
          id={"#{@mission}-brief-timers"}
          class="ml-auto flex flex-nowrap items-center gap-x-4"
        >
          <span :if={@elapsed >= @limit} class="badge badge-error font-bold">時間切れ</span>
          <span
            id={"#{@mission}-timer"}
            class="font-mono text-2xl font-bold tabular-nums text-primary leading-none"
          >
            {format_timer(max(0, @limit - @elapsed))}
          </span>
        </span>
      </summary>
      <%!-- daisyUIは開いたときに min-height: fit-content を付け、h-56 より長い中身で伸びてしまうので打ち消す。
           下の余白（開いたときに付く1rem）も半分にして、いちばん長いミッション4の指令書がスクロールせずに収まるようにする --%>
      <div class="collapse-content flex flex-col gap-1 h-56 !min-h-0 !pb-2 overflow-y-auto">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  # ヒント（開始直後から見られる）。指令書の右に、同じ高さ（h-72）の枠で置く。
  # 閉じている間は「ヒントを見る」ボタンだけ。開くと同じ枠の中に中身を出し、入りきらない分は枠の中でスクロールする。
  # 開閉はサーバーで覚える（handle_event("toggle_hint", ...)）。タイマーで描き直しても閉じない
  attr :mission, :string, required: true
  attr :open, :boolean, required: true

  # プロンプト例の無いヒント（ミッション１・４）は、余白を詰めて、枠の中でスクロールせずに収める
  attr :compact, :boolean, default: false
  slot :inner_block, required: true

  defp hint(assigns) do
    ~H"""
    <section
      id={"#{@mission}-hint"}
      class="h-72 rounded-box bg-base-100 border border-warning shadow-sm flex flex-col overflow-hidden"
    >
      <div :if={not @open} class="flex-1 flex items-center justify-center">
        <button
          type="button"
          id={"#{@mission}-hint-open"}
          class="btn btn-warning btn-lg"
          phx-click="toggle_hint"
          phx-value-mission={@mission}
        >
          💡 ヒントを見る
        </button>
      </div>

      <div
        :if={@open}
        class={[
          "flex items-center justify-between px-4 pb-1",
          if(@compact, do: "pt-2", else: "pt-3")
        ]}
      >
        <span class="font-bold">💡 ヒント</span>
        <button
          type="button"
          id={"#{@mission}-hint-close"}
          class="btn btn-ghost btn-sm"
          phx-click="toggle_hint"
          phx-value-mission={@mission}
        >
          ✕ 閉じる
        </button>
      </div>
      <div
        :if={@open}
        id={"#{@mission}-hint-body"}
        class={[
          "flex-1 min-h-0 overflow-y-auto px-4 flex flex-col text-sm",
          if(@compact, do: "pb-2 gap-1", else: "pb-3 gap-2")
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  # プロンプト例など、受講者が生成AIに貼り付ける文。「コピー」ボタンでクリップボードに入れる。
  # ボタンは見出し（「プロンプト例」）と同じ行の右端に置く。見出しと枠の間に入れる説明は inner_block に書く
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :title, :string, default: "プロンプト例"
  slot :inner_block

  defp copyable(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 mt-2">
      <div id={"#{@id}-header"} class="flex items-center justify-between gap-2">
        <p class="font-bold">{@title}</p>
        <button
          type="button"
          id={"#{@id}-copy"}
          class="btn btn-xs btn-outline"
          phx-hook=".CopyText"
          data-target={"##{@id}"}
        >
          📋 コピー
        </button>
      </div>
      {render_slot(@inner_block)}
      <pre
        id={@id}
        class="font-mono bg-neutral text-neutral-content rounded p-3 whitespace-pre-wrap select-text"
      >{@text}</pre>
    </div>
    """
  end

  attr :done, :boolean, required: true
  slot :inner_block, required: true

  defp task_item(assigns) do
    ~H"""
    <li class={["flex items-start gap-2", @done && "text-success font-bold"]}>
      <span class="w-5 shrink-0">{if @done, do: "✅", else: "⬜"}</span>
      <span>{render_slot(@inner_block)}</span>
    </li>
    """
  end

  attr :table, :map, required: true
  attr :id, :string, default: nil

  defp data_table(assigns) do
    ~H"""
    <%!-- 黒いサーバー側の画面の中に置くので、文字色を継がずに表の背景に合う色を指定する --%>
    <div class="overflow-x-auto rounded border border-base-300 bg-base-100 text-base-content">
      <table id={@id} class="table table-sm table-zebra">
        <thead>
          <tr>
            <th :for={c <- @table.columns} class="bg-base-200 text-base-content">{c}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @table.rows}>
            <td :for={v <- row} class="font-mono">{cell(v)}</td>
          </tr>
          <tr :if={@table.rows == []}>
            <td colspan={max(length(@table.columns), 1)} class="opacity-60 italic">（該当する行はありません）</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # ミッション1のヒントのSQL例（クリックで入力欄に入る）。
  # ミッション1の答え（在庫10個未満の検索、付箋の登録）と同じ文は入れない。CRUDの順に並べる
  defp m2_examples do
    [
      {"作成（C）", "INSERT INTO 商品 VALUES (4, 'ホッチキス', 600, 6);"},
      {"検索（R）", "SELECT * FROM 商品 WHERE 価格 >= 200;"},
      {"更新（U）", "UPDATE 商品 SET 在庫 = 20 WHERE id = 1;"},
      {"削除（D）", "DELETE FROM 商品 WHERE id = 4;"}
    ]
  end

  # ミッション1〜3で共通の、SQLの入力欄（sqlite3のコマンドラインのような、黒地のターミナル）。
  # 打ったSQLと結果が、上から順に積み重なる
  attr :mission, :string, required: true
  attr :db, :any, required: true
  attr :history, :list, required: true
  attr :sql, :string, required: true
  attr :running, :boolean, required: true

  defp terminal(assigns) do
    assigns =
      assign(assigns,
        height: @terminal_height,
        history_json:
          Jason.encode!(for({:query, sql, _} <- assigns.history, do: String.trim(sql)))
      )

    ~H"""
    <div>
      <div
        id={"#{@mission}-terminal"}
        class={[
          "terminal-font rounded-lg bg-black text-neutral-200 text-sm border border-neutral-700 shadow-sm flex flex-col",
          @height
        ]}
      >
        <div
          id={"#{@mission}-history"}
          phx-hook=".TerminalScroll"
          class="flex-1 min-h-0 overflow-y-auto overflow-x-auto p-3"
        >
          <div
            :for={{entry, i} <- Enum.with_index(@history)}
            id={"#{@mission}-entry-#{i}"}
            class="mb-3"
          >
            <.terminal_entry entry={entry} />
          </div>

          <form
            id={"#{@mission}-form"}
            phx-change="sql_changed"
            phx-submit="run"
            class="flex items-start gap-2"
          >
            <input type="hidden" name="mission" value={@mission} />
            <span class="text-green-400 select-none leading-5">&gt;</span>
            <textarea
              id={"#{@mission}-sql"}
              name="sql"
              rows="3"
              spellcheck="false"
              autocomplete="off"
              autocapitalize="off"
              phx-debounce="300"
              phx-hook=".Terminal"
              data-history={@history_json}
              class="flex-1 bg-transparent text-neutral-100 outline-none resize-none leading-5"
            >{@sql}</textarea>
          </form>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-x-4 gap-y-2 mt-2">
        <span :if={@running} class="text-xs font-bold text-primary">実行中...</span>
        <div class="flex gap-2">
          <button
            type="button"
            class="btn btn-outline btn-xs"
            phx-click="reset"
            phx-value-mission={@mission}
            data-confirm="データベースを最初の状態に戻します。よろしいですか？"
          >
            ↺ 最初のデータに戻す
          </button>
          <button
            type="button"
            class="btn btn-outline btn-xs"
            phx-click="clear_history"
            phx-value-mission={@mission}
          >
            🧹 画面を消去
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :any, required: true

  defp terminal_entry(assigns)

  defp terminal_entry(%{entry: {:note, text}} = assigns) do
    assigns = assign(assigns, :text, text)

    ~H"""
    <pre class="text-neutral-500">{@text}</pre>
    """
  end

  defp terminal_entry(%{entry: {:query, sql, result}} = assigns) do
    assigns = assign(assigns, sql: sql, result: result)

    ~H"""
    <pre :if={@sql != ""} class="text-green-300 whitespace-pre-wrap">{mark_wide_spaces(prompt_text(@sql))}</pre>
    <.terminal_output result={@result} sql={@sql} />
    """
  end

  attr :result, :any, required: true
  attr :sql, :string, required: true

  defp terminal_output(assigns)

  # 実行する前に、'…' の外に全角の記号が見つかった（SQLiteには渡していない）
  defp terminal_output(%{result: {:fullwidth, found}} = assigns) do
    line = Enum.at(String.split(assigns.sql, "\n"), found.line - 1)

    assigns =
      assign(assigns,
        message: SqlCheck.fullwidth_message(assigns.sql, found),
        line: line,
        col: found.col
      )

    ~H"""
    <pre class="fullwidth-error text-red-400 whitespace-pre-wrap">エラー: {@message}（実行していません）</pre>
    <.caret line={@line} col={@col} />
    """
  end

  defp terminal_output(%{result: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <pre class="text-red-400 whitespace-pre-wrap">エラー: {@reason}</pre>
    <.error_hint message={@reason} sql={@sql} />
    """
  end

  defp terminal_output(%{result: {:ok, outcome}} = assigns) do
    assigns = assign(assigns, :outcome, outcome)

    ~H"""
    <div :for={r <- @outcome.results}>
      <pre :if={r.type == :rows} class="text-neutral-200">{terminal_table(r)}</pre>
      <pre :if={r.type == :rows and r.truncated} class="text-neutral-500">-- 先頭の200行だけを表示しています</pre>
      <pre :if={r.type == :change} class="text-neutral-300">{change_message(r.count)}</pre>
    </div>
    <pre :if={@outcome.error} class="text-red-400 whitespace-pre-wrap">エラー: {@outcome.error.message}</pre>
    <.error_hint :if={@outcome.error} message={@outcome.error.message} sql={@sql} />
    """
  end

  # SQLiteの英語のエラーの下に出す、日本語の手がかり（制約のエラーには出さない）
  attr :message, :string, required: true
  attr :sql, :string, required: true

  defp error_hint(assigns) do
    {hint, token} = SqlCheck.error_hint(assigns.message) || {nil, nil}
    located = token && SqlCheck.locate(assigns.sql, token)
    assigns = assign(assigns, hint: hint, located: located)

    ~H"""
    <pre :if={@hint} class="error-hint text-yellow-300 whitespace-pre-wrap">→ {@hint}</pre>
    <.caret :if={@located} line={elem(@located, 0)} col={elem(@located, 1)} />
    """
  end

  # コマンドの1行を出し直して、その下の col 文字目に「^」で印を付ける（全角は幅2として揃える）
  attr :line, :string, required: true
  attr :col, :integer, required: true

  defp caret(assigns) do
    before = String.slice(assigns.line, 0, assigns.col - 1)
    pad = String.duplicate(" ", 2 + display_width(before))
    {:safe, marked} = mark_wide_spaces("> " <> assigns.line)
    assigns = assign(assigns, :text, {:safe, [marked, "\n", pad, "^"]})

    ~H"""
    <pre class="caret text-yellow-300 whitespace-pre">{@text}</pre>
    """
  end

  # 入力したSQLを、プロンプトつきで表示する（2行目以降は継続のプロンプト）
  defp prompt_text(sql) do
    [first | rest] = sql |> String.trim_trailing() |> String.split("\n")
    Enum.join(["> " <> first | Enum.map(rest, &("> " <> &1))], "\n")
  end

  # 全角スペースを、色付きの枠で囲んで見えるようにする（文字はそのまま残す）
  defp mark_wide_spaces(text) do
    text
    |> String.split("　")
    |> Enum.map(&(&1 |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()))
    |> Enum.join(
      ~s(<span class="wide-space outline outline-1 outline-yellow-300 bg-yellow-300/30 rounded-sm" title="全角スペース">　</span>)
    )
    |> Phoenix.HTML.raw()
  end

  # 結果の表を、等幅の文字の表にする（列の幅は、全角を2として揃える）
  defp terminal_table(%{columns: columns, rows: rows}) do
    cells = Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)

    widths =
      columns
      |> Enum.with_index()
      |> Enum.map(fn {name, i} ->
        Enum.max([display_width(name) | Enum.map(cells, &display_width(Enum.at(&1, i)))])
      end)

    line = fn items ->
      items
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {text, width} -> pad_right(text, width) end)
      |> String.trim_trailing()
    end

    separator = Enum.map_join(widths, "  ", &String.duplicate("-", &1))

    if rows == [] do
      "-- （0行）"
    else
      Enum.join([line.(columns), separator | Enum.map(cells, line)], "\n")
    end
  end

  defp pad_right(text, width), do: text <> String.duplicate(" ", width - display_width(text))

  # 等幅の表示での幅。全角の文字（日本語など）は2、それ以外は1
  defp display_width(text) do
    text |> String.to_charlist() |> Enum.reduce(0, &(&2 + if(wide_char?(&1), do: 2, else: 1)))
  end

  defp wide_char?(c) do
    c in 0x1100..0x115F or c in 0x2E80..0xA4CF or c in 0xAC00..0xD7A3 or c in 0xF900..0xFAFF or
      c in 0xFE30..0xFE6F or c in 0xFF00..0xFF60 or c in 0xFFE0..0xFFE6 or c in 0x1F300..0x1FAFF
  end

  # ヒントの中の「SQL例」（クリックで入力欄に入る）
  attr :mission, :string, required: true
  attr :examples, :list, required: true

  defp sql_examples(assigns) do
    ~H"""
    <div id={"#{@mission}-hint-examples"} class="flex flex-col gap-1">
      <button
        :for={{label, sql} <- @examples}
        type="button"
        class="btn btn-sm btn-outline justify-start font-mono normal-case"
        phx-click="use_example"
        phx-value-mission={@mission}
        phx-value-sql={sql}
      >
        <span class="font-sans font-bold text-left shrink-0 min-w-20 pr-2">{label}</span>{sql}
      </button>
    </div>
    """
  end

  # ── SQLインジェクション ───────────────────────────────

  defp inject_caution do
    [
      "ここは練習用の環境です。自分のPCの中だけの、安全な体験です。",
      "実際のサービスで試すと、不正アクセスなどの犯罪になります。"
    ]
  end

  # ミッション1〜3と同じ並び（上の段: 指令書とヒント、左下: ターミナル、右下: Web画面）。
  # 受講者はWeb画面から入力する。ターミナルは表示だけで、できあがるSQLと実行の結果を見せる
  defp inject_lab(assigns) do
    {preview_sql, _params} =
      Missions.injection_query(injection_mode(assigns.inject_mode), assigns.inject_input)

    assigns =
      assign(assigns,
        preview_sql: preview_sql,
        terminal_height: @terminal_height,
        radio_class:
          "appearance-none w-4 h-4 rounded-full bg-white border border-neutral-800 checked:bg-black checked:shadow-[inset_0_0_0_3px_white] cursor-pointer"
      )

    ~H"""
    <.start_card mission="inject" started={@inject_started} />

    <div
      :if={@inject_started}
      id="inject-top"
      class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4 lg:h-72"
    >
      <.brief mission="inject" class="" open={@inject_brief_open} elapsed={@inject_elapsed}>
        <p>セキュリティ監査で、全員の会員情報が見えてしまう操作が見つかった。</p>
        <p>会員を名前で探す画面で、何が起きているのか調査せよ。</p>
        <div id="inject-caution" class="text-warning font-bold">
          <p>注意</p>
          <ul class="ml-1">
            <li :for={line <- inject_caution()}>・{line}</li>
          </ul>
        </div>
      </.brief>

      <.hint mission="inject" open={@inject_hint_open} compact>
        <p id="inject-hint-steps-title" class="font-bold">調べ方</p>
        <ol id="inject-hint-steps" class="list-decimal ml-5">
          <li>①で、ふつうの名前（例：鈴木 ゆい）を検索する。</li>
          <li>同じ①で、<code class="font-mono">' OR '1'='1</code> を検索する。</li>
          <li>②に切り替えて、同じように検索する。</li>
        </ol>

        <p id="inject-hint-reading-title" class="font-bold mt-1">SQLの読み方</p>
        <p>ターミナルに出るSQLを、①と②で見比べてみましょう。</p>
        <ul id="inject-hint-reading" class="list-disc ml-5">
          <li>
            <code class="font-mono">'</code>
            は、文字の始まりと終わりの印です。入力した最初の <code class="font-mono">'</code>
            で、名前が閉じます。
          </li>
          <li><code class="font-mono">OR</code> は「または」です。どちらか片方が正しければ、その行を表示します。</li>
          <li><code class="font-mono">'1'='1'</code> が正しくなるのは、どんなときでしょうか？</li>
        </ul>
        <p>②では、入力は「?に渡した値」として、まるごと名前として扱われます。</p>
      </.hint>
    </div>

    <form
      :if={@inject_started}
      id="inject-form"
      phx-change="inject_changed"
      phx-submit="inject_search"
      class="grid grid-cols-1 lg:grid-cols-2 gap-4"
    >
      <%!-- 表示だけのターミナル（入力欄はない）。検索した結果を積み、最後の行に、いま検索すると実行するSQLを出す。
           下のボタンの行は、ミッション1〜3のターミナルと同じ（下の段の下端をそろえる） --%>
      <div id="inject-terminal-area">
        <div
          id="inject-terminal"
          class={[
            "terminal-font rounded-lg bg-black text-neutral-200 text-sm border border-neutral-700 shadow-sm flex flex-col",
            @terminal_height
          ]}
        >
          <div
            id="inject-history"
            phx-hook=".TerminalScroll"
            class="flex-1 min-h-0 overflow-y-auto overflow-x-auto p-3"
          >
            <div
              :for={{entry, i} <- Enum.with_index(@inject_history)}
              id={"inject-entry-#{i}"}
              class="mb-3"
            >
              <.inject_entry entry={entry} />
            </div>
            <pre class="text-neutral-500">-- 検索すると、次のSQLを実行します</pre>
            <pre id="inject-sql" class="text-green-300 whitespace-pre-wrap">{"> " <> @preview_sql}</pre>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-x-4 gap-y-2 mt-2">
          <div class="flex gap-2">
            <button
              type="button"
              id="inject-clear"
              class="btn btn-outline btn-xs"
              phx-click="clear_history"
              phx-value-mission="inject"
            >
              🧹 画面を消去
            </button>
          </div>
        </div>
      </div>

      <%!-- Web画面と、その下のサーバー側の設定を合わせて、左のターミナルと同じ高さにする --%>
      <div id="inject-right" class={[@terminal_height, "flex flex-col gap-2"]}>
        <.shop_frame id="inject-shop" height="flex-1 min-h-0">
          <div class="flex items-center gap-2">
            <input
              type="text"
              id="inject-input"
              name="input"
              value={@inject_input}
              phx-debounce="300"
              autocomplete="off"
              spellcheck="false"
              placeholder="名前を入力"
              class="input input-bordered input-sm flex-1 font-mono"
            />
            <button
              type="submit"
              class="btn btn-primary btn-sm"
              disabled={@inject_running or is_nil(@inject_db)}
            >
              🔍 検索
            </button>
          </div>

          <div id="inject-result" class="mt-3 flex flex-col gap-1">
            <pre :if={match?({:failed, _}, @inject_outcome)} class="text-error whitespace-pre-wrap">{elem(
              @inject_outcome,
              1
            )}</pre>
            <.inject_rows :if={is_map(@inject_outcome)} result={@inject_outcome.result} />
          </div>
        </.shop_frame>

        <%!-- 検索するのは会員テーブルだけ。作り方（①・②）を横1行に並べる --%>
        <fieldset
          id="inject-settings"
          class="rounded-lg bg-neutral-500 text-white text-sm border border-neutral-300 px-3 py-2 flex flex-wrap items-center gap-x-6 gap-y-1"
        >
          <label class="flex items-center gap-2 cursor-pointer text-white">
            <input
              type="radio"
              name="mode"
              value="unsafe"
              checked={@inject_mode == "unsafe"}
              class={@radio_class}
            /> ① 入力をそのままSQLに入れる
          </label>
          <label class="flex items-center gap-2 cursor-pointer text-white">
            <input
              type="radio"
              name="mode"
              value="placeholder"
              checked={@inject_mode == "placeholder"}
              class={@radio_class}
            /> ② プレースホルダ
          </label>
        </fieldset>
      </div>
    </form>
    """
  end

  # ターミナルに積む、検索1回分（実行したSQL、②なら ? に渡した値、件数かエラー）
  attr :entry, :any, required: true

  defp inject_entry(%{entry: {:failed, message}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <pre class="text-red-400 whitespace-pre-wrap">{@message}</pre>
    """
  end

  defp inject_entry(assigns) do
    ~H"""
    <pre class="text-green-300 whitespace-pre-wrap">{"> " <> @entry.sql}</pre>
    <pre :if={@entry.params != []} class="text-neutral-300 whitespace-pre-wrap">{"?に渡した値: " <> Enum.join(@entry.params, ", ")}</pre>
    <pre :if={match?({:ok, _}, @entry.result)} class="text-neutral-200">{"→ #{length(elem(@entry.result, 1).rows)}件"}</pre>
    <pre :if={match?({:error, _}, @entry.result)} class="text-red-400 whitespace-pre-wrap">{"エラー: " <> elem(@entry.result, 1)}</pre>
    """
  end

  attr :result, :any, required: true

  defp inject_rows(assigns) do
    ~H"""
    <%!-- whitespace-pre-wrap なので、テンプレートの改行・字下げが出ないよう pre で1行に書く --%>
    <pre
      :if={match?({:error, _}, @result)}
      id="inject-error"
      class="rounded border border-error bg-error/10 text-error font-mono text-sm p-3 whitespace-pre-wrap"
    >エラー: {elem(@result, 1)}</pre>

    <div :if={match?({:ok, _}, @result)} class="flex flex-col gap-1">
      <%!-- 件数は、ターミナルの「→ N件」で見る --%>
      <.data_table table={elem(@result, 1)} />
    </div>
    """
  end

  defp challenge("m2") do
    %{
      questions: [
        "商品を価格が高い順に並べて表示せよ。",
        "価格が200円以上で、在庫が10個未満の商品を探し出せ。",
        "名前に「ペン」を含む商品を、あいまい検索で探し出せ。"
      ],
      examples: [
        {"価格が高い順に並べる", "ORDER BY 価格 DESC"},
        {"かつ（両方の条件を満たす）", "AND"},
        {"あいまい検索（%は「何文字でもよい」という意味）", "名前 LIKE '%ペン%'"}
      ]
    }
  end

  defp challenge("m3") do
    %{
      lead: "在庫が少ない商品は、値上げして、品切れを防ぎたい。先ほどの事故があったので、慎重に進めたい。",
      questions: [
        "在庫が10個未満の商品だけ、価格を10円値上げせよ。ただし、変更する前にSELECTを実行して確認すること。"
      ],
      examples: [
        {"更新する", "UPDATE 商品 SET 価格 = 価格 + 10 WHERE 条件;"}
      ]
    }
  end

  # 会員テーブルの NOT NULL（名前）と CHECK（退会 IN (0, 1)）のエラーを、受講者が自分で読む
  defp challenge("m4") do
    %{
      lead: "データベースは、UNIQUE制約のほかにも、ルールでデータを守っている。次のSQLを実行して、どんなルールに守られているか確かめよ。",
      questions: [
        "名前を入れずに、会員を登録すると？",
        "「退会」の列を、2にすると？"
      ],
      examples: [
        {"名前を入れずに登録する", "INSERT INTO 会員 (メールアドレス) VALUES ('メール');"},
        {"「退会」の列を2にする", "UPDATE 会員 SET 退会 = 2 WHERE id = 3;"}
      ]
    }
  end

  attr :mission, :string, required: true
  attr :open, :boolean, required: true

  defp challenge_box(assigns) do
    assigns = assign(assigns, :challenge, challenge(assigns.mission))

    ~H"""
    <div
      id={"#{@mission}-challenge"}
      class="mt-3 rounded-lg border border-primary/40 bg-primary/5 p-3 flex flex-col gap-2"
    >
      <p class="font-bold text-primary">📌 追加指令</p>
      <p class="text-xs opacity-70">
        必須の課題はクリアです。同じデータベースで、自分で考えて試してみましょう。結果はSELECTで確かめます。
      </p>
      <p :if={@challenge[:lead]} id={"#{@mission}-challenge-lead"} class="text-sm">
        {@challenge[:lead]}
      </p>
      <ol class="list-decimal ml-5 text-sm flex flex-col gap-1">
        <li :for={q <- @challenge.questions}>{q}</li>
      </ol>
      <details
        id={"#{@mission}-examples"}
        class="collapse collapse-arrow bg-base-100 border border-warning"
        open={@open}
      >
        <summary
          class="collapse-title font-bold"
          phx-click="toggle_examples"
          phx-value-mission={@mission}
        >
          💡 SQL例
        </summary>
        <div class="collapse-content flex flex-col gap-2 text-sm">
          <div :for={{label, code} <- @challenge.examples} class="flex flex-wrap items-baseline gap-2">
            <span class="font-bold">{label}</span>
            <code class="font-mono bg-base-200 rounded px-2 py-1 whitespace-pre-wrap">{code}</code>
          </div>
        </div>
      </details>
    </div>
    """
  end

  # ミッションの画面に埋め込む、通販サイトの商品の画面（見るだけ）。
  # SQLを実行するたびに @m2_table / @m3_table が更新されるので、自動で最新の表示になる
  attr :mission, :string, required: true
  attr :table, :any, required: true

  defp mission_shop(assigns) do
    assigns = assign(assigns, :height, @terminal_height)

    ~H"""
    <.shop_frame id={"#{@mission}-shop"} height={@height}>
      <h3 class="font-bold mb-2">商品一覧</h3>
      <.products table={@table} />
    </.shop_frame>
    """
  end

  # ── ミッション2 ───────────────────────────────────────

  defp mission2(assigns) do
    assigns = assign(assigns, :examples, m2_examples())

    ~H"""
    <.start_card mission="m2" started={@m2_started} />
    <div :if={@m2_started} id="m2-top" class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4 lg:h-72">
      <.brief mission="m2" class="" open={@m2_brief_open} elapsed={@m2_elapsed}>
        <p>SQLを使って、データベースへ<strong>直接</strong>指示を出せ。</p>
        <ol class="flex flex-col gap-1 mt-2">
          <.task_item done={MapSet.member?(@m2_done, :insert)}>
            1. 新商品「付箋」（価格200円、在庫12個）を登録する
          </.task_item>
          <.task_item done={MapSet.member?(@m2_done, :low_stock)}>2. 在庫が10個未満の商品を検索する</.task_item>
          <.task_item done={MapSet.member?(@m2_done, :update)}>3. コピー用紙の在庫を30個に更新する</.task_item>
          <.task_item done={MapSet.member?(@m2_done, :delete)}>4. 「付箋」を削除する</.task_item>
        </ol>
        <div :if={MapSet.size(@m2_done) == 4} class="alert alert-success mt-2 font-bold">
          🎉 ミッション完了！ データベースに直接命令を出せるようになりました。
        </div>
        <.challenge_box :if={@m2_challenge} mission="m2" open={@m2_examples_open} />
      </.brief>

      <.hint mission="m2" open={@m2_hint_open} compact>
        <p>データベースには、<strong>SQL</strong>という専用の言葉で命令を出します。</p>
        <.sql_examples mission="m2" examples={@examples} />
        <%!-- 1段落に詰めると読みにくいので、条件・比較の記号・つなぎ方の3行に分ける --%>
        <div id="m2-hint-where" class="flex flex-col gap-1">
          <p><code>WHERE</code> は「どの行に対して」を指定する条件です。</p>
          <p>
            比較の記号：<code>=</code>（等しい）、<code>&lt;&gt;</code> <code>!=</code>（等しくない）、<code>&lt;</code> <code>&gt;</code>（より小さい・より大きい）、<code>&lt;=</code> <code>&gt;=</code>（以下・以上）
          </p>
          <p>条件をつなぐ：<code>AND</code>（かつ）、<code>OR</code>（または）</p>
        </div>
      </.hint>
    </div>

    <div :if={@m2_started} class="flex flex-col gap-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.terminal
          mission="m2"
          db={@m2_db}
          history={@m2_history}
          sql={@m2_sql}
          running={@m2_running}
        />
        <.mission_shop mission="m2" table={@m2_table} />
      </div>
    </div>
    """
  end

  # ── ミッション3 ───────────────────────────────────────

  defp mission3(assigns) do
    ~H"""
    <.start_card mission="m3" started={@m3_started} />
    <div :if={@m3_started} id="m3-top" class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4 lg:h-72">
      <.brief mission="m3" class="" open={@m3_brief_open} elapsed={@m3_elapsed}>
        <p>「ボールペンの価格が古いまま」という問題を直すために、次のSQLを実行したところ、</p>
        <pre class="font-mono font-bold bg-base-200 rounded px-3 py-1">{Missions.m3_mistake_sql()}</pre>
        <p><strong>コピー用紙とファイルの価格も</strong>150円になってしまった。</p>
        <p>原因を突き止めて、正しい価格に戻せ。</p>
        <%!-- 達成前に指令書の枠（h-56）に収まるよう、2つの価格は1行に並べる --%>
        <p id="m3-brief-prices">・コピー用紙：480円　・ファイル：250円</p>
        <ul class="flex flex-col gap-1 mt-2">
          <.task_item done={@m3_fixed}>コピー用紙480円・ボールペン150円・ファイル250円に戻す</.task_item>
        </ul>
        <div :if={@m3_fixed} class="alert alert-success mt-2 font-bold">
          🎉 復旧完了！ 通販サイトの画面の価格が元に戻りました。
        </div>
        <.challenge_box :if={@m3_challenge} mission="m3" open={@m3_examples_open} />
      </.brief>

      <.hint mission="m3" open={@m3_hint_open}>
        <p>困ったときは、<strong>生成AI</strong>に相談してみましょう。使う生成AIは、講師が案内します。</p>
        <p>※今日は架空のデータを使っています。業務では、個人情報やお客さんのデータは生成AIに入れません。</p>
        <p>聞き方によって、返ってくる答えの質が大きく変わります。どちらが役に立つ答えになるか、試してみてください。</p>
        <ol class="list-decimal ml-5">
          <li>何が起きたかだけを伝える。</li>
          <li>実行したSQLとテーブルの中身も一緒に伝える。</li>
        </ol>
        <.copyable id="m3-prompt" text={m3_prompt()} />
      </.hint>
    </div>

    <div :if={@m3_started} class="flex flex-col gap-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.terminal
          mission="m3"
          db={@m3_db}
          history={@m3_history}
          sql={@m3_sql}
          running={@m3_running}
        />
        <.mission_shop mission="m3" table={@m3_table} />
      </div>
    </div>
    """
  end

  defp m3_prompt do
    """
    データベースのUPDATE文を実行したら、1件だけ変えたかったのに
    全部の行の価格が変わってしまいました。原因と直し方を教えてください。

    【実行したSQL】
    UPDATE 商品 SET 価格 = 150;

    【テーブルの中身（実行後）】
    id | 名前       | 価格 | 在庫
    1  | コピー用紙 | 150  | 24
    2  | ボールペン | 150  | 8
    3  | ファイル   | 150  | 5

    【本来の価格】
    - コピー用紙 480円
    - ファイル 250円\
    """
  end

  # ミッション３（内部名m4）のヒントの、生成AIへのプロンプト例（コピーして使う）
  defp m4_prompt do
    """
    会員登録のデータをデータベースに追加しようとしたら、次のエラーが出ました。
    原因として考えられることをあげてください。

    【実行したSQL】
    INSERT INTO 会員 (名前, メールアドレス) VALUES ('佐藤 さくら', 'sakura@example.com');

    【エラーメッセージ】
    UNIQUE constraint failed: 会員.メールアドレス\
    """
  end

  # ── ミッション4 ───────────────────────────────────────

  defp mission4(assigns) do
    assigns =
      assign(assigns,
        all_done: assigns.m4_error_seen and assigns.m4_found and assigns.m4_registered,
        terminal_height: @terminal_height
      )

    ~H"""
    <.start_card mission="m4" started={@m4_started} />
    <div :if={@m4_started} id="m4-top" class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4 lg:h-72">
      <.brief mission="m4" class="" open={@m4_brief_open} elapsed={@m4_elapsed}>
        <p>「会員登録ができません」という声が、お客さんから届いた。</p>
        <p>通販サイトの会員登録画面で登録し、何が起きているか確かめよ。</p>
        <p>原因を突き止めて、お客さんが登録できるようにせよ。</p>
        <ul class="flex flex-col gap-1 mt-2">
          <.task_item done={@m4_error_seen}>1. 通販サイトの会員登録画面で、エラーを再現する</.task_item>
          <.task_item done={@m4_found}>2. SQLで会員テーブルを調べ、原因になっている行を見つける</.task_item>
          <.task_item done={@m4_registered}>3. お客さんが登録できるようにする</.task_item>
        </ul>
        <div :if={@all_done} class="alert alert-success mt-2 font-bold flex-col items-start">
          <span>🎉 ミッション完了！ お客さんが登録できるようになりました。</span>
          <span class="text-sm font-normal">
            メールアドレスには、同じ値を2回登録できないルール（<strong>UNIQUE制約</strong>）が付いています。以前に退会したお客さんのデータが残っていたため、同じメールアドレスでは登録できませんでした。
          </span>
        </div>
        <.challenge_box :if={@m4_challenge} mission="m4" open={@m4_examples_open} />
      </.brief>

      <.hint mission="m4" open={@m4_hint_open}>
        <p>エラーメッセージは、英語で書かれていても<strong>原因がそのまま書いてある</strong>ことがほとんどです。</p>
        <ul class="list-disc ml-5">
          <li>どのテーブルの、どの列で起きているか</li>
          <li>どんなルール（制約）に引っかかったか</li>
        </ul>
        <p>意味が分からない単語は、生成AIに聞いてみましょう。会員テーブルの中身も、SELECTで確かめてみましょう。</p>
        <.copyable id="m4-prompt" text={m4_prompt()}>
          <p>次のように、SQLとエラーメッセージを一緒に伝えます。</p>
        </.copyable>
      </.hint>
    </div>

    <div :if={@m4_started} class="flex flex-col gap-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <%!-- 会員テーブルは常時表示しない。原因の行を SQL で探すのがこのミッションの課題なので --%>
        <.terminal
          mission="m4"
          db={@m4_db}
          history={@m4_history}
          sql={@m4_sql}
          running={@m4_running}
        />
        <div class="flex flex-col gap-4">
          <.shop_frame id="m4-shop" height={@terminal_height}>
            <h3 class="font-bold mb-2">会員登録</h3>
            <form
              id="m4-shop-form"
              phx-change="m4_signup_changed"
              phx-submit="m4_signup"
              class="flex flex-col gap-2 max-w-sm"
            >
              <label class="text-sm font-bold">お名前</label>
              <input
                type="text"
                name="name"
                value={@m4_shop_name}
                autocomplete="off"
                class="input input-bordered input-sm w-full"
              />
              <label class="text-sm font-bold">メールアドレス</label>
              <input
                type="text"
                name="email"
                value={@m4_shop_email}
                autocomplete="off"
                class="input input-bordered input-sm w-full"
              />
              <button type="submit" class="btn btn-primary btn-sm self-start mt-1">登録する</button>
            </form>
          </.shop_frame>

          <div
            id="m4-server-log"
            phx-hook=".ScrollIntoViewOnLog"
            class="border border-base-300/70 rounded-lg p-3 bg-base-100"
          >
            <h3 class="font-bold mb-2">📟 サーバーのログ</h3>
            <p :if={is_nil(@m4_register)} class="text-sm opacity-60">
              通販サイトの会員登録画面で登録ボタンを押すと、サーバーの記録がここに表示されます。
            </p>
            <pre
              :if={@m4_register}
              class="font-mono text-xs bg-neutral text-neutral-content rounded p-2 whitespace-pre-wrap"
            >{m4_server_log(@m4_register)}</pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp m4_server_log(%{sql: sql, error: nil}), do: "#{sql}\n→ OK"
  defp m4_server_log(%{sql: sql, error: error}), do: "#{sql}\n→ #{error}"

  # ── 画面全体 ──────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Terminal">
      export default {
        mounted() {
          const el = this.el
          this.draft = ""
          this.pos = null

          const history = () => {
            try { return JSON.parse(el.dataset.history || "[]") } catch (_e) { return [] }
          }
          const setValue = (v) => {
            el.value = v
            el.dispatchEvent(new Event("input", {bubbles: true}))
            el.setSelectionRange(v.length, v.length)
          }

          el.addEventListener("keydown", (e) => {
            // 日本語入力の変換中のEnterでは、実行しない
            if (e.isComposing || e.keyCode === 229) return
            const v = el.value

            if (e.key === "Enter" && !e.shiftKey) {
              // 最後が ; なら実行。それ以外は、そのまま改行（複数行の入力）。Ctrl+Enterは、いつでも実行
              if (e.ctrlKey || e.metaKey || v.trim().endsWith(";")) {
                e.preventDefault()
                if (v.trim() !== "") el.form.requestSubmit()
              }
            } else if (e.key === "ArrowUp" && !v.slice(0, el.selectionStart).includes("\n")) {
              const h = history()
              if (h.length === 0) return
              if (this.pos === null) { this.draft = v; this.pos = h.length }
              if (this.pos > 0) { this.pos -= 1; e.preventDefault(); setValue(h[this.pos]) }
            } else if (e.key === "ArrowDown" && this.pos !== null && !v.slice(el.selectionEnd).includes("\n")) {
              const h = history()
              e.preventDefault()
              this.pos += 1
              if (this.pos >= h.length) { this.pos = null; setValue(this.draft) } else { setValue(h[this.pos]) }
            }
          })

          // 送信したら、入力欄を空にする（LiveViewは、フォーカス中の入力欄を、サーバーからは書き換えない）
          el.form.addEventListener("submit", () => {
            this.pos = null
            this.draft = ""
            setTimeout(() => setValue(""), 0)
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyText">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            const target = document.querySelector(this.el.dataset.target)
            if (!target) return
            const text = target.innerText
            const done = () => {
              const label = this.el.textContent
              this.el.textContent = "✅ コピーしました"
              setTimeout(() => { this.el.textContent = label }, 1500)
            }
            // 講師PCのIPアドレス（http）で開くと navigator.clipboard は使えないので、古い方法に切り替える
            const fallback = () => {
              const ta = document.createElement("textarea")
              ta.value = text
              ta.style.position = "fixed"
              ta.style.opacity = "0"
              document.body.appendChild(ta)
              ta.select()
              document.execCommand("copy")
              ta.remove()
              done()
            }
            if (navigator.clipboard && window.isSecureContext) {
              navigator.clipboard.writeText(text).then(done, fallback)
            } else {
              fallback()
            }
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollIntoViewOnLog">
      export default {
        mounted() {
          // 「登録する」の結果を受け取ったときだけ、ログの欄が見える位置までスクロールする
          // （block: "nearest" なので、最初から見えているときは動かない）
          this.handleEvent("m4:show-server-log", () => {
            this.el.scrollIntoView({block: "nearest", behavior: "smooth"})
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".TerminalScroll">
      export default {
        mounted() { this.el.scrollTop = this.el.scrollHeight },
        updated() { this.el.scrollTop = this.el.scrollHeight }
      }
    </script>

    <%!-- 受講者のPC(ブラウザの中が約1536×740px)で、指令書・ヒント・ターミナル・Web画面が1画面に収まるよう、縦を詰める --%>
    <div class="px-6 py-3 max-w-[96rem] mx-auto">
      <header id="page-header" class="flex flex-wrap items-center gap-x-6 gap-y-2 mb-3">
        <h1 class="text-3xl font-bold">🛠️ システムトラブルを解決せよ！</h1>

        <div role="tablist" class="tabs tabs-boxed bg-base-200 p-1 rounded-xl gap-1">
          <a
            :for={
              {tab, label} <- [
                {"m2", "ミッション１"},
                {"m3", "ミッション２"},
                {"m4", "ミッション３"},
                {"inject", "ミッション４"}
              ]
            }
            role="tab"
            class={tab_class(@tab, tab)}
            phx-click="switch_tab"
            phx-value-tab={tab}
          >
            {label}
          </a>
        </div>
      </header>

      <.inject_lab :if={@tab == "inject"} {assigns} />
      <.mission2 :if={@tab == "m2"} {assigns} />
      <.mission3 :if={@tab == "m3"} {assigns} />
      <.mission4 :if={@tab == "m4"} {assigns} />
    </div>
    """
  end
end
