# PowerShell script to write .gitconfig file by rendering a Jinja template
# Assuming wsl_environment = true for rendering

# Define the content based on the Jinja template with wsl_environment = true
$content = @"
[credential]
  helper = manager
  useHttpPath = true
[user]
  name = $env:GIT_USER
  email = $env:GIT_EMAIL
[merge]
  tool = vimdiff
[alias]
  b = branch --sort=-committerdate --column
  br = branch --sort=-committerdate --column -r
  aa = add .
  ci = commit
  co = checkout
  slog = log --pretty=format:'%C(white)[%C(yellow)%h%C(white)] %C(blue)(%ad) %C(white)%s %C(green)%an' --date=local
  glog = log --graph --pretty=oneline --abbrev-commit
  st = status -s
  blame = blame -w
  wtf = blame -w
  staged = diff --cached
  pr = pull-request
  amend = commit -a --amend
[core]
  excludesfile = ~/.gitignore
  preloadindex = true
  editor = vim
  mergeoptions = --no-edit
  pager = cat
[push]
  default = upstream
[pull]
  rebase = false
"@

# Write the content to .gitconfig file
Set-Content -Path 'C:\Users\david\.gitconfig' -Value $content

Write-Output "Git configuration has been written to C:\Users\david\.gitconfig"
