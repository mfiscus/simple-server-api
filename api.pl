#!/usr/bin/perl -w

my $LIBPATH = "./lib/";

#---Standard Perl & VMware includes
#use strict;
use warnings;
use Data::Dumper;
use VMware::VIFPLib;
use VMware::VIRuntime;
require HTTP::Request;
require $LIBPATH . "Location.pm";
require $LIBPATH . "Storage.pm";
require $LIBPATH . "VMWare.pm";
require $LIBPATH . "SNMP.pm";

my %opts = (
    tool => {
        type => "=s",
        help => "Tool name\n\tcertFix\n\tpowerDown\n\tpowerOffVm\n\tpowerOnVm\n\tgetVmState\n\tconfigNtp\n\thostState\n\thostPowerOff\n\thostPowerOn\n\tgetScmState\n\tscmSafe\n\tscmReset\n\tgetSwitchState\n\trebuildDrive\n\ttier2Prep\n\ttier2Post",
        required => 1,
    },
    locationnumber => {
        type => "=s",
        help => "Location number",
        required => 1,
    },
    drivenumber => {
        type => "=i",
        help => "Hard drive number",
        required => 0,
    },
    hostnumber => {
        type => "=i",
        help => "ESXi host number",
        required => 0,
    },
    scmnumber => {
        type => "=i",
        help => "Storage controller module number",
        required => 0,
    },
    switchnumber => {
        type => "=i",
        help => "Switch module number",
        required => 0,
    },
    vmname => {
        type => "=s",
        help => "Virtual machine name",
        required => 0,
    },
    date => {
        type => "=s",
        help => "Date (epoch unix time)",
        required => 0,
    },
    verbose => {
        type => "=i",
        help => "Enable verbose output [0|1]",
        required => 0,
    },
    
);

Opts::add_options(%opts);
Opts::parse();

if ( !defined(Opts::get_option('tool')) || !defined(Opts::get_option('locationnumber')) ) {
    Opts::validate();
    
}

my $verbose = ( Opts::get_option('verbose') && Opts::get_option('verbose') =~ /^\d+?$/ ) ? Opts::get_option('verbose') : 0;
my $tool = Opts::get_option('tool');
my $locationnumber = ( Opts::get_option('locationnumber') =~ /^\d+?$/ ) ? sprintf( "%d",Opts::get_option('locationnumber') ) : 0;
my $username = 'root';
my $vcvapassword = getPassword( hostname => 'vcva' );
my $cmmusername = 'admin';
my $cmmpassword = getPassword( hostname => 'cmm' );
my $locationLan2Sub = getSubnetOfHostname( hostname => "vma" . $locationnumber . ".fisc.us", verbose => $verbose );
my $vcva = $locationLan2Sub . ".185";
my $locationvma = $locationLan2Sub . ".186";
my $cmmip = $locationLan2Sub . ".187";
my $snmpget = "snmpget -v2c -Ovq -c public " . $cmmip . " ";


# =========================================================================== #
# Function Name: wlog()
#
# Purpose: Write output to log file
# =========================================================================== #
sub wlog {
    my $LOG_FILE = "/var/log/api.log";
    my $message = $_[1];
    my $call_script = $_[0];
    my $MyDate = `date`;
    chomp($MyDate);

    open(LOGF, ">>$LOG_FILE") or die "Could not open log file\n";
        print $message . "\n";
        print LOGF "$MyDate - $call_script - $tool - $locationnumber - $message \n";
    close(LOGF);
    
}#End wlog()


# =========================================================================== #
# Function Name: bytesToHuman()
#
# Purpose: Converts bytes to human readable format
#
# Expects: bytes string
# =========================================================================== #
sub bytesToHuman($) {
    my $c = shift;
    $c >= 1073741824 ? sprintf("%0.2f GB", $c/1073741824)
        : $c >= 1048576 ? sprintf("%0.2f MB", $c/1048576)
        : $c >= 1024 ? sprintf("%0.2f KB", $c/1024)
        : $c . " bytes";
    
}


# =========================================================================== #
# Function Name: openSession()
#
# Purpose: Opens a session to the vmware sdk
#
# Expects: host, username, password, verbose
# =========================================================================== #
sub openSession() {
    my %args = @_;
    my $session;
    eval {
        $session = getVMSDKSession(
            host => $vcva,
            username => $username,
            password => $vcvapassword,
            verbose => $verbose
        );
        
    };
    
    if ( $@ ) {
        return "false";
        
    } else {
        return $session;
        
    }
    
}


