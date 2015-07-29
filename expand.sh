#!/bin/bash
# Wrapper script to build files using ENV variables
#set -x

function usage () {
  echo "Usage: $0 command [args] ..."
  echo "       $0 -c <filename>"
  echo ""
  echo "This script uses the value of EXPAND_FILES as a key to dump"
  echo "env variables to files. Since newlines are not allowed in env"
  echo "variables, it converts the ascii SUB character (octal 32) to newline"
  echo "when it dumps the variables."
  echo ""
  echo "Run with the '-c' switch to convert files."
  echo ""
  echo "  $0 -c filename >> env_file"
  echo ""
}

function __cmd-check () {
  name=$1
  shift 1

  # See if the command is available, under any of the provided names
  # then define the named variable with its binary path
  for cmd in "$@"; do
    if hash "$cmd" 1>/dev/null 2>/dev/null; then
      declare -g $name="$cmd"
      return
    fi
  done
}

function cmd-check-require () {
  name=$1

  __cmd-check "$@"

  if ! [[ ${!name} ]]; then
    echo "ERROR: no \`$1' equivalent found in path"
    exit 1
  fi
}

function cmd-check () {
  name=$1

  __cmd-check "$@"

  if ! [[ ${!name} ]]; then
    echo "WARNING: no \`$1' equivalent found in path"
  fi
}


# Ensure that we have the basics installed
cmd-check-require CAT cat
cmd-check-require TR tr
cmd-check-require CUT cut
cmd-check-require DIRNAME dirname
cmd-check-require BASENAME basename
cmd-check-require GREP grep
cmd-check-require SED sed
cmd-check-require CHOWN chown 
cmd-check-require CHMOD chmod
cmd-check-require MKDIR mkdir
cmd-check-require TAR tar
cmd-check-require RM rm

