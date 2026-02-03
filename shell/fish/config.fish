if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Initialize starship prompt
starship init fish | source

# Path additions
set -gx PATH $PATH $HOME/.local/bin
set -gx PATH $PATH $HOME/.cargo/bin
set -gx PATH $PATH $HOME/.lmstudio/bin

# NVM for fish (via nvm.fish plugin)
# Handled by fisher plugin: jorgebucaran/nvm.fish

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline -10'
alias gd='git diff'
