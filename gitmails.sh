#!/bin/sh

set -e
set -x
#trap bye_bye INT

USERNAME=""

SEPARATOR="|:|"

BASE_PATH="/tmp/gitmails"
GITHUB_PATH="${BASE_PATH}/github"
GILLAB_PATH="${BASE_PATH}/gitlab"
BITBUCKET_PATH="${BASE_PATH}/bitbucket"

BITBUCKET_API=""
GITHUB_API="https://api.github.com"
GITLAB_API=""

GITHUB_USER_ATTRIBUTES="login                 id                node_id           \
			avatar_url            gravatar_id       url               \
			html_url              followers_url     following_url     \
			gists_url             starred_url       subscriptions_url \
			organizations_url     repos_url         events_url        \
			received_events_url   type              site_admin        \
			name                  company           blog              \
			location email        hireable bio      public_repos      \
			public_gists          followers         following         \
			created_at updated_at"					  \

GITHUB_REPO_ATTRIBUTES="id                node_id              name               \
			full_name         private              html_url           \
			description       fork                 url                \
			forks_url         keys_url             collaborators_url  \
			teams_url         hooks_url            issue_events_url   \
			events_url        assignees_url        branches_url       \
			tags_url          blobs_url            git_tags_url       \
			git_refs_url      trees_url            statuses_url       \
			languages_url     stargazers_url       contributors_url   \
			subscribers_url   subscriptions_url    commits_url        \
			git_commits_url   comments_url         issue_comment_url  \
			contents_url      compare_url          merges_url         \
			archive_url       downloads_url        issues_url         \
			pulls_url         milestones_url       notifications_url  \
			labels_url        releases_url         deployments_url    \
			created_at        updated_at           pushed_at          \
			git_url           ssh_url              clone_url          \
			svn_url           homepage             size               \
			has_issues        has_projects         has_downloads      \
			has_wiki          has_pages            forks_count        \
			mirror_url        archived             open_issues_count  \
			forks             open_issues          watchers           \
			default_branch    license"

bye_bye () {
	echo -e "\nAborting..."
}

echoerr () {
	echo "$@" 1>&2
}

get_attr () {
	echo "$1" | jq "$2"
}

get_raw_attr () {
	echo "$1" | jq -r "$2"
}

parse_fields () {
	for f in $2; do
		field=$(echo "${f}" | tr -d '[:space:]')
		echo "${field}${SEPARATOR}$(get_attr "$1" ".${field}")"
	done
}

make_request () {
	result=$(curl --silent -w 'HTTPSTATUS:%{http_code}' "$1")
	body=$(echo "${result}" | sed -e 's/HTTPSTATUS\:.*//g')
	status_code=$(echo "${result}" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
	if [ "${status_code}" -ne 200 ]; then
		echoerr "gitmails: HTTP request returned status code ${status_code}"
		return 1
	else
		echo "${body}"
		return 0
	fi
}

analyze_repo () {
	mkdir -p "$2"
	echo "Clonning repo $1 in $2"
	git clone --quiet --bare "$1" "$2"
	(
		cd "$2"
		git log --all --format='%aN <%cE>' | sort | uniq -c | sort -bgr > "$2/unique_authors"
	)
}

collect_github_user () {
	user=$(make_request "${GITHUB_API}"/users/"$1")
	test "$?" -ne 0 && return 1
	mkdir -p "$GITHUB_PATH/users/$1"
	parse_fields "${user}" "${GITHUB_USER_ATTRIBUTES}" > "$GITHUB_PATH/users/$1/attributes"
}

#github_repo () {
#}

collect_github_repos_from_user () {
	repos=$(make_request "${GITHUB_API}/users/$1/repos")
	if [ "$?" -ne 0 ]; then
		echoerr "gitmails: Couldn't collect github repositories"
		return 1
	fi
	github_qtd_repos=$(expr `get_attr "${repos}" length` - 1)
	pids=""
	counter=0
	while [ "${counter}" -lt "${github_qtd_repos}" ]; do
		#(
		repo=$(get_attr "${repos}" ".[${counter}]")
		mkdir -p "$GITHUB_PATH/repos/${counter}"
		parse_fields "${repo}" "${GITHUB_REPO_ATTRIBUTES}" > "$GITHUB_PATH/repos/${counter}/attributes"
		repo_url=$(get_raw_attr "${repo}" ".clone_url")
		mkdir -p "$GITHUB_PATH/tmp"
		analyze_repo "${repo_url}" "$GITHUB_PATH/tmp/${counter}"
		#) &
		#pids="${pids} $!"
		true $(( counter++ ))
	done
	#wait ${pids}
}

main () {
	#collect_github_user "$USERNAME"
	collect_github_repos_from_user "$USERNAME"
}

main