# =========================================================================== #
# Function Name: getActiveScm()
#
# Purpose: Returns the active scm number
#
# Expects: none
# =========================================================================== #
sub getActiveScm() {
    my $snmp;
    my $scmCount = 'numOfScms.0';
    my @oids = ();
    push(@oids, $scmCount);
    
    my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    for(my $i = 1; $i <= $snmp->{$scmCount}; $i++) {
        push(@oids, "scmRole.$i");
        
    }
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
    
    for(my $j = 1; $j <= $snmp->{$scmCount}; $j++) {
        if ( defined($snmp->{"scmRole.$j"}) && $snmp->{"scmRole.$j"} eq "1" ) {
            return $j;
            last;
            
        }
        
    }
    
}


# =========================================================================== #
# Function Name: getDriveType()
#
# Purpose: Returns drive type
#
# Expects: drive number
# =========================================================================== #
sub getDriveType {
    my %args = @_;
    my $drivenumber = $args{drivenumber};
    my $driveType = "sDriveType.$drivenumber";
    my $snmp;
    
    my @oids = ();
    
    my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
    
    push(@oids, $driveType);
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
    
    return $snmp->{$driveType};
    
}


# =========================================================================== #
# Function Name: getDriveSize()
#
# Purpose: Returns drive size
#
# Expects: drive number
# =========================================================================== #
sub getDriveSize {
    my %args = @_;
    my $drivenumber = $args{drivenumber};
    my $driveSize = "sDrivePhysicalCapacity.$drivenumber";
    my $snmp;
    
    my @oids = ();
    
    my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
    
    push(@oids, $driveSize);
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
    
    return $snmp->{$driveSize};
    
}


# =========================================================================== #
# Function Name: getStoragePoolID()
#
# Purpose: Returns storage pool id
#
# Expects: drive number
# =========================================================================== #
sub getStoragePoolID {
    my %args = @_;
    my $drivenumber = $args{drivenumber};
    my $driveStoragePoolID = "sDriveStoragePoolID.$drivenumber";
    my $snmp;
    
    my @oids = ();
    
    my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
    
    push(@oids, $driveStoragePoolID);
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
    
    return $snmp->{$driveStoragePoolID};
    
}


# =========================================================================== #
# Function Name: getStoragePoolCondition()
#
# Purpose: Returns storage pool condition
#
# Expects: storage pool id
# =========================================================================== #
sub getStoragePoolCondition {
    my %args = @_;
    my $storagePoolID = $args{storagePoolID};
    my $storagePoolCondition = "poolCondition.$storagePoolID";
    my $snmp;
    
    my @oids = ();
    
    my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
    
    push(@oids, $storagePoolCondition);
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
    
    return $snmp->{$storagePoolCondition};
    
}


# =========================================================================== #
# Function Name: getStoragePoolName()
#
# Purpose: Returns storage pool name
#
# Expects: storage pool id
# =========================================================================== #
sub getStoragePoolName {
    my %args = @_;
    my $storagePoolID = $args{storagePoolID};
    my $storagePoolName = "poolAlias.$storagePoolID";
    my $snmp;
    
    my @oids = ();
    
    my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
    
    push(@oids, $storagePoolName);
    
    ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
    
    closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
    
    return $snmp->{$storagePoolName};
    
}


# =========================================================================== #
# Function Name: openCli()
#
# Purpose: Opens a session to the CMM cli
#
# Expects: none
# =========================================================================== #
sub openCli() {
    my $Cli;
    
    eval {
        $Cli = CliAutomation->new(
            host => $cmmip,
            password => $cmmpassword,
            user => $cmmusername,
            port => 2200,
            log_file => "/tmp/api.$locationnumber.cmm",
            timeout => 600,
            prompt => '.*[#>] ?$',
            verbose=> 0,
        );
        
    };
    
    if ( $@ ) {
        return "false";
        
    } else {
        return $Cli;
        
    }
    
}


# =========================================================================== #
# Function Name: closeSession()
#
# Purpose: Closes the vmware sdk session
#
# Expects: session, verbose
# =========================================================================== #
sub closeSession() {
    my %args = @_;
    closeVMSDKSession(
        session => $args{session},
        verbose => $args{verbose}
    );
    
}


