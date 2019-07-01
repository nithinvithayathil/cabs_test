#!/usr/bin/perl -w
###############################################
###    Script for transferring a file to  Changeman DS
###    Lace Joy/George Trubisky
###    July  19, 2011
###
###############################################

####################################################################################################
use strict;
use Time::gmtime;
use File::stat;
use IO::Handle;
use lib "/appl/chje/adm/perllib/";
use XML::Simple;

use constant {
	REPO => '.repository',
};

####################################################################################################
# globals vars
####################################################################################################
my ($dmcm_user, $dmcm_pass, $dmcm_host, $dmcm_bdb, $dmcm_dsn);
my ($logpath, $credentials, $pomfile, $pompath, $workspacepath, $product, $tostream, $streampath, $tostage, $qastages);
my ($auto_deploy, $auto_baseline);
my ($cleanup_property_file, $retention_limit);
my ($std, $verbose);
my ($groupId, $artifactId, $packaging, $version);
my ($logfile);
my (@temparray);

############+##############################################################################+

my $dmprofile = "/appl/chdm/dimensions/14.3.3/cm/dmprofile";
my $myname = $0;
$myname =~ s/.*\/([^\/]+)/$1/;

#ci_dimcm.pl -logpath logs -credentials ci_dimcm_qa.txt -pomfile pom.xml -pompath . -workspacepath work -product TEST -tostream JPTEST2 -streampath jptest2 -auto_deploy -auto_baseline -cleanup_property_file <property_file> -retention_limit <count> 
my $usage = "\nUsage:".
	"\n$myname -logpath <path> -credentials <file> -pomfile <file> -pompath <path>".
	"\n-workspacepath <path> -product <product> -tostream <stream> -streampath <streampath> [-tostage <stage>] [-qastages <qa environments>]".
	"\n[-auto_deploy [<environments>]] [-auto_baseline [<environments>]]".
	"\n[-cleanup_property_file <property_file> -retention_limit <count>]".
	"\n[-std] [-verbose]\n\n";

####################################################################################################
# write message to stdout and logfile
####################################################################################################
sub report_info
{
   	while (my $info = shift)
	{
		if ($logfile)
		{
			print LOG "$info\n";
			print  "$info\n";
		}
		else
		{
		    push(@temparray,$info);
		}
	}
}

####################################################################################################
# write message to stdout and logfile
####################################################################################################
sub report_info_from_temparray
{
	foreach my $info ( @temparray)
	{
		print LOG "$info\n";
		print  "$info\n";
	}
}

####################################################################################################
# write error message to stdout and logfile and die
####################################################################################################
sub report_error
{
	my $info = shift;
	report_info("Script aborted:\n$info");
	unless ($logfile)
	{
		print "\nFailed to create the logfile so printing the information captured in the temporarry array \n";
		foreach (@temparray)
		{
			print "$_\n";
		}
	}
	exit 1;
}

####################################################################################################
# Check if directory path exists & create it if not (UNUSED)
####################################################################################################
sub check_path
{
	my $path = shift;
	unless (-e $path)
	{
		if (!mkdir($path))
		{
			report_error("Not able to create directory $path $!");
		}
		else
		{
			report_info("Created the directory $path $!");
		}
	}
}

####################################################################################################
# subroutine for deleting the logfiles older than a week
####################################################################################################
sub del_old_files
{
	my $dir = shift;
	my @files = `ls -tr $dir`;
	my $weekoldtime = time - 604800;
	foreach my $file (@files)
	{
		chomp($file);
		my $sb = stat("$dir$file");
		if ($sb->mtime lt $weekoldtime)
		{
			report_info("Logfile $dir$file is stale...deleting");
			unlink("$dir$file");
		}
		else
		{
			# we found a fresh file, so exit the loop since the files are sorted from oldest to newest
			report_info("Logfile $dir$file is not stale...");
			last;
		}
	}
}

