#Bookmarking system
package Bookmark;

use DBI; 
use strict; 

my $prefix = main::PREFIX();

my $db = DBI->connect("dbi:SQLite:".$prefix."/urlbot.db","","", {RaiseError => 1, AutoCommit => 1});

sub add($$$$) {
	my ($irc,$nick,$title,$url) = @_;
	$title = $db->quote($title);
	$url = $db->quote($url);
	my $table = "bm_".$nick;
	if (!table_exists($table)) {
		$irc->yield(notice => $nick => "You have not created a database yet.  Please type /MSG URLbot BOOKMARK CREATE");
	} else {
		$db->do("INSERT INTO $table VALUES ($title, $url)");
                $irc->yield(notice => $nick => "Added $url as \"$title\"");
	}
}

sub create {
	my ($irc,$nick) = @_;
	my $table = "bm_".$nick;
	if (!table_exists($table)) {
		$db->do("CREATE TABLE ".$table." (title TEXT, url TEXT)");
		$irc->yield(notice => $nick => "You have now created a bookmark database");
		$irc->yield(notice => $nick => "Type /MSG URLbot HELP for more information");
	}
	else {
		$irc->yield(notice => $nick => "You already have a database created");
	}
}

sub table_exists {
        my @row = $db->selectrow_array("SELECT name FROM sqlite_master WHERE type='table' AND name='$_[0]'");
        return (@row > 0);
}
sub item_exists($$$) {
	my ($nick,$title) = @_;
	my $table = "bm_".$nick;
	my $row = $db->selectrow_array("SELECT $title FROM $table");
	return @$row;
}
sub share_item($$$$) {
	my ($irc,$nick,$title,$target) = @_;
	my $table = "bm_".$nick;
        if (!table_exists($table)) {
                $irc->yield(notice => $nick => "You have not created a database yet.  Please type /MSG URLbot BOOKMARK CREATE");
        } else {
                $title = $db->quote($title);
                my @results = $db->selectrow_array("SELECT * FROM $table WHERE title = $title");
		if ($#results gt -1) {
			$irc->yield(privmsg => $target => "$nick wanted to share $title with you.  It is located at $results[1]");
		}
	}
}	
sub grab_item($$$) {
	my ($irc,$nick,$title) = @_;
        my $table = "bm_".$nick;
        if (!table_exists($table)) {
                $irc->yield(notice => $nick => "You have not created a database yet.  Please type /MSG URLbot BOOKMARK CREATE");
        } else {
		$irc->yield(notice => $nick => "Bookmarks matching \003$title\003");
		$irc->yield(notice => $nick => "----------------------------------");
		$title =~ s/\*/\%/g;
	       	$title = $db->quote($title);
       		my $results = $db->selectall_arrayref("SELECT * FROM $table WHERE title LIKE $title LIMIT 15");
		if (@$results gt 0) {
			foreach my $row (@$results) {
				my ($title,$url) = @$row;
				$irc->yield(notice => $nick => "$title     ($url)");
			}
		}
		else {
			$irc->yield(notice => $nick => "Sorry, nothing was found.");
		}
		$irc->yield(notice => $nick => "----------------------------------");
	}
}
return 1;