# =========================================================================== #
# Function Name: throwError()
#
# Purpose: Error handling
#
# Expects: message, code, verbose
# =========================================================================== #
sub throwError {
    my %args = @_;
    wlog("api", "[ERROR] " . $args{message});
    exit 1;
    
}



########################
### BEGIN: api tools ###
########################


# Safely power down the IMS
sub powerDown() {
    print "Power down request initiated.\n";
    exec("/bin/nice -n 19 /usr/local/bin/config_poweroffall.pl --verbose 0 --location $locationnumber &>/dev/null &");
    
}


# Shutdown a virtual machine operating system
sub powerOffVm {
    my $vmname = Opts::get_option('vmname');
    
    if ( defined($vmname) ) {
        my $session;
        eval {
            $session = openSession();
            
        };
        
        if ( $@ ) {
            throwError(message=>"-1001");
            
        }
        
        my $iStartTime = time;
        my $vm = $session->find_entity_view( view_type => 'VirtualMachine', filter => { name => $vmname } );
        my $timeout = 600;
        my $iMaxTime = $iStartTime + $timeout;
        my $verbose = 0;
        
        if($vm->runtime->powerState->val ne 'poweredOff') {
            eval {
                $vm->ShutdownGuest();
                
            };
            
            if ( ! $@ ) {
                while ( $vm->runtime->powerState->val ne 'poweredOff' && ( time < $iMaxTime ) ) {
                    sleep 1;
                    $vm->update_view_data();
                    
                }
                
                if ( $vm->runtime->powerState->val ne 'poweredOff' ) {
                    eval {
                        handleTask(
                            task => $vm->PowerOffVM_Task(),
                            timeout => $timeout,
                            verbose => $verbose,
                            session => $session
                        );
                        
                    };
                    
                }
                
                $vm->update_view_data();
                if ( $vm->runtime->powerState->val eq 'poweredOff' ) {
                    print 'Successfully powered off ' . $vm->name . "\n";
                    return 1;
                    
                } else {
                    throwError( message=>'-1002' );
                    
                }
                
            }
            
        } else {
            print $vm->name . " is already powered off.\n";
            
        }
        
    }
    
}


# Boot a virtual machine operating system
sub powerOnVm() {
    my $vmname = Opts::get_option('vmname');
    
    if ( defined($vmname) ) {
        my $session;
        eval {
            $session = openSession();
            
        };
        
        if ( $@ ) {	
            throwError( message=>'-1001' );
            
        }
        
        my $vm = $session->find_entity_view( view_type => 'VirtualMachine', filter => { name => $vmname } );
        my $timeout = 600;
        my $verbose = 0;
        
        if( $vm->runtime->powerState->val ne 'poweredOn' ) {
            eval {
                handleTask(
                    task => $vm->PowerOnVM_Task(),
                    timeout => $timeout,
                    verbose => $verbose,
                    session => $session
                );
                
            };
            
            if( $@ ) {
                throwError( message => '-1003' );
                
            } else {
                $vm->update_view_data();
                if ( $vm->runtime->powerState->val eq 'poweredOn' ) {
                    print 'Successfully powered on ' . $vm->name . "\n";
                    return 1;
                    
                } else {
                    throwError( message=>'-1003' );
                    
                }
                
            }
            
        } else {
            print $vm->name . " is already powered on.\n";
            
        }
        
    }
    
}


# Get the power state of a virtual machine
sub getVmState() {
    my $vmname = Opts::get_option('vmname');
    my $session;
    if( defined($vmname) ) {
        eval {
            $session = openSession();
            
        };
        
        if ( $@ ) {	
            throwError( message=>'-1001' );
            
        }
        
        my $vmhandle = $session->find_entity_view( view_type => 'VirtualMachine', filter => { name => $vmname } );
        
        if ( $vmhandle ) {
            print $vmhandle->runtime->powerState->val . "\n";
            
        }
        
    } else {
        return "false";
        
    }
    
}


