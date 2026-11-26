param(
    [string]$Config = "config\customer-a.json"
)
# 部署前自检：装得成吗、跑得起来吗。全绿才进客户现场。
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$cfgPath = if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $root $Config }
$fail = 0

function Item($name, $ok, $detail) {
    $mark = if ($ok) { "[OK]  " } else { "[FAIL]" }
    Write-Host ("{0} {1,-14} {2}" -f $mark, $name, $detail)
    if (-not $ok) { $script:fail++ }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "== 交付前自检 ==" -ForegroundColor Cyan
Write-Host ("配置：{0}" -f $cfgPath)

if (-not (Test-Path $cfgPath)) {
    Item "配置文件" $false "找不到 $cfgPath"
    exit 1
}
$cfg = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json
Item "配置文件" $true ("端口 {0}，模型 {1}" -f $cfg.port, $cfg.model)

# 1) Python 与依赖
$py = $cfg.python
if (-not (Test-Path $py)) { $py = "python" }
$ver = & $py --version 2>&1
Item "Python" ($LASTEXITCODE -eq 0) $ver

if ($cfg.vendor -and (Test-Path (Join-Path $root $cfg.vendor))) {
    $env:PYTHONPATH = (Join-Path $root $cfg.vendor)
    Write-Host ("      依赖目录：{0}" -f $env:PYTHONPATH)
}
$mods = @("fastapi", "uvicorn")
foreach ($m in $mods) {
    & $py -c "import $m" 2>$null
    Item $m ($LASTEXITCODE -eq 0) $(if ($LASTEXITCODE -eq 0) { "已安装" } else { "缺依赖：pip install $m" })
}

# 2) 密钥（只报有没有，不打印内容）
$key = $cfg.apiKey
if (-not $key -and (Test-Path $cfg.apiKeyFile)) {
    $key = (Get-Content $cfg.apiKeyFile -Raw | ConvertFrom-Json).providers.openai.apiKey
}
Item "模型密钥" ([bool]$key) $(if ($key) { "已配置（长度 $($key.Length)）" } else { "缺密钥，检查 apiKeyFile" })

# 3) 端口
$busy = $false
try {
    $c = New-Object System.Net.Sockets.TcpClient
    $busy = $c.ConnectAsync("127.0.0.1", [int]$cfg.port).Wait(800)
    $c.Close()
} catch { $busy = $false }
Item "端口 $($cfg.port)" (-not $busy) $(if ($busy) { "被占用，部署前先释放或改配置" } else { "空闲" })

# 4) 索引文件
$idx = Join-Path $root $cfg.index
Item "知识库索引" (Test-Path $idx) $(if (Test-Path $idx) { "$([math]::Round((Get-Item $idx).Length/1KB,1)) KB" } else { "缺索引，先跑 ingest" })

# 5) 模型连通性（用 Python 探，避开 PowerShell 的 TLS 问题）
$ping = Join-Path $PSScriptRoot "ping_model.py"
$res = & $py $ping $cfg.apiBase $key 2>&1 | Select-Object -Last 1
if ($res -like "ok *") {
    $parts = $res -split " "
    Item "模型接口" $true ("{0} 通（{1} ms，{2} 个模型）" -f $cfg.apiBase, $parts[1], $parts[2])
} else {
    Item "模型接口" $false ("连不上：{0}" -f $res)
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "结论：全部通过，可以部署。" -ForegroundColor Green
    exit 0
} else {
    Write-Host ("结论：有 {0} 项没通过，按上面提示处理后再跑一次。" -f $fail) -ForegroundColor Red
    exit 1
}
