#!/usr/bin/env perl

use encoding 'utf8';
use strict;
use warnings;

use List::MoreUtils qw(first_index);
use Getopt::Std;

my @chapters = qw(
    Foreword
    NginxVariables
    NginxDirectiveExecOrder
);

my %text2chapter = (
    '缘起' => 'Forword',
    'Nginx 变量漫谈' => 'NginxVariables',
    'Nginx 配置指令的执行顺序' => 'NginxDirectiveExecOrder',
);

my @nums = qw(
   零 一 二 三 四 五 六 七 八 九
   十 十一 十二 十三 十四 十五 十六 十七 十八 十九
   二十
);

my %opts;
getopts('o:', \%opts) or usage();

my $outfile = $opts{o};

my $infile = shift or usage();

my ($cur_chapter, $cur_serial, $cur_order);
if ($infile =~ /\b(\d+)-(\w+?)(?:\d+)?\.wiki$/) {
    $cur_serial = $1;
    $cur_chapter = $2;
    $cur_order = $3;

} else {
    die "Bad input file $infile\n";
}

open my $in, "<:encoding(UTF-8)", $infile
    or die "Cannot open $infile for reading: $!\n";

my $ctx = {};
my $html = '';
while (<$in>) {
    #warn "line $.\n";
    if (/^\s+$/) {
        if ($ctx->{code}) {
            #warn "inserting br in code";
            $html .= "<br/>\n";
        }
        next;
    }

    if (/^\s+/) {
        $html .= fmt_code($_, $ctx);

    } elsif (/^\S/) {

        $html .= fmt_para($_, $ctx);
    }
}

close $in;

$html .= "    </body>\n</html>\n";

if ($outfile) {
    open my $out, ">:encoding(UTF-8)", $outfile
        or die "Cannot open $outfile for writing: $!\n";

    print $out $html;
    close $out;

} else {
    print $html;
}

sub fmt_para {
    my ($s, $ctx) = @_;
    if ($s =~ /^= (.*?) =$/) {
        my $title = $1;
        return <<"_EOC_";
<html>
    <head>
        <title>$title</title>
        <meta http-equiv="content-type" content="text/html; charset=UTF-8">
    </head>
    <body>
    <h3>$title</h3>
_EOC_
    }

    if (/^<geshi/) {
        $ctx->{code} = 1;
        return "<code>";
    }

    if (m{^</geshi>}) {
        $ctx->{code} = 0;
        return "</code>";
    }

    my $res;

    while (1) {
        #my $pos = pos $s;
        #warn "pos: $pos" if defined $pos;
        if ($s =~ /\G (\s*) \[ (http[^\]\s]+) \s+ ([^\]]+) \] /gcx) {
            my ($indent, $url, $label) = ($1, $2, $3);

            if ($label =~ /(.+)系列$/ && $text2chapter{$1}) {
                my $chapter = $text2chapter{$1};
                if (!$chapter) {
                    die "Chapter $1 not found";
                }
                my $serial = first_index { $_ eq $chapter } @chapters;
                if (!$serial) {
                    die "chapter $chapter not found";
                }

                $serial = sprintf("%02d", $serial);
                my $fname = "$serial-${chapter}01.html";
                $res .= qq{$indent<a href="$fname">$label</a>};
            } elsif ($label =~ m/(.*)（([一二三四五六七八九十]+)）/) {
                my $text = $1;
                my $cn_num = $2;
                my $order = sprintf "%02d", first_index { $_ eq $cn_num } @nums;

                my ($chapter, $serial);
                if (!$text) {
                    $chapter = $cur_chapter;
                    $serial = $cur_serial;

                } else {
                    $chapter = $text2chapter{$text};
                    if (!$chapter) {
                        die "chapter $text not found";
                    }

                    $serial = first_index { $_ eq $chapter } @chapters;
                    if (!$serial) {
                        die "chapter $chapter not found";
                    }

                    $serial = sprintf("%02d", $serial);
                }

                $res .= qq{$indent<a href="$serial-$chapter$order.html">$label</a>};

            } else {
                #warn "matched abs link $&\n";
                $label = fmt_html($label);
                $res .= qq{$indent<a href="$url" target="_blank">$label</a>};
            }

        } elsif ($s =~ /\G \s* \[\[ ([^\|\]]+) \| ([^\]]+) \]\]/gcx) {
            my ($url, $label) = ($1, $2);
            #warn "matched rel link $&\n";
            $url =~ s/\$/.24/g;
            $res .= qq{ <a href="http://wiki.nginx.org/$url" target="_blank">$label</a>};

        } elsif ($s =~ /\G [^\[]+ /gcx) {
            #warn "matched text $&\n";
            $res .= $&;

        } elsif ($s =~ /\G ./gcx) {
            #warn "unknown link $&\n";

        } else {
            #warn "breaking";
            last;
        }
    }

    return "<p>$res</p>\n";
}

sub fmt_html {
    my $s = shift;
    $s =~ s/\&/\&amp;/g;
    $s =~ s/"/\&quot;/g;
    $s =~ s/</\&lt;/g;
    $s =~ s/>/\&gt;/g;
    $s =~ s/ /\&nbsp;/g;
    $s;
}

sub fmt_code {
    my $s = shift;
    $s = fmt_html($s);
    $s =~ s{\n}{<br/>\n}sg;
    $s;
}

sub usage {
    die "Usage: $0 [-o <outfile>] <infile>\n";
}

