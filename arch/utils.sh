CONFIG_FILE="./config.conf"

function config_set() {
	if grep -Eq "^${1}.*" "${CONFIG_FILE}"; then
		sed -i -e "/^${1}.*/d" "${CONFIG_FILE}"
	fi
	echo "${1}=${2}" >> "${CONFIG_FILE}"
	source "${CONFIG_FILE}"
}
