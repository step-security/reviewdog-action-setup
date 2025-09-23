#!/bin/sh
# Nightly reviewdog installer - custom implementation
# Same functionality as upstream with different structure

set -e

show_help() {
  script_name=$1
  cat <<EOF
$script_name: install reviewdog nightly binary from GitHub

Usage: $script_name [-b bindir] [-d] [-n] [tag]
  -b sets binary installation directory, defaults to \${NIGHTLY_BIN:-\${HOME}/.local/bin}
  -d enables debug output
  -n enables dry run mode
   [tag] specifies release tag from
   https://github.com/reviewdog/nightly/releases
   If tag is missing, latest will be used.

 Custom nightly installer
EOF
  exit 2
}

cat /dev/null <<EOF
------------------------------------------------------------------------
Portable shell functions for cross-platform compatibility
Public domain utilities
------------------------------------------------------------------------
EOF

check_command() {
  command -v "$1" >/dev/null
}

print_error() {
  echo "$@" 1>&2
}

log_level=6
configure_log_level() {
  log_level="$1"
}

validate_log_level() {
  if test -z "$1"; then
    echo "$log_level"
    return
  fi
  [ "$1" -le "$log_level" ]
}

level_name() {
  case $1 in
    0) echo "emergency" ;;
    1) echo "alert" ;;
    2) echo "critical" ;;
    3) echo "error" ;;
    4) echo "warning" ;;
    5) echo "notice" ;;
    6) echo "info" ;;
    7) echo "debug" ;;
    *) echo "$1" ;;
  esac
}

log_debug_msg() {
  validate_log_level 7 || return 0
  print_error "$(get_log_prefix)" "$(level_name 7)" "$@"
}

log_info_msg() {
  validate_log_level 6 || return 0
  print_error "$(get_log_prefix)" "$(level_name 6)" "$@"
}

log_error_msg() {
  validate_log_level 3 || return 0
  print_error "$(get_log_prefix)" "$(level_name 3)" "$@"
}

log_critical_msg() {
  validate_log_level 2 || return 0
  print_error "$(get_log_prefix)" "$(level_name 2)" "$@"
}

detect_operating_system() {
  system_os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$system_os" in
    msys*) system_os="windows" ;;
    mingw*) system_os="windows" ;;
    cygwin*) system_os="windows" ;;
  esac
  if [ "$system_os" = "sunos" ]; then
    if [ "$(uname -o)" = "illumos" ]; then
      system_os="illumos"
    else
      system_os="solaris"
    fi
  fi
  echo "$system_os"
}

detect_architecture() {
  cpu_arch=$(uname -m)
  case $cpu_arch in
    x86_64) cpu_arch="amd64" ;;
    i86pc) cpu_arch="amd64" ;;
    x86) cpu_arch="386" ;;
    i686) cpu_arch="386" ;;
    i386) cpu_arch="386" ;;
    aarch64) cpu_arch="arm64" ;;
    armv5*) cpu_arch="armv5" ;;
    armv6*) cpu_arch="armv6" ;;
    armv7*) cpu_arch="armv7" ;;
  esac
  echo "${cpu_arch}"
}

validate_os_support() {
  current_os=$(detect_operating_system)
  case "$current_os" in
    darwin) return 0 ;;
    dragonfly) return 0 ;;
    freebsd) return 0 ;;
    linux) return 0 ;;
    android) return 0 ;;
    midnightbsd) return 0 ;;
    nacl) return 0 ;;
    netbsd) return 0 ;;
    openbsd) return 0 ;;
    plan9) return 0 ;;
    solaris) return 0 ;;
    illumos) return 0 ;;
    windows) return 0 ;;
  esac
  log_critical_msg "Operating system '$(uname -s)' converted to '$current_os' is not supported"
  return 1
}

validate_arch_support() {
  current_arch=$(detect_architecture)
  case "$current_arch" in
    386) return 0 ;;
    amd64) return 0 ;;
    arm64) return 0 ;;
    armv5) return 0 ;;
    armv6) return 0 ;;
    armv7) return 0 ;;
    ppc64) return 0 ;;
    ppc64le) return 0 ;;
    mips) return 0 ;;
    mipsle) return 0 ;;
    mips64) return 0 ;;
    mips64le) return 0 ;;
    s390x) return 0 ;;
    amd64p32) return 0 ;;
  esac
  log_critical_msg "Architecture '$(uname -m)' converted to '$current_arch' is not supported"
  return 1
}

cat /dev/null <<EOF
------------------------------------------------------------------------
End of platform compatibility functions
------------------------------------------------------------------------
EOF

