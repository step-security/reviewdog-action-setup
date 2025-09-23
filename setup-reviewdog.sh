#!/bin/sh
# Reviewdog stable installer - custom implementation
# Same functionality as upstream with different structure

set -e

display_help() {
  program_name=$1
  cat <<EOF
$program_name: install reviewdog stable binary from GitHub

Usage: $program_name [-b bindir] [-d] [-n] [tag]
  -b sets binary installation directory, defaults to \${REVIEWDOG_BIN:-\${HOME}/.local/bin}
  -d enables debug output
  -n enables dry run mode
   [tag] specifies release tag from
   https://github.com/reviewdog/reviewdog/releases
   If tag is missing, latest will be used.

 Custom stable installer
EOF
  exit 2
}

cat /dev/null <<EOF
------------------------------------------------------------------------
Cross-platform shell utilities for portable functionality
Public domain compatibility functions
------------------------------------------------------------------------
EOF

command_exists() {
  command -v "$1" >/dev/null
}

output_to_stderr() {
  echo "$@" 1>&2
}

verbosity_level=6
set_verbosity() {
  verbosity_level="$1"
}

check_verbosity() {
  if test -z "$1"; then
    echo "$verbosity_level"
    return
  fi
  [ "$1" -le "$verbosity_level" ]
}

get_severity_label() {
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

debug_message() {
  check_verbosity 7 || return 0
  output_to_stderr "$(repo_identifier)" "$(get_severity_label 7)" "$@"
}

info_message() {
  check_verbosity 6 || return 0
  output_to_stderr "$(repo_identifier)" "$(get_severity_label 6)" "$@"
}

error_message() {
  check_verbosity 3 || return 0
  output_to_stderr "$(repo_identifier)" "$(get_severity_label 3)" "$@"
}

critical_message() {
  check_verbosity 2 || return 0
  output_to_stderr "$(repo_identifier)" "$(get_severity_label 2)" "$@"
}

identify_os() {
  operating_system=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$operating_system" in
    msys*) operating_system="windows" ;;
    mingw*) operating_system="windows" ;;
    cygwin*) operating_system="windows" ;;
  esac
  if [ "$operating_system" = "sunos" ]; then
    if [ "$(uname -o)" = "illumos" ]; then
      operating_system="illumos"
    else
      operating_system="solaris"
    fi
  fi
  echo "$operating_system"
}

identify_arch() {
  processor_arch=$(uname -m)
  case $processor_arch in
    x86_64) processor_arch="amd64" ;;
    i86pc) processor_arch="amd64" ;;
    x86) processor_arch="386" ;;
    i686) processor_arch="386" ;;
    i386) processor_arch="386" ;;
    aarch64) processor_arch="arm64" ;;
    armv5*) processor_arch="armv5" ;;
    armv6*) processor_arch="armv6" ;;
    armv7*) processor_arch="armv7" ;;
  esac
  echo "${processor_arch}"
}

verify_os_compatibility() {
  current_os=$(identify_os)
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
  critical_message "Operating system '$(uname -s)' converted to '$current_os' is not supported"
  return 1
}

verify_arch_compatibility() {
  current_arch=$(identify_arch)
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
  critical_message "Architecture '$(uname -m)' converted to '$current_arch' is not supported"
  return 1
}

cat /dev/null <<EOF
------------------------------------------------------------------------
End of cross-platform compatibility functions
------------------------------------------------------------------------
EOF

calculate_sha256() {
  target_file=\${1:-/dev/stdin}
  if command_exists gsha256sum; then
    hash_result=$(gsha256sum "$target_file") || return 1
    echo "$hash_result" | cut -d ' ' -f 1
  elif command_exists sha256sum; then
    hash_result=$(sha256sum "$target_file") || return 1
    echo "$hash_result" | cut -d ' ' -f 1
  elif command_exists shasum; then
    hash_result=$(shasum -a 256 "$target_file" 2>/dev/null) || return 1
    echo "$hash_result" | cut -d ' ' -f 1
  elif command_exists openssl; then
    hash_result=$(openssl dgst -sha256 "$target_file") || return 1
    echo "$hash_result" | cut -d ' ' -f 2
  else
    critical_message "Unable to find SHA-256 hash computation tool"
    return 1
  fi
}

