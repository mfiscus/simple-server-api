#!/usr/bin/perl -w
use strict;
use warnings;
use Switch;
require "CliAutomation.pm";

package Server;
sub new {
	my $class=shift;
	my %args = @_;
	bless {
	}, $class;
}
sub GetServerNumberFromName {
	my $self = shift;
	my %args = @_;
	my $serverName = $args{server};
	return substr $serverName,-1,1;
}
sub isMissing {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	$Cli->cd(dir=>"/servers/$serverName");
	my $properties = $Cli->show(mode=>"properties");
	return (!defined($properties->val($Cli->{PROPERTIES},"Status")) || $properties->val($Cli->{PROPERTIES},"Status") =~ m/missing/);
}
sub isOff {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	$Cli->cd(dir=>"/servers/$serverName");
	my $properties = $Cli->show(mode=>"properties");
	return ($properties->val($Cli->{PROPERTIES},"Status") =~ m/OFF/);
}
sub PowerOn {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	$Cli->cd(dir=>"/servers/$serverName");
	my $properties = $Cli->show(mode=>"properties");
	if(!$self->isMissing(Cli=>$Cli, server=>$serverName)) {
		if($properties->val($Cli->{PROPERTIES},"Status") =~ m/OFF/) {
			$Cli->runCommand("poweron confirm");
			sleep 5;
		}
		return 1;
	}
	return 0;
}
sub PowerOff {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	my $mode = defined($args{mode}) ? $args{mode} : 'graceful';
	
	$Cli->cd(dir=>"/servers/$serverName");
	my $properties = $Cli->show(mode=>"properties");
	if(!$self->isMissing(Cli=>$Cli, server=>$serverName)) {
		if($properties->val($Cli->{PROPERTIES},"Status") =~ m/ON/) {
			$Cli->runCommand("poweroff $mode");
		}
	}
}
sub GetMacAddress {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	if(!$self->isMissing(Cli=>$Cli, server=>$serverName)) {
		$Cli->cd(dir=>"/servers/$serverName");
		my $properties = $Cli->show(mode=>"properties");
		if($properties->val($Cli->{PROPERTIES}, 'MAC1') !~ m/(([0-9A-F]{2}:){5}[0-9A-F]{2})/)
		{
			if($self->PowerOn(Cli=>$Cli, server=>$serverName)) {
				$Cli->cd(dir=>"/servers/$serverName");
				$Cli->waitForPropertyValue (
					property => 'MAC1',
					value => '(([0-9A-F]{2}:){5}[0-9A-F]{2})',
					retryRateMilliseconds => 5000,
					usePregEx => 1,
				);
				$properties = $Cli->show(mode=>"properties");
			}
		}
		my $mac = $properties->val($Cli->{PROPERTIES}, 'MAC1'); 
		$self->PowerOff(Cli=>$Cli, server=>$serverName);
		return $mac;
	}
	return "0";
}
sub lightUID {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	my $seconds = defined($args{seconds}) ? $args{seconds} : 900;
	if($seconds > 900) {
		$seconds = 900;
	}
	if($seconds < 1) {
		$seconds = 1;
	}
	if(!$self->isMissing(Cli=>$Cli, server=>$serverName)) {
		$Cli->cd(dir=>"/servers/$serverName");
		$Cli->runCommand("identify $seconds");
	}
}
sub PXEBoot {
	my $self = shift;
	my %args = @_;
	my $Cli = $args{Cli};
	my $serverName = $args{server};
	$Cli->cd(dir=>"/servers/$serverName");
	my $properties = $Cli->show(mode=>"properties");
	if(!$self->isMissing(Cli=>$Cli, server=>$serverName)) {
		if($properties->val($Cli->{PROPERTIES},"Status") =~ m/ON/) {
			$Cli->cd(dir=>"/servers/$serverName");
			$Cli->waitForPropertyValue (
				property => 'Status',
				value => 'OK, ON',
				retryRateMilliseconds => 5000,
			);
			$Cli->runCommand("poweroff forced");
			$Cli->waitForPropertyValue (
				property => 'Status',
				value => 'OFF',
				retryRateMilliseconds => 10000,
				usePregEx => 1,
			);
			sleep(10);
		}
		$Cli->cd(dir=>"/servers/$serverName");
		$Cli->runCommand("poweron oneshotboot pxe");
		
		return 1;
	}
	return 0;
}
