#!/usr/bin/env perl

# common stuff for app/couch
# comotion@krutt.org 2012-12-12

package Members;

use strict ;
use warnings;
use utf8;
use CouchDB;
use JSON::XS;
use Encode;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
my $DEBUG = 0;

#my $json = JSON::XS->new->ascii->utf8->space_after->allow_nonref;
my $json = JSON::XS->new->ascii->utf8;

sub create_views{
   my $org = shift;
   my ($db) = @_;
   my $req = "/$org/_design/v";
   my $def = qq{{
  "_id": "_design/v",
  "_rev": "::REV::",
  "language": "javascript",
  "views":
  {
    "all": {
      "map": "function(doc) { emit(null, doc) }"
    },
    "account": {
      "map": "function(doc) { if (doc.account) { if(typeof(doc.account) == 'object') { for(var i = 0; i < doc.account.length; i++){ emit(doc.account[i], doc); } }else{ emit(doc.account, doc); } } }"

    },
    "email": {
      "map": "function(doc) { if (doc.email) { emit(doc.email, doc) }; if(doc.old_mail){ if(typeof(doc.old_mail) == 'object') { for(var i = 0; i < doc.old_mail.length; i++) { emit(doc.old_mail[i]) }} else { emit(doc.old_mail, doc) } } }"
    },
    "name": {
      "map": "function(doc) { emit(doc.name.toLowerCase().replace('.',''), doc) }"
    },
    "new": {
      "map": "function(doc) { if(!doc.approved){ emit(null, doc); } }"
    }
   }
}
};
      #"map": "function(doc) { if (doc.email) { emit(doc.email, doc) }else if(doc.old_mail){ emit(doc.old_mail, doc) } }"
   my $tf;
   warn "Creating views\n";
   $tf= eval{$db->get($req)};
   unless($tf){
     warn "Creating db\n";
     eval{$db->put("/$org/", "whatever")};
     $def =~ s/ *"_rev": "::REV::",//;
   }else{
      my $rv = $json->decode($tf);
      my $rev = $rv->{_rev};
      $def =~ s/::REV::/$rev/;
   }
   #print $json->decode($def)->{views}{account}{map};
   $db->put($req, $def);
   print "Done with views & db\n";
   return "yaya";
}

sub new_id{
   my ($db) = shift;
   return $json->decode($db->get("_uuids"))->{uuids}[0];
}

# put a new document, with retries if the uuid doesn't match.
sub put {
   my ($db, $path, $entry) = @_;
   my $ret;
   if(not defined $entry->{_id}){
      while(not defined $ret) {
         $entry->{_id} = new_id($db);
         $ret = eval{$db->put($path.$entry->{_id}, $json->encode($entry))};
      }
      print "ny $entry->{_id}: $entry->{email}\n" if $DEBUG;
   }else{
      print "ol $entry->{_id}: $entry->{email}\n" if $DEBUG;
      $ret = eval{$db->put($path.$entry->{_id}, $json->encode($entry))};
      if(not defined $ret){
         warn "put failed, $@";
         return undef;
      }
   }
   return $entry->{_id};
}


# lookup $key in $view and check dupes
# return a hashref for 1st entry if no dupes
sub lookup {
   my ($org, $db, $view, $key) = @_;
   #print "'$view/$key\n";
   my $req = qq(/$org/_design/v/_view/$view?key="$key");
   my $tj = eval{$db->get($req)};
   unless($tj) { create_views($org, $db) and $tj = $db->get($req)}
   #print "$tj";
   my $th = $json->decode($tj);
   my $this = $th->{rows};
   if(@$this > 1){
      warn "OOPS, dupe $key: ".scalar @$this;
      warn "The dupe is ".$json->encode($this)."\n";
      my @that;
      for (@$this){
         push @that, $_->{value};
      }
      # natch, dont return an array
      # better, return 1st match
      #return \@that;
   }
   if(@$this < 1) {
      return undef;
   }
   my $that = $this->[0]{value};
   return $that;
}

# return true if duplicate

#  1) add emails to old_mail list
#  2) add accounts (which one is newer? last one used)
#  3) filter already-matched ids
#  4) definitely merge if same accound same mail (or same name)
#  5) merge if name is off by one or two (edit dist)

sub duplicate {
   my ($a, $b) = @_;
   if(defined $a->{_id} and defined $b->{_id} and $a->{_id} eq $b->{_id} and
     (defined $a->{_rev} and defined $b->{_rev} and $a->{_rev} eq $b->{_rev})){
      #print "dupe by rev\n";
      return 0;
   }
   if(defined $a->{account} and defined $b->{account} and $a->{account} eq $b->{account}) {
      #print "dupe by accv\n";
      if(match_name($a->{name}, $b->{name}) or match_mail($a, $b)){
         #print "dupe by name\n";
         return 1;
      }else{
         print "$a->{name} and $b->{name} share same account\n";
      }
   #}elsif(match_mail($a,$b)){
   #   print "dupe by mail\n";
   #   return 1;
   }elsif($b->{name} eq "Ukjent"){
      print "Discovery ! Ukjent is $b->{name}!\n";
      return 2;
   }elsif(match_name($a->{name},$b->{name})){
      #print "dupe by name\n";
      return 1;
   }
   #print "not a match: $a->{name} $b->{name}\n";
   return 0;
}