generate_hash() {
  calculate_sha256 "$1"
}

decompress_archive() {
  compressed_file=$1
  strip_depth=\${2:-0} # default 0
  case "\${compressed_file}" in
  *.tar.gz | *.tgz) tar --no-same-owner -xzf "\${compressed_file}" --strip-components "\${strip_depth}" ;;
  *.tar.xz) tar --no-same-owner -xJf "\${compressed_file}" --strip-components "\${strip_depth}" ;;
  *.tar.bz2) tar --no-same-owner -xjf "\${compressed_file}" --strip-components "\${strip_depth}" ;;
  *.tar) tar --no-same-owner -xf "\${compressed_file}" --strip-components "\${strip_depth}" ;;
  *.gz) gunzip "\${compressed_file}" ;;
  *.zip)
    if [ "$strip_depth" -gt 0 ]; then
      extraction_dir=$(basename "\${compressed_file%.zip}")_extract_temp
      unzip -q "\${compressed_file}" -d "\${extraction_dir}"
      primary_dir=$(find "\${extraction_dir}" -mindepth 1 -maxdepth 1 -type d -print -quit)
      if [ -n "$primary_dir" ]; then
        mv "\${primary_dir}"/* .
        rmdir "\${primary_dir}"
        rmdir "\${extraction_dir}"
      else
        info_message "No subdirectory found in zip for component stripping from \${extraction_dir}"
      fi
    else
      unzip -q "\${compressed_file}"
    fi
    ;;
  *)
    error_message "Unknown archive format for \${compressed_file}"
    return 1
    ;;
  esac
}

validate_checksum() {
  target_path=$1
  sum_file=$2
  if [ -z "\${sum_file}" ]; then
    error_message "Checksum file not provided for verification"
    return 1
  fi
  computed_sum=$(generate_hash "$target_path")
  if [ -z "\${computed_sum}" ]; then
    error_message "Failed to calculate hash for: \${target_path}"
    return 1
  fi

  filename_only=\${target_path##*/}

  while IFS= read -r sum_line || [ -n "$sum_line" ]; do
    sum_line=$(echo "$sum_line" | tr '\t' ' ')
    clean_line=$(echo "$sum_line" | sed 's/[[:space:]]*$//')
    
    if [ "$clean_line" = "$computed_sum" ]; then
      return 0
    fi

    sum_portion=$(echo "$sum_line" | cut -d' ' -f1)
    if [ "$sum_portion" != "$computed_sum" ]; then
      continue
    fi

    leftover_text="\${sum_line#"$computed_sum"}"
    while [ "\${leftover_text#[ ]}" != "$leftover_text" ]; do
      leftover_text="\${leftover_text#[ ]}"
    done

    if [ "\${leftover_text#\\*}" != "$leftover_text" ]; then
      leftover_text="\${leftover_text#\\*}"
    fi

    final_filename="\${leftover_text##*/}"
    if [ "$final_filename" = "$filename_only" ]; then
      return 0
    fi
  done < "$sum_file"

  error_message "Checksum verification failed for '$target_path'"
  error_message "  Computed hash: \${computed_sum}"
  error_message "  Checksum file contents:"
  cat "$sum_file" >&2
  return 1
}

fetch_with_curl() {
  output_file=$1
  source_url=$2
  header_option=$3
  if [ -n "$GITHUB_TOKEN" ]; then
    debug_message "Using GitHub token for authentication"
    if [ -z "$header_option" ]; then
      curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o "$output_file" "$source_url"
    else
      curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "$header_option" -o "$output_file" "$source_url"
    fi
  else
    if [ -z "$header_option" ]; then
      curl -fsSL -o "$output_file" "$source_url"
    else
      curl -fsSL -H "$header_option" -o "$output_file" "$source_url"
    fi
  fi
}

