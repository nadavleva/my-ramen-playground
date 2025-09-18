#! /bin/bash

# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# vim: set ts=4 sw=4 et :

# Usage: pre-commit.sh

# Run checks from root of the repo
scriptdir="$(dirname "$(realpath "$0")")"
cd "$scriptdir/.." || exit 1

OUTPUTS_FILE="$(mktemp --tmpdir tool-errors-XXXXXX)"

echo "${OUTPUTS_FILE}"

check_version() {
    if ! [[ "$1" == "$(echo -e "$1\n$2" | sort -V | tail -n1)" ]] ; then
        echo "ERROR: $3 version is too old. Expected $2, found $1"
        exit 1
    fi
}

get_files() {
    git ls-files -z | grep --binary-files=without-match --null-data --null -E "$1"
}

# check_tool <tool>
check_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: $1 is not installed"
        echo "You can install it by running:"
        case "$1" in
            mdl)
                echo "  gem install mdl"
                ;;
            shellcheck)
                echo "  dnf install ShellCheck"
                ;;
            yamllint)
                echo "  dnf install yamllint"
                ;;
            *)
                echo "  unknown tool $1"
                ;;
        esac
        exit 1
    fi
}

# markdownlint: https://github.com/markdownlint/markdownlint
# https://github.com/markdownlint/markdownlint/blob/master/docs/RULES.md
run_mdl() {
    local tool="mdl"
    local required_version="0.13.0"
    local detected_version

    echo "=====  $tool ====="

    check_tool "${tool}"

    detected_version=$("${tool}" --version)
    check_version "${detected_version}" "${required_version}" "${tool}"

    get_files ".*\.md" | grep -v -E "(DEPLOYMENT|LIGHTWEIGHT|OPENSHIFT|PLAYGROUND|STORAGE)" 2>/dev/null | xargs -0 -r "${tool}" --style "${scriptdir}/mdl-style.rb" | tee -a "${OUTPUTS_FILE}"
    echo
    echo
}

run_shellcheck() {
    local tool="shellcheck"
    local required_version="0.9.0"
    local detected_version

    echo "=====  $tool  ====="

    check_tool "${tool}"

    detected_version=$("${tool}" --version | grep "version:" | cut -d' ' -f2)
    check_version "${detected_version}" "${required_version}" "${tool}"

    get_files '.*\.(ba)?sh' | grep -v '^examples/' 2>/dev/null | xargs -0 -r "${tool}" | tee -a "${OUTPUTS_FILE}"
    echo
    echo
}

run_yamllint() {
    local tool="yamllint"
    local required_version="1.35.0"
    local detected_version

    echo "=====  $tool  ====="

    check_tool "${tool}"

    detected_version=$("${tool}" -v | cut -d' ' -f2)
    echo "detected tool: ${tool} version: ${detected_version}"
    check_version "${detected_version}" "${required_version}" "${tool}"

    # Debug: Show what files we're processing
    echo "Files found:"
    get_files '.*\.ya?ml' | grep -v -E "(^|/)(vendor|demo|testbin|third_party|\\.git)/" 2>/dev/null | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            echo "Processing: $file"
        fi
    done
    
    # Run yamllint and capture exit code
    local exit_code=0
    get_files '.*\.ya?ml' | grep -v -E "(^|/)(vendor|demo|testbin|third_party|\\.git)/" 2>/dev/null | while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            echo "$file"
        fi
    done | xargs -r "${tool}" -s -c "${scriptdir}/yamlconfig.yaml" | tee -a "${OUTPUTS_FILE}" || exit_code=$?
    
    echo "yamllint exit code: $exit_code"
    echo
    echo
}


run_mdl
run_shellcheck
# run_yamllint  # Skipped by user request

# Fail if any of the tools reported errors
(! < "${OUTPUTS_FILE}" read -r)
