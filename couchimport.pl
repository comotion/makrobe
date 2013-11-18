#!/usr/bin/env perl
#
# import membership data csv to couch
# NOTE: this data usually has plenty of crazy notation,
# and this script was written with one particularily large
# excel spreadsheet in mind.
#
# This code will probably not work for anything else without hacking.
#
# comotion@krutt.org 2012-12-12

use strict;
use POSIX qw(strftime);
use utf8;
use JSON::XS;
use CouchDB;
use Date::Parse;
use Members;

use Encode;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

my $json = JSON::XS->new->ascii;
my $db = CouchDB->new('localhost', 5984);

our $DEBUG =1 ;
our $REAL = 1;

# The name of the organization running this instance.
our $org = "members";

#,,"E-post / Telefon","OPPDATERT: 24.04.12",Kontonummer,,Navn,"Gyldig fra","Gyldig til","Betalinger 200",250,"Bøter, på stedet","Bøter, giro","Individuelt regnskap",
#2010,,,2010,,,,,,,,,,,
#,,me@example.com,myoldemail@gmail.com,1231.13.13131,,"Hans Rotvær",2012/11/28,2012/12/28,7,16,2,,3900,
#,2012/03/08,,bambus.bambusskudd@gmail.com,1314.14.14143,,"Espen Bambus",08.03.11,08.04.11,,1,,,250,
#,2012/11/29,,aasejord@yahoo.no,2323.23.23233,,"Åse Jord",2012/11/29,2012/12/29,1,,,,200,

# some things carry over lines:: years and dates
# counting starts in 2010
my ($g_year, $last_date) = ('2009', '2010-01-01');

sub norm_date {
   my ($cdate, $year)  = @_;
   # this sets the entry date, normalize and verify year
   $cdate =~ s/^ *"? *//;
   $cdate =~ s/ *"? *$//;
   $cdate =~ s/[^.\-\/0-9]//g;
   if($cdate eq '') { return '' };
   if($cdate =~ /\./) {
      $cdate =~ s/\.+/\./g; # suss out double dots
      # oh dear. format is DD.MM.YY not YYYY/MM/DD, flip it
      my ($di, $mo, $ye) = split /\./, $cdate;
      # special cases
      if($di eq ''){
         # forgot day
         $di = '01';
      }
      if(not defined $ye){
         # forgot a dot
         if($di =~ /(.?.)(..)/){
            $di = $1;
            $ye = $mo;
            $mo = $2;
         }elsif($mo =~ /(..)(..)/){
            $mo = $1;
            $ye = $2;
         }else{
            # probably this year?
            $ye = "2012";
         }
      }
      $cdate = $ye+2000 . "/$mo/$di";
   }
   my ($ss,$mm,$hh,$day,$month,$cyear,$zone) = strptime($cdate);
   if(not $year){
      $year = $cyear + 1900;
   }
   $month++;
   #Usage: POSIX::strftime(fmt, sec, min, hour, mday, mon, year, wday = -1, yday = -1, isdst = -1) at couchimport.pl line 34, <> line 13.

   return strftime "%F",0,0,0,$day,$month-1,$year-1900;
}
sub valid_email {
   my $_ = shift;
   /\w+@\w+/ or return 0; # do a shitty job of an impossible task
}

# Unquote strings
sub unq {
   my $_ = shift;
   s/^"? *(.*)/$1/;
   s/ *"? *$//;
   return $_;
}

