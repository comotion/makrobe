#!/usr/bin/env perl
# les en cultura/bbs pdf og registrer
#
# comotion@krutt.org 2012-12-12

use warnings;
use strict;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
use POSIX qw(strftime);
#use encoding 'utf-8';#, Filter=> 1;
use utf8;
use JSON::XS;
use Date::Parse;
use Encode;

use Members;

my $org = "org";
my $json = JSON::XS->new->ascii->utf8;

our $REAL = 0;
our $VERBOSE = 1;


if ($REAL){
    use CouchDB;
}
my $db = CouchDB->new('localhost', 5984) if $REAL;

our $CSV = 1; 
print "date, amount, blankett, ref, id, name, addr, post, account, melding\n" if $CSV;

=stuff
MELDING OM KREDITERING
BETALER:
>NAME
>ADDR
>ZIPNUMMER
MOTTAKER:
HACKERIET OSLO
BELØPET GJELDER:
>blash
Oppgj. dato : 10/12-2012
Oppdr. dato : 07/12-2012
Til konto : 1111.11.11111
Fra konto : 2222.22.22222
Beløp : 123,00
Blankettnr. : 4444444444
Arkivref. : 555555555
ID nummer : 00000000666

squeeze format was: 
MELDING OM KREDITERING
BETALER: MOTTAKER:

SOME GUY SOME GUY ADDRESS

THE DESTINATION

Oppgj. dato Oppdr. dato Til konto Fra konto Beløp Blankettnr. Arkivref. ID nummer

: : : : : : : :

03/12-2012 01/12-2012 PLAN.KA.KONTO ACCO.UN.TNUMB $$$,$$ BLANKETTTT ARKIVREFF IDNUMMERRRR
=cut

use constant {
    RESET => 0,
          GETNAME => 1,
          HASNAME => 2,
          GETMSG => 3
};

    # to parse these lines
my $datefmt = '(\d\d\/\d\d-\d\d\d\d)';
my $acctfmt = '(\d{4}\.\d{2}\.\d{5})';
my $amntfmt = '([0-9\.]+,\d{2})';
my $blnkfmt = '(\d+)';
my $areffmt = '([\d*]+)';
my $idnrfmt = '(\d+)';

my $nameaddr = '';
my $melding = '';
my $state = RESET;

# make sure all the facts are strait.
sub check_payment {
    die "not enough ".scalar @_ if scalar @_ != 10;
    my ($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id,$nameaddr, $melding) = @_;
    # check account number and payment info.
}

sub date_me {
    my $do = shift;
    #07/12-2012
    my ($da,$ma,$ya) = $do =~ /(\d{2})\/(\d{2})-(\d{4})$/;
    return ($da, $ma, $ya);
}
sub proper_date{
    my ($da,$ma,$ya) = @_;
    return strftime "%F",0,0,0,$da,$ma-1,$ya-1900;
}

sub inc_month{
    my ($da,$ma,$ya) = @_;
    if($ma == 12){
        $ya++;
    }else{
        $ma++;
    }
    return ($da, $ma, $ya);
}

# store payment in db
sub register_payment {
    die "bogous transaction, format correct?" if not check_payment(@_);
    my ($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id,$nameaddr, $melding) = @_;
    $mye =~ s/,/./;

    #print "@_\n";

    #print "DATO: $oppdr, $fra, $mye, $blankett, $aref, $id\n";
    my @adr = split /:;/, $nameaddr;
    my $name = shift @adr;
    my $post = pop @adr;
    my $addr = join @adr;

    # count payment from oppdragsdato
    my ($da, $ma, $ya) = date_me($oppdr);
    my $date = proper_date($da,$ma,$ya);
    my $val_to = proper_date($da,$ma+1, $ya);
    #print "$name sier:$melding\n";
    $fra =~ s/\.//g;
    my $by_name = 0;


    # lookup the account
    my $that = Members::lookup ($org, $db, 'account', $fra) if $REAL;

    #no account, ok, so maybe by name?
    if(not $that){
        $that = Members::lookup($org, $db, 'name', lc $name) if $REAL;
        if($that){
            $by_name = 1;
            #print "Score boyyo $that->{name}\n";
        }
    }
    if(not $that) {
        # neither account # nor name is known, make new
        return register_new($oppdr, $fra, $mye, $blankett, $aref, $id,$name, $addr, $post, $melding)
    }

    #print $json->encode($that);
    #print lc decode('utf8',$that->{name})."\n";
    $that->{name}  =~ s/\.//g; # punctuations
        $name = lc $name;

    if(not $REAL or Members::match_name($name, $that->{name})){
    #print "$that->{name} matches\n";
        if($by_name) {
            print "Update $that->{name} with account $fra\n";
            put_account($db, $that, $fra);
            $that = Members::lookup($org, $db, 'account', $fra);
        }
        return pay_him($db, $that, $fra, $oppdr, $mye, $blankett, $aref, $id, $name, $addr, $post, $melding);
    }else{
        warn "$name, $addr, $post doesnt match $that->{name} associated with account $that->{account}!\n";
    }

    # store transaction
    #$that->{xact}
    ## put $th->{transactions}->{id}(when,howmuch)
    return $nameaddr;
}

sub put_account {
    my ($db, $that, $account) = @_;
    $that->{account} = Common::merge_accounts($account, $that->{account});
    #print "put $that->{_id} :: $that->{account}")."\n";
    $db->put("/$org/".$that->{_id}, $json->encode($that)) if $REAL;
}


