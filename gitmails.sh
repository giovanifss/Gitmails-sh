#!/bin/sh

set -e
trap "echo -e '\nAborting...'" INT

#--------------------
# Gitmails Constants
#--------------------
BITBUCKET_API=""
GITHUB_API="https://api.github.com"
GITLAB_API=""
DEPENDENCIES="tr jq awk sed cat git echo curl sort uniq mkdir"

#------------------
# Gitmails Options
#------------------
TARGET=""
TARGET_TYPE=""

TMP_PATH=""
BASE_PATH="/tmp/gitmails"
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
	echo "$1" | jq "$2"
}

get_raw_attr () {
	echo "$1" | jq -r "$2"
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
	else
		export TMP_PATH="$BASE_PATH/tmp/$TARGET"
	fi
	export REPOS_PATH="$BASE_PATH/repos"
	export GITHUB_PATH="$BASE_PATH/$TARGET/github"
	export GILLAB_PATH="$BASE_PATH/$TARGET/gitlab"
	export BITBUCKET_PATH="$BASE_PATH/$TARGET/bitbucket"
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
	result=$(curl --silent -w 'HTTPSTATUS:%{http_code}' "$1")
	body=$(echo "${result}" | sed -e 's/HTTPSTATUS\:.*//g')
	status_code=$(echo "${result}" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
	if [ "${status_code}" -ne 200 ]; then
		echoerr "gitmails: HTTP request returned status code '${status_code}'"
		return 1
	else
		echo "${body}"
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
		git log --all --format='%GS <%GK?' | sort | uniq -c | sort -bgr > "$3/signer_info"
	)
}

collect_github_user_info () {
	user=$(make_request "${GITHUB_API}"/users/"$1")
	test "$?" -ne 0 && return 1
	mkdir -p "$GITHUB_PATH"
	echo "${user}" > "$GITHUB_PATH/attributes"
}

collect_repo () {
	repo_url=$(get_raw_attr "$1" "$2")
	repo_name=$(get_raw_attr "$1" "$3" | tr '/' '_')
	mkdir -p "$4"
	mkdir -p "$5/${repo_name}"
	echo "$1" > "$5/${repo_name}/attributes"
	analyze_repo "${repo_url}" "$4/${repo_name}" "$5/${repo_name}"
}

collect_repos () {
	repos=$(make_request "$1")
	if [ $? -ne 0 ]; then
		echoerr "gitmails: Couldn't collect $2 repositories"
		return 1
	fi
	qtd_repos=$(expr `get_attr "${repos}" length` - 1)
	pids=""
	counter=0
	while [ "${counter}" -lt "${qtd_repos}" ]; do
		(
			repo=$(get_attr "${repos}" ".[${counter}]")
			collect_repo "${repo}" "$3" "$4" "$TMP_PATH/$2" "$5"
		) &
		pids="${pids} $!"
		true $(( counter++ ))
	done
	wait ${pids}
}

collect_github_repos_from_user () {
	echo "Collecting github repositories for user $1"
	collect_repos "$GITHUB_API/users/$1/repos" "github" ".clone_url" ".name" "$GITHUB_PATH/repos"
}

collect_github_user () {
	collect_github_user_info "$TARGET"
	collect_github_repos_from_user "$TARGET"
}

collect_repo_from_url () {
	repo_name=$(echo "$1" | awk -F "://" '{print $2}' | tr '/' '_')
	analyze_repo "$1" "$TMP_PATH/${repo_name}" "$REPOS_PATH/${repo_name}"
}

collect_user () {
	if $GITHUB; then
		collect_github_user "$TARGET"
	fi
}

collect_org () {
	echo "bla"
}

main () {
	case "$TARGET_TYPE" in
		repo)
			collect_repo_from_url "$TARGET";;
		user)
			collect_user;;
		org)
			collect_org;;
	esac
}

check_dependencies
parse_args $@
main
