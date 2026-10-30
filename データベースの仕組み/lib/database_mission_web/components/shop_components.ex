defmodule DatabaseMissionWeb.ShopComponents do
  @moduledoc """
  通販サイトの商品の画面（お客さんが見る画面）を表示する部品。

  別ページの通販サイト（`DatabaseMissionWeb.ShopLive`、`/shop`）と、ミッションの画面に
  埋め込んだ表示（`DatabaseMissionWeb.MissionLive`）の、両方で使う。
  """

  use Phoenix.Component

  @doc """
  通販サイトらしい見た目の、ヘッダー（店名・メニュー・カート）とフッターが付いた枠。
  中身（商品の一覧、会員登録フォームなど）は呼び出し側が決める。メニューは飾りで、
  押しても何も起きない。
  """
  attr :id, :string, default: nil
  attr :height, :string, default: "h-full"
  slot :inner_block, required: true

  def shop_frame(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        @height,
        "flex flex-col rounded-lg border border-base-300 bg-base-100 shadow-sm overflow-hidden"
      ]}
    >
      <header class="bg-primary text-primary-content px-3 py-2 flex items-center justify-between gap-2">
        <div class="flex items-center gap-2 font-bold whitespace-nowrap">
          <span aria-hidden="true">📦</span> <span>オフィスいちば</span>
        </div>

        <nav class="hidden sm:flex items-center gap-3 text-xs opacity-90">
          <span>商品一覧</span> <span>会員登録</span> <span>よくある質問</span>
        </nav>
        <span aria-hidden="true" class="text-lg">🛒</span>
      </header>

      <div class="p-3 flex-1 overflow-y-auto">
        {render_slot(@inner_block)}
      </div>

      <footer class="px-3 py-1.5 border-t border-base-300 text-center text-[11px] opacity-60">
        © オフィスいちば（この画面は講座の練習用です）
      </footer>
    </div>
    """
  end

  attr :table, :any, required: true

  def products(assigns) do
    assigns = assign(assigns, :items, shop_items(assigns.table))

    ~H"""
    <p :if={is_nil(@items)} class="text-sm text-error">商品を表示できません。</p>

    <div :if={@items} class="grid grid-cols-2 sm:grid-cols-3 gap-2">
      <div
        :for={item <- @items}
        class="rounded-lg border border-base-300 p-2 text-center bg-base-200/40"
      >
        <div class="text-3xl">{product_icon(item.name)}</div>

        <div class="font-bold">{item.name}</div>

        <div class="text-primary font-bold tabular-nums">{cell(item.price)}円</div>

        <div class={[
          "text-xs",
          (is_integer(item.stock) and item.stock < 10) && "text-error font-bold"
        ]}>
          {if is_integer(item.stock) and item.stock < 10,
            do: "残りわずか（#{item.stock}個）",
            else: "在庫 #{cell(item.stock)}個"}
        </div>
      </div>
    </div>
    """
  end

  # 商品テーブルから、画面に並べる商品を取り出す。列が足りなければ nil
  defp shop_items(%{columns: columns, rows: rows}) do
    with i when is_integer(i) <- Enum.find_index(columns, &(&1 == "名前")),
         j when is_integer(j) <- Enum.find_index(columns, &(&1 == "価格")),
         s when is_integer(s) <- Enum.find_index(columns, &(&1 == "在庫")) do
      Enum.map(rows, fn row ->
        %{name: to_string(Enum.at(row, i)), price: Enum.at(row, j), stock: Enum.at(row, s)}
      end)
    else
      _ -> nil
    end
  end

  defp shop_items(_), do: nil

  defp product_icon("コピー用紙"), do: "📄"
  defp product_icon("ボールペン"), do: "🖊️"
  defp product_icon("ファイル"), do: "📁"
  defp product_icon("付箋"), do: "🗒️"
  defp product_icon("ホッチキス"), do: "📎"
  defp product_icon(_), do: "🛒"

  defp cell(nil), do: "NULL"
  defp cell(value), do: to_string(value)
end
