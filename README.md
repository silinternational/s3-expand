s3-expand
=========

__Note: Documentation for this script is incomplete; it can do a bit more 
than what is detailed here__

`s3-expand` is a wrapper bash shell script, intended for use in a docker
container. It provides functionality to generate and edit files:

 * Directing the contents of environmental variables into files
 * Pulling data from Amazon S3:
   * Individual files
   * Tar archives, which are extracted into a directory
   * File synchronization
 * Running `sed` on existing files

Note: for local development you can pass in these environmental variables using
docker's `--env-file` switch; see `ENV-FILE.example` for an example of what
this file might look like.

Usage
=====

    s3-expand <actual_cmd> [args ...]

`actual_cmd` is exec'ed by the wrapper once it has completed its run.
Operation is determined by the setting one or more of the following
environmental variables. If none are set, the script exec's the `actual_cmd`.

The wrapper was written under the assumption that it is run within a container
as root, and so has arbitrary ability to create files and change their owners
and modes. Consequently, it is possible that not everything will work correctly
if it is run as another user.

  * `EXPAND_FILES`
  * `EXPAND_S3_TARS`
  * `EXPAND_S3_FILES`
  * `EXPAND_S3_FOLDERS`
  * `EXPAND_SED_FOLDERS`

Details on the workings of each below.

`EXPAND_FILES`
--------------

The value of `EXPAND_FILES` must be a space-delimited list of key-value 
pairs, each separated by an equals sign. For each pair, the key is the name 
of a referenced environmental variable, and the value is the path to a new 
file, whose contents will be the current value of the referenced variable. 
All parent directories in the path will be created if they do not exist, and 
if the referenced environmental variable is not set, that particular 
key-value pair will be ignored. You can also append `[mode|]`, 
`[mode|owner]`, or `[|owner]` to the path to set the numerical file 
permissions, and/or the file owner. Since newlines are not allowed in 
environmental variables, the script will replace any ascii SUB character 
(`\032` or `\x1a`) in the the value of the referenced environmental variable 
with a newline in the created file.

So, as an example, suppose the following are set for the container:

    EXPAND_FILES= ISSUE=/etc/issue SPECIFIC=/home/foo/.bashrc[0644|foo] FORGOT=/data/my_file
    
    ISSUE=Linux, running in Docker!
    SPECIFIC=cd ~

The wrapper script will then, when the container is started, overwrite 
`/etc/issue` with "Linux, runnning in Docker!", create `/home/foo/.bashrc` with 
contents "cd ~" (no newline at the end), permissions 644 and owner 
user 'foo', and do nothing for `/data/my_file`, since FORGOT was not set.


S3 Access
---------

Three modes are available for pulling data from Amazon S3: file, sync, and
archive. Each require two other environmental variables to be set in order to
work. They are:

  * `EXPAND_S3_KEY`
  * `EXPAND_S3_SECRET`

They must be set to the AWS access key, and AWS secret key, respectively, which
have sufficent permissions to access the specified S3 targets. After use, they
will be scrubbed from the environment.

`EXPAND_S3_TARS`
----------------

The value of `EXPAND_S3_TARS` must be a space-delimited list of key-value 
pairs, each separated by a pipe (|). The key is the location of a tar archive 
in S3, in the format `bucket/path`. The value is is the directory in which 
the archive should be extracted. This target directory will be created if it 
does not already exist.

So, for example, suppose the following are set for the container:

    EXPAND_S3_TARS= DXCmEdg4gb/data.tar|/data 
yBO8IJ/homes/foo/special.tar|/home/foo/my_dir
    
    EXPAND_S3_KEY=PHGCNQMRTHQMDROKAEA2
    EXPAND_S3_SECRET=25FLQSI2P0BBLBOVUIST0W0NBM0ZG17MJV3AQVMH

The wrapper script will use the provided key and secret to grab 
s3://DXCmEdg4gb/data.tar and s3://yBO8IJ/homes/foo/special.tar, unpacking 
them into /data and /home/foo/my_dir, respectively.

Testing
=======

A simple shell testing framework is included in `tests` for verifying the
operation of the wrapper. It is designed to be run from within a container as
root; the included Dockerfile is for this purpose.

Just create an file called `env.local` with contents similar to:

    EXPAND_S3_KEY=OTGJTJBPGPXVHUKOUBTY
    EXPAND_S3_SECRET=NUId1Ar6nnQ/ah4Y27q5bskVHxhJHPipvC3kEitb

    S3_TEST_PATH=random-bucket-OyQ3Qu/randomfolder-xtyD2C

Then, to run the tests, use these commands:

    docker build -t s3-expand-testing .
    docker run --rm -it --env-file env.local s3-expand-testing

The S3 folder formed from the url `s3://$S3_TEST_PATH` will be used as a staging
area for testing the wrapper modes that pull from S3.
