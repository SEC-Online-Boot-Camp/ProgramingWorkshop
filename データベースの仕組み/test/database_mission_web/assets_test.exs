defmodule DatabaseMissionWeb.AssetsTest do
  use ExUnit.Case, async: true

  # 研修PCにはビルド用のツールがないので、ビルド済みのCSSをコミットしている。
  # ソース(assets/css/app.css)の変更が、ビルド済みのCSSにも入っていることを確かめる
  @source File.read!("assets/css/app.css")
  @built File.read!("priv/static/assets/css/app.css")

  test "ターミナルのフォント: 日本語が全角=半角2つ分の等幅フォントにし、' \" ` だけ Consolas にする" do
    for css <- [@source, @built] do
      assert css =~ "Workshop Text Quote"
      assert css =~ "local(\"Consolas\")" or css =~ "local(Consolas)"
      assert css =~ ~r/unicode-range:\s*U\+(0022|22),\s*U\+(0027|27),\s*U\+(0060|60)/i
      assert css =~ "BIZ UDGothic"
      assert css =~ "MS Gothic"
      assert css =~ ~r/letter-spacing:\s*0/
      assert css =~ ".terminal-font"
    end
  end

  test "ビルド済みのCSSに、ターミナルで使うクラスが入っている" do
    for class <- ["bg-black", "text-red-400", "text-green-300", "h-80"] do
      assert @built =~ class, "ビルド済みのCSSに無い: #{class}"
    end
  end
end
