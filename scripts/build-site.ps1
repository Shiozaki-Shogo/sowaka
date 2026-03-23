param(
  [string]$SourceRoot = "..",
  [string]$OutputDir = "docs",
  [string]$LandingPageBaseName = "E382BDE383AFE382ABE381A1E38283E38293E7968FE98894"
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

function Escape-YamlSingleQuoted {
  param([string]$Text)
  if ($null -eq $Text) { return "" }
  return ($Text -replace "'", "''")
}

function To-AsciiSlug {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $norm = $Text.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
  $norm = $norm -replace "&", " and "
  $norm = $norm -replace "[^a-z0-9._/\-\s+]", "-"
  $norm = $norm -replace "[\s/+:]+", "-"
  $norm = $norm -replace "-{2,}", "-"
  $norm = $norm.Trim("-","_",".")
  return $norm
}

function Resolve-LocalAssetOrUrl {
  param([string]$Source)
  $src = $Source.Trim()
  if ($src -eq "") { return "" }

  if ($src -match "^(https?://sowaka\.s-dog\.net)/(photo|image|attach|character)/(.+)$") {
    $path = "$($matches[2])/$($matches[3])"
    return "{{ '/$path' | relative_url }}"
  }
  if ($src -match "^(photo|image|attach|character)/(.+)$") {
    return "{{ '/$src' | relative_url }}"
  }
  if ($src -match "^https?://") { return $src }
  return $src
}

function Render-RefTag {
  param([string]$ArgsRaw)

  $args = $ArgsRaw.Trim() -replace "\)$", ""
  if ($args -eq "") { return "" }
  $parts = $args -split ","
  if ($parts.Count -eq 0) { return "" }

  $srcRaw = $parts[0].Trim()
  $src = Resolve-LocalAssetOrUrl -Source $srcRaw
  if ($src -eq "") { return "" }

  $nolink = $false
  $title = ""
  if ($parts.Count -ge 2) {
    foreach ($p in $parts[1..($parts.Count - 1)]) {
      $v = $p.Trim()
      if ($v -eq "") { continue }
      if ($v -ieq "nolink") {
        $nolink = $true
        continue
      }
      if ($title -eq "") { $title = $v }
    }
  }
  if ($title -eq "") { $title = [System.IO.Path]::GetFileName($srcRaw) }

  $alt = Escape-Html $title
  $srcEsc = if ($src -like "{{*") { $src } else { Escape-Html $src }
  $img = "<img src=""$srcEsc"" alt=""$alt"" loading=""lazy"" />"
  if ($nolink) { return $img }
  return "<a href=""$srcEsc"">$img</a>"
}

function Render-PhotoTag {
  param([string]$ArgsRaw)
  $args = $ArgsRaw.Trim()
  if ($args -eq "") { return "" }
  $parts = $args -split ","
  if ($parts.Count -eq 0) { return "" }
  $name = $parts[0].Trim()
  if ($name -eq "") { return "" }

  $src = Resolve-LocalAssetOrUrl -Source ("photo/" + $name)
  $title = ""
  if ($parts.Count -ge 2) {
    foreach ($p in $parts[1..($parts.Count - 1)]) {
      $v = $p.Trim()
      if ($v -eq "") { continue }
      if ($title -eq "") { $title = $v }
    }
  }
  if ($title -eq "") { $title = $name }

  $alt = Escape-Html $title
  $srcEsc = if ($src -like "{{*") { $src } else { Escape-Html $src }
  return "<a href=""$srcEsc""><img src=""$srcEsc"" alt=""$alt"" loading=""lazy"" /></a>"
}

function Convert-Inline {
  param(
    [string]$Text,
    [hashtable]$PageMap,
    [hashtable]$LegacyLinkMap
  )

  $out = Escape-Html $Text

  $out = [regex]::Replace($out, "\[\[([^:\]]+):((?:https?|ftp)://[^\]]+)\]\]", {
    param($m)
    $label = $m.Groups[1].Value
    $url = $m.Groups[2].Value
    return "[$label]($url)"
  })

  $out = [regex]::Replace($out, "\[\[([^>\]]+)>((?:https?|ftp)://[^\]]+)\]\]", {
    param($m)
    $label = $m.Groups[1].Value
    $url = $m.Groups[2].Value
    return "[$label]($url)"
  })

  $out = [regex]::Replace($out, "\[\[([^>\]]+)>([^\]]+)\]\]", {
    param($m)
    $label = $m.Groups[1].Value
    $target = $m.Groups[2].Value
    if ($PageMap.ContainsKey($target)) {
      return "[$label]($($PageMap[$target]))"
    }
    return $label
  })

  $out = [regex]::Replace($out, "\[\[([^\]]+)\]\]", {
    param($m)
    $target = $m.Groups[1].Value
    if ($PageMap.ContainsKey($target)) {
      return "[$target]($($PageMap[$target]))"
    }
    return $target
  })

  $out = [regex]::Replace($out, "&amp;ref\((.+?)\);", {
    param($m)
    return Render-RefTag -ArgsRaw $m.Groups[1].Value
  })

  $out = [regex]::Replace($out, "&amp;photo\((.+?)\);", {
    param($m)
    return Render-PhotoTag -ArgsRaw $m.Groups[1].Value
  })

  $out = [regex]::Replace($out, "#htmlinsert\(flash,([^)]+)\)", {
    param($m)
    $arg = $m.Groups[1].Value
    if ($arg -match "swf=([^,\s]+)") {
      $swf = $matches[1]
      $src = Resolve-LocalAssetOrUrl -Source $swf
      $srcEsc = if ($src -like "{{*") { $src } else { Escape-Html $src }
      return "<a href=""$srcEsc"">flash: $srcEsc</a>"
    }
    return ""
  })

  $out = [regex]::Replace($out, "''(.*?)''", '**$1**')
  $out = [regex]::Replace($out, "&#39;&#39;(.*?)&#39;&#39;", '**$1**')
  $out = [regex]::Replace($out, "&amp;br;", "<br />")

  $out = [regex]::Replace($out, "&amp;color\(([^)]+)\)\{(.*?)\};", {
    param($m)
    $arg = $m.Groups[1].Value
    $txt = $m.Groups[2].Value
    $parts = $arg -split ","
    $fg = $parts[0].Trim()
    $style = "color:$fg;"
    if ($parts.Count -ge 2) {
      $bg = $parts[1].Trim()
      if ($bg -ne "") { $style += "background-color:$bg;" }
    }
    return "<span style=""$style"">$txt</span>"
  })

  $out = [regex]::Replace($out, "&amp;size\(([^)]+)\)\{(.*?)\};", {
    param($m)
    $sz = $m.Groups[1].Value.Trim()
    if ($sz -match "^\d+$") { $sz = "$sz" + "px" }
    return "<span style=""font-size:$sz;"">$($m.Groups[2].Value)</span>"
  })

  $out = [regex]::Replace($out, 'https?://sowaka\.s-dog\.net/([A-Za-z0-9._\-]+\.html)', {
    param($m)
    $key = $m.Groups[1].Value.ToLowerInvariant()
    if ($LegacyLinkMap.ContainsKey($key)) {
      return $LegacyLinkMap[$key]
    }
    return $m.Value
  })

  $out = [regex]::Replace($out, 'href="https?://sowaka\.s-dog\.net/"', 'href="{{ ''/'' | relative_url }}"')
  return $out
}

function Normalize-LiquidQuoteEntities {
  param([string]$Html)
  return [regex]::Replace($Html, '\{\{[^}]+\}\}', {
    param($m)
    return ($m.Value -replace "&#39;", "'")
  })
}

function Rewrite-LegacySiteLinks {
  param(
    [string]$Html,
    [hashtable]$LegacyLinkMap
  )
  $text = $Html
  $text = [regex]::Replace($text, 'https?://sowaka\.s-dog\.net/([A-Za-z0-9._\-]+\.html)', {
    param($m)
    $key = $m.Groups[1].Value.ToLowerInvariant()
    if ($LegacyLinkMap.ContainsKey($key)) { return $LegacyLinkMap[$key] }
    return $m.Value
  })
  $text = [regex]::Replace($text, '\(https?://sowaka\.s-dog\.net/(photo|image|attach|character)/([^)]+)\)', {
    param($m)
    $dir = $m.Groups[1].Value
    $name = $m.Groups[2].Value
    return "({{ '/$dir/$name' | relative_url }})"
  })
  $text = [regex]::Replace($text, '\(https?://sowaka\.s-dog\.net/\)', "({{ '/' | relative_url }})")
  $text = [regex]::Replace($text, 'href="https?://sowaka\.s-dog\.net/"', 'href="{{ ''/'' | relative_url }}"')
  $text = [regex]::Replace($text, 'https?://sowaka\.s-dog\.net/', "{{ '/' | relative_url }}")
  return $text
}

function Render-Body {
  param(
    [string[]]$Lines,
    [hashtable]$PageMap,
    [hashtable]$LegacyLinkMap
  )

  $sb = New-Object System.Text.StringBuilder
  $inUl = $false
  $inOl = $false
  $inTable = $false
  $inQuote = $false

  function Close-Blocks {
    param([ref]$Sb, [ref]$InUl, [ref]$InOl, [ref]$InTable)
    if ($InUl.Value) { [void]$Sb.Value.AppendLine("</ul>"); $InUl.Value = $false }
    if ($InOl.Value) { [void]$Sb.Value.AppendLine("</ol>"); $InOl.Value = $false }
    if ($InTable.Value) { [void]$Sb.Value.AppendLine("</table>"); $InTable.Value = $false }
  }

  foreach ($lineRaw in $Lines) {
    $line = $lineRaw.TrimEnd("`r")
    $trimmed = $line.Trim()

    if ($trimmed -eq ">") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      if (-not $inQuote) { [void]$sb.AppendLine("<blockquote>"); $inQuote = $true }
      continue
    }
    if ($trimmed -match "^>(.+)$") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $qText = Convert-Inline -Text $matches[1].Trim() -PageMap $PageMap -LegacyLinkMap $LegacyLinkMap
      [void]$sb.AppendLine("> $qText")
      continue
    }
    if ($trimmed -eq "<") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      if ($inQuote) { [void]$sb.AppendLine("</blockquote>"); $inQuote = $false }
      continue
    }

    if ($line -match "^#nicovideo\(([^)]+)\)") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $id = ($matches[1] -split ",")[0].Trim()
      [void]$sb.AppendLine("[Niconico: $id](https://www.nicovideo.jp/watch/$id)")
      continue
    }
    if ($line -match "^#youtube\(([^)]+)\)") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $id = ($matches[1] -split ",")[0].Trim()
      [void]$sb.AppendLine("<div class=""video""><iframe src=""https://www.youtube.com/embed/$id"" title=""YouTube $id"" loading=""lazy"" allowfullscreen></iframe></div>")
      continue
    }
    if ($line -match "^#iframe\((.+)\)\s*$") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $parts = $matches[1] -split ","
      $url = $parts[0].Trim()
      if ($url -match "^https?://") { [void]$sb.AppendLine("[$url]($url)") }
      continue
    }

    if ($line -match "^#(analog|counter|comment(?:_kcaptcha)?|search2chdat|search|recent|calendar|navi|ls2?|p?comment|article|tracker|dat2ch)\b") { continue }
    if ($line -match "^#contents" -or $line -match "^#norelated" -or $line -match "^#nofollow") { continue }

    if ($line -match "^#ref\((.+)\)\s*$") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $refHtml = Render-RefTag -ArgsRaw $matches[1]
      if ($refHtml -ne "") { [void]$sb.AppendLine($refHtml) }
      continue
    }

    if ($line -eq "") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      [void]$sb.AppendLine("")
      continue
    }

    if ($trimmed -match "^\|.*\|$") {
      if (-not $inTable) {
        Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
        [void]$sb.AppendLine("<table class=""wiki-table"">")
        $inTable = $true
      }
      $rawCells = $trimmed.Substring(1, $trimmed.Length - 2).Split("|")
      [void]$sb.AppendLine("<tr>")
      foreach ($c in $rawCells) {
        $cellRaw = $c.Trim()
        if ($cellRaw -eq "") { [void]$sb.AppendLine("<td></td>"); continue }
        $tag = "td"
        if ($cellRaw.StartsWith("~")) { $tag = "th"; $cellRaw = $cellRaw.Substring(1) }
        if ($cellRaw -match "^(LEFT|CENTER|RIGHT):") { $cellRaw = $cellRaw -replace "^(LEFT|CENTER|RIGHT):", "" }
        $cell = Convert-Inline -Text $cellRaw -PageMap $PageMap -LegacyLinkMap $LegacyLinkMap
        [void]$sb.AppendLine("<$tag>$cell</$tag>")
      }
      [void]$sb.AppendLine("</tr>")
      continue
    }

    if ($line -match "^(\*{1,3})\s*(.+)$") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $lv = $matches[1].Length
      $text = $matches[2] -replace "\s*\[#[-A-Za-z0-9_]+\]\s*$", ""
      $text = Convert-Inline -Text $text -PageMap $PageMap -LegacyLinkMap $LegacyLinkMap
      $hashes = "#" * $lv
      [void]$sb.AppendLine("$hashes $text")
      continue
    }

    if ($line -match "^-(.+)$") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $text = Convert-Inline -Text ($matches[1].Trim()) -PageMap $PageMap -LegacyLinkMap $LegacyLinkMap
      [void]$sb.AppendLine("- $text")
      continue
    }

    if ($line -match "^\+(.+)$") {
      Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
      $text = Convert-Inline -Text ($matches[1].Trim()) -PageMap $PageMap -LegacyLinkMap $LegacyLinkMap
      [void]$sb.AppendLine("1. $text")
      continue
    }

    Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
    $text2 = Convert-Inline -Text ($line -replace "~\s*$", "") -PageMap $PageMap -LegacyLinkMap $LegacyLinkMap
    [void]$sb.AppendLine($text2)
  }

  Close-Blocks ([ref]$sb) ([ref]$inUl) ([ref]$inOl) ([ref]$inTable)
  if ($inQuote) { [void]$sb.AppendLine("</blockquote>"); $inQuote = $false }
  return $sb.ToString()
}

