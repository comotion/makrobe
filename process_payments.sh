#!/bin/sh
#set -x
cd ~/plankapp/

rm -f todo_list
# fetch payments
python imap.py > todo_list

# process payments
for file in `cat todo_list | grep '\.pdf'`
do
   pdftotext -nopgbrk -raw $file - | perl cultura.pl
   mv $file pdf/
done | egrep -v '^(tx:|/tmp/|Update)'