# Configure network time protocol on esxi hosts
sub configNtp() {
    my $session;
    
    eval {
        $session = openSession();
        
    };
    
    if ( $@ ) {	
        throwError( message=>'-1001' );
        
    }
    
    #---Setup New NTP Settings structure
    my @NTP_Servers = ["ntp.fisc.us","nnm02.fisc.us","nnm04.fisc.us"];
    
    my $HostNtpCfg = HostNtpConfig->new(
        server => @NTP_Servers
    );
    
    my $HostDTTMConfig = HostDateTimeConfig->new(
        ntpConfig => $HostNtpCfg,
    );
    
    #---Get a handle to the ESXi host
    my $hs_list = $session->find_entity_views( view_type => 'HostSystem' );
    unless (defined $hs_list) {
        throwError( message=>'-1004' );
    	
    }
    
    foreach(@$hs_list) {
        my $hs_Entity = $_;
        
        my $hs_HostDTTMMgr = $session->get_view( mo_ref => $hs_Entity->configManager->dateTimeSystem );
        
        eval {
            handleTask(
                task => $hs_HostDTTMMgr->UpdateDateTimeConfig(config => $HostDTTMConfig),
                timeout => $timeout,
                verbose => $verbose,
                session => $session
            );
            
        };
        
        if( $@ ) {
            my $ntperror = '-1011';
            
        } else {
            
            my $serviceSystem = $session->get_view(mo_ref => $hs_Entity->configManager->serviceSystem);
            
            eval {
                handleTask(
                    task => $serviceSystem->RestartService(id => "ntpd"),
                    timeout => $timeout,
                    verbose => $verbose,
                    session => $session
                );
                
            };
            
            if($@) {
                my $restarterror = '-1012';
                
            }
            
        }
        
    }#End foreach
    
    if ( defined($ntperror) ) {
        throwError( message => $ntperror );
        
    } elsif ( defined($restarterror) ) {
        throwError( message => $restarterror );
        
    } else {
        print "Successfully configured NTP.\n"
        
    }
    
}


# Get esxi host power state
sub hostState() {
    my $hostnumber = Opts::get_option('hostnumber');
    
    if ( defined($hostnumber) ) {
        my $snmp;
        my $hostPresence = 'bladePresence.' . $hostnumber;
        my $hostPower = 'bladePowerLed.' . $hostnumber;
        my @oids = ();
        push(@oids, $hostPresence);
        push(@oids, $hostPower);
        
        my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
        
        ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
        
        if ( defined($snmp->{$hostPresence}) && $snmp->{$hostPresence} eq "1" ) {
            if ( defined($snmp->{$hostPower}) && $snmp->{$hostPower} eq "2" ) {
                print "OK, ON\n";
                
            } elsif ( defined($snmp->{$hostPower}) && $snmp->{$hostPower} eq "0" ) {
                print "OK, OFF\n";
                
            } else {
                print "OK\n";
                
            }
            
        } elsif ( defined($snmp->{$hostPresence}) && $snmp->{$hostPresence} eq "0" ) {
            print "Missing\n";
            
        } else {
            throwError( message=>'-1008' );
            
        }
        
    }
    
}


# Power off esxi host
sub hostPowerOff() {
    my $hostnumber = Opts::get_option('hostnumber');
    
    if ( defined($hostnumber) ) {
        my $timeout = 300;
        my $verbose = 0;
        my $session;
        my $host;
        
        eval {
            $session = openSession();
            
        };
        
        if ( $@ ) {	
            throwError( message => '-1001' );
            
        }
        
        eval {
            $host = $session->find_entity_view(
                view_type => 'HostSystem',
                filter => { name => hostLookup( subnet => $locationLan2Sub, hostnumber => $hostnumber ) }
            );
            
        };
        
        if ( $@ ) {	
            throwError( message => '-1004' );
            
        }
        
        if ( ! $host->runtime->inMaintenanceMode ) {
            eval {
                enterMaintModeHost( host => $host, session => $session );
                
            };
            
        }
        
        if ( $@ ) {
            throwError( message => '-1005' );
            
        }
        
        if( $host->runtime->connectionState->val eq 'connected' ) {
            handleTask(
                task => $host->ShutdownHost_Task( force => 1 ),
                timeout => $timeout,
                verbose => $verbose,
                session => $session
            );
            
        } else {
            throwError( message => '-1009' );
            
        }
        
        print "Successfully powered off host " . $hostnumber . "\n";
        
    }
    
}