function Load-RewriteMapAliases {
  param([string]$SourceRootDir)
  $map = @{}
  $rewriteHexFile = Join-Path $SourceRootDir "wiki\3A636F6E6669672F526577726974654D6170.txt"
  if (-not (Test-Path $rewriteHexFile)) { return $map }
  $lines = [System.IO.File]::ReadAllLines($rewriteHexFile, [System.Text.Encoding]::UTF8)
  foreach ($line in $lines) {
    if ($line -match "^\|([^|]+)\|([^|]+)\|\s*$") {
      $alias = $matches[1].Trim()
      $page = $matches[2].Trim()
      if ($alias -ne "" -and $page -ne "") { $map[$page] = $alias }
    }
  }
  return $map
}

$sourceWiki = Join-Path $SourceRoot "wiki"
if (-not (Test-Path $sourceWiki)) { throw "wiki directory not found: $sourceWiki" }

if (Test-Path $OutputDir) { Remove-Item -Recurse -Force $OutputDir }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$pageDir = Join-Path $OutputDir "pages"
New-Item -ItemType Directory -Force -Path $pageDir | Out-Null
$layoutDir = Join-Path $OutputDir "_layouts"
New-Item -ItemType Directory -Force -Path $layoutDir | Out-Null

$assetDirs = @("attach", "image", "photo", "mp3", "character")
foreach ($d in $assetDirs) {
  $src = Join-Path $SourceRoot $d
  if (Test-Path $src) { Copy-Item -Recurse -Force -Path $src -Destination (Join-Path $OutputDir $d) }
}

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