# Need to have SOME arguments
if [[ $# < 1 ]]; then
  usage
  exit 1
fi

# Catch the Special Mode switches
if [[ $1 = '-c' ]]; then
  if [[ -z $2 ]]; then
    echo "ERROR: -c requires an argument"
    echo ""
    usage
    exit 1
  else
    "$CAT" $2 | "$TR" '\n' '\32'
    exit 0
  fi
fi

# Any other thing that looks like a switch will be passed to as an argument to `exec'.
# We don't want this.
if [[ $1 =~ ^- ]]; then
  echo "ERROR: \`$1' is not a valid switch"
  echo ""
  usage
  exit 1
fi




# Expand Environmental Vars into Files
#
# EXPAND_FILES is a space-delimited list, iterative over it
for var in $EXPAND_FILES; do
  # Separate into the name of the ENV variable referenced,
  # and the target file to be created/replaced
  ev=$( echo $var | "$CUT" -d '=' -f 1 )
  target=$( echo $var | "$CUT" -d '=' -f 2- )
  basedir=$( "$DIRNAME" $target )

  #Extract the metadata, if it is set
  meta=$( "$BASENAME" $target | "$GREP" -o '\[.*\]$' | "$SED" -e 's/^\[//' -e 's/\]$//' )
  file=$( echo $target | "$SED" 's/\(.*\)\[.*\]$/\1/' )

  perms=$( echo $meta | "$CUT" -d '|' -f 1)
  if echo $meta | "$GREP" '|' 1>/dev/null; then
    owner=$( echo $meta | "$CUT" -d '|' -f 2-)
  else
    owner=""
  fi

  # Sanity Check the passed permissions
  if [[ -n $perms ]] && ! [[ $perms =~ ^[01234567]+$ ]]; then
    echo "ERROR: \`$perms' is not a valid file permission"
    exit 1
  fi


  # If the referenced variable doesn't exist then skip this entry
  if [ "x${!ev}" = "x" ];then
    echo "WARN: referenced variable named \`$ev' was not found in the environment"
    continue
  fi


  # Create the parent directory
  "$MKDIR" -p $basedir

  # Dump the value to the named file, running the conversion
  echo -n ${!ev} | "$TR" "\32" "\n" > $file

  # Set the file's permissions, if applicable
  if [[ -n $perms ]]; then
    "$CHMOD" $perms $file
  fi

  # Set the file's owner, if applicable
  if [[ -n $owner ]]; then
    "$CHOWN" $owner $file
  fi

  # Unset the variable in the environment
  export -n ${ev} EXPAND_FILES
done





cmd-check S3CMD s3cmd
# Check for EXPAND_S3_KEY and EXPAND_S3_SECRET in the environment, useless otherwise
if [[ -n $S3CMD ]] && [[ -n $EXPAND_S3_KEY ]] && [[ -n $EXPAND_S3_SECRET ]]; then
  # Configure the credentials
  "$CAT" > ~/.s3cfg <<-EOF
	[default]
	access_key = $EXPAND_S3_KEY
	secret_key = $EXPAND_S3_SECRET
	EOF

  # Pull tarballs from S3
  # Space delimited list..
  for var in $EXPAND_S3_TARS; do
    # If there is no bar ("|"), the entry is invalid; move on
    if ! echo $var | grep '|' 1>/dev/null; then continue; fi

    # Separate out the tarball from its unpacking destination
    object=$( echo $var | "$CUT" -d '|' -f 1)
    targetdir=$( echo $var | "$CUT" -d '|' -f 2-)

    # We need both to be defined, move on otherwise
    if [[ -z $object ]] || [[ -z $targetdir ]]; then continue; fi

    # Create the target directory if necessary
    "$MKDIR" -p $targetdir

    # Run the extraction, overwriting files if necessary
    "$S3CMD" --force get s3://$object /expand_s3.tar
    
    # Untar it
    "$TAR" xf /expand_s3.tar -C $targetdir

    # Clean Up the original tarball
    "$RM" /expand_s3.tar
  done

  # Pull Individual files from S3
  # Space delimited list..
  for var in $EXPAND_S3_FILES; do
    # If there is no bar ("|"), the entry is invalid; move on
    if ! echo $var | grep '|' 1>/dev/null; then continue; fi

    # Separate out the s3 source from the local destination
    object=$( echo $var | "$CUT" -d '|' -f 1)
    targetfile=$( echo $var | "$CUT" -d '|' -f 2-)

    # We need both to be defined, move on otherwise
    if [[ -z $object ]] || [[ -z $targetfile ]]; then continue; fi

    # Create the containing directory, if necessary
    if [[ $targetfile =~ /^ ]]; then
      "$MKDIR" -p $targetfile
    else
      "$MKDIR" -p $("$DIRNAME" $targetfile)
    fi

    # Run the extraction
    "$S3CMD" --force get s3://$object $targetfile
  done

  # Pull Folders from S3 (trailing slash = just the contents, not the folder itself)
  # Space delimited list..
  for var in $EXPAND_S3_FOLDERS; do

    # Separate out the s3 source from the local destination
    object=$( echo $var | "$CUT" -d '|' -f 1)
    targetfolder=$( echo $var | "$CUT" -d '|' -f 2-)

    # We need both to be defined, move on otherwise
    if [[ -z $object ]] || [[ -z $targetfolder ]]; then continue; fi

    # Run the extraction
    "$S3CMD" sync -r s3://$object $targetfolder
  done

  # Remove the Credentials, Unset the Environment
  "$RM" ~/.s3cfg
  export -n EXPAND_S3_KEY EXPAND_S3_SECRET EXPAND_S3_FILES
fi





# Finally, run sed on target files
# Space delimited list..
for var in $EXPAND_SED_FILES; do
  # Separate out target file from the sed script to run on it
  target=$( echo $var | "$CUT" -d '|' -f 1)
  script=$( echo $var | "$CUT" -d '|' -f 2-)

  "$SED" -i "$target" -f "$script"
  
  export -n EXPAND_SED_FILES
done





exec "$@"