# Power on esxi host
sub hostPowerOn() {
    my $hostnumber = Opts::get_option('hostnumber');
    
    if ( defined($hostnumber) ) {
        my $Cli = openCli();
        my $serverObj = Server->new();
        my $timeout = 600;
        my $elapsedTime = 0;
        my $verbose = 0;
        my $session;
        my $host;
        my $hostip = hostLookup( subnet => $locationLan2Sub, hostnumber => $hostnumber );
        my $ua = LWP::UserAgent->new();
        my $continue = 1;
        
        eval {
            $serverObj->PowerOn( Cli => $Cli, server => 'server' . $hostnumber );
            
        };
        
        if ( $@ ) {	
            throwError( message => '-1007' );
            
        } else {
            # Wait for sdk to start
            do {
                my $url =  'https://' . $hostip . '/';
                my $request = HTTP::Request->new(GET => $url); 
                my $response = $ua->request($request);
                if ( $response->is_success || $elapsedTime >= $timeout ) {
                    $continue = 0;
                    
                } else {
                    $elapsedTime += 10;
                    sleep 10;
                    
                }
                
            } while( $continue );
            
            eval {
                $session = openSession();
                
            };
            
            eval {
                $host = $session->find_entity_view(
                    view_type => 'HostSystem',
                    filter => { name => $hostip }
                );
                
            };
            
            # Wait for host to reconnect to host
            $continue = 1;
            $elapsedTime = 0;
            do {
                $host->ViewBase::update_view_data();
                if ( $host->runtime->connectionState->val eq 'connected' || $elapsedTime >= $timeout ) {
                    $continue = 0;
                    
                } else {
                    $elapsedTime += 10;
                    sleep 10;
                    
                }
                
            } while( $continue );
            
            # Exit maintenance mode if necessary
            if( $host->runtime->inMaintenanceMode ) {            
                eval {
                    exitMaintModeHost( host => $host, session => $session, verbose => $verbose, timeout => $timeout );
                    
                };
                
            }
            
            print "Successfully powered on host " . $hostnumber . "\n";
            
        }
        
    }
    
}


# Get SCM state
sub getScmState() {
    my $scmnumber = Opts::get_option('scmnumber');
    if ( defined($scmnumber) ) {
        my $snmp;
        my $scmStatus = 'scmOpStatus.' . $scmnumber;
        my $scmPowerLed = 'scmPowerLed.' . $scmnumber;
        my $scmFaultLed = 'scmFaultLed.' . $scmnumber;
        my @oids = ();
        push(@oids, $scmStatus);
        push(@oids, $scmPowerLed);
        push(@oids, $scmFaultLed);
        
        my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
        
        ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
        
        if ( defined($snmp->{$scmStatus}) ) {
            if ( $snmp->{$scmStatus} =~ m/OK/i ) {
                print "OK\n";
                
            } elsif ($snmp->{$scmStatus} =~ m/Not Present/i ){
                if ( defined($snmp->{$scmPowerLed}) && defined($snmp->{$scmFaultLed}) && $snmp->{$scmPowerLed} eq "2" && $snmp->{$scmFaultLed} eq "0" ) {
                    print "Safe Mode\n";
                    
                } else {
                    print "Unknown\n";
                    
                }
                
            } else {
                throwError( message=>'-1008' );
                
                
            }
            
        }
        
    }
    
}


# Reset SCM (safe mode)
sub scmSafe() {
    my $scmnumber = Opts::get_option('scmnumber');
    if ( defined($scmnumber) ) {
        my $Cli = openCli();
        my %scm = $Cli->getThingWithTargets(parentDirectory=>'/storage', searchString=>'scm' . $scmnumber);
        if( defined($scm{'scm' . $scmnumber}{"Status"}) && $scm{$scm}{"Status"} !~ m/missing/i && $scm{$scm}{"Status"} !~ m/safe/i ) {
            # reset scm
            $Cli->cd(dir => "/storage/scm$scmnumber");
            $Cli->runCommand("reset safe");
            print "Reset SCM " . $scmnumber . " (safe)\n";
            
        } else {
            throwError( message=>'-1014' );
            
        }
        
    }
    
}


# Reset SCM (normal)
sub scmReset() {
    my $scmnumber = Opts::get_option('scmnumber');
    if ( defined($scmnumber) ) {
        my $Cli = openCli();
        my %scm = $Cli->getThingWithTargets(parentDirectory=>'/storage', searchString=>'scm' . $scmnumber);
        if( defined($scm{'scm' . $scmnumber}{"Status"}) && $scm{$scm}{"Status"} !~ m/missing/i ) {
            # reset scm
            $Cli->cd(dir => "/storage/scm$scmnumber");
            $Cli->runCommand("reset normal");
            print "Reset SCM " . $scmnumber . " (normal)\n";
            
        } else {
            throwError( message=>'-1013' );
            
        }
        
    }
    
}


