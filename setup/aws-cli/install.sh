#!/usr/bin/env bash

set -euo pipefail

system_prefix() {
    printf '%s\n' "usr/local"
}

aws_cli_version() {
    local binary=$1
    local output

    if ! output=$("$binary" --version 2>&1); then
        return 1
    fi

    if [[ "$output" =~ ^aws-cli/([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" && "$(dirname -- "$TEMP_DIR")" == "$TEMP_ROOT" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

main() {
    if [[ ! "${AWS_CLI_VERSION:-}" =~ ^2\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid AWS CLI V2 version: ${AWS_CLI_VERSION:-}" >&2
        exit 1
    fi

    local selected_aws
    local installed_version=""
    if selected_aws=$(command -v aws) && installed_version=$(aws_cli_version "$selected_aws"); then
        if [[ "$installed_version" == 2.* ]]; then
            echo "Working AWS CLI V2 $installed_version is already installed at $selected_aws; skipping installation."
            return 0
        fi

        echo "Installed AWS CLI Version '$installed_version' is not v2; installing AWS CLI v2 $AWS_CLI_VERSION."
    elif [[ -n "${selected_aws:-}" ]]; then
        echo "Installed AWS CLI Version is unknown; installing required version '$AWS_CLI_VERSION'."
    fi

    local machine_arch
    machine_arch=$(uname -m)
    local aws_cli_arch
    case "$machine_arch" in
        x86_64 | amd64)
            aws_cli_arch="x86_64"
            ;;
        aarch64 | arm64)
            aws_cli_arch="aarch64"
            ;;
        *)
            echo "Unsupported runner architecture: $machine_arch" >&2
            exit 1
            ;;
    esac

    local run_as_root=false
    local use_sudo=false
    if [[ "$(id -u)" == "0" ]]; then
        run_as_root=true
    elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        use_sudo=true
    fi

    local -a missing_prerequisites=()
    command -v curl >/dev/null 2>&1 || missing_prerequisites+=("curl")
    command -v unzip >/dev/null 2>&1 || missing_prerequisites+=("unzip")

    if (( ${#missing_prerequisites[@]} > 0 )); then
        if [[ "$run_as_root" != true && "$use_sudo" != true ]]; then
            echo "Missing required prerequisite(s): ${missing_prerequisites[*]}. Install them or provide non-interactive sudo access." >&2
            exit 1
        fi

        if ! command -v apt-get >/dev/null 2>&1; then
            echo "Missing required prerequisite(s): ${missing_prerequisites[*]}, and apt-get is unavailable" >&2
            exit 1
        fi

        if [[ "$use_sudo" == true ]]; then
            sudo -n apt-get update
            sudo -n apt-get install -y "${missing_prerequisites[@]}"
        else
            apt-get update
            apt-get install -y "${missing_prerequisites[@]}"
        fi

        local prerequisite
        for prerequisite in "${missing_prerequisites[@]}"; do
            if ! command -v "$prerequisite" >/dev/null 2>&1; then
                echo "Failed to install required prerequisite: $prerequisite" >&2
                exit 1
            fi
        done
    fi

    local bin_dir
    local install_dir
    local prefix
    if [[ "$run_as_root" == true || "$use_sudo" == true ]]; then
        prefix=$(system_prefix)
        bin_dir="$prefix/bin"
        install_dir="$prefix/aws-cli"
    else
        prefix="${RUNNER_TEMP:-$HOME/.local}"
        bin_dir="$prefix/bin"
        install_dir="$prefix/aws-cli"
        mkdir -p -- "$prefix" "$bin_dir"
    fi

    TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    mkdir -p -- "$TEMP_ROOT"
    TEMP_DIR=$(mktemp -d "$TEMP_ROOT/awscli.xxxxxx")
    trap cleanup EXIT

    curl -fsSL --retry 3 --retry-all-errors \
        "https://awscli.amazonaws.com/awscli-exe-linux-${aws_cli_arch}-${AWS_CLI_VERSION}.zip" \
        -o "$TEMP_DIR/awscliv2.zip"
    
    unzip -q "$TEMP_DIR/awscliv2.zip" -d "$TEMP_DIR"

    local -a install_args=(
        "$TEMP_DIR/aws/install"
        "--bin-dir" "$bin_dir"
        "--install-dir" "$install_dir"
    )

    if [[ -d "$install_dir/v2" ]]; then
        install_args+=("--update")
    fi

    if [[ "$use_sudo" == true ]]; then
        sudo -n "${install_args[@]}"
    else
        "${install_args[@]}"
    fi

    selected_aws="$bin_dir/aws"
    if [[ ! -x "$selected_aws" ]]; then
        echo "AWS CLI installer did not create an executable at $selected_aws" >&2
        exit 1
    fi

    installed_version=$(aws_cli_version "$selected_aws") || {
        echo "Unable to determine the installed AWS CLI version at $selected_aws" >&2
        exit 1
    }
    if [[ "$installed_version" != "$AWS_CLI_VERSION" ]]; then
        echo "Installed AWS CLI version '$installed_version' does not match requested version '$AWS_CLI_VERSION'." >&2
        exit 1
    fi

    printf '%s\n' "$bin_dir" >> "$GITHUB_PATH"
    "$selected_aws" --versiom
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi