# PyGameチュートリアル

Pythonのゲーム用ライブラリ「PyGame」の使い方を、3つのサンプルで順に学びます。

| ファイル | 内容 |
|---|---|
| `sample1.py` | PyGameが入っているかを確かめる（バージョンを表示する） |
| `sample2.py` | ゲームの土台。ウィンドウを開いて、毎秒60回、画面を塗りつぶして描き直す |
| `sample3.py` | 赤い円（プレイヤー）を、キーボードで動かす |

## 準備（初回だけ）

Python 3.12が必要です。PyGameを入れます。

```powershell
py -3.12 -m pip install pygame
```

## 動かす

このフォルダで、動かしたいサンプルを実行します。

```powershell
py -3.12 sample1.py
py -3.12 sample2.py
py -3.12 sample3.py
```

`sample3.py`の操作は、`W`（上）・`A`（左）・`S`（下）・`D`（右）です。
`sample2.py`・`sample3.py`は、ウィンドウの「×」で閉じます。
