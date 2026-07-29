# このリポジトリ専用の chezmoi ソース

このディレクトリは、このリポジトリ(`ProgramingWorkshop`)内の各プロジェクトを
他のPCでも動かせるように、環境構築をchezmoiで自動化するための**このリポジトリ専用**の
chezmoiソースディレクトリです。特定のプロジェクトに限定されない汎用の仕組みとして使います。

個人の `~/.local/share/chezmoi`(dotfiles用)とは完全に別物です。混同を避けるため
`chezmoi init` はせず、常に `--source` オプションで明示的に指定して使います。
これにより個人のchezmoi設定(sourceDirやconfig)には一切影響しません。

## 新しいPCでのセットアップ手順

0. [scoop](https://scoop.sh/)とchezmoi自体が未導入の場合はインストールする。

   ```powershell
   # scoopが未導入の場合
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   irm get.scoop.sh | iex

   # chezmoiを導入
   scoop install chezmoi
   ```

1. このリポジトリをクローンする。

   ```powershell
   git clone <このリポジトリのURL> ProgramingWorkshop
   ```

2. リポジトリのルートを `--source` に指定して `chezmoi apply` を実行する。
   （ルート直下の `.chezmoiroot` により、実体としては `chezmoi/` サブディレクトリが
   ソースとして使われる）

   ```powershell
   chezmoi apply --source "C:\path\to\ProgramingWorkshop"
   ```

   これにより `.chezmoiscripts/` 配下のセットアップスクリプトが実行され、
   各プロジェクトに必要なツールチェーン導入・依存関係取得などが自動化される。

## 依存関係を更新したとき

各プロジェクトの依存関係定義を変更してコミットし、他のPCで `git pull` した後、再度

```powershell
chezmoi apply --source "C:\path\to\ProgramingWorkshop"
```

を実行すればセットアップスクリプトが再実行され、環境が最新化される。

## ファイル構成

- `.chezmoiscripts/`
  各プロジェクトのセットアップスクリプトを置く。ファイル名の attribute
  (`run_`/`run_once_`/`run_onchange_`など)を除いた部分の名前順に実行されるため、
  番号プレフィックス(`10-`, `20-`, ...)で実行順を制御する。
- `.chezmoiignore`
  この `README.md` など、ホームディレクトリへ配置すべきでないファイルを除外する。

新しいプロジェクトの環境構築を追加したい場合は、`.chezmoiscripts/` に
`run_onchange_<番号>-<名前>.ps1.tmpl` (導入・変更検知系) や
`run_<番号>-<名前>.ps1.tmpl` (毎回実行系) のスクリプトを追加していく。

## 前提条件

- Windows で [scoop](https://scoop.sh/) が導入可能なこと(未導入なら自動導入される)
- Git がインストール済みで、このリポジトリをクローンできること