fetch_with_wget() {
  output_file=$1
  source_url=$2
  header_option=$3
  if [ -n "$GITHUB_TOKEN" ]; then
    debug_message "Using GitHub token for authentication"
    if [ -z "$header_option" ]; then
      wget -q --header "Authorization: Bearer $GITHUB_TOKEN" -O "$output_file" "$source_url"
    else
      wget -q --header "Authorization: Bearer $GITHUB_TOKEN" --header "$header_option" -O "$output_file" "$source_url"
    fi
  else
    if [ -z "$header_option" ]; then
      wget -q -O "$output_file" "$source_url"
    else
      wget -q --header "$header_option" -O "$output_file" "$source_url"
    fi
  fi
}

execute_download() {
  debug_message "Downloading from $2"
  if command_exists curl; then
    fetch_with_curl "$@"
    return
  elif command_exists wget; then
    fetch_with_wget "$@"
    return
  fi
  critical_message "Neither curl nor wget available for download"
  return 1
}

retrieve_content() {
  staging_file=$(mktemp)
  execute_download "\${staging_file}" "$@" || return 1
  file_contents=$(cat "$staging_file")
  rm -f "\${staging_file}"
  echo "$file_contents"
}

fetch_release_info() {
  repo_path=$1
  version_spec=$2
  test -z "$version_spec" && version_spec="latest"
  github_url="https://github.com/\${repo_path}/releases/\${version_spec}"
  json_response=$(retrieve_content "$github_url" "Accept:application/json")
  test -z "$json_response" && return 1
  version_tag=$(echo "$json_response" | tr -s '\n' ' ' | sed 's/.*"tag_name":"//' | sed 's/".*//')
  test -z "$version_tag" && return 1
  echo "$version_tag"
}

# Embedded checksums storage
PRECOMPUTED_CHECKSUMS=""

find_stored_checksum() {
  version_key="$1"
  file_key="$2"
  echo "$PRECOMPUTED_CHECKSUMS" | grep -E "^\${version_key}:\${file_key}:" | cut -d':' -f3
}

handle_arguments() {
  target_directory="\${REVIEWDOG_BIN:-\${HOME}/.local/bin}"
  simulation_mode=0
  while getopts "b:dqh?xn" flag; do
    case "$flag" in
    b) target_directory="$OPTARG" ;;
    d) set_verbosity 10 ;;
    q) set_verbosity 3 ;;
    h | \\?) display_help "$0" ;;
    x) set -x ;;
    n) simulation_mode=1 ;;
    esac
  done
  shift $((OPTIND - 1))
  version_tag="\${1:-latest}"
}

