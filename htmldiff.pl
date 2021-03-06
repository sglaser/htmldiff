#!/usr/bin/perl
#
# htmldiff - present a diff marked version of two html documents
#
# Copyright (c) 1998-2006 MACS, Inc.
#
# Copyright (c) 2007-2015 SiSco, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# See http://www.themacs.com for more information.
#
# usage: htmldiff [[-c] [-l] [-o] [-t] oldversion newversion [output]]
#
# -c - disable metahtml comment processing
# -o - disable outputting of old text
# -l - use navindex to create sequence of diffs
# -t - allow display of previous content
#
# oldversion - the previous version of the document
# newversion - the newer version of the document
# output - a filename to place the output in. If omitted, the output goes to
#          standard output.
#
# if invoked with no options or arguments, operates as a CGI script. It then
# takes the following parameters:
#
# oldfile - the URL of the original file
# newfile - the URL of the new file
# mhtml - a flag to indicate whether it should be aware of MetaHTML comments.
#
# requires GNU diff utility
# also requires the perl modules Getopt::Std
#
# NOTE: The markup created by htmldiff may not validate against the HTML 4.0
# DTD. This is because the algorithm is realtively simple, and there are
# places in the markup content model where the span element is not allowed.
# Htmldiff is NOT aware of these places.
#
#

use Getopt::Std;

sub usage {
	print STDERR "htmldiff [-c] [-o] oldversion newversion [output]\n";
	exit;
}

sub url_encode {
    my $str = shift;
    $str =~ s/([\x00-\x1f\x7F-\xFF])/
                 sprintf ('%%%02x', ord ($1))/eg;
    return $str;
}

# markit - diff-mark the streams
#
# markit(file1, file2)
#
# markit relies upon GNUdiff to mark up the text.
#
# The markup is encoded using special control sequences:
#
#   a block wrapped in control-a is deleted text
#   a block wrapped in control-b is old text
#   a block wrapped in control-c is new text
#
# The main processing loop attempts to wrap the text blocks in appropriate
# SPANs based upon the type of text that it is.
#
# When the loop encounters a < in the text, it stops the span. Then it outputs
# the element that is defined, then it restarts the span.

