#!/usr/bin/perl
use strict;
use IO::Socket;
use LWP;
use Bookmark;
use POE qw(Component::IRC Component::IRC::Plugin::WWW::GetPageTitle);
use Config::Tiny;
use Getopt::Long;

die "Error: You must rename urlbot.db.example to urlbot.db\n" if !-e "urlbot.db";
die "Error: You must rename urlbot.conf.example to urlbot.conf\n" if !-e "urlbot.conf";
die "Usage: $0 ircserver channels\,separated\,by\,commas\n" if !$ARGV[0] && !$ARGV[1];

my $debug;
GetOptions ('debug' => \$debug);

my $conf = Config::Tiny->read( 'urlbot.conf' );
my $botnick = $conf->{bot}->{nickname};
my $nickpass = $conf->{bot}->{password};
my $server = $ARGV[0];
sub CHANNEL () { $ARGV[1]; }
my %flood;

our ($irc) = POE::Component::IRC->spawn();

POE::Session->create(
     inline_states => {
          _start              => \&bot_start,
          connect             => \&bot_connect,
          irc_001             => \&on_connect,
          irc_433             => \&err_nickinuse,
          irc_471             => \&err_chan,
          irc_473             => \&err_chan,
          irc_474             => \&err_chan,
          irc_475             => \&err_chan,
          irc_public          => \&on_public,
          irc_ctcp_version    => \&on_version,
          irc_ctcp_time       => \&on_time,
          irc_msg             => \&on_privmsg,
          irc_notice          => \&on_notice,
          irc_error           => \&bot_reconnect,
          irc_socketerr       => \&bot_reconnect,
          irc_ctcp_action     => \&on_action,
          irc_page_title      => \&irc_page_title,
          irc_kick            => \&on_kick,
     },
);

sub bot_start {
     my $kernel  = $_[KERNEL];
     my $heap    = $_[HEAP];
     my $session = $_[SESSION];

     $irc->yield( register => "all" );
     $irc->plugin_add('get_page_title' =>
                       POE::Component::IRC::Plugin::WWW::GetPageTitle->new(
                         response_event   => 'irc_page_title',
                         auto => 0,
                         max_uris  => 2,
                         find_uris => 1,
                         addressed => 0,
                         listen_for_input => [ qw(public) ],
                         eat => 0,
                         trigger   => qr/^/,
                       ),
                   );

     $kernel->yield("connect");
}
sub bot_connect {
     my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
     $irc->yield(connect =>
           { Nick => 'URLBot',
            Username => 'URLBot',
            Ircname  => 'URLBot by MusashiX90',
            Server   => $server,
            Port     => '6667',
            Flood    => '1',
          }
     );
}
sub on_connect {
     $irc->yield( join => CHANNEL );
     $irc->yield( mode => $botnick => '+B' );
}

sub daemonize() {
     close STDIN;
     close STDOUT;
     close STDERR;
     open(STDIN, '>', '/dev/null');
     open(STDOUT, '>', '/dev/null');
     open(STDERR,  '>', '/dev/null');
     if(fork()) { exit(0) }
}

daemonize() if !defined($debug);
$poe_kernel->run();
exit 0;