convert_tag_to_version() {
  if [ "$version_tag" = "latest" ]; then
    info_message "Fetching latest release tag from GitHub"
    resolved_tag=$(fetch_release_info "\${project_repository}" "\${version_tag}") && true
    test -n "$resolved_tag" || {
      critical_message "Could not determine latest tag for \${project_repository}"
      exit 1
    }
  else
    resolved_tag="$version_tag"
  fi
  if test -z "$resolved_tag"; then
    critical_message "Unable to find '\${version_tag}' - use 'latest' or check https://github.com/\${project_repository}/releases"
    exit 1
  fi
  clean_version=\${resolved_tag#v} # Strip leading 'v'
  version_tag="$resolved_tag"       # Use the resolved tag
  info_message "Resolved version: \${clean_version} (tag: \${version_tag})"
}

build_asset_filename() {
  # Apply platform-specific mapping rules
  final_asset_name=""
  if [ "\${platform_arch}" = 'amd64' ] && true
  then
    target_arch='x86_64'
  elif [ "\${platform_arch}" = '386' ] && true
  then
    target_arch='i386'
  else
    target_arch="\${platform_arch}"
  fi
  
  # Convert OS name to title case
  first_char=$(printf "%s" "\${platform_os}" | cut -c1)
  upper_first=$(printf "%s" "$first_char" | tr '[:lower:]' '[:upper:]')
  target_os=$(printf "%s%s" "$upper_first" "$(printf "%s" "\${platform_os}" | cut -c2-)")
  
  if [ -z "\${final_asset_name}" ]; then
    final_asset_name="\${app_name}_\${clean_version}_\${target_os}_\${target_arch}\${archive_ext}"
  fi
}

remove_temp_resources() {
  if [ -n "$work_directory" ] && [ -d "$work_directory" ]; then
    debug_message "Cleaning up temporary directory: $work_directory"
    rm -rf -- "$work_directory"
  fi
}

perform_installation() {
  strip_components_count=0
  verification_filename="checksums.txt"

  # Build download URLs
  release_base="https://github.com/\${project_repository}/releases/download"
  asset_url="\${release_base}/\${version_tag}/\${final_asset_name}"
  verification_url=""
  if [ -n "$verification_filename" ]; then
    verification_url="\${release_base}/\${version_tag}/\${verification_filename}"
  fi

  # Download and verify process
  work_directory=$(mktemp -d)
  trap 'rm -rf -- "$work_directory"' EXIT HUP INT TERM
  debug_message "Using working directory: \${work_directory}"
  info_message "Downloading \${asset_url}"
  execute_download "\${work_directory}/\${final_asset_name}" "\${asset_url}"

  # Check for embedded checksums first
  embedded_sum=$(find_stored_checksum "$clean_version" "$final_asset_name")

  if [ -n "$embedded_sum" ]; then
    info_message "Using embedded checksum for verification"
    actual_sum=$(generate_hash "\${work_directory}/\${final_asset_name}")
    if [ "$actual_sum" != "$embedded_sum" ]; then
      critical_message "Checksum verification failed for \${final_asset_name}"
      critical_message "Expected: \${embedded_sum}"
      critical_message "Actual: \${actual_sum}"
      return 1
    fi
    info_message "Checksum verification successful"
  elif [ -n "$verification_url" ]; then
    info_message "Downloading checksums from \${verification_url}"
    execute_download "\${work_directory}/\${verification_filename}" "\${verification_url}"
    info_message "Verifying checksum..."
    validate_checksum "\${work_directory}/\${final_asset_name}" "\${work_directory}/\${verification_filename}"
  else
    info_message "No checksum available, skipping verification"
  fi

  if [ -z "\${archive_ext}" ] || [ "\${archive_ext}" = ".exe" ]; then
    debug_message "Binary file detected"
  else
    info_message "Extracting \${final_asset_name}..."
    (cd "\${work_directory}" && decompress_archive "\${final_asset_name}" "\${strip_components_count}")
  fi
  
  binary_filename='reviewdog'
  if [ -z "\${archive_ext}" ] || [ "\${archive_ext}" = ".exe" ]; then
    binary_location="\${work_directory}/\${final_asset_name}"
  else
    binary_location="\${work_directory}/reviewdog"
  fi

  if [ "\${platform_os}" = "windows" ]; then
    case "\${binary_filename}" in *.exe) ;; *) binary_filename="\${binary_filename}.exe" ;; esac
    case "\${binary_location}" in *.exe) ;; *) binary_location="\${binary_location}.exe" ;; esac
  fi

  if [ ! -f "\${binary_location}" ]; then
    critical_message "Executable not found: \${binary_location}"
    critical_message "Directory contents:"
    if command -v find >/dev/null 2>&1; then
      cd "\${work_directory}" && find .
    else
      cd "\${work_directory}" && ls -R .
    fi
    return 1
  fi
  
  # Install the binary
  installation_path="\${target_directory}/\${binary_filename}"

  if [ "$simulation_mode" = "1" ]; then
    info_message "[DRY RUN] \${binary_filename} dry-run installation succeeded! (Would install to: \${installation_path})"
  else
    info_message "Installing binary to \${installation_path}"
    test ! -d "\${target_directory}" && install -d "\${target_directory}"
    install "\${binary_location}" "\${installation_path}"
    info_message "\${binary_filename} installation complete!"
  fi
}

# Configuration constants
app_name='reviewdog'
project_repository='reviewdog/reviewdog'
archive_ext='.tar.gz'

repo_identifier() {
  echo "\${project_repository}"
}

handle_arguments "$@"

# Detect target platform
platform_os="\${REVIEWDOG_OS:-$(identify_os)}"
original_platform_os="\${platform_os}"

platform_arch="\${REVIEWDOG_ARCH:-$(identify_arch)}"
original_platform_arch="\${platform_arch}"
info_message "Detected Platform: \${platform_os}/\${platform_arch}"

# Validate platform support
verify_os_compatibility "$platform_os"
verify_arch_compatibility "$platform_arch"

convert_tag_to_version
build_asset_filename
perform_installation