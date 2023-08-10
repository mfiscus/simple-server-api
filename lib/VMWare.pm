#!/usr/bin/perl -w

use strict;
use warnings;
use HTTP::Request;
use VMware::VIFPLib;
use VMware::VIRuntime;

require "Network.pm";


sub reconfigureVMA2ndNic {
	my %args = @_;
	#Debug bit.
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	#Username
	my $username = $args{username};
	#Password
	my $password = $args{password};
	#Network To configure to
	my $new_network = $args{network};
	#Vcenter IP/Address. Not required if we have a session established.
	my $vcenter = $args{vcenter};
	my $session = (defined($args{session})) ? $args{session} : "buh";
	#Default closing the session to true....
	my $closeSession = (defined($args{closeSession})) ? $args{closeSession} : 1;
	#Unless of course it was already defined when it was passed into the function
	#Then we explicitly WON'T close it unless specified.
	if($session ne "buh" && !defined($args{closeSession})) { $closeSession = 0; }
	if($session eq "buh") {
		$session = getVMSDKSession(host=>$vcenter, username=>$username, password=>$password, verbose=>$verbose);
	}
	
	my $vma = $session->find_entity_view (view_type => 'VirtualMachine', filter => {name => 'vma'} );
	
	# find the first card.
	my $devices = $vma->config->hardware->device;
	my $netCard = undef;
	foreach my $dev (@$devices) {
		next unless ($dev->isa ("VirtualEthernetCard"));
		my $devName = $dev->deviceInfo->label;
                if($devName =~ m/Network adapter 2/i) {
                        $netCard = $dev;
                        last;
                }
	}
	my $host_view = $session->get_view(mo_ref => $vma->runtime->host);
	my $host_network_list = $session->get_views(mo_ref_array => $host_view->network);
	my $network = undef;
	foreach (@$host_network_list){
		next unless ($new_network eq $_->name);
		$network = $_;
		last;
	}
	
	# $network holds the reference to the new network
	my $backing_info = VirtualEthernetCardNetworkBackingInfo->new(deviceName => $network->name, network => $network);
	
	#change the backing info to the new network
	$netCard->backing($backing_info);
	my $config_spec_operation = VirtualDeviceConfigSpecOperation->new('edit');
	my $devspec = VirtualDeviceConfigSpec->new(operation => $config_spec_operation, device => $netCard);
	my $vmspec = VirtualMachineConfigSpec->new(deviceChange => [$devspec]);
	if($verbose) { print "Reconfiguring vma to use $new_network on second nic.\n"; }
	eval {
		$vma->ReconfigVM( spec => $vmspec );
	};
	if ($@) {
	print "\nReconfiguration failed: ";
	print "\n" . $@ . "\n";
	die "Reconfiguration failed";
	}
}
sub findVM {
	my %args = @_;
	my %hypervisors = %{$args{hypervisors}};
	my $username = $args{username};
	my $password = $args{password};
	my $vmname = $args{vmname};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	if($verbose) { print "Entered findVM function.\n"; }
	foreach my $hv (keys %hypervisors) {
		if($verbose) { print "Searching for $vmname on $hv (" . $hypervisors{$hv} . ")\n"; }
		if(!simplePing(dest => $hypervisors{$hv}, verbose => $verbose) ){ next; }
		my $host_session = getVMSDKSession(host=>$hypervisors{$hv}, username=>$username, password=>$password, verbose=>$verbose);
		if($verbose) { print "Logged in successfully, searching for $vmname\n"; }
		my $vm = $host_session->find_entity_view (view_type => 'VirtualMachine', filter => {name => $vmname} );
		if($vm) {
			if($verbose) { print "Found $vmname on " . $hypervisors{$hv} . ". Returning host session and VM object.\n"; }
			return ($host_session , $vm );
		}
	}
	die "Could not find $vmname on any host provided!\n";
}
sub findVCVA {
	my %args = @_;
	my %hypervisors = %{$args{hypervisors}};
	my $username = $args{username};
	my $password = $args{password};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	if($verbose) { print "Entered findVCVA function.\n"; }
	my $foundVCVA = 0;
	foreach my $hv (keys %hypervisors) {
		if($verbose) { print "Searching for VCVA on $hv (" . $hypervisors{$hv} . ")\n"; }
		if(!simplePing(dest => $hypervisors{$hv}, verbose => $verbose) ){ next; }
		my $host_session = getVMSDKSession(host=>$hypervisors{$hv}, username=>$username, password=>$password, verbose=>$verbose);
		if($verbose) { print "Logged in successfully, searching for vcva\n"; }
		my $vcva = $host_session->find_entity_view (view_type => 'VirtualMachine', filter => {name => 'vcva'} );
		my $vcvaIp = undef;
		if($vcva) {
			$foundVCVA = 1;
			if($verbose) { print "Found " . $vcva->name . " on " . $hypervisors{$hv} . ".\n"; }
			if(!confirmMgmtVm(ip=>$vcva->guest->ipAddress, verbose=>$verbose,)) {
				repairMgmtVm(vm_name=>$vcva->name, ip=>$vcva->guest->ipAddress, session=>$host_session, force=>1, verbose=>$verbose);
			}
			$vcvaIp = $vcva->guest->ipAddress;
		}
		$host_session->logout();
		return getVMSDKSession(host=>$vcvaIp, username=>$username, password=>$password, verbose=>$verbose);
	}
	if(!$foundVCVA) {
		die "Could not find vcva on any hosts!\n";
	}
}
sub repairSimpleVm {
	my %args = @_;
	my $vmName = $args{vm_name};
	my $ip = $args{ip};
	my $vcenterIP = $args{vc};
	my $username = $args{username};
	my $password = $args{password};
	my $session = (defined($args{session})) ? $args{session} : "buh";
	my $closeSession = (defined($args{closeSession})) ? $args{closeSession} : 1;
	if($session ne "buh" && !defined($args{closeSession})) { $closeSession = 0; }
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $timeout = defined($args{timeout}) ? $args{timeout} : 600;
	my $vm = defined($args{vm}) ? $args{vm} : 0;
	my $force = defined($args{force}) ? $args{force} : 0;
	my $timeElapsed = 0;
	if($session eq "buh") {
		$session = getVMSDKSession(host=>$vcenterIP, username=>$username, password=>$password, verbose=>$verbose);
	}
	if($verbose) { print "Attempting to repair $vmName (simple)\n"; }
	if(!simplePing(dest => $ip, verbose=>$verbose) || $force) {
		if(!$vm) { $vm = $session->find_entity_view (view_type => 'VirtualMachine', filter => {name => $vmName} ); }
		if($vm->runtime->powerState->val eq 'poweredOn'){
			#Reset VM
			if($verbose) { print "Resetting $vmName - this will take a bit.\n"; }
			resetVM(session=>$session, vm=>$vm, verbose=>$verbose);
		}
		elsif ($vm->runtime->powerState->val eq 'poweredOff') {
			#Poweron VM
			if($verbose) { print "Powering on $vmName - this will take a bit.\n"; }
			powerOnVM(session=>$session, vm=>$vm, verbose=>$verbose);
		}
		
		while(!defined($vm->guest->ipAddress) ) {
			if($timeElapsed > $timeout) { die $vm->name . " did not power up in $timeout seconds!\n"; }
			if($verbose) { print $vm->name . " powered on, now waiting for network connectivity\n"; }
			sleep 20;
			$timeElapsed += 20;
			$vm->ViewBase::update_view_data();
		}
		while(!simplePing(dest => $vm->guest->ipAddress, verbose=>$verbose)) {
			if($timeElapsed > $timeout) { die $vm->name . " was not reachable on the network in $timeout seconds!\n"; }
			if($verbose) { print $vm->name . " powered on, now attempting to ping\n"; }
			sleep 20;
			$timeElapsed += 20;
		}
	}
	if($closeSession) { closeVMSDKSession(session=>$session, verbose=>$verbose); }
	return ($vm, $timeElapsed);
}
sub confirmMgmtVm {
	my %args = @_;
	my $ip = $args{ip};
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $timeout = defined($args{timeout}) ? $args{timeout} : 600;
	my $timeElapsed = defined($args{timeElapsed}) ? $args{timeElapsed} : 0;
	
	if(!defined($args{ip})) { return 0; }
	if($verbose) { print "Confirming Management VM ($ip) is alive through ping\n";}
	my $vmAlive = simplePing( dest => $ip, verbose=>$verbose );
	if($vmAlive) {
		if($verbose) { print "Management VM ($ip) is alive, testing web services\n";}
		my $ua = LWP::UserAgent->new;
		my $continue = 1;
		do {
			my $url =  "https://$ip/";
			my $request = HTTP::Request->new(GET => $url); 
			my $response = $ua->request($request);
			if ($response->is_success) {
				$continue = 0;
			}
			else {
				if($timeElapsed > $timeout) { die "$ip web services did not come up in $timeout seconds!\n"; }
				if($verbose) { print "$ip is up and on network - waiting for services to come up. " . ($timeout - $timeElapsed) . " seconds left until timeout.\n"; }
				sleep 20;
				$timeElapsed += 20;
			}
		}while($continue);
	}
	if($verbose) { print "Management VM ($ip) is" . (($vmAlive) ? " " : " NOT ") . "responding on port 443.\n";}
	return ($vmAlive, $timeElapsed);
}
sub repairMgmtVm {
	my %args = @_;
	my $vmName = $args{vm_name};
	my $ip = $args{ip};
	my $session = (defined($args{session})) ? $args{session} : "buh";
	my $closeSession = (defined($args{closeSession})) ? $args{closeSession} : 1;
	if($session ne "buh" && !defined($args{closeSession})) { $closeSession = 0; }
	my $vm = defined($args{vm}) ? $args{vm} : 0;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $timeout = defined($args{timeout}) ? $args{timeout} : 600;
	my $force = defined($args{force}) ? $args{force} : 0;
	my $timeElapsed = 0;
	
	if($verbose) { print "Attempting to repair $vmName (Mgmt)\n"; }
	($vm, $timeElapsed) = repairSimpleVm(vm_name=>$vmName, ip=>$ip, session=>$session, timeout=>$timeout, vm=>$vm, closeSession=>$closeSession, force=>$force, verbose=>$verbose);
	my $vmalive = 1;
	($vmalive, $timeElapsed) = confirmMgmtVm(ip=>$ip,timeout=>$timeout, timeElapsed=>$timeElapsed, verbose=>$verbose );
	if($closeSession) { closeVMSDKSession(session=>$session, verbose=>$verbose); }
}
sub getVMSDKSession {
	my %args = @_;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $sdkHost = $args{host};
	my $username = $args{username};
	my $password = $args{password};
	if(!simplePing(dest => $sdkHost, verbose => $verbose) ){ die "Can't communicate with $sdkHost on network!"; }
	my $session = Vim->new(service_url => "https://$sdkHost/sdk",);
	if($verbose) { print "Connecting as $username\n"; }
	$session->login(user_name => $username, password => $password,);
	if($verbose) { print "Logged in to $sdkHost successfully\n"; }
	return $session;
}
sub closeVMSDKSession {
	my %args = @_;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	my $session = $args{session};
	if($verbose) { print "Closing session.."; }
	$session->logout();
	if($verbose) { print "complete\n"; }
}

