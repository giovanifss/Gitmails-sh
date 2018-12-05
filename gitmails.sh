#!/bin/sh

set -e
trap "echo -e '\nAborting...'" INT

#--------------------
# Gitmails Constants
#--------------------
GITHUB_API="https://api.github.com"
GITLAB_API="https://gitlab.com/api/v4"
BITBUCKET_API="https://api.bitbucket.org/2.0"
DEPENDENCIES="tr jq awk sed cat git echo curl sort find uniq mkdir"

#------------------
# Gitmails Options
#------------------
TARGET=""
TARGET_TYPE=""

TMP_PATH=""
BASE_PATH="/tmp/gitmails"
TARGET_PATH=""
GITHUB_PATH=""
GITLAB_PATH=""
BITBUCKET_PATH=""

#----------------
# Gitmails Flags
#----------------
GITHUB=true
GITLAB=true
BITBUCKET=true


echoerr () {
	echo "$@" 1>&2
}

get_attr () {
	echo "$1" | tr '\r\n' ' ' | jq "$2"
}

get_raw_attr () {
	echo "$1" | tr '\r\n' ' ' | jq -r "$2"
}

check_second_arg () {
	if [ -z "$1" ] || [[ "$1" == "-*" ]]; then
		echoerr "error: expected argument after $2 option"
		exit 1
	fi
}

check_target () {
	if [ -z "$TARGET" ]; then
		echoerr "error: target not specified. Use -u|--user, -o|--org or -r|--repo to specify a target"
		echoerr "usage: gitmails <target> [options]"
		echoerr "use -h or --help to see available options"
		exit 2
	fi
}

set_target () {
	if [ ! -z "$TARGET" ]; then
		echoerr "gitmails: target must be specified only once"
		exit 2
	fi
	TARGET="$1"
	TARGET_TYPE="$2"
}

check_services () {
	if ! $GITHUB && ! $GITLAB && ! $BITBUCKET; then
		echoerr "error: at least one host service must be collectable"
		echoerr "specify one of --github, --gitlab or --bitbucket"
		echoerr "use -h or --help to see available options"
		exit 3
	fi
}

check_dependencies () {
	missing=false
	for dep in $DEPENDENCIES; do
		if ! command -v "${dep}" 2>&1 > /dev/null; then
			echoerr "error: missing required dependency '${dep}'"
			missing=true
		fi
	done
	${missing} && exit 4
}

set_variables () {
	if [ "$TARGET_TYPE" == "repo" ]; then
		export TMP_PATH="$BASE_PATH/tmp/repos"
		export TARGET_PATH="$BASE_PATH"
	else
		export TMP_PATH="$BASE_PATH/tmp/$TARGET"
		export TARGET_PATH="$BASE_PATH/$TARGET"
	fi
	export REPOS_PATH="$TARGET_PATH/repos"
	export GITHUB_PATH="$TARGET_PATH/github"
	export GITLAB_PATH="$TARGET_PATH/gitlab"
	export BITBUCKET_PATH="$TARGET_PATH/bitbucket"
}

display_help () {
	echo "usage: gitmails <target> [options] [flags]"
	echo
	echo "target: user, organization or repository"
	echo -e "\t-u|--user: specify a user as target"
	echo -e "\t-r|--repo: specify a repository as target"
	echo -e "\t-o|--org:  specify an organization as target"
	echo
	echo "options:"
	echo -e "\t-h|--help: display this message"
	echo -e "\t-V|--version: display version information"
	echo -e "\t-b|--base-dir: specify the base directory for gitmails to work on"
	echo
	echo "flags:"
	echo -e "\t--github: collect information only on github"
	echo -e "\t--gitlab: collect information only on gitlab"
	echo -e "\t--bitbucket: collect information only on bitbucket"
	echo -e "\t--no-github: skip information collection on github"
	echo -e "\t--no-gitlab: skip information collection on gitlab"
	echo -e "\t--no-bitbucket: skip information collection on bitbucket"
}

parse_args () {
	if [ $# -eq 0 ]; then
		display_help
		exit 1
	fi
	while [ $# -gt 0 ]; do
		case "$1" in
			-V|--version)
				echo "author: giovanifss"
				echo "source: https://github.com/giovanifss/Gitmails-sh"
				echo "license: MIT"
				echo "version: 1.0"
				exit 0;;
			-h|--help)
				display_help
				exit 0;;
			-b|--base-dir)
				check_second_arg "$2" "base-dir"
				BASE_PATH="$2"
				shift;;
			-u|--user)
				check_second_arg "$2" "user"
				set_target "$2" "user"
				shift;;
			-r|--repo)
				check_second_arg "$2" "repository"
				set_target "$2" "repo"
				shift;;
			-o|--org)
				check_second_arg "$2" "organization"
				set_target "$2" "org"
				shift;;
			--github)
				GITLAB=false
				BITBUCKET=false;;
			--gitlab)
				GITHUB=false
				BITBUCKET=false;;
			--bitbucket)
				GITHUB=false
				GITLAB=false;;
			--no-github)
				GITHUB=false;;
			--no-gitlab)
				GITLAB=false;;
			--no-bitbucket)
				BITBUCKET=false;;
			*)
				echoerr "error: unknown argument '$1'"
				echoerr "use -h or --help to see available options"
				exit 1;;
		esac
		shift
	done
	check_target
	check_services
	set_variables
}

