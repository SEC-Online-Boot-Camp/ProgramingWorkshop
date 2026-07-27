defmodule CodebreakingMission.CiphersTest do
  use ExUnit.Case, async: true

  alias CodebreakingMission.Ciphers

  describe "caesar_decode/3 (ミッション1: ひらがな)" do
    test "鍵3でほもないめよを→ひみつをまもれ" do
      assert Ciphers.caesar_decode("ほもないめよを", 3) == "ひみつをまもれ"
    end

    test "鍵0は無変換" do
      assert Ciphers.caesar_decode("ほもないめよを", 0) == "ほもないめよを"
    end

    test "五十音にない文字（記号・空白）はそのまま通す" do
      # 復号（-shift方向）なので、あ(index0)は1つ戻ってん(末尾)になる
      assert Ciphers.caesar_decode("あ ！ん", 1) == "ん ！を"
    end
  end

  describe "caesar_encode/3 (ミッション1: 暗号化)" do
    test "decodeの鏡像になっている（暗号化してから復号すると元に戻る）" do
      original = "ひみつをまもれ"
      encoded = Ciphers.caesar_encode(original, 3)
      assert encoded == "ほもないめよを"
      assert Ciphers.caesar_decode(encoded, 3) == original
    end
  end

  describe "caesar_decode_alpha/2 と caesar_encode_alpha/2 のアルファベットモード" do
    test "ひらがなと同じ文章をアルファベットで暗号化・復号できる（往復一致）" do
      original = "HELLO WORLD"
      encoded = Ciphers.caesar_encode_alpha(original, 5)
      assert Ciphers.caesar_decode_alpha(encoded, 5) == original
      refute encoded == original
    end

    test "大文字・小文字を保持する" do
      assert Ciphers.caesar_encode_alpha("Hello", 1) == "Ifmmp"
    end
  end

  describe "caesar_decode_alpha/2 と brute_force/2 (ミッション2)" do
    @cipher "DPTVZF OL EDFRT YZ DSTCPT HZ XLEP"

    test "鍵11で正しい平文になる" do
      assert Ciphers.caesar_decode_alpha(@cipher, 11) == "SEIKOU DA TSUGI NO SHIREI WO MATE"
    end

    test "brute_forceは0からlimit-1までのタプルを返す" do
      results = Ciphers.brute_force(@cipher, 26)
      assert length(results) == 26
      assert {11, "SEIKOU DA TSUGI NO SHIREI WO MATE"} in results
      assert {0, @cipher} in results
    end
  end

  describe "letter_frequency/1 と substitution_preview/2 (ミッション3)" do
    @cipher """
    Zgh Ltektz!
    Ziol ol zit ltektz zqla ygk ngx.
    Zit stzztk t ol zit dglz yktjxtfz stzztk of Tfusoli.
    Ltt zit ziktt vgkrl zit, ziol, qfr ziqz.
    Tctkngft eqf lgsct ziol tqlosn vozi q sozzst ziofaofu.
    Ngx qkt ctkn ldqkz qfr ngx eqf rg ziol egrt.
    Zit jxoea wkgvf ygb pxdhl gctk zit sqmn rgu!
    Uggr sxea qfr iqct yxf vozi ziol eohitk lnlztd!
    """

    # 全26文字を使う単一換字式暗号。頻度分析とクリブ解読で手作業で導出・検証済み。
    @full_mapping %{
      "Z" => "T", "I" => "H", "T" => "E", "L" => "S", "Q" => "A", "F" => "N",
      "R" => "D", "O" => "I", "U" => "G", "E" => "C", "H" => "P", "K" => "R",
      "A" => "K", "Y" => "F", "G" => "O", "N" => "Y", "X" => "U", "S" => "L",
      "D" => "M", "J" => "Q", "C" => "V", "W" => "B", "V" => "W", "B" => "X",
      "P" => "J", "M" => "Z"
    }

    test "最頻出はT" do
      [{top_char, _count} | _] = Ciphers.letter_frequency(@cipher)
      assert top_char == "T"
    end

    test "完全な対応表を与えると全26文字が確定し、意図した平文になる（大文字小文字は保持）" do
      decoded =
        @cipher
        |> Ciphers.substitution_preview(@full_mapping)
        |> Enum.map_join(fn {_orig, plain} -> plain || "_" end)

      assert decoded =~ "Top Secret!"
      assert decoded =~ "This is the"
      assert decoded =~ "task for you."
      assert decoded =~ "The letter e is the most frequent letter in English."
      assert decoded =~ "See the three words the, this, and that."
      assert decoded =~ "You are very smart and you can do this code."
      assert decoded =~ "Everyone can solve this easily with a little thinking."
      assert decoded =~ "The quick brown fox jumps over the lazy dog!"
      assert decoded =~ "Good luck and have fun with this cipher system!"
      refute decoded =~ "_"
    end

    test "クリア判定に使う7文字（T,Z,I,L,Q,F,R）だけでも部分的に解読できる" do
      partial_mapping = Map.take(@full_mapping, ["Z", "I", "T", "L", "Q", "F", "R"])
      preview = Ciphers.substitution_preview("Ziol", partial_mapping)
      # Z→T, i→h, o→未確定(nil), l→s
      assert preview == [{"Z", "T"}, {"i", "h"}, {"o", nil}, {"l", "s"}]
    end

    test "未確定の文字はnilのまま返す" do
      preview = Ciphers.substitution_preview("ZIT", %{"Z" => "T"})
      assert preview == [{"Z", "T"}, {"I", nil}, {"T", nil}]
    end

    test "小文字の暗号文字は小文字の平文字を返す（大文字小文字を保持）" do
      preview = Ciphers.substitution_preview("Zit", %{"Z" => "T", "I" => "H", "T" => "E"})
      assert preview == [{"Z", "T"}, {"i", "h"}, {"t", "e"}]
    end

    test "空白・句読点はそのまま通す" do
      preview = Ciphers.substitution_preview("A B.", %{"A" => "X"})
      assert preview == [{"A", "X"}, {" ", " "}, {"B", nil}, {".", "."}]
    end
  end

  describe "vigenere_decode/2 (ミッション4)" do
    @cipher """
    Mcz Qsvfor. Zxjoj Thib.
    Wcn vkts ufyisg hrpsx qsnvxfc rcwoi, zim hrgg hbo gg wwpdsksxr.
    Has ucm bg k uckr, xmh t bekpxf, cm qhixrwgu dfs esdrskg ggze byr vxzz wcn.
    Zymy th dfs yfooixbmw htpvc. Wm wc yzfccr teod.
    Cjxfi jsmhop wl vsbwgu lcvbbn kogm ngtysbcbm akqyl.
    Typ hafoc vnbnpsw moyfl domdes myzesn rvbg dfs nblpstykzzx qsnvxf.
    Lsh xjol o ecxe yxm vcoosc y famdfa bbcgrx hrc hxld,
    ybw o wyqawxc qtb pgbw hryh kvirvf wx y ahaolh.
    Wc xmh mfeqh t goafxh wchacn. Rfngd komvokomwmq wggdcow.
    Oxb wy mys qtbxmh ufoyy mvo awivop, oly dfs aiwyb pvy fcerc rvx yow.
    """

    test "鍵TOKYOで正しい平文になる" do
      assert Ciphers.vigenere_decode(@cipher, "TOKYO") ==
               """
               Top Secret. Level Four.
               You have broken three ciphers today, but this one is different.
               The key is a word, not a number, so counting the letters will not help you.
               Look at the frequency table. It is almost flat.
               Every letter is hiding behind many different masks.
               For three hundred years people called this the unbreakable cipher.
               But even a long key leaves a rhythm inside the text,
               and a machine can find that rhythm in a moment.
               Do not trust a secret method. Trust mathematics instead.
               And if you cannot break the cipher, ask the human who holds the key.
               """
    end

    test "鍵が空文字なら空文字を返す" do
      assert Ciphers.vigenere_decode(@cipher, "") == ""
    end

    test "鍵に含まれる非アルファベットは除去して正規化される" do
      assert Ciphers.vigenere_decode(@cipher, "TOKYO") ==
               Ciphers.vigenere_decode(@cipher, "to-kyo!")
    end
  end

  describe "vigenere_encode/2 (ミッション4: 暗号化)" do
    test "decodeの鏡像になっている（暗号化してから復号すると元に戻る）" do
      original =
        """
        Top Secret. Level Four.
        You have broken three ciphers today, but this one is different.
        The key is a word, not a number, so counting the letters will not help you.
        Look at the frequency table. It is almost flat.
        Every letter is hiding behind many different masks.
        For three hundred years people called this the unbreakable cipher.
        But even a long key leaves a rhythm inside the text,
        and a machine can find that rhythm in a moment.
        Do not trust a secret method. Trust mathematics instead.
        And if you cannot break the cipher, ask the human who holds the key.
        """

      encoded = Ciphers.vigenere_encode(original, "TOKYO")
      assert encoded == @cipher
      assert Ciphers.vigenere_decode(encoded, "TOKYO") == original
    end

    test "鍵が空文字なら空文字を返す" do
      assert Ciphers.vigenere_encode("HELLO", "") == ""
    end
  end
end
