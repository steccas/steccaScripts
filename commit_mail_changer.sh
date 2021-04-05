#!/bin/bash
# Script to change email and username of existing commit in a repo

git filter-branch --commit-filter '
      if [ "$GIT_AUTHOR_EMAIL" = "email_to_remove" ];
      then
              GIT_AUTHOR_NAME="git_username";
              GIT_AUTHOR_EMAIL="new_git_email";
              git commit-tree "$@";
      else
              git commit-tree "$@";
      fi' HEAD

exit 0
