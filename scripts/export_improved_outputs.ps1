$projectRoot = Split-Path -Parent $PSScriptRoot
$exportDir = Join-Path $projectRoot "powerbi\data\improved"
$mysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"

New-Item -ItemType Directory -Force -Path $exportDir -ErrorAction Stop |
    Out-Null

$mysqlOptions = @(
    "-h", "127.0.0.1",
    "-P", "3306",
    "-u", "root",
    "-p",
    "--batch",
    "--raw",
    "--column-names",
    "--default-character-set=utf8mb4"
)

# Read the verified comparison query.
$comparisonPath = Join-Path $projectRoot "sql\08_funnel_definition_comparison.sql"
$comparisonSql = Get-Content -LiteralPath $comparisonPath -Raw -Encoding UTF8 -ErrorAction Stop

$comparisonText = & $mysqlExe @mysqlOptions "--execute=$comparisonSql"
if ($LASTEXITCODE -ne 0) {
    throw "Comparison query failed."
}

$comparisonRows = @($comparisonText | ConvertFrom-Csv -Delimiter "`t")
if ($comparisonRows.Count -ne 5) {
    throw "Expected 5 comparison rows."
}

# Convert MySQL NULL into an empty CSV value.
foreach ($row in $comparisonRows) {
    if ($row.delta_pp -eq "NULL") {
        $row.delta_pp = ""
    }
}

# Export one row per funnel stage.
$funnelSql = @'
SELECT 1 AS stage_order, 'view' AS stage, COUNT(*) AS user_count
FROM retailrocket.funnel_user_24h
UNION ALL
SELECT 2, 'addtocart', COUNT(cart_ts)
FROM retailrocket.funnel_user_24h
UNION ALL
SELECT 3, 'transaction', COUNT(buy_ts)
FROM retailrocket.funnel_user_24h
ORDER BY stage_order;
'@

$funnelText = & $mysqlExe @mysqlOptions "--execute=$funnelSql"
if ($LASTEXITCODE -ne 0) {
    throw "Funnel query failed."
}

$funnelRows = @($funnelText | ConvertFrom-Csv -Delimiter "`t")
if ($funnelRows.Count -ne 3) {
    throw "Expected 3 funnel rows."
}

$comparisonRows |
    Export-Csv -LiteralPath (Join-Path $exportDir "funnel_definition_comparison.csv") -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

$funnelRows |
    Export-Csv -LiteralPath (Join-Path $exportDir "ordered_funnel_24h.csv") -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

$comparisonRows | Format-Table -AutoSize | Out-Host
$funnelRows | Format-Table -AutoSize | Out-Host