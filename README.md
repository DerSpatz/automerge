# automerge
\"automerge\" is a tool to merge directories on different drives created by mergerfs (or a similar union filesystem) into a single directory on a single disk. It can be useful to consolidate files that belong together, like media files and their metadata, to reduce disk spin ups; or to generally clean up your filesystem.

\"automerge\" was thouroughly tested and is not designed to delete files on its own. Use this tool with caution anyways, as it applies changes to your file system structure. Use the dry-run option -d to see the actual changes before they are written to the disks.

# Installation
\"automerge\" needs to be installed into your local binary path (usually /usr/local/bin/), then it must be renamed and given execution permissions  It can then be called from the directory you want to merge.

For a simple installation, go to your binary directory (depends on your Linux distribution) and paste this command:

'''
sudo wget https://raw.githubusercontent.com/DerSpatz/automerge/main/automerge.sh -O automerge
sudo chmod +x automerge
'''

# How it works
\"automerge\" will take the input path, check if any similar paths exist on any other drive
except the system drive, and add all existing branches into a list. It will then check
additional sources (if specified) for additional branches to merge.

\"automerge\" then shows a list of all branches found, and the user can select the target
branch where all the other branches will be moved. Target branch selection can be auto-
mated to select the branch with the most free space on its drive (to reduce disk usage)
or the branch which already has the largest size (to reduce disk writes).

If not automated, \"automerge\" will ask the user for confirmation before moving the
branches using rsync. Finally it will delete all directories that are now empty.

\"automerge\" can also be set up to run in a parent directory, and check all sub-directories
as individual input paths. This is useful if you want to automerge many directories at the
same time, but not handle all directories together as a single entity.

\"automerge\" is able to create possible new branches if it finds a branch in an addtional
source that does not have a corresponding target branch on the additional source drive, yet.

# Additional controls
automerge accepts the following parameters:

| Parameter | Effect |
|----------------------|--------|
|  -d\|--dry-run | make a dry run without writing any real changes |
| -p\|--custom-path [path]  | automerge will not run in the current path, but in the specified custom path |
| -a\|--add-source  [path]  | adds an additional path to the branches  |
| -c\|--create-branches | automerge creates additional optional branches if an additonal source path is specified |
| -r\|--recursion-depth [#] | takes a number as recursion depth level automerge will run through all directories of the specifed level. Standard is 0, so the current directory will be automerged |
| -m\|--most-free-space | automatically select the branch with the most free space on its drive |
| -l\|--largest-branch | automatically select the largest existing branch; -m and -l can not be used at the same time |
| -h\|--help | shows a help text |
