#!/usr/bin/env bash
set -euo pipefail

RESET="\033[0m"
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"

REPO_URL="https://github.com/universeclouddev/universe.git"
DEFAULT_DIR="$HOME/universe"
DEFAULT_BRANCH="production"
EXTENSIONS=(
  "runtime-docker"
  "runtime-k8s"
  "storage-s3"
  "db-postgres"
  "db-mongodb"
  "db-redis"
  "metrics-prometheus"
  "metrics-influxdb"
  "gitops"
  "argocd"
  "discord"
  "tailscale"
)

print_header() {
  printf "\n${BOLD}${CYAN}Universe installer${RESET}\n"
  printf "${CYAN}Installs Universe from source and builds the selected modules.${RESET}\n\n"
}

info() {
  printf "${BLUE}==>${RESET} %s\n" "$1"
}

success() {
  printf "${GREEN}✓${RESET} %s\n" "$1"
}

warn() {
  printf "${YELLOW}!${RESET} %s\n" "$1" >&2
}

fail() {
  printf "${RED}✗${RESET} %s\n" "$1" >&2
  exit 1
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local answer=""
  read -r -p "$(printf "${BOLD}%s${RESET} [%s]: " "$prompt" "$default")" answer
  printf "%s" "${answer:-$default}"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is required. Install it and run this script again."
  fi
}

confirm() {
  local prompt="$1"
  local answer=""
  read -r -p "$(printf "${BOLD}%s${RESET} [y/N]: " "$prompt")" answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

confirm_default_yes() {
  local prompt="$1"
  local answer=""
  read -r -p "$(printf "${BOLD}%s${RESET} [Y/n]: " "$prompt")" answer
  case "$answer" in
    n|N|no|NO) return 1 ;;
    *) return 0 ;;
  esac
}

select_build_mode() {
  printf "\n${BOLD}Build source or use pre-compiled files?${RESET}\n" >&2
  printf "1) Compile from source\n" >&2
  printf "2) Pre-compiled files ${YELLOW}(not available yet)${RESET}\n" >&2
  local answer=""
  while true; do
    read -r -p "Choose an option [1]: " answer
    answer="${answer:-1}"
    case "$answer" in
      1) printf "compile"; return ;;
      2) warn "Pre-compiled files are not available yet. This installer will compile from source."; printf "compile"; return ;;
      *) warn "Choose 1 or 2." ;;
    esac
  done
}