sub enterMaintModeHost{
	my %args = @_;
	my $session = $args{session};
	my $host = $args{host};
	my $timeout = 300;
	my $verbose = 0;
	
	if( ! $host->runtime->inMaintenanceMode && $host->runtime->connectionState->val eq 'connected') {
		handleTask( task=>$host->EnterMaintenanceMode_Task(evacuatePoweredOffVms => 1,timeout=>$timeout), timeout=>$timeout, verbose=>$verbose, session=>$session);
	}

}
sub exitMaintModeHost{
	my %args = @_;
	my $session = $args{session};
	my $host = $args{host};
	my $timeout = defined($args{timeout}) ? $args{timeout} : 300;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	if( $host->runtime->inMaintenanceMode ) {
		if($verbose) { print "exiting host " . $host->name . "from MaintMode.\n"; } 
		handleTask( task=>$host->ExitMaintenanceMode_Task( timeout => $timeout ), timeout=>$timeout, verbose=>$verbose, session=>$session );
	}
	elsif ($verbose) {
		print "host " . $host->name . " not in maintenance mode\n";
	}
}

sub resetVM {
	my %args = @_;
	my $session = $args{session};
	my $vm = $args{vm};
	my $timeout = defined($args{timeout}) ? $args{timeout} : 300;
	my $verbose = defined($args{verbose}) ? $args{verbose} : 0;
	if($vm->runtime->powerState->val ne 'poweredOff') {
		if($verbose) { print "Resetting " . $vm->name . ".\n"; }
		eval {
			handleTask( task=>$vm->ResetVM_Task(), timeout=>$timeout, verbose=>$verbose, session=>$session);
		};
		if($@) { die "Couldn't reset " . $vm->name . "!\n"; }
	}
	else {
		die "can't reset a poweredoff vm";
	}
}
sub handleTask {
	my %args = @_;
	my $timeout = $args{timeout};
	my $session = $args{session};
	my $task = $args{task};
	my $counter = 0;
	my $continue = 1;
	my $taskView = $session->get_view(mo_ref => $task);
	do {
		my $info = $taskView->info;
		if ($info->state->val eq 'success') {
			$continue = 0;
		} elsif ($info->state->val eq 'error') {
			return "false";
		}
		sleep 1;
		$taskView->ViewBase::update_view_data();
		$counter++;
		if($counter > $timeout) {
			return "false";
		}
	} while ($continue);
}
