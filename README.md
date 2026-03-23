# sowaka

旧 PukiWiki サイトを GitHub Pages で公開するための静的アーカイブです。

## 1. 運用方針

PukiWiki からの変換作業は完了済みです。  
今後は `docs/` 配下を直接編集して運用します（再変換スクリプトは廃止）。

## 2. 出力されるもの

- `docs/index.md`: トップページ（Jekyll で `index.html` として公開）
- `docs/pages/*.md`: 各ページ（Jekyll で `.html` 化）
- `docs/_layouts/default.html`: レイアウト
- `docs/image`, `docs/photo`: 静的アセット
- `docs/pages.json`: ページ一覧メタデータ

## 3. GitHub Pages 設定

GitHub リポジトリ設定で以下を指定します。

- `Settings` -> `Pages`
- `Build and deployment` -> `Source`: `Deploy from a branch`
- `Branch`: `main` / `/docs`

## 4. 共同編集の推奨設定

- `Settings` -> `Collaborators` でメンバー追加
- `Settings` -> `Branches` で `main` 保護
- Pull Request 必須、直接 push を制限
