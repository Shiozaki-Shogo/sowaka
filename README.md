# sowaka

`sowaka` は、GitHub Pages で公開している静的サイトです。  
サイト本体は `docs/` 配下にあり、Markdown を直接編集して更新します。

## 使い方（最短）

1. `docs/index.md` または `docs/pages/*.md` を編集
2. 画像が必要なら `docs/photo/` または `docs/image/` に追加
3. ブランチを切ってコミットし、Pull Request を作成
4. `main` にマージすると GitHub Pages に反映

## ディレクトリ構成

- `docs/index.md` : トップページ
- `docs/pages/*.md` : 各コンテンツページ
- `docs/_layouts/default.html` : 共通レイアウト
- `docs/styles.css` : 共通スタイル
- `docs/photo`, `docs/image` : 画像アセット
- `docs/pages.json` : ページ一覧メタデータ

## 公開設定（GitHub Pages）

GitHub リポジトリの `Settings -> Pages` で以下を設定します。

- `Source`: `Deploy from a branch`
- `Branch`: `main` / `/docs`

## 注意

- 変換スクリプトは廃止済みです。`docs/` を直接編集してください。
- URL変更を避けるため、ページファイル名は既存のものを基本的に維持してください。
