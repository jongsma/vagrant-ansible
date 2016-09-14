#!/usr/bin/perl

#
# $Header: /home/rcitton/CVS/MDBUtil/mdbutil.pl,v 1.71 2016/05/05 15:53:22 rcitton Exp $
#
# mdbutil.pl
#
# Copyright (c) 2014, 2015, Oracle and/or its affiliates. All rights reserved.
#
#    NAME
#      mdbutil.pl
#
#    DESCRIPTION
#      GI Management Repository configuration tool
#
#    NOTES
#        The Grid Infrastructure should be installed as grid/oinstall
#
#    MODIFIED   (MM/DD/YY)
#    RCITTON     05/05/16 - olsnode usage
#    RCITTON     03/30/16 - Cluster Depedency change
#    RCITTON     09/15/15 - trace permission
#    RCITTON     09/15/15 - ssh root check
#    RCITTON     09/15/15 - status fix
#    RCITTON     09/14/15 - grid user usage
#    RCITTON     08/27/15 - space usage
#    RCITTON     08/27/15 - redologs as source
#    RCITTON     08/27/15 - asm sid
#    RCITTON     08/24/15 - new debug option 
#    RCITTON     08/05/15 - new mvmgmtdb 
#    RCITTON     08/05/15 - su griduser fix
#    RCITTON     07/08/15 - qx usage
#    RCITTON     07/01/15 - root user check
#    RCITTON     07/01/15 - Bug 21357054
#    RCITTON     06/30/15 - mvmgmtdb using ctrl file
#    RCITTON     06/11/15 - added mvmgmtdb option
#    RCITTON     06/03/15 - Post HQ review
#    RCITTON     03/02/15 - onecommand
#    RCITTON     01/30/15 - added check/status option
#    RCITTON     01/29/15 - move CHMData support for 12.1.0.2.0
#    RCITTON     01/29/15 - chm ACL grid OS user
#    RCITTON     01/28/15 - CDB Usage on 12.1.0.2.0
#    CHAHUANG    MM/DD/14 - Creation
#

### ------------------------------------------------------------------------
### DISCLAIMER: 
###    It is NOT supported by Oracle World Wide Technical Support. 
###    The script has been tested and appears to work as intended. 
###    You should always run new scripts on a test instance initially. 
### ------------------------------------------------------------------------
 
 

################ Documentation ################
=head1 NAME

 mdbutil.pl - "Manager DB Utility" for MGMTDB in 12c Grid Infrastructure 
 
=head1 SYNOPSIS

 Create/Enable MGMTDB & CHM
   mdbutil.pl --addmdb --target=<MGMTDB destination>
 Move MGMTDB to another location
   mdbutil.pl --mvmgmtdb --target=<new MGMTDB destination>   
 Check MGMTDB status
   mdbutil.pl --status
   
 mdbutil.pl OPTIONS
   --addmdb            Create MGMTDB/CHM and reconfigure related functions
   --mvmgmtdb          Migrate MGMTDB to another location   
   --target='+DATA'    MGMTDB Disk Group location
   --status            Check the CHM & MGMTDB status
   --help              Display this help and exit
   --debug             Verbose commands output/trace
   
 Example:
   Create/Enable MGMTDB:
     mdbutil.pl --addmdb --target=+DATA
   Move MGMTDB to another location:
     mdbutil.pl --mvmgmtdb --target=+REDO             
   Check CHM:
     mdbutil.pl --status

=head1 COPYRIGHT

 Copyright (c) 2014, 2015, Oracle and/or its affiliates. All rights reserved.  

=head1 DISCLAIMER

 It is NOT supported by Oracle World Wide Technical Support. 
 The script has been tested and appears to work as intended. 
 You should always run new scripts on a test instance initially. 

=head1 VERSION

 20160505.2.11 $Revision: 1.71 $

=cut
################ End Documentation ################

use File::Spec;                         # For cross-platform file operations
use File::Spec::Functions;              # Directly use catfile('a','b','c')
use File::Temp qw/ tempfile/;           # Directly use tempfile()
use File::Copy;                         # Directly use copy()
use File::Basename;                     # Use dirname()
use Sys::Hostname;                      # Get hostname();
use Getopt::Long;                       # Deal with command line options
use Pod::Usage;
use Term::ANSIColor;
use English;
use Cwd;
use strict;
use Fcntl;
use warnings;


my @out= system_cmd("uname");
my $platform = $out[1];
chomp $platform;

my $hostname = hostname();
if ($hostname =~ /\./) {
  my @tmphost = split/\./, $hostname;
  $hostname = $tmphost[0];
}
$hostname = lc($hostname);

# Identify init.crs location for startup and stop CRSD and related files
my ($ocrloc,$olrloc,$orainstloc,$orainvloc,$oratab,$chown,$chmod,$pinproc);
my $tmp = File::Spec->tmpdir();
$oratab = "/etc/oratab";

if ($platform eq "Linux") {
  $orainstloc="/etc/oraInst.loc";
  $ocrloc="/etc/oracle/ocr.loc";
  $olrloc="/etc/oracle/olr.loc";
  $pinproc= "osysmond.bin,ologgerd,ocssd.bin,cssdmonitor,cssdagent,mdb_pmon_-MGMTDB,kswapd0";
  }
elsif ($platform eq "HP-UX") {
  $orainstloc="/etc/oraInst.loc";
  $ocrloc="/etc/oracle/ocr.loc";
  $olrloc="/etc/oracle/olr.loc";   
  $pinproc = "osysmond.bin,ologgerd,ocssd.bin,cssdmonitor,cssdagent,mdb_pmon_-MGMTDB";
  }
elsif ($platform eq "AIX"){
  $orainstloc="/etc/oraInst.loc";
  $ocrloc="/etc/oracle/ocr.loc";
  $olrloc="/etc/oracle/olr.loc";   
  $pinproc = "osysmond.bin,ologgerd,ocssd.bin,cssdmonitor,cssdagent,mdb_pmon_-MGMTDB";
  }
elsif ($platform eq "SunOS") {
  $orainstloc="/etc/oraInst.loc";
  $ocrloc="/var/opt/oracle/ocr.loc";
  $olrloc="/var/opt/oracle/olr.loc";
  $pinproc= "osysmond.bin,ologgerd,ocssd.bin,cssdmonitor,cssdagent,mdb_pmon_-MGMTDB,pageout,sched";      
  }
else {
  die "ERROR: Unknown Operating System!\n";
}


my $crshome=getCRSHomefromOLR();
my @nodelist=getCRSNodelist();
my $crsusr = getpwuid((stat("$crshome/bin/oracle"))[4]);

################################
my @redolocation;
my @datafileslocation;
my @tempdatafileslocation;
my @pdbdatafileslocation;
my @pdbtempdatafileslocation;
my $time;
my $debug;

my $mvmgmtdb=0;
my $rmchm=0;
my $addchm=0;
my $rmmdb=0;
my $addmdb=0;
my $status=0;
my $target="";
my $help=0;
my $usage_rc = 1;

my $result = GetOptions(
                        "mvmgmtdb!"   => \$mvmgmtdb, 
                        "rmchm!"      => \$rmchm,
                        "addchm!"     => \$addchm,
                        "addmdb!"     => \$addmdb,
                        "rmmdb!"      => \$rmmdb,
                        "status!"     => \$status,
                        "target=s"    => \$target,
                        "debug"       => \$debug,
                        "help!"       => \$help,
                        ) or pod2usage($usage_rc);

pod2usage(-msg => "Invalid extra options passed: @ARGV", -exitval => $usage_rc) if (@ARGV);

# print help message if --help specified
(pod2usage() && exit) if ( $help );

if (($mvmgmtdb||$addmdb))
{
  if (!$target) {
    pod2usage(-msg => "Must Specify Target Location When Not Disable MGMTDB!\n", -exitval => $usage_rc);
    exit;
  } 
  elsif ( $target =~ /^\+/ ) {
    my $targetname = $target;
    $targetname =~ s/^\+(.*)/$1/;
    my @out=system_cmd("$crshome/bin/srvctl status diskgroup -g $targetname");
    if ( ! grep(/is running on.*$hostname/,@out) ) {exit_error(1,"Specified Target $target Not accessible on $hostname!")};
  }
  else {exit_error(1,"Only Support Using ASM Diskgroup (+DiskGroupName) Format!")};
}

