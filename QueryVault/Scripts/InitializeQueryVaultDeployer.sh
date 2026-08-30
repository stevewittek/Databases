#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly sqlcmd_bin="${SQLCMD_BIN:-/opt/mssql-tools18/bin/sqlcmd}"
readonly admin_credential_file="${QUERYVAULT_ADMIN_CREDENTIAL_FILE:-/home/nasa/netherwood-data-partners/backend/.env.sql-setup}"
readonly credential_dir="${QUERYVAULT_CREDENTIAL_DIR:-/home/nasa/.config/queryvault-production}"
readonly credential_file="${QUERYVAULT_SQL_CREDENTIAL_FILE:-${credential_dir}/sql.env}"

if [[ ! -x "$sqlcmd_bin" ]]; then
    printf 'sqlcmd is not executable at %s\n' "$sqlcmd_bin" >&2
    exit 1
fi

if [[ -e "$credential_file" || -L "$credential_file" ]]; then
    printf 'Refusing to replace existing QueryVault credential file: %s\n' "$credential_file" >&2
    exit 1
fi

if [[ -L "$admin_credential_file" || ! -f "$admin_credential_file" ]]; then
    printf 'Protected SQL administrative credential is unavailable.\n' >&2
    exit 1
fi

admin_mode="$(stat -c '%a' "$admin_credential_file")"
if (( (8#$admin_mode & 8#077) != 0 )); then
    printf 'Administrative credential file permissions are too broad.\n' >&2
    exit 1
fi

read_encoded() {
    local key="$1"
    local encoded
    encoded="$(awk -F= -v key="$key" '$1 == key { print substr($0,index($0,"=")+1); exit }' "$admin_credential_file")"
    [[ -n "$encoded" && "$encoded" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
    printf '%s' "$encoded" | base64 --decode
}

admin_user="$(read_encoded NDP_SQL_ADMIN_USER_BASE64)"
admin_password="$(read_encoded NDP_SQL_ADMIN_PASSWORD_BASE64)"
deployer_password="$(openssl rand -base64 48 | tr -d '\n')"

install -d -m 0700 "$credential_dir"
umask 077
temporary_file="$(mktemp "${credential_file}.tmp.XXXXXX")"
cleanup() {
    unset admin_password deployer_password SQLCMDPASSWORD QueryVaultDeployerPassword
    if [[ -n "${temporary_file:-}" && -e "$temporary_file" ]]; then
        unlink "$temporary_file"
    fi
}
trap cleanup EXIT

printf '%s\n' \
    'QUERYVAULT_SQL_USER=queryvault_deployer' \
    "QUERYVAULT_SQL_PASSWORD=${deployer_password}" \
    >"$temporary_file"
chmod 0600 "$temporary_file"

export SQLCMDPASSWORD="$admin_password"
export QueryVaultDeployerPassword="$deployer_password"
"$sqlcmd_bin" \
    -S tcp:127.0.0.1,1433 -U "$admin_user" -d master \
    -N -C -b -V 16 -l 15 -t 120 \
    -i "$script_dir/ProvisionQueryVaultDeployer.sql"

mv "$temporary_file" "$credential_file"
temporary_file=''

export SQLCMDPASSWORD="$deployer_password"
"$sqlcmd_bin" \
    -S tcp:127.0.0.1,1433 -U queryvault_deployer -d QueryVaultDB \
    -N -C -b -V 16 -l 15 -t 30 \
    -Q "SET NOCOUNT ON; SELECT SUSER_SNAME() AS LoginName,DB_NAME() AS DatabaseName;"

printf 'Protected QueryVault deployment credential created: %s\n' "$credential_file"
