#!/usr/bin/perl -w
use strict;
use warnings;
use Net::SSH::Expect;
use Config::IniFiles;
use Time::HiRes;


package CliAutomation;

sub new {
	my $class = shift;
	my %args = @_;
	if(	!defined($args{host}) ||
		!defined($args{password}) ||
		!defined($args{user}) ||
		!defined($args{port}) ||
		!defined($args{log_file}) ||
		!defined($args{timeout}) ||
		!defined($args{verbose}) ||
		!defined($args{prompt})
		)
	{
		die "Not all arguments defined!\n";
	}
	bless {
		COMMANDS => "Commands",
		TARGETS => "Targets",
		PROPERTIES => "Properties",
		OUTCOME => "Outcome",
		RESULT => "Result",
		FAILURE => "Failure",
		SUCCESS => "Success",
		COMMENTS => "Comments",
		VALUE => "Value",
		pwd => "/",
		host => $args{host},
		password => $args{password},
		user => $args{user},
		port => $args{port},
		log_file => $args{log_file},
		timeout => $args{timeout},
		prompt => $args{prompt},
		sessionAlive => 0,
		ssh => Net::SSH::Expect->new (
		    host => $args{host},
		    password=> $args{password},
		    user => $args{user}, 
		    port => $args{port},
		    timeout => 30,
		    log_file => $args{log_file},
		    log_stdout => $args{verbose},
		    raw_pty => 1,
		),
		
	},$class;
}

