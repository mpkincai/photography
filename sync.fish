#!/opt/homebrew/bin/fish
#
# Script will track changes in a picture directory by checking a directory hash value.
# If a difference is found, rclone is run on that directory to sync (one way) to a
# cloud provider
#
# dependencies
#   - brew install rclone (you will need to configure a cloud target)
#   - brew install exa
#   - brew install jq
#   - brew install exiftool
#   - tslog global function

#-- Global Variables
set dirHashFile dirHash.json
set logFile /var/log/photography/sync.log
set month (date +"%m")
set scriptVersion 1.1
set globalExclude ".*,*.json,*.sums"
set excludeFile ".exclude"

#
# Local Functions
#

# Function will sync the local directory with the cloud directory
function syncDirectory
   set targetDir (string replace /Volumes/Backup/OneDrive "" $path)

   #-- check for files to exclude from the upload
   set rcloneExclude $globalExclude
   if test -e $path/$excludeFile
      cat $path/$excludeFile | while read xFile
         tslog "Excluding $xFile from the sync process"
         set rcloneExclude "$rcloneExclude,$xFile"
      end
   end

   tslog "Running rclone on $path"
   rclone sync $path ODR:$targetDir \
      --exclude "{$rcloneExclude}" --size-only --verbose --create-empty-src-dirs --max-depth 1 \
      --stats=2m --stats-one-line --log-format date,time,pid $OPT 2>&1 | gsed --unbuffered "s/\/$month\//-$month-/g" | tee -a $logFile
   return $pipestatus[1]
end

#-- Function will calc a simply directory hash
function getDirHash
   exa $path -laB -s Name --no-user --no-permissions --time-style=long-iso -I=".*|*.json|*.sums" | shasum | string split ' ' | head -1
end

#-- Function will update the file date to match the photo create date
function changeCreateDate
   #-- Different files have different create date fields set
   set cdate (/opt/homebrew/bin/exiftool -d %Y%m%d%H%M -CreateDate "$filename" | awk '{print $NF}')
   if test -z "$cdate"
      set cdate (exiftool -d %Y%m%d%H%M -DateTimeCreated "$filename" | awk '{print $NF}')
   end

   set mdate (stat -f "%Sm" -t "%Y%m%d%H%M" "$filename")

   if test ! -z "$cdate"
      if [ "$cdate" -ne "$mdate" ]
         tslog "Changing date from $mdate to $cdate for file $filename"
         if ! $DEBUG
            touch -mt $cdate "$filename"
         end
      end
   else
      tslog "Photo date not found for file $filename"
   end
end

#
# End Local Functions
#

#-- Log script startup
tslog "Executing Script"

#-- Parse and assign input values
getArgv $argv | while read -l key value
   switch $key
      case d dry-run
         set OPT "--dry-run"
         set DEBUG true
         tslog "Setting rclone option $OPT"
      case p picture-directory
         set pictureDir $value
         tslog "Setting pictureDir to $pictureDir"
      case f force
         set force $value
         tslog "Setting force to $force"
      case h help
         exit 0
      case v version
         echo $scriptVersion
         exit 0
   end
end

#-- Default Inputs
if not set -q pictureDir ; set pictureDir /Volumes/Backup/OneDrive/Pictures ; end
if not set -q force ; set force false ; end
if not set -q DEBUG ; set DEBUG false ; end

#-- Verify the picture directory is mounted
if not test -d $pictureDir
	tslog "Directory $pictureDir is not mounted, exiting"
   exit 1
end

#-- For each directory from the picture base
find $pictureDir -type d | while read path

   #-- Create hash based on the files in the directory
   set dirHash (getDirHash)
	
   if test -e $path/$dirHashFile

	   #-- If file exists, test if there is a change in hash
       if [ (jq .dirHash $path/$dirHashFile | tr -d \") != $dirHash ] || $force

            #-- prior to running rclone, check for file date updates and recalc directory hash
            tslog "Check file dates for directory $path"
            find "$path" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print | while read filename
               changeCreateDate
            end
            set dirHash (getDirHash)

            #-- Sync the directory, if successful, update the directory hash value
       	   if syncDirectory
               tslog "Updating hash in file $path/$dirHashFile"
               if ! $DEBUG
                  jq --arg value $dirHash '.dirHash |= $value' $path/$dirHashFile | sponge $path/$dirHashFile
               end
            else
               tslog "Rclone directory sync failed" "ERROR"
            end
       end
   else
      #-- prior to running rclone, check for file date updates and recalc directory hash
      find "$path" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print | while read filename
         tslog "Check file dates for directory $path"
         changeCreateDate
      end
      set dirHash (getDirHash)

      #-- Sync the directory, if successful, update the directory hash value
      if syncDirectory
         tslog "Creating file $path/$dirHashFile"
         if ! $DEBUG
            printf '{"dirHash": "%s"}' $dirHash | jq | sponge $path/$dirHashFile
         end
      else
         tslog "Rclone directory sync failed" "ERROR"
      end
   end
end

exit 0