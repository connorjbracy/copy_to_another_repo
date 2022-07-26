#!/bin/sh

set -e
set -x

################################################################################
####################### Construct/Validate Basic Inputs ########################
################################################################################
echo "##### Construct/Validate Basic Inputs"
if [ -z "$INPUT_SOURCE_TARGET" ]; then
  echo "Source target file/directory to be copied must be defined (see GitHub Actions argument 'source_target')"
  return 1
fi

if [ -z "$INPUT_DESTINATION_REPO" ]; then
  echo "Destination repository must be defined (see GitHub Actions argument 'destination_repo')"
  return 1
fi

# Input arguments with default values
INPUT_GIT_SERVER=${INPUT_GIT_SERVER:-"github.com"}
INPUT_DESTINATION_BRANCH=${INPUT_DESTINATION_BRANCH:-"$GITHUB_HEAD_REF"}
INPUT_DESTINATION_FOLDER=${INPUT_DESTINATION_FOLDER:-"."}

echo "Copying target: '$INPUT_SOURCE_TARGET'"
echo "From source repo: '$GITHUB_REPOSITORY'"
echo "To destination repo: '$INPUT_DESTINATION_REPO'"
echo "Under destination branch: '$INPUT_DESTINATION_BRANCH'"

################################################################################
############################# Checkout Target Repo #############################
################################################################################
echo "##### Checkout Target Repo"
######################## Clone Target Repo to a tmp Dir ########################
TARGET_REPO_DIR="$(mktemp -d)"
DESTINATION_PATH="$(realpath "$TARGET_REPO_DIR"/"$INPUT_DESTINATION_FOLDER")"

echo "Cloning destination git repository..."
git config --global user.email "$INPUT_USER_EMAIL"
git config --global user.name "$INPUT_USER_NAME"
git clone "https://x-access-token:$INPUT_REPO_LEVEL_SECRET@$INPUT_GIT_SERVER/$INPUT_DESTINATION_REPO.git" "$TARGET_REPO_DIR"

################### Find the Base Ref Branch in Target Repo ####################
echo "Determining if target repo has branch target branch name already..."
TARGET_ORIGIN_BRANCH_NAME="origin/$INPUT_DESTINATION_BRANCH"
TARGET_REMOTE_ORIGIN_BRANCH_NAME="remotes/$TARGET_ORIGIN_BRANCH_NAME"
echo "Looking for '$INPUT_DESTINATION_BRANCH' in origin..."
TARGET_ORIGIN_HEAD_REF="$(                                       \
  git -C "$TARGET_REPO_DIR" branch -a                            \
  | sed -nr "s|^\s*($TARGET_REMOTE_ORIGIN_BRANCH_NAME)\s*$|\1|p" \
)"
######## Checkout Existing Base Ref Branch or Create New with Same Name ########
if [ "$TARGET_ORIGIN_HEAD_REF" ]; then
  echo "Found $TARGET_ORIGIN_HEAD_REF, pushing to existing branch!"
  echo "Switching to target repo's branch..."
  git -C "$TARGET_REPO_DIR"                                      \
      switch -c "$INPUT_DESTINATION_BRANCH" "$TARGET_ORIGIN_HEAD_REF"
else
  echo "Did not find $TARGET_ORIGIN_BRANCH_NAME, starting a new branch!"
  echo "Creating a new branch for the target repo..."
  git -C "$TARGET_REPO_DIR" checkout -b "$INPUT_DESTINATION_BRANCH"
fi

################################################################################
################################# Copy Target ##################################
################################################################################
echo "##### Copy File(s)"
echo "Copying contents of '$GITHUB_REPOSITORY@$GITHUB_HEAD_REF:$INPUT_SOURCE_TARGET'..."
echo "To destination '$INPUT_DESTINATION_REPO@$INPUT_DESTINATION_BRANCH:$DESTINATION_PATH'..."
mkdir -p "$DESTINATION_PATH"
if [ -z "$INPUT_USE_RSYNC" ]; then
  if [ -d "$INPUT_SOURCE_TARGET" ]; then
    # If we our copy target is a directory, the combination of the flag 'a'
    # and the trailing '.' are needed to copy the contents into the target
    # directory without copying to a subdirectory with the same name as the
    # source target. E.g.,
    #   "cp -a <path>/."
    INPUT_SOURCE_TARGET="$(realpath "$INPUT_SOURCE_TARGET")/."
  fi
  cp -av "$INPUT_SOURCE_TARGET" "$DESTINATION_PATH"
else
  echo "rsync mode detected"
  # TODO: Test if a modification like what is done above for 'cp' is needed for
  #       'INPUT_SOURCE_TARGET' when using rsync.
  rsync -avrh "$INPUT_SOURCE_TARGET" "$DESTINATION_PATH"
fi

cd "$TARGET_REPO_DIR"

if [ -z "$INPUT_COMMIT_MESSAGE" ]; then
  INPUT_COMMIT_MESSAGE="Update from https://$INPUT_GIT_SERVER/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
fi

echo "Adding git commit"
git add .
if git status | grep -q "Changes to be committed"; then
  git commit --message "$INPUT_COMMIT_MESSAGE"
  echo "Pushing git commit"
  git push -u origin HEAD:"$INPUT_DESTINATION_BRANCH"
else
  echo "No changes detected"
fi
