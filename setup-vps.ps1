# Investment Castle EA - VPS bootstrap
# Run in PowerShell on the VPS. Installs tooling, clones the repo, installs Claude Code.
# The only interactive steps are GitHub login (once) and, afterwards, `claude` auth.
$ErrorActionPreference = "Stop"
$RepoSlug = "ahmedalaaldin/mt4"
$RepoDir  = "$env:USERPROFILE\mt4"

function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User")
}

Write-Host "== 1/5 Installing tooling (git, Node LTS, GitHub CLI) ==" -ForegroundColor Cyan
if (-not (Have git))  { winget install --id Git.Git          -e --silent --accept-package-agreements --accept-source-agreements }
if (-not (Have node)) { winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements }
if (-not (Have gh))   { winget install --id GitHub.cli        -e --silent --accept-package-agreements --accept-source-agreements }
Refresh-Path

Write-Host "== 2/5 GitHub authentication ==" -ForegroundColor Cyan
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Choose: GitHub.com -> HTTPS -> Yes -> Login with a web browser" -ForegroundColor Yellow
    gh auth login
}
gh auth setup-git

Write-Host "== 3/5 Cloning repo to $RepoDir ==" -ForegroundColor Cyan
if (Test-Path "$RepoDir\.git") { git -C $RepoDir pull } else { gh repo clone $RepoSlug $RepoDir }

Write-Host "== 4/5 Installing Claude Code ==" -ForegroundColor Cyan
npm install -g @anthropic-ai/claude-code

Write-Host "== 5/5 MT4 EA files ==" -ForegroundColor Cyan
Write-Host "Copy '$RepoDir\experts\*' into your MT4 '...\MQL4\Experts\' folder (path depends on the MT4 install)."

Write-Host ""
Write-Host "DONE. Next:" -ForegroundColor Green
Write-Host "  cd $RepoDir" -ForegroundColor Green
Write-Host "  claude        # then authenticate; CLAUDE.md loads the project context" -ForegroundColor Green