compute_sha256() {
  input_file=\${1:-/dev/stdin}
  if check_command gsha256sum; then
    computed_hash=$(gsha256sum "$input_file") || return 1
    echo "$computed_hash" | cut -d ' ' -f 1
  elif check_command sha256sum; then
    computed_hash=$(sha256sum "$input_file") || return 1
    echo "$computed_hash" | cut -d ' ' -f 1
  elif check_command shasum; then
    computed_hash=$(shasum -a 256 "$input_file" 2>/dev/null) || return 1
    echo "$computed_hash" | cut -d ' ' -f 1
  elif check_command openssl; then
    computed_hash=$(openssl dgst -sha256 "$input_file") || return 1
    echo "$computed_hash" | cut -d ' ' -f 2
  else
    log_critical_msg "Unable to find SHA-256 hash computation tool"
    return 1
  fi
}

calculate_hash() {
  compute_sha256 "$1"
}

extract_files() {
  archive_file=$1
  strip_levels=\${2:-0} # default 0
  case "\${archive_file}" in
  *.tar.gz | *.tgz) tar --no-same-owner -xzf "\${archive_file}" --strip-components "\${strip_levels}" ;;
  *.tar.xz) tar --no-same-owner -xJf "\${archive_file}" --strip-components "\${strip_levels}" ;;
  *.tar.bz2) tar --no-same-owner -xjf "\${archive_file}" --strip-components "\${strip_levels}" ;;
  *.tar) tar --no-same-owner -xf "\${archive_file}" --strip-components "\${strip_levels}" ;;
  *.gz) gunzip "\${archive_file}" ;;
  *.zip)
    if [ "$strip_levels" -gt 0 ]; then
      temp_dir=$(basename "\${archive_file%.zip}")_temp_extracted
      unzip -q "\${archive_file}" -d "\${temp_dir}"
      main_dir=$(find "\${temp_dir}" -mindepth 1 -maxdepth 1 -type d -print -quit)
      if [ -n "$main_dir" ]; then
        mv "\${main_dir}"/* .
        rmdir "\${main_dir}"
        rmdir "\${temp_dir}"
      else
        log_info_msg "No subdirectory found in zip for component stripping from \${temp_dir}"
      fi
    else
      unzip -q "\${archive_file}"
    fi
    ;;
  *)
    log_error_msg "Unknown archive format for \${archive_file}"
    return 1
    ;;
  esac
}

verify_checksum() {
  file_path=$1
  checksum_file=$2
  if [ -z "\${checksum_file}" ]; then
    log_error_msg "Checksum file not provided for verification"
    return 1
  fi
  calculated=$(calculate_hash "$file_path")
  if [ -z "\${calculated}" ]; then
    log_error_msg "Failed to calculate hash for: \${file_path}"
    return 1
  fi

  file_base=\${file_path##*/}

  while IFS= read -r checksum_line || [ -n "$checksum_line" ]; do
    checksum_line=$(echo "$checksum_line" | tr '\t' ' ')
    trimmed_line=$(echo "$checksum_line" | sed 's/[[:space:]]*$//')
    
    if [ "$trimmed_line" = "$calculated" ]; then
      return 0
    fi

    hash_part=$(echo "$checksum_line" | cut -d' ' -f1)
    if [ "$hash_part" != "$calculated" ]; then
      continue
    fi

    remaining_text="\${checksum_line#"$calculated"}"
    while [ "\${remaining_text#[ ]}" != "$remaining_text" ]; do
      remaining_text="\${remaining_text#[ ]}"
    done

    if [ "\${remaining_text#\\*}" != "$remaining_text" ]; then
      remaining_text="\${remaining_text#\\*}"
    fi

    extracted_name="\${remaining_text##*/}"
    if [ "$extracted_name" = "$file_base" ]; then
      return 0
    fi
  done < "$checksum_file"

  log_error_msg "Checksum verification failed for '$file_path'"
  log_error_msg "  Calculated hash: \${calculated}"
  log_error_msg "  Checksum file contents:"
  cat "$checksum_file" >&2
  return 1
}

download_with_curl_tool() {
  target_file=$1
  download_url=$2
  custom_header=$3
  if [ -n "$GITHUB_TOKEN" ]; then
    log_debug_msg "Using GitHub token for authentication"
    if [ -z "$custom_header" ]; then
      curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o "$target_file" "$download_url"
    else
      curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "$custom_header" -o "$target_file" "$download_url"
    fi
  else
    if [ -z "$custom_header" ]; then
      curl -fsSL -o "$target_file" "$download_url"
    else
      curl -fsSL -H "$custom_header" -o "$target_file" "$download_url"
    fi
  fi
}