$aliasByPage = Load-RewriteMapAliases -SourceRootDir $SourceRoot
$pages = @()
$usedSlugs = @{}
$slugOverridesByBase = @{
  "E382BDE383AFE382ABE381A1E38283E38293E7968FE98894" = "sowaka-shosho"
}

Get-ChildItem -Path $sourceWiki -File -Filter "*.txt" | ForEach-Object {
  $base = $_.BaseName
  $title = Decode-HexPageName $base

  $excluded = $false
  foreach ($pattern in $excludedPagePatterns) {
    if ($title -match $pattern) { $excluded = $true; break }
  }
  if ($excluded) { return }

  $slug = ""
  if ($slugOverridesByBase.ContainsKey($base.ToUpperInvariant())) {
    $slug = To-AsciiSlug $slugOverridesByBase[$base.ToUpperInvariant()]
  }
  if ([string]::IsNullOrWhiteSpace($slug) -and $aliasByPage.ContainsKey($title)) {
    $slug = To-AsciiSlug $aliasByPage[$title]
  }
  if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = To-AsciiSlug $title
  }
  if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = "page-" + $base.ToLowerInvariant()
  }

  $originalSlug = $slug
  $n = 2
  while ($usedSlugs.ContainsKey($slug)) {
    $slug = "$originalSlug-$n"
    $n++
  }
  $usedSlugs[$slug] = $true

  $relMd = "pages/$slug.md"
  $pages += [PSCustomObject]@{
    Base = $base
    Title = $title
    Slug = $slug
    SourcePath = $_.FullName
    RelMdPath = $relMd
    OutPath = Join-Path $pageDir ($slug + ".md")
  }
}