sub start_session {
	my $self = shift;
	my $login = undef;
	$self->{ssh}->run_ssh();
	if($self->{password} ne "") {
		$self->{ssh}->waitfor('.*[Pp]assword: ?$', 10);
		$self->{ssh}->send($self->{password});
		$self->{ssh}->waitfor($self->{prompt}, 10);
	}
	$self->{sessionAlive} = 1;
	#$self->cd(dir=>"/");
	return 1;
}
sub send_and_get_response {
	my $self = shift;
	my %args = @_;
	my $prompt = defined($args{prompt}) ? $args{prompt} : $self->{prompt};
	my $timeout = defined($args{timeout}) ? $args{timeout} : $self->{timeout};
	my $cmd = $args{command};
	if($self->{sessionAlive} != 1) {
		$self->start_session();
	}
	$self->{ssh}->send($cmd);
	if($self->{ssh}->waitfor($prompt, $timeout)) {
		return $self->{ssh}->before();
	} else {
		die "It appears the script has failed trying to get a response from your last command ($cmd)";
	}
	
}
sub logout {
	my $self = shift;
	my %args = @_;
	my $code = $args{code};
	$self->{ssh}->exec("exit");
	$self->{sessionAlive} = 0;
	exit $code;
}
sub runCommand {
	my $self = shift;
	my $cmd = shift;
	my $ret = 1;
	my $kill = 0;
	my $output = $self->send_and_get_response( command=>$cmd, );
	$output =~ s/$cmd\r?\n//g;
	chomp($output);
	#print "'$output'\n";
	if($output && $output !~ m/connecting to switch .../) {
		
		$ret = Config::IniFiles->new( -file => \$output );
	}
	eval { $ret->SectionExists ('Outcome') };
	if($@) {
		if($output =~ m/%/) {
			$kill = 1;
		}
	}
	elsif(!$ret->SectionExists ('Outcome')) {
		print "Warning: $cmd produced no outcome!\n";
	}
	elsif($ret->val($self->{OUTCOME}, $self->{RESULT}) eq $self->{FAILURE} ){
		$kill = 1;
	}
	
	if($kill) {
		die "Warning: $cmd produced '$output'\n";
		#$self->logout( code=>1 );
	}
	return $ret;
}
sub cd{
	my $self = shift;
	my %args = @_;
	my $dir = $args{dir};
	if(!defined($self->{pwd})) { $self->{pwd} = "/" }
	if($dir eq ".") { $dir = $self->{pwd}; }
	if($dir ne $self->{pwd}) {
		my $ret = $self->runCommand("cd $dir");
		$self->{pwd} = $ret->val($self->{OUTCOME}, $self->{VALUE});#($ret[$self->{OUTCOME}]["Value"]);
		return $ret;
	}
}
sub show{
	my $self = shift;
	my %args = @_;
	my $mode = defined($args{mode}) ? $args{mode} : "";
	return $self->runCommand("show $mode");
}
sub getThingWithTargets{
	my $self = shift;
	my %args = @_;
	my $parentdirectory = $args{parentDirectory};
	my $searchString = $args{searchString};
	#
	my %objHash = ();
	$self->cd(dir => $parentdirectory);
	my $ls = $self->show(mode=>"targets");
	my @targets = $ls->Parameters($self->{TARGETS});
	foreach my $targetName (@targets) {
		if($targetName !~ m/$searchString/) {
			next;
		}
		$self->cd(dir=>$targetName);
		my $propsObj = $self->show(mode=>"properties");
		my @props = $propsObj->Parameters($self->{PROPERTIES});
		foreach my $propName (@props) {
			$objHash { $targetName } { $propName } = $propsObj->val( $self->{PROPERTIES}, $propName );
		}
		$self->cd(dir=>"..");
	}
	return %objHash;
}
sub getSwitches {
	my $self = shift;
	return $self->getThingWithTargets(parentDirectory=>'/switches', searchString=>'switch');
}
sub getVirtualDisksFromPool {
	my $self = shift;
	my %args = @_;
	my $poolId = $args{poolId};
	return $self->getThingWithTargets(parentDirectory=>"/storage/$poolId", searchString=>'vd');
}
sub getPools {
	my $self = shift;
	return $self->getThingWithTargets(parentDirectory=>'/storage', searchString=>'pool');
}
sub getDrives {
	my $self = shift;
	return $self->getThingWithTargets(parentDirectory=>'/storage', searchString=>'drive');
}
sub getServers {
	my $self = shift;
	return $self->getThingWithTargets(parentDirectory=>'/servers', searchString=>'server');
}
sub getSCMs {
	my $self = shift;
	return $self->getThingWithTargets(parentDirectory=>'/storage', searchString=>'scm');
}
sub set {
	my $self = shift;
	my %args = @_;
	my $property = $args {property};
	my $value = $args {value};
	return $self->runCommand("set $property='$value'");
}
sub waitForPropertyValue {
	my $self = shift;
	my %args = @_;
	my $property = $args{property};
	my $value = $args{value};
	my $retryRateMilliseconds = $args{retryRateMilliseconds};
	my $timeoutMilliseconds = defined($args{timeoutMilliseconds}) ? $args{timeoutMilliseconds} : 0;
	my $propertyAlreadyExists = defined($args{propertyAlreadyExists}) ? $args{propertyAlreadyExists} : 1;
	my $usePregEx = defined($args{usePregEx}) ? $args{usePregEx} : 0;
	
	my ($startTime, $startTimeToss) = Time::HiRes::gettimeofday();
	while(1) {
		my $properties = $self->show(mode=>"properties");
		if($propertyAlreadyExists && !defined($properties->val($self->{PROPERTIES},$property))){
			die "'$property' does not exist in current context! Cannot continue.\n";
		}
		if($timeoutMilliseconds > 0) {
			my ($currentTime, $currentTimeToss) = Time::HiRes::gettimeofday();
			if(($currentTime - $startTime) >= ($timeoutMilliseconds/1000)) {
				die "Waiting for value timeout: $property != $value after $timeoutMilliseconds\n";
			}
		}
		if((!$usePregEx && defined($properties->val($self->{PROPERTIES},$property)) && $properties->val($self->{PROPERTIES},$property) eq $value) || 
		   ($usePregEx && defined($properties->val($self->{PROPERTIES},$property)) && $properties->val($self->{PROPERTIES},$property) =~ m/($value)/)) {
			return 1;
		}
		Time::HiRes::usleep($retryRateMilliseconds);
	}
}
1;
