s3-expand
=========

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
    s3-expand -c <filename>

`actual_cmd` is exec'ed by the wrapper once it has completed its run.
Operation is determined by the setting one or more of the following
environmental variables. If none are set, the script exec's the `actual_cmd`.

  * `EXPAND_FILES`
  * `EXPAND_SED_FILES`
  * `EXPAND_S3_TARS`
  * `EXPAND_S3_FILES`
  * `EXPAND_S3_FOLDERS`

Details on the workings of each are in the following sections.

The wrapper was written under the assumption that it is run within a container
as root, and so has arbitrary ability to create files and change their owners
and modes. Consequently, it is possible that not everything will work correctly
if it is run as another user.

The second form runs the script as an conversion utility to translate all the
newlines in a file to octal 032, which can then be placed into ENV variables for
use with the `EXPAND_FILES` mode.

`EXPAND_FILES`
--------------

The value of `EXPAND_FILES` must be a space-delimited list of key-value 
pairs, each separated by an equals sign (`=`). For each pair, the key is the
name of a referenced environmental variable, and the value is the path to a new
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

`EXPAND_SED_FILES`
------------------

The value of `EXPAND_SED_FILES` must be a space-delimited list of key-value 
pairs, each separated by a pipe (`|`). The key is the path to an existing file,
while the value is the path to a sed script.

`sed -i "<key>" -f "<value>"` will be run for every key-value pair.

Suppose the following ENV variable is set for the container:

    EXPAND_SED_FILES="/etc/issue|/data/issue.sed"

Given that `/etc/issue` already exists, with contents:

    Ubuntu 14.04.2 LTS \n \l
    

...and that `/data/issue.sed` has previously been placed into the container, with
contents:

    1s/$/ \n \t/

The wrapper will run `sed`, and the result contents of `/etc/issue` will be:

    Ubuntu 14.04.2 LTS \n \l \n \t
    

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

`EXPAND_S3_FILES`
----------------

The value of `EXPAND_S3_FILES` must be a space-delimited list of key-value 
pairs, each separated by a pipe (`|`). The key is the location of a file in S3,
in the format `bucket/path-to-file`. The value is the path where the file
should be placed, either a filename, or a directory (if ending with a `/`).
Parent directories will be created if they do not already exist.

Suppose the following ENV variable is set for the container (in addition to the
S3 credentials):

    EXPAND_S3_FILES="DXCmEdg4gb/database.sql|/archive.sql yBO8IJ/homes/foo/authorized_keys|/home/foo/.ssh/"

The wrapper will pull the files thus:

    s3://DXCmEdg4gb/database.sql          -> /archive.sql
    s3://yBO8IJ/homes/foo/authorized_keys -> /home/foo/.ssh/authorized_keys

`EXPAND_S3_TARS`
----------------

The value of `EXPAND_S3_TARS` must be a space-delimited list of key-value 
pairs, each separated by a pipe (`|`). The key is the location of a tar archive 
in S3, in the format `bucket/path-to-archive`. The value is is the directory in
which the archive should be extracted. This target directory will be created if
it does not already exist.

Suppose the following ENV variable is set for the container (in addition to the
S3 credentials):

    EXPAND_S3_TARS="DXCmEdg4gb/data.tar|/data yBO8IJ/homes/foo/special.tar|/home/foo/my_dir/"

Given contents of `data.tar`:

    toplevelfile
    newdir/
    newdir/foo
    newdir/bar

Given contents of `special.tar`:

    a
    b
    c

The wrapper will extract the archives thus:

    s3://DXCmEdg4gb/data.tar          -> /data/toplevelfile
                                      -> /data/newdir/foo
                                      -> /data/newdir/bar

    s3://yBO8IJ/homes/foo/special.tar -> /home/foo/my_dir/a
                                      -> /home/foo/my_dir/b
                                      -> /home/foo/my_dir/c
`EXPAND_S3_FOLDERS`
-------------------

The value of `EXPAND_S3_FOLDERS` must be a space-delimited list of key-value 
pairs, each separated by a pipe (`|`). The key is the location of a folder in
S3, in the format `bucket/path-to-folder`. The value is the path to a directory
(which will be created if it does not already exist.

If the key ends in a slash (`/`), the _contents_ of the S3 folder will be
synchronized; if it does not end in slash, the S3 folder itself will be
synchronized in the target directory

Suppose the following ENV variable is set for the container (in addition to the
S3 credentials):

    EXPAND_S3_FILES="DXCmEdg4gb/proj|/data yBO8IJ/homes/foo/|/home/foo"

Given that the folder layout in S3 is:

    s3://DXCmEdg4gb/proj/Makefile
    s3://DXCmEdg4gb/proj/source.c
    s3://DXCmEdg4gb/proj/source.h

    s3://yBO8IJ/homes/foo/.ssh/
    s3://yBO8IJ/homes/foo/.ssh/authorized_keys

The wrapper will synchronize thus:

    s3://DXCmEdg4gb/proj/Makefile              -> /data/proj/Makefile
    s3://DXCmEdg4gb/proj/source.c              -> /data/proj/source.c
    s3://DXCmEdg4gb/proj/source.h              -> /data/proj/source.h

    s3://yBO8IJ/homes/foo/.ssh/authorized_keys -> /home/foo/.ssh/authorized_keys

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
    docker run --rm -it --env-file env.local s3-expand-testing bash

The S3 folder formed from the url `s3://$S3_TEST_PATH` will be used as a staging
area for testing the wrapper modes that pull from S3.
