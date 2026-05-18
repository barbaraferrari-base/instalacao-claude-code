#!/usr/bin/env bash
# Installs Claude Code CLI with all required dependencies on macOS.
# Detects Homebrew, installs Node.js LTS, Git, and Claude Code CLI globally via npm.
# Skips components already installed.

set -euo pipefail

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
step()  { printf "\n\033[36m==> %s\033[0m\n" "$*"; }
ok()    { printf "    \033[32m[OK]\033[0m %s\n" "$*"; }
skip()  { printf "    \033[33m[--]\033[0m %s (already installed)\n" "$*"; }
fail()  { printf "    \033[31m[!!]\033[0m %s\n" "$*"; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

get_version() {
    local cmd="$1"
    local arg="${2:---version}"
    "$cmd" "$arg" 2>/dev/null | head -1 || true
}

# ──────────────────────────────────────────────
# OS check
# ──────────────────────────────────────────────
step "Detecting operating system"
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
    fail "This script targets macOS. Detected: $OS"
fi
ok "macOS detected"

# ──────────────────────────────────────────────
# 1. Homebrew
# ──────────────────────────────────────────────
step "Checking Homebrew"
if command_exists brew; then
    skip "Homebrew $(brew --version | head -1)"
else
    printf "    Installing Homebrew...\n"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || \
        fail "Homebrew installation failed"

    # Add brew to PATH for Apple Silicon and Intel macs
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        # Persist for future shells
        PROFILE_FILE="$HOME/.zprofile"
        if ! grep -q 'homebrew/bin/brew shellenv' "$PROFILE_FILE" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$PROFILE_FILE"
        fi
    fi
    ok "Homebrew installed"
fi

# ──────────────────────────────────────────────
# 2. Node.js (LTS) + npm
# ──────────────────────────────────────────────
step "Checking Node.js"
if command_exists node; then
    skip "Node.js $(get_version node)"
else
    printf "    Installing Node.js LTS via Homebrew...\n"
    brew install node@lts 2>/dev/null || brew install node || \
        fail "Node.js installation failed"

    # Link in case brew installed a versioned formula
    brew link --overwrite node 2>/dev/null || brew link --overwrite node@lts 2>/dev/null || true
    ok "Node.js $(get_version node) installed"
fi

if command_exists npm; then
    ok "npm $(get_version npm)"
else
    fail "npm not found — it should ship with Node.js"
fi

# ──────────────────────────────────────────────
# 3. Git
# ──────────────────────────────────────────────
step "Checking Git"
if command_exists git; then
    skip "$(get_version git)"
else
    printf "    Installing Git via Homebrew...\n"
    brew install git || fail "Git installation failed"
    ok "Git $(get_version git) installed"
fi

# ──────────────────────────────────────────────
# 4. Claude Code CLI
# ──────────────────────────────────────────────
step "Checking Claude Code CLI"
if command_exists claude; then
    skip "claude $(get_version claude)"
else
    printf "    Installing Claude Code CLI globally via npm...\n"
    npm install -g @anthropic-ai/claude-code || fail "Claude Code CLI installation failed"
    ok "Claude Code CLI installed"
fi

# ──────────────────────────────────────────────
# 5. PATH validation
# ──────────────────────────────────────────────
step "Validating PATH"
NPM_BIN="$(npm config get prefix)/bin"
case ":$PATH:" in
    *":$NPM_BIN:"*) ok "npm global bin already in PATH" ;;
    *)
        printf "    Adding %s to PATH...\n" "$NPM_BIN"
        PROFILE_FILE="$HOME/.zprofile"
        if ! grep -qF "$NPM_BIN" "$PROFILE_FILE" 2>/dev/null; then
            echo "export PATH=\"$NPM_BIN:\$PATH\"" >> "$PROFILE_FILE"
        fi
        export PATH="$NPM_BIN:$PATH"
        ok "Added $NPM_BIN to PATH"
        ;;
esac

# ──────────────────────────────────────────────
# 6. Validation summary
# ──────────────────────────────────────────────
step "Validation"

ALL_OK=true
for item in "node:Node.js" "npm:npm" "git:Git" "claude:Claude"; do
    cmd="${item%%:*}"
    label="${item##*:}"
    v="$(get_version "$cmd" 2>/dev/null || true)"
    if [[ -n "$v" ]]; then
        ok "$label: $v"
    else
        printf "    \033[31m[!!]\033[0m %s not found\n" "$label"
        ALL_OK=false
    fi
done

if [[ "$ALL_OK" != "true" ]]; then
    fail "Some components are missing. Please resolve the errors above."
fi

step "Smoke test — claude --version"
claude --version

printf "\n\033[32mClaude Code CLI is ready.\033[0m\n"
printf "Run 'claude' to start, or 'claude --help' for options.\n\n"