download_with_wget_tool() {
  target_file=$1
  download_url=$2
  custom_header=$3
  if [ -n "$GITHUB_TOKEN" ]; then
    log_debug_msg "Using GitHub token for authentication"
    if [ -z "$custom_header" ]; then
      wget -q --header "Authorization: Bearer $GITHUB_TOKEN" -O "$target_file" "$download_url"
    else
      wget -q --header "Authorization: Bearer $GITHUB_TOKEN" --header "$custom_header" -O "$target_file" "$download_url"
    fi
  else
    if [ -z "$custom_header" ]; then
      wget -q -O "$target_file" "$download_url"
    else
      wget -q --header "$custom_header" -O "$target_file" "$download_url"
    fi
  fi
}

perform_github_download() {
  log_debug_msg "Downloading from $2"
  if check_command curl; then
    download_with_curl_tool "$@"
    return
  elif check_command wget; then
    download_with_wget_tool "$@"
    return
  fi
  log_critical_msg "Neither curl nor wget available for download"
  return 1
}

fetch_github_content() {
  temp_file=$(mktemp)
  perform_github_download "\${temp_file}" "$@" || return 1
  content=$(cat "$temp_file")
  rm -f "\${temp_file}"
  echo "$content"
}

get_github_release() {
  repository=$1
  release_version=$2
  test -z "$release_version" && release_version="latest"
  api_endpoint="https://github.com/\${repository}/releases/\${release_version}"
  release_data=$(fetch_github_content "$api_endpoint" "Accept:application/json")
  test -z "$release_data" && return 1
  tag_version=$(echo "$release_data" | tr -s '\n' ' ' | sed 's/.*"tag_name":"//' | sed 's/".*//')
  test -z "$tag_version" && return 1
  echo "$tag_version"
}

# Embedded checksums storage
STORED_CHECKSUMS=""

lookup_embedded_checksum() {
  release_version="$1"
  asset_filename="$2"
  echo "$STORED_CHECKSUMS" | grep -E "^\${release_version}:\${asset_filename}:" | cut -d':' -f3
}

process_arguments() {
  install_directory="\${NIGHTLY_BIN:-\${HOME}/.local/bin}"
  dry_run_mode=0
  while getopts "b:dqh?xn" option; do
    case "$option" in
    b) install_directory="$OPTARG" ;;
    d) configure_log_level 10 ;;
    q) configure_log_level 3 ;;
    h | \\?) show_help "$0" ;;
    x) set -x ;;
    n) dry_run_mode=1 ;;
    esac
  done
  shift $((OPTIND - 1))
  release_tag="\${1:-latest}"
}