####################################################################################################
# prepare_logfile checks if the directory structure is in place to support the log file path and
# builds the directory structure if needed. After verifying the directory structure, the log file
# is opened for reading using the file handle 'LOG'
####################################################################################################
sub prepare_logfile
{
	$logpath = path_cleanup( $logpath, '', '/' );
	if( not -d $logpath )
	{
		report_info("Logpath does not exist, attempting to create...");
		mkdir $logpath;
		if( not -d $logpath )
		{
			report_error($usage."Logpath does not exist or cannot be opened.");
		}
	}
	report_info("Using logpath \"$logpath\"");
	del_old_files( $logpath );

	# set the log file name
	my @arr = split / /, localtime;
	shift @arr;
	unshift @arr, (pop @arr);
	my $now = join '_', @arr;
	$now =~ s/://g;
	$logfile = "$logpath$now.txt";
}

####################################################################################################
# get_credentials retrieves credentials from the specifed file
# blank lines and commented lines are allowed.  Commented lines must
# be preceded by the '#' symbol
####################################################################################################
sub get_credentials
{
	my $file = shift;
	report_error("$file doesn't exist")
		if (not -r $file);

	report_info("Using credential file $file");

	open CREDFILE, $file || die "Could not open the file $file!";
	while( <CREDFILE> )
	{
		chomp;
		eval $_;
	}
	close CREDFILE;

	if(
		not defined $dmcm_user or
		not defined $dmcm_pass or
		not defined $dmcm_host or
		not defined $dmcm_bdb or
		not defined $dmcm_dsn
	) {
		report_error("Problem in credentials file");
	}
}

####################################################################################################
# Parse command line options
####################################################################################################
sub parse_options
{
	report_info("*********Parsing options *********");
	my $temptime = localtime;
	report_info($temptime.":${0}");
	while (my $arg = lc shift) {
		if ($arg eq '-logpath') {
			$logpath = shift;
		} elsif ($arg eq '-credentials') {
			$credentials = shift;
		} elsif ($arg eq '-pomfile') {
			$pomfile = shift;
		} elsif ($arg eq '-pompath') {
			$pompath = shift;
		} elsif ($arg eq '-workspacepath') {
			$workspacepath = shift;
		} elsif ($arg eq '-product') {
			$product = shift;
		} elsif ($arg eq '-tostream') {
			$tostream = shift;
		} elsif ($arg eq '-streampath') {
			$streampath = shift;
		} elsif ($arg eq '-tostage') {
			$tostage = shift;
		} elsif ($arg eq '-qastages') {
			$qastages = shift;
		} elsif ($arg eq '-cleanup_property_file') {
			$cleanup_property_file = shift;
		} elsif ($arg eq '-retention_limit') {
			$retention_limit = shift;
		} elsif ($arg eq '-auto_deploy') {
			$auto_deploy = shift;
			if ($auto_deploy =~ /^-.*/) {
				unshift @_, $auto_deploy;
				$auto_deploy = 1;
			}
			report_info("auto_deploy: $auto_deploy");
		} elsif ($arg eq '-auto_baseline') {
			$auto_baseline = shift;
			if ($auto_baseline =~ /^-.*/) {
				unshift @_, $auto_baseline;
				$auto_baseline = 1;
			}
			report_info("auto_baseline: $auto_baseline");
		}
		elsif ($arg eq '-std') {
			$std = 1;
		} elsif ($arg eq '-verbose') {
			$verbose = 1;
		} else {
			report_error($usage."Wrong argument '$arg' is passed");
		}
	}
	if (!defined($logpath) || $logpath eq '') {
		report_error($usage, "Logpath not set");
	}
	if (!defined($credentials ) || $credentials eq '') {
		report_error("No <credentials> file specified or value is empty");
	}
	if (!defined($pomfile ) || $pomfile eq '') {
		report_error("No <pomfile> specified or value is empty");
	}
	if (!defined($pompath ) || $pompath eq '') {
		report_error("No <pompath> specified or value is empty");
	}
	if (!defined($workspacepath ) || $workspacepath eq '') {
		report_error("No <workspacepath> specified or value is empty");
	}
	if (!defined($product) || $product eq '') {
		report_error("No <product> specified or value is empty");
	}
	if (!defined($tostream) || $tostream eq '') {
		report_error("No <tostream> specified or value is empty");
	}
	if (!defined($streampath) || $streampath eq '') {
		report_info("No <streampath> specified or value is empty");
		$streampath = '';
	}
	if (!defined($tostage) || $tostage eq '') {
		report_info("WARNING: No <tostage> specified, will skip promotion");
		$tostage = '';
	}
	if ((!defined($qastages) || $qastages eq '') && (defined($tostage) && $tostage ne '')) {
		$qastages = "qa1,qa1-wlpj,qa2,qa2-wlpj,qac,qac-wlpj,qap,qap-wlpj";
		report_info("INFO: No <qastages> specified or value is empty. Default has been set to '$qastages'.");
	}
}

