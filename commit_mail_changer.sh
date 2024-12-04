#!/bin/bash
# Script to change email and username of existing commit in a repo

usage() {
    echo "Usage: $0 [-h] -o <old_email> -n <new_email> -u <new_username>"
    echo "Options:"
    echo "  -h    Show this help message"
    echo "  -o    Old email address to replace"
    echo "  -n    New email address"
    echo "  -u    New git username"
    exit 1
}

# Parse arguments
while getopts "ho:n:u:" opt; do
    case $opt in
        h)
            usage
            ;;
        o)
            OLD_EMAIL="$OPTARG"
            ;;
        n)
            NEW_EMAIL="$OPTARG"
            ;;
        u)
            NEW_USERNAME="$OPTARG"
            ;;
        \?)
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$OLD_EMAIL" ] || [ -z "$NEW_EMAIL" ] || [ -z "$NEW_USERNAME" ]; then
    echo "Error: Missing required arguments"
    usage
fi

# Validate email format
email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
if ! [[ "$OLD_EMAIL" =~ $email_regex ]] || ! [[ "$NEW_EMAIL" =~ $email_regex ]]; then
    echo "Error: Invalid email format"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Show what will be changed
echo "The following changes will be made:"
echo "Old email: $OLD_EMAIL"
echo "New email: $NEW_EMAIL"
echo "New username: $NEW_USERNAME"
echo
read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

# Perform the change
git filter-branch --env-filter "
    if [ \"\$GIT_AUTHOR_EMAIL\" = \"$OLD_EMAIL\" ]; then
        export GIT_AUTHOR_NAME=\"$NEW_USERNAME\"
        export GIT_AUTHOR_EMAIL=\"$NEW_EMAIL\"
    fi
    if [ \"\$GIT_COMMITTER_EMAIL\" = \"$OLD_EMAIL\" ]; then
        export GIT_COMMITTER_NAME=\"$NEW_USERNAME\"
        export GIT_COMMITTER_EMAIL=\"$NEW_EMAIL\"
    fi
" --tag-name-filter cat -- --branches --tags

echo
echo "Changes completed. Please verify the changes and force push if needed."
echo "To push changes: git push --force --all"
echo "To push tags: git push --force --tags"

exit 0
