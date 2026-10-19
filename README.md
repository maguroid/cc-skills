# cc-skills

[Claude Code](https://claude.com/claude-code) 用のスキルを管理する個人リポジトリです。1つのスキルは1つのディレクトリにまとまっており、Claude Code がタスクに応じて自動で読み込んで使います。あわせて、リポジトリにシークレットが紛れ込むのを防ぐための軽量な仕組み（secretlint + lefthook）を同梱しています。

## スキルとは

Claude Code の「スキル」は、特定の作業手順をまとめた説明書です。各スキルのディレクトリ直下には `SKILL.md` があり、その先頭（フロントマター）に `name` と `description` が書かれています。Claude Code はこの `description` を見て、ユーザーの依頼に合うスキルを自分で選んで読み込みます。補助ファイルは `references/`（詳細手順のドキュメント）や `scripts/`（実行用スクリプト）に置きます。

## 含まれるスキル

| スキル | 概要 |
|--------|------|
| [`codex-delegate`](codex-delegate/SKILL.md) | ユーザーが Codex への委譲を求めたとき、タスクを `codex exec` に渡して結果を点検・要約する。 |

### codex-delegate の構成

- [`codex-delegate/SKILL.md`](codex-delegate/SKILL.md) — スキル本体。委譲プロンプトの書き方、ラッパースクリプトの呼び出し方、完了後の点検方針。
- [`codex-delegate/references/options.md`](codex-delegate/references/options.md) — サンドボックス・ネットワーク・モデル・推論努力・Web 検索の各オプションの選び方。
- [`codex-delegate/references/review.md`](codex-delegate/references/review.md) — git diff のレビュー（`codex exec review`）を行う場合の手順。
- [`codex-delegate/scripts/codex-run.sh`](codex-delegate/scripts/codex-run.sh) — `codex exec` を安全に呼ぶラッパー。stdin を閉じ（バックグラウンド実行時のハング防止）、全文トランスクリプトをログファイルに記録する。

> このスキルを実際に動かすには、別途 [Codex CLI](https://github.com/openai/codex)（`codex` コマンド）が PATH に必要です。`codex-run.sh` は `codex` が見つからない場合は終了コード 127 で止まります。

## セットアップ

このリポジトリのツール（シークレット検査）を動かすための手順です。スキル自体の利用に Node.js は必要ありません。

### 前提

- Node.js v22 以上 と npm（`secretlint` などの依存パッケージが `package-lock.json` で `node >= 22.0.0` を要求します）
- git

### 依存関係のインストール

```bash
npm install
```

これで `secretlint`（シークレット検査ツール）とその推奨ルールプリセットが `node_modules/` に入ります。

### git フックの有効化（任意だが推奨）

`lefthook.yml` では **pre-push** 時に、push 対象ファイルへ secretlint をかけるフックを定義しています。フックを有効にするには [lefthook](https://github.com/evilmartians/lefthook) をインストールしたうえで、リポジトリに登録します。

```bash
# lefthook を未導入なら、都度 npx で実行してフックを登録
npx lefthook install
```

登録後は `git push` のたびに、push されるファイルに対して自動で secretlint が走ります。検査に引っかかると push は中断されます。

> `lefthook` はこのリポジトリの `package.json` には含めていません。グローバル導入（Homebrew / `npm i -g lefthook` など）か `npx lefthook` で用意してください。

## 使い方

### シークレット検査を手動で実行する

```bash
# リポジトリ全体をまとめて検査
npm run secretlint -- "**/*"
```

`package.json` の `secretlint` スクリプトは `secretlint` を呼ぶだけなので、検査したいファイル（グロブ）を `--` の後ろに渡します。pre-push フックではこの引数部分に lefthook が push 対象ファイル（`{push_files}`）を自動で差し込みます。ルールは [`.secretlintrc.json`](.secretlintrc.json) の `@secretlint/secretlint-rule-preset-recommend` を使用します。

### スキルを使う

このリポジトリのスキルは、Claude Code からスキルとして認識される場所に置かれていれば、依頼内容に応じて Claude Code が自動的に読み込みます。たとえば「Codex に委譲して」と頼むと `codex-delegate` が選ばれます。スキルの配置・同期方法は利用環境によって異なるため、お使いの Claude Code のスキル設定に合わせてください。

## 新しいスキルの追加

既存の `codex-delegate` と同じ構成にならえば追加できます。

1. リポジトリ直下にスキル名のディレクトリを作る（例: `my-skill/`）。
2. その中に `SKILL.md` を作り、先頭にフロントマターを書く。

   ```markdown
   ---
   name: my-skill
   description: "このスキルが何をするか・いつ使われるかを1〜2文で。Claude Code はこの説明で発動を判断する。"
   ---

   # My Skill

   手順をここに書く。
   ```

3. 詳細な手順は `my-skill/references/*.md` に、実行スクリプトは `my-skill/scripts/*` に分ける（任意）。`SKILL.md` からは相対パス（例: `references/options.md`）で参照する。
4. シェルスクリプトを置く場合は `shellcheck` をかけ、実行ビットを付けて `#!/usr/bin/env bash` と `set -euo pipefail` を基本にする。

## リポジトリ構成

```
.
├── codex-delegate/          # スキル: Codex への委譲
│   ├── SKILL.md
│   ├── references/
│   │   ├── options.md
│   │   └── review.md
│   └── scripts/
│       └── codex-run.sh
├── .claude/
│   └── settings.json        # Claude Code 用フック（下記参照）
├── .secretlintrc.json       # secretlint のルール設定
├── lefthook.yml             # pre-push で secretlint を実行
├── package.json             # secretlint 関連の依存とスクリプト
└── package-lock.json
```

### .claude/settings.json のフックについて

このリポジトリには、Claude Code のクラウドセッション向けフックが設定されています（`main` ブランチにいるときだけ動作します）。

- **SessionStart**: セッション開始時に `main` を `git pull --ff-only` で最新化する。
- **Stop**: 応答終了時に `main` の変更を自動コミット（`chore: auto-commit (Claude Code session)`）して push する。

`main` 以外のブランチでは、いずれのフックも何もしません。意図しない自動コミットを避けたい場合は、作業用ブランチを切って進めてください。