####################################################################################################
### clean up path: remove double slashes, trailing slash
####################################################################################################
sub path_cleanup
{
	my ($str, $pre, $post) = @_;
	($pre, $post) = ('', '') if(not defined $pre);

	while( $str =~ s/\/\//\//g ){};
	$str =~ s/^([^\/])/$pre$1/;
	$str =~ s/([^\/])$/$1$post/ if(defined $post);
	$str =~ s/\/$// if(not defined $post);

	return $str;
}

####################################################################################################
### Parse the pom file
####################################################################################################
sub get_attributes
{
	$pompath = path_cleanup( $pompath, '/', '/' );
	$workspacepath = path_cleanup( $workspacepath, '' );

	# constructing pomfile path
	my $pomfilepath = $workspacepath.$pompath.$pomfile;
	if (not -r $pomfilepath) {
		report_error("$pomfilepath does not exist");
	}
	report_info("The file $pomfilepath is used for parsing ");

	# create xml object for parsing the file
	#my $xml = new XML::Simple;
	#my $data = $xml->XMLin($pomfilepath);

	#access XML data
	$groupId = '';

	$artifactId = '';

	$packaging = '';

	$version = '';
}

####################################################################################################
# update Dimensions work area
####################################################################################################
sub generate_update_command
{
	my ($groupIdpath, $from_path, $rel_path);
	my ($prd, $strm, $cmd);

	# Prepare agruments for the command
	$groupIdpath = $groupId;
	$groupIdpath =~ s/\./\//g;
	$from_path = "$workspacepath";

	$prd = uc $product;
	$strm = uc $tostream;
	
	if ($streampath =~ "std"){
        $rel_path = qq["$streampath\\batch\\lib"];
		$cmd = "SCWS \"$prd:$strm\" /DIRECTORY=\"$from_path\/$streampath\" /NODEFAULT\n".
	       "UPDATE /DIRECTORY=\"$rel_path\"\n";		
    } else {
        $cmd = "SCWS \"$prd:$strm\" /DIRECTORY=\"$from_path\" /NODEFAULT\n".
	    "UPDATE /NORECURSIVE\n";
    }
	
	return $cmd;
}

####################################################################################################
# transfers
####################################################################################################
sub transfer_files
{
	my ($groupIdpath, $from_path, $from_file);
	my ($cmd);

	# Prepare agruments for the command
	$groupIdpath = $groupId;
	$groupIdpath =~ s/\./\//g;
	$from_path = "$workspacepath";
	$from_file = "sample.006.txt";
        #$rel_path = qq["$streampath/$from_file"];

        if ( $streampath =~ "std" ){
			$cmd = "mkdir -p $from_path$streampath\/$streampath\/batch\/lib;ln -s -f $from_path$from_file $from_path$streampath\/$streampath\/batch\/lib\/$from_file";
        }
        else {
        $cmd = "mkdir -p $from_path$streampath;ln -s -f $from_path$from_file $from_path$streampath\/$from_file";
        }

	print $cmd;
	my $output = `$cmd`; #"* bypassed *\n"; #`$cmd`;
#	my $output = `$cmd`;

	my $check = $?;
	if( $check ne '0' )
	{
		report_error("Error - copy return code '$check'\n");
	}
	report_info($output);
	return $cmd;
}

sub generate_transfer_command
{
	my ($groupIdpath, $from_path, $from_file, $rel_path);
	my ($prd, $prt, $strm, $comment, $bl_name, $cmd, $future_time);

	# Prepare agruments for the command
	$groupIdpath = $groupId;
	$groupIdpath =~ s/\./\//g;
	$from_path = "$workspacepath";
	$from_file = "sample.006.txt";
        if ($streampath =~ "std"){
			$rel_path = "pabs_dev/sample.006.txt";
        }
        else {
        $rel_path = "pabs_dev/sample.006.txt";
        }
	$bl_name = "sample.006.txt";

	#update the timestamp so Dimensions will acknowledge the post-UPDATE command change
	$future_time = `date -d "now + 1 minutes" +'%y%m%d%H%M'`;
	$future_time =~ s/^\s+//;
	$future_time =~ s/\s+$//;
	`touch -c -t $future_time $from_path$rel_path`;

	$prd = uc $product;
#	$prd = uc $dmcm_prod;
#	$prt = uc $dmcm_part;
	$strm = uc $tostream;

#	$comment = qq["<artifactId>$artifactId<version>$version<packaging>$packaging"];
	$comment = "Delivered from Jenkins build";

	if ($streampath =~ "std"){
		$cmd = "SCWS \"$prd:$strm\" /DIRECTORY=\"$from_path\/$streampath\" /NODEFAULT\n".
	       "DELIVER /USER_DIRECTORY=\"$from_path\/$streampath\" /COMMENT=\"$comment\" /DESCRIPTION=\"$comment\" /ADD /UPDATE\n";
    } else {
	$cmd = "SCWS \"$prd:$strm\" /DIRECTORY=\"$from_path\" /NODEFAULT\n".
	       "DELIVER \"$rel_path\" /COMMENT=\"$comment\" /DESCRIPTION=\"$comment\" /ADD\n";
    }	
	


	#allow auto deploy to any environment except prd
	if(($auto_deploy && ($auto_deploy eq 1 or index(",$auto_deploy,", ",$tostage,")) != -1 ) and 
            $tostage ne 'prd' and
            $tostage ne 'prd-wlpj' )
	{
		my $stage;
		if(index(",$qastages,", ",$tostage,") != -1) {
			$stage="QA";
		} else {
			$stage="DEV";
		}
		$cmd = $cmd . "PMI \"$rel_path\" /STAGE=$stage /WORKSET=\"$prd:$strm\"\n";
	}
	#allow auto baseline for any environment,
	#but always baseline prd
	if(($auto_baseline && ($auto_baseline eq 1 or index(",$auto_baseline,", ",$tostage,")) != -1 ) or
            $tostage eq 'prd' or
            $tostage eq 'prd-wlpj' )
	{
		$cmd = $cmd . "CBL \"$bl_name\" /PART=\"$prd:$strm.A;1\" /template_id=\"ALL_ITEMS_APPROVED\" /TYPE=\"BASELINE\" /SCOPE=\"PART\" /WORKSET=\"$prd:$strm\"\n";
	}
	return $cmd;
}

####################################################################################################
# execute the provided command and return the output
####################################################################################################
sub execute_dimcm
{
	my ($groupIdpath, $from_path, $from_file);
	my ($dm_file, $cmd);

	# Prepare agruments for the command
	$groupIdpath = $groupId;
	$groupIdpath =~ s/\./\//g;
	$from_path = "$workspacepath";
	$from_file = "sample.006.txt";
#	$dm_file = $logpath.'dm_cmdfile.txt';
	$dm_file = 'dm_cmdfile'.$_[1].'.txt';
	$cmd = $_[0];
	print $cmd; #TODO remove me


#	if( defined $verbose ) {
#	report_info("*****************************************************");
#	    report_info($cmd);
#	}
	open DMFILE, ">$dm_file" || die "Could not open the file $dm_file\n";
	print DMFILE $cmd;
	close DMFILE;

		#TODO: hard code different path for test as domain account
		#open DMFILE, ">/appl/chje/adm/scripts/$dm_file" || die "Could not open the file $dm_file\n";
        open DMFILE, ">scripts/$dm_file" || die "Could not open the file $dm_file\n";
	print DMFILE $cmd;
	close DMFILE;


#	$cmd = "dmcli -user $dmcm_user -pass **** -host $dmcm_host -dbname $dmcm_bdb -dsn $dmcm_dsn -file \"$dm_file\"";
	$cmd = "dmcli -user $dmcm_user -pass **** -host $dmcm_host -dbname $dmcm_bdb -dsn $dmcm_dsn -file '$dm_file'";
	report_info("********************************************************************************");
	report_info("$cmd");
	$cmd =~ s/(\-pass\s+)\*+/$1$dmcm_pass/;

	my $output = `. $dmprofile;$cmd`; #"* bypassed *\n"; #`$cmd`;
#	my $output = `$cmd`;

	my $check = $?;
	if( $check ne '0' )
	{
		report_info($output);
		report_error("Error - Dimensions DMCLI return code '$check'\n");
	}
	#TODO begin
	#else
	#{
	#	unlink File::Spec->file($from_path."/".$streampath, $from_file);
	#}
	#TODO end
	report_info($output);
	#TODO keep dm_file for testing
	#unlink $dm_file;

	return $output;
}

sub generate_cleanup_command
{
	my ($groupIdpath, $from_path);
	my ($prd, $strm, $cmd);
	$groupIdpath = $groupId;
	$groupIdpath =~ s/\./\//g;
	$from_path = "$workspacepath";

	$prd = uc $product;
	$strm = uc $tostream;

	$cmd = "SCWS \"$prd:$strm\" /DIRECTORY=\"$from_path\" /NODEFAULT\n";

	my $item_specs = read_item_specs_from_output($_[0]);
	my $item_files = read_item_files_from_output($_[0]);
	#print "\nItem Specs:\n$item_specs\n";

	foreach my $item_spec (split("\n", $item_specs))
	{
		if (!$item_spec eq "")
		{
                       if ($item_spec =~ "EAR") {
			$cmd = $cmd."SI $item_spec\n";
                       }
		}
	}
	my $cleanup_script = '/appl/chje/adm/scripts/build-cleanup.pl';
	if ($cleanup_property_file)
	{
		foreach my $item_file (split("\n", $item_files))
		{
			$item_file =~ s/$from_path//;
			if (!$item_file eq "" and $retention_limit)
			{
				report_info(`$cleanup_script -logpath $logpath -file $item_file -property_file $cleanup_property_file -retention_limit $retention_limit -stream_cleanup $credentials -workset $prd:$strm -workarea $from_path`);
			}
			elsif (!$item_file eq "")
			{
				report_info(`$cleanup_script -logpath $logpath -file $item_file -property_file $cleanup_property_file -stream_cleanup $credentials -workset $prd:$strm -workarea $from_path`);
			}
		}
	}
	return $cmd;
}

###
### parse the item specification from dmcli output
### sample input: Preserved '/path/to/file/test.txt' as Item "TEST:TEST TXT-242413780X12388X20.A-SRC;jptest2#1"
###
### Regex patterns
### ^Preserved \'.*\' as Item \".*\"$
### \".*\"
###
sub read_item_specs_from_output
{
	my ($str, @match);
	my $item_specs = '';
	my (@line_matches, $find_line_pattern);
	my (@item_matches, $find_item_pattern);
	$str = $_[0];
	#print "\nInput:\n$str\n";
	$find_line_pattern = "^Preserved \\'.*\\' as Item \\\".*\\\"\$"; #requires "gm" regex modifiers
	#$find_line_pattern = "Preserved \\'.*\\' as Item \\\".*\\\"";
	@line_matches =  $str =~ m/$find_line_pattern/gm;
	#$str = @line_matches;
	$str = "";
	foreach my $line_match (@line_matches)
	{
		@match = $line_match =~ m/$find_line_pattern/gm;
		$str = $str.$match[0]."\n";
	}
	#print "\Intermediate:\n$str\n";
	$find_item_pattern = "\\\".*\\\"";
	@item_matches =  $str =~ m/$find_item_pattern/g;
	foreach my $item_match (@item_matches)
	{
		@match = $item_match =~ m/$find_item_pattern/g;
		$item_specs = $item_specs.$match[0]."\n";
	}
	#print "\nOutput:\n$item_specs\n";
	return $item_specs;
}

###
### parse the item files from dmcli output
### sample input: Preserved '/path/to/file/test.txt' as Item "TEST:TEST TXT-242413780X12388X20.A-SRC;jptest2#1"
###
### Regex patterns
### ^Preserved \'.*\' as Item \".*\"$
### \'.*\'
###
sub read_item_files_from_output
{
	my ($str, @match);
	my $item_files = '';
	my (@line_matches, $find_line_pattern);
	my (@item_matches, $find_item_pattern);
	$str = $_[0];
	#print "\nInput:\n$str\n";
	$find_line_pattern = "^Preserved \\'.*\\' as Item \\\".*\\\"\$"; #requires "gm" regex modifiers
	#$find_line_pattern = "Preserved \\'.*\\' as Item \\\".*\\\"";
	@line_matches =  $str =~ m/$find_line_pattern/gm;
	#$str = @line_matches;
	$str = "";
	foreach my $line_match (@line_matches)
	{
		@match = $line_match =~ m/$find_line_pattern/gm;
		$str = $str.$match[0]."\n";
	}
	#print "\Intermediate:\n$str\n";
	$find_item_pattern = "\\\'.*\\\'";
	@item_matches =  $str =~ m/$find_item_pattern/g;
	foreach my $item_match (@item_matches)
	{
		@match = $item_match =~ m/$find_item_pattern/g;
		$item_files = $item_files.$match[0]."\n";
	}
	#print "\nOutput:\n$item_files\n";
	return $item_files;
}

####################################################################################################
### main
####################################################################################################

parse_options(@ARGV);

prepare_logfile;
open LOG, ">$logfile" || report_error("Failed to open log file $logfile $!");
report_info("Logfile $logfile is created");
report_info_from_temparray();

if( defined $verbose ) {
	report_info("\@ARGV:\n".(join "\n",@ARGV),'','');
	my $who = `whoami`;
	my $grp = `groups`;
	chomp $who;
	chomp $grp;
	report_info("WHO: $who");
	report_info("GRP: $grp");
}
get_credentials($credentials);
#get_attributes;
execute_dimcm(generate_update_command(),"_update");
#transfer_files;
#my $dmcli_output = execute_dimcm(generate_transfer_command(),"_tx");
#$dmcli_output = 'Preserved \'/home/jperz01/work/.repository/com/example/test/0.1-SNAPSHOT/jptest2/test-0.1-SNAPSHOT.pom\' as Item "TEST:TEST 0 1 SNAPSHOT POM-243119155X13540X2.A-DAT;jptest2#1"'
#$dmcli_output = 'Preserved \'\\D2NTAPNAS01\CHDMQA_STAGE\jperz00\JPTEST2\jptest\test\test.txt\' as Item "TEST:TEST TXT-242413780X12388X20.A-SRC;jptest2#1"';
#execute_dimcm(generate_cleanup_command($dmcli_output),"_cls");

close LOG;
