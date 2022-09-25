#!/opt/homebrew/bin/fish
#
# Script will create and validate checksum files

#-- Global Variables
set checksumFile sha256.sums
set logFile /var/log/photography/checksum.log
set scriptVersion 1.0

#-- Local Functions
function validateChecksums
   set currentTS (date +"%Y-%m-%d %T")
   shasum -a 256 --strict --ignore-missing --quiet -c $path/$checksumFile 2> /dev/null | ts "$currentTS [$fish_pid] INFO  :" | tee -a $logFile
   return $pipestatus[1]
end

function getFiles
   gfind . -maxdepth 1 -type f -not \( -iname '*.DS_Store' -o -iname '*.json' -o -iname '*.sums' -o -iname '*.unbound' \) -printf '%f\n'
end

function createChecksums
   set trgtFiles (getFiles)
   if test -z "$trgtFiles"
      tslog "Bypass directory, no files to checksum"
   else
      shasum -a 256 $trgtFiles > $checksumFile
   end
end

#-- Log script startup
tslog "Starting Script"

#-- Parse and assign input values
getArgv $argv | while read -l key value
   switch $key
      case p picture-directory
         set pictureDir $value
         tslog "Setting pictureDir to $pictureDir"
      case f force
         set force $value
         tslog "Setting force to $force"
      case h help
         tslog "Executing help" > /dev/null
         echo ""
         echo "Usage: checksum.fish [OPTION]"
         echo "Create and validate checksums recursively for target directory"
         echo ""
         echo "   -p, --picture-directory    Override default target directory"
         echo "   -f, --force                Create new checksum file even though there is a checksum difference"
         echo ""
         exit 0
      case v version
         tslog "Version: $scriptVersion"
         exit 0
   end
end

#-- Default Inputs
if not set -q pictureDir ; set pictureDir /Volumes/Backup/OneDrive/Pictures ; end
if not set -q force ; set force false ; end

#-- Verify the picture directory is mounted
if not test -d $pictureDir
	tslog "Directory $pictureDir is not mounted, exiting"
   exit 1
end

#-- For each directory from the picture base
gfind "$pictureDir" -type d | while read path
   tslog "Processing directory $path"
   cd "$path"

   if test -e $checksumFile
   #-- If file exists
      
      if validateChecksums
         #-- checksums match
         set dirFileCnt (getFiles | wc -l | tr -d ' ')
         set sumsFileCnt (cat $checksumFile | wc -l | tr -d ' ')

         if [ "$dirFileCnt" -gt "$sumsFileCnt" ]
            #-- Net files were added to the directory

            set fileCntDiff (math "$dirFileCnt - $sumsFileCnt")
            tslog "Updating checksums due to net $fileCntDiff file(s) added to the directory"
            createChecksums
         else if ! shasum -a 256 --strict --status -c $path/$checksumFile >/dev/null 2>&1
            #-- Files were dropped from the directory
            
            set fileCntDiff (math "$dirFileCnt - $sumsFileCnt")
            tslog "Updating checksums due to missing files, net file count change is $fileCntDiff"
            createChecksums
         end
      else
         #-- Checksum failed and differences reported

         if $force
            #-- Recreate the checksum file if forced

            tslog "Updating checksums due to force set to $force"
            createChecksums
         end
      end
	else
      set trgtFiles (getFiles)
      if test -z "$trgtFiles"
         tslog "Bypass directory, no files to checksum"
      else
		   tslog "Create first checksum file"
		   createChecksums
      end
   end
end

tslog "Finished Script"
exit 0