select_extensions() {
  printf "\n${BOLD}Optional extensions${RESET}\n" >&2
  printf "Enter numbers separated by spaces, type 'all', or press Enter for none.\n" >&2
  local i=1
  for extension in "${EXTENSIONS[@]}"; do
    printf "%2d) %s\n" "$i" "$extension" >&2
    i=$((i + 1))
  done

  local answer=""
  read -r -p "Extensions: " answer
  if [[ -z "$answer" ]]; then
    return
  fi

  if [[ "$answer" == "all" ]]; then
    printf "%s\n" "${EXTENSIONS[@]}"
    return
  fi

  local selected=()
  local item=""
  for item in $answer; do
    if [[ "$item" =~ ^[0-9]+$ ]] && (( item >= 1 && item <= ${#EXTENSIONS[@]} )); then
      selected+=("${EXTENSIONS[$((item - 1))]}")
    else
      warn "Ignoring invalid extension selection: $item"
    fi
  done

  printf "%s\n" "${selected[@]}"
}

prepare_directory() {
  local install_dir="$1"
  SOURCE_UPDATED=0
  mkdir -p "$install_dir"
  if [[ -d "$install_dir/source/.git" ]]; then
    if [[ -f "$install_dir/runtime/config.json" || -f "$install_dir/runtime/database.json" ]]; then
      info "An existing Universe installation was found."
    else
      info "An existing Universe source checkout was found."
    fi
    if confirm "Update Universe source with git pull?"; then
      git -C "$install_dir/source" pull --ff-only
      SOURCE_UPDATED=1
    else
      warn "Using the existing source revision without fetching, checking out, or pulling."
    fi
  else
    if [[ -e "$install_dir/source" ]]; then
      fail "$install_dir/source exists but is not a Git repository. Move it or choose another install directory."
    fi
    git clone "$REPO_URL" "$install_dir/source"
    SOURCE_UPDATED=1
  fi
}

is_valid_remote_ref() {
  local source_dir="$1"
  local ref="$2"
  git check-ref-format --branch "$ref" >/dev/null 2>&1 && \
    git -C "$source_dir" ls-remote --exit-code origin "refs/heads/$ref" "refs/tags/$ref" >/dev/null 2>&1
}

select_branch() {
  local source_dir="$1"
  local branch=""

  if (( ! SOURCE_UPDATED )); then
    branch=$(git -C "$source_dir" rev-parse --abbrev-ref HEAD)
    info "Keeping the existing checked-out revision ($branch)." >&2
    printf "%s" "$branch"
    return
  fi

  if confirm_default_yes "Use the production source branch?"; then
    printf "%s" "$DEFAULT_BRANCH"
    return
  fi

  while true; do
    branch=$(prompt_default "Universe branch or tag" "$DEFAULT_BRANCH")
    if is_valid_remote_ref "$source_dir" "$branch"; then
      printf "%s" "$branch"
      return
    fi
    warn "'$branch' is not a branch or tag in the Universe repository. Please try again."
  done
}

checkout_branch() {
  local source_dir="$1"
  local branch="$2"

  if (( ! SOURCE_UPDATED )); then
    return
  fi

  git -C "$source_dir" fetch --all --prune
  git -C "$source_dir" checkout "$branch"
  if git -C "$source_dir" symbolic-ref --quiet HEAD >/dev/null; then
    git -C "$source_dir" pull --ff-only
  fi
}

build_universe() {
  local source_dir="$1"
  shift
  local selected_extensions=("$@")
  local tasks=(":loader:build" ":app:build" ":api:build")

  for extension in "${selected_extensions[@]}"; do
    tasks+=(":extensions:extension-$extension:build")
  done

  chmod +x "$source_dir/gradlew"
  (cd "$source_dir" && ./gradlew --no-daemon "${tasks[@]}")
}

write_runtime_files() {
  local install_dir="$1"
  mkdir -p "$install_dir/runtime/extensions" "$install_dir/runtime/configuration" "$install_dir/runtime/templates" "$install_dir/runtime/running" "$install_dir/runtime/data"

  if [[ ! -f "$install_dir/runtime/config.json" ]]; then
    cat > "$install_dir/runtime/config.json" <<'JSON'
{
  "address": "127.0.0.1",
  "port": 6000,
  "apiPort": 7000,
  "nodeId": "node-1",
  "clusterName": "universe-cluster",
  "isMasterNode": true,
  "masterAddress": "127.0.0.1",
  "masterPort": 6000,
  "masterApiPort": 7000
}
JSON
  fi

  if [[ ! -f "$install_dir/runtime/database.json" ]]; then
    cat > "$install_dir/runtime/database.json" <<'JSON'
{
  "provider": "h2",
  "url": "universe.db",
  "host": "localhost",
  "port": 3306,
  "database": "universe",
  "username": "sa",
  "password": ""
}
JSON
  fi
}

copy_artifacts() {
  local install_dir="$1"
  local source_dir="$install_dir/source"
  mkdir -p "$install_dir/runtime/jars" "$install_dir/runtime/extensions"
  find "$source_dir/.built" -maxdepth 1 -type f -name 'universe-extension-*.jar' -exec cp {} "$install_dir/runtime/extensions/" \;
  find "$source_dir/.built" -maxdepth 1 -type f -name '*.jar' ! -name 'universe-extension-*.jar' -exec cp {} "$install_dir/runtime/jars/" \;
}

print_next_steps() {
  local install_dir="$1"
  local loader_jar=""
  loader_jar=$(find "$install_dir/runtime/jars" -maxdepth 1 -type f -name '*loader*.jar' | head -n 1 || true)

  printf "\n${BOLD}${GREEN}Universe is installed.${RESET}\n"
  printf "${BOLD}Install directory:${RESET} %s\n" "$install_dir"
  printf "${BOLD}Runtime directory:${RESET} %s\n" "$install_dir/runtime"

  if [[ -n "$loader_jar" ]]; then
    printf "\n${BOLD}Start Universe:${RESET}\n"
    printf "cd %q/runtime\n" "$install_dir"
    printf "java -jar %q\n" "jars/$(basename "$loader_jar")"
  else
    warn "No loader JAR was found in runtime/jars. Check the Gradle build output."
  fi
}

main() {
  print_header
  require_command git
  require_command java
  require_command find

  local install_dir=""
  local branch=""
  local build_mode=""
  mapfile -t selected_extensions < <(select_extensions)

  install_dir=$(prompt_default "Install directory" "$DEFAULT_DIR")
  build_mode=$(select_build_mode)

  if [[ "$build_mode" != "compile" ]]; then
    fail "Only source compilation is available right now."
  fi

  info "Preparing install directory"
  prepare_directory "$install_dir"
  branch=$(select_branch "$install_dir/source")
  info "Checking out $branch"
  checkout_branch "$install_dir/source" "$branch"
  info "Building Universe"
  build_universe "$install_dir/source" "${selected_extensions[@]}"
  info "Creating runtime files"
  write_runtime_files "$install_dir"
  info "Copying build artifacts"
  copy_artifacts "$install_dir"
  success "Finished"
  print_next_steps "$install_dir"
}

main "$@"
