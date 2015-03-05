#!/usr/bin/env perl
use 5.010;
use warnings;
use XML::LibXML;
use String::Util 'trim';
use Data::Dumper qw(Dumper);
use List::Util 'reduce';

# Welcome
# to
# the
# wonderful
# world
# of
# perl
# to
# install
# please
# run
# the
# following
# command
# on
# your
# computer
# cpan XML::LibXML String::Util

my $xml = XML::LibXML->new->parse_html_file($ARGV[0]);
my @nodes = $xml->findnodes('//table[@class="myBox"]//table//table/tbody/tr');


my %months;
my %years;
my %groupsy;
my %groupsm;

sub parse_amount {
   my $amount = shift;
   $amount =~ s/,00//;
   $amount =~ s/,/\./;
   return $amount + 0;
}

for my $list (@nodes) {
	my $date  = trim($list->findvalue('td[position()=1]'));
	my $group = trim($list->findvalue('td[position()=3]'));
	my $in    = trim($list->findvalue('td[position()=4]'));
	my $out   = trim($list->findvalue('td[position()=5]'));
	my $val   = ($in ? $in : "-" . $out);
	$val =~ s/\.//;

	if ($date =~ /^(?:[0-9]{2}\.?)+$/) {
		$date =~ s/^...//g;
		$date = "20" . join('/', reverse(split(/\./, $date)));
		$year = $date;
		$year =~ s/...$//g;

		if (!$groupsm{$group}->{$date}) { $groupsm{$group}->{$date} = []; }
		if (!$groupsy{$group}->{$year}) { $groupsy{$group}->{$year} = []; }
		if (!$months{$date}->{$group}) { $months{$date}->{$group} = []; }
		if (!$years{$year}->{$group}) { $years{$year}->{$group} = []; }

		push($groupsm{$group}->{$date}, $val);
		push($groupsy{$group}->{$year}, $val);
		push($months{$date}->{$group}, $val);
		push($years{$year}->{$group}, $val);
	}
}

say "\r\nYearly";
say "=======";

foreach $key (sort (keys(%years))) {
	print "$key\r\n";
	foreach $g (sort (keys($years{$key}))) {
		printf "\t%-20s\t%-10s\t%s\r\n",
			$g,
			parse_amount(reduce { parse_amount($a) + parse_amount($b) } @{$years{$key}{$g}}),
			join(';', map { sprintf("%10s", $_) } @{$years{$key}{$g}});

	}
}

say "\r\nMonthly:";
say "=======";

foreach $key (sort (keys(%months))) {
	print "$key\r\n";
	foreach $g (sort (keys($months{$key}))) {
		printf "\t%-20s\t%-10s\t%s\r\n",
			$g,
			parse_amount(reduce { parse_amount($a) + parse_amount($b) } @{$months{$key}{$g}}),
			join(';', map { sprintf("%10s", $_) } @{$months{$key}{$g}});
	}
}