sub match_mail {
   my ($a, $b) = @_;
   my (@x, @y);
   if($a->{old_mail}){
      if(ref $a->{old_mail} eq 'ARRAY'){
         for my $m (@{$a->{old_mail}}){
            push @x, $m;
         }
      }else{
         push @x, $a->{old_mail}
      }
   }
   if($a->{email}){
      push @x, $a->{email};
   }
   if($b->{old_mail}){
      if(ref $b->{old_mail} eq 'ARRAY'){
         for my $m (@{$a->{old_mail}}){
            push @x, $m;
         }
      }else{
         push @y, $b->{old_mail};
      }
   }
   if($b->{email}){
      push @y, $b->{email};
   }
   map { my $zool = $_; grep { $zool eq $_ } @y } @x;
   if(wantarray) {
      return @x;
   }else{
      return scalar @x;
   }
}

sub merge_mail {
   my ($a, $b) = @_;
   my %hh;
   my $last = '';
   for ($a->{old_mail}){
      next if not $_;
      if(ref $_ eq 'ARRAY'){
         for my $m (@$_){
            $hh{$m} = 1;
         }
      }else{
         $hh{$_} = 1;
      }
      $last = $_;
   }
   for ($b->{old_mail}){
      next if not $_;
      if(ref $_ eq 'ARRAY'){
         for my $m (@$_){
            $hh{$m} = 1;
         }
      }else{
         $hh{$_} = 1;
      }
      $last = $_;
   }
   if($b->{email}){
      $hh{$b->{email}} = 1;
      $last = $b->{email};
   }
   if($a->{email}){ 
      $hh{$a->{email}} = 1;
      $last = $a->{email};
   }
   delete $hh{$last};
   my @a = keys %hh;
   push @a, $last;
   return \@a;
}


sub match_name {
   my $score = 0;
   my ($name, $other) = @_;
   if(lc $other eq lc $name) { 
      $score = 99;
      #print "SCORE $name\n";
   }else{
      # either name is short
      my @ny = split / /,lc $name;
      my $na = lc $other;
      $score = 0;
      for my $w (@ny) {
         #print "$w;";
         $na =~ /$w/ and $score++;
      }
      # misspelled, or levensteinxs or string::approx
   }
   #if($score){
     #print "'$name' is '$other' by $score\n";
   #}else{
   #   print "$name is not $other";
   #}

   return $score;
}

sub merge_accounts{
   my ($a, $b) = @_;
   return $a if not defined $b or not $b;
   if(ref $b){
      if(not ref $a){
         if(not grep { $a eq $_ } $b){
            push $b, $a;
         }
         $a = $b;
      }else{
         my %hh;
         foreach($a){
            $hh{$_} = 1;
         }
         foreach($b){
            $hh{$_} = 1;
         }
         $a = keys %hh;
      }
      return $a;
   }else{
      if(not ref $a) {
         if($a ne $b){
            return [$a, $b];
         }
      }else{
         return merge_accounts($b, $a);
      }
   }
}

# merge in all from this except what we want from that
sub merge_hash {
   my ($this, $that) = @_;
   if($this->{_id} and $that->{_id} and $this->{_id} eq $that->{id}) {
      if(defined $this->{_rev} and defined $that->{_rev}){
         if($this->{_rev} eq $that->{_rev}){
            # same id, same rev
            return $this;
         }
         if($this->{_rev} ge $that->{_rev}){
            # same id, lower rev
            return $this;
         }
         # same id, higher rev
         return $that;
      }
      # same id, but someone is missing a rev.
      return $this; # maybe that?
   }


   my %res;
   my $same = 1;

   # check if we are trying to merge on same record.
   for (keys %$this){
      if($_ eq '_id' or $_ eq '_rev'){
         next;
      }
      if(not defined $that->{$_} or $that->{$_} ne $this->{$_}){
         $same = 0;
         last;
      }
   }
   return $this if $same;

   for (keys %$this){
      if( defined $that->{$_}){
         if(/mail/){
            next;
         }elsif(/account/){
            $this->{account} = merge_accounts($this->{account}, $that->{account});
         }elsif( ($_ eq 'join_date' and $that->{$_} lt $this->{$_}) or
          ($_ eq 'valid_to' and $that->{$_} gt $this->{$_}) or
          ($_ eq 'valid_from' and $that->{$_} gt $this->{$_}) ){
            print "Merge: $_: $that->{$_} over $this->{$_}\n" if $DEBUG;
            $res{$_} = $that->{$_};
         }elsif (/^paid_|^bot|^indiv/){
            if( $this->{$_} eq ''){
               $res{$_} = $that->{$_};
            }elsif($that->{$_} eq ''){
               $res{$_} = $this->{$_};
            }else{
               $res{$_} = $that->{$_} + $this->{$_};
            }
            print "Merge: $_: $that->{$_} + $this->{$_}\n" if $DEBUG;
         }elsif ($_ eq '_id' or $_ eq '_rev') {
             # merge on that id and rev
            $res{$_} = $that->{$_};
         }else{
            $res{$_} = $this->{$_};
         }
         delete $that->{$_};
      }else {
         $res{$_} = $this->{$_};
      }
   }
   my $mail = merge_mail($this, $that);
   $res{email} = pop $mail;
   $res{old_mail} = $mail;
   delete $that->{email};
   delete $that->{old_mail};

   print "merged mail: ".$res{email}."\n";
   for (keys %$that){
      $res{$_} = $that->{$_};
   }

   return \%res;
}



#my $db = CouchDB->new('localhost', 5984);
#print "uh: ".new_id($db)."\n";