# Get switch state
sub getSwitchState() {
    my $switchnumber = Opts::get_option('switchnumber');
    
    if ( defined($switchnumber) ) {
        my $snmp;
        my $switchStatus = 'switchIfOperStatus.' . $switchnumber . '.1';
        my @oids = ();
        push(@oids, $switchStatus);
        
        my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
        
        ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
        
        if( defined($snmp->{$switchStatus}) ) {
            if ( $snmp->{$switchStatus} eq "1" ) {
                print "OK, Up\n";
                
            } elsif ( $snmp->{$switchStatus} eq "2" ) {
                print "OK, Down\n";
                
            } else {
                print "Unknown\n";
                
            }
            
        } else {
            throwError(message=>'-1010');
            
        }
        
        closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
        
    }
    
}


sub getDriveState() {
    my $drivenumber = Opts::get_option('drivenumber');
    
    if ( defined($drivenumber) ) {
        my $snmp;
        my $driveStatus = 'sDriveOperationalStatus.' . $drivenumber;
        my $driveCapacity = 'sDrivePhysicalCapacity.' . $drivenumber;
        my $driveType = 'sDriveType.' . $drivenumber;
        my $poolID = 'sDriveStoragePoolID.' . $drivenumber;
        my $driveSerial = 'sDriveSerialNumber.' . $drivenumber;
        my @oids = ();
        push(@oids, $driveStatus);
        push(@oids, $driveCapacity);
        push(@oids, $driveType);
        push(@oids, $poolID);
        push(@oids, $driveSerial);
        
        my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
        
        ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
        
        if ( defined($snmp->{$driveStatus}) ) {
            if ( $snmp->{$driveStatus} =~ m/OK/i ) {
                if ( $snmp->{$driveStatus} =~ m/PFA/i ) {
                    print "PFA";
                    
                } else {
                    print "OK";
                    
                }
                
            } elsif ( $snmp->{$driveStatus} =~ m/Dead/i ) {
                print "Dead";
                
            } elsif ( $snmp->{$driveStatus} =~ m/Applicable/i ) {
                print "Missing";
                
            } elsif ( $snmp->{$driveStatus} =~ m/Rebuilding/i ) {
                print "Rebuilding";
                
            } elsif ( $snmp->{$driveStatus} =~ m/Stale/i ) {
                print "Stale";
                
            } else {
                print "Unknown";
                
            }
            
            if ( $snmp->{$driveStatus} !~ m/Applicable/i ) {
                if ($snmp->{$driveCapacity} =~ /^\d+?$/) {
                    print ", " . bytesToHuman($snmp->{$driveCapacity});
                    
                }
                
                if ( defined($snmp->{$driveType}) ) {
                    if ( $snmp->{$driveType} eq "4" ) {
                        print ", SAS";
                        
                    } elsif ( $snmp->{$driveType} eq "1" ) {
                        print ", SSD";
                        
                    }
                    
                }
                
                if ( defined($snmp->{$poolID}) && $snmp->{$poolID} ne "0" ) {
                    my $poolName = getStoragePoolName(storagePoolID=>$snmp->{$poolID});
                    
                    if ( defined($poolName) && $poolName !~ m/Unknown/i ) {
                        print ", " . $poolName;
                        
                    } else {
                        print ", None";
                        
                    }
                    
                } else {
                    print ", None";
                    
                }
                
                if ( defined($snmp->{$driveSerial}) ) {
                    print ", " . $snmp->{$driveSerial};
                    
                }
                
            }
            
            print "\n";
            
        } else {
            throwError(message=>'-1015');
            
        }
        
        closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
        
    }
    
}


