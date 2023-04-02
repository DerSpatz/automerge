#!/bin/bash

# automerge - written by Bastian Mohing using ChatGPT
# 
# Automerge is a tool to merge directories on different drives created by mergerfs into a single directory on a single disk
# It can be useful to consolidate files that belong together, like media files and their metadata, to reduce disk spin ups
# 
# Use this tool with caution, as it applies changes to you file system structure. 
# Use the dry-run option -d to see the actual changes before they are written to th disks.
#
# For more information, run automerge -h or automerge --help.
# 
# Automerge needs to be installed into you local binary path (usually /usr/local/bin/) and can then be called from the directory you want to merge.
#
# automerge is released under the MIT license:
# 
# MIT License
# 
# Copyright (c) 2023 DerSpatz

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

### START OF THE SCRIPT ###

# Get the current directory name and path
base_path=$(pwd)

# Set default values for flags
largest_branch=false
most_free_space=false
dry_run=false
create_branches=false
recursion_depth=0

# Declare array for additional source directories
declare -a add_source_dirs

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    # Show help
    -h|--help)
	  echo ""
      echo "automerge - written by Bastian Mohing using ChatGPT"
      echo ""
      echo "\"automerge\" is a tool to merge directories on different drives created by mergerfs"
      echo "(or a similar union filesystem) into a single directory on a single disk."
      echo "It can be useful to consolidate files that belong together, like media files and their"
      echo "metadata, to reduce disk spin ups; or to generally clean up your filesystem."
      echo ""
      echo "\"automerge\" was thouroughly tested and is not designed to delete files on its own."
      echo "Use this tool with caution anyways, as it applies changes to your file system structure."
      echo "Use the dry-run option -d to see the actual changes before they are written to the disks."
      echo ""
      echo "\"automerge\" needs to be installed into your local binary path (usually /usr/local/bin/) and"
      echo "can then be called from the directory you want to merge."
      echo ""
      echo "\"automerge\" will take the input path, check if any similar paths exist on any other drive"
      echo "except the system drive, and add all existing branches into a list. It will then check"
      echo "additional sources (if specified) for additional branches to merge."
      echo ""
      echo "\"automerge\" then shows a list of all branches found, and the user can select the target"
      echo "branch where all the other branches will be moved. Target branch selection can be auto-"
      echo "mated to select the branch with the most free space on its drive (to reduce disk usage)"
      echo "or the branch which already has the largest size (to reduce disk writes)."
      echo ""
      echo "If not automated, \"automerge\" will ask the user for confirmation before moving the"
      echo "branches using rsync. Finally it will delete all directories that are now empty."
      echo ""
      echo "\"automerge\" can also be set up to run in a parent directory, and check all sub-directories"
      echo "as individual input paths. This is useful if you want to automerge many directories at the"
      echo "same time, but not handle all directories together as a single entity."
      echo ""
      echo "\"automerge\" is able to create possible new branches if it finds a branch in an addtional"
      echo "source that does not have a corresponding target branch on the additional source drive, yet."
      echo ""
      echo "automerge is released under the MIT license."
      echo ""
      echo "automerge accepts the following parameters:"
      echo ""
      echo " +------------------------------+------------------------------------------------------+"
      echo " |   -d|--dry-run               |   make a dry run without writing any real changes    |"
      echo " |                              |                                                      |"
      echo " |   -p|--custom-path [path]    |   automerge will not run in the current path,        |"
      echo " |                              |   but in the specified custom path                   |"
      echo " |                              |                                                      |"
      echo " |   -a|--add-source  [path]    |   adds an additional path to the branches            |"
      echo " |                              |                                                      |"
      echo " |   -c|--create-branches       |   automerge creates additional optional branches     |"
      echo " |                              |   if an additonal source path is specified           |"
      echo " |                              |                                                      |"
      echo " |   -r|--recursion-depth [#]   |   takes a number as recursion depth level            |"
      echo " |                              |   automerge will run through all directories of      |"
      echo " |                              |   the specifed level. Standard is 0, so the          |"
      echo " |                              |   current directory will be automerged               |"
      echo " |                              |                                                      |"
      echo " |   -m|--most-free-space       |   automatically select the branch with the most      |"
      echo " |                              |   free space on its drive                            |"
      echo " |                              |                                                      |"
      echo " |   -l|--largest-branch        |   automatically select the largest existing branch   |"
      echo " |                              |   -m and -l can not be used at the same time         |"
      echo " |                              |                                                      |"
	  echo " |   -h|--help                  |   shows this help text                               |"
      echo " +------------------------------+------------------------------------------------------+"
      echo ""
      exit 0
      ;;

    # Sets a custom base bath if the automerge script should not run in the directory it was executed in
    -p|--custom-path)
      if [[ -d "$2" ]]; then
        base_path=("$2")
      else
        echo "Error: $2 is not a directory. Run automerge -h for help."
        exit 1
      fi
      shift
      ;;

    # Automatically select the branch with the largest directory size
    -l|--largest-branch)
      largest_branch=true
      ;;

    # Automatically select the branch with most free space on the drive
    -m|--most-free-space)
      most_free_space=true
      ;;

    # Create directories on the drives of additional sources that don't have a branch yet
    -c|--create-branches)
      create_branches=true
      ;;

    # Add additional source paths
    -a|--add-source)
      if [[ -d "$2" ]]; then
        add_source_dirs+=("$2")
      else
        echo "Error: $2 is not a directory. Run automerge -h for help."
        exit 1
      fi
      shift
      ;;

    # Select the subfolder level that should be merged
    -r|--recursion_depth)
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        recursion_depth="$2"
        if (( recursion_depth < 0 )); then
          echo "Error: recursion depth must be 0 or higher. Run automerge -h for help."
          exit 1
        fi
      else
        echo "Error: recursion depth must be an integer. Run automerge -h for help."
        exit 1
      fi
      shift
      ;;

    # Only do a dry run: no files will be moved and no directories will be deleted except the directories created by --create_branches
    -d|--dry-run)
      dry_run=true
      ;;

    # Abort on unknown input parameter
    *)
      echo "Error: unrecognized option $1. Run automerge -h for help."
      exit 1
      ;;
  esac
  shift