$pages = $pages | Sort-Object Title
$landing = $pages | Where-Object { $_.Base.ToUpperInvariant() -eq $LandingPageBaseName.ToUpperInvariant() } | Select-Object -First 1
$contentPages = $pages
if ($null -ne $landing) {
  $contentPages = $pages | Where-Object { $_.Base.ToUpperInvariant() -ne $LandingPageBaseName.ToUpperInvariant() }
}

$pageMap = @{}
foreach ($p in $pages) {
  if ($null -ne $landing -and $p.Base.ToUpperInvariant() -eq $LandingPageBaseName.ToUpperInvariant()) {
    $pageMap[$p.Title] = "{{ '/' | relative_url }}"
  } else {
    $pageMap[$p.Title] = "{{ '/pages/$($p.Slug).html' | relative_url }}"
  }
}

$legacyLinkMap = @{}
foreach ($p in $pages) {
  if ($null -ne $landing -and $p.Base.ToUpperInvariant() -eq $LandingPageBaseName.ToUpperInvariant()) {
    $legacyLinkMap[("$($p.Slug).html").ToLowerInvariant()] = "{{ '/' | relative_url }}"
  } else {
    $legacyLinkMap[("$($p.Slug).html").ToLowerInvariant()] = "{{ '/pages/$($p.Slug).html' | relative_url }}"
  }
}
foreach ($kv in $aliasByPage.GetEnumerator()) {
  $title = [string]$kv.Key
  $alias = [string]$kv.Value
  if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($alias)) { continue }
  $target = $pages | Where-Object { $_.Title -eq $title } | Select-Object -First 1
  if ($null -ne $target) {
    $legacyLinkMap[($alias.ToLowerInvariant() + ".html")] = "{{ '/pages/$($target.Slug).html' | relative_url }}"
  }
}