# Rebuild storage array
sub rebuildDrive() {
    my $drivenumber = Opts::get_option('drivenumber');
    
    if ( defined($drivenumber) ) {
        # make sure new drive is ok -- clear stale state
        # make sure drive is not part of a storage pool (poolID=0)
        # compare new drive size to all other drives
        #  deterine if drives that match are of the same time (sas/ssd)
        #  deterine if drives that match come from a degraded storage pool
        # rebuild compatible drive
        
        my $snmp;
        my $driveCount = "14";
        my $driveStatus = 'sDriveOperationalStatus.' . $drivenumber;
        my $driveCapacity = 'sDrivePhysicalCapacity.' . $drivenumber;
        my $driveType = 'sDriveType.' . $drivenumber;
        my $poolID = 'sDriveStoragePoolID.' . $drivenumber;
        
        my @oids = ();
        
        push(@oids, $driveStatus);
        push(@oids, $driveCapacity);
        push(@oids, $driveType);
        push(@oids, $poolID);
        
        my $snmpsession = openSnmpSession( host=>$cmmip, verbose=>$verbose );
        
        ($snmp, $snmpsession) = snmpRequests(session=>$snmpsession, oids=>\@oids, verbose=>$verbose);
        
        closeSnmpSession(session=>$snmpsession, verbose=>$verbose);
        
        if ( defined($snmp->{$driveStatus}) && defined($snmp->{$poolID}) && ( $snmp->{$driveStatus} =~ m/OK/i || $snmp->{$driveStatus} =~ m/Stale/i ) && $snmp->{$poolID} eq "0" ) {
            our ($type, $size, $poolid, $condition, $rebuild, $poolName);
            for ( my $i=1; $i<=$driveCount; $i++ ) {
                if ($i ne $drivenumber) {
                    $poolid = getStoragePoolID(drivenumber=>$i);
                    if ( defined($poolid) && ($poolid ne "0" && $poolid ne "-32") ) {
                        if ($verbose) { print "\ndrive " . $i . "\n"; }
                        $condition = getStoragePoolCondition(storagePoolID=>$poolid);
                        if ($verbose) { print "storage pool condition = " . $condition . "\n"; }
                        if ( defined($condition) && $condition =~ m/Degraded/i ) {
                            $type = getDriveType(drivenumber=>$i);
                            if ($verbose) { print "drive type = " . $type . " (looking for " . $snmp->{$driveType} . ")\n"; }
                            if ( defined($type) && $type eq $snmp->{$driveType} ) {
                                $size = getDriveSize(drivenumber=>$i);
                                if ($verbose) { print "drive size = " . $size . " (looking for " . $snmp->{$driveCapacity} . ")\n"; }
                                if ( defined($size) && $size eq $snmp->{$driveCapacity} ) {
                                    # we have a winner
                                    $poolName = getStoragePoolName(storagePoolID=>$poolid);
                                    if ( defined($poolName) && $poolName !~ m/Unknown/i ) {
                                        $rebuild = 1;
                                        last;
                                        
                                    }
                                    
                                }
                                
                            }
                            
                        }
                        
                    }
                    
                }
                
            }
            
        }
        
        if ( defined($rebuild) && defined($poolName) && defined($poolid) ) {
            if ($verbose) { print "Drive " . $drivenumber . " is eligible to rebuild " . $poolName . "\n"; }
            my $Cli = openCli();
            
            if ( $snmp->{$driveStatus} =~ m/Stale/i ) {
                $Cli->cd(dir=>"/storage/drive$drivenumber");
                $Cli->runCommand("clear confirm");
                
            }
            
            $Cli->cd(dir=>"/storage/pool$poolid");
            $Cli->runCommand("rebuild drive" . $drivenumber);
            print "Rebuilding drive " . $drivenumber . " in " . $poolName . "\n";
            
        } else {
            if ($verbose) { print "Drive " . $drivenumber . " is not compatible with any storage pool.\n"; }
            throwError(message=>'-1016');
            
        }
        
    }
    
}


# Prepare system for TIER2 swap for seagate hard drive recall
sub tier2Prep() {
    wlog("api","[INFO] TIER2 preparation initiated.");
    exec("/bin/nice -n 19 /usr/local/bin/IMSTier2Prep.pl --verbose 0 --location $locationnumber &>/dev/null &");
    
}


# Bring the system back online after a TIER2 swap
sub tier2Post() {
    #print "TIER2 post-install initiated.\n";
    wlog("api","[INFO] TIER2 post-install initiated.");
    exec("/bin/nice -n 19 /usr/local/bin/IMSTier2Post.pl --verbose 0 --location $locationnumber &>/dev/null &");
    
}


# Fix issues with accepting centralvma self-signed certificate
sub certFix() {
    wlog("api","[INFO] Running central vMA certificate fix on location $locationnumber");
    exec("/bin/nice -n 19 /usr/local/bin/certfix.sh $locationnumber &>/dev/null");
    print "Ran Central vMA certificate fix on location $locationnumber\n";
    
}

### END: api tools


# Call appropriate function
&$tool();
exit 0;