make_request () {
	cmd="curl"
	if [ ! -z "$2" ]; then
		cmd="${cmd} $2"
	fi
	cmd="${cmd} --silent -w HTTPSTATUS:%{http_code} $1"
	result=$(${cmd})
	content=$(echo "${result}" | sed -e 's/HTTPSTATUS\:.*//g')
	status_code=$(echo "${result}" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
	if [ "${status_code}" -ne 200 ]; then
		echoerr "gitmails: HTTP request returned status code '${status_code}'"
		return 1
	else
		echo "${content}"
		return 0
	fi
}

analyze_repo () {
	mkdir -p "$2"
	mkdir -p "$3"
	echo "Clonning repo $1 in $2"
	git clone --quiet --bare "$1" "$2"
	(
		cd "$2"
		git log --all --format='%an <%ae>' | sort | uniq -c | sort -bgr > "$3/authors"
		git log --all --format='%cn <%ce>' | sort | uniq -c | sort -bgr > "$3/commiters"
		git log --all --format='%aN <%aE>' | sort | uniq -c | sort -bgr > "$3/mailmap_authors"
		git log --all --format='%cN <%cE>' | sort | uniq -c | sort -bgr > "$3/mailmap_commiters"
		git log --all --format='%GS <%GK>' | sort | uniq -c | sort -bgr > "$3/signer_info"
	)
}

count_uniques () {
	for filename in $3; do
		uniques=$(find "$1/$2" -name "${filename}" -exec cat {} \; | tr -s ' ' | cut -d ' ' -f3- | sort -u)
		IFS="$(printf '\n ')" && IFS="${IFS% }"
		for unique in ${uniques}; do
			find "$1/$2" -name "${filename}" -exec cat {} \; | grep "${unique}" | \
				awk -F ' ' '{sum+=$1} END {$1=""; sep=")"; print sum sep $0}' >> "$1/$2_${filename}"
		done
		unset IFS
	done
}

collect_info () {
	info=$(make_request "$1")
	if [ $? -ne 0 ]; then
		echoerr "gitmails: Could not collect $2 of $3 '$4'"
		return 1
	fi
	mkdir -p "$5"
	echo "${info}" | jq > "$5/$2"
}

parse_repo () {
	repo_url=$(get_raw_attr "$1" "$2")
	repo_name=$(get_raw_attr "$1" "$3" | tr '/' '_')
	mkdir -p "$4"
	mkdir -p "$5/${repo_name}"
	echo "$1" > "$5/${repo_name}/attributes"
	analyze_repo "${repo_url}" "$4/${repo_name}" "$5/${repo_name}"
}

parse_repos () {
	pids=""
	index=0
	qtd_repos=$(expr `get_attr "$1" length` - 1)
	while [ "${index}" -lt "${qtd_repos}" ]; do
		(
			repo=$(get_attr "$1" ".[${index}]")
			parse_repo "${repo}" "$3" "$4" "$TMP_PATH/$2" "$5"
		) &
		pids="${pids} $!"
		true $(( index++ ))
	done
	wait ${pids}
}

get_qtd_pages_from_link_header () {
	result=$(make_request "$1" --head)
	if [ $? -ne 0 ]; then
		echoerr "gitmails: could not collect headers from $1"
		return 1
	fi
	qtd_pages=1
	link_header=$(echo "${result}" | grep "^Link" || true)
	if [ ! -z "${link_header}" ]; then
		qtd_pages=$(echo "${link_header}" | cut -d ',' -f2 | awk '{ gsub("'"$2"'", "\n") ; print $0 }' \
			| head -n1 | rev | cut -d '=' -f1 | rev)
	fi
	echo "${qtd_pages}"
}

collect_info_with_link_header_pagination () {
	url="$1"; substr="$2"; target="$3"; info_type="$4"; service="$5"; function="$6"
	shift 6
	qtd_pages=$(get_qtd_pages_from_link_header "${url}" "${substr}")
	counter=1
	while [ "${counter}" -le "${qtd_pages}" ]; do
		content=$(make_request "${url}?page=${counter}")
		if [ $? -ne 0 ]; then
			echoerr "gitmails: couldn't collect page ${counter} of ${qtd_pages} from ${target} ${info_type} in ${service}"
			continue
		fi
		echo "Collecting page ${counter} of ${qtd_pages} of ${info_type}"
		${function} "${content}" "${service}" "$@"
		true $(( counter++ ))
	done
}

get_next_bitbucket () {
	next=$(get_raw_attr "$1" ".next")
	if [ -z "${next}" ]; then
		return 1
	fi
	echo "${next}"
}

pagination_bitbucket () {
	url="$1"; function="$2"
	shift 2
	result=$(make_request "${url}")
	if [ $? -ne 0 ]; then
		echoerr "gitmails: couldn't collect bitbucket page"
		return 1
	fi
	${function} "$(get_attr "${result}" '.values')" "$@"
	if next=$(get_next_bitbucket "${result}"); then
		pagination_bitbucket "${next}" "${function}" "$@"
	fi
}

collect_github_user () {
	echo "Collecting github information for user '$1'"
	collect_info "$GITHUB_API/users/$1" "attributes" "user" "$1" "$GITHUB_PATH"
	echo "Collecting github repositories for user '$1'"
	collect_info_with_link_header_pagination "$GITHUB_API/users/$1/repos" ">" "$1" \
		"repositories" "github" "parse_repos" ".clone_url" ".name" "$GITHUB_PATH/repos"
	count_uniques "$GITHUB_PATH" "repos" "authors commiters mailmap_authors mailmap_commiters signer_info"
}

collect_gitlab_user () {
	echo "Collecting gitlab information for user '$1'"
	users=$(make_request "$GITLAB_API/users?username=$1")
	if [ $? -ne 0 ]; then
		echoerr "gitmails: couldn't collect userid for user '$1'"
		return 1
	fi
	userid=$(get_raw_attr "${users}" ".[0].id")
	collect_info "$GITLAB_API/users/${userid}" "attributes" "user" "$1" "$GITLAB_PATH"
	collect_info "$GITLAB_API/users/${userid}/keys" "keys" "user" "$1" "$GITLAB_PATH"
	collect_info "$GITLAB_API/users/${userid}/status" "status" "user" "$1" "$GITLAB_PATH"
	echo "Collecting gitlab repositories for user '$1'"
	collect_info_with_link_header_pagination "$GITLAB_API/users/${userid}/projects" "&per_page" "$1" \
		"repositories" "gitlab" "parse_repos" ".http_url_to_repo" ".name" "$GITLAB_PATH/repos"
	count_uniques "$GITLAB_PATH" "repos" "authors commiters mailmap_authors mailmap_commiters signer_info"
}

collect_bitbucket_user () {
	echo "Collecting bitbucket information for user '$1'"
	collect_info "$BITBUCKET_API/users/$1" "attributes" "user" "$1" "$BITBUCKET_PATH"
	echo "Collecting bitbucket repositories for user '$1'"
	pagination_bitbucket "$BITBUCKET_API/repositories/$1" "parse_repos" "bitbucket" ".links.clone | .[0].href" \
		".name" "$BITBUCKET_PATH/repos"
	count_uniques "$BITBUCKET_PATH" "repos" "authors commiters mailmap_authors mailmap_commiters signer_info"
}

collect_github_org () {
	echo "Collecting github information for organization $1"
	collect_info "$GITHUB_API/orgs/$1" "attributes" "organization" "$1" "$GITHUB_PATH"
	collect_info_with_link_header_pagination "$GITHUB_API/orgs/$1/members" ">" "$1" \
		"members" "github" "parse_members" ".clone_url" ".name" "$GITHUB_PATH/members"
	echo "Collecting github repositories for organization '$1'"
	collect_info_with_link_header_pagination "$GITHUB_API/orgs/$1/repos" ">" "$1" \
		"repositories" "github" "parse_repos" ".clone_url" ".name" "$GITHUB_PATH/repos"
	count_uniques "$GITHUB_PATH" "repos" "authors commiters mailmap_authors mailmap_commiters signer_info"
}

collect_gitlab_org () {
	echo "Collecting gitlab information for organization $1"
	collect_info "$GITLAB_API/groups/$1" "attributes" "group" "$1" "$GITLAB_PATH"
	echo "Collecting gitlab repositories for group '$1'"
	collect_info_with_link_header_pagination "$GITLAB_API/groups/$1/projects" "&per_page" "$1" \
		"repositories" "gitlab" "parse_repos" ".http_url_to_repo" ".name" "$GITLAB_PATH/repos"
	count_uniques "$GITLAB_PATH" "repos" "authors commiters mailmap_authors mailmap_commiters signer_info"
}

perform_collection () {
	case "$1" in
		repo)
			repo_name=$(echo "$2" | awk -F "://" '{print $2}' | tr '/' '_')
			analyze_repo "$2" "$TMP_PATH/${repo_name}" "$REPOS_PATH/${repo_name}";;
		user)
			if $GITHUB; then
				collect_github_user "$2"
			fi
			if $GITLAB; then
				collect_gitlab_user "$2"
			fi
			if $BITBUCKET; then
				collect_bitbucket_user "$2"
			fi;;
		org)
			if $GITHUB; then
				collect_github_org "$2"
			fi
			if $GITLAB; then
				collect_gitlab_org "$2"
			fi;;
	esac
}

output_info () {
	for filename in $(find "$1" -type f -maxdepth 2 '!' -name attributes); do
		echo $(echo "${filename}" | rev | cut -d '/' -f1 | rev)
		IFS="$(printf '\n ')" && IFS="${IFS% }"
		for line in $(cat "${filename}" | sort -n); do
			echo -e "\t${line}"
		done
		unset IFS
	done
}

main () {
	perform_collection "$TARGET_TYPE" "$TARGET"
	output_info "$TARGET_PATH"
}

check_dependencies
parse_args "$@"
main