my $extra = '';
# normalize accounts, taking account of peeps with multiple accounts
sub norm_acc {
   my $acc = shift;
   $acc =~ s/  /\//;
   if($acc =~ /\//){
      my @az = split /\//,$acc;
      my @ay;
      for(@az){
         push @ay, norm_acc($_);
      }
      return \@ay;
   }
   # weird scientific notation for credit card no
   if($acc =~ /\d\.\d{3}\d{4}\d{4}(\d{3})E\+15/) {
      $acc = '';
      $extra = $1.'0';
      return $acc;
   }elsif($acc =~ /\d\.\d{3}\d{4}\d{4}(\d{4})E+15/) {
      $acc = '';
      $extra = $1;
      return $acc;
   # credit card?
   }elsif($acc =~ /^ *\d{4} ?\d{4} ?\d{4} ?(\d{4}) *$/) {
      $acc = '';
      $extra = $1;
      return $acc;
   }
   my $acca = $acc;
   $acc =~ s/[^\d]//g;
   # nice formatting
   if($acc =~ /^(\d{4}\d{2}\d{5})$/){
      return $acc;
   }
   # we likely lost a zero in the sheet
   if($acc =~ /^(\d{8})/){
      return '0'.$acc;
   }

   # moar shit at the end.. "extra"
   if($acc =~ /^(\d{4}\d{2}\d{5})(.+)$/){
      $acc = $1;
      $extra = $2;
      #print "ACC: $acc\n";
   }

   return $acc;
}
# handle caccount-special-cases
sub do_extra {
   # suppose it's a card number and we are only interested in the
   # final four digits
   #print "EXTRA: $extra\n";
   my ($c) = ($extra =~ /(\d *\d *\d *\d *$)/);
   $extra = '';
   return $c;
}


my $note = '';
sub norm_name {
   my $name = shift;
   if($name =~ /^\(([^)]*)\) *(.*)$/){
      $name = $2;
      $note = $1;
   }elsif($name =~ /^([^(]*) *\(([^)]*)\)$/) {
      $name = $1;
      $note = $2;
   }
   return $name;
}


# XXX: get rid of "comments"
sub norm_mail {
   my $mail = shift;
   $mail =~ s/^ *" *//;
   $mail =~ s/ *" *$//;
   if($mail =~ /^([^(]*) *\(([^)]*)\)$/) {
      $mail=$1;
      $note=$2;
   }
   $mail =~ s/ //g;
   if($mail eq '?'){
      $mail = '';
   }

   return $mail;
}

sub validatta {
   my $hr = shift;
   my $name = $hr->{name};
   if(not defined $name){
      die "Oh dear";
   }
   if(not $hr->{old_mail} and not $hr->{email}) {
      #warn "No email for $name\n"; # common
      return 0;
   }
   if(not $hr->{account}) {
      #warn "No account for $name\n"; # common
      return 0;
   }
   my $from = str2time($hr->{valid_from});
   my $to;
   my $now = time();
   $to = str2time($hr->{valid_to}) if defined $hr->{valid_to};
   my $start = str2time($hr->{join_date});
   if(not defined $from){
      warn "$name missing from date\n";
      return 0;
   }elsif($start > $from){
      #warn "$name starts($hr->{join_date}) after validity($hr->{valid_from})\n";
      return 0;
   }elsif(defined $to and $from > $to) {
      warn "$name account validity fubar ($hr->{valid_from} -> $hr->{valid_to})\n";
      return 0;
   }elsif($start > $now){
      warn "$name starts in the future\n";
   }elsif(defined $from and $from > $now){
      warn "$name is valid from the future ($hr->{valid_from})\n";
   }
   return 1;
}

sub norm_card {
   my ($card) = @_;
   $card =~ s/[^\w]//;
   return $card;
}

sub print_dates {
   my ($name, $valfrom, $valto) = @_;
   print "$name :: $valfrom (".norm_date($valfrom).")";
   if(defined $valto and $valto ne ''){
      print " $valto (".norm_date($valto).")";
   }
   print "\n";
}

sub filter_special {
   # input-wide special cases
   s/  / /g;                        # case of the double space
   s/("[^",]*)\.,([^",]*")/$1.$2/g; # case of the bad comma
   s/\xc2 / /g;                     # case of the unicode space
   s/ / /g;                         # case of the evil two-byte space
   s/"<([^>]+)>, "/$1/g;            # case of the fanged email
   s/,"(\d{4}),(\d{2}),(\d{5})",/,$1.$2.$3,/; # and the comma account
   s/(\([^)]*),([^)]*\))/$1 $2/g; # case of the evil comma
   s/epost, p/epost. p/;        #pænchod!
   /, Beate=mor/ and $note = "Beate=mor" and s/, Beate=mor//;
}

