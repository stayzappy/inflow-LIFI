# deploy.ps1

git init
git add .
git commit -m "🚀 Initial commit: inFlow Base Hackathon Build"
git branch -M main
gh repo create inflow --public --source=. --remote=origin --push

Write-Host "✅ Boom! Code is live on GitHub." -ForegroundColor Green