if ( $addmdb && $target )
{
  die "Must configure MGMTDB as $crsusr ... \n" if ((getpwuid($<))[0] ne $crsusr);
  trace("I","Starting To Configure MGMTDB at $target...");
  configMGMTDB($target);
  trace("I","MGMTDB & CHM configuration done!");
}
elsif ( $rmmdb )
{
  die "Must deinstall MGMTDB as $crsusr ... \n" if ((getpwuid($<))[0] ne $crsusr);
  trace("I","Starting To Remove MGMTDB and Disable Related CHM&OC4J Functions...");
  deinstallMGMTDB();
  trace("I","MGMTDB Deletion Successfully Completed!");
}
elsif ( $mvmgmtdb && $target ) 
{
  die "Must move MGMTDB (GIMR) as $crsusr (Grid Infrastructure owner user)... \n" if ((getpwuid($<))[0] ne $crsusr);
  my $rnode = whereMGMTDBRunning();
  if ($hostname ne $rnode) {
  exit_error(1,"Error: The MGMTDB is not running locally");    
  }
  print "Moving MGMTDB, it will be stopped, are you sure (Y/N)? ";
  my $userinput = <STDIN>;
  chomp ($userinput);
  exit 1 if ($userinput eq "");

  if ( $userinput eq "Y" or $userinput eq "y" ){
    checkMGMTDBPath();
    createNewPath();
    getFilesLocation();
    $time = generateCurrentTimeStample(); 
    createCTRLFileScript();

    createTempPFile();
    changeTempPFile($target);
    createTargetSPFile($target);

    createCTRL($target);
    setSPFile($target);
    updateInit();
    removeDBFile();
    changeDependency();
    restartMDMTDB();
    trace("I","MGMTDB Successfully moved to $target!");
  }
  else {
    exit;
  }
} 
elsif ( $rmchm )
{
  die "Must remove CHM as root user ... \n" if ($< != 0 );
  trace("I","Starting To Disable CHM...");
  deinstallCHM();
  trace("I","Disable CHM Successfully Completed!");
} elsif ( $addchm )
{
  die "Must configure CHM as root user ... \n" if ($< != 0 );
  trace("I","Starting To Configure CHM...");
  configureCHM();
  trace("I","CHM Configure Successfully Completed!");
}
elsif ( $status )
{
  trace("I","Checking CHM status...");
  statusCHM();
}
else {
  pod2usage(-msg => "Unrecognized options passed!\n", -exitval => $usage_rc);
  exit;
}

# ====================================================================
sub configureCHM
{
  # Create CHM/OS config
  my $bdbloc;
  crf_do_delete();
  my $crfconfig    = catfile($crshome, 'crf', 'admin',
                              'crf' . $hostname . '.ora');
  my $tmpcrfconfig = crf_config_generate($hostname,
                                          "default",
                                          $crsusr,
                                          @nodelist);
  $bdbloc = catfile($crshome, 'crf', 'db', $hostname);
  
  if ( ! isCHMConfigured() )
  { 
    my $rc=0;
    my @out=();
    deinstallCHM();
    copy_file($tmpcrfconfig, $crfconfig);
    trace("I","Creating CHM/OS config file $crfconfig");
    unlink $tmpcrfconfig;
    ($rc,@out)=system_cmd_capture("$crshome/bin/crsctl add type ora.crf.type -basetype ora.daemon.type -file $crshome/crs/template/crf.type -init");
    exit_error(1,"Failed to add type ora.crf.type on $hostname, exiting...") if ($rc);
    ($rc,@out)=system_cmd_capture("$crshome/bin/crsctl add resource ora.crf -attr \" ACL=\'owner:root:rw-,pgrp:oinstall:rw-,other::r--,user:grid:r-x\' \" -type ora.crf.type -init");
    exit_error(1,"Failed to add resource ora.crf on $hostname, exiting...") if ($rc);
    ($rc,@out)=system_cmd_capture("$crshome/bin/crsctl start res ora.crf -init");
    exit_error(1,"Failed to start ora.crf on $hostname, exiting...") if ($rc);
  } 
  else 
  {
    trace("I","CHM has already been configured!");
    if ( isCHMRunning() )
    {
      stopCHM();
      startCHM();
    } 
    else {startCHM();}; 
  }
}

sub deinstallCHM
{
  my $bdbloc = catfile($crshome, 'crf', 'db', $hostname);
  my $chmconfigloc = catfile($crshome, 'crf', 'admin');
  my $is_crf_running = isCHMRunning();
  
  stopCHM() if ($is_crf_running);
  crf_delete_bdb($bdbloc);
  crf_delete_chmconfig($chmconfigloc);
  crf_remove_chm_res();
}

sub crf_config_generate
{
  my $master = "";
  my $replica = "";
  my $masterpub = "";
  my ($mynameEntry,$bdbloc,$usernm,@hosts)=@_;
  my $hlist=join(",",@hosts);
  my @clustname_out = system_cmd("$crshome/bin/olsnodes -c");
  
  my $clustnm=$clustname_out[1];
  my $crfhome = $crshome;
  my $host = $hostname;
  my $configfile;

  (undef, $configfile) = tempfile();
  $master = $hosts[0];
  if ($platform eq "windows")
  {
    $usernm = "";
  }

  # no replica if less than 2 nodes
  if (scalar(@hosts) >= 2) { $replica = $hosts[1]; }

  if ($mynameEntry eq $master)
  {
    $masterpub = $host;
  }

  my $orafile = catfile ($crfhome, "crf", "admin", "crf$host.ora");

  if (!-e $orafile)
  {
    open CONFIG_FILE,'>',$configfile or die $!;
    print CONFIG_FILE  "BDBLOC=$bdbloc\n" ;
    print CONFIG_FILE  "PINNEDPROCS=$pinproc\n" ;
  }
  else
  {
    copy_file($orafile, $configfile);
    open CONFIG_FILE,'>>',$configfile or die $!;
    if (getCHMAttrib("BDBLOC", $configfile) eq "")
    {
      print CONFIG_FILE  "BDBLOC=$bdbloc\n" ;
    }
    if (getCHMAttrib("PINNEDPROCS", $configfile) eq "")
    {
      print CONFIG_FILE  "PINNEDPROCS=$pinproc\n" ;
    }
  }

  if (getCHMAttrib("HOSTS", $configfile) eq "")
  {
    print CONFIG_FILE  "HOSTS=$hlist\n" ;
  }
  if (getCHMAttrib("MASTER", $configfile) eq "")
  {
    print CONFIG_FILE  "MASTER=$master\n" ;
  }
  if (getCHMAttrib("MYNAME", $configfile) eq "")
  {
    print CONFIG_FILE  "MYNAME=$mynameEntry\n" ;
  }
  if (getCHMAttrib("MASTERPUB", $configfile) eq "")
  {
    print CONFIG_FILE  "MASTERPUB=$masterpub\n" ;
  }
  if (getCHMAttrib("CLUSTERNAME", $configfile) eq "")
  {
    print CONFIG_FILE  "CLUSTERNAME=$clustnm\n" ;
  }
  if (getCHMAttrib("USERNAME", $configfile) eq "")
  {
    print CONFIG_FILE  "USERNAME=$usernm\n";
  }
  if (getCHMAttrib("CRFHOME", $configfile) eq "")
  {
    print CONFIG_FILE  "CRFHOME=$crfhome\n" ;
  }
  close CONFIG_FILE ;
  return $configfile;
}