my $line = 0;
my $dude = 0;
while(<>){
   filter_special();
   $line++;
   # the porcessing
   my ($yr,$cdate,$omail,$email,$account,$card,$name,$valfrom,$valto,$pay200,$pay250,$bot,$botgiro,$indiv) = split/,/;
   /Ukjent innbetaling: ([^,]*)/ and
    $name = 'Ukjent' and $account = $1;

   if($yr ne '' and int($yr)){
      # sets the default year on otherwise empty lines
      $g_year = $yr;
   }
   if($cdate ne '' and not $cdate =~ /^"1900/ ) {
      # start date lies about start year
      $last_date = norm_date($cdate, $g_year);
   }

   if (not defined $email or not $email or $email =~ / / or not valid_email($email)){
      if(defined $name and $name ne '' and $name ne 'Navn'){
         ; # ok
      }elsif($yr ne ' '){
         next;
      }else{
         print "Invalid line, '$account,$name,$email'\n" if $DEBUG;
         next;
      }
   }
   my %h = (
      'join_date' => $last_date,
      'old_mail' => $omail,
      'email' => norm_mail($email),
      'account' => norm_acc(unq($account)),
      'name' => norm_name(unq($name)),
      'valid_from' => norm_date($valfrom),
      'valid_to' => norm_date($valto),
      'paid_200' => $pay200,
      'paid_250' => $pay250,
      'bot'      => $bot,
      'bot_giro' => $botgiro,
      'indiv'    => $indiv,
      'card'     => norm_card($card),
      'approved' => $last_date,
   );
   if($extra){
      my $ecard = do_extra();
      if($ecard) {
         if($h{card} and $h{card} ne $ecard) {
            my @cards = ($card, $ecard);
            $h{card} = \@cards;
         }else{
            #print "CARD: $h{card}\n";
            $h{card} = $ecard;
         }
      }
   }
   if($note){
      $h{note} = $note;
      #print "NOTE: $note\n";
      $note = '';
   }
   #print_dates($name, norm_date($valfrom), norm_date($valto));
   #print "$h{name}: $h{account}\n" if $h{account};

   # validate.. but these are only warnings anyway
   if(not validatta(\%h)){
      #print;
   }

   # deduplication! check for existing account, email, name
   my @ids;
   my $that;
   if($h{account}) {
      $that = Members::lookup($db, 'account', $h{account});
      if($that) {
         if(Members::duplicate(\%h, $that)){
            #print "$that->{_id} |MERGE| with $dude\n";
            %h = %{Members::merge_hash(\%h, $that)};
            print "Merged to $h{_id}, $h{_rev}\n";
         #}else{
         #   print "\n$that->{_id} $that->{name} /not merging/ on $dude $h{name}\n";
         }
         push @ids, $that->{_id};
      }
   }
   if($h{email}){
      $that = Members::lookup($db, 'email', $h{email});
      if($that){
         if(not grep $that->{_id},@ids and Members::duplicate(\%h, $that)){
            #print "$that->{_id} |MERGE| with $dude\n";
            %h = %{Members::merge_hash(\%h, $that)};
            print "Merged to $h{_id}, $h{_rev}\n";
         #}else{
         #   print "\n$that->{_id} $that->{name} /not merging/ on $dude $h{name}\n";
         }
         push @ids, $that->{_id};
      }
   }
   #$h{name} = encode('utf8', $h{name});
   $that = Members::lookup($db, 'name', lc $h{name});
   if($that){
      print "Found dupe on $h{name}: \n ".$json->encode($that)."\n" if $that;
      if(not grep $that->{_id},@ids){
         if(Members::duplicate(\%h, $that)){
            print "$that->{_id} |MERGE| with $dude\n";
            %h = %{Members::merge_hash(\%h, $that)};
            print "Merged to $h{_id}, $h{_rev}\n";
         #}else{
         #   print "not merged $that->{name}\n";
         }
      #}else{
      #   print "\n$that->{_id} $that->{name} /not merging/ on $dude $h{name}\n";
      }
      push @ids, $that->{_id};
   }
   #my $nc = $json->encode(\%h);
   #print "put $dude". lc $name ."\n";
   Members::put($db, "/$org/",\%h) if $REAL;
   $dude++;
   #print "$nc\n";
   #print "  ". $json->decode($nc)->{'date'}."\n";
   #print " -> ".str2time($json->decode($nc)->{'date'}) if defined($last_date);
}

print "Added $dude over $line lines\n";

#print $db->get('/example/some_doc_id')."\n";