sub markit {
	my $retval = "";
	my($file1) = shift;
	my($file2) = shift;
#	my $old="<span class=\\\"diff-old-a\\\">deleted text: </span>%c'\012'%c'\001'%c'\012'%<%c'\012'%c'\001'%c'\012'";
	my $old="%c'\012'%c'\001'%c'\012'%<%c'\012'%c'\001'%c'\012'";
	my $new="%c'\012'%c'\003'%c'\012'%>%c'\012'%c'\003'%c'\012'";
	my $unchanged="%=";
	my $changed="%c'\012'%c'\001'%c'\012'%<%c'\012'%c'\001'%c'\012'%c'\004'%c'\012'%>%c'\012'%c'\004'%c'\012'";
	if ($opt_o) {
		$old = "";
		$changed = "%c'\012'%c'\004'%c'\012'%>%c'\012'%c'\004'%c'\012'";
	}
#	my $old="%c'\002'<font color=\\\"purple\\\" size=\\\"-2\\\">deleted text:</font><s>%c'\012'%c'\001'%c'\012'%<%c'\012'%c'\001'%c'\012'</s>%c'\012'%c'\002'";
#	my $new="%c'\002'<font color=\\\"purple\\\"><u>%c'\012'%c'\002'%>%c'\002'</u></font>%c'\002'%c'\012'";
#	my $unchanged="%=";
#	my $changed="%c'\002'<s>%c'\012'%c'\001'%c'\012'%<%c'\012'%c'\001'%c'\012'</s><font color=\\\"purple\\\"><u>%c'\002'%c'\012'%>%c'\012'%c'\002'</u></font>%c'\002'%c'\012'";

	my @span;
	$span[0]="</span>";
	$span[1]="<del class=\"diff-old\">";
	$span[2]="<del class=\"diff-old\">";
	$span[3]="<ins class=\"diff-new\">";
	$span[4]="<ins class=\"diff-chg\">";
	
	my @diffEnd ;
	$diffEnd[1] = '</del>';
	$diffEnd[2] = '</del>';
	$diffEnd[3] = '</ins>';
	$diffEnd[4] = '</ins>';

	my $diffcounter = 0;

	open(FILE, qq(diff -d --old-group-format="$old" --new-group-format="$new" --changed-group-format="$changed" --unchanged-group-format="$unchanged" $file1 $file2 |)) || die("Diff failed: $!");
#	system (qq(diff --old-group-format="$old" --new-group-format="$new" --changed-group-format="$changed" --unchanged-group-format="$unchanged" $file1 $file2 > /tmp/output));

	my $state = 0;
	my $inblock = 0;
	my $temp = "";
	my $lineCount = 0;

# strategy: 
#
# process the output of diff...
#
# a link with control A-D means the start/end of the corresponding ordinal
# state (1-4). Resting state is state 0.
#
# While in a state, accumulate the contents for that state. When exiting the
# state, determine if it is appropriate to emit the contents with markup or
# not (basically, if the accumulated buffer contains only empty lines or lines
# with markup, then we don't want to emit the wrappers.  We don't need them.
#
# Note that if there is markup in the "old" block, that markup is silently
# removed.  It isn't really that interesting, and it messes up the output
# something fierce.

	while (<FILE>) {
		my $anchor = $opt_l ? qq[<a tabindex="$diffcounter">] : "" ;
		my $anchorEnd = $opt_l ? q[</a>] : "" ;
		$lineCount ++;
		if ($state == 0) {	# if we are resting and we find a marker, 
							# then we must be entering a block
			if (m/^([\001-\004])/) {
				$state = ord($1);
				$_ = "";
			}
#			if (m/^\001/) {
#				$state = 1;
#				s/^/$span[1]/;
#			} elsif (m/^\002/) {
#				$state = 2;
#				s/^/$span[2]/;
#			} elsif (m/^\003/) {
#				$state = 3;
#				s/^/$span[3]/;
#			} elsif (m/^\004/) {
#				$state = 4;
#				s/^/$span[4]/;
#			}
		} else {
			# if we are in "old" state, remove markup
			if (($state == 1) || ($state == 2)) {
				s/\<.*\>//;	# get rid of any old markup
				s/\</&lt;/g; # escape any remaining STAG or ETAGs
				s/\>/&gt;/g;
			}
			# if we found another marker, we must be exiting the state
			if (m/^([\001-\004])/) {
				if ($temp ne "") {
					$_ = $span[$state] . $anchor . $temp . $anchorEnd . $diffEnd[$state] . "\n";
					$temp = "";
				} else {
					$_ = "" ;
				}
				$state = 0;
			} elsif (m/^\s*\</) { # otherwise, is this line markup?
				# if it is markup AND we haven't seen anything else yet,
				# then we will emit the markup
				if ($temp eq "") {
					$retval .= $_;
					$_ = "";
				} else {	# we wrap it with the state switches and hold it
					s/^/$anchorEnd$diffEnd[$state]/;
					s/$/$span[$state]$anchor/;
					$temp .= $_;
					$_ = "";
				}
			} else {
				if (m/.+/) {
					$temp .= $_;
					$_ = "";
				}
			}
		}

		s/\001//g;
		s/\002//g;
		s/\003//g;
		s/\004//g;
		if ($_ !~ m/^$/) {
			$retval .= $_;
		}
		$diffcounter++;
	}
	close FILE;
	$retval =~ s/$span[1]\n+$diffEnd[1]//g;
	$retval =~ s/$span[2]\n+$diffEnd[2]//g;
	$retval =~ s/$span[3]\n+$diffEnd[3]//g;
	$retval =~ s/$span[4]\n+$diffEnd[4]//g;
	$retval =~ s/$span[1]\n*$//g;
	$retval =~ s/$span[2]\n*$//g;
	$retval =~ s/$span[3]\n*$//g;
	$retval =~ s/$span[4]\n*$//g;
	return $retval;
}

