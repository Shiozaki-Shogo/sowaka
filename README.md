# sowaka

旧 PukiWiki サイトを GitHub Pages で公開するための静的アーカイブです。

## 1. 変換を実行

このリポジトリの 1 つ上の階層に旧サイト一式（`wiki/`, `attach/`, `photo/` など）がある前提です。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-site.ps1 -SourceRoot .. -OutputDir docs
```

## 2. 出力されるもの

- `docs/index.html`: トップページ
- `docs/pages/*.html`: 各ページ
- `docs/attach`, `docs/image`, `docs/photo`, `docs/mp3`: 静的アセット
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