sub statusCHM
{ 
  my ($rc,@out);
  my $lsnhost=whereMGMTLSNRunning();
  if ( $lsnhost eq "" ) {
    my @out=system_cmd("$crshome/bin/srvctl status mgmtlsnr");
    if ( grep(/PRCD-1120|PRCR-1001/,@out) ) {
      trace("W","MGMTLSNR is not configured");
    }
    elsif ( grep(/Listener MGMTLSNR is not running/,@out) ) {
      trace("W","Listener MGMTLSNR is not runnig");
    }
  }
  else {
    trace("I","Listener MGMTLSNR is configured and running on $lsnhost");
  }
  
  my $mdbhost=whereMGMTDBRunning();
  if ( $mdbhost eq "" ) {
    my @out=system_cmd("$crshome/bin/srvctl status mgmtdb");
    if ( grep(/PRCD-1120|PRCR-1001/,@out) ) {
      trace("W","MGMTDB is not configured on $hostname!");
    }
    elsif ( grep(/Database is not running/,@out) ) {
      trace("W","Database MGMTDB is not runnig");
    }
  }
  else {
    trace("I","Database MGMTDB is configured and running on $mdbhost");
  }

  my $run = isCHMRunning();
  my $conf = isCHMConfigured();  
  if ($conf && $run) {
    trace("I","Cluster Health Monitor (CHM) is configured and running"); 
    @out=system_cmd("$crshome/bin/oclumon manage -get reppath");
    if ( grep(/Connection Error/,@out) ) {
      exit(0);
    }
    if (defined $out[2]){
      print "--------------------------------------------------------------------------------\n";
      print "$out[2]\n"; 
    }
    my @target = split(/\=/, $out[2]);
    my $dg = my_trim_data($target[1]);
    @target = split(/\//, $dg);
    $dg = my_trim_data($target[0]);
    my $asmsid = getasmsid();
    my $asmsetenv = racsetenv($crshome,$asmsid);
    ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp du --suppressheader \'$dg/_MGMTDB/\'");

    my @space = split(/\ /, my_trim_data($out[1]));
    print("MGMTDB space used on DG $dg = $space[0] Mb\n");
    print "--------------------------------------------------------------------------------\n";
    trace("W", "Not able to get the MGMTDB size")  if ($rc);
  }
  elsif ($conf && !$run)  {
    trace("W", "Cluster Health Monitor (CHM) is configured and not running on $hostname!");  
  }
  else {
    trace("W", "Cluster Health Monitor (CHM) is not configured and not running on $hostname!");  
  }
}

# This subroutine takes argument as attribute of ora file and returns
# the corresponding value of that attribute in the ora file.
# Eg: If ora file has a line with "BDBSIZE = 25632",
# this subroutine returns 25632.
sub getCHMAttrib
{
  my $arg = $_[0];
  my $orafile = $_[1];
  my $loc="";
  my $home = $crshome;
  my $host = $hostname;
  $host =~ tr/A-Z/a-z/;

  if ($arg ne ""){
    # Read the ora file to get the BDB path
    if ($orafile eq ""){
      $orafile = catfile ($home, "crf", "admin", "crf$host.ora");
    }
    if (!-f $orafile){
      trace("I","Info: No ora file present at $orafile");
      return "";
    }

    my @filecontent = readfile ($orafile);
    foreach my $line (@filecontent){
      # skip blanks and comments
      if ($line !~ /^#|^\s*$/){
        if ($line =~ /$arg=(.*)/) { $loc = $1; last;}
      }
    }
    return $loc;
  }
  return "";
}

# Verify if CHM is running now
# Return 1 when CHM is running otherwise return 0
sub isCHMRunning
{
  my $rc=0;
  my @chmstat_out = system_cmd("$crshome/bin/crsctl stat res ora.crf -init");
  my @chmstat = grep /STATE=ONLINE/, @chmstat_out;
  $rc=1 if (scalar(@chmstat));
  return $rc;
}

#Verify if CHM configured in environment
#Return 1 when CHM is configured otherwise return 0
sub isCHMConfigured
{
  my $rc=1;
  my @rmchmres_out=();
  my @rmchmrestype_out=();
  my @statchmres_out=system_cmd("$crshome/bin/crsctl stat res ora.crf -init");
  my @statchmrestype_out=system_cmd("$crshome/bin/crsctl stat type ora.crf.type -init");
  $rc=0 if ( grep(/CRS-2613/,@statchmres_out) || grep(/CRS-2560/,@statchmrestype_out) );
  $rc=0 if ( ! -e "$crshome/crf/admin/crf$hostname.ora" );
  $rc=0 if ( ! -e "$crshome/crf/admin/crf$hostname.cfg" );
  return $rc;
}

# Stop CHM on Local Host
# Return 0 when stop action succceeds otherwise retrun 1
sub stopCHM
{
  my $rc=1;
  my @downchm_out = system_cmd("$crshome/bin/crsctl stop res ora.crf -init");
  my @downchm = grep /CRS-2677|CRS-2500/, @downchm_out;
  exit_error(1,"Fail to stop CHM on $hostname, exiting...") if (!scalar(@downchm)) or $rc=0;
  return $rc;
}

sub startCHM
{
  my $rc=1;
  my @startchm_out = system_cmd("$crshome/bin/crsctl start res ora.crf -init");
  my @startchm = grep /CRS-5702|CRS-2676/, @startchm_out;
  exit_error(1,"Fail to start CHM on $hostname, exiting...") if (!scalar(@startchm)) or $rc=0;
  return $rc; 
}

# delete the bdb files in bdbloc.
sub crf_delete_bdb
{
  my $bdbloc = $_[0];
  my $cwd = getcwd();

  if ($bdbloc ne "" and -d $bdbloc)
  {
    # remove files which we created.
    chdir $bdbloc or exit_error(1, "Cannot switch to BDB directory $bdbloc");
    opendir(DIR, "$bdbloc") || exit_error(1, "Cannot switch to BDB directory $bdbloc, exiting...");
    my $crfbdbfile;
    my @ldbfiles = grep(/\.ldb$/,readdir(DIR));
    foreach $crfbdbfile (@ldbfiles)
    {
      unlink ($crfbdbfile);
    }

    # database files
    rewinddir (DIR);
    my @bdbfiles = grep(/\.bdb$/,readdir(DIR));
    foreach $crfbdbfile (@bdbfiles)
    {
      unlink ($crfbdbfile);
    }

    # env files
    rewinddir (DIR);
    my @dbfiles = grep(/__db.*$/,readdir(DIR));
    foreach $crfbdbfile (@dbfiles)
    {
      unlink ($crfbdbfile);
    }

    # archive log
    rewinddir (DIR);
    my @bdblogfiles = grep(/log.*$/,readdir(DIR));
    foreach $crfbdbfile (@bdblogfiles)
    {
      unlink ($crfbdbfile);
    }
    closedir (DIR);
    # change back to current working directory.
    chdir $cwd or exit_error(1, "Cannot switch to current directory $cwd, exiting...");
  }
}

sub crf_delete_chmconfig
{
  my $chmconfigloc = $_[0];
  my $cwd = getcwd();

  if ($chmconfigloc ne "" and -d $chmconfigloc)
  {
    # remove files which we created.
    chdir $chmconfigloc or exit_error(1, "Cannot switch to CHM Configure File directory $chmconfigloc, exiting...");
    opendir(DIR, "$chmconfigloc") || exit_error(1, "Cannot open CHM Configure File directory $chmconfigloc, exiting...");
    my $cfgfile;
    my @cfgfiles = grep(/crf/,readdir(DIR));
    foreach $cfgfile (@cfgfiles)
    {
      unlink ($cfgfile);
    }
    closedir (DIR);
    # change back to current working directory.
    chdir $cwd or exit_error(1, "Cannot switch to current directory $cwd, exiting...");
  }
}

sub crf_remove_chm_res
{
  my $rc1=0;
  my $rc2=0;
  my @rmchmres_out=();
  my @rmchmrestype_out=();
  my @statchmres_out=system_cmd("$crshome/bin/crsctl stat res ora.crf -init");
  if ( !grep(/CRS-2613/,@statchmres_out) )
  {
      ($rc1,@rmchmres_out)=system_cmd_capture("$crshome/bin/crsctl delete res ora.crf -init");
      exit_error(1,"Failed to remove resource ora.crf on $hostname, exiting...") if ($rc1); 
  }
  my @statchmrestype_out=system_cmd("$crshome/bin/crsctl stat type ora.crf.type -init");
  if ( !grep(/CRS-2560/,@statchmrestype_out) ) 
  {
      ($rc2,@rmchmrestype_out)=system_cmd_capture("$crshome/bin/crsctl delete type ora.crf.type -init");
      exit_error(1,"Failed to remove resource type ora.crf.type on $hostname, exiting...") if ($rc2);
  }
  return ($rc1,$rc2);
}

sub crf_do_delete
{
   # shutdown the sysmond, ologgerd, oproxyd if they are running
   my ($cmd, $instdir, $defpath, $rootpath, $configfile, $line, $bdbloc,
       $admindir, $admin, $runpth);

      $instdir  = "/usr/lib/oracrf";
      $defpath  = "/usr/bin/";
      $rootpath = "/";

   my $instfile = catfile($instdir, "install", "installed");

   if ( -f $instfile ) 
   {
      $cmd = "oclumon"." ". "stop"." ". "all";
      my $crfhome = $instdir;
      $admindir = catfile("$instdir", "crf");
      if ( -d $admindir) {
         $configfile = catfile($instdir, "crf", "admin", "crf" . $hostname . ".ora");
         $runpth     = catfile($crfhome, "crf", "admin", "run");
         $admin      = 'crf';
      }
      else {
         $configfile = catfile($instdir, "admin", "crf" . $hostname . ".ora");
         $runpth     = catfile($crfhome, "admin", "run");
         $admin      = 'admin';
      }

      system("$cmd");
      sleep(5);

      # read config file to find older BDB loc
      $bdbloc = getCHMAttrib("BDBLOC", $configfile);
      if ($bdbloc eq "default")
      {
        $bdbloc = catfile($instdir, "crf", "db", "$hostname");
      }

      my $pidf=catfile($runpth, "crfmond", "s" . $hostname . ".pid");
      if (-f $pidf) {
         open(PID_FILE, $pidf);
         while (<PID_FILE>) {
            my $pid=$_;
            kill(15, $pid);

            # if that didn't work, use force
            if (kill(0, $pid)) 
            {
               kill(9, $pid);
            }
         }
         close(PID_FILE);
         unlink($pidf);
      }

      my $dir = catfile("$runpth", "crfmond");
      rmdir("$dir");

      # ologgerd now
      $pidf=catfile($runpth, "crflogd", "l" . $hostname . ".pid");
      if (-f $pidf) {
         open(PID_FILE, $pidf);
         while (<PID_FILE>) {
            my $pid=$_;
            kill(15, $pid);

            # if that didn't work, use force
            if (kill(0, $pid)) 
            {
               kill(9, $pid);
            }
         }

         close(PID_FILE);
         unlink($pidf);
      }

      $dir = catfile($runpth, "crflogd");
      rmdir("$dir");

      # proxy next
      $pidf=catfile($runpth, "crfproxy", "p" . $hostname . ".pid");
      if (-f $pidf) {
         open(PID_FILE, $pidf);
         while (<PID_FILE>) {
            my $pid=$_;
            kill(15, $pid);

            # if that didn't work, use force
            if (kill(0, $pid)) 
            {
               kill(9, $pid);
            }
            # give some time to oproxy to react.
            sleep 2;
         }

         close(PID_FILE);
         unlink($pidf);
      }

      $dir = catfile($runpth, "crfproxy");
      rmdir("$dir");

      # ask crfcheck to shutdown cleanly
      $pidf=catfile($crfhome, "log", $hostname, "crfcheck", "crfcheck.lck");
      if (-f $pidf) {
         open(PID_FILE, $pidf);
         while (<PID_FILE>) {
            kill 15, $_;
         }
         close(PID_FILE);
      }

      my $rootpath;
      unlink("/etc/init.d/init.crfd");
      `sed '/^#.*$/!s/^.*init.*crfd.*$/#&/g' /etc/inittab -i.bak`;

      # remove the tree
      my $filed;
      my $file;
      foreach $filed ('bin', 'lib', $admin, 'jlib', 'mesg', 'log',
                     'install', 'jdk', 'db')
      {
         $file = catfile($instdir, "$filed");
         rmtree("$file", 0, 0);
      }

      # delete old bdb files.
      crf_delete_bdb($bdbloc);

      unlink("$defpath"."crfgui");
      unlink("$defpath"."oclumon");
      unlink("$defpath"."ologdbg");

      # change dir to a safer place
      chdir $rootpath;
      rmdir $instdir;
   }
}

sub deinstallMGMTDB
{
   my ($rc,$out);
   my $mdbhost=whereMGMTDBRunning();
   if ($mdbhost eq "")
   {
     my @out=system_cmd("$crshome/bin/srvctl start mgmtdb -n $hostname");
     trace("W","Not found MGMTDB Configured in Cluster!") if ( grep(/PRCD-1120|PRCR-1001/,@out) );
     if ( grep(/PRCR-1013|PRCR-1064/,@out ) ) {
       ($rc,@out) = system_cmd_capture("echo \"y\" | $crshome/bin/srvctl remove mgmtdb");
       trace("W","Cannot remove MGMTDB") if ($rc);
     }
   }
     
   if ($mdbhost ne $hostname && $mdbhost)
   {
      ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl relocate mgmtdb -n $hostname");
      trace("W","Cannot relocate mgmtdb to $hostname!") if ($rc);
   }

   if ( $mdbhost )
   {
      ($rc,@out) = system_cmd_capture("$crshome/bin/dbca -silent -deleteDatabase -sourceDB -MGMTDB");
      trace("W","Cannot delete MGMTDB on $hostname") if ($rc);
      ($rc,@out) = system_cmd_capture("echo \"y\" | $crshome/bin/srvctl remove mgmtdb");
      #trace("W","Cannot remove MGMTDB") if ($rc);
   }

   ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl stop mgmtlsnr");
   exit_error(1,"Cannot stop MGMTLSNR on $hostname, exiting...") if ($rc && ! grep (/PRCR-1001/,@out));
   ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl remove mgmtlsnr");
   exit_error(1,"Cannot remove MGMTLSNR on $hostname, exiting...") if ($rc && ! grep (/PRCR-1001/,@out));
   disableOC4J();

   foreach (@nodelist)
   { 
      my $host=$_;
      my $scriptpath=__FILE__;
      my $scriptname=basename(__FILE__);
      system_cmd("scp $scriptpath $host:/tmp/" );
      trace("I","Executing \"/tmp/$scriptname --rmchm\" on $host as root to deinstall CHM.");
      $rc = system_cmd("ssh root\@$host \"/tmp/$scriptname --rmchm\"");
      trace("W","Not able to execute \"/tmp/$scriptname --rmchm\" on $host as root to deinstall CHM.") if ($rc);
   }
}

sub configMGMTDB
{
  my $target = shift;
  $target =~ s/\+(.*)/$1/;
  my ($rc,@out);
  @out=system_cmd("$crshome/bin/srvctl status mgmtlsnr");
  if (grep(/PRCR-1001/,@out))
  {
    ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl add mgmtlsnr");
    exit_error(1,"Cannot add MGMTLSNR on $hostname, exiting...") if ($rc && ! grep (/PRCR-1001/,@out));    
  }
  my $mdbhost=whereMGMTDBRunning();
  if (! $mdbhost )
  {
    my @out=system_cmd("$crshome/bin/srvctl status mgmtdb");
    if ( grep(/PRCD-1120|PRCR-1001/,@out) )
    {
    ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl stop mgmtlsnr");
    exit_error(1,"Cannot stop MGMTLSNR on $hostname, exiting...") if ($rc && ! grep (/PRCC-1016|PRCR-1005/,@out));   
    enableOC4J();    
        
    my $crsver = get_crs_version();
    my @ver = split(/\./, $crsver);
    
    if ( $ver[3] eq 1 ) {     
      ($rc,@out) = system_cmd_capture("$crshome/bin/dbca  -silent -createDatabase -templateName MGMTSeed_Database.dbc -sid -MGMTDB -gdbName _mgmtdb -storageType ASM -diskGroupName $target -datafileJarLocation $crshome/assistants/dbca/templates -characterset AL32UTF8 -autoGeneratePasswords   -oui_internal");
      exit_error(1,"Cannot create MGMTDB on $hostname, exiting...") if ($rc);    
    }
    elsif ( $ver[3] gt 1 ) {  
      trace("I","Container database creation in progress..."); 
      ($rc,@out) = system_cmd_capture("$crshome/bin/dbca  -silent -createDatabase -createAsContainerDatabase true -templateName MGMTSeed_Database.dbc -sid -MGMTDB -gdbName _mgmtdb -storageType ASM -diskGroupName $target -datafileJarLocation $crshome/assistants/dbca/templates -characterset AL32UTF8 -autoGeneratePasswords -skipUserTemplateCheck");
      exit_error(1,"Cannot create CDB MGMTDB on $hostname, exiting...") if ($rc);    
      
      trace("I","Plugable database creation in progress..."); 
      my $clstname = get_cluster_name();
      ($rc,@out) = system_cmd_capture("$crshome/bin/dbca -silent -createPluggableDatabase -sourceDB -MGMTDB -pdbName $clstname -createPDBFrom RMANBACKUP -PDBBackUpfile $crshome/assistants/dbca/templates/mgmtseed_pdb.dfb -PDBMetadataFile $crshome/assistants/dbca/templates/mgmtseed_pdb.xml -createAsClone true -internalSkipGIHomeCheck");
      exit_error(1,"Cannot create PDB $clstname on $hostname, exiting...") if ($rc);
    }
            
    ($rc,@out) = system_cmd_capture("$crshome/bin/mgmtca");
    exit_error(1,"MGMTCA failed on $hostname, exiting...") if ($rc);
    }
  }
  else {
      trace("W","MGMTDB is already configured and running on $mdbhost, skipping...");
  }
  foreach (@nodelist)
  { 
    my $host=$_;
    my $scriptpath=__FILE__;
    my $scriptname=basename(__FILE__);
    system_cmd("scp $scriptpath $host:/tmp/" );
    trace("I","Executing \"/tmp/$scriptname --addchm\" on $host as root to configure CHM.");      
    $rc = system_cmd("ssh root\@$host \"/tmp/$scriptname --addchm\"");
    trace("W","Not able to execute \"/tmp/$scriptname --addchm\" on $host as root to configure CHM.") if ($rc);
  }
}

sub disableOC4J
{
  my ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl stop oc4j");
  exit_error(1,"Cannot stop OC4J on $hostname, exiting...") if ($rc && ! grep (/PRCC-1016|PRCR-1005/,@out));  
  ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl disable oc4j");
  exit_error(1,"Cannot disable OC4J on $hostname, exiting...") if ($rc && ! grep (/PRKO-2115/,@out) );  
}

sub enableOC4J
{
  my ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl enable oc4j");
  exit_error(1,"Cannot enable OC4J on $hostname, exiting...") if ($rc && ! grep (/PRKO-2116/,@out));  
  ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl start oc4j");
  exit_error(1,"Cannot start OC4J on $hostname, exiting...") if ($rc && ! grep (/PRCC-1014|PRCR-1004/,@out));  
}

sub isMGMTDBRunning
{
  my $rc=0;
  my @mdbstat_out=system_cmd("$crshome/bin/srvctl status mgmtdb");
  $rc=1 if (grep(/MGMTDB is running on/,@mdbstat_out));
  return $rc;
}

sub isMGMTLSNRunning
{
  my $rc=0;
  my @mdbstat_out=system_cmd("$crshome/bin/srvctl status mgmtlsnr");
  $rc=1 if (grep(/Listener MGMTLSNR is running on/,@mdbstat_out));
  return $rc;
}

sub whereMGMTDBRunning
{
  my $mdbhost="";
  if (isMGMTDBRunning())
  {
      my @mdbstat_out=system_cmd("$crshome/bin/srvctl status mgmtdb");
      my $mdbhost=$mdbstat_out[-1];
      $mdbhost =~ s/^.*(node )(.*)$/$2/;
      return $mdbhost;
  }
  return $mdbhost;
}

sub whereMGMTLSNRunning
{
  my $host="";
  if (isMGMTLSNRunning())
  {
      my @mdbstat_out=system_cmd("$crshome/bin/srvctl status mgmtlsnr");
      my $host=$mdbstat_out[-1];
      $host =~ s/^.*(node\(s\): )(.*)$/$2/;
      return $host;
  }
  return $host;
}

sub generateCurrentTimeStample
{
  # Get local system time and convert to standard format 'yyyymmddhh24mi', to minute
  my ($sec,$min,$hour,$day,$mon,$year)=localtime(time);
  #month array begins at '0'...
  $mon++;
  if (length ($mon) == 1) {$mon = '0'.$mon;}
  if (length ($day) == 1) {$day = '0'.$day;}
  if (length ($hour) == 1) {$hour = '0'.$hour;}
  if (length ($min) == 1) {$min = '0'.$min;}
  if (length ($sec) == 1) {$sec = '0'.$sec;}
  $year+=1900;
  return $day = $year.$mon.$day.$hour.$min.$sec;
}

sub getCHMDatafileLocation 
{
  local *TEMP;
  my $tmpfile="$tmp/mdbutil_chmdatafileloc.sql";
  open(TEMP, ">$tmpfile");   
  print TEMP "set echo off;\n";
  print TEMP "set feedback off;\n";
  print TEMP "set pagesize 0;\n";
  print TEMP "set linesize 32000;\n";
  print TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  
  my $crsver = get_crs_version();
  my @ver = split(/\./, $crsver); 
     
  if ($ver[3] gt 1) { 
    my $clstname = get_cluster_name();
    print TEMP "ALTER SESSION SET CONTAINER = $clstname;\n";
  }
    
  print TEMP "select file_name from dba_data_files where tablespace_name='SYSMGMTDATA';\n";
  print TEMP "exit;\n";
  close(TEMP);
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$tmpfile
EOF'};
  my @rc = split(":", $rc_string);
  if ( $rc[0] eq 'ERROR' ) {
    $rc_string = my_trim_data( $rc[1]);
    unlink $tmpfile;
    exit_error(1,"Unable to get CHM Datafile location, due to error: $rc_string, exiting...");
  }
  unlink $tmpfile;
  return  $rc_string;
}

sub openPDB
{
  my $clstname = shift; 
  local *TEMP;
  my $tmpfile="$tmp/mdbutil_openpdb.sql";
  open(TEMP, ">$tmpfile");   
  print TEMP "set echo off;\n";
  print TEMP "set feedback off;\n";
  print TEMP "set pagesize 0;\n";
  print TEMP "set linesize 32000;\n";
  print TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  
  print TEMP "ALTER PLUGGABLE DATABASE $clstname OPEN READ WRITE;\n";          
  print TEMP "exit;\n";
  close(TEMP);
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";

  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$tmpfile
EOF'};
  my @rc = split(":", $rc_string);
  if ( $rc[0] eq 'ERROR' ) {
    $rc_string = my_trim_data( $rc[1]);
    unlink $tmpfile;
    exit_error(1,"Unable open MGMTDB PDB Database, due to error: $rc_string, exiting...");
  }
  unlink $tmpfile;
}

sub getMGMTDBDatafilesLocation 
{
  my $clstname = shift; 
  local *TEMP;
  my $tmpfile="$tmp/mdbutil_dbfileloc.sql";
  open(TEMP, ">$tmpfile");  
  print TEMP "set echo off;\n";
  print TEMP "set feedback off;\n";
  print TEMP "set pagesize 0;\n";
  print TEMP "set linesize 32000;\n";
  print TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  
  if ( defined($clstname) ) {
      trace("I","Getting MGMTDB PDB $clstname files location");
      openPDB($clstname);        
      print TEMP "ALTER SESSION SET CONTAINER = $clstname;\n";
  }
  else {
      trace("I","Getting MGMTDB Database files location");
  } 
  print TEMP "select file_name from dba_data_files;\n";
  print TEMP "exit;\n";
  close(TEMP);
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";

  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$tmpfile
EOF'};
  
  my @rc = split(":", $rc_string);
  if ( $rc[0] eq 'ERROR' ) {
    my $rc_string = $rc[1];
    unlink $tmpfile;
    exit_error(1,"Unable to get MGMTDB datafiles location, due to error: $rc_string, exiting...");
  }
  my $out = my_trim_data($rc_string);
  my @array = split('\n', $out);
  unlink $tmpfile;
  return @array;
}

sub getMGMTDBTempfilesLocation 
{
  my $clstname = shift; 
  local *TEMP;
  my $tmpfile="$tmp/mdbutil_tempfileloc.sql";
  open(TEMP, ">$tmpfile");  
  print TEMP "set echo off;\n";
  print TEMP "set feedback off;\n";
  print TEMP "set pagesize 0;\n";
  print TEMP "set linesize 32000;\n";
  print TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";

  if ( defined($clstname) ) { 
      trace("I","Getting MGMTDB PDB $clstname Temp files location");
      openPDB($clstname);  
      print TEMP "ALTER SESSION SET CONTAINER = $clstname;\n";
  } 
  else {
      trace("I","Getting MGMTDB Temp files location");
  }     
  print TEMP "select file_name from dba_temp_files;\n";
  print TEMP "exit;\n";
  close(TEMP);
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$tmpfile
EOF'};
  
  my @rc = split(":", $rc_string);
  if ( $rc[0] eq 'ERROR' ) {
    $rc_string = $rc[1];
    unlink $tmpfile;
    exit_error(1,"Unable to get MGMTDB temp datafiles location, due to error: $rc_string, exiting...");
  }
  my $out = my_trim_data($rc_string);
  my @array = split('\n', $out);
  unlink $tmpfile;
  return @array;
}

sub getCTRLFileLocation 
{
  trace("I","Getting DB CTRL file location");
  local *TEMP;
  my $tmpfile="$tmp/mdbutil_ctrlfileloc.sql";    
  open(TEMP, ">$tmpfile");   
  print TEMP "set echo off;\n";
  print TEMP "set feedback off;\n";
  print TEMP "set pagesize 0;\n";
  print TEMP "set linesize 32000;\n";  
  print TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";

  print TEMP "select name from v\$controlfile;\n";
  print TEMP "exit;\n";
  close(TEMP);
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$tmpfile
EOF'};
  
  my @rc = split(":", $rc_string);
  if ( $rc[0] eq 'ERROR' ) {
    $rc_string = $rc[1];
    unlink $tmpfile;
    exit_error(1,"Unable to get MGMTDB ctrl file location, due to error: $rc_string, exiting...");
  }
  unlink $tmpfile;
  return $rc_string;
}

sub getFilesLocation {
  @datafileslocation = getMGMTDBDatafilesLocation();
  @tempdatafileslocation = getMGMTDBTempfilesLocation();   

  my $crsver = get_crs_version();
  my @ver = split(/\./, $crsver); 
  if ($ver[3] gt 1) { 
    my $clstname = get_cluster_name();   
    @pdbdatafileslocation = getMGMTDBDatafilesLocation($clstname);
    @pdbtempdatafileslocation = getMGMTDBTempfilesLocation($clstname);       
  }
}

sub getRedoLogInfo {
  my $sredo="$tmp/mdbutil_slog.sql";   
  open(my $TEMP, '>', $sredo) or die "Could not open file '$sredo $!";
  print $TEMP "set echo off;\n";
  print $TEMP "set feedback off;\n";
  print $TEMP "set pagesize 0;\n";
  print $TEMP "set linesize 32000;\n";  
  print $TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  print $TEMP "SELECT GROUP#,',',BYTES FROM V\$LOG;\n";
  print $TEMP "exit;\n";
  close($TEMP);

  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  my $redoinfo = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$sredo
EOF'};

  unlink $sredo;
  exit_error(1,"Unable get source RedoLog info, due to error:\n $redoinfo, exiting...") if (grep (/ERROR/,$redoinfo));
  
  my $out = my_trim_data($redoinfo);
  my @redoinfo = split('\n', $out); 
  return @redoinfo;
}


sub createCTRLFileScript {
  local *TEMP;
  my $tmpfile = "$tmp/mdbutil_CTRLFile.sql";
  my $targetPFile="$tmp/mdbutil_targetPFile.ora"; 
  open(TEMP, ">$tmpfile");
  print TEMP "STARTUP NOMOUNT pfile=$targetPFile\n";
  print TEMP "CREATE CONTROLFILE REUSE DATABASE \"_MGMTDB\" RESETLOGS  NOARCHIVELOG\n";
  print TEMP "    MAXLOGFILES 16\n";
  print TEMP "    MAXLOGMEMBERS 3\n";
  print TEMP "    MAXDATAFILES 1024\n";
  print TEMP "    MAXINSTANCES 2\n";
  print TEMP "    MAXLOGHISTORY 1168\n";
  print TEMP "LOGFILE\n";
  
  my $redo;
  my @check_location;
  my $source;

  my @redoinfo = getRedoLogInfo();
  my ($group_no, $size);
  my $i=0;
  foreach (@redoinfo){
    chomp;
    ($group_no, $size) = split(/,/,$redoinfo[$i]);
    $group_no=my_trim_data($group_no);
    $size=my_trim_data($size);
    $i++;
    print TEMP "  GROUP $group_no '$target/_MGMTDB/ONLINELOG/redo$group_no.$time.log' SIZE $size BLOCKSIZE 512,\n"; 
  }

  print TEMP "DATAFILE\n";   

  $i=1;
  my $dbfile;
  my $dbfilenum = @datafileslocation;
  my $pdbdbfilenum = @pdbdatafileslocation;
  foreach (@datafileslocation) {
    $dbfile = $_;
    $dbfile = basename($dbfile);
    $dbfile =~ s{\.[^.]+$}{};
    $dbfile =~ s{\.[^.]+$}{};    
    $dbfile = $dbfile . "." . $time;

    if ( $i < $dbfilenum ){ 
      print TEMP "'$target/_MGMTDB/DATAFILES/$dbfile.dbf',\n";
    }
    elsif ( ($i = $dbfilenum) or ($pdbdbfilenum == 0) ) {
      print TEMP "'$target/_MGMTDB/DATAFILES/$dbfile.dbf',\n";
    }    
    else {
      print TEMP "'$target/_MGMTDB/DATAFILES/$dbfile.dbf'\n";
    }
    $i = $i+1;
  }

  $i=1;
  my $clstname;
  foreach (@pdbdatafileslocation) {
    $clstname = get_cluster_name();  
    $dbfile = $_;
    $dbfile = basename($dbfile);
    $dbfile =~ s{\.[^.]+$}{};
    $dbfile =~ s{\.[^.]+$}{};    
    $dbfile = $dbfile . "." . $time;
    if ( $i < $pdbdbfilenum ){ 
      print TEMP "'$target/_MGMTDB/DATAFILES/$clstname/$dbfile.dbf',\n";
    }
    else {
      print TEMP "'$target/_MGMTDB/DATAFILES/$clstname/$dbfile.dbf'\n";
    }
    $i = $i+1;
  }

  print TEMP "CHARACTER SET AL32UTF8;\n";   
  print TEMP "ALTER DATABASE OPEN RESETLOGS;\n";   
  print TEMP "ALTER PLUGGABLE DATABASE ALL OPEN;\n"; 
  
  foreach (@tempdatafileslocation) {
    print TEMP "ALTER TABLESPACE TEMP ADD TEMPFILE '$target' SIZE 104857600  REUSE AUTOEXTEND ON NEXT 104857600  MAXSIZE 32767M;\n";
  }  

  my $crsver = get_crs_version();
  my @ver = split(/\./, $crsver); 
  if ($ver[3] gt 1) { 
      $clstname = get_cluster_name();
      print TEMP "ALTER SESSION SET CONTAINER = $clstname;\n";
      foreach (@pdbtempdatafileslocation) {
        print TEMP "ALTER TABLESPACE TEMP ADD TEMPFILE '$target' SIZE 104857600  REUSE AUTOEXTEND ON NEXT 104857600  MAXSIZE 32767M;\n";
      }      
  }
  print TEMP "EXIT;\n";
  close(TEMP);
  return;
}

sub checkMGMTDBPath {
  my @out=system_cmd("$crshome/bin/oclumon manage -get reppath");
  if (defined $out[2] ){
    my @path = split("=",$out[2]);
    my @dg = split("/",$path[1]);
    my $dg = my_trim_data($dg[0]);
    if ( $dg eq $target ){
      exit_error(1,"MGMTDB is currently running from $dg diskgroup, exiting...");
    }
  }
}

sub createNewPath {
  my $asmsid = getasmsid();
  my $asmsetenv = racsetenv($crshome,$asmsid);
  
  trace("I","Checking for the required paths under $target"); 
  my ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/PARAMETERFILE/\'");
  if ($rc ne 0) {
      trace("I","Creating new path $target/_MGMTDB/PARAMETERFILE");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/\'");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/PARAMETERFILE/\'");
      exit_error(1,"Cannot create required path $target/_MGMTDB/PARAMETERFILE, exiting...") if ($rc);
  }  
  ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/CONTROLFILE/\'");
  if ($rc ne 0) {
      trace("I","Creating new path $target/_MGMTDB/CONTROLFILE");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/\'");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/CONTROLFILE/\'");
      exit_error(1,"Cannot create required path $target/_MGMTDB/CONTROLFILE, exiting...") if ($rc);
  }
  ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/ONLINELOG/\'");
  if ($rc ne 0) {
      trace("I","Creating new path $target/_MGMTDB/ONLINELOG");  
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/\'");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/ONLINELOG/\'");
      exit_error(1,"Cannot create required path $target/_MGMTDB/ONLINELOG, exiting...") if ($rc);
  }
  ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/DATAFILES/\'");
  if ($rc ne 0) {
      trace("I","Creating new path $target/_MGMTDB/DATAFILES");   
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/\'");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/DATAFILES/\'");
      exit_error(1,"Cannot create required path $target/_MGMTDB/DATAFILES, exiting...") if ($rc);
  } 
  ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/TEMPFILE/\'");
  if ($rc ne 0) {
      trace("I","Creating new path $target/_MGMTDB/TEMPFILE");  
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/\'");
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/TEMPFILE/\'");
      exit_error(1,"Cannot create required path $target/_MGMTDB/TEMPFILE, exiting...") if ($rc);
  }
    
  my $crsver = get_crs_version();
  my @ver = split(/\./, $crsver); 
  my $clstname;
  if ($ver[3] gt 1) { 
      $clstname = get_cluster_name(); 
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/DATAFILES/$clstname\'");
      if ($rc ne 0) {
        trace("I","Creating new path $target/_MGMTDB/DATAFILES/$clstname");  
        ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/DATAFILES/$clstname\'");
        exit_error(1,"Cannot create required path $target/_MGMTDB/DATAFILES/$clstname, exiting...") if ($rc);
      }    
      ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp ls \'$target/_MGMTDB/TEMPFILE/$clstname\'");
      if ($rc ne 0) {
        trace("I","Creating new path $target/_MGMTDB/TEMPFILE/$clstname");  
        ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp mkdir \'$target/_MGMTDB/TEMPFILE/$clstname\'");
        exit_error(1,"Cannot create required path $target/_MGMTDB/TEMPFILE/$clstname, exiting...") if ($rc);
      }          
  }
}

sub createTempPFile {

  my ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl config mgmtdb |grep Spfile");
  exit_error(1,"Cannot get original SPfile path, exiting...") if ($rc);
  my @original_path = split(":",$out[1]);
  my $path = my_trim_data($original_path[1]);

  my $sourcePFile="$tmp/mdbutil_sourcePFile.ora";   
  my $SQLpfile="$tmp/mdbutil_SQLpfile.sql"; 
  open(my $TEMP, '>', $SQLpfile) or die "Could not open file '$SQLpfile' $!";
  print $TEMP "set echo off;\n";
  print $TEMP "set feedback off;\n";
  print $TEMP "set pagesize 0;\n";
  print $TEMP "set linesize 32000;\n";  
  print $TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  print $TEMP "CREATE PFILE=\'$sourcePFile\' FROM SPFILE=\'$path\';\n";
  print $TEMP "exit;\n";
  close($TEMP);
    
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  trace("I","Creating temporary PFILE");
  
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$SQLpfile
EOF'};
  exit_error(1,"Unable create temporary PFILE, due to error:\n $rc_string, exiting...") if (grep (/ERROR/,$rc_string));  
  unlink $SQLpfile;  
}

sub changeTempPFile {
  my $target = shift;  

  my $sourcePFile="$tmp/mdbutil_sourcePFile.ora";
  my $targetPFile="$tmp/mdbutil_targetPFile.ora"; 

  open(my $INFILE, '<', $sourcePFile)  or die "Could not open file '$sourcePFile' $!";
  open(my $OUTFILE, '>', $targetPFile) or die "Could not open file '$targetPFile' $!";
  
  while (my $line = <$INFILE>) {
    if (( index($line, 'control_files' ) == -1) and ( index($line, 'db_create_file_dest' ) == -1) ) {
      print $OUTFILE $line;
    }
  }
  my $target_path=$target.'/_MGMTDB/CONTROLFILE/ctrl'.'.'.$time; 
  print $OUTFILE "*.control_files=\'$target_path\'\n";
  print $OUTFILE "*.db_create_file_dest=\'$target\'\n";
    
  close($INFILE);
  close($OUTFILE);  
  unlink $sourcePFile;      
}

sub createTargetSPFile {
  my $target = shift;
  my $targetPFile="$tmp/mdbutil_targetPFile.ora"; 
  my $targetSPFile=$target.'/_MGMTDB/PARAMETERFILE/spfile'.'.'.$time;
  my $SQLspfile="$tmp/mdbutil_spfile.sql"; 

  open(my $TEMP, '>', $SQLspfile) or die "Could not open file '$SQLspfile' $!";
  print $TEMP "set echo off;\n";
  print $TEMP "set feedback off;\n";
  print $TEMP "set pagesize 0;\n";
  print $TEMP "set linesize 32000;\n";  
  print $TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  print $TEMP "CREATE SPFILE=\'$targetSPFile\' FROM PFILE=\'$targetPFile\';\n";
  print $TEMP "exit;\n";
  close($TEMP);
    
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  trace("I","Creating target SPFILE");

  my ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl config mgmtdb |grep Spfile");
  exit_error(1,"Cannot get original SPfile path, exiting...") if ($rc);
  my @original_path = split(":",$out[1]);
  my $path = my_trim_data($original_path[1]);
  
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$SQLspfile
EOF'};
  exit_error(1,"Unable create target SPFILE: $targetSPFile, due to error:\n $rc_string, exiting...") if (grep (/ERROR/,$rc_string));  
  unlink $SQLspfile; 
  
  ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl modify mgmtdb -spfile \'$path\'");
  exit_error(1,"Cannot set original SPfile path, exiting...") if ($rc);
}

sub updateInit {
  my $dbsid = "-MGMTDB";
  my $s_init="$crshome/dbs/init$dbsid.ora";
  unlink($s_init);
  my $s_spfile="$crshome/dbs/spfile$dbsid.ora";
  unlink($s_spfile);
  
  system_cmd("touch $crshome/dbs/init$dbsid.ora");  
  
  trace("I","Modifing the init parameter");
  open(SINI,">$s_init") || die("ERROR   : cannot open init.ora at source host");
  print SINI "SPFILE=\"$target/_MGMTDB/PARAMETERFILE/spfile.$time\"\n";      
  close(SINI);
}

sub setSPFile {
  my $target = shift;
  trace("I","Setting MGMTDB SPFile location");    
  my $target_path=$target.'/_MGMTDB/PARAMETERFILE/spfile'.'.'.$time;
  my($rc,@out) = system_cmd_capture("$crshome/bin/srvctl modify mgmtdb -spfile \'$target_path\'");
  exit_error(1,"Cannot set SPfile path, exiting...") if ($rc);
  return;   
}

sub createCTRL {
  my $target = shift;
  my $tmpfile = "$tmp/mdbutil_CTRLFile.sql";
  my $targetPFile = "$tmp/mdbutil_targetPFile.ora";

  my $asmsid = getasmsid();
  my $asmsetenv = racsetenv($crshome,$asmsid);

  trace("I","Stopping mgmtdb");
  my($rc,@out) = system_cmd_capture("$crshome/bin/srvctl stop mgmtdb");
  exit_error(1,"Cannot stop mgmtdb, exiting...") if ($rc);
  
  my $olddbfile;
  my $dbfile;
  trace("I","Copying MGMTDB DBFiles to $target");
  foreach (@datafileslocation) {
    $olddbfile = $_;
    $dbfile = basename($olddbfile);
    $dbfile =~ s{\.[^.]+$}{};
    $dbfile =~ s{\.[^.]+$}{};
    $dbfile = $dbfile . "." . $time;
    ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp cp \'$olddbfile\' \'$target/_MGMTDB/DATAFILES/$dbfile.dbf\'");
    exit_error(1,"Cannot copy MGMTDB DBFiles to $target, exiting...") if ($rc);
  }  

  my $crsver = get_crs_version();
  my @ver = split(/\./, $crsver); 
  if ($ver[3] gt 1) { 
      my $clstname = get_cluster_name();
      trace("I","Copying MGMTDB $clstname PDB DBFiles to $target");   
      foreach (@pdbdatafileslocation) {
        $olddbfile = $_;
        $dbfile = basename($olddbfile);
        $dbfile =~ s{\.[^.]+$}{};
        $dbfile =~ s{\.[^.]+$}{};
        $dbfile = $dbfile . "." . $time;
        ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp cp \'$olddbfile\' \'$target/_MGMTDB/DATAFILES/$clstname/$dbfile.dbf\'");
        exit_error(1,"Cannot copy MGMTDB $clstname PDB DBFiles to $target, exiting...") if ($rc);
      }
  }

  trace("I","Creating the CTRL File");  
  my $conn = "/ as sysdba";
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);  
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$tmpfile
EOF'};
   if (grep (/ERROR/,$rc_string)) {
     trace("W","Unable to create CTRL File, due to error:\n $rc_string");
     my ($rc,@out) = system_cmd("$crshome/bin/srvctl stop mgmtdb");
     ($rc,@out) = system_cmd("$crshome/bin/srvctl start mgmtdb -n $hostname");
     trace("W","Cannot startup source MGMTDB!") if ($rc);
     ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp rm -fr $target/_MGMTDB");
     trace("W","Cannot remove target $target MGMTDB!") if ($rc);
     exit_error(1,"MGMTDB moves to $target failed, exiting...");        
   }  
  unlink $tmpfile;
  unlink $targetPFile;
  trace("I","The CTRL File has been created and MGMTDB is now running from $target");  
}