sub splitit {
	my $filename = shift;
	my $headertmp = shift;
	my $inheader=0;
	my $preformatted=0;
	my $inelement=0;
	my $retval = "";
	my $styles = q(<style type='text/css'>
.diff-old-a {
  font-size: smaller;
  color: red;
}

.diff-new { background-color: yellow; }
.diff-chg { background-color: lime; }
.diff-new:before,
.diff-new:after
    { content: "\2191" }
.diff-chg:before, .diff-chg:after
    { content: "\2195" }
.diff-old { text-decoration: line-through; background-color: #FBB; }
.diff-old:before,
.diff-old:after
    { content: "\2193" }
:focus { border: thin red solid}
</style>
);
	if ($opt_t) {
		$styles .= q(
<script type="text/javascript">
<!--
function setOldDisplay() {
	for ( var s = 0; s < document.styleSheets.length; s++ ) {
		var css = document.styleSheets[s];
		var mydata ;
		try { mydata = css.cssRules ;
		if ( ! mydata ) mydata = css.rules;
		for ( var r = 0; r < mydata.length; r++ ) {
			if ( mydata[r].selectorText == '.diff-old' ) {
				mydata[r].style.display = ( mydata[r].style.display == '' ) ? 'none'
: '';
				return;
			}
		} 
		} catch(e) {} ;
	}
}
-->
</script>
);

	}
	
	if ($stripheader) {
		open(HEADER, ">$headertmp");
	}

	my $incomment = 0;
	my $inhead = 1;
	open(FILE, $filename) || die("File $filename cannot be opened: $!");
	while (<FILE>) {
		if ($inhead == 1) {
			if (m/(.*)\<\/head/i) {
                print HEADER $1 ;
				print HEADER $styles;
                print HEADER "</head>\n";
                # strip off everything - we have printed it
                s/.*<\/head>//i
			}
			if (m/(\<body.*?>)/i) {
				$inhead = 0;
				print HEADER $1;
                print HEADER "\n";
				if ($opt_t) {
					print HEADER q(
<form action=""><input type="button" onclick="setOldDisplay()" value="Show/Hide Old Content" /></form>
);
				}
				close HEADER;
                s/<body.*?>//i;
			} else {
				print HEADER;
			}
		}

        if (!$inhead) {
			if ($incomment) {
				if (m;-->;) {
					$incomment = 0;
					s/.*-->//;
				} else {
					next;
				}
			}
			if (m;<!--;) {
				while (m;<!--.*-->;) {
					s/<!--.*?-->//;
				}
				if (m;<!--; ) {
					$incomment = 1;
					s/<!--.*//;
				}
			}
			if (m/\<pre/i) {
				$preformatted = 1;
			}
			if (m/\<\/pre\>/i) {
				$preformatted = 0;
			}
			if ($preformatted) {
				$retval .= $_;
			} elsif ($mhtmlcomments && /^;;;/) {
				$retval .= $_;
			} else {
				my @list = split(' ');
				foreach $element (@list) {
					if ($element =~ m/\<H[1-6]/i) {
#						$inheader = 1;
					}
					if ($inheader == 0) {
						$element =~ s/</\n</g;
						$element =~ s/^\n//;
						$element =~ s/>/>\n/g;
						$element =~ s/\n$//;
						$element =~ s/>\n([.,:!]+)/>$1/g;
					}
					if ($element =~ m/\<\/H[1-6]\>/i) {
						$inheader = 0;
					}
					$retval .= "$element";
					$inelement += ($element =~ s/</&lt;/g);
					$inelement -= ($element =~ s/>/&gt;/g);
					if ($inelement < 0) {
						$inelement = 0;
					}
					if (($inelement == 0) && ($inheader == 0)) {
						$retval .= "\n";
					} else {
						$retval .= " ";
					}
				}
			undef @list;
			}
		}
	}
	$retval .= "\n";
	close FILE;
	return $retval;
}

$mhtmlcomments = 1;

sub cli {
	getopts("clto") || usage();

	if ($opt_c) {$mhtmlcomments = 0;}

	if (@ARGV < 2) { usage(); }

	$file1 = $ARGV[0];
	$file2 = $ARGV[1];
	$file3 = $ARGV[2];

	$tmp = splitit($file1, $headertmp1);
	open (FILE, ">$tmp1");
	print FILE $tmp;
	close FILE;

	$tmp = splitit($file2, $headertmp2);
	open (FILE, ">$tmp2");
	print FILE $tmp;
	close FILE;

	$output = "";

	if ($stripheader) {
		open(FILE, $headertmp2);
		while (<FILE>) {
			$output .= $_;
		}
		close(FILE);
	}

	$output .= markit($tmp1, $tmp2);

	if ($file3) {
		open(FILE, ">$file3");
		print FILE $output;
		close FILE;
	} else {
		print $output;
	}
}

sub cgi {
	use LWP::UserAgent;
	use CGI;

	my $query = new CGI;
	my $url1 = $query->param("oldfile");
    my $oldContent = $query->param("oldcontent") ;
	my $url2 = $query->param("newfile");
    my $newContent = $query->param("newcontent") ;
	my $mhtml = $query->param("mhtml");
    my $base = $query->param("base") ;

	my $file1 = "/tmp/htdcgi1.$$";
	my $file2 = "/tmp/htdcgi2.$$";

	my $ua = new LWP::UserAgent;
	$ua->agent("SiSco, Inc. HTMLdiff/0.9 " . $ua->agent);

    my $contentType = "UTF-8" ;

	# Create a request

    if (defined $url1 && $url1 ne '') {
        my $req1 = new HTTP::Request GET => $url1;

        my $res1 = $ua->request($req1, $file1);
        if ($res1->is_error) {
            print $query->header(-type=>'text/html');
            print $res1->error_as_HTML();
            print "<p>The URL $url1 could not be found.  Please check it and try again.</p>";
            return;
        }
        $contentType = $res1->content_encoding() ;
    } elsif (defined $oldContent) {
        if (open(FILE, ">$file1")) {
            print FILE $oldContent ;
            close FILE;
        }
    } else {
        print $query->header(-type=>'text/html');
        print "<p>There is no olduri and no oldcontent parameter.</p>";
        return ;
    }

    if (defined $url2 && $url2 ne '') {
        my $req2 = new HTTP::Request GET => $url2;

        my $res2 = $ua->request($req2, $file2);
        if ($res2->is_error) {
            print $query->header(-type=>'text/html');
            print $res2->error_as_HTML();
            print "<p>The URL $url2 could not be found.  Please check it and try again.</p>";
            return;
        } else {
            if ($base eq '') {
                $base = $res2->base() ;
            }
            $contentType = $res2->content_encoding() ;
        }
    } elsif (defined $newContent) {
        if (open(FILE, ">$file2")) {
            print FILE $newContent ;
            close FILE;
        }
    } else {
        print $query->header(-type=>'text/html');
        print "<p>There is no newuri and no newcontent parameter.</p>";
        return ;
    }

	$split1 = splitit($file1, $headertmp1);
	open (FILE, ">$tmp1");
	print FILE $split1;
	close FILE;

	$split2 = splitit($file2, $headertmp2);
	open (FILE, ">$tmp2");
	print FILE $split2;
	close FILE;

	$output = "";

	if ($stripheader) {
		open(FILE, $headertmp2);
		while (<FILE>) {
			$output .= $_;
		}
		close(FILE);
	}

	$output .= markit($tmp1, $tmp2);

	if ($base !~ /\/$/) {
		$base =~ s/[^\/]*$//;
	}

	if ( $base ne '' && $output !~ /<base/i ) {
		$output =~ s/<head>/<head>\n<base href="$base">/i ||
	  	$output =~ s/<html>/<html>\n<base href="$base">/i ;
	}

	print $query->header(-type=>"text/html; charset=$contentType") ;
	print $output;

	unlink $file1;
	unlink $file2;

}

use File::Temp ':mktemp';

$tmp1=mktemp("htdtmp1XXXXXX");
$headertmp1=mktemp("htdhtmp1.XXXXXX");
$tmp2=mktemp("htdtmp2.XXXXXX");
$headertmp2=mktemp("htdhtmp2.XXXXXX");
$stripheader = 1;

if (@ARGV == 0) {
	cgi();		# if no arguments, we must be operating as a cgi script
} else {
	cli();		# if there are arguments, then we are operating as a CLI
}

unlink $tmp1;
unlink $headertmp1;
unlink $tmp2;
unlink $headertmp2;
