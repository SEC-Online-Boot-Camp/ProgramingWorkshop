defmodule DatabaseMissionWeb.ShopLive do
  @moduledoc """
  通販サイトの画面（Web画面）。ミッションの画面とは別のページ（`/shop`）で、別のウィンドウに開く。

    * 商品の画面 ... ミッション2・3の商品テーブルを、通販サイトの画面として見る（見るだけ）。
      ミッションの画面には商品テーブルを出さない（SELECTで調べる練習になるため）ので、
      ここで確認する。ミッション2・3のデータの切り替えは、ラジオボタンで行う。
    * 会員登録画面 ... ミッション4のデータベースに、会員を登録する。

  同じブラウザ（同じ受講者）のデータベースを、セッションの識別子から引く
  （`DatabaseMission.Participant`）。ミッションを始めていない（データベースがない）ときは、
  案内を出す。表示は、開いたとき・切り替えたとき・「更新」を押したときの内容。

  会員登録の結果は、PubSubでミッション4の画面に知らせる（課題の達成判定と、
  「サーバーの記録」の表示に使う）。
  """

  use DatabaseMissionWeb, :live_view

  import DatabaseMissionWeb.ShopComponents

  alias DatabaseMission.{Missions, Participant, Sql}

  @impl true
  def mount(_params, session, socket) do
    customer = Missions.m4_customer()

    socket =
      socket
      |> assign(page_title: "通販サイト", pid: session["participant_id"], source: "m2")
      |> assign(name: customer.name, email: customer.email, signup: nil)
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("shop_source", %{"source" => source}, socket) when source in ~w(m2 m3) do
    {:noreply, socket |> assign(:source, source) |> load()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket)}
  end

  def handle_event("signup_changed", %{"name" => name, "email" => email}, socket) do
    {:noreply, assign(socket, name: name, email: email)}
  end

  def handle_event("signup", %{"name" => name, "email" => email}, socket) do
    socket = assign(socket, name: name, email: email)
    pid = socket.assigns.pid

    if Participant.db_exists?(pid, "m4") do
      {:noreply, register(socket, pid, name, email)}
    else
      {:noreply, load(socket)}
    end
  end

  # ── 内部処理 ──────────────────────────────────────────

  # 表示に使うデータを読み直す
  defp load(socket) do
    pid = socket.assigns.pid

    assign(socket,
      products: read_products(pid, socket.assigns.source),
      members_ready: Participant.db_exists?(pid, "m4")
    )
  end

  # 商品テーブルを、読み取り専用で読む。nil = ミッションを始めていない
  defp read_products(pid, mission) do
    if Participant.db_exists?(pid, mission) do
      case Sql.query(Participant.db_path(pid, mission), Missions.products_snapshot_sql()) do
        {:ok, table} -> table
        {:error, _} -> :error
      end
    end
  end

  defp register(socket, pid, name, email) do
    record = Participant.register_member(pid, name, email)
    assign(socket, :signup, if(record.error, do: :error, else: :ok))
  end

  # ── 画面 ──────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-3xl mx-auto">
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">🛒 通販サイト</h1>
        <button type="button" class="btn btn-outline btn-sm" phx-click="refresh">🔄 更新</button>
      </div>

      <p class="text-sm opacity-70 mb-4">
        ミッションで操作しているデータを、お客さんが見る画面（Web画面）として確認する別ウィンドウです。ミッションの画面に戻って操作したあと、「更新」を押すと最新の内容になります。
      </p>

      <section class="border border-base-300/70 rounded-lg p-3 bg-base-100 mb-4">
        <h2 class="font-bold mb-2">商品の画面</h2>
        <form
          id="shop-source-form"
          phx-change="shop_source"
          class="flex flex-wrap gap-x-6 gap-y-1 mb-3 text-sm"
        >
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="radio"
              name="source"
              value="m2"
              checked={@source == "m2"}
              class="radio radio-sm"
            /> ミッション２のデータ
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="radio"
              name="source"
              value="m3"
              checked={@source == "m3"}
              class="radio radio-sm"
            /> ミッション３のデータ
          </label>
        </form>

        <div id="shop-products">
          <p :if={is_nil(@products)} class="text-sm opacity-70">ミッションを始めると、表示されます。</p>
          <p :if={@products == :error} class="text-sm text-error">
            読み込めませんでした。「更新」を押してください。
          </p>
          <.products :if={is_map(@products)} table={@products} />
        </div>
      </section>

      <section class="border border-base-300/70 rounded-lg p-3 bg-base-100">
        <h2 class="font-bold mb-2">会員登録画面</h2>

        <p :if={not @members_ready} id="signup-guide" class="text-sm opacity-70">
          ミッションを始めると、表示されます。
        </p>

        <form
          :if={@members_ready}
          id="signup-form"
          phx-change="signup_changed"
          phx-submit="signup"
          class="flex flex-col gap-2 max-w-sm"
        >
          <label class="text-sm font-bold">お名前</label>
          <input
            type="text"
            name="name"
            value={@name}
            autocomplete="off"
            class="input input-bordered input-sm w-full"
          />
          <label class="text-sm font-bold">メールアドレス</label>
          <input
            type="text"
            name="email"
            value={@email}
            autocomplete="off"
            class="input input-bordered input-sm w-full"
          />
          <button type="submit" class="btn btn-primary btn-sm self-start mt-1">登録する</button>
        </form>

        <div :if={@members_ready} id="signup-result" class="mt-3">
          <p :if={@signup == :ok} class="text-success font-bold">✅ 登録できました</p>
          <p :if={@signup == :error} class="text-error font-bold">
            ⚠️ 登録できませんでした。しばらくしてからお試しください。
          </p>
        </div>
      </section>
    </div>
    """
  end
end
