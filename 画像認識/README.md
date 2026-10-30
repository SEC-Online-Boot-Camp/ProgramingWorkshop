# 画像認識（AIじゃんけん）

カメラに映した手（グー・チョキ・パー）をAIが見分けて、AIとじゃんけんをするScratchの作品です。
画像を見分けるAI（モデル）は、[Teachable Machine](https://teachablemachine.withgoogle.com/)で作ります。

| もの | 内容 |
|---|---|
| `AI_Janken.sb3` | じゃんけんのScratch作品 |
| `memo.txt` | 使うサイトのURL |

## 使うサイト

どちらもブラウザで使います。インストールは要りません。

- [Teachable Machine](https://teachablemachine.withgoogle.com/)：カメラの画像から、見分けるAI（モデル）を作るサイト（Google）
- [Stretch3](https://stretch3.github.io/)：Teachable Machineのモデルを使える拡張機能（TM2Scratch）が入った、Scratch 3.0

## 遊ぶ

1. ブラウザで[Stretch3](https://stretch3.github.io/)を開きます。
2. メニューの「ファイル」→「コンピューターから読み込む」で、`AI_Janken.sb3`を開きます。
3. カメラの使用を許可します。
4. 緑の旗を押して、カメラに手を映します。「じゃんけん」「ぽん！」の合図で、AIが人間の手とＡＩの手を比べ、「人間の勝ち」「ＡＩの勝ち」「あいこ」を表示します。

作品には、作成済みのモデルのURLが入っているので、そのまま遊べます。

## 自分でモデルを作る

1. [Teachable Machine](https://teachablemachine.withgoogle.com/)で、画像プロジェクト（標準の画像モデル）を作ります。
2. クラスを4つ作り、名前を`グー`・`チョキ`・`パー`・`なにか`にします（手を映していないときの画像は「なにか」）。
   作品は、この名前で手を見分けるので、1文字も違わないようにします。
3. カメラで、クラスごとに画像を撮って、モデルをトレーニングします。
4. 「モデルをエクスポート」で、モデルをアップロードし、表示された共有リンク（URL）をコピーします。
5. Stretch3の作品の中にある、画像分類モデルのURLを指定するブロックに、コピーしたURLを貼り付けます。