done


# Check if both -l and -m are used
if [[ "$largest_branch" == true && "$most_free_space" == true ]]; then
  echo "Error: -l and -m cannot be used together. Run automerge -h for help."
  exit 1
fi

# Function to get a list of UUIDs of all the drives in the system
get_drives() {
  # Declare array for drives
  declare -a drives

  # Get the UUID of the system partition
  system_uuid=$(lsblk -no UUID "$(mount | grep ' / ' | cut -d ' ' -f 1)")

  # Read the list of filesystems from /etc/fstab
  while read -r line; do
    # Ignore lines starting with "#" in fstab
    if [[ ${line:0:1} != "#" ]]; then
      # Check if the line contains /srv/dev-disk-by-uuid
      if [[ $line == *"/srv/dev-disk-by-uuid-"* ]]; then
        # Extract the UUID from the line
        uuid=$(echo "$line" | awk '{print $1}' | awk -F '/' '{print $5}')

        # Check if the UUID is not the same as the system UUID
        if [[ $uuid != "$system_uuid" ]]; then
          # Add the UUID to the array of drives
          drives+=("$uuid")
        fi
      fi
    fi
  done < /etc/fstab

  # Return the array of drive UUIDs
  echo "${drives[@]}"
}

# Function to get all the branches of an existing path
get_branches() {
  local path="$1"
  # Trim the first part of the path
  local trimmed_path="${path#/srv/*/}"
  local drives=($(get_drives))
  local branches=()

  # Create the branches using the trimmed path and the UUIDs
  for drive in "${drives[@]}"; do
    local drive_path="/srv/dev-disk-by-uuid-$drive/$trimmed_path"
    if [[ -d "$drive_path" ]]; then
      branches+=("$drive_path")
    fi
  done

  printf '%s\n' "${branches[@]}"
}