sub pay_him {
    my ($db, $his, $account, $date, $mye, $blankett, $aref, $id, $name, $addr, $post, $melding) = @_;
    my $tx = $his->{transactions};
    if(not defined $tx) {
        $tx = [];
    }
    my ($da,$ma,$ya) = date_me($date);
    my $val_from = proper_date($da,$ma,$ya);
    my $val_to = proper_date(inc_month($da,$ma,$ya));
    $his->{valid_from} = $val_from;
    $his->{valid_to} = $val_to;
    #check if txid is already there!
    if(grep { $_->{blankett} eq $blankett and $_->{arkivref} eq $aref } @{$tx}){
        #warn "tx $aref already registered\n";
        return;
    }

    push @{$tx}, { 
        date => $val_from,
             amount => $mye,
             blankett => $blankett,
             arkivref => $aref,
             txid => $id,
             name => $name,
             address => $addr,
             post => $post,
             konto =>  $account,
             melding => $melding};
    $his->{transactions} = $tx;
    print "tx: $his->{name} $his->{transactions}[0]{name} $mye\n" if $VERBOSE;
    print "$val_from, $mye, $blankett, $aref, $id, $name, $addr, $post, $account, $melding\n" if $CSV;

    Members::put($db, "/$org/", $his) if $REAL;
}

sub parse_amount {
    my $amount = shift;
    $amount =~ s/\.(\d\d\d)/$1/g;
    return $amount + 0;
}

    # register a new account
sub register_new {
    print "New @_\n" if $VERBOSE;
    my ($date, $fra, $mye, $blankett, $aref, $id,$name, $addr, $post, $melding) = @_;
    my ($da,$ma,$ya) = date_me($date);
    my $joined = proper_date($da,$ma,$ya);
    my $val_to = proper_date(inc_month($da,$ma,$ya));
    my %h = (
            'join_date' => $joined,
            'account' => $fra,
            'name' => $name,
            'valid_from' => $joined,
            'valid_to' => $val_to
            );
    $mye = parse_amount($mye);
    if($mye == 200){
        $h{paid_200} = 1;
    }elsif($mye == 250){
        $h{paid_250} = 1;
    }
    # create the entry by "paying it"
    return pay_him($db, \%h, $fra, $date, $mye, $blankett, $aref, $id, $name, $addr, $post, $melding);
}

sub send_ackmail {
    my ($mailto, $stuff) = @_;
    #print "sure, $mailto\n";
}

sub new_credit {
    my ($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id,$nameaddr, $melding) = @_;
    if(defined $oppgj and $oppgj ne '') {
        register_payment($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id, $nameaddr, $melding) if defined $oppgj;
    }
    reset_credit();
    return 1;
}

my ($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id);

sub reset_credit {
    $oppgj=$oppdr=$til=$fra=$mye=$blankett=$aref=$id=undef;
    $nameaddr = $melding = '';
    $state = RESET;
}


sub parse_payment_line {
    #print and 
    chomp;
    /^Side \d+ av \d+$/ and 1 or
        /^forts. / and 1 or
        /^Forsendelsen inneholder \d/ and 1 or
        /^konto 1254.05.72966:/ and 1 or
        /^\d+ meldinger om kreditering/ and 1 or
        /^Oppgj. dato : (.*)$/ and $1 =~ $datefmt and $oppgj = $1 or
        /^Oppdr. dato : (.*)$/ and $1 =~ $datefmt and $oppdr = $1 or
        /^Til konto : (.*)$/ and $1 =~ $acctfmt and $til = $1 or
        /^Fra konto : (.*)$/ and $1 =~ $acctfmt and $fra = $1 or
        /^Bel[^ ]* : (.*)$/ and $1 =~ $amntfmt and $mye = $1 or
        /^Blankettnr. : (.*)$/ and $1 =~ $blnkfmt and $blankett = $1 or
        /^Arkivref. : (.*)$/ and $1 =~ $areffmt and $aref = $1 or
        /^ID nummer : (.*)$/ and $1 =~ $idnrfmt and $id = $1 or
        /^MELDING OM KREDITERING/ and $oppgj and
        new_credit($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id, $nameaddr, $melding) or
        /^BETALER:$/ and $state = GETNAME or
        /^MOTTAKER:$/ and $state = HASNAME or
        /^BEL[^P]*PET GJELDER:$/ and $state = GETMSG or 
        $state == GETNAME and $nameaddr .= $_ . ':;' or
        $state == GETMSG and $melding .= $_ or 1;
}
sub parse_last_line() {
    $oppgj and new_credit($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id, $nameaddr, $melding);
}



# For older (squeeze) poppler-utils
sub parse_payment_line_squeeze {
    if (/^$datefmt $datefmt $acctfmt $acctfmt $amntfmt $blnkfmt $areffmt $idnrfmt/) {
        my ($oppgj, $oppdr, $til, $fra, $mye, $blankett, $aref, $id) = ($1, $2, $3, $4, $5, $6, $7, $8);
        # check all the facts
        # register in db
        my $got = register_payment($oppgj,$oppdr,$til,$fra,$mye,$blankett,$aref,$id,$nameaddr,$melding);
        # send mail on it
        send_ackmail($got);
        $nameaddr = $melding = '';
        $state = RESET;
    }elsif (/^BETALER: MOTTAKER:/) {
        $state = GETNAME;
    }elsif ($state == GETNAME and not $nameaddr and not /^$/){
        ($nameaddr) = /^(.*)$/;
        $state = HASNAME;
    }elsif (/^BELØPET GJELDER:/) {
        $state = GETMSG;
    }elsif ($state == GETMSG and not $melding and not /^$/){
        ($melding) = /^(.*)$/;
        $state = RESET;
    }
}

while (<>) {
    parse_payment_line();
}
parse_last_line();