sub on_public {
     my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
     my $nick = ( split /!/, $who )[0];
     my $channel = $where->[0];

     my $ts = scalar localtime;
     print " [$ts] <$nick:$channel> $msg\n" if defined($debug);
     my @args = split(/ /,$msg,4) if length($msg) > 0;
     if ($msg =~ /$botnick\: ping\?/i) {
          $irc->yield(privmsg => $channel => "$nick: Pong!");
     }
}
sub on_privmsg {
     my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
     my $nick = ( split /!/, $who )[0];
     my $target = $where->[0];

     my @split = split(/\s/,$msg);
     if ($split[0] =~ /^(bookmark|bm)$/i) {
          if ($split[1] =~ /^create$/i) {
               Bookmark::create($irc,$nick);
          }
          elsif ($split[1] =~ /^add/i and @split eq 4) {
               Bookmark::add($irc,$nick,$split[2],$split[3]);
          }
          elsif ($split[1] =~ /^search/i and @split eq 3) {
               Bookmark::grab_item($irc,$nick,$split[2]);
          }
          elsif ($split[1] =~ /^share/i and @split eq 4) {
               Bookmark::share_item($irc,$nick,$split[2],$split[3]);
          }
     }
     elsif ($split[0] =~ /^help$/i) {
          if ($split[1] =~ /^bookmark$/i) {
               if (@split eq 2) {
                    $irc->yield(notice => $nick => "Commands:");
                    $irc->yield(notice => $nick => "  CREATE    Starts the bookmarking system");
                    $irc->yield(notice => $nick => "  ADD       Adds a bookmark");
                    $irc->yield(notice => $nick => "  SEARCH    Searches through bookmarks");
               } elsif ($split[2] =~ /^create$/) {
                    $irc->yield(notice => $nick => "Creates the database used for bookmarks");
               } elsif ($split[2] =~ /^add$/i) {
                    $irc->yield(notice => $nick => "Adds a bookmark");
                    $irc->yield(notice => $nick => "Syntax: BOOKMARK ADD <title> <URL>");
               } elsif ($split[2] =~ /^search$/i) {
                    $irc->yield(notice => $nick => "Searchs for bookmarks by title (wildcards can be used)");
                    $irc->yield(notice => $nick => "Syntax: BOOKMARK SEARCH <title>");
               }
          } elsif ($split[1] =~ /^xrl$/i) {
               $irc->yield(notice => $nick => "Shortens URLs with the XRL.US website");
               $irc->yield(notice => $nick => "Syntax: XRL <url>");
          } else {
               $irc->yield(notice => $nick => "Commands:");
               $irc->yield(notice => $nick => "  BOOKMARK    Bookmarking system");
               $irc->yield(notice => $nick => "  XRL         Shortens URLs");
          }
     }
     elsif ($split[0] =~ /^xrl$/i and @split eq 2) {
          $irc->yield(notice => $nick => xrl($split[1]));
     }
}
sub on_notice {
     my ( $kernel, $who, $where, $msg ) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
     my $nick = ( split /!/, $who )[0];
     my $target = $where->[0];
     if ($msg =~ /nick(.+)type(.+)\/msg NickServ IDENTIFY(.+)password(.+) Otherwise/i && $nick =~ /NickServ/i) {
          $irc->yield(privmsg => "NickServ" => "identify $nickpass");
     }
     print "$nick -> $msg\n" if defined($debug);
}
sub irc_banned {
     my $rejointime = time()+30;
     while ($rejointime ne 0) {
          if ($rejointime eq time() || $rejointime lt time()) {
               $rejointime = 0;
               ircsend("JOIN $_[0]");
          }
     }
}
sub xrl {
     my $url = "http://metamark.net/api/rest/simple?long_url=";
     if ($_[0] =~ /http\:\/\//) { 
          $url .= $_[0]; 
     } else { 
          $url .= "http://".$_[0]; 
     }
     my $browser = LWP::UserAgent->new;
     my $response = $browser->get($url);
     return "Can't get $url --".$response->status_line unless $response->is_success;
     my $newurl = $response->content;
     return "$newurl";
}
sub on_version {
     my ($kernel,$who,$where,$msg) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
     my $nick = (split /!/,$who)[0];
     my $target = $where->[0];
     my $ts = scalar localtime;

     print " [$ts] -- CTCP VERSION request from $nick.\n" if defined($debug);
     $irc->yield(ctcpreply => $nick => 'VERSION URLBot 0.4-poe by MusashiX90');
}
sub on_time {
     my ($kernel,$who,$where,$msg) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
     my $nick = (split /!/,$who)[0];
     my $target = $where->[0];
     my $ts = scalar localtime;
     print " [$ts] -- CTCP TIME request from $nick.\n" if defined($debug);
     $irc->yield(ctcpreply => $nick => 'TIME '.scalar localtime);
}
sub bot_reconnect {
    my $kernel = $_[KERNEL];
    $kernel->delay( connect => 60);
}
sub on_action {
     my ($kernel,$who,$where,$msg) = @_[ KERNEL, ARG0, ARG1, ARG2 ];
     my $nick = (split /!/,$who)[0];
     my $channel = $where->[0];
}
sub err_nickinuse {
     my $kernel = KERNEL;
     print "Error: Nickname is already in use.\n" if defined($debug);
     $botnick .= "_" if $botnick !~ /_$/;
     $irc->yield(nick => $botnick);
     $irc->delay( [ nick => "URLBot" ], 60);
}
sub err_chan {
     my $kernel = KERNEL;
     $irc->delay( [ join => CHANNEL ], 120);
}
sub irc_page_title {
     my $target = $_[ARG0]{channel};
     my $title = $_[ARG0]{title};
     my $who = $_[ARG0]{who};
     $flood{$target} = 0 if !defined($flood{$target});
     $flood{$who} = 0 if !defined($flood{$who});
     print "Found: $target -  $title\n" if defined($debug);
     if (time - $flood{$target} >= 3 && time - $flood{$who} >= 5) {
          if (time - $flood{$target} >= 5 && $title !~ /DCC SEND/ && $title !~ /(start|stop)keylogger/ && $title !~ /irc\.(.+)\.(.+)/ && $title !~ /^\[[a-z].+\]\s$/) {
               $irc->yield(privmsg => $target => $title);
          }
          $flood{$target} = time();
          $flood{$who} = time();
      }
}
sub on_kick {
     my $channel = $_[ARG1];
     my $victim = $_[ARG2];
     if ($victim eq $botnick) {
          $irc->delay( [ join => $channel ], 120);
     }
}
