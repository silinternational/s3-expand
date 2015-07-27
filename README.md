s3-expand
=========

expand.sh
---------

__Note: Documentation for this script is incomplete; it can do a bit more than what is detailed here__

`expand.sh` is a wrapper, run before the CMD. It can create files in the container by extracting data from other environmental
variables, and/or pulling and unpacking tar archives from S3.

Operation is determined by the setting the following environmental variables. If neither are set, the script merely just runs
the main CMD.

  * `EXPAND_FILES`
  * `EXPAND_S3_TARS`

The value of `EXPAND_FILES` must be a space-delimited list of key-value pairs, each separated by an equals sign. For each pair,
the key is the name of a referenced environmental variable, and the value is the path to a new file, whose contents will be the
current value of the referenced variable. All parent directories in the path will be created if they do not exist, and if the
referenced environmental variable is not set, that particular key-value pair will be ignored. You can also append `[mode|]`,
`[mode|owner]`, or `[|owner]` to the path to set the numerical file permissions, and/or the file owner. Since newlines are not
allowed in environmental variables, the script will replace any ascii SUB character (`\032` or `\x1a`) in the the value of the
referenced environmental variable with a newline in the created file.

So, as an example, suppose the following are set for the container:

    EXPAND_FILES= ISSUE=/etc/issue SPECIFIC=/home/foo/.bashrc[0644|foo] FORGOT=/data/my_file
    
    ISSUE=Linux, running in Docker!
    SPECIFIC=cd ~

The wrapper script will then, when the container is started, overwrite /etc/issue with "Linux, runnning in Docker!",
create /home/foo/.bashrc with contents "cd ~" (no newline at the end) and permissions 644 and the owner user 'foo',
and do nothing for /data/my_file, since FORGOT was not set.


The value of `EXPAND_S3_TARS` must be a space-delimited list of key-value pairs, each separated by a pipe (|). The key is the
location of a tar archive in S3, in the format `bucket/path`. The value is is the directory in which the archive should be
extracted. This target directory will be created if it does not already exist.

If set, `EXPAND_S3_TARS` requires two other environmental variables to be set in order to work. They are:

  * EXPAND_S3_KEY
  * EXPAND_S3_SECRET

So, for example, suppose the following are set for the container:

    EXPAND_S3_TARS= DXCmEdg4gb/data.tar|/data yBO8IJ/homes/foo/special.tar|/home/foo/my_dir
    
    EXPAND_S3_KEY=PHGCNQMRTHQMDROKAEA2
    EXPAND_S3_SECRET=25FLQSI2P0BBLBOVUIST0W0NBM0ZG17MJV3AQVMH

The wrapper script will use the provided key and secret to grab s3://DXCmEdg4gb/data.tar and s3://yBO8IJ/homes/foo/special.tar,
unpacking them into /data and /home/foo/my_dir, respectively.


You can pass in these environmental variables using docker's `--env-file` switch; see `ENV-FILE.example` for an example
of what this file might look like.
