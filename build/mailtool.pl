#!/usr/bin/env perl
#
#

use strict;
use warnings;
use MIME::Lite;
use Encode;
use DBI;
use Text::Wrap;
use Text::CSV;
use URI::Escape;
use open ':encoding(UTF-8)';

no warnings 'redundant';

binmode STDOUT, ":utf8";

$Text::Wrap::columns = 73;
$Text::Wrap::huge = "overflow";

# General configuration
my $BASE = "/usr/src/app";
my $MsmtpAccount = "default";
#my $HtmlFilter = "LC_ALL=C lynx -dump";
my $HtmlFilter = "LC_ALL=en_GB.utf8 lynx -display_charset=utf8 -dump";
my $HtmlFetch = "LC_ALL=C curl -s ";

# For list processors
my $L = { };


# Job config
if ($#ARGV < 0) {
	print("$0: please specify job name\n\n  usage: $0 job-name [--commit] [--no-sanity]\n\n");
	exit(1);
}

my $ConfFile = $ARGV[0].".mtc";

open(CONF, $ConfFile) or die("Cannot read configuration file: $ConfFile\n");

# different list sources
my $RcptList = "";	### Regular list (tab-separated values)
my $RcptCsv = "";	### Regular list (CSV)
my $RcptQuery = "";	### MySQL query
my $DB = "";		#    database
my $DBUser = "";	#    username
my $DBPassword = "";	#    password
my $PDFDir = "";	### Read from PDF files in directory
my $PDFFields = "";	#    field list
my $SubQuery = "";	#    additional query to DB (after reading main list)

# config variables for all sources
my @file_list;
my @htmlattach_list;
my $IncludeDir = "";
my $BodyFile = "";
my $BodyEncoding = "UTF-8";
my $Subject = "";

# CSV parser
my $csv = Text::CSV->new({ sep_char => ',', binary => 1, auto_diag => 1, diag_verbose => 2  });

# default names unless changed
my $FieldEmail = "email";
my $FieldId = "id";
my $FieldCc = "cc";

# default values - can be overwritten
my $EnvFrom = 'newsletter@eqar.eu';
my $FromName = "EQAR newsletter";
my $ReplyTo;
my $Bcc;

while(<CONF>) {
	chomp;

	if (/^([^\#]\w*)\t+([^\t]+)(\t+([^\t]+))?/) {	# valid line
		if ($1 eq "RcptList") {
			$RcptList = $2;
		} elsif ($1 eq "RcptCsv") {
			$RcptCsv = $2;
		} elsif ($1 eq "RcptQuery") {
			$RcptQuery = $2;
		} elsif ($1 eq "DB") {
			$DB = $2;
		} elsif ($1 eq "DBUser") {
			$DBUser = $2;
		} elsif ($1 eq "DBPassword") {
			$DBPassword = $2;
		} elsif ($1 eq "PDFDir") {
			$PDFDir = $2;
		} elsif ($1 eq "PDFFields") {
			$PDFFields = $2;
		} elsif ($1 eq "SubQuery") {
			$SubQuery = $2;
		} elsif ($1 eq "IncludeDir") {
			$IncludeDir = $2;
		} elsif ($1 eq "BodyFile") {
			$BodyFile = $2;
		} elsif ($1 eq "BodyEncoding") {
			$BodyEncoding = $2;
		} elsif ($1 eq "Subject") {
			$Subject = $2;
		} elsif ($1 eq "FieldEmail") {
			$FieldEmail = $2;
		} elsif ($1 eq "FieldId") {
			$FieldId = $2;
		} elsif ($1 eq "FieldCc") {
			$FieldCc = $2;
		} elsif ($1 eq "From") {
			$EnvFrom = $2;
		} elsif ($1 eq "FromName") {
			$FromName = $2;
		} elsif ($1 eq "ReplyTo") {
			$ReplyTo = $2;
		} elsif ($1 eq "Bcc") {
			$Bcc = $2;
		} elsif ($1 eq "Attach") {
			push(@file_list, { File => $4, Type => $2 } );
		} elsif ($1 eq "HtmlAttach") {
			push(@htmlattach_list, { File => $4, Type => $2 } );
		} else {
			print("unknown configuration variable: $1\n");
		}
	}
}
close(CONF);

if ($BodyFile eq "") {	# default name
	$BodyFile = ($BodyEncoding eq "HTML") ? $ARGV[0].".html" : $ARGV[0].".txt";
}

if ($RcptList =~ /^\./) {	# starts with a dot -> add to default name
	$RcptList = $ARGV[0].$RcptList;
}
if ($RcptCsv =~ /^\./) {	# starts with a dot -> add to default name
	$RcptCsv = $ARGV[0].$RcptCsv;
}

# Full From header
my $From = encode("MIME-Q",$FromName).' <'.$EnvFrom.'>';
# Special options for running on Netgear ReadyNAS
MIME::Lite->send("sendmail", "/usr/bin/msmtp -f $EnvFrom -a $MsmtpAccount -t -oi -oem");

print("Configuration read:\n * From: $From - Bcc: $Bcc\n * Read body from $BodyFile (Subject: $Subject)\n * Attach from $IncludeDir:\n");

foreach (@file_list) {
	# Parse filename
	print("   ".$_->{'File'}." (".$_->{'Type'}.")\n");
}

if ( ( ($RcptList eq "") && ($RcptCsv eq "") && ($RcptQuery eq "") && ($PDFDir eq "") ) || ($BodyFile eq "") || ($Subject eq "") ) {
	print("Warning: not all mandatory parameters specified!\n");
}
if ( ($#file_list > -1) && ($IncludeDir eq "") ) {
	print("Warning: attachments specified, but no include directory!\n");
}
if ( ($#htmlattach_list > -1) && ($BodyEncoding ne "HTML") ) {
	print("Warning: HTML-message attachments specified, but type is not HTML - will be skipped.\n");
}

if ($RcptList ne "") {
	print(" * Recipients read from $RcptList (tab-separated)\n");
	if ($RcptQuery ne "") {
		print(" ! RcptQuery also specified, will be ignored.\n");
	}
} elsif ($RcptCsv ne "") {
	print(" * Recipients read from $RcptCsv (CSV)\n");
} elsif ($RcptQuery ne "") {
	if ( ($DB eq "") || ($DBUser eq "") ) {
		die(" ! DB and DBUser need to be specified when using RcptQuery - exiting.\n");
	}
	if ( $DBPassword eq "" ) {
		print(" ! DBPassword is empty.\n");
	}
	print(" * Recipients from ".$DBUser."@".$DB." with query '$RcptQuery'\n");
} elsif ($PDFDir ne "") {
	if ( $PDFFields eq "" ) {
		die(" ! You have to specify the fields.\n");
	}
	print(" * Recipients from PDF files in $PDFDir as\n   [*$PDFFields*]\n");
}
if ( ($SubQuery ne "") && ( ($DB eq "") || ($DBUser eq "") ) ) {
	die(" ! DB and DBUser need to be specified when using SubQuery - exiting.\n");
}


########################################################################

##my ($id, $org, $name, $email);	# values to read from list
##my $cc = '';

# Read template mailbody from file
open(BODY, $BodyFile) or die("Cannot read mail body template: $BodyFile\n");
my @Body = <BODY>;
my $mailbody = join('',@Body);
close(BODY);

######## INIT DATA SOURCE ###########

my $dbh;	# DB connection
my $sth;	# statement
my @Fields;	# Field list (general)
my @Files;	# for PDF handler
my $RCPT;	# file handle

if ( ($SubQuery ne "") || ($RcptQuery ne "") ) {
	$dbh = DBI->connect($DB, $DBUser, $DBPassword, { } )
		or die("Cannot connect to database: ".$DBI::errstr."\n");
}

if ($RcptList ne "") {
	# Open recipient list
	open($RCPT, $RcptList)
		or die("Cannot read recipient list: $RcptList\n");

	$_ = <$RCPT>;		# read first line (field names)
	chomp;			# remove trailing NL
	s/\r+$//;		# remove trailing CR
	@Fields = split(/\t/);

} elsif ($RcptCsv ne "") {
	# Open recipient list
	open($RCPT, $RcptCsv)
		or die("Cannot read recipient list: $RcptList\n");

	@Fields = @{$csv->getline($RCPT)};

} elsif ($RcptQuery ne "") {

	$sth = $dbh->prepare($RcptQuery);

	$sth->execute()
		or die("Cannot execute query: ".$DBI::errstr."\n");

	print(" * SQL query returned ".$sth->rows." rows.\n");

	@Fields = @{$sth->{NAME}};

} elsif ($PDFDir ne "") {

	@Fields = split(/\|/, $PDFFields);
	
	opendir(my $DIR, $PDFDir) || die("Cannot open directory: $PDFDir\n");
	
	@Files = sort( grep { /^[^\.].*\.pdf$/ } readdir($DIR) );

	closedir($DIR);
	
	print(" * Found ".($#Files + 1 )." PDF files (*.pdf)\n");

} else {

	die("No main recipient list specified - exiting.\n");

}

print(" * Merge fields:");

foreach (@Fields) {
	chomp;
	print(" {".$_."}");
}

print(" * Subquery: $SubQuery\n") if ($SubQuery ne "");

# switches
my $sanityCheck = 1;
my $commit = ($ARGV[1] ? ($ARGV[1] eq "--commit") : undef);
my $debug = ($ARGV[1] ? ($ARGV[1] eq "--debug") : undef);

if ($commit) {
	print("\n\n-- COMMIT MODE, will send emails! Continue? ");
	$_ = <STDIN>; unless(/^[yY]/) { exit(1) };
} else {
	print("\n\n-- dry-run, won't send any emails --------------------------------------\n");
}

if ($debug) {
	print("\n\n-- DEBUG mode, will dump emails ----------------------------------------\n");
}

######## MAIN LOOP ###########
my $lineNumber = 0;

while ( ($RcptList ne "") ? ($_ = <$RCPT>) : ( ( $RcptCsv ne "" ? (my $csvline = $csv->getline($RCPT)) : ($PDFDir ne "" ) ? (my $file = shift(@Files) ) : (my $row = $sth->fetchrow_hashref()) ) ) ) {
	
	$lineNumber++;

	print("*- line: $lineNumber -*\n") if ($debug);

	my %Data;
	
	if ($RcptList ne "") {
		# read one record (tab-separated values)
		chomp;
		s/\r+$//;

		if (/###END###/) {
			die("Record ###END### found - quitting.\n");
		}

		next if (/^#/);

		my @DataArray;
		@DataArray = split(/\t/);

		for(my $i=0;$i<=$#Fields;$i++) {
			if ($DataArray[$i]) {
				$Data{$Fields[$i]} = $DataArray[$i];
			} else {
				$Data{$Fields[$i]} = "";
			}
		}
		
	} elsif ($RcptCsv ne "") {

		for(my $i=0;$i<=$#Fields;$i++) {
			if( $csvline->[$i]) {
				$Data{$Fields[$i]} = $csvline->[$i];
			} else {
				$Data{$Fields[$i]} = "";
			}
		}

	} elsif ($RcptQuery ne "") {
	
		my $key;
		
		foreach $key (keys(%$row)) {
			if ($row->{$key}) {
				$Data{$key} = $row->{$key};
			} else {
				$Data{$key} = "";
			}
		}
		
	} elsif ($PDFDir ne "") {
	
		open(PDF, "pdftotext -raw $PDFDir/$file - |");

		my @InputLines = <PDF>;
		my $rawInput = join("", @InputLines);
		$rawInput =~ s/\n/ /g;
		
		close(PDF);
		
		if ($rawInput =~ /\[\*([^\*]+)\*\]/) {
			my @DataArray;
			@DataArray = split(/\|/, $1);

			for(my $i=0;$i<=$#Fields;$i++) {
				if ($DataArray[$i]) {
					$Data{$Fields[$i]} = $DataArray[$i];
				} else {
					$Data{$Fields[$i]} = "";
				}
			}
		} else {
			print("   !!! cannot find [*...*] line in $file\n");
			next;
		}

	}
	
	if ($debug) {	# in debug mode, print all fields
		print "  Fields from main source:\n";
		foreach (@Fields) {
			print("   {$_} = ".$Data{$_}."\n");
		}
	}

	if ($SubQuery ne "") {
		my $parsedQuery = $SubQuery;
		$parsedQuery =~ s/\{([^\}]+)\}/$Data{$1}/g;

		if ($debug) {
			print("Subquery: ".$parsedQuery."\n");
		}

		$sth = $dbh->prepare($parsedQuery);

		$sth->execute()
			or print("   !!! Could not execute query.\n       Query=".$parsedQuery."\n       Error=".$DBI::errstr."\n");

		if ($sth->rows == 0) {
			print("   !!! SQL query returned no rows.\n");
		} elsif ($sth->rows gt 1) {
			print("   !!! SQL query returned  ".$sth->rows." rows - everything but first row will be discarded.\n");
		}

		if (my $row = $sth->fetchrow_hashref()) {
			print("  Fields from subquery:\n") if ($debug);
			foreach (keys(%$row)) {
				unless (grep(/^$_$/, @Fields)) {
					push(@Fields, $_);
				}
				if ($row->{$_}) {
					$Data{$_} = $row->{$_};
				} else {
					$Data{$_} = "";
				}
				print("   {$_} = ".$Data{$_}."\n") if ($debug);
			}
		}
	}

	my $email = $Data{$FieldEmail};
	my $cc = $Data{$FieldCc};
	my $id = $Data{$FieldId};

	unless ($id) {
		$id = $lineNumber - 1;
	}

	# log record ID
	print("\n-> $id:\n");

	if ($cc ne "" && ! $email) {
		print("[Cc used as To] ");
		$email = $cc;
		$cc = undef;
	}
	
	if ($email && ( (! $sanityCheck) || checkEmail($email) ) ) {
		# sanity check email
		if ($sanityCheck) {
			#if ($id == 0 && $id ne "0") {
			#	print("   !!! id '$id' does not seem to be a number\n");
			#}
			if ($cc) {
				$cc = undef unless (checkEmail($cc));
			}
		}

		print("   To: $email");

		if ($cc) {
			print(" / Cc: $cc\n");
		} else {
			print("\n");
		}
		
		foreach (@Fields) {
			if (! $Data{$_}) {	# not set
				print("   !!! field '$_' is not set\n");
			}
		}

		my $parsedSubject = $Subject;	# parsed Subject
		my $msg;			# this will always hold the full message

		$parsedSubject =~ s/\{([^\}]+)\}/$Data{$1}/g;
		
		print "   Subject: $parsedSubject\n";

		$msg = MIME::Lite->new( 
			From		=> $From,
			To		=> $email,
			Cc		=> $cc,
			Bcc		=> $Bcc,
			#'Reply-To'	=> $ReplyTo,
			#'Precedence:'	=> 'bulk',
			#'List-Unsubscribe:' => '<mailto:'.$EnvFrom.'?subject=Unsubscribe>',
			Subject		=> $parsedSubject,
			Type		=> 'multipart/mixed',
			Encoding	=> '7bit'
			); 
				
		# Create new multipart message
		if ($BodyEncoding eq "HTML") {
			my $part = MIME::Lite->new( 
				Type		=> 'multipart/alternative',
				Encoding	=> '7bit'
				); 

			# Parse HTML body
			my $parsedbody = $mailbody;
			$parsedbody =~ s/(\<\!\-\-)?\{([^\}]+)\}(\-\-\>)?/$Data{$2}/g;
			$parsedbody =~ s/\*\*\+([^\+]+)\+\*\*/uri_escape($Data{$1})/ge;

			# check for request to include external data
			if ($parsedbody =~ /\<\!\-\-INCLUDE\|([^\|]*)\|([^\|]*)\|([^\|]*)\|\-\-\>/) {
				my $url = $1;
				my $mark_begin = $2;
				my $mark_end = $3;

				$url =~ s/\{([^\}]+)\}/$Data{$1}/g;

				print "   <-- $url\n";

				open(INCLUDE, $HtmlFetch." \"$url\" | iconv -f iso8859-1 -t utf-8 |");
				my @IncludeRaw = <INCLUDE>;
				my $include = join('', @IncludeRaw);
				close(INCLUDE);

				my $pos_begin = index($include, $mark_begin);
				my $pos_end = index($include, $mark_end, $pos_begin);
				my $include_part = substr($include, $pos_begin, $pos_end - $pos_begin);
				
				$parsedbody =~ s/\<\!\-\-INCLUDE\|[^\|]*\|[^\|]*\|[^\|]*\|\-\-\>/$include_part/;

			}
			
			# fix img src attribute
			$parsedbody =~ s/src\=\"([^\"]+)\"/src\=\"cid:image_$1\"/ig;

			# convert HTML to plain text
			open(HTMLTEXT, "> /tmp/mailtool_$BodyFile");
			print HTMLTEXT $parsedbody;
			close(HTMLTEXT);
	
			my $txtbody = "";
			# filter HTML to plain text
			open(PLAINTEXT, $HtmlFilter." /tmp/mailtool_".$BodyFile." |");
			while(<PLAINTEXT>) {
				$txtbody = $txtbody . $_;
			}
			close(PLAINTEXT);	

			my $txtpart = MIME::Lite->new(
				Type		=> 'text/plain',
				Encoding	=> 'quoted-printable', 
				Data		=> encode('UTF-8', $txtbody)
				);
				
			$txtpart->attr('content-type.charset' => 'UTF-8');

			$part->attach($txtpart);

			my $htmlpart = MIME::Lite->new(
				Type		=> 'multipart/related',
				Encoding	=> '7bit'
				);

			my $htmlbody = MIME::Lite->new(
				Type		=> 'text/html',
				Encoding	=> 'quoted-printable',
				Data		=> encode('UTF-8', $parsedbody)
				);
				
			$htmlbody->attr('content-type.charset' => 'UTF-8');

			$htmlpart->attach($htmlbody);

			foreach (@htmlattach_list) {
				my $file = $_->{'File'};
				my $file_base = substr($file,rindex($file,'/')+1);
				
				if (-r $IncludeDir.$file) {
					print("   + $file. [".$_->{'Type'}."]\n") if $commit;
				} else {
					print("   !!! file '$file' not readable (dir: $IncludeDir)\n") if $sanityCheck;
				}

				# create part
				my $htmlattach = MIME::Lite->new(
						Type 		=> $_->{'Type'},
						Path		=> $IncludeDir.$file,
						Filename	=> $file_base,
						Id		=> "<image_".$file_base.">"
						);

				# attach it to the message
				$htmlpart->attach($htmlattach);
			}
		
			$part->attach($htmlpart);

			$msg->attach($part);

			if ($debug) {
				$msg->print();
			}
		
		} else {
			# Parse text
			my $parsedbody = $mailbody;
			$parsedbody =~ s/\{([^\%\}]+)(\%[^\}]+)\}/sprintf($2, $Data{$1})/ge;
			$parsedbody =~ s/\{([^\}]+)\}/$Data{$1}/g;
			$parsedbody =~ s/\*\*\+([^\+]+)\+\*\*/uri_escape($Data{$1})/ge;
			$parsedbody = wrap('', '', $parsedbody);

			# Text body
			my $part = MIME::Lite->new(
				Type		=> 'TEXT',
				Encoding	=> 'quoted-printable', 
				Data		=> encode("utf8",$parsedbody)
				);

			$part->attr('content-type.charset' => $BodyEncoding);
		
			$msg->attach($part);
			
			if ($debug) {
				$msg->print();
			}
		
		}
		

		foreach (@file_list) {
			# Parse filename
			my $file = sprintf($_->{'File'}, $id);
			
			if (-r $IncludeDir.$file) {
				print("   + $file. [".$_->{'Type'}."]\n") if $commit;
			} else {
				print("   !!! file '$file' not readable (dir: $IncludeDir)\n") if $sanityCheck;
			}

			# create part
			my $part = MIME::Lite->new(
					Type 		=> $_->{'Type'},
					Path		=> $IncludeDir.$file,
					Filename	=> substr($file,rindex($file,'/')+1) );

			# attach it to the message
			$msg->attach($part);
		}

		if ($commit) {
			print("   > Sending...");
			$msg->send; 
			print("Done.\n");
		}
		
	} else {

		print("   !!! no email address - skipping.\n");
	}

}

if ( ($RcptList ne "") || ($RcptCsv ne "") ) {
	close($RCPT);
}

# remove temporary file
unlink(" /tmp/mailtool_".$BodyFile);

### sanity check
sub checkEmail {
	my $text = shift(@_);

	if ($text =~ /^\s*$/) {
		print "   --- '$text' is empty or consisting of whitespace only\n";
		return(0);
	}
	if ($text =~ /^([^@,]+@[^@,]+)?(,[^@,]+@[^@,]+)*\,?$/) {
		return(1);
	} else {
		print "   !!! '$text' does not seem to be a valid email address\n";
		return(0);
	}
}

