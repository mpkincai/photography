#!/opt/homebrew/bin/fish
#
# Script will update the file date to match the photo date
#

#-- Global Variables
set log /dev/null
set scriptVersion 1.0

#--
#-- exiftool -d %Y%m%d%H%M -CreateDate=200007010600 Scan-150124-0002.jpg
#--

function changeCreateDate
   
   #-- Different files have different create date fields set
   set cdate (/opt/homebrew/bin/exiftool -d %Y%m%d%H%M -CreateDate "$filename" | awk '{print $NF}')
   if test -z "$cdate"
      set cdate (exiftool -d %Y%m%d%H%M -DateTimeCreated "$filename" | awk '{print $NF}')
   end

   set mdate (stat -f "%Sm" -t "%Y%m%d%H%M" "$filename")

   if $DEBUG
      echo "Name: $filename CreateDate: $cdate FileDate: $mdate"
   end

   if test ! -z "$cdate"
      if [ "$cdate" -ne "$mdate" ]
         echo "Changing date from $mdate to $cdate for file $filename" | tee -a $log
         touch -mt $cdate "$filename"
      end
   else
      echo "Photo date not found for file $filename" | tee -a $log
   end
end

#-- Parse and assign input values
getArgv $argv | while read -l key value
   switch $key
      case p picture-directory
         set pictureDir $value
         echo "Setting pictureDir to $pictureDir"
      case d DEBUG
         set DEBUG true
      case h help
         exit 0
      case v version
         echo $scriptVersion
         exit 0
   end
end

#-- Default Inputs
if not set -q pictureDir ; set pictureDir ~/Pictures/workflow/5-metadata-added ; end
if not set -q DEBUG ; set DEBUG false ; end

#-- Main
find "$pictureDir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print | while read filename
   changeCreateDate
end
