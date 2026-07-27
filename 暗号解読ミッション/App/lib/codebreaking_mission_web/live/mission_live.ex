defmodule CodebreakingMissionWeb.MissionLive do
  @moduledoc """
  暗号解読ミッション1〜4のページ。参考ツール（静的HTML版）と同じ内容を、
  LiveViewのassign更新だけで動かす。暗号円盤の回転もボタン操作のみで、
  JSフックは使わない（角度計算はサーバー側でSVGの`transform`を再計算するだけ）。

  各ミッションの指令書欄には解答入力欄があり、送信すると正誤フィードバックを表示する
  （正誤判定はこの解答欄でのみ行い、解読ツール側の状態からの自動判定は行わない）。

  ミッション2の「自動回転・総当たり」だけは、参考HTML版のsetIntervalアニメーション
  （180msごとに1行ずつ表示）を、OTPの`Process.send_after/3`による自己タイマーで再現する。
  """

  use CodebreakingMissionWeb, :live_view

  alias CodebreakingMission.Ciphers
  alias CodebreakingMission.Python.{Runner, RunSupervisor}

  # ── ミッション1 ──────────────────────────────────────────
  @m1_hira_default "ほもないめよを"
  @m1_alpha_default "HELLO WORLD"
  @m1_answer "ひみつをまもれ"

  # ── ミッション2 ──────────────────────────────────────────
  @m2_cipher "DPTVZF OL EDFRT YZ DSTCPT HZ XLEP"
  @m2_answer "SEIKOU DA TSUGI NO SHIREI WO MATE"

  # ── ミッション3 ──────────────────────────────────────────
  @m3_cipher """
  Zgh Ltektz!
  Ziol ol zit ltektz zqla ygk ngx.
  Zit stzztk t ol zit dglz yktjxtfz stzztk of Tfusoli.
  Ltt zit ziktt vgkrl zit, ziol, qfr ziqz.
  Tctkngft eqf lgsct ziol tqlosn vozi q sozzst ziofaofu.
  Ngx qkt ctkn ldqkz qfr ngx eqf rg ziol egrt.
  Zit jxoea wkgvf ygb pxdhl gctk zit sqmn rgu!
  Uggr sxea qfr iqct yxf vozi ziol eohitk lnlztd!\
  """
  @m3_answer """
  Top Secret!
  This is the secret task for you.
  The letter e is the most frequent letter in English.
  See the three words the, this, and that.
  Everyone can solve this easily with a little thinking.
  You are very smart and you can do this code.
  The quick brown fox jumps over the lazy dog!
  Good luck and have fun with this cipher system!\
  """

  # ── ミッション4 ──────────────────────────────────────────
  @m4_cipher """
  Mcz Qsvfor. Zxjoj Thib.
  Wcn vkts ufyisg hrpsx qsnvxfc rcwoi, zim hrgg hbo gg wwpdsksxr.
  Has ucm bg k uckr, xmh t bekpxf, cm qhixrwgu dfs esdrskg ggze byr vxzz wcn.
  Zymy th dfs yfooixbmw htpvc. Wm wc yzfccr teod.
  Cjxfi jsmhop wl vsbwgu lcvbbn kogm ngtysbcbm akqyl.
  Typ hafoc vnbnpsw moyfl domdes myzesn rvbg dfs nblpstykzzx qsnvxf.
  Lsh xjol o ecxe yxm vcoosc y famdfa bbcgrx hrc hxld,
  ybw o wyqawxc qtb pgbw hryh kvirvf wx y ahaolh.
  Wc xmh mfeqh t goafxh wchacn. Rfngd komvokomwmq wggdcow.
  Oxb wy mys qtbxmh ufoyy mvo awivop, oly dfs aiwyb pvy fcerc rvx yow.\
  """
  @m4_answer """
  Top Secret. Level Four.
  You have broken three ciphers today, but this one is different.
  The key is a word, not a number, so counting the letters will not help you.
  Look at the frequency table. It is almost flat.
  Every letter is hiding behind many different masks.
  For three hundred years people called this the unbreakable cipher.
  But even a long key leaves a rhythm inside the text,
  and a machine can find that rhythm in a moment.
  Do not trust a secret method. Trust mathematics instead.
  And if you cannot break the cipher, ask the human who holds the key.\
  """

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        tab: "m1",
        # ミッション2・4のPython実行が発行するrun_idの採番元（両ミッションで共有し、
        # 衝突しない一意な値にする）。
        run_seq: 0,

        # ミッション1
        m1_lang: "hira",
        m1_cipher: @m1_hira_default,
        m1_shift: 0,
        m1_answer_feedback: nil,
        m1_tool_open: false,

        # ミッション2
        m2_cipher: @m2_cipher,
        m2_single_k: 1,
        m2_single_result: nil,
        m2_manual_tested: MapSet.new(),
        m2_manual_history: [],
        m2_disk_shift: 0,
        m2_code: m2_default_code(),
        m2_status: :idle,
        m2_run_id: 0,
        m2_runner_pid: nil,
        m2_terminal_lines: [],
        m2_answer_feedback: nil,
        m2_tool_open: false,

        # ミッション3
        m3_cipher: @m3_cipher,
        m3_text: @m3_cipher,
        m3_mapping: %{},
        m3_code: m3_default_code(),
        m3_status: :idle,
        m3_run_id: 0,
        m3_runner_pid: nil,
        m3_terminal_lines: [],
        m3_freq: [],
        m3_answer_feedback: nil,
        m3_tool_open: false,

        # ミッション4
        m4_cipher: @m4_cipher,
        m4_key: "",
        m4_code: m4_default_code(),
        m4_status: :idle,
        m4_run_id: 0,
        m4_runner_pid: nil,
        m4_terminal_lines: [],
        m4_answer_feedback: nil,
        m4_tool_open: false
      )

    {:ok, socket}
  end

  # ── イベントハンドラ（全ミッション分をここにまとめる） ─────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("m1_lang_changed", %{"lang" => lang}, socket) do
    cipher = if lang == "alpha", do: @m1_alpha_default, else: @m1_hira_default
    {:noreply, assign(socket, m1_lang: lang, m1_cipher: cipher, m1_shift: 0)}
  end

  def handle_event("m1_cipher_changed", %{"cipher" => cipher}, socket) do
    {:noreply, assign(socket, :m1_cipher, cipher)}
  end

  def handle_event("m1_rotate", %{"dir" => dir}, socket) do
    total = if socket.assigns.m1_lang == "alpha", do: 26, else: 46
    shift = Integer.mod(socket.assigns.m1_shift + String.to_integer(dir), total)
    {:noreply, assign(socket, :m1_shift, shift)}
  end

  def handle_event("m1_answer_submit", %{"answer" => answer}, socket) do
    correct? = String.trim(answer) == @m1_answer
    {:noreply, assign(socket, :m1_answer_feedback, correct?)}
  end

  def handle_event("m1_toggle_tool", _params, socket) do
    {:noreply, assign(socket, :m1_tool_open, not socket.assigns.m1_tool_open)}
  end

  def handle_event("m2_cipher_changed", %{"cipher" => cipher}, socket) do
    {:noreply, assign(socket, :m2_cipher, cipher)}
  end

  def handle_event("m2_single_k_changed", %{"k" => k}, socket) do
    k =
      case Integer.parse(k) do
        {n, ""} -> n |> max(0) |> min(25)
        _ -> socket.assigns.m2_single_k
      end

    {:noreply, assign(socket, :m2_single_k, k)}
  end

  def handle_event("m2_single_run", _params, socket) do
    %{m2_cipher: cipher, m2_single_k: k, m2_manual_tested: tested, m2_manual_history: history} =
      socket.assigns

    decoded = Ciphers.caesar_decode_alpha(cipher, k)

    socket =
      assign(socket,
        m2_disk_shift: k,
        m2_single_result: "k = #{k}: #{decoded}",
        m2_manual_tested: MapSet.put(tested, k),
        m2_manual_history: [{k, decoded} | history]
      )

    {:noreply, socket}
  end

  def handle_event("m2_code_changed", %{"code" => code}, socket) do
    {:noreply, assign(socket, :m2_code, code)}
  end

  def handle_event("m2_run", _params, %{assigns: %{m2_status: :running}} = socket) do
    {:noreply, socket}
  end

  def handle_event("m2_run", _params, socket) do
    run_id = socket.assigns.run_seq + 1
    code = inject_cipher_text(socket.assigns.m2_code, socket.assigns.m2_cipher)

    socket =
      assign(socket,
        run_seq: run_id,
        m2_run_id: run_id,
        m2_status: :running,
        m2_terminal_lines: []
      )

    case RunSupervisor.start_run(code, self(), run_id) do
      {:ok, pid} ->
        {:noreply, assign(socket, :m2_runner_pid, pid)}

      {:error, reason} ->
        socket =
          append_m2_line(socket, "[実行を開始できませんでした: #{inspect(reason)}]")

        {:noreply, assign(socket, m2_status: :idle, m2_runner_pid: nil)}
    end
  end

  def handle_event("m2_stop", _params, socket) do
    if socket.assigns.m2_runner_pid do
      Runner.stop(socket.assigns.m2_runner_pid)
    end

    {:noreply, socket}
  end

  def handle_event("m2_answer_submit", %{"answer" => answer}, socket) do
    correct? = answer |> String.trim() |> String.upcase() == @m2_answer
    {:noreply, assign(socket, :m2_answer_feedback, correct?)}
  end

  def handle_event("m2_toggle_tool", _params, socket) do
    {:noreply, assign(socket, :m2_tool_open, not socket.assigns.m2_tool_open)}
  end

  def handle_event("m3_text_changed", %{"text" => text}, socket) do
    {:noreply,
     assign(socket,
       m3_text: text,
       m3_mapping: %{},
       m3_freq: [],
       m3_terminal_lines: []
     )}
  end

  def handle_event("m3_map_changed", %{"mapping" => mapping}, socket) do
    clean =
      Enum.reduce(mapping, %{}, fn {cipher_char, plain_value}, acc ->
        case plain_value |> String.upcase() |> String.slice(0, 1) do
          "" -> acc
          letter -> Map.put(acc, cipher_char, letter)
        end
      end)

    {:noreply, assign(socket, :m3_mapping, clean)}
  end

  def handle_event("m3_reset", _params, socket) do
    {:noreply, assign(socket, :m3_mapping, %{})}
  end

  def handle_event("m3_code_changed", %{"code" => code}, socket) do
    {:noreply, assign(socket, :m3_code, code)}
  end

  def handle_event("m3_run", _params, %{assigns: %{m3_status: :running}} = socket) do
    {:noreply, socket}
  end

  def handle_event("m3_run", _params, socket) do
    run_id = socket.assigns.run_seq + 1
    code = inject_cipher_text(socket.assigns.m3_code, socket.assigns.m3_text)

    socket =
      assign(socket,
        run_seq: run_id,
        m3_run_id: run_id,
        m3_status: :running,
        m3_terminal_lines: []
      )

    case RunSupervisor.start_run(code, self(), run_id) do
      {:ok, pid} ->
        {:noreply, assign(socket, :m3_runner_pid, pid)}

      {:error, reason} ->
        socket = append_m3_line(socket, "[実行を開始できませんでした: #{inspect(reason)}]")
        {:noreply, assign(socket, m3_status: :idle, m3_runner_pid: nil)}
    end
  end

  def handle_event("m3_stop", _params, socket) do
    if socket.assigns.m3_runner_pid do
      Runner.stop(socket.assigns.m3_runner_pid)
    end

    {:noreply, socket}
  end

  def handle_event("m3_answer_submit", %{"answer" => answer}, socket) do
    correct? = normalize_m3_answer(answer) == normalize_m3_answer(@m3_answer)
    {:noreply, assign(socket, :m3_answer_feedback, correct?)}
  end

  def handle_event("m3_toggle_tool", _params, socket) do
    {:noreply, assign(socket, :m3_tool_open, not socket.assigns.m3_tool_open)}
  end

  def handle_event("m4_cipher_changed", %{"cipher" => cipher}, socket) do
    {:noreply, assign(socket, :m4_cipher, cipher)}
  end

  def handle_event("m4_key_changed", %{"key" => key}, socket) do
    {:noreply, assign(socket, :m4_key, key)}
  end

  def handle_event("m4_code_changed", %{"code" => code}, socket) do
    {:noreply, assign(socket, :m4_code, code)}
  end

  def handle_event("m4_run", _params, %{assigns: %{m4_status: :running}} = socket) do
    {:noreply, socket}
  end

  def handle_event("m4_run", _params, socket) do
    run_id = socket.assigns.run_seq + 1
    code = inject_cipher_text(socket.assigns.m4_code, socket.assigns.m4_cipher)

    socket =
      assign(socket,
        run_seq: run_id,
        m4_run_id: run_id,
        m4_status: :running,
        m4_terminal_lines: []
      )

    case RunSupervisor.start_run(code, self(), run_id) do
      {:ok, pid} ->
        {:noreply, assign(socket, :m4_runner_pid, pid)}

      {:error, reason} ->
        socket = append_m4_line(socket, "[実行を開始できませんでした: #{inspect(reason)}]")
        {:noreply, assign(socket, m4_status: :idle, m4_runner_pid: nil)}
    end
  end

  def handle_event("m4_stop", _params, socket) do
    if socket.assigns.m4_runner_pid do
      Runner.stop(socket.assigns.m4_runner_pid)
    end

    {:noreply, socket}
  end

  def handle_event("m4_answer_submit", %{"answer" => answer}, socket) do
    correct? = normalize_m4_answer(answer) == normalize_m4_answer(@m4_answer)
    {:noreply, assign(socket, :m4_answer_feedback, correct?)}
  end

  def handle_event("m4_toggle_tool", _params, socket) do
    {:noreply, assign(socket, :m4_tool_open, not socket.assigns.m4_tool_open)}
  end

  @impl true
  def handle_info({:python_output, run_id, line}, %{assigns: %{m2_run_id: run_id}} = socket) do
    {:noreply, append_m2_line(socket, line)}
  end

  def handle_info({:python_done, run_id, _status}, %{assigns: %{m2_run_id: run_id}} = socket) do
    {:noreply, assign(socket, m2_status: :idle, m2_runner_pid: nil)}
  end

  def handle_info({:python_output, run_id, line}, %{assigns: %{m3_run_id: run_id}} = socket) do
    {:noreply, append_m3_line(socket, line)}
  end

  def handle_info({:python_done, run_id, _status}, %{assigns: %{m3_run_id: run_id}} = socket) do
    {:noreply, assign(socket, m3_status: :idle, m3_runner_pid: nil)}
  end

  def handle_info({:python_output, run_id, line}, %{assigns: %{m4_run_id: run_id}} = socket) do
    {:noreply, append_m4_line(socket, line)}
  end

  def handle_info({:python_done, run_id, _status}, %{assigns: %{m4_run_id: run_id}} = socket) do
    {:noreply, assign(socket, m4_status: :idle, m4_runner_pid: nil)}
  end

  # 古い実行（既に停止・タイムアウトで終わったもの）からの遅延メッセージは無視する。
  def handle_info({:python_output, _run_id, _line}, socket), do: {:noreply, socket}
  def handle_info({:python_done, _run_id, _status}, socket), do: {:noreply, socket}

  # ── ミッション1: ヘルパー ────────────────────────────────

  defp m1_decode(cipher, shift, "alpha"), do: Ciphers.caesar_decode_alpha(cipher, shift)
  defp m1_decode(cipher, shift, _hira), do: Ciphers.caesar_decode(cipher, shift)

  defp m1_encode(cipher, shift, "alpha"), do: Ciphers.caesar_encode_alpha(cipher, shift)
  defp m1_encode(cipher, shift, _hira), do: Ciphers.caesar_encode(cipher, shift)

  # ── ミッション2: ヘルパー ────────────────────────────────

  defp m2_default_code do
    """

    def decode(text, k):
        result = ""
        for ch in text:
            if ch.isalpha():
                base = ord("A") if ch.isupper() else ord("a")
                result += chr((ord(ch) - base - k) % 26 + base)
            else:
                result += ch
        return result


    for k in range(5):
      print(f"k={k:2d}:", decode(CIPHER_TEXT, k))
    """
  end

  # Pythonの出力1行を受け取り、`k= 3: SOME TEXT`形式ならkと復号結果を取り出して
  # 暗号盤の位置に反映し、それ以外（エラー・終了コード表示など）はそのまま表示する。
  defp append_m2_line(socket, line) do
    entry =
      case Regex.run(~r/^k=\s*(\d+):\s(.*)$/, line) do
        [_, k_str, text] -> %{k: String.to_integer(k_str), text: text}
        nil -> %{k: nil, text: line}
      end

    socket =
      case entry.k do
        nil -> socket
        k -> assign(socket, :m2_disk_shift, k)
      end

    assign(socket, :m2_terminal_lines, socket.assigns.m2_terminal_lines ++ [entry])
  end

  # ── ミッション3: ヘルパー ────────────────────────────────

  defp is_alpha?(<<c::utf8>>) when c in ?A..?Z or c in ?a..?z, do: true
  defp is_alpha?(_), do: false

  defp m3_default_code do
    """
    counts = {}
    for ch in CIPHER_TEXT.upper():
        if ch.isalpha():
            counts[ch] = counts.get(ch, 0) + 1

    for letter, count in sorted(counts.items(), key=lambda item: -item[1]):
        print(f"{letter}: {count}")
    """
  end

  # Pythonの出力をそのまま1行ずつ表示する（`T: 42`のような集計結果や、
  # エラー時のトレースバックもすべて含めて、実行結果としてそのまま見せる）。
  # `T: 42`形式の行はさらに解析し、Step 2の出現頻度グラフ・対応表の元データ
  # （m3_freq）としても蓄積する。プログラム実行前はm3_freqが空のままなので、
  # Step 2はStep 1の実行結果が入るまで空欄になる。
  defp append_m3_line(socket, line) do
    socket = assign(socket, :m3_terminal_lines, socket.assigns.m3_terminal_lines ++ [%{text: line}])

    case Regex.run(~r/^([A-Z]): (\d+)$/, line) do
      [_, letter, count_str] ->
        assign(socket, :m3_freq, socket.assigns.m3_freq ++ [{letter, String.to_integer(count_str)}])

      nil ->
        socket
    end
  end

  # 解答の全文入力は複数行になるため、改行コードの違い（\r\n / \n）と
  # 前後の空白を吸収してから比較する。
  defp normalize_m3_answer(text), do: text |> String.replace("\r\n", "\n") |> String.trim()

  # ミッション4は大文字小文字の揺れを許容しつつ、改行差分を吸収して比較する。
  defp normalize_m4_answer(text), do: text |> String.replace("\r\n", "\n") |> String.trim() |> String.upcase()

  defp chunk_lines(preview) do
    preview
    |> Enum.chunk_while(
      [],
      fn
        {"\n", "\n"}, acc -> {:cont, Enum.reverse(acc), []}
        item, acc -> {:cont, [item | acc]}
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
  end

  # 4列表示を縦詰めで並べる。
  # 例: 1..26 ->
  # 1 8 15 21
  # 2 9 16 22
  # ...
  # 7 14
  defp reorder_freq_for_columns(freq, cols) when cols > 0 do
    total = length(freq)
    rows = div(total + cols - 1, cols)
    base = div(total, cols)
    rem_cols = rem(total, cols)

    col_sizes =
      0..(cols - 1)
      |> Enum.map(fn c -> if c < rem_cols, do: base + 1, else: base end)

    columns =
      Enum.map_reduce(col_sizes, freq, fn size, rest ->
        {Enum.take(rest, size), Enum.drop(rest, size)}
      end)
      |> elem(0)

    0..(rows - 1)
    |> Enum.flat_map(fn row_idx ->
      columns
      |> Enum.map(&Enum.at(&1, row_idx))
      |> Enum.reject(&is_nil/1)
    end)
  end

  # ── ミッション4: ヘルパー ────────────────────────────────

  defp m4_default_code do
    """

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


    # ヒント: 鍵は「日本の首都（アルファベット大文字5文字）」
    candidates = ["TOKYO"]

    for key in candidates:
      print(f"key={key}:", decode(CIPHER_TEXT, key))
    """
  end

  defp inject_cipher_text(code, cipher_text) do
    "CIPHER_TEXT = #{inspect(cipher_text)}\n" <> code
  end

  # Pythonの出力1行を受け取り、`key=XXXXX: 復号結果`形式なら鍵と復号結果を取り出し、
  # それ以外（エラーなど）はそのまま表示する。
  defp append_m4_line(socket, line) do
    entry =
      case Regex.run(~r/^key=(\S+):\s(.*)$/, line) do
        [_, key, text] -> %{key: key, text: text}
        nil -> %{key: nil, text: line}
      end

    assign(socket, :m4_terminal_lines, socket.assigns.m4_terminal_lines ++ [entry])
  end

  # ── 暗号円盤の座標計算（ミッション1・2で共用） ──────────────

  defp disk_positions(chars_string, radius) do
    chars = String.graphemes(chars_string)
    total = length(chars)

    chars
    |> Enum.with_index()
    |> Enum.map(fn {char, i} ->
      angle_deg = i * 360 / total - 90
      rad = angle_deg * :math.pi() / 180
      %{char: char, x: radius * :math.cos(rad), y: radius * :math.sin(rad)}
    end)
  end

  defp tab_class(current, this) do
    if current == this do
      "tab !bg-primary !text-primary-content font-bold rounded-t-lg shadow-sm border border-primary"
    else
      "tab !text-base-content/70 hover:!text-base-content hover:!bg-base-200 rounded-t-lg"
    end
  end

  attr :chars, :string, required: true
  attr :shift, :integer, required: true
  attr :font_size, :string, default: "11"

  defp cipher_disk(assigns) do
    total = String.length(assigns.chars)

    assigns =
      assign(assigns,
        outer: disk_positions(assigns.chars, 127),
        inner: disk_positions(assigns.chars, 80),
        angle: -assigns.shift * (360 / total)
      )

    ~H"""
    <svg viewBox="-160 -160 320 320" class="w-64 h-64">
      <polygon points="0,-158 -8,-142 8,-142" class="fill-error" />
      <circle r="150" class="fill-base-200 stroke-base-content/40" stroke-width="2" />
      <circle r="105" class="fill-base-100 stroke-base-300" stroke-width="1.5" />
      <text
        :for={p <- @outer}
        x={p.x}
        y={p.y + 5}
        text-anchor="middle"
        font-size={@font_size}
        font-weight="bold"
        class="fill-base-content"
      >{p.char}</text>
      <g transform={"rotate(#{@angle})"}>
        <circle r="105" class="fill-primary/10 stroke-primary" stroke-width="2" />
        <circle r="55" class="fill-base-100 stroke-primary/40" stroke-width="1.5" />
        <text
          :for={p <- @inner}
          x={p.x}
          y={p.y + 5}
          text-anchor="middle"
          font-size={@font_size}
          font-weight="bold"
          class="fill-primary"
        >{p.char}</text>
      </g>
      <circle r="20" class="fill-primary" />
    </svg>
    """
  end

  # 指令書欄の「解答」フォーム送信後に出す正誤フィードバック。
  # `nil`＝未送信、`true`＝正解、`false`＝不正解。
  attr :feedback, :any, required: true

  defp answer_feedback(assigns) do
    ~H"""
    <p :if={@feedback == true} class="text-success text-sm font-bold mt-2">✅ 正解です！</p>
    <p :if={@feedback == false} class="text-error text-sm font-bold mt-2">
      ❌ 違うようです。もう一度確認してみましょう。
    </p>
    """
  end

  # render/1のみからは参照できないモジュール属性を、関数コンポーネント側で
  # 使うための小さなラッパー（~H内の@はassignsを指すため、モジュール属性は
  # 直接読めない。これらは「指令書」欄の固定表示専用で、assignsに含める
  # ほどではない定数のため関数化して都度呼び出す）。
  defp m1_hira_cipher_display, do: @m1_hira_default
  defp m3_original_cipher, do: @m3_cipher
  defp m4_original_cipher, do: @m4_cipher

  # ── ミッション1: シーザー暗号（ひらがな／アルファベット） ──────

  attr :lang, :string, required: true
  attr :cipher, :string, required: true
  attr :shift, :integer, required: true
  attr :answer_feedback, :any, required: true
  attr :tool_open, :boolean, required: true

  def mission1(assigns) do
    {disk_chars, font_size} =
      if assigns.lang == "alpha", do: {Ciphers.alphabet(), "14"}, else: {Ciphers.hiragana(), "11"}

    assigns =
      assign(assigns,
        disk_chars: disk_chars,
        font_size: font_size,
        decoded: m1_decode(assigns.cipher, assigns.shift, assigns.lang),
        encoded: m1_encode(assigns.cipher, assigns.shift, assigns.lang)
      )

    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm p-5 mb-4">
      <h2 class="font-bold text-primary mb-2">📜 指令書</h2>
      <p>最初の暗号を傍受した。制限時間10分で復号せよ。</p>
      <div class="font-mono font-bold bg-base-200 rounded p-3 mt-2">{m1_hira_cipher_display()}</div>

      <form phx-submit="m1_answer_submit" class="flex items-center gap-2 mt-3">
        <label class="font-bold text-sm shrink-0">解答：</label>
        <input
          type="text"
          name="answer"
          placeholder="解読した文章を入力"
          class="input input-bordered input-sm flex-1"
        />
        <button type="submit" class="btn btn-primary btn-sm">送信</button>
      </form>
      <.answer_feedback feedback={@answer_feedback} />
    </div>

    <details class="collapse collapse-arrow bg-base-100 border border-warning mb-4">
      <summary class="collapse-title font-bold">💡 ヒントを表示する</summary>
      <div class="collapse-content text-sm flex flex-col gap-2">
        <p><strong>シーザー暗号（ずらす暗号）</strong>が使われています。</p>
        <p>文字を「同じ数だけ戻す」と意味の通る言葉になります。暗号円盤を使って試してみましょう！</p>
      </div>
    </details>

    <details class="collapse collapse-arrow bg-base-100 border border-base-300" open={@tool_open}>
      <summary class="collapse-title font-bold" phx-click="m1_toggle_tool">⚙️ 解読ツール ＆ 暗号作成コーナー</summary>
      <div class="collapse-content flex flex-col gap-4">
        <form id="m1-lang-form" phx-change="m1_lang_changed" class="flex gap-4">
          <label class="flex items-center gap-1.5 font-bold cursor-pointer">
            <input type="radio" name="lang" value="hira" checked={@lang == "hira"} class="radio radio-sm" />
            ひらがな（50音 / 46文字）
          </label>
          <label class="flex items-center gap-1.5 font-bold cursor-pointer">
            <input type="radio" name="lang" value="alpha" checked={@lang == "alpha"} class="radio radio-sm" />
            アルファベット（A-Z / 26文字）
          </label>
        </form>

        <label class="label text-sm font-bold">対象の文章（暗号文・自由テキスト）：</label>
        <form id="m1-cipher-form" phx-change="m1_cipher_changed">
          <input
            type="text"
            name="cipher"
            value={@cipher}
            placeholder="好きな文章を入力してください"
            class="input input-bordered w-full font-mono"
          />
        </form>

        <div class="flex flex-col items-center gap-3">
          <.cipher_disk chars={@disk_chars} shift={@shift} font_size={@font_size} />
          <div class="flex items-center gap-4">
            <button class="btn btn-sm" phx-click="m1_rotate" phx-value-dir="-1">↺ 1つ左へ</button>
            <div class="font-bold text-primary min-w-28 text-center">ずらし（鍵）: {@shift}</div>
            <button class="btn btn-sm" phx-click="m1_rotate" phx-value-dir="1">1つ右へ ↻</button>
          </div>
        </div>

        <div>
          <h3 class="font-bold mb-1">解読結果（戻す ⬅️）</h3>
          <div class="font-mono text-xl font-bold border-2 border-base-300 rounded p-4 min-h-16">
            {@decoded}
          </div>
        </div>

        <div>
          <h3 class="font-bold mb-1">暗号化結果（進める ➔）</h3>
          <div class="font-mono text-xl font-bold border-2 border-base-300 rounded p-4 min-h-16">
            {@encoded}
          </div>
        </div>
      </div>
    </details>
    """
  end

  # ── ミッション2: 鍵不明の暗号（手動ステップ＋自動回転総当たり） ──

  attr :cipher, :string, required: true
  attr :single_k, :integer, required: true
  attr :single_result, :any, required: true
  attr :manual_tested, :any, required: true
  attr :manual_history, :list, required: true
  attr :disk_shift, :integer, required: true
  attr :code, :string, required: true
  attr :status, :atom, required: true
  attr :terminal_lines, :list, required: true
  attr :answer_feedback, :any, required: true
  attr :tool_open, :boolean, required: true

  def mission2(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm p-5 mb-4">
      <h2 class="font-bold text-primary mb-2">📜 指令書</h2>
      <p>新たな暗号文を傍受した。復号せよ。</p>
      <div class="font-mono font-bold bg-base-200 rounded p-3 mt-2">{@cipher}</div>
      <form phx-submit="m2_answer_submit" class="flex items-center gap-2 mt-3">
        <label class="font-bold text-sm shrink-0">解答：</label>
        <input
          type="text"
          name="answer"
          placeholder="解読した文章を入力"
          class="input input-bordered input-sm flex-1"
        />
        <button type="submit" class="btn btn-primary btn-sm">送信</button>
      </form>
      <.answer_feedback feedback={@answer_feedback} />
    </div>

    <details class="collapse collapse-arrow bg-base-100 border border-warning mb-4">
      <summary class="collapse-title font-bold">💡 ヒントを表示する</summary>
      <div class="collapse-content text-sm flex flex-col gap-2">
        <p>1つずつ手動で試すのは時間がかかります。</p>
        <p>
          コンピュータの繰り返し処理（<code>for</code>ループ）を使えば、0から25までの
          全パターン（総当たり攻撃）を一気に試行できます。下のコードエディタで
          <code>range(...)</code>の数を書き換えて、実際にPythonプログラムとして
          実行してみましょう！
        </p>
      </div>
    </details>

    <details class="collapse collapse-arrow bg-base-100 border border-base-300" open={@tool_open}>
      <summary class="collapse-title font-bold" phx-click="m2_toggle_tool">⚙️ 解読ツール ＆ ブルートフォース解読シミュレーター</summary>
      <div class="collapse-content flex flex-col gap-4">
        <label class="label text-sm font-bold">対象の文章（暗号文・自由テキスト）：</label>
        <form id="m2-cipher-form" phx-change="m2_cipher_changed">
          <input
            type="text"
            name="cipher"
            value={@cipher}
            placeholder="好きな文章を入力してください"
            class="input input-bordered w-full font-mono"
          />
        </form>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 items-start">
          <div class="flex flex-col items-center bg-base-200 border border-base-300 rounded p-4">
            <p class="font-bold text-sm mb-2 text-primary">🔄 プログラム連動 暗号盤</p>
            <.cipher_disk chars={Ciphers.alphabet()} shift={@disk_shift} font_size="14" />
            <div class="font-bold text-primary mt-2">現在の位置（鍵 k）: {@disk_shift}</div>
          </div>

          <div class="flex flex-col gap-4">
            <div>
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold">Step 1: 手動で位置（k）を変えて動かしてみる</h3>
                <span class="text-xs font-bold text-warning">
                  手動試行: {MapSet.size(@manual_tested)} / 26 回
                </span>
              </div>
              <div class="bg-base-200 border border-base-300 rounded p-3">
                <form id="m2-single-k-form" phx-change="m2_single_k_changed" class="flex items-center gap-2 mb-2">
                  <label class="font-bold text-sm">位置（k）：</label>
                  <input
                    type="number"
                    name="k"
                    value={@single_k}
                    min="0"
                    max="25"
                    class="input input-bordered input-sm w-20"
                  />
                  <button type="button" class="btn btn-sm" phx-click="m2_single_run">この位置に合わせる</button>
                </form>
                <div class="bg-base-100 border border-base-300 rounded p-2 font-mono text-sm min-h-11">
                  {@single_result || "位置を選んでボタンを押すと暗号盤が回ります"}
                </div>
                <div class="bg-base-100 border border-base-300 rounded p-2 mt-2 max-h-28 overflow-y-auto font-mono text-xs">
                  <p :if={@manual_history == []} class="opacity-50 italic">まだ手動の履歴はありません</p>
                  <div :for={{k, decoded} <- @manual_history} class="py-0.5 border-b border-base-300/50">
                    <strong>k = {k}</strong> ➔ {decoded}
                  </div>
                </div>
              </div>
            </div>

            <div>
              <h3 class="font-bold mb-1">Step 2: 実際にPythonプログラムを書いて実行する</h3>
              <p class="text-xs opacity-70 mb-2">
                下のコードは実際に実行されます。<code>for</code>ループの<code>range(...)</code>を
                書き換えて、0から25まで全パターンを試してみましょう。
              </p>

              <form id="m2-code-form" phx-change="m2_code_changed">
                <textarea
                  name="code"
                  rows="12"
                  spellcheck="false"
                  phx-debounce="300"
                  class="textarea textarea-bordered w-full font-mono text-xs"
                >{@code}</textarea>
              </form>

              <div class="flex items-center gap-3 mt-2">
                <button class="btn btn-primary btn-sm" phx-click="m2_run" disabled={@status == :running}>
                  ▶ 実行
                </button>
                <button class="btn btn-outline btn-sm" phx-click="m2_stop" disabled={@status != :running}>
                  ■ 停止
                </button>
                <span class="text-xs font-bold text-primary">
                  {if @status == :running, do: "実行中...", else: "待機中"}
                </span>
              </div>

              <h3 class="font-bold mt-3 mb-1">実行結果（ターミナル）</h3>
              <div
                id="m2-terminal"
                phx-hook=".AutoScroll"
                class="bg-neutral text-neutral-content font-mono text-sm rounded p-3 max-h-52 overflow-y-auto"
              >
                <p :if={@terminal_lines == []} class="opacity-60">
                  [SYSTEM READY] 実行ボタンを押すとプログラムの出力がここに表示されます...
                </p>
                <div :for={line <- @terminal_lines} class="flex gap-3 py-0.5">
                  <span :if={line.k} class="text-warning font-bold w-14">k = {line.k}:</span><span>{line.text}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </details>
    """
  end

  # ── ミッション3: 換字式暗号（頻度分析＋対応表＋使用状況パレット） ─

  attr :text, :string, required: true
  attr :mapping, :map, required: true
  attr :code, :string, required: true
  attr :status, :atom, required: true
  attr :terminal_lines, :list, required: true
  attr :freq, :list, required: true
  attr :answer_feedback, :any, required: true
  attr :tool_open, :boolean, required: true

  def mission3(assigns) do
    normalized_text = String.replace(assigns.text, "\r\n", "\n")
    preview = Ciphers.substitution_preview(normalized_text, assigns.mapping)
    lines = chunk_lines(preview)
    freq = assigns.freq
    freq_for_display = reorder_freq_for_columns(freq, 4)
    max_count = freq |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end)
    used_letters = assigns.mapping |> Map.values() |> MapSet.new()

    assigns =
      assign(assigns,
        lines: lines,
        freq: freq_for_display,
        max_count: max_count,
        alphabet_status: Enum.map(String.graphemes(Ciphers.alphabet()), &{&1, MapSet.member?(used_letters, &1)})
      )

    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm p-5 mb-4">
      <h2 class="font-bold text-primary mb-2">📜 指令書</h2>
      <p>長文の暗号文を傍受した。復号せよ。</p>
      <div class="font-mono font-bold bg-base-200 rounded p-3 mt-2 whitespace-pre-wrap">{m3_original_cipher()}</div>
      <form phx-submit="m3_answer_submit" class="flex flex-col gap-2 mt-3">
        <label class="font-bold text-sm">解答（全文を入力）：</label>
        <textarea
          name="answer"
          rows="4"
          placeholder="解読した文章をすべて入力"
          class="textarea textarea-bordered text-sm font-mono"
        ></textarea>
        <button type="submit" class="btn btn-primary btn-sm self-start">送信</button>
      </form>
      <.answer_feedback feedback={@answer_feedback} />
    </div>

    <details class="collapse collapse-arrow bg-base-100 border border-warning mb-4">
      <summary class="collapse-title font-bold">💡 ヒントを表示する</summary>
      <div class="collapse-content text-sm flex flex-col gap-2">
        <p>文字をバラバラに置き換える<strong>単一換字式暗号</strong>です。</p>
        <p>
          <strong>連鎖解読のコツ：</strong><br />
          1. グラフで圧倒的1位の文字 <b>T / t</b> は、英語で最も使われる <b>E / e</b> です！<br />
          2. 何度も出てくる3文字の <b>Zit / zit</b> は <b>The / the</b>（Z=T, I=H, T=E）です。<br />
          3. 「T, H, E」が入ると、<b>ziol</b>（thi_ ➔ this）や <b>ziqz</b>（th_t ➔ that）が見えてきます！
        </p>
        <p>まずはStep 1で、実際にプログラムを書いて頻度を数えてみましょう。</p>
      </div>
    </details>

    <details class="collapse collapse-arrow bg-base-100 border border-base-300" open={@tool_open}>
      <summary class="collapse-title font-bold" phx-click="m3_toggle_tool">⚙️ 解読ツール ＆ 頻度分析実験</summary>
      <div class="collapse-content flex flex-col gap-4">
        <label class="label text-sm font-bold">対象の文章（暗号文・自由テキスト）：</label>
        <form id="m3-text-form" phx-change="m3_text_changed">
          <textarea
            name="text"
            rows="6"
            class="textarea textarea-bordered w-full font-mono text-sm"
          >{@text}</textarea>
        </form>

        <div>
          <h3 class="font-bold mb-1">Step 1: 頻度をプログラムで集計する</h3>
          <p class="text-xs opacity-70 mb-2">
            下のコードは実際に実行されます。上の「対象の文章」に入力されているテキストを対象に、
            26文字それぞれが何回出てくるかをプログラムで数えてみましょう。
          </p>

          <form id="m3-code-form" phx-change="m3_code_changed">
            <textarea
              name="code"
              rows="12"
              spellcheck="false"
              phx-debounce="300"
              class="textarea textarea-bordered w-full font-mono text-xs"
            >{@code}</textarea>
          </form>

          <div class="flex items-center gap-3 mt-2">
            <button class="btn btn-primary btn-sm" phx-click="m3_run" disabled={@status == :running}>
              ▶ 実行
            </button>
            <button class="btn btn-outline btn-sm" phx-click="m3_stop" disabled={@status != :running}>
              ■ 停止
            </button>
            <span class="text-xs font-bold text-primary">
              {if @status == :running, do: "実行中...", else: "待機中"}
            </span>
          </div>

          <h3 class="font-bold mt-3 mb-1">実行結果（ターミナル）</h3>
          <div
            id="m3-terminal"
            phx-hook=".AutoScroll"
            class="bg-neutral text-neutral-content font-mono text-sm rounded p-3 max-h-52 overflow-y-auto"
          >
            <p :if={@terminal_lines == []} class="opacity-60">
              [SYSTEM READY] 実行ボタンを押すとプログラムの出力がここに表示されます...
            </p>
            <div :for={line <- @terminal_lines} class="py-0.5">{line.text}</div>
          </div>
        </div>

        <div class="flex flex-col gap-5">
          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="font-bold">Step 2: 📊 入力した文章の出現頻度と対応表（全26文字網羅）</h3>
              <button class="btn btn-error btn-xs" phx-click="m3_reset">リセット</button>
            </div>

            <div class="bg-base-200 border border-base-300 rounded p-2 mb-3">
              <div class="flex items-center justify-between text-xs font-bold opacity-70 mb-1.5">
                <span>🔤 復号文字の使用状況（A〜Z）</span>
                <span class="font-normal">グレー＝使用済み</span>
              </div>
              <div class="grid grid-cols-[repeat(26,minmax(0,1fr))] gap-1 w-full">
                <div
                  :for={{letter, used} <- @alphabet_status}
                  class={[
                    "h-6 w-full flex items-center justify-center font-mono font-bold text-xs rounded border",
                    used && "bg-base-300 text-base-content/50 line-through border-base-300" ||
                      "bg-base-100 text-primary border-primary"
                  ]}
                >
                  {letter}
                </div>
              </div>
            </div>

            <p :if={@freq == []} class="text-sm opacity-60 italic">
              上の「対象の文章」を変更した後にStep 1を実行すると、ここに最新の集計結果が表示されます。
            </p>
            <form id="m3-mapping-form" phx-change="m3_map_changed" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-1.5">
              <div :for={{char, count} <- @freq} class="grid grid-cols-[20px_1fr_28px_16px_36px] items-center gap-1.5 bg-base-200 border border-base-300 rounded px-2 py-1">
                <div class="font-mono font-bold text-center">{char}</div>
                <div class="h-2 bg-base-300 rounded overflow-hidden">
                  <div class="h-full bg-primary rounded" style={"width: #{count / @max_count * 100}%"}></div>
                </div>
                <span class="text-xs opacity-60 text-right">{count}</span>
                <div class="text-center opacity-60 text-xs">➔</div>
                <input
                  type="text"
                  name={"mapping[#{char}]"}
                  value={Map.get(@mapping, char, "")}
                  maxlength="1"
                  class="input input-bordered input-sm w-9 text-center font-mono font-bold uppercase"
                />
              </div>
            </form>
          </div>

          <div>
            <h3 class="font-bold mb-2">📖 解読プレビュー（スクロール可）</h3>
            <div class="border border-base-300 rounded p-3 flex flex-col gap-2">
              <div :for={line <- @lines} class="bg-base-200 border border-base-300 rounded p-2">
                <div class="flex flex-wrap gap-y-1">
                  <div :for={{orig, plain} <- line} class={["inline-flex flex-col items-center font-mono", orig == " " && "w-3" || "w-5"]}>
                    <span class="text-xs opacity-60">{if orig == " ", do: raw("&nbsp;"), else: orig}</span>
                    <span class={[
                      "text-sm font-bold h-6 leading-6 w-full text-center rounded",
                      is_alpha?(orig) && is_nil(plain) && "text-base-300",
                      is_alpha?(orig) && plain && "bg-primary/10 text-primary"
                    ]}>
                      {cond do
                        orig == " " -> raw("&nbsp;")
                        is_alpha?(orig) -> plain || "_"
                        true -> orig
                      end}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </details>
    """
  end

  # ── ミッション4: ヴィジュネル暗号（復号＋暗号化） ───────────

  attr :cipher, :string, required: true
  attr :key, :string, required: true
  attr :code, :string, required: true
  attr :status, :atom, required: true
  attr :terminal_lines, :list, required: true
  attr :answer_feedback, :any, required: true
  attr :tool_open, :boolean, required: true

  def mission4(assigns) do
    {decoded, encoded} =
      if assigns.key == "" do
        {"鍵を入力してください", "鍵を入力してください"}
      else
        {Ciphers.vigenere_decode(assigns.cipher, assigns.key), Ciphers.vigenere_encode(assigns.cipher, assigns.key)}
      end

    assigns = assign(assigns, decoded: decoded, encoded: encoded)

    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm p-5 mb-4">
      <h2 class="font-bold text-primary mb-2">📜 指令書</h2>
      <p>最高レベルの暗号文を傍受した。復号せよ。</p>
      <div class="font-mono font-bold bg-base-200 rounded p-3 mt-2 whitespace-pre-wrap">{m4_original_cipher()}</div>
      <form phx-submit="m4_answer_submit" class="flex flex-col gap-2 mt-3">
        <label class="font-bold text-sm">解答（全文を入力）：</label>
        <textarea
          name="answer"
          rows="4"
          placeholder="解読した文章を入力"
          class="textarea textarea-bordered text-sm font-mono"
        ></textarea>
        <button type="submit" class="btn btn-primary btn-sm self-start">送信</button>
      </form>
      <.answer_feedback feedback={@answer_feedback} />
    </div>

    <details class="collapse collapse-arrow bg-base-100 border border-warning mb-4">
      <summary class="collapse-title font-bold">💡 ヒントを表示する</summary>
      <div class="collapse-content text-sm flex flex-col gap-2">
        <p>鍵が単語になっている<strong>ヴィジュネル暗号</strong>です。</p>
        <p>
          AIに解読用Pythonプログラムを作成・実行させた結果、暗号の鍵は
          <b>「日本の首都（アルファベット大文字5文字）」</b>であると判明しました！
          下のStep 1で、実際にAIに書かせたようなプログラムを動かして確かめてみましょう。
        </p>
      </div>
    </details>

    <details class="collapse collapse-arrow bg-base-100 border border-base-300" open={@tool_open}>
      <summary class="collapse-title font-bold" phx-click="m4_toggle_tool">⚙️ 解読ツール ＆ ヴィジュネル暗号作成</summary>
      <div class="collapse-content flex flex-col gap-4">
        <label class="label text-sm font-bold">対象の文章（暗号文・自由テキスト）：</label>
        <form id="m4-cipher-form" phx-change="m4_cipher_changed">
          <textarea
            name="cipher"
            rows="8"
            placeholder="好きな英文を入力してください"
            class="textarea textarea-bordered w-full font-mono text-sm"
          >{@cipher}</textarea>
        </form>

        <div>
          <h3 class="font-bold mb-1">Step 1: AIに作らせたプログラムを実行する</h3>
          <p class="text-xs opacity-70 mb-2">
            下のコードは実際に実行されます。<code>candidates</code>のリストに試したい鍵を
            追加したり、AIに考えさせたコードに書き換えたりして実行してみましょう。
          </p>

          <form id="m4-code-form" phx-change="m4_code_changed">
            <textarea
              name="code"
              rows="14"
              spellcheck="false"
              phx-debounce="300"
              class="textarea textarea-bordered w-full font-mono text-xs"
            >{@code}</textarea>
          </form>

          <div class="flex items-center gap-3 mt-2">
            <button class="btn btn-primary btn-sm" phx-click="m4_run" disabled={@status == :running}>
              ▶ 実行
            </button>
            <button class="btn btn-outline btn-sm" phx-click="m4_stop" disabled={@status != :running}>
              ■ 停止
            </button>
            <span class="text-xs font-bold text-primary">
              {if @status == :running, do: "実行中...", else: "待機中"}
            </span>
          </div>

          <h3 class="font-bold mt-3 mb-1">実行結果（ターミナル）</h3>
          <div
            id="m4-terminal"
            phx-hook=".AutoScroll"
            class="bg-neutral text-neutral-content font-mono text-sm rounded p-3 max-h-52 overflow-y-auto"
          >
            <p :if={@terminal_lines == []} class="opacity-60">
              [SYSTEM READY] 実行ボタンを押すとプログラムの出力がここに表示されます...
            </p>
            <div :for={line <- @terminal_lines} class="flex gap-3 py-0.5">
              <span :if={line.key} class="text-warning font-bold w-24">key = {line.key}:</span><span>{line.text}</span>
            </div>
          </div>
        </div>

        <h3 class="font-bold mb-1 mt-4">Step 2: 鍵を直接試してみる</h3>
        <form id="m4-key-form" phx-change="m4_key_changed" class="flex items-center gap-2 mb-4">
          <label class="font-bold">鍵（KEY）：</label>
          <input type="text" name="key" value={@key} placeholder="例: TOKYO" class="input input-bordered w-48 font-mono" />
        </form>

        <div>
          <h3 class="font-bold mb-1">解読結果（鍵で戻す ⬅️）</h3>
          <div class="font-mono text-lg font-bold border-2 border-base-300 rounded p-4 min-h-16 whitespace-pre-wrap">
            {@decoded}
          </div>
        </div>

        <div class="mb-2">
          <h3 class="font-bold mb-1">暗号化結果（鍵で進める ➔）</h3>
          <div class="font-mono text-lg font-bold border-2 border-base-300 rounded p-4 min-h-16 whitespace-pre-wrap">
            {@encoded}
          </div>
        </div>
      </div>
    </details>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoScroll">
      export default {
        updated() {
          this.el.scrollTop = this.el.scrollHeight
        }
      }
    </script>

    <div class="p-6 max-w-[96rem] mx-auto">
      <h1 class="text-2xl font-bold mb-4">🔐 暗号解読ミッション 解読ツール</h1>

      <div role="tablist" class="tabs tabs-boxed bg-base-200 p-1 rounded-xl mb-6 gap-1">
        <a role="tab" class={tab_class(@tab, "m1")} phx-click="switch_tab" phx-value-tab="m1">
          ミッション1：シーザー暗号
        </a>
        <a role="tab" class={tab_class(@tab, "m2")} phx-click="switch_tab" phx-value-tab="m2">
          ミッション2：鍵不明の暗号
        </a>
        <a role="tab" class={tab_class(@tab, "m3")} phx-click="switch_tab" phx-value-tab="m3">
          ミッション3：複雑な暗号
        </a>
        <a role="tab" class={tab_class(@tab, "m4")} phx-click="switch_tab" phx-value-tab="m4">
          ミッション4：最難関の暗号
        </a>
      </div>

      <.mission1
        :if={@tab == "m1"}
        lang={@m1_lang}
        cipher={@m1_cipher}
        shift={@m1_shift}
        answer_feedback={@m1_answer_feedback}
        tool_open={@m1_tool_open}
      />

      <.mission2
        :if={@tab == "m2"}
        cipher={@m2_cipher}
        single_k={@m2_single_k}
        single_result={@m2_single_result}
        manual_tested={@m2_manual_tested}
        manual_history={@m2_manual_history}
        disk_shift={@m2_disk_shift}
        code={@m2_code}
        status={@m2_status}
        terminal_lines={@m2_terminal_lines}
        answer_feedback={@m2_answer_feedback}
        tool_open={@m2_tool_open}
      />

      <.mission3
        :if={@tab == "m3"}
        text={@m3_text}
        mapping={@m3_mapping}
        code={@m3_code}
        status={@m3_status}
        terminal_lines={@m3_terminal_lines}
        freq={@m3_freq}
        answer_feedback={@m3_answer_feedback}
        tool_open={@m3_tool_open}
      />

      <.mission4
        :if={@tab == "m4"}
        cipher={@m4_cipher}
        key={@m4_key}
        code={@m4_code}
        status={@m4_status}
        terminal_lines={@m4_terminal_lines}
        answer_feedback={@m4_answer_feedback}
        tool_open={@m4_tool_open}
      />
    </div>
    """
  end
end