resolve_tag_version() {
  if [ "$release_tag" = "latest" ]; then
    log_info_msg "Fetching latest release tag from GitHub"
    actual_tag=$(get_github_release "\${repository_path}" "\${release_tag}") && true
    test -n "$actual_tag" || {
      log_critical_msg "Could not determine latest tag for \${repository_path}"
      exit 1
    }
  else
    actual_tag="$release_tag"
  fi
  if test -z "$actual_tag"; then
    log_critical_msg "Unable to find '\${release_tag}' - use 'latest' or check https://github.com/\${repository_path}/releases"
    exit 1
  fi
  version_number=\${actual_tag#v} # Strip leading 'v'
  release_tag="$actual_tag"       # Use the resolved tag
  log_info_msg "Resolved version: \${version_number} (tag: \${release_tag})"
}

determine_asset_name() {
  # Apply platform-specific rules
  asset_file_name=""
  if [ "\${detected_arch}" = 'amd64' ] && true
  then
    mapped_arch='x86_64'
  else
    mapped_arch="\${detected_arch}"
  fi
  if [ "\${detected_os}" = 'darwin' ] && true
  then
    mapped_os='Darwin'
  elif [ "\${detected_os}" = 'linux' ] && true
  then
    mapped_os='Linux'
  elif [ "\${detected_os}" = 'windows' ] && true
  then
    mapped_os='Windows'
  else
    mapped_os="\${detected_os}"
  fi
  if [ -z "\${asset_file_name}" ]; then
    asset_file_name="reviewdog_\${version_number}_\${mapped_os}_\${mapped_arch}\${file_extension}"
  fi
}

cleanup_temp_files() {
  if [ -n "$temp_directory" ] && [ -d "$temp_directory" ]; then
    log_debug_msg "Cleaning up temporary directory: $temp_directory"
    rm -rf -- "$temp_directory"
  fi
}

run_main_process() {
  component_strip_level=0
  checksums_filename="checksums.txt"

  # Build download URLs
  github_releases_base="https://github.com/\${repository_path}/releases/download"
  binary_download_url="\${github_releases_base}/\${release_tag}/\${asset_file_name}"
  checksum_download_url=""
  if [ -n "$checksums_filename" ]; then
    checksum_download_url="\${github_releases_base}/\${release_tag}/\${checksums_filename}"
  fi

  # Download and verify process
  temp_directory=$(mktemp -d)
  trap 'rm -rf -- "$temp_directory"' EXIT HUP INT TERM
  log_debug_msg "Using temporary directory: \${temp_directory}"
  log_info_msg "Downloading \${binary_download_url}"
  perform_github_download "\${temp_directory}/\${asset_file_name}" "\${binary_download_url}"

  # Check for embedded checksums first
  stored_hash=$(lookup_embedded_checksum "$version_number" "$asset_file_name")

  if [ -n "$stored_hash" ]; then
    log_info_msg "Using embedded checksum for verification"
    computed=$(calculate_hash "\${temp_directory}/\${asset_file_name}")
    if [ "$computed" != "$stored_hash" ]; then
      log_critical_msg "Checksum verification failed for \${asset_file_name}"
      log_critical_msg "Expected: \${stored_hash}"
      log_critical_msg "Computed: \${computed}"
      return 1
    fi
    log_info_msg "Checksum verification successful"
  elif [ -n "$checksum_download_url" ]; then
    log_info_msg "Downloading checksums from \${checksum_download_url}"
    perform_github_download "\${temp_directory}/\${checksums_filename}" "\${checksum_download_url}"
    log_info_msg "Verifying checksum..."
    verify_checksum "\${temp_directory}/\${asset_file_name}" "\${temp_directory}/\${checksums_filename}"
  else
    log_info_msg "No checksum available, skipping verification"
  fi

  if [ -z "\${file_extension}" ] || [ "\${file_extension}" = ".exe" ]; then
    log_debug_msg "Binary file detected"
  else
    log_info_msg "Extracting \${asset_file_name}..."
    (cd "\${temp_directory}" && extract_files "\${asset_file_name}" "\${component_strip_level}")
  fi
  
  executable_name='reviewdog'
  if [ -z "\${file_extension}" ] || [ "\${file_extension}" = ".exe" ]; then
    executable_file_path="\${temp_directory}/\${asset_file_name}"
  else
    executable_file_path="\${temp_directory}/reviewdog"
  fi

  if [ "\${detected_os}" = "windows" ]; then
    case "\${executable_name}" in *.exe) ;; *) executable_name="\${executable_name}.exe" ;; esac
    case "\${executable_file_path}" in *.exe) ;; *) executable_file_path="\${executable_file_path}.exe" ;; esac
  fi

  if [ ! -f "\${executable_file_path}" ]; then
    log_critical_msg "Executable not found: \${executable_file_path}"
    log_critical_msg "Directory contents:"
    if command -v find >/dev/null 2>&1; then
      cd "\${temp_directory}" && find .
    else
      cd "\${temp_directory}" && ls -R .
    fi
    return 1
  fi
  
  # Install the binary
  final_install_path="\${install_directory}/\${executable_name}"

  if [ "$dry_run_mode" = "1" ]; then
    log_info_msg "[DRY RUN] \${executable_name} dry-run installation succeeded! (Would install to: \${final_install_path})"
  else
    log_info_msg "Installing binary to \${final_install_path}"
    test ! -d "\${install_directory}" && install -d "\${install_directory}"
    install "\${executable_file_path}" "\${final_install_path}"
    log_info_msg "\${executable_name} installation complete!"
  fi
}

# Configuration constants
binary_name='reviewdog'
repository_path='reviewdog/nightly'
file_extension='.tar.gz'

get_log_prefix() {
  echo "\${repository_path}"
}

process_arguments "$@"

# Detect target platform
detected_os="\${NIGHTLY_OS:-$(detect_operating_system)}"
original_os="\${detected_os}"

detected_arch="\${NIGHTLY_ARCH:-$(detect_architecture)}"
original_arch="\${detected_arch}"
log_info_msg "Detected Platform: \${detected_os}/\${detected_arch}"

# Validate platform support
validate_os_support "$detected_os"
validate_arch_support "$detected_arch"

resolve_tag_version
determine_asset_name
run_main_process