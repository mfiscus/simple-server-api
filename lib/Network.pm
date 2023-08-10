#!/usr/bin/perl -w

use strict;
use warnings;
use Net::Ping;
use Net::DNS;
use Data::Dumper;
sub simplePing {
	my %args = @_;
	my $dest = $args{dest};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	if(!defined($args{dest})) { return 0; }
	chomp($dest);
	if($dest eq "") { die "Destination Address is empty!\n"; }
	my $p = Net::Ping->new("icmp");
	if($verbose) { print "Pinging $dest: "; }
	my $result = $p->ping($dest);
	if($verbose) { print "" . (($result)?'success.' : 'failure') . "\n"; }
	#if(!$result) { print "Could not ping $dest.\n";}
	$p->close();
	return $result;
}
sub getSubnetOfHostname {
	my %args = @_;
	my $hostName = $args{hostname};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $res = Net::DNS::Resolver->new();
	if($verbose) { print "Looking up $hostName.."; }
	my $record = $res->query($hostName, "A");
	if(!defined($record)) { die "ERROR - Can't find $hostName in DNS\n"; }
	foreach my $answer ($record->answer) {
		if("Net::DNS::RR::A" eq ref($answer)) {
			my $subnet = join(".", (split(/\./, $answer->address))[0,1,2]); 
			if($verbose) { print "subnet is $subnet\n"; }
			return $subnet;
		}
	}
}
sub getLocationnumFromIP {
	my %args = @_;
	my $hostName = $args{hostname};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $res = Net::DNS::Resolver->new();
	if($verbose) { print "Looking up $hostName.."; }
	my $subnet = join(".", (split(/\./, $hostName))[0,1,2]); 
	$hostName = "$subnet.186";
	my $record = $res->query($hostName, "A");
	if(!defined($record)) { die "ERROR - Can't find $hostName in DNS\n"; }
	foreach my $answer ($record->answer) {
		if("Net::DNS::RR::PTR" eq ref($answer)) {
			my $locationNum = $answer->ptrdname;
			$locationNum =~ s/vma(\d{1,5})\.fisc\.us/$1/;
			if($verbose) { print "Location Number is '$locationNum'\n"; }
			return $locationNum;
		}
	}
}
1;