foreach ($p in $contentPages) {
  $lines = [System.IO.File]::ReadAllLines($p.SourcePath, [System.Text.Encoding]::UTF8)
  $body = Render-Body -Lines $lines -PageMap $pageMap -LegacyLinkMap $legacyLinkMap
  $body = Rewrite-LegacySiteLinks -Html $body -LegacyLinkMap $legacyLinkMap
  $body = Normalize-LiquidQuoteEntities -Html $body
  $yamlTitle = Escape-YamlSingleQuoted $p.Title
  $md = @"
---
layout: default
title: '$yamlTitle'
---

## $($p.Title)

$body
"@
  [System.IO.File]::WriteAllText($p.OutPath, $md, [System.Text.Encoding]::UTF8)
}

$listItems = ($contentPages | ForEach-Object {
  "- [$($_.Title)]($($pageMap[$_.Title]))"
}) -join "`n"

if ($null -ne $landing) {
  $landingLines = [System.IO.File]::ReadAllLines($landing.SourcePath, [System.Text.Encoding]::UTF8)
  $landingBody = Render-Body -Lines $landingLines -PageMap $pageMap -LegacyLinkMap $legacyLinkMap
  $landingBody = Rewrite-LegacySiteLinks -Html $landingBody -LegacyLinkMap $legacyLinkMap
  $landingBody = Normalize-LiquidQuoteEntities -Html $landingBody
  $landingTitleYaml = Escape-YamlSingleQuoted $landing.Title
  $indexMd = @"
---
layout: default
title: '$landingTitleYaml'
---

## $($landing.Title)

$landingBody

## Pages

Total: $($contentPages.Count) pages

$listItems
"@
} else {
  $indexMd = @"
---
layout: default
title: 'sowaka archive'
---

## Pages

Total: $($contentPages.Count) pages

$listItems
"@
}
[System.IO.File]::WriteAllText((Join-Path $OutputDir "index.md"), $indexMd, [System.Text.Encoding]::UTF8)

