param(
    [string]$Config = "config\customer-a.json"
)
# 出问题时一键收现场：环境快照 + 配置（脱敏）+ 依赖清单 + 最近日志，打成一个包发回来。
$root = Split-Path -Parent $PSScriptRoot
$cfgPath = if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $root $Config }
$cfg = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$work = Join-Path $root "diagnose-$stamp"
New-Item -ItemType Directory -Path $work -Force | Out-Null

Write-Host "== 收集现场 ==" -ForegroundColor Cyan

# 1) 环境快照
$envScript = Join-Path $root "..\envcheck\envcheck.py"
if (Test-Path $envScript) {
    & $cfg.python $envScript --json-only | Out-Null
    $latest = Get-ChildItem (Join-Path $root "..\envcheck\reports") -Filter "体检-*.json" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { Copy-Item $latest.FullName (Join-Path $work "环境快照.json") }
    Write-Host "  环境快照 ✓"
}

# 2) 配置脱敏（密钥只留前 4 位）
$safe = $cfg.PSObject.Copy()
if ($safe.apiKey) { $safe.apiKey = $safe.apiKey.Substring(0, [Math]::Min(4, $safe.apiKey.Length)) + "****" }
$safe | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $work "配置-脱敏.json") -Encoding utf8
Write-Host "  配置（脱敏）✓"

# 3) 依赖清单
& $cfg.python -m pip freeze 2>$null | Set-Content (Join-Path $work "pip-freeze.txt") -Encoding utf8
Write-Host "  pip freeze ✓"

# 4) 最近日志（最后 300 行）
$logDir = Join-Path $root $cfg.logDir
if (Test-Path $logDir) {
    $log = Get-ChildItem $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        Get-Content $log.FullName -Tail 300 | Set-Content (Join-Path $work "最近日志.txt") -Encoding utf8
        Write-Host "  日志（$($log.Name)）✓"
    }
}

# 5) 服务是不是活着
$alive = $false
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$($cfg.port)/health" -TimeoutSec 5 -UseBasicParsing
    $alive = ($r.StatusCode -eq 200)
    $r.Content | Set-Content (Join-Path $work "health.json") -Encoding utf8
} catch { }
"服务存活：$alive" | Set-Content (Join-Path $work "服务状态.txt") -Encoding utf8
Write-Host "  服务状态：$(if ($alive) { '活着' } else { '没响应' })"

$zip = Join-Path $root "排障包-$stamp.zip"
Compress-Archive -Path (Join-Path $work "*") -DestinationPath $zip -Force
Remove-Item $work -Recurse -Force
Write-Host ""
Write-Host "排障包：$zip" -ForegroundColor Green
Write-Host "把这个 zip 发回给我即可，里面不含完整密钥。"
