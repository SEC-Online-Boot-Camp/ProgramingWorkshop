defmodule DatabaseMissionWeb.TestHelpers do
  @moduledoc """
  テストで共通に使う補助。
  """

  import Phoenix.ConnTest, only: [init_test_session: 2]

  @doc """
  受講者の識別子つきのセッションを持つ接続を作る。

  同じ接続で、ミッションの画面（`/`）と通販サイト（`/shop`）を開くと、
  同じ受講者（同じブラウザ）として、同じデータベースを見る。
  """
  def participant_conn(conn, id \\ nil) do
    id =
      id ||
        "t#{System.unique_integer([:positive])}_" <>
          Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

    init_test_session(conn, %{"participant_id" => id})
  end
end