$layout = @'
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{{ page.title }} | sowaka archive</title>
  <link rel="stylesheet" href="{{ '/styles.css' | relative_url }}" />
</head>
<body>
  <header class="site-header">
    <div class="wrap">
      <h1><a href="{{ '/' | relative_url }}">sowaka archive</a></h1>
      <p>Static archive converted from legacy PukiWiki</p>
    </div>
  </header>
  <main class="wrap">
    {{ content }}
  </main>
</body>
</html>
'@
[System.IO.File]::WriteAllText((Join-Path $layoutDir "default.html"), $layout, [System.Text.Encoding]::UTF8)

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
h2, h3 { line-height: 1.3; }
a { color: var(--link); }
ul.page-list { columns: 2; column-gap: 24px; }
ul.page-list li { break-inside: avoid; margin-bottom: 4px; }
.video { position: relative; padding-top: 56.25%; margin: 12px 0; }
.video iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
.wiki-table {
  width: 100%;
  border-collapse: collapse;
  margin: 12px 0;
}
.wiki-table th, .wiki-table td {
  border: 1px solid var(--line);
  padding: 6px 8px;
  vertical-align: top;
}
.wiki-table th { background: #f4f3f1; }
blockquote {
  margin: 12px 0;
  padding: 0 12px;
  border-left: 4px solid var(--line);
}
@media (max-width: 900px) {
  ul.page-list { columns: 1; }
}
'@
[System.IO.File]::WriteAllText((Join-Path $OutputDir "styles.css"), $styles, [System.Text.Encoding]::UTF8)

$meta = $contentPages | Select-Object Title, Base, Slug, RelMdPath
$metaJson = $meta | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText((Join-Path $OutputDir "pages.json"), $metaJson, [System.Text.Encoding]::UTF8)

Write-Host "Generated $($contentPages.Count) markdown pages into $OutputDir"
