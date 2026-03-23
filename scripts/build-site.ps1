param(
  [string]$SourceRoot = "..",
  [string]$OutputDir = "docs",
  [string]$LandingPageRelPath = "pages/e382bde383afe382abe381a1e38283e38293e7968fe98894.html"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Decode-HexPageName {
  param([Parameter(Mandatory = $true)][string]$Hex)
  if ($Hex -notmatch "^[0-9A-Fa-f]+$" -or ($Hex.Length % 2 -ne 0)) {
    return $Hex
  }
  $bytes = New-Object byte[] ($Hex.Length / 2)
  for ($i = 0; $i -lt $Hex.Length; $i += 2) {
    $bytes[$i / 2] = [Convert]::ToByte($Hex.Substring($i, 2), 16)
  }
  return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Escape-Html {
  param([string]$Text)
  if ($null -eq $Text) { return "" }
  return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Convert-Inline {
  param(
    [string]$Text,
    [hashtable]$PageMap
  )

  $out = Escape-Html $Text

  $out = [regex]::Replace($out, "\[\[([^:\]]+):((?:https?|ftp)://[^\]]+)\]\]", {
    param($m)
    $label = $m.Groups[1].Value
    $url = $m.Groups[2].Value
    return "<a href=""$url"">$label</a>"
  })

  $out = [regex]::Replace($out, "\[\[([^>\]]+)>((?:https?|ftp)://[^\]]+)\]\]", {
    param($m)
    $label = $m.Groups[1].Value
    $url = $m.Groups[2].Value
    return "<a href=""$url"">$label</a>"
  })

  $out = [regex]::Replace($out, "\[\[([^>\]]+)>([^\]]+)\]\]", {
    param($m)
    $label = $m.Groups[1].Value
    $target = $m.Groups[2].Value
    if ($PageMap.ContainsKey($target)) {
      return "<a href=""$($PageMap[$target])"">$label</a>"
    }
    return $label
  })

  $out = [regex]::Replace($out, "\[\[([^\]]+)\]\]", {
    param($m)
    $target = $m.Groups[1].Value
    if ($PageMap.ContainsKey($target)) {
      return "<a href=""$($PageMap[$target])"">$target</a>"
    }
    return $target
  })

  $out = [regex]::Replace($out, "''(.*?)''", '<strong>$1</strong>')
  $out = [regex]::Replace($out, '(?<!["''<>])(https?://[^\s<]+)', '<a href="$1">$1</a>')

  return $out
}

function Render-Body {
  param(
    [string[]]$Lines,
    [hashtable]$PageMap
  )

  $sb = New-Object System.Text.StringBuilder
  $inUl = $false
  $inOl = $false

  function Close-Lists {
    param([ref]$Sb, [ref]$InUl, [ref]$InOl)
    if ($InUl.Value) {
      [void]$Sb.Value.AppendLine("</ul>")
      $InUl.Value = $false
    }
    if ($InOl.Value) {
      [void]$Sb.Value.AppendLine("</ol>")
      $InOl.Value = $false
    }
  }

  foreach ($lineRaw in $Lines) {
    $line = $lineRaw.TrimEnd("`r")

    if ($line -match "^#nicovideo\(([^)]+)\)") {
      Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
      $id = $matches[1]
      [void]$sb.AppendLine("<p><a href=""https://www.nicovideo.jp/watch/$id"">Niconico: $id</a></p>")
      continue
    }

    if ($line -match "^#youtube\(([^)]+)\)") {
      Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
      $id = $matches[1]
      [void]$sb.AppendLine("<div class=""video""><iframe src=""https://www.youtube.com/embed/$id"" title=""YouTube $id"" loading=""lazy"" allowfullscreen></iframe></div>")
      continue
    }

    if ($line -match "^#contents" -or $line -match "^#norelated" -or $line -match "^#nofollow") {
      continue
    }

    if ($line -eq "") {
      Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
      [void]$sb.AppendLine("")
      continue
    }

    if ($line -match "^(\*{1,3})\s*(.+)$") {
      Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
      $lv = $matches[1].Length
      $text = $matches[2] -replace "\s*\[#[-A-Za-z0-9_]+\]\s*$", ""
      $text = Convert-Inline $text $PageMap
      [void]$sb.AppendLine("<h$lv>$text</h$lv>")
      continue
    }

    if ($line -match "^-(.+)$") {
      if (-not $inUl) {
        Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
        [void]$sb.AppendLine("<ul>")
        $inUl = $true
      }
      $text = Convert-Inline ($matches[1].Trim()) $PageMap
      [void]$sb.AppendLine("<li>$text</li>")
      continue
    }

    if ($line -match "^\+(.+)$") {
      if (-not $inOl) {
        Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
        [void]$sb.AppendLine("<ol>")
        $inOl = $true
      }
      $text = Convert-Inline ($matches[1].Trim()) $PageMap
      [void]$sb.AppendLine("<li>$text</li>")
      continue
    }

    Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
    $text2 = Convert-Inline ($line -replace "~\s*$", "") $PageMap
    [void]$sb.AppendLine("<p>$text2</p>")
  }

  Close-Lists ([ref]$sb) ([ref]$inUl) ([ref]$inOl)
  return $sb.ToString()
}

$sourceWiki = Join-Path $SourceRoot "wiki"
if (-not (Test-Path $sourceWiki)) {
  throw "wiki directory not found: $sourceWiki"
}

if (Test-Path $OutputDir) {
  Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$pageDir = Join-Path $OutputDir "pages"
New-Item -ItemType Directory -Force -Path $pageDir | Out-Null

$assetDirs = @("attach", "image", "photo", "mp3")
foreach ($d in $assetDirs) {
  $src = Join-Path $SourceRoot $d
  if (Test-Path $src) {
    Copy-Item -Recurse -Force -Path $src -Destination (Join-Path $OutputDir $d)
  }
}

$pages = @()
$pageMap = @{}
$excludedPagePatterns = @(
  "^:config(?:/|$)",
  "^:RenameLog$",
  "^BracketName$",
  "^FormattingRules$",
  "^Help$",
  "^PukiWiki(?:/|$)",
  "^InterWiki$",
  "^InterWikiName$",
  "^InterWikiSandBox$",
  "^RecentChanges$",
  "^RecentDeleted$",
  "^WikiEngines$",
  "^WikiName$",
  "^WikiWikiWeb$",
  "^PHP$",
  "^SandBox$",
  "^2chdat$"
)

Get-ChildItem -Path $sourceWiki -File -Filter "*.txt" | ForEach-Object {
  $base = $_.BaseName
  $title = Decode-HexPageName $base
  $excluded = $false
  foreach ($pattern in $excludedPagePatterns) {
    if ($title -match $pattern) {
      $excluded = $true
      break
    }
  }
  if ($excluded) {
    return
  }
  $slug = ($base.ToLowerInvariant()) + ".html"
  $rel = "pages/" + $slug
  $pageMap[$title] = $rel
  $pages += [PSCustomObject]@{
    Base = $base
    Title = $title
    SourcePath = $_.FullName
    RelPath = $rel
    OutPath = Join-Path $pageDir $slug
  }
}

$pages = $pages | Sort-Object Title

$templateHeader = @'
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>__TITLE__</title>
  <link rel="stylesheet" href="__CSS__" />
</head>
<body>
  <header class="site-header">
    <div class="wrap">
      <h1><a href="__HOME__">sowaka archive</a></h1>
      <p>Static archive converted from legacy PukiWiki</p>
    </div>
  </header>
  <main class="wrap">
'@

$templateFooter = @'
  </main>
</body>
</html>
'@

foreach ($p in $pages) {
  $lines = [System.IO.File]::ReadAllLines($p.SourcePath, [System.Text.Encoding]::UTF8)
  $body = Render-Body $lines $pageMap
  $content = "<article>`n<h2>$([System.Net.WebUtility]::HtmlEncode($p.Title))</h2>`n$body`n</article>"

  $html = $templateHeader.Replace("__TITLE__", [System.Net.WebUtility]::HtmlEncode($p.Title + " | sowaka archive")).Replace("__CSS__", "../styles.css").Replace("__HOME__", "../index.html") +
    $content +
    $templateFooter

  [System.IO.File]::WriteAllText($p.OutPath, $html, [System.Text.Encoding]::UTF8)
}

$items = $pages | ForEach-Object {
  "<li><a href=""$($_.RelPath)"">$([System.Net.WebUtility]::HtmlEncode($_.Title))</a></li>"
}
$listItems = ($items -join "`n")

[array]$landing = $pages | Where-Object { $_.RelPath -eq $LandingPageRelPath } | Select-Object -First 1

if ($landing.Count -eq 1) {
  $landingLines = [System.IO.File]::ReadAllLines($landing[0].SourcePath, [System.Text.Encoding]::UTF8)
  $landingBodyHtml = Render-Body $landingLines $pageMap
  $indexBody = @"
<article>
  <h2>$([System.Net.WebUtility]::HtmlEncode($landing[0].Title))</h2>
  $landingBodyHtml
</article>
<section>
  <h2>Pages</h2>
  <p>Total: $($pages.Count) pages</p>
  <ul class="page-list">
$listItems
  </ul>
</section>
"@
  $indexTitle = "$($landing[0].Title) | sowaka archive"
} else {
  $indexBody = @"
<section>
  <h2>Pages</h2>
  <p>Total: $($pages.Count) pages</p>
  <ul class="page-list">
$listItems
  </ul>
</section>
"@
  $indexTitle = "sowaka archive"
}

$indexHtml = $templateHeader.Replace("__TITLE__", [System.Net.WebUtility]::HtmlEncode($indexTitle)).Replace("__CSS__", "styles.css").Replace("__HOME__", "index.html") + $indexBody + $templateFooter
[System.IO.File]::WriteAllText((Join-Path $OutputDir "index.html"), $indexHtml, [System.Text.Encoding]::UTF8)

$styles = @'
:root {
  --bg: #faf7f2;
  --panel: #ffffff;
  --ink: #1e1f22;
  --sub: #59606b;
  --line: #d8d6d1;
  --link: #005ecb;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: "Yu Gothic", "Hiragino Kaku Gothic ProN", sans-serif;
  color: var(--ink);
  background: radial-gradient(circle at 20% 0%, #fff 0%, var(--bg) 45%, #efe8dd 100%);
  line-height: 1.7;
}
.wrap { max-width: 980px; margin: 0 auto; padding: 0 16px; }
.site-header {
  border-bottom: 1px solid var(--line);
  background: rgba(255,255,255,.8);
  backdrop-filter: blur(4px);
  position: sticky;
  top: 0;
}
.site-header h1 { margin: 0; padding-top: 10px; font-size: 1.2rem; }
.site-header p { margin: 0; padding: 0 0 10px; color: var(--sub); font-size: .9rem; }
.site-header a { text-decoration: none; color: inherit; }
main { padding-top: 22px; padding-bottom: 40px; }
article, section {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 20px;
}
h2, h3 { line-height: 1.3; }
a { color: var(--link); }
ul.page-list {
  columns: 2;
  column-gap: 24px;
}
ul.page-list li { break-inside: avoid; margin-bottom: 4px; }
.video { position: relative; padding-top: 56.25%; margin: 12px 0; }
.video iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
@media (max-width: 900px) {
  ul.page-list { columns: 1; }
}
'@
[System.IO.File]::WriteAllText((Join-Path $OutputDir "styles.css"), $styles, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $OutputDir ".nojekyll"), "", [System.Text.Encoding]::UTF8)

$meta = $pages | Select-Object Title, Base, RelPath
$metaJson = $meta | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText((Join-Path $OutputDir "pages.json"), $metaJson, [System.Text.Encoding]::UTF8)

Write-Host "Generated $($pages.Count) pages into $OutputDir"