sub removeDBFile {
  my $asmsid = getasmsid();
  my $asmsetenv = racsetenv($crshome,$asmsid);
  my $source = shift @datafileslocation;
  my @path = split("/",$source);
  my $dg = $path[0];
  trace("I","Removing old MGMTDB");
  my ($rc,@out) = system_cmd_capture("$asmsetenv;$crshome/bin/asmcmd --nocp rm -fr $dg/_MGMTDB");
  exit_error(1,"Cannot remove old MGMTDB, exiting...") if ($rc);
  return;  
}

sub changeDependency {
  my $dg = $target;
  $dg =~ tr/+//d;
  
  trace("I","Changing START_DEPENDENCIES");
  my ($rc,@out) = system_cmd_capture("$crshome/bin/crsctl modify res ora.mgmtdb -attr \"START_DEPENDENCIES='hard(ora.MGMTLSNR,ora.$dg.dg) pullup(ora.MGMTLSNR,ora.$dg.dg) weak(global:type:ora.scan_listener.type, uniform:ora.ons)'\" -f -unsupported");
  trace("W","Cannot change START_DEPENDENCIES") if ($rc);
  
  trace("I","Changing STOP_DEPENDENCIES");
  ($rc,@out) = system_cmd_capture("$crshome/bin/crsctl modify res ora.mgmtdb -attr \"STOP_DEPENDENCIES='hard(intermediate:ora.MGMTLSNR, intermediate:ora.asm, shutdown:ora.$dg.dg)'\" -f -unsupported");
  trace("W","Cannot change STOP_DEPENDENCIES") if ($rc);
}

