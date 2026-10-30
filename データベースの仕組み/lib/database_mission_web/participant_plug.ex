defmodule DatabaseMissionWeb.ParticipantPlug do
  @moduledoc """
  セッションに、受講者の識別子（`"participant_id"`）がなければ作る。

  ミッションの画面と、別ページの通販サイト（`/shop`）が、同じブラウザ＝同じ受講者の
  データベースを見るために使う。詳しくは `DatabaseMission.Participant`。
  """

  import Plug.Conn

  alias DatabaseMission.Participant

  def init(opts), do: opts

  def call(conn, _opts) do
    if Participant.valid?(get_session(conn, "participant_id")) do
      conn
    else
      put_session(conn, "participant_id", Participant.new_id())
    end
  end
end
