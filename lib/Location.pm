#!/usr/bin/perl -w

require "Network.pm";

use strict;
use warnings;
use MIME::Base64;
use Switch 'Perl5', 'Perl6';


# =========================================================================== #
# Function Name: getHosts()
#
# Purpose: Returns a list of hosts
#
# Expects: subnet
# =========================================================================== #
sub getHosts() { # subnet
    my %args = @_;
    my @hosts;
    for ( my $oct4 = 177; $oct4 <= 182; $oct4++) { 
        my $host = $args{subnet} . "." . $oct4;
        if ( simplePing( dest=>$host, verbose=> 0 ) ) {
            push (@hosts,$host);
            
        }
        
    }
    
    return @hosts;
    
}


# =========================================================================== #
# Function Name: hostLookup()
#
# Purpose: Returns an IP address for a hostnumber
#
# Expects: subnet, hostnumber
# =========================================================================== #
sub hostLookup() {
    my %args = @_;
    my $subnet = $args{subnet};
    my $hostnumber = $args{hostnumber};
    switch ( $hostnumber ) {
        when "1" { return $subnet . ".177"; }
        when "2" { return $subnet . ".178"; }
        when "3" { return $subnet . ".179"; }
        when "4" { return $subnet . ".180"; }
        when "5" { return $subnet . ".181"; }
        when "6" { return $subnet . ".182"; }
        default  { return "false"; }
        
    }
    
}



# =========================================================================== #
# Function Name: getPassword()
#
# Purpose: Returns the password for specified hostname
#
# Expects: hostname
# =========================================================================== #
sub getPassword() { # hostname
    my %args = @_;
    switch ( $args{hostname} ) {
        when "ssrv"   { return decode_base64("ezMncmUub0s="); }
        when "psrv"     { return decode_base64("ZkBzJEd1MXRAcg=="); }
        when "isrv"   { return decode_base64("ezMncmUub0s="); }
        when "fsrv" { return decode_base64("ezMncmUub0s="); }
        when "esxi"       { return decode_base64("JTRVMmtuMHc="); }
        when "vcva"  { return decode_base64("JTRVMmtuMHc="); }
        when "wssrv" { return decode_base64("d3QwUmVicmlkZ2U="); }
        when "phv"  { return decode_base64("ZjFnS0BodW5h"); }
        when "shv"   { return decode_base64("ZjFnS0BodW5h"); }
        when "cmm"        { return decode_base64("V3QzdjNKMGJz"); }
        default           { return decode_base64("JTRVMmtuMHc="); }
        
    }
    
}