sub restartMDMTDB {
  trace("I","Restarting MGMTDB using target SPFile");  
  my $SQLfile="$tmp/mgmtdb_shutdown.sql"; 
  open(my $TEMP, '>', $SQLfile) or die "Could not open file '$SQLfile' $!";
  print $TEMP "set echo off;\n";
  print $TEMP "set feedback off;\n";
  print $TEMP "set pagesize 0;\n";
  print $TEMP "set linesize 32000;\n";  
  print $TEMP "WHENEVER SQLERROR EXIT SQL.SQLCODE;\n";
  print $TEMP "shutdown immediate;\n";
  print $TEMP "exit;\n";
  close($TEMP);
    
  my $dbsid = "-MGMTDB";
  my $setenv = racsetenv($crshome,$dbsid);
  my $conn = "/ as sysdba";
  my $rc_string = qx{$setenv;$crshome/bin/sqlplus -s $conn <<EOF
  \@$SQLfile
EOF'};
  exit_error(1,"Unable to stop MGMTDB, due to error:\n $rc_string, exiting...") if (grep (/ERROR/,$rc_string));  
  unlink $SQLfile; 
  system_cmd("$crshome/bin/srvctl start mgmtdb -n $hostname");
  my ($rc,@out) = system_cmd("$crshome/bin/crsctl stat res -t |grep -A 1 ora.mgmtdb|tail -n +2");
  trace("E","MGMTDB is not running $out[0] $out[1]") if (!grep (/Open,STABLE/,@out));  
}

# ================================================================


# Set sqlplus environment
# Usage: racsetenv($orahome, $sid)
sub racsetenv {
  my $orahome = $_[0];
  my $sid = defined $_[1]?$_[1]:"";
  if ($ENV{"SHELL"} eq "csh") {
    return "setenv ORACLE_SID $sid;setenv ORACLE_HOME $orahome";
  } else {
    return "export ORACLE_SID=$sid;export ORACLE_HOME=$orahome";
  }
}

sub getasmsid {
  my ($rc,@out) = system_cmd_capture("ps -eo args | grep -v grep | grep asm_pmon");
  exit_error(1,"ASM instance is not running, can not get pmon process of ASM instance, exiting...") if (! defined($out[1]));  
  my @asmsid = split("_",$out[1]); 
  return $asmsid[2];
}

# Argument: Null
# Return: spfile location
sub get_spfile{ 
  my ($rc,@out) = system_cmd_capture("$crshome/bin/srvctl config mgmtdb |grep Spfile");
  exit_error(1,"Cannot get SPFile location, exiting...") if ($rc);   
  my @spfile = split(":",$out[1]); 
  return my_trim_data($spfile[1]);
}

# Argument: Null
# Return: cluster name changing "-" to "_"
sub get_cluster_name { 
  my ($rc,@out) = system_cmd_capture("$crshome/bin/cemutlo -n");
  exit_error(1,"Cannot get cluster name, exiting...") if ($rc);    
  my $clstname = $out[1];
  $clstname =~ s/-/_/g;
  return $clstname;
}

# Argument: Null
# Return: active cluster version
sub get_crs_version { 
  my @ver  = (0, 0, 0, 0, 0);
  my $verstring;
  
  # run "crsctl query crs activeversion" -- stack must be up
  # Example output:
  # Oracle Grid Infrastructure active version on the cluster is [12.1.0.2.0]
  my ($rc,@out) = system_cmd_capture("$crshome/bin/crsctl query crs activeversion");
  exit_error(1,"Cannot get CRS version, Grid Infrastructure down?") if ($rc);
  
  # if succeeded, parse to ver numbers, output must be a single line,
  # version is 5 numbers, major to minor (see above)
  $verstring = $out[1];
  $verstring =~ m/\[?(\d*)\.(\d*)\.(\d*)\.(\d*)\.(\d*)\]?.*$/;
  @ver = ($1, $2, $3, $4, $5);
  $verstring = join('.',@ver);
  @ver = split(/\./, $verstring);
   
  #check version validity
  if (scalar(@ver) != 5) {
      die("Not a valid Grid Infrastructure version. The version obtained is @ver");
  }
  return $verstring ;
}

# Argument: Null
# Return: cluster home location
sub getCRSHomefromOLR 
{
  die "Cannot find olr location: $olrloc, is Oracle CRS installed?\n" unless ( -f $olrloc );
  my @olrfile = readfile($olrloc);
  my @tmp = grep /crs_home/, @olrfile;
  my $crshome = $tmp[0];
  $crshome =~ s/^.*(crs_home=)(.*)$/$2/;
  exit_error(1,"Cannot retrieve Cluster Home from OLR!") if (!$crshome);
  return $crshome;
}

sub getCRSNodelist
{
  my ($rc,@nodelist) = system_cmd_capture("$crshome/bin/olsnodes");
  exit_error(1,"Cannot Retrieve Cluster Node List, Grid Infrastructure down?") if ($rc);
  return @nodelist;
}

# Arguments: Null
# Return: cluster home location
sub getCRSHomefromInventory
{
   my $crshome;
   my $invloc=getCentralInvLocation();
   my @invfile=readfile("$invloc/ContentsXML/inventory.xml");
   my @tmp = grep /LOC=.*CRS=\"true\"/, @invfile;
   if ( defined($tmp[0]) ) {
    $crshome = $tmp[0];
    $crshome =~ s/^<.*(LOC=\")(.*)(\".*TYPE).*>$/$2/;      
   } else {die ("Cannot retrieve crshome from central inventory! \n");}  
   return $crshome;
}

# Arguments: Null
# Return: central inventory location
sub getCentralInvLocation
{
   my (@orainstfile,@tmp,@invline,$inv_loc);
   @orainstfile=readfile($orainstloc);
   @tmp = grep /inventory_loc/, @orainstfile;
   if ( defined($tmp[0]) ) {
    @invline = split /=/, $tmp[0];
    $inv_loc = $invline[1];
    chomp $inv_loc;
   } else {die ("Cannot retrieve inventory location from $orainstloc! \n");} 
   return $inv_loc;
}

# Arguments: file location
# Return: file content 
sub readfile
{
  my ($in_file, $line, @a);
  $in_file = shift; 
  open(ARRAYFILE, "< $in_file") or die("Cannot open $in_file! \n");
  while ( defined ($line = <ARRAYFILE>)) {
    chomp ($line);
    push @a, $line; 
  };
  close(ARRAYFILE);
  return @a;
}



sub trace
{
  my @msg = @_;
  my ($sec, $min, $hour, $day, $month, $year) = (localtime) [0, 1, 2, 3, 4, 5];
  $month = $month + 1;
  $year  = $year + 1900;
  open (TRCFILE, ">>", "/tmp/mdbutil.trc")
    or die "Cant open trace file: /tmp/mdbutil.trc";
  printf TRCFILE  "%04d-%02d-%02d %02d:%02d:%02d: @msg\n", $year, $month, $day, $hour, $min, $sec;
  close (TRCFILE);

  if ( 'root' eq getpwuid( $< )) {
    chmod(0666,"/tmp/mdbutil.trc");
  }
  
  if ($msg[0] eq 'I') 
  {
    printf "%04d-%02d-%02d %02d:%02d:%02d: ", $year, $month, $day, $hour, $min, $sec;
    print color 'bold blue';
    printf "$msg[0] ";
    print color 'reset';
    printf "$msg[1]\n";
  }
  elsif ($msg[0] eq 'W') {
    printf "%04d-%02d-%02d %02d:%02d:%02d: ", $year, $month, $day, $hour, $min, $sec;
    print color 'bold yellow';
    printf "$msg[0] ";
    print color 'reset';
    printf "$msg[1]\n";
  }  
  elsif ($msg[0] eq 'E') {
    printf "%04d-%02d-%02d %02d:%02d:%02d: ", $year, $month, $day, $hour, $min, $sec;
    print color 'bold red';
    printf "$msg[0] ";
    print color 'reset';
    printf "$msg[1]\n";
  }
  elsif ($msg[0] eq 'D') {
    printf "%04d-%02d-%02d %02d:%02d:%02d: ", $year, $month, $day, $hour, $min, $sec;
    print color 'bold magenta';
    printf "$msg[0] ";
    print color 'reset';
    printf "$msg[1]\n";
  }
}

# Arguments: command to be executed
# Return: return_value, command output
sub system_cmd_capture {
  my $rc  = 0;
  my $prc = 0;
  my @output;

  if (defined $debug) {
    trace("D","Executing: @_");
  }
    
  push @output, "Executing cmd: @_";

  if (!open(CMD, "@_ 2>&1 |")) { $rc = -1; }
  else {
    push @output, (<CMD>);
    close CMD;
    # the code return must be after the close
    $prc = $CHILD_ERROR >> 8; # get program return code right away
    chomp(@output);
  }
  if ( $rc == -1 ) {
    push @output, "Cannot execute @_ \n";
  } 
  else { 
    $rc = $prc;
  }
  close CMD;
  if (defined $debug) {
    trace("D","Exit code: $rc");
    trace("D","Output of last command execution: ");
    if (defined $output[1]){
      print("$output[1]\n");
    }
  }
  return ($rc, @output);
}

# Arguments: command to be executed
# Return: command output
sub system_cmd {
  my ($rc, @output) = system_cmd_capture(@_);
  return @output;
}

sub copy_file {
  my $src = $_[0];
  my $dst = $_[1];
  my $usr = $_[2];
  my $grp = $_[3];

  if (! (-f $src)) {
    exit_error(1,"Source file $src not exist!");
  }
  if (! copy( $src, $dst ))
  {
    exit_error(1,"Failed to copy file from $src to $dst!");
  }
  # chown to specific user if requested
  if (defined( $usr ) && defined( $grp ))
  {
    my $uid = getpwnam ($usr);
    my $gid = getgrnam ($grp);

    if (! chown ($uid, $gid, $dst)) {
      exit_error(1, "Can't change ownership of $dst: $!");
    }
  }
}

sub my_trim_data
{
  my ($data) = @_;
  chomp($data);
  $data =~ s/(\s*)$//;
  $data =~ s/^(\s*)//;
  return $data;
}

sub exit_error {
   my $rc=$_[0];
   my $out=$_[1];
   trace("E","$out");
   exit $rc;
}
__END__
# ======================================================================
# EndOfFile
# ======================================================================
