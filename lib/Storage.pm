#!/usr/bin/perl -w
use strict;
use warnings;
use Switch;
require "CliAutomation.pm";
require "Server.pm";

package Storage;
sub new {
	my $class = shift;
	my %args = @_;
	bless {
		MIN_SSD_DISKS_FOR_BUILD => 3,
		MIN_SAS_DISKS_FOR_BUILD => 3,
		SAS_STORAGE_POOL => 'SAS_STORAGE_POOL',
		SSD_STORAGE_POOL => 'SSD_STORAGE_POOL',
		TIER1_vDISK => 'TIER1_vDISK',
		TIER2_vDISK => 'TIER2_vDISK',
		SAS => '(SAS)',
		SSD => '(SSD)',
	}, $class;
}
sub shutdownSCMs {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my %scms = $Cli->getSCMs();
	my $first = 1;
	foreach my $scm ( keys %scms ) {
		if(defined($scms{$scm}{"Status"}) && $scms{$scm}{"Status"} !~ m/missing/i) {
			$Cli->cd(dir=>"/storage/$scm");
			$Cli->runCommand("reset safe");
			if($first) {
				sleep 120;
				$first = 0;
			}
		}
	}
}
sub resetScmsNormal {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my %scms = $Cli->getSCMs();
	my $first = 1;
	foreach my $scm ( keys %scms ) {
		if(defined($scms{$scm}{"Status"}) && $scms{$scm}{"Status"} !~ m/missing/i) {
			$Cli->cd(dir=>"/storage/$scm");
			$Cli->runCommand("reset normal");
			if($first) {
				sleep 120;
				$first = 0;
			}
		}
	}
}
sub areScmsSafe {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my %scms = $Cli->getSCMs();
	my $scmsSafe = 1;
	foreach my $scm ( keys %scms ) {
		if(defined($scms{$scm}{"Status"}) && $scms{$scm}{"Status"} !~ m/safe/i) {
			$scmsSafe = 0;
		}
	}
	return $scmsSafe;
}
sub getDrivesByType {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my %retHash = ();
	my %drives = $Cli->getDrives();
	#Foreach drive - get the drive name and the properties object associated
	foreach my $drive ( keys %drives )
	{
		if(defined($drives{$drive}{"ProductID"})) {
			my $parenpos = rindex($drives{$drive}{"ProductID"}, '(');
			my $driveType = substr($drives{$drive}{"ProductID"}, $parenpos);
			switch($driveType) {
				case [$self->{SAS}, $self->{SSD}] {
					if(!defined($retHash{ $driveType })) {
						#print "Creating array for $driveType\n";
						$retHash{ $driveType } = [];
					}
					#print "Pushing $drive to $driveType array\n";
					push(@{$retHash{ $driveType }}, $drive);
				}
				else {
					die "'$driveType' not known!";
				}
			}
		}
	}
	#foreach my $driveType ( keys %retHash )
	#{
	#	print "Drive Type: $driveType\n";
	#	foreach my $drive (@{$retHash{ $driveType}}) {
	#		print "\t$drive\n";
	#	}
	#}
	return %retHash;
}
