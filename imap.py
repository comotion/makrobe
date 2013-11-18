# Download only CULTURA pdf's from imap mail.
#
# comotion@krutt.org 2012-12-12

from datetime import datetime, timedelta
import email
from imapclient import IMAPClient
import re
import os

REAL = True
#REAL = False
HOST = 'imap.gmail.com'
USERFILE = '.user'
PASSFILE = '.pass'
TMPPATH = '/tmp/'
ssl = True

#sjekker bare siste X dager.
today = datetime.today()
cutoff = today - timedelta(days=5)
folder = 'INBOX'

# override to get everything from the end of time
cutoff = datetime(1900,1,1,1,1,1,1)
folder = '[Gmail]/All e-post'

done_label = 'processed'
done_flag  = 'done'

urf = open(USERFILE, 'r')
username = urf.readline()
urf.close()
username = username.rstrip()

pwf = open(PASSFILE, 'r')
password = pwf.readline()
pwf.close()
password = password.rstrip()

## Connect, login and select the folder
server = IMAPClient(HOST, use_uid=True, ssl=ssl)
server.login(username, password)

#folderlist = server.xlist_folders()
#print(folderlist)

select_info = server.select_folder(folder)

## Search for relevant messages
## see http://tools.ietf.org/html/rfc3501#section-6.4.5
messages = server.search(
['SUBJECT "E-post fra CULTURA SPAREBANK"', 
 'FROM "bbs-distribusjon@bbs.no"', 
 'UNKEYWORD "done"',
 'SINCE %s' % cutoff.strftime('%d-%b-%Y')])
response = server.fetch(messages, ['RFC822'])

count = 0
for msgid, data in response.iteritems():
   msg_string = data['RFC822']
   msg = email.message_from_string(msg_string)
   #print 'ID %d: From: %s Date: %s' % (msgid, msg['From'], msg['date'])
   #print msg['Subject']
	#print(msg.get_content_type())
   labels = server.get_gmail_labels(msgid)
   if done_label in labels[msgid]:
      #print server.get_flags(msgid) # should have 'done' flag
      #server.remove_flags(msgid, ('\\Flagged'))
      #server.add_flags(msgid,(done_flag))
      #print('#skipped %s'% msgid)
      continue

   #print server.get_flags(msgid)
   if(msg.is_multipart()):
      for mess in msg.get_payload():
         #print "  " +mess.get_content_type()
         if mess.get_content_type() == "application/pdf":
            filename = mess.get_filename().split('/')[-1]     # get rid of path
            filename = re.sub('[^a-zA-Z\.0-9_]','_',filename) # take no chances, accept only alpahnum!
            filename = TMPPATH + filename
            #print mess.get_payload().decode()
            print "%s" % filename
            if not REAL:
               continue
               
            f = open(filename, 'w')
            pdf = mess.get_payload(decode=True)
            f.write(pdf)
            f.close()
            count = count + 1
            # now mark as downloaded and processed
            #print "progress: %d" % count
            #print ("pdftotext -nopgbrk -raw " + filename + " - | perl cultura.pl")

      if REAL:
         #print("setting flags on message")
         server.add_gmail_labels(msgid, (done_label))
         server.add_flags(msgid,(done_flag))
         server.remove_gmail_labels(msgid, ('\\Inbox'))

   #else:
      #print msg.get_content_type()
      #print("meh")

   #exit()
