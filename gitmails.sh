#!/bin/sh

set -e
trap "echo -e '\nAborting...'" INT

#--------------------
# Gitmails Constants
#--------------------
GITHUB_API="https://api.github.com"
GITLAB_API="https://gitlab.com/api/v4"
BITBUCKET_API="https://api.bitbucket.org/2.0"
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
	export GITLAB_PATH="$BASE_PATH/$TARGET/gitlab"
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

collect_user_info () {
	info=$(make_request "$1")
	if [ $? -ne 0 ]; then
		echoerr "gitmails: Could not collect $2 of user '$3'"
		return 1
	fi
	mkdir -p "$4"
	echo "${info}" | jq > "$4/$2"
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
	counter=0
	qtd_repos=$(expr `get_attr "$1" length` - 1)
	while [ "${counter}" -lt "${qtd_repos}" ]; do
		(
			repo=$(get_attr "$1" ".[${counter}]")
			parse_repo "${repo}" "$3" "$4" "$TMP_PATH/$2" "$5"
		) &
		pids="${pids} $!"
		true $(( counter++ ))
	done
	wait ${pids}
}

collect_repos_with_link_header_pagination () {
	result=$(make_request "$1" --head)
	qtd_pages=1
	link_header=$(echo "${result}" | grep "^Link" || true)
	if [ ! -z "${link_header}" ]; then
		qtd_pages=$(echo "${link_header}" | cut -d ',' -f2 | awk '{ gsub("'"$2"'", "\n") ; print $0 }' \
			| head -n1 | rev | cut -d '=' -f1 | rev)
	fi
	pids=""
	counter=1
	while [ "${counter}" -le "${qtd_pages}" ]; do
		repos=$(make_request "$1?page=${counter}")
		if [ $? -ne 0 ]; then
			echoerr "gitmails: Couldn't collect page ${counter} of ${qtd_pages} from $3 repositories in $4"
			continue
		fi
		parse_repos "${repos}" "$4" "$5" "$6" "$7" &
		pids="${pids} $!"
		# Sleep to wait previous clones to at least be closer to finishing
		# Hopes to avoid too many git clone processes running at the same time
		sleep 2
		true $(( counter++ ))
	done
	wait ${pids}
}

pagination_bitbucket () {
	result=$(curl --silent "$1")
	parse_repos # echo ${results} | jq .values
	while echo "${result}" | jq -re '.next'; do
		url=$(echo "${result}" | jq -re '.next')
		result=$(make_request "${url}")
		parse_repos # echo ${results} | jq .values
	done
}

# $1 = url with api endpoint to collect repos
# $2 = service_name (e.g. github)
# $3 = field of url to clone location in json to be used with jq (e.g. .clone_url)
# $4 = field of repository name to be used with jq (e.g. .name)
# $5 = path to repos location (e.g. $GITHUB_PATH/repos)
# TODO: PAGINATION
collect_repos () {
	# while pagination
	repos=$(make_request "$1")
	if [ $? -ne 0 ]; then
		echoerr "gitmails: Couldn't collect $2 repositories"
		return 1
	fi
	# get repos json from json if needed
	parse_repos "${repos}" "$2" "$3" "$4" "$5"
}

collect_github_user () {
	echo "Collecting github information for user '$1'"
	collect_user_info "$GITHUB_API/users/$1" "attributes" "$1" "$GITHUB_PATH"
	echo "Collecting github repositories for user '$1'"
	collect_repos_with_link_header_pagination "$GITHUB_API/users/$1/repos" ">" "$1" \
		"github" ".clone_url" ".name" "$GITHUB_PATH/repos"
}

collect_gitlab_user () {
	echo "Collecting gitlab information for user '$1'"
	users=$(make_request "$GITLAB_API/users?username=$1")
	userid=$(get_raw_attr "${users}" ".[0].id")
	collect_user_info "$GITLAB_API/users/${userid}" "attributes" "$1" "$GITLAB_PATH"
	collect_user_info "$GITLAB_API/users/${userid}/keys" "keys" "$1" "$GITLAB_PATH"
	collect_user_info "$GITLAB_API/users/${userid}/status" "status" "$1" "$GITLAB_PATH"
	echo "Collecting gitlab repositories for user '$1'"
	collect_repos_with_link_header_pagination "$GITLAB_API/users/${userid}/projects" "&per_page" "$1" \
		"gitlab" ".http_url_to_repo" ".name" "$GITLAB_PATH/repos"
}

collect_bitbucket_user () {
	echo "Collecting bitbucket information for user '$1'"
	collect_user_info "$BITBUCKET_API/users/$1" "attributes" "$1" "$BITBUCKET_PATH"
	echo "Collecting bitbucket repositories for user '$1'"
	# collect_repos "$BITBUCKET_API/repositories/$1" "bitbucket"
}

collect_org () {
	echo "bla"
}

main () {
	case "$TARGET_TYPE" in
		repo)
			repo_name=$(echo "$TARGET" | awk -F "://" '{print $2}' | tr '/' '_')
			analyze_repo "$TARGET" "$TMP_PATH/${repo_name}" "$REPOS_PATH/${repo_name}";;
		user)
			if $GITHUB; then
				collect_github_user "$TARGET"
			fi
			if $GITLAB; then
				collect_gitlab_user "$TARGET"
			fi;;
		org)
			collect_org  "$TARGET";;
	esac
}

check_dependencies
parse_args $@
main