# Convert a long path (/srv/dev-disk-by-uuid-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/) into a a shorter path (dev/sdxy/) for better readability
get_device() {
    local path="$1"
    local dev_path=$(df -P "$path" | awk 'NR==2{print $1}')
    local dev_name=$(basename "$dev_path")
    local dev_dir=$(dirname "$dev_path")
    echo "${dev_dir}/${dev_name}/$(echo "$path" | sed "s|^/[^/]*/[^/]*/||")"
}

# Main function that merges the branches depending on user input
merge() {
  # Empty arrays for the next run
  additional_branches=()
  base_path=()
  clear
  input_path="$1"
  input_path_trimmed="${input_path#/srv/*/}"
  
  # Check for additional source directories first, so empty branches can be created
  if [[ ${#add_source_dirs[@]} -gt 0 ]]; then
    for dir in "${add_source_dirs[@]}"; do
      additional_branches+=("$(get_branches "$dir$(basename "$1")")")
      if [[ ${#additional_branches[@]} -gt 0 ]]; then
        # Get base path for the additional branches
        base_path+="$(echo "${additional_branches[0]}" | sed -E 's/\/([^\/]*)\/[^\/]*\/?$/\/\1\//')"
	  fi
	done
  fi
  
  # Empty the array if only an empty item is stored
  if [[ "${additional_branches[@]}" == "" ]]; then
    additional_branches=()
  fi

  # Print dry-run message
  if [[ "$dry_run" == true ]]; then
    printf "\n\e[31m!!! DRY RUN !!! NO ACTUAL CHANGES WILL BE MADE TO THE FILE SYSTEMS.\e[0m"
    printf "\n"
    printf "\n"
  fi
  
  # Create new branches on drives where additional sources are located, so they will be added to the main branches
  if [[ "$base_path" != "" ]] && [[ "$create_branches" = true ]]; then
    for num_new_branch in "${!additional_branches[@]}"; do
      new_branch_drive=$(echo "${additional_branches[$num_new_branch]}" | sed -e 's/^\(\/[^\/]*\/[^\/]*\/\).*/\1/')
	  if [[ "$new_branch_drive" != "" ]]; then
	    new_branch_path="$new_branch_drive$input_path_trimmed"
	    if [[ ! -d $new_branch_path ]]; then
	      new_branches+=("$new_branch_path")
	      mkdir -p "$new_branch_path"
	    fi
	  fi
    done
  fi
  
  

  # Get main branches from the given path
  mapfile -t main_branches < <(get_branches "$input_path")

  # Print header for main branches
  printf "Main branches:\n"
  printf "\n"
  printf " # | Used / Total space | Branch size | Branch path\n"
  printf -- "---+-$(printf -- '-%.0s' {1..18})-+-$(printf -- '-%.0s' {1..11})-+-$(printf -- '-%.0s' {1..60})-\n"

  # Loop through the main branches and print the enumerated chart
  for num_main_branch in "${!main_branches[@]}"; do
    branch="${main_branches[$num_main_branch]}"
    size=$(du -hs "$branch" | awk '{print $1}')
    total_size=$(df -h "$branch" | awk 'NR==2 {print $2}')
    used_space=$(df -h "$branch" | awk 'NR==2 {print $3}')
    path=$(get_device "$branch")
    printf "%*s | %*s / %*s | %*s | %s\n" 2 "$num_main_branch" 7 "$used_space" 8 "$total_size" 11 "$size" "$path"
  done
  printf "\n"
  printf "\n"
  
  # Check if additional sources are available
  num_additional_branch=-1
  if [[ "${#additional_branches[@]}" -gt 0 ]]; then
    if [[ "$base_path[@]" != "" ]]; then
      # Print header for additional branches
      printf "Additional source directory: %s\n" "${add_source_dirs[@]}"
      printf "\n"
      printf " # | Used / Total space | Branch size | Branch path\n"
      printf -- "---+-$(printf -- '-%.0s' {1..18})-+-$(printf -- '-%.0s' {1..11})-+-$(printf -- '-%.0s' {1..60})-\n"
  
      # Loop through the additional branches and print the enumerated chart for them
      num_additional_branch=-1
      for num_additional_branch in "${!additional_branches[@]}"; do
        branch="${additional_branches[$num_additional_branch]}"
  	    if [[ "$branch" != "" ]]; then
          size=$(du -hs "$branch" | awk '{print $1}')
          total_size=$(df -h "$branch" | awk 'NR==2 {print $2}')
          used_space=$(df -h "$branch" | awk 'NR==2 {print $3}')
          path=$(get_device "$branch")
          printf "%*s | %*s / %*s | %*s | %s\n" 2 "" 7 "$used_space" 8 "$total_size" 11 "$size" "$path"
	    fi
      done
      printf "\n"
      printf "\n"
	fi
  fi
  
  # Exit function if only the original branch exists
  if [[ num_main_branch -eq 0 && num_additional_branch -eq -1 ]] && [[ "$most_free_space" = false && "$largest_branch" = false ]]; then
	echo "No directories need to be merged."
	echo ""
    read -n 1 -s -r -p "Press any key to continue..."
	printf "\n"
	printf "\n"
    return 0
  fi

  # Determine target branch
  if [[ "$largest_branch" == true ]]; then
    # Select the main branch with the largest size on disk
	target_branch=$(printf '%s\0' "${main_branches[@]}" | du -0s --files0-from=- | sort -zn | tail -z -n1 | cut -z -f2-)
  elif [[ "$most_free_space" == true ]]; then
    # Select the main branch with the most free space on disk
	target_branch=$(printf '%s\0' "${main_branches[@]}" | xargs -0 df | sort -nk4 | tail -1 | awk '{print $6}')
    # Get the full path to the target branch
    for branch in "${main_branches[@]}"; do
      if [[ "$(df -P "$branch" | awk 'NR==2 {print $6}')" == "$target_branch" ]]; then
        target_branch="$branch"
        break
      fi
    done
  else
    # Automatically select target branch if only one main branch exists
    if [[ num_main_branch -eq 0 ]]; then
	  target_branch_index=0
    else
      while true; do
	    # Ask user to select target branch
	    read -p "Enter the number of the target branch: " target_branch_index
	    echo ""
	    # Check if input is a valid number between 0 and num_main_branch
	    if [[ "$target_branch_index" =~ ^[0-9]+$ ]] && ((target_branch_index >= 0 && target_branch_index <= num_main_branch)); then
	  	  break
	    else
	      echo "Invalid input. Please enter a number between 0 and $num_main_branch."
	      echo ""
	    fi
	  done
    fi
  target_branch="${main_branches[$target_branch_index]}"
  fi

  echo "The selected target is: $(get_device "$target_branch")"
  echo ""

  # Declare array for branches to move
  declare -a branches_to_move

  # Add all main branches, except target branch, to the list of branches to move
  for i in "${!main_branches[@]}"; do
    if [[ "${main_branches[$i]}" != "$target_branch" ]]; then
      branches_to_move+=("${main_branches[$i]}")
    fi
  done

  # Add additional source branches automatically if largest_branch=true or most_free_space=true
  if [[ "$base_path" != "" ]]; then
    if [[ "$largest_branch" == true || "$most_free_space" == true ]]; then
      additional_branches=()
      for dir in "${add_source_dirs[@]}"; do
        additional_branches+=("$(get_branches "$dir$(basename "$1")")")
      done
      for branch in "${additional_branches[@]}"; do
        if [[ "$branch" != "$target_branch" ]]; then
          branches_to_move+=("$branch")
        fi
      done
    else
      # Ask user for confirmation to add additional source branches
      for dir in "${add_source_dirs[@]}"; do
        read -p "Do you want to move the branches from directory $dir? [Y/n] " confirm
		echo ""
        if [[ "$confirm" == "Y" || "$confirm" == "y" ]]; then
          additional_branches=("$(get_branches "$dir$(basename "$1")")")
          for branch in "${additional_branches[@]}"; do
            if [[ "$branch" != "$target_branch" ]]; then
              branches_to_move+=("$branch")
            fi
          done
        fi
      done
	fi
  fi

  # Calculate the total size of all branches that will be moved
  total_size=0
  for branch in "${branches_to_move[@]}"; do
    if [[ "$branch" != "" ]]; then
      size=$(du -sb "$branch" | awk '{print $1}')
      total_size=$((total_size + size))
	fi
  done
  printf "Total size of all branches that will be moved: %s\n" "$(numfmt --to=iec $total_size)"
  printf "\n"
  
  # Exit function if no files need to be moved
  if [[ "$total_size" -eq 0 ]] && [[ "$most_free_space" = false && "$largest_branch" = false ]]; then
	echo "No directories need to be merged."
	echo ""
	if [[ "$most_free_space" == false || "$largest_branch" == false ]]; then
      read -n 1 -s -r -p "Press any key to continue..."
	  printf "\n"
	  printf "\n"
      return 0
	fi
  fi

  # Calculate the total size of all branches that will be moved between different file systems
  total_cross_fs_size=0
  for branch in "${branches_to_move[@]}"; do
    if [[ "$branch" != "" ]]; then
      # Get the mount point of the branch
      branch_fs=$(df -P "$branch" | awk 'NR==2 {print $1}')
      # Get the mount point of the target branch
      target_branch_fs=$(df -P "$target_branch" | awk 'NR==2 {print $1}')
      # Check if the branch and the target branch are on different file systems
      if [[ "$branch_fs" != "$target_branch_fs" ]]; then
        size=$(du -sb "$branch" | awk '{print $1}')
        total_cross_fs_size=$((total_cross_fs_size + size))
      fi
	fi
  done
  printf "Total size of all branches that will be moved between different file systems: %s\n" "$(numfmt --to=iec $total_cross_fs_size)"
  printf "\n"

  # Check if there is enough space on the target file system and ask the user to select a different if there is not
  if [[ "$total_cross_fs_size" -gt 0 ]]; then
    target_fs=$(df -P "$target_branch" | awk 'NR==2 {print $1}')
    target_free_space=$(df -P -B 1 "$target_branch" | awk 'NR==2 {print $4}')
    printf "Free space on %s: %s\n" "$target_fs" "$(numfmt --to=iec $target_free_space)"
    printf "\n"
    while (( target_free_space < total_cross_fs_size )); do
      printf "Error: not enough free space on target file system for all files that come from different file systems\n"
      printf "\n"

      printf "Please select a different target branch, or enter 'q' to abort:\n"
      printf "\n"
      for i in "${!main_branches[@]}"; do
        if [[ "${main_branches[$i]}" != "$target_branch" ]]; then
          printf "%2s) %s\n" "$i" "$(get_device "${main_branches[$i]}")"
        fi
      done
      printf "\n"
      read -p "Enter the number of the new target branch, or 'q' to abort: " target_branch_index
      printf "\n"
      if [[ "$target_branch_index" == "q" ]]; then
        printf "Aborting...\n"
        printf "\n"
        exit 1
      elif [[ "$target_branch_index" =~ ^[0-9]+$ ]]; then
        target_branch="${main_branches[$target_branch_index]}"
        target_fs=$(df -P "$target_branch" | awk 'NR==2 {print $1}')
        target_free_space=$(df -P -B 1 "$target_branch" | awk 'NR==2 {print $4}')
        printf "New target branch: %s\n" "$(get_device "${target_branch}")"
        printf "Free space on %s: %s\n" "$target_fs" "$target_free_space"
        printf "\n"
      else
        printf "Invalid input.\n"
        printf "\n"
      fi
    done
  fi

  # Determine if confirmation is needed
  if [[ "$most_free_space" = true || "$largest_branch" = true ]]; then
    confirm="y"
  else
    # Ask for confirmation before proceeding
    read -p "Are you sure you want to merge these branches into $(get_device "${target_branch}")? (Y/n): " confirm
	printf "\n"
  fi

  if [[ "$confirm" != [yY] ]]; then
    printf "Aborted by user."
    printf "\n"
	printf "\n"
    return 0
  fi

  # Move branches to target branch
  for branch in "${branches_to_move[@]}"; do
    if [[ "$branch" != "" ]]; then
      if [[ "$dry_run" == true ]]; then
        printf "\n\e[31m!!! DRY RUN !!! NO ACTUAL CHANGES WILL BE MADE TO THE FILE SYSTEMS.\e[0m"
        printf "\n"
        printf "\n"
		printf "\nMoving branches to $(get_device "${target_branch}")...\n"
        rsync --remove-source-files -a -n -v "$branch/" "$target_branch/"
      else
	    printf "\nMoving branches to $(get_device "${target_branch}")...\n"
        rsync --remove-source-files -a -v "$branch/" "$target_branch/"
      fi
	fi
  done

  # Delete empty directories
  if [[ "$dry_run" == true ]]; then
    printf "\n\e[31m!!! DRY RUN !!! NO ACTUAL CHANGES WILL BE MADE TO THE FILE SYSTEMS.\e[0m\n"
    printf "\n"
    printf "Directories to be deleted (includes all subdirectories):\n"
	printf "\n"
	
    # Dry run to preview directories that will be deleted
    for branch in "${branches_to_move[@]}"; do
	  if [[ "$branch" != "" ]]; then
        dir_name="$(basename "$branch")"
	    find "$branch" -maxdepth 1 -type d -name "$dir_name" -print
	  fi
    done
  else
    printf "\nDeleting empty directories...\n"
	printf "\n"
	# Delete empty directories and subdirectories in the paths themselves
    for branch in "${branches_to_move[@]}"; do
	  if [[ "$branch" != "" ]]; then
        find "$branch" -type d -empty -delete
	  fi
    done
  fi
  printf "\n"
  
  # Delete temporary new branches that were not used
  if [[ "$create_branches" == true ]]; then
    for num_new_branch in "${!new_branches[@]}"; do
      rmdir -p --ignore-fail-on-non-empty "${new_branches[$num_new_branch]}"
    done
  fi
  
  # Wait for the user to continue
  if [[ "$most_free_space" == true || "$largest_branch" == true ]]; then
  	# ask user to show the next change in a dry run
	if [[ "$dry_run" = true ]]; then
      echo "Branches successfully merged!"
      echo ""
      read -n 1 -s -r -p "Press any key to continue..."
      printf "\n"
    else
	  echo "Branches successfully merged!"
	fi
  else
    # Ask for confirmation before proceeding
    echo "Branches successfully merged!"
	echo ""
    read -n 1 -s -r -p "Press any key to continue..."
	printf "\n"
  fi

  printf "\n"
}

# MAIN LOOP

# Run merge function in base path if recursion depth is zero
if [[ "$recursion_depth" -eq 0 ]]; then
  merge "$base_path"
else
  # Recurse into subdirectories and add them to paths_to_merge array
  while IFS= read -r -d '' path; do
    paths_to_merge+=("$path")
  done < <(find "$base_path" -mindepth "$recursion_depth" -maxdepth "$recursion_depth" -type d -print0)

  # Run merge function on each path in the array
  for path in "${paths_to_merge[@]}"; do
    merge "$path"
  done
fi

exit