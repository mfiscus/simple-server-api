<?php

class Constants {
    // valid application api keys
    public static $apikeys = array(
        'service' => 'RmllbGQgU2VydmljZXMK',
        'support' => 'UGhhcm1hY3kgU3VwcG9ydAo=',
    );
    
    
    // available tools, paramaters and parameter options
    public static $instructions = array(
        'tool' => array(
            'certFix' => array(
                'name' => 'Certificate fix',
                'description' => 'Certificate fix',
                'parameters' => array(
                    'locationnumber',
                ),
            ),
            'rebuildDrive' => array(
                'name' => 'Rebuild array',
                'description' => 'Rebuild raid array on degraded storage pool',
                'parameters' => array(
                    'locationnumber',
                    'drivenumber',
                ),
            ),
            'powerDown' => array(
                'name' => 'System Power Down',
                'description' => 'Safely power down the system',
                'parameters' => array(
                    'locationnumber',
                ),
            ),
            'powerOffVm' => array(
                'name' => 'Power Off VM',
                'description' => 'Shutdown a virtual machine operating system',
                'parameters' => array(
                    'locationnumber',
                    'vmname',
                ),
            ),
            'powerOnVm' => array(
                'name' => 'Power On VM',
                'description' => 'Boot a virtual machine operating system',
                'parameters' => array(
                    'locationnumber',
                    'vmname',
                ),
            ),
            'getVmState' => array(
                'name' => 'Get VM Power State',
                'description' => 'Get the power state of a virtual machine',
                'parameters' => array(
                    'locationnumber',
                    'vmname',
                ),
            ),
            'getSwitchState' => array(
                'name' => 'Get Switch State',
                'description' => 'Get the state of a switch module',
                'parameters' => array(
                    'locationnumber',
                    'switchnumber',
                ),
            ),
            'getScmState' => array(
                'name' => 'Get SCM State',
                'description' => 'Get the state of a storage controller module',
                'parameters' => array(
                    'locationnumber',
                    'scmnumber',
                ),
            ),
            'getDriveState' => array(
                'name' => 'Get drive State',
                'description' => 'Get the state of a drive',
                'parameters' => array(
                    'locationnumber',
                    'drivenumber',
                ),
            ),
            'configNtp' => array(
                'name' => 'Configure NTP',
                'description' => 'Configure network time protocol on esxi hosts',
                'parameters' => array(
                    'locationnumber',
                ),
            ),
            'hostState' => array(
                'name' => 'Host power state',
                'description' => 'Get esxi host power state',
                'parameters' => array(
                    'locationnumber',
                    'hostnumber',
                ),
            ),
            'hostPowerOff' => array(
                'name' => 'Power off host',
                'description' => 'Power off esxi host',
                'parameters' => array(
                    'locationnumber',
                    'hostnumber',
                ),
            ),
            'hostPowerOn' => array(
                'name' => 'Power on host',
                'description' => 'Power on esxi host',
                'parameters' => array(
                    'locationnumber',
                    'hostnumber',
                ),
            ),
            'scmSafe' => array(
                'name' => 'SCM safe mode',
                'description' => 'Reset SCM (safe mode)',
                'parameters' => array(
                    'locationnumber',
                    'scmnumber',
                ),
            ),
            'scmReset' => array(
                'name' => 'Reset SCM',
                'description' => 'Reset SCM (normal)',
                'parameters' => array(
                    'locationnumber',
                    'scmnumber',
                ),
            ),
            'tier2Prep' => array(
                'name' => 'TIER2 prep',
                'description' => 'TIER2 swap preparation',
                'parameters' => array(
                    'locationnumber',
                ),
            ),
            'tier2Post' => array(
                'name' => 'TIER2 post-install',
                'description' => 'Bring the system back online after a TIER2 swap',
                'parameters' => array(
                    'locationnumber',
                ),
            ),
        ),
        'options' => array(
            'drivenumbers' => array(
                '1',
                '2',
                '3',
                '4',
                '5',
                '6',
                '7',
                '8',
                '9',
                '10',
                '11',
                '12',
                '13',
                '14',
            ),
            'hostnumbers' => array(
                '1',
                '2',
                '3',
                '4',
                '5',
                '6',
            ),
            'scmnumbers' => array(
                '1',
                '2',
            ),
            'switchnumbers' => array(
                '1',
                '2',
            ),
            'vmnames' => array(
                'FileServer',
                'InfraServer',
                'PharmServer',
                'POSServer',
                'StoreWsSrv',
            ),
        ),
    );
    
    
    // function to return application api keys
    public static function getKeys($application = "") {
        // validate provided key
        if (array_key_exists($application, self::$apikeys)) {
            // return specified key as a string
            return self::$apikeys[$application];
            
        } else {
            // oops, provided key doesn't exist
            // return all keys as an array
            return self::$apikeys;
            
        }
        
    }
    
    
    // function to return available tools
    public static function getInstructions($option = "") {
        // validate provided option
        if (array_key_exists($option, self::$instructions)) {
            // return specified subset (tools or parameter options)
            return self::$instructions[$option];
            
        } else {
            // oops, provided option doesn't exist
            // return all instructions as an array
            return self::$instructions;
            
        }
        
    }
    
    
    public static function validateTool($tool = "") {
        // validate provided tool
        if (array_key_exists($tool, self::$instructions['tool'])) {
            // provided tool exists
            return true;
            
        } else {
            // provided tool doesn't exist
            return false;
            
        }
        
    }
    
}


// iterate over known valid keys to validate posted key
foreach(Constants::getKeys() as $application => $apikey) {
    // validate posted key
    if ($_POST['key'] === $apikey) {
        // check for posted tool
        if (!empty($_POST['tool'])) {
            // try to interpret posted tool
            try {
                // decode posted json object and convert to php object
                $objTool=json_decode(base64_decode($_POST['tool']), false, 512);
                
                // make sure required properties are present
                if (!empty($objTool->date) && !empty($objTool->locationnumber) && !empty($objTool->tool)) {
                    // validate posted tool
                    if (Constants::validateTool($objTool->tool)) {
                        // create a time variable to reference the object expiration
                        $time=time();
                        
                        // expiration time
                        $expiration=900;
                        
                        // make sure request came in within the last 15 minutes
                        if ($time <= $objTool->date+$expiration) {
                            // traverse object and build command arguments
                            $args = '';
                            foreach(get_object_vars($objTool) as $property => $value) {
                                //print($property . " = " . $objTool->$property . "\\\\n");
                                $args .= " --" . $property . " \"" . $objTool->$property . "\"";
                                
                            }
                            
                            //print("DEBUG MODE VAR DUMP\\\\n\\\\n" . $args);
                            
                            // execute instruction set
                            $output = shell_exec("sudo -s \". /etc/bashrc; /bin/nice -n -4 ./api.pl " . $args . "\"");
                            $trimmedoutput = trim($output);
                            print $trimmedoutput;
                            
                        } else {
                            // object is older than 15 minutes
                            throw new Exception("object is expired");
                            
                        } // end if
                        
                    } else {
                        // posted tool is invalid
                        throw new Exception("invalid tool");
                        
                    } // end if
                    
                } else {
                    // expecting tool, locationnumber and date properties
                    throw new Exception("object does not contain required properties");
                    
                } // end if
                
            } catch (Exception $e) {
                // print the caught exception
                print("Caught exception: " . $e->getMessage() . "\n");
                
            } // end try
            
        } else {
            // we got a valid key, but no tool object
            // generate json object with usage properties
            print json_encode(Constants::getInstructions());
            
        } // end if
        
        break;
        
    } // end if
    
} // end foreach

?>