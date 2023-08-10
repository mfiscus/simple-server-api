#!/usr/bin/perl -w
use strict;
use warnings;
use Net::SNMP;
use NetSNMP::OID;
use Data::Dumper;

sub snmpRequests {
	my %args = @_;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $host = (defined($args{host})) ? $args{host} : undef;
	my $session = (defined($args{session})) ? $args{session} : undef;
	if($host && $session) {
		warn "Both host ($host) and session are set. Ignoring $host and using session.\n";
	}
	if(!$session) { $session = openSnmpSession(host=>$host, verbose=>$verbose, ); }
	my $closeSession = (defined($args{closeSession})) ? $args{closeSession} : 1;
	if($session && !defined($args{closeSession})) { $closeSession = 0; }
	my @oids = @{$args{oids}};
	my @numOIDs = processOIDs(oids=>\@oids, verbose=>$verbose);
	if($verbose) { print "Processed OIDs\n"; }
	if($verbose) { print "Performing get_request.\n"; }
	my $results = $session->get_request(-varbindlist => \@numOIDs,);
	if($verbose) { print "Request complete.\n"; }
	if(!defined($results)) { die "ERROR: " . $session->error() . "\n"; }
	if($verbose) { print "Error check passed.\n"; }
	my $oidCount = scalar(@oids);
	for(my $i=0; $i < $oidCount; $i++) {
		my $oidName = $oids[$i];
		my $oidNumber = $numOIDs[$i];
		if($verbose) { print "Mapping $oidName to $oidNumber (" . $results->{$oidNumber} . ")\n"; }
		$results->{$oidName} = $results->{$oidNumber};
	}
	if($closeSession) {
		closeSnmpSession( session=>$session, verbose=>$verbose);
		return $results;
	}
	return ($results, $session);
}
sub processOIDs {
	my %args = @_; 
	my @oids = @{$args{oids}};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	if($verbose) { print "Processing " . scalar(@oids) . " oids.\n"; }
	my @newOids = ();
	foreach my $oidStr (@oids) {
		if($verbose) { print "\tProcessing '$oidStr': "; }
		my $oid = NetSNMP::OID->new($oidStr);
		my @numarray = $oid->to_array();
		my $oidNumStr = '';
		my $first = 1;
		foreach my $num (@numarray) {
			if(!$first) {
				$oidNumStr .= '.';
			}
			$oidNumStr .=  $num;
			$first = 0;
		}
		if($verbose) { print "$oidNumStr\n"; }
		push(@newOids, $oidNumStr);
	}
	return @newOids;
}
sub openSnmpSession {
	my %args = @_;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $host = (defined($args{host})) ? $args{host} : undef;
	if(!$host) { die "ERROR: No host ($host) or session set!\n"; }
	if($verbose) { print "Opening up a new session to $host\n"; }
	my ($session, $error) = Net::SNMP->session(
		-hostname => $host,
		-community => 'public',
		-version => 2,
	);
	if (!defined $session) { die "ERROR: $error.\n"; }
	if($verbose) { print "Session created.\n"; }
	return $session;
}
sub closeSnmpSession {
	my %args = @_;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $session = (defined($args{session})) ? $args{session} : undef;
	if($verbose) { print "Closing session.."; }
	$session->close();
	if($verbose) { print "session closed\n"; }
}
1;
