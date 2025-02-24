#!/bin/bash -e

	if [ "$GF_AUTH_LDAP_ENABLED" = "true" ]; then
		echo "LDAP Auth is Enabled, Generating Config File..."
		ldap_conf=${GF_AUTH_LDAP_CONFIG_FILE}
		echo "[[servers]]
		host = '${LDAP_GF_HOST}'
		port = ${LDAP_GF_PORT}
		use_ssl = ${LDAP_GF_USE_SSL}
		start_tls = ${LDAP_GF_START_TLS}
		ssl_skip_verify = ${LDAP_GF_SKIP_VERIFY}
		bind_dn = '${LDAP_GF_BIND_DN}'
		bind_password = '${LDAP_GF_BIND_PASSWORD}'
		search_filter = '${LDAP_GF_SEARCH_FILTER}'
		search_base_dns = ['${LDAP_GF_SEARCH_BASE_DNS}']
		[servers.attributes]
		name = '${LDAP_GF_NAME}'
		surname = '${LDAP_GF_SURNAME}'
		username = '${LDAP_GF_USERNAME}'
		member_of = '${LDAP_GF_MEMBER_OF}'
		email =  '${LDAP_GF_EMAIL}'
		[[servers.group_mappings]]
		group_dn = '${LDAP_GF_GROUP_DN_ADMIN}'
		org_role = '${LDAP_GF_ORG_ROLE_ADMIN}'
		[[servers.group_mappings]]
		group_dn = '${LDAP_GF_GROUP_DN_EDITOR}'
		org_role = '${LDAP_GF_ORG_ROLE_EDITOR}'
		[[servers.group_mappings]]
		group_dn = '${LDAP_GF_GROUP_DN_VIEWER}'
		org_role = '${LDAP_GF_ORG_ROLE_VIEWER}'" > $ldap_conf
		echo "Generating LDAP Config - Done!"
	else
		echo "LDAP Auth is Disable, Config Generation skipping..."
	fi

PERMISSIONS_OK=0

if [ ! -r "$GF_PATHS_CONFIG" ]; then
    echo "GF_PATHS_CONFIG='$GF_PATHS_CONFIG' is not readable."
    PERMISSIONS_OK=1
fi

if [ ! -w "$GF_PATHS_DATA" ]; then
    echo "GF_PATHS_DATA='$GF_PATHS_DATA' is not writable."
    PERMISSIONS_OK=1
fi

if [ ! -r "$GF_PATHS_HOME" ]; then
    echo "GF_PATHS_HOME='$GF_PATHS_HOME' is not readable."
    PERMISSIONS_OK=1
fi

if [ $PERMISSIONS_OK -eq 1 ]; then
    echo "You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migration-from-a-previous-version-of-the-docker-container-to-5-1-or-later"
fi

if [ ! -d "$GF_PATHS_PLUGINS" ]; then
    mkdir "$GF_PATHS_PLUGINS"
fi

if [ ! -z ${GF_AWS_PROFILES+x} ]; then
    > "$GF_PATHS_HOME/.aws/credentials"

    for profile in ${GF_AWS_PROFILES}; do
        access_key_varname="GF_AWS_${profile}_ACCESS_KEY_ID"
        secret_key_varname="GF_AWS_${profile}_SECRET_ACCESS_KEY"
        region_varname="GF_AWS_${profile}_REGION"

        if [ ! -z "${!access_key_varname}" -a ! -z "${!secret_key_varname}" ]; then
            echo "[${profile}]" >> "$GF_PATHS_HOME/.aws/credentials"
            echo "aws_access_key_id = ${!access_key_varname}" >> "$GF_PATHS_HOME/.aws/credentials"
            echo "aws_secret_access_key = ${!secret_key_varname}" >> "$GF_PATHS_HOME/.aws/credentials"
            if [ ! -z "${!region_varname}" ]; then
                echo "region = ${!region_varname}" >> "$GF_PATHS_HOME/.aws/credentials"
            fi
        fi
    done

    chmod 600 "$GF_PATHS_HOME/.aws/credentials"
fi

# Convert all environment variables with names ending in __FILE into the content of
# the file that they point at and use the name without the trailing __FILE.
# This can be used to carry in Docker secrets.
for VAR_NAME in $(env | grep '^GF_[^=]\+__FILE=.\+' | sed -r "s/([^=]*)__FILE=.*/\1/g"); do
    VAR_NAME_FILE="$VAR_NAME"__FILE
    if [ "${!VAR_NAME}" ]; then
        echo >&2 "ERROR: Both $VAR_NAME and $VAR_NAME_FILE are set (but are exclusive)"
        exit 1
    fi
    echo "Getting secret $VAR_NAME from ${!VAR_NAME_FILE}"
    export "$VAR_NAME"="$(< "${!VAR_NAME_FILE}")"
    unset "$VAR_NAME_FILE"
done

export HOME="$GF_PATHS_HOME"

if [ ! -z "${GF_INSTALL_PLUGINS}" ]; then
  OLDIFS=$IFS
  IFS=','
  for plugin in ${GF_INSTALL_PLUGINS}; do
    IFS=$OLDIFS
    grafana-cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install ${plugin}
  done
fi

exec grafana-server                                         \
  --homepath="$GF_PATHS_HOME"                               \
  --config="$GF_PATHS_CONFIG"                               \
  "$@"                                                      \
  cfg:default.log.mode="console"                            \
  cfg:default.paths.data="$GF_PATHS_DATA"                   \
  cfg:default.paths.logs="$GF_PATHS_LOGS"                   \
  cfg:default.paths.plugins="$GF_PATHS_PLUGINS"             \
  cfg:default.paths.provisioning="$GF_PATHS_PROVISIONING"